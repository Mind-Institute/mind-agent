import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Limpeza do HubSpot aprovada pela Adriana (24/09/2026, docs/HUBSPOT_LIMPEZA_APROVACAO.md itens 1–9).
// A rotina não recebe operações de fora: executa um LOTE gravado no banco em public.mind_admin_audit
// (resource 'hubspot_limpeza_lote', record_id = nome do lote, after_data = {ops: [...]}), uma única vez.
// Antes de mudar qualquer objeto, guarda a cópia do que havia lá (resource 'hubspot_snapshot'), e no fim
// grava o resultado (resource 'hubspot_limpeza_resultado').
//
// Operações:
//   atualizar    {objeto, itens: [{id, props}]}
//   arquivar     {objeto, ids}                          (arquivar no HubSpot é reversível por 90 dias)
//   criar        {objeto, itens: [{ref, props}]}
//   desassociar  {de, para, pares: [{de, para}]}
//   associar     {de, para, pares: [{de, para}]}
//   limpar_company {company, contatos}                  tira a associação desses contatos e dos negócios
//                                                       que só chegaram à company por eles
//   fundir       {pares: [{principal, outro}]}          merge de contatos

const HUBSPOT = "https://api.hubapi.com";

type Op = Record<string, unknown> & { tipo: string };

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

const pausa = (ms: number) => new Promise((r) => setTimeout(r, ms));

Deno.serve(async (req: Request) => {
  const token = Deno.env.get("HUBSPOT_TOKEN");
  const url = Deno.env.get("SUPABASE_URL");
  const chave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!token) return json(500, { ok: false, erro: "HUBSPOT_TOKEN ausente nos secrets" });
  if (!url || !chave) return json(500, { ok: false, erro: "ambiente do supabase incompleto" });
  const db = createClient(url, chave, { auth: { persistSession: false } });

  const pedido: { lote?: string } = req.method === "POST" ? await req.json().catch(() => ({})) : {};
  const lote = String(pedido.lote ?? "");
  if (!lote) return json(400, { ok: false, erro: "informe o lote" });

  const { data: feito } = await db.from("mind_admin_audit").select("id")
    .eq("resource", "hubspot_limpeza_resultado").eq("record_id", lote).limit(1);
  if (feito && feito.length > 0) return json(409, { ok: false, erro: "lote já executado" });
  const { data: linhas, error } = await db.from("mind_admin_audit").select("after_data")
    .eq("resource", "hubspot_limpeza_lote").eq("record_id", lote).order("occurred_at", { ascending: false }).limit(1);
  if (error) return json(500, { ok: false, erro: error.message });
  const ops = ((linhas?.[0]?.after_data as { ops?: Op[] })?.ops ?? []);
  if (ops.length === 0) return json(404, { ok: false, erro: "lote não encontrado ou vazio" });

  const api = async (metodo: string, caminho: string, body?: unknown) => {
    for (let tentativa = 0; tentativa < 4; tentativa++) {
      const res = await fetch(`${HUBSPOT}${caminho}`, {
        method: metodo,
        headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(30_000),
      });
      const texto = await res.text();
      if (res.status === 429) { await pausa(1500 * (tentativa + 1)); continue; }
      let dados: unknown = null;
      try { dados = texto ? JSON.parse(texto) : null; } catch { dados = texto; }
      return { status: res.status, ok: res.status >= 200 && res.status < 300, dados: dados as Record<string, unknown> };
    }
    return { status: 429, ok: false, dados: { erro: "limite de requisições" } as Record<string, unknown> };
  };

  const copia = async (objeto: string, rotulo: string, dados: unknown) => {
    await db.from("mind_admin_audit").insert({
      action: "atualizar", resource: "hubspot_snapshot", record_id: lote,
      record_label: `${rotulo} (${objeto}) — cópia antes da mudança`, before_data: dados, request_id: crypto.randomUUID(),
    });
  };

  let todasPropsContato: string[] | null = null;
  const propsContato = async () => {
    if (todasPropsContato) return todasPropsContato;
    const r = await api("GET", "/crm/v3/properties/contacts");
    todasPropsContato = ((r.dados?.results as Array<{ name: string }>) ?? []).map((p) => p.name);
    return todasPropsContato;
  };

  const ler = async (objeto: string, ids: string[], props: string[]) => {
    const saida: unknown[] = [];
    for (let i = 0; i < ids.length; i += 100) {
      const r = await api("POST", `/crm/v3/objects/${objeto}/batch/read`,
        { properties: props, inputs: ids.slice(i, i + 100).map((id) => ({ id })) });
      saida.push(...((r.dados?.results as unknown[]) ?? []));
    }
    return saida;
  };

  const associacoes = async (de: string, para: string, ids: string[]) => {
    const mapa = new Map<string, string[]>();
    for (let i = 0; i < ids.length; i += 100) {
      const r = await api("POST", `/crm/v4/associations/${de}/${para}/batch/read`,
        { inputs: ids.slice(i, i + 100).map((id) => ({ id })) });
      for (const x of ((r.dados?.results as Array<{ from: { id: string }; to: Array<{ toObjectId: number }> }>) ?? [])) {
        mapa.set(String(x.from.id), x.to.map((t) => String(t.toObjectId)));
      }
    }
    return mapa;
  };

  const resultado: Array<Record<string, unknown>> = [];

  for (const op of ops) {
    const r: Record<string, unknown> = { tipo: op.tipo, rotulo: op.rotulo ?? null };
    try {
      if (op.tipo === "atualizar") {
        const objeto = String(op.objeto);
        const itens = op.itens as Array<{ id: string; props: Record<string, string> }>;
        const chaves = [...new Set(itens.flatMap((i) => Object.keys(i.props)))];
        await copia(objeto, String(op.rotulo ?? "atualizar"), await ler(objeto, itens.map((i) => i.id), chaves));
        let ok = 0; const erros: unknown[] = [];
        for (let i = 0; i < itens.length; i += 100) {
          const lote = itens.slice(i, i + 100);
          const x = await api("POST", `/crm/v3/objects/${objeto}/batch/update`,
            { inputs: lote.map((it) => ({ id: it.id, properties: it.props })) });
          if (x.ok) ok += ((x.dados?.results as unknown[]) ?? []).length;
          if (!x.ok || x.status === 207) erros.push({ status: x.status, dados: x.dados });
          if (!x.ok && lote.length > 1) {
            // um item ruim derruba o lote inteiro: refaz um a um
            for (const it of lote) {
              const y = await api("PATCH", `/crm/v3/objects/${objeto}/${it.id}`, { properties: it.props });
              if (y.ok) ok++; else erros.push({ id: it.id, status: y.status, dados: y.dados });
            }
          }
        }
        Object.assign(r, { ok, erros: erros.slice(0, 30) });
      } else if (op.tipo === "arquivar") {
        const objeto = String(op.objeto);
        const ids = (op.ids as string[]).map(String);
        const props = objeto === "contacts"
          ? ["email", "firstname", "lastname", "phone", "company", "jobtitle", "hs_additional_emails"]
          : ["name", "domain", "website", "industry"];
        await copia(objeto, String(op.rotulo ?? "arquivar"), await ler(objeto, ids, props));
        const x = await api("POST", `/crm/v3/objects/${objeto}/batch/archive`, { inputs: ids.map((id) => ({ id })) });
        Object.assign(r, { status: x.status, arquivados: x.ok ? ids.length : 0, erro: x.ok ? null : x.dados });
      } else if (op.tipo === "criar") {
        const objeto = String(op.objeto);
        const todos = op.itens as Array<{ ref: string; props: Record<string, string> }>;
        const criados: Array<{ ref: string; id: string }> = []; const erros: unknown[] = [];
        // quem já existe no HubSpot (pelo e-mail, primário ou secundário) não é criado de novo
        const existentes: Array<{ ref: string; id: string }> = [];
        const porEmail = new Map(todos.filter((t) => t.props.email).map((t) => [t.props.email.toLowerCase(), t.ref]));
        const emails = [...porEmail.keys()];
        for (let i = 0; i < emails.length; i += 100) {
          const x = await api("POST", `/crm/v3/objects/${objeto}/batch/read`,
            { idProperty: "email", properties: ["email"], inputs: emails.slice(i, i + 100).map((id) => ({ id })) });
          for (const c of ((x.dados?.results as Array<{ id: string; properties: { email?: string } }>) ?? [])) {
            const ref = porEmail.get(String(c.properties?.email ?? "").toLowerCase());
            if (ref) existentes.push({ ref, id: String(c.id) });
          }
        }
        const jaExiste = new Set(existentes.map((e) => e.ref));
        const itens = todos.filter((t) => !jaExiste.has(t.ref));
        for (let i = 0; i < itens.length; i += 100) {
          const lote = itens.slice(i, i + 100);
          const x = await api("POST", `/crm/v3/objects/${objeto}/batch/create`,
            { inputs: lote.map((it) => ({ properties: it.props, objectWriteTraceId: it.ref })) });
          for (const c of ((x.dados?.results as Array<{ id: string; objectWriteTraceId?: string }>) ?? [])) {
            criados.push({ ref: String(c.objectWriteTraceId), id: String(c.id) });
          }
          const n = ((x.dados?.results as unknown[]) ?? []).length;
          if (x.ok && n < lote.length) erros.push({ status: x.status, dados: x.dados?.errors ?? x.dados });
          if (!x.ok) {
            // e-mail que já existe derruba o lote: refaz um a um
            for (const it of lote) {
              const y = await api("POST", `/crm/v3/objects/${objeto}`, { properties: it.props });
              if (y.ok) criados.push({ ref: it.ref, id: String(y.dados?.id) });
              else erros.push({ ref: it.ref, status: y.status, dados: y.dados });
            }
          }
        }
        Object.assign(r, { criados, existentes, erros: erros.slice(0, 50) });
      } else if (op.tipo === "desassociar" || op.tipo === "associar") {
        const de = String(op.de), para = String(op.para);
        const pares = op.pares as Array<{ de: string; para: string }>;
        const caminho = op.tipo === "desassociar" ? "batch/archive" : "batch/associate/default";
        let ok = 0; const erros: unknown[] = [];
        for (let i = 0; i < pares.length; i += 100) {
          const lote = pares.slice(i, i + 100);
          const corpo = op.tipo === "desassociar"
            ? { inputs: lote.map((p) => ({ from: { id: String(p.de) }, to: [{ id: String(p.para) }] })) }
            : { inputs: lote.map((p) => ({ from: { id: String(p.de) }, to: { id: String(p.para) } })) };
          const x = await api("POST", `/crm/v4/associations/${de}/${para}/${caminho}`, corpo);
          if (x.ok) ok += lote.length; else erros.push({ status: x.status, dados: x.dados });
        }
        Object.assign(r, { ok, erros });
      } else if (op.tipo === "limpar_company") {
        const company = String(op.company);
        const contatos = new Set((op.contatos as string[]).map(String));
        const negocios = (await associacoes("companies", "deals", [company])).get(company) ?? [];
        const contatosDoNegocio = await associacoes("deals", "contacts", negocios);
        const negociosSoDeles = negocios.filter((d) => {
          const cs = contatosDoNegocio.get(d) ?? [];
          return cs.length > 0 && cs.every((c) => contatos.has(c));
        });
        await copia("companies", `limpar_company ${company}`, {
          company, contatos: [...contatos], negocios, negocios_desassociados: negociosSoDeles,
          contatos_dos_negocios: Object.fromEntries(contatosDoNegocio),
        });
        const a = await api("POST", "/crm/v4/associations/companies/contacts/batch/archive",
          { inputs: [{ from: { id: company }, to: [...contatos].map((id) => ({ id })) }] });
        const b = negociosSoDeles.length === 0 ? { ok: true, status: 204 } : await api("POST",
          "/crm/v4/associations/companies/deals/batch/archive",
          { inputs: [{ from: { id: company }, to: negociosSoDeles.map((id) => ({ id })) }] });
        Object.assign(r, {
          company, contatos: contatos.size, negocios: negocios.length, negocios_desassociados: negociosSoDeles.length,
          status_contatos: a.status, status_negocios: b.status,
        });
      } else if (op.tipo === "fundir") {
        const pares = op.pares as Array<{ principal: string; outro: string }>;
        const props = await propsContato();
        const ids = [...new Set(pares.flatMap((p) => [String(p.principal), String(p.outro)]))];
        const antes: unknown[] = [];
        for (let i = 0; i < props.length; i += 250) antes.push(...await ler("contacts", ids, props.slice(i, i + 250)));
        await copia("contacts", String(op.rotulo ?? "fundir"), { pares, contatos: antes });
        const feitos: unknown[] = []; const erros: unknown[] = [];
        // o merge gera um id novo para o contato resultante: quem já foi fundido passa a ser o id novo
        const atual = new Map<string, string>();
        const seguir = (id: string) => { let v = id; for (let k = 0; k < 10 && atual.has(v); k++) v = atual.get(v)!; return v; };
        for (const p of pares) {
          let principal = seguir(String(p.principal));
          const outro = seguir(String(p.outro));
          if (principal === outro) { feitos.push({ ...p, ja_era_o_mesmo: true }); continue; }
          let x = await api("POST", "/crm/v3/objects/contacts/merge", { primaryObjectId: principal, objectIdToMerge: outro });
          for (let t = 0; t < 2 && !x.ok; t++) {
            // "forward reference to N": o contato já foi fundido antes (neste ou noutro lote); usa o id vivo
            const m = String((x.dados as { message?: string })?.message ?? "").match(/objectId=(\d+)} because it has a forward reference to (\d+)/);
            if (!m || m[1] === m[2]) break;
            atual.set(m[1], m[2]);
            principal = seguir(principal);
            const o2 = seguir(outro);
            if (principal === o2) break;
            x = await api("POST", "/crm/v3/objects/contacts/merge", { primaryObjectId: principal, objectIdToMerge: o2 });
          }
          if (x.ok) {
            const novo = String(x.dados?.id ?? principal);
            if (novo !== principal) atual.set(principal, novo);
            if (novo !== outro) atual.set(outro, novo);
            feitos.push({ ...p, principal_usado: principal, novo_id: novo });
          } else erros.push({ ...p, status: x.status, dados: x.dados });
          await pausa(120);
        }
        Object.assign(r, { fundidos: feitos.length, feitos, erros });
      } else if (op.tipo === "acrescentar") {
        // Marca propriedades de múltipla escolha SOMANDO ao que já existe (nunca apaga valor). Cada item traz
        // todos os ids conhecidos da pessoa; o contato vivo é achado por hs_all_contact_vids (ids fundidos).
        // Propriedades em op.se_vazio só são gravadas se estiverem vazias.
        const objeto = "contacts";
        const itens = op.itens as Array<{ ids: string[]; props: Record<string, string> }>;
        const seVazio = new Set((op.se_vazio as string[] | undefined) ?? []);
        const chaves = [...new Set(itens.flatMap((i) => Object.keys(i.props)))];
        const ids = [...new Set(itens.flatMap((i) => i.ids.map(String)))];
        const vivos = await ler(objeto, ids, [...chaves, "hs_all_contact_vids"]) as Array<{ id: string; properties: Record<string, string | null> }>;
        const porVid = new Map<string, { id: string; properties: Record<string, string | null> }>();
        for (const c of vivos) {
          porVid.set(String(c.id), c);
          for (const v of String(c.properties?.hs_all_contact_vids ?? "").split(";")) if (v) porVid.set(v.trim(), c);
        }
        const alvo = new Map<string, { atual: Record<string, string | null>; novo: Record<string, Set<string>> }>();
        let semContato = 0;
        for (const it of itens) {
          const c = it.ids.map((i) => porVid.get(String(i))).find(Boolean);
          if (!c) { semContato++; continue; }
          const a = alvo.get(c.id) ?? { atual: c.properties, novo: {} };
          for (const [k, v] of Object.entries(it.props)) {
            const s = a.novo[k] ?? new Set<string>();
            for (const x of String(v).split(";")) if (x) s.add(x);
            a.novo[k] = s;
          }
          alvo.set(c.id, a);
        }
        const updates: Array<{ id: string; props: Record<string, string> }> = [];
        for (const [id, a] of alvo) {
          const props: Record<string, string> = {};
          for (const [k, s] of Object.entries(a.novo)) {
            const antes = String(a.atual?.[k] ?? "").split(";").filter(Boolean);
            if (seVazio.has(k)) { if (antes.length === 0) props[k] = [...s][0]; continue; }
            const uniao = [...new Set([...antes, ...s])];
            if (uniao.length !== antes.length) props[k] = uniao.join(";");
          }
          if (Object.keys(props).length) updates.push({ id, props });
        }
        await copia(objeto, String(op.rotulo ?? "acrescentar"),
          updates.map((u) => ({ id: u.id, antes: Object.fromEntries(Object.keys(u.props).map((k) => [k, alvo.get(u.id)?.atual?.[k] ?? null])) })));
        let ok = 0; const erros: unknown[] = [];
        for (let i = 0; i < updates.length; i += 100) {
          const lote = updates.slice(i, i + 100);
          const x = await api("POST", `/crm/v3/objects/${objeto}/batch/update`,
            { inputs: lote.map((u) => ({ id: u.id, properties: u.props })) });
          if (x.ok) ok += ((x.dados?.results as unknown[]) ?? []).length;
          else erros.push({ status: x.status, dados: x.dados });
        }
        Object.assign(r, { itens: itens.length, contatos: alvo.size, atualizados: ok, sem_mudanca: alvo.size - updates.length, sem_contato: semContato, erros: erros.slice(0, 20) });
      } else {
        r.erro = "tipo desconhecido";
      }
    } catch (e) {
      r.erro = String(e);
    }
    resultado.push(r);
  }

  await db.from("mind_admin_audit").insert({
    action: "atualizar", resource: "hubspot_limpeza_resultado", record_id: lote,
    record_label: "resultado da limpeza do HubSpot", after_data: { resultado }, request_id: crypto.randomUUID(),
  });
  return json(200, { ok: true, lote, resultado });
});
