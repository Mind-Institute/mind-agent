import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Write-back de pessoas.empresas para o HubSpot (aprovação da Adriana, 24/09/2026).
// O plano vem do banco (pessoas.empresas_hubspot_plano): 'criar' (empresa nova com domínio que combina
// com o nome, ou porte confirmado), 'atualizar' (só preenche campo VAZIO no HubSpot). 'revisar*' nunca grava.
// Ensaio por padrão: POST {} devolve o plano; POST {"executar": true} grava.
// Depois de criar, associa à company os contatos das pessoas ligadas a ela que não têm company no HubSpot.

const HUBSPOT = "https://api.hubapi.com";
const LOTE = 50;

type Item = { id: string; acao: string; hubspot_company_id: string | null; props: Record<string, string> };
type Resultado = { id: string; acao: string; ok: boolean; hubspot_company_id?: string | null; erro?: string };

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

async function hubspot(caminho: string, token: string, body: unknown) {
  const res = await fetch(`${HUBSPOT}${caminho}`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(30_000),
  });
  const texto = await res.text();
  let dados: unknown = null;
  try { dados = JSON.parse(texto); } catch { dados = texto; }
  return { status: res.status, dados: dados as Record<string, unknown> };
}

Deno.serve(async (req: Request) => {
  const token = Deno.env.get("HUBSPOT_TOKEN");
  const url = Deno.env.get("SUPABASE_URL");
  const chave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!token) return json(500, { ok: false, erro: "HUBSPOT_TOKEN ausente nos secrets" });
  if (!url || !chave) return json(500, { ok: false, erro: "ambiente do supabase incompleto" });
  const db = createClient(url, chave, { auth: { persistSession: false } });

  let pedido: { executar?: boolean; associar?: boolean } = {};
  if (req.method === "POST") pedido = await req.json().catch(() => ({}));

  // Modo associar (24/09/2026): contato sem company no HubSpot ganha a company que já existe lá para a
  // sua empresa em pessoas.pessoas. Só aditivo; o plano (pessoas.empresas_hubspot_associar_pares) não
  // traz contato já associado a outra company.
  if (pedido.associar) {
    const { data: pares, error } = await db.rpc("mind_empresas_hubspot_associar_pares", {});
    if (error) return json(500, { ok: false, erro: `pares: ${error.message}` });
    const lista = ((pares as Array<{ mind_id: string; contato: string; company: string }>) ?? []);
    if (!pedido.executar) return json(200, { ok: true, ensaio: true, associar: lista.length });
    const feitos: typeof lista = [];
    const erros: string[] = [];
    for (let i = 0; i < lista.length; i += 100) {
      const lote = lista.slice(i, i + 100);
      const r = await hubspot("/crm/v4/associations/contacts/companies/batch/associate/default", token, {
        inputs: lote.map((p) => ({ from: { id: String(p.contato) }, to: { id: String(p.company) } })),
      });
      if (r.status >= 200 && r.status < 300) feitos.push(...lote);
      else erros.push(`HTTP ${r.status}: ${JSON.stringify(r.dados).slice(0, 300)}`);
    }
    const { data: reg, error: erroReg } = await db.rpc("mind_empresas_hubspot_associar_registrar", { p_pares: feitos });
    return json(200, { ok: true, associados: feitos.length, erros, registro: erroReg ? { erro: erroReg.message } : reg });
  }

  const { data: plano, error: erroPlano } = await db.rpc("mind_empresas_hubspot_plano", {});
  if (erroPlano) return json(500, { ok: false, erro: `plano: ${erroPlano.message}` });
  const itens = ((plano as { itens?: Item[] })?.itens ?? []);
  const criar = itens.filter((i) => i.acao === "criar");
  const atualizar = itens.filter((i) => i.acao === "atualizar" && i.hubspot_company_id);

  if (!pedido.executar) {
    return json(200, { ok: true, ensaio: true, resumo: (plano as { resumo?: unknown })?.resumo, criar: criar.length, atualizar: atualizar.length });
  }

  const resultados: Resultado[] = [];

  // 1. criar companies (objectWriteTraceId = id em pessoas.empresas, para casar a resposta)
  for (let i = 0; i < criar.length; i += LOTE) {
    const lote = criar.slice(i, i + LOTE);
    const r = await hubspot("/crm/v3/objects/companies/batch/create", token, {
      inputs: lote.map((it) => ({ properties: it.props, objectWriteTraceId: it.id })),
    });
    const criados = new Map<string, string>();
    for (const c of ((r.dados?.results as Array<{ id: string; objectWriteTraceId?: string }>) ?? [])) {
      if (c.objectWriteTraceId) criados.set(c.objectWriteTraceId, String(c.id));
    }
    for (const it of lote) {
      const hid = criados.get(it.id);
      resultados.push(hid
        ? { id: it.id, acao: "criar", ok: true, hubspot_company_id: hid }
        : { id: it.id, acao: "criar", ok: false, erro: `HTTP ${r.status}: ${JSON.stringify(r.dados).slice(0, 300)}` });
    }
  }

  // 2. atualizar companies existentes (só campos vazios lá — o plano já filtrou)
  for (let i = 0; i < atualizar.length; i += LOTE) {
    const lote = atualizar.slice(i, i + LOTE);
    const r = await hubspot("/crm/v3/objects/companies/batch/update", token, {
      inputs: lote.map((it) => ({ id: it.hubspot_company_id, properties: it.props })),
    });
    const ok = new Set(((r.dados?.results as Array<{ id: string }>) ?? []).map((c) => String(c.id)));
    for (const it of lote) {
      resultados.push(ok.has(String(it.hubspot_company_id))
        ? { id: it.id, acao: "atualizar", ok: true, hubspot_company_id: it.hubspot_company_id }
        : { id: it.id, acao: "atualizar", ok: false, erro: `HTTP ${r.status}: ${JSON.stringify(r.dados).slice(0, 300)}` });
    }
  }

  // 3. associar contatos às companies criadas
  const criadas = resultados.filter((r) => r.acao === "criar" && r.ok);
  let associados = 0;
  const errosAssoc: string[] = [];
  if (criadas.length > 0) {
    const { data: contatos, error } = await db.rpc("mind_empresas_hubspot_contatos",
      { p_empresa_ids: criadas.map((c) => c.id) });
    if (error) errosAssoc.push(`contatos: ${error.message}`);
    const porEmpresa = new Map(criadas.map((c) => [c.id, c.hubspot_company_id as string]));
    const pares = ((contatos as Array<{ empresa_id: string; contato: string }>) ?? [])
      .filter((p) => porEmpresa.has(p.empresa_id))
      .map((p) => ({ from: { id: String(p.contato) }, to: { id: porEmpresa.get(p.empresa_id) } }));
    for (let i = 0; i < pares.length; i += 100) {
      const r = await hubspot("/crm/v4/associations/contacts/companies/batch/associate/default", token, { inputs: pares.slice(i, i + 100) });
      if (r.status >= 200 && r.status < 300) associados += pares.slice(i, i + 100).length;
      else errosAssoc.push(`HTTP ${r.status}: ${JSON.stringify(r.dados).slice(0, 300)}`);
    }
  }

  const { data: reg, error: erroReg } = await db.rpc("mind_empresas_hubspot_registrar",
    { p_resultados: resultados });

  return json(200, {
    ok: true,
    criadas: criadas.length,
    atualizadas: resultados.filter((r) => r.acao === "atualizar" && r.ok).length,
    falhas: resultados.filter((r) => !r.ok).length,
    exemplos_falha: resultados.filter((r) => !r.ok).slice(0, 5),
    contatos_associados: associados,
    erros_associacao: errosAssoc,
    registro: erroReg ? { erro: erroReg.message } : reg,
  });
});
