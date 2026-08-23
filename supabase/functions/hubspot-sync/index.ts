// Espelho do HubSpot: contatos e negócios, incremental, com marca d'água.
//
// Por que aqui e não no chat: são 11.556 contatos e ~9.800 negócios. Isso não
// cabe numa conversa, e uma carga diária não pode depender de alguém estar com
// a janela aberta.
//
// A função NÃO sabe quais colunas existem no espelho. Ela manda o registro
// inteiro do HubSpot e `mind_espelho_gravar` decide o que vira coluna tipada e
// o que fica em `propriedades`. É isso que faz coluna nova ser preenchida sem
// deploy — a razão de o espelho ser jsonb + colunas, e não 418 colunas.
//
// Cada fonte guarda em `crm.sync_estado` até onde já leu. Sem isso, toda noite
// seria uma varredura completa de 20 mil registros para achar as dez que
// mudaram.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Abaixo do limite da Edge Function, com folga para a última página terminar.
// Quando estoura, salva onde parou e devolve concluido=false: o cron chama de
// novo e continua de onde ficou. Carga grande vira várias corridas curtas.
const ORCAMENTO_MS = 90_000;
const PAGINA = 100; // teto da Search API do HubSpot

type Fonte = "hubspot_contatos" | "hubspot_negocios" | "hubspot_negocios_historicos";

// `modificado` difere por objeto: contato usa `lastmodifieddate`, negocio usa
// `hs_lastmodifieddate`. Buscar pela propriedade errada nao da erro no HubSpot --
// devolve zero resultado, que e pior do que falhar.
const FONTES: Record<Fonte, { objeto: "contacts" | "deals"; modificado: string; pipelineDe?: "leads" | "historico" }> = {
  hubspot_contatos: { objeto: "contacts", modificado: "lastmodifieddate" },
  hubspot_negocios: { objeto: "deals", modificado: "hs_lastmodifieddate", pipelineDe: "leads" },
  hubspot_negocios_historicos: { objeto: "deals", modificado: "hs_lastmodifieddate", pipelineDe: "historico" },
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

// O HubSpot devolve TUDO como string. Coluna numérica recebendo "" ou "N/A"
// derruba o lote inteiro, então a conversão acontece aqui, guiada pelo tipo que
// o próprio HubSpot declara — não por adivinhação.
function limpar(valor: unknown, tipo: string): unknown {
  if (valor === null || valor === undefined) return null;
  const s = String(valor).trim();
  if (s === "") return null;
  if (tipo === "number") return Number.isFinite(Number(s)) ? s : null;
  if (tipo === "bool") return s === "true" || s === "false" ? s : null;
  if (tipo === "date" || tipo === "datetime") return s;
  return s;
}

async function hubspot(caminho: string, token: string, init?: RequestInit) {
  const res = await fetch(`https://api.hubapi.com${caminho}`, {
    ...init,
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
  if (!res.ok) {
    const corpo = await res.text().catch(() => "");
    throw new Error(`hubspot ${res.status} em ${caminho}: ${corpo.slice(0, 300)}`);
  }
  return res.json();
}

// Quais propriedades pedir. Buscamos a lista viva em vez de manter uma cópia:
// propriedade criada hoje já entra na próxima corrida.
async function propriedadesDe(objeto: string, token: string) {
  const r = await hubspot(`/crm/v3/properties/${objeto}`, token);
  const tipos = new Map<string, string>();
  for (const p of r.results ?? []) tipos.set(p.name, p.type);
  return tipos;
}

// A Search API não devolve associação. O contato de um negócio vem daqui, em
// lote de até 100 — é o que permite `mind_espelho_ligar` amarrar negócio a
// pessoa sem uma chamada por negócio.
async function contatosDosNegocios(ids: string[], token: string) {
  const mapa = new Map<string, string[]>();
  if (ids.length === 0) return mapa;
  const r = await hubspot("/crm/v4/associations/deals/contacts/batch/read", token, {
    method: "POST",
    body: JSON.stringify({ inputs: ids.map((id) => ({ id })) }),
  });
  for (const linha of r.results ?? []) {
    const de = String(linha.from?.id ?? "");
    const para = (linha.to ?? []).map((t: { toObjectId?: string | number }) => String(t.toObjectId));
    if (de) mapa.set(de, para);
  }
  return mapa;
}

Deno.serve(async (req: Request) => {
  const inicio = Date.now();
  const token = Deno.env.get("HUBSPOT_TOKEN");
  const url = Deno.env.get("SUPABASE_URL");
  const chave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!token) return json(500, { ok: false, erro: "HUBSPOT_TOKEN ausente nos secrets" });
  if (!url || !chave) return json(500, { ok: false, erro: "ambiente do supabase incompleto" });

  const db = createClient(url, chave, { auth: { persistSession: false } });

  let pedido: { fonte?: Fonte; paginas?: number } = {};
  if (req.method === "POST") pedido = await req.json().catch(() => ({}));

  const alvos: Fonte[] = pedido.fonte ? [pedido.fonte] : (Object.keys(FONTES) as Fonte[]);
  const tetoPaginas = Number.isInteger(pedido.paginas) ? Number(pedido.paginas) : 1000;

  const relatorio: Record<string, unknown> = {};
  let concluidoTudo = true;

  for (const fonte of alvos) {
    const { objeto, modificado, pipelineDe } = FONTES[fonte];

    // Abrir a corrida: marca d'água, destino e config vêm de uma RPC só.
    const { data: abertura, error: erroAbrir } = await db.rpc("mind_sync_abrir", { p_fonte: fonte });
    if (erroAbrir) {
      relatorio[fonte] = { erro: `abrir: ${erroAbrir.message}` };
      concluidoTudo = false;
      continue;
    }
    const cfg = ((abertura as { config?: Record<string, string> })?.config ?? {});
    const pipeline = pipelineDe === "leads"
      ? cfg.pipeline_leads
      : pipelineDe === "historico"
      ? cfg.pipeline_historico
      : null;

    if (pipelineDe && !pipeline) {
      relatorio[fonte] = { erro: "pipeline nao configurado em platform.integracoes" };
      concluidoTudo = false;
      continue;
    }

    // 1970 na primeira vez = carga inicial. Depois disso, só o que mudou.
    const marcaSalva = (abertura as { marca_dagua?: string })?.marca_dagua;
    let marca = marcaSalva ? new Date(marcaSalva).getTime() : 0;

    let tipos: Map<string, string>;
    try {
      tipos = await propriedadesDe(objeto, token);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      await db.rpc("mind_sync_marcar", { p_fonte: fonte, p_status: "erro", p_erro: msg });
      relatorio[fonte] = { erro: msg };
      concluidoTudo = false;
      continue;
    }
    const nomes = [...tipos.keys()];

    let depois: string | undefined;
    let lidos = 0;
    let gravados = 0;
    let paginas = 0;
    let concluido = true;
    let erro: string | null = null;

    try {
      while (paginas < tetoPaginas) {
        if (Date.now() - inicio > ORCAMENTO_MS) { concluido = false; break; }

        const filtros: Record<string, unknown>[] = [
          { propertyName: modificado, operator: "GT", value: String(marca) },
        ];
        if (pipeline) filtros.push({ propertyName: "pipeline", operator: "EQ", value: pipeline });

        const busca = await hubspot(`/crm/v3/objects/${objeto}/search`, token, {
          method: "POST",
          body: JSON.stringify({
            filterGroups: [{ filters: filtros }],
            sorts: [{ propertyName: modificado, direction: "ASCENDING" }],
            properties: nomes,
            limit: PAGINA,
            after: depois,
          }),
        });

        const linhas = busca.results ?? [];
        if (linhas.length === 0) break;
        paginas += 1;
        lidos += linhas.length;

        const ids = linhas.map((l: { id: string }) => String(l.id));
        const assoc = objeto === "deals" ? await contatosDosNegocios(ids, token) : new Map();

        const registros = linhas.map((l: { id: string; properties: Record<string, unknown> }) => {
          const props = l.properties ?? {};
          const limpo: Record<string, unknown> = {};
          for (const [k, v] of Object.entries(props)) {
            limpo[k] = limpar(v, tipos.get(k) ?? "string");
          }
          // O registro cru vai inteiro; `_contatos` viaja junto porque é o que
          // liga negócio a pessoa e não existe como propriedade no HubSpot.
          const inteiro: Record<string, unknown> = { ...limpo };
          if (objeto === "deals") inteiro._contatos = assoc.get(String(l.id)) ?? [];

          return {
            ...limpo,
            [objeto === "contacts" ? "hubspot_id" : "hubspot_deal_id"]: String(l.id),
            propriedades: inteiro,
          };
        });

        const { data: res, error } = await db.rpc("mind_espelho_gravar", {
          p_fonte: fonte,
          p_registros: registros,
        });
        if (error) throw new Error(`gravar: ${error.message}`);
        gravados += Number((res as { gravados?: number })?.gravados ?? 0);

        // A marca d'água só anda depois de gravar. Se cair no meio, a próxima
        // corrida relê a página — reler é idempotente, pular não seria.
        const ultimo = linhas[linhas.length - 1]?.properties?.[modificado];
        if (ultimo) marca = new Date(ultimo).getTime();

        depois = busca.paging?.next?.after;
        await db.rpc("mind_sync_marcar", {
          p_fonte: fonte,
          p_marca: new Date(marca).toISOString(),
          p_lidos: lidos,
          p_gravados: gravados,
        });

        // Sem `after` a consulta acabou. A marca d'água já andou, então a
        // próxima rodada começa depois do último que veio.
        if (!depois) break;
      }
    } catch (e) {
      erro = e instanceof Error ? e.message : String(e);
      concluido = false;
    }

    if (!concluido) concluidoTudo = false;

    await db.rpc("mind_sync_marcar", {
      p_fonte: fonte,
      p_status: erro ? "erro" : concluido ? "ocioso" : "parcial",
      p_erro: erro,
    });

    relatorio[fonte] = { lidos, gravados, paginas, concluido, erro };
    console.info(JSON.stringify({ fn: "hubspot-sync", fonte, lidos, gravados, paginas, concluido, erro }));
  }

  // Amarrar sempre, mesmo em corrida parcial: contato que chegou agora já pode
  // ser ligado à pessoa, e negócio que chegou antes do contato dele é ligado na
  // corrida seguinte.
  const { data: ligados, error: erroLigar } = await db.rpc("mind_espelho_ligar");

  return json(200, {
    ok: true,
    concluido: concluidoTudo,
    fontes: relatorio,
    ligacoes: erroLigar ? { erro: erroLigar.message } : ligados,
    ms: Date.now() - inicio,
  });
});
