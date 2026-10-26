// hubspot-credenciamento-writeback — leva o credenciamento do Summit 2026 ao HubSpot.
//
// Pedido da Adriana em 23/09/2026, na direção de D1 (o banco alimenta o HubSpot).
// O plano por pessoa vem de `mind_credenciamento_hubspot_plano()`; a decisão do que
// escrever em cada contato é `mapping.ts` (puro, testado no Node); aqui só há I/O.
//
// NADA que já está no HubSpot é sobrescrito (regra dela): só se preenche o que está
// vazio, e nos anos acrescenta-se 2026. A exceção é o reembolso confirmado pela Eduzz,
// que troca `status_summit_2026` e aparece em `substituicoes` no relatório.
//
// Chamada: POST com JSON { token, executar?, limite?, deslocamento?, emails? }.
//   token        obrigatório — intelligence.config.analise_token (mesma porta dos
//                outros disparos internos). Além do JWT que o gateway exige.
//   executar     false por padrão: ENSAIO, nada é escrito, o relatório diz o que seria.
//   limite / deslocamento / emails  recortam o plano (piloto, retomada).
//
// Escreve em lotes de 100 (batch API); se um lote falha, refaz um a um para isolar o
// erro em vez de perder o lote inteiro. Respeita 429 com espera.
//
// Publicação manual (este repo não tem supabase/config.toml). Antes de publicar,
// diferencie contra a versão no ar — supabase/functions/README.md.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";
import {
  type ContatoAtual,
  type Decisao,
  type Definicoes,
  type Linha,
  planejar,
  PROPRIEDADES_LIDAS,
} from "./mapping.ts";

const HUBSPOT = "https://api.hubapi.com";
const LOTE = 100;
const ORCAMENTO_MS = 110_000; // o gateway derruba a chamada em 150 s; a função devolve antes
const MAX_LISTA = 400;

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function mensagem(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

function fatiar<T>(itens: T[], tamanho: number): T[][] {
  const fatias: T[][] = [];
  for (let i = 0; i < itens.length; i += tamanho) fatias.push(itens.slice(i, i + tamanho));
  return fatias;
}

const dormir = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function hubspot(
  token: string,
  caminho: string,
  init?: RequestInit,
  tentativa = 0,
): Promise<Record<string, unknown>> {
  const res = await fetch(`${HUBSPOT}${caminho}`, {
    ...init,
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
    signal: AbortSignal.timeout(30_000),
  });
  if (res.status === 429 && tentativa < 3) {
    await dormir(2_000 * (tentativa + 1));
    return hubspot(token, caminho, init, tentativa + 1);
  }
  const texto = await res.text();
  if (!res.ok) throw new HubSpotErro(res.status, caminho, texto);
  return texto ? JSON.parse(texto) as Record<string, unknown> : {};
}

class HubSpotErro extends Error {
  status: number;
  corpo: string;
  constructor(status: number, caminho: string, corpo: string) {
    super(`hubspot ${status} em ${caminho}: ${corpo.slice(0, 300)}`);
    this.status = status;
    this.corpo = corpo;
  }
}

// O HubSpot recusa a escrita inteira quando UMA propriedade é inválida (e-mail com
// domínio errado, telefone que não bate com o +55). O corpo do 400 nomeia a propriedade:
// {"isValid":false,"error":"INVALID_PHONE_NUMBER","name":"hs_whatsapp_phone_number"}.
function propriedadesRecusadas(e: unknown): string[] {
  if (!(e instanceof HubSpotErro) || e.status !== 400) return [];
  const nomes = new Set<string>();
  for (const m of e.corpo.matchAll(/\\?"name\\?":\\?"([a-z0-9_]+)\\?"/g)) nomes.add(m[1]);
  return [...nomes];
}

// A introspecção do token é melhor esforço: para alguns tokens o HubSpot não devolve os
// escopos. Aí ninguém é bloqueado por "desconhecido" — a própria leitura ou escrita no
// HubSpot denuncia falta de permissão, e o erro vai para o relatório.
async function escopos(token: string): Promise<{ http: number; lista: string[] | null }> {
  try {
    const res = await fetch(`${HUBSPOT}/oauth/v1/access-tokens/${token}`, { signal: AbortSignal.timeout(15_000) });
    const info = await res.json().catch(() => null) as { scopes?: unknown } | null;
    const lista = Array.isArray(info?.scopes) ? (info!.scopes as unknown[]).map(String) : null;
    return { http: res.status, lista };
  } catch {
    return { http: 0, lista: null };
  }
}

async function definicoes(token: string): Promise<Definicoes> {
  const r = await hubspot(token, "/crm/v3/properties/contacts");
  const defs: Definicoes = {};
  for (const p of (r.results ?? []) as Array<Record<string, unknown>>) {
    defs[String(p.name)] = {
      name: String(p.name),
      type: String(p.type ?? ""),
      fieldType: String(p.fieldType ?? ""),
      options: Array.isArray(p.options) ? p.options as Definicoes[string]["options"] : [],
    };
  }
  return defs;
}

async function lerContatos(token: string, emails: string[]): Promise<Map<string, ContatoAtual>> {
  const mapa = new Map<string, ContatoAtual>();
  for (const fatia of fatiar(emails, LOTE)) {
    const r = await hubspot(token, "/crm/v3/objects/contacts/batch/read", {
      method: "POST",
      body: JSON.stringify({
        idProperty: "email",
        inputs: fatia.map((id) => ({ id })),
        properties: PROPRIEDADES_LIDAS,
      }),
    });
    for (const c of (r.results ?? []) as Array<{ id: string | number; properties?: Record<string, string | null> }>) {
      const em = String(c.properties?.email ?? "").trim().toLowerCase();
      if (em) mapa.set(em, { id: String(c.id), properties: c.properties ?? {} });
    }
  }
  return mapa;
}

/**
 * Escreve um contato sozinho. Se o HubSpot recusar uma propriedade, tira só ela e tenta
 * mais uma vez: o resto do que a pessoa tem entra, e o valor recusado vai para `erros`
 * com o nome da propriedade, para a correção acontecer na origem.
 */
async function umAUm(
  token: string,
  caminho: string,
  metodo: "PATCH" | "POST",
  d: Decisao,
  erros: string[],
): Promise<boolean> {
  let propriedades = { ...d.propriedades };
  for (let tentativa = 0; tentativa < 2; tentativa += 1) {
    try {
      await hubspot(token, caminho, { method: metodo, body: JSON.stringify({ properties: propriedades }) });
      return true;
    } catch (e) {
      const recusadas = propriedadesRecusadas(e).filter((p) => p in propriedades);
      if (recusadas.length === 0 || recusadas.includes("email")) {
        erros.push(`${d.email}: ${mensagem(e).slice(0, 220)}`);
        return false;
      }
      for (const p of recusadas) {
        erros.push(`${d.email}: ${p} recusado pelo HubSpot (${propriedades[p]}), gravado sem ele`);
        delete propriedades[p];
      }
      if (Object.keys(propriedades).length === 0) return false;
    }
  }
  return false;
}

type Escrita = { criados: number; atualizados: number; incompleto: boolean };

async function escrever(
  token: string,
  decisoes: Decisao[],
  erros: string[],
  prazo: () => boolean,
): Promise<Escrita> {
  const resultado: Escrita = { criados: 0, atualizados: 0, incompleto: false };

  for (const fatia of fatiar(decisoes.filter((d) => d.acao === "atualizar"), LOTE)) {
    if (prazo()) { resultado.incompleto = true; return resultado; }
    try {
      await hubspot(token, "/crm/v3/objects/contacts/batch/update", {
        method: "POST",
        body: JSON.stringify({ inputs: fatia.map((d) => ({ id: d.id, properties: d.propriedades })) }),
      });
      resultado.atualizados += fatia.length;
    } catch (e) {
      erros.push(`lote de atualização recusado, refazendo um a um: ${mensagem(e).slice(0, 160)}`);
      for (const d of fatia) {
        if (prazo()) { resultado.incompleto = true; return resultado; }
        const ok = await umAUm(token, `/crm/v3/objects/contacts/${encodeURIComponent(d.id ?? "")}`, "PATCH", d, erros);
        if (ok) resultado.atualizados += 1;
      }
    }
  }

  for (const fatia of fatiar(decisoes.filter((d) => d.acao === "criar"), LOTE)) {
    if (prazo()) { resultado.incompleto = true; return resultado; }
    try {
      await hubspot(token, "/crm/v3/objects/contacts/batch/create", {
        method: "POST",
        body: JSON.stringify({ inputs: fatia.map((d) => ({ properties: d.propriedades })) }),
      });
      resultado.criados += fatia.length;
    } catch (e) {
      erros.push(`lote de criação recusado, refazendo um a um: ${mensagem(e).slice(0, 160)}`);
      for (const d of fatia) {
        if (prazo()) { resultado.incompleto = true; return resultado; }
        const ok = await umAUm(token, "/crm/v3/objects/contacts", "POST", d, erros);
        if (ok) resultado.criados += 1;
      }
    }
  }

  return resultado;
}

Deno.serve(async (req: Request) => {
  const inicio = Date.now();
  const prazo = () => Date.now() - inicio > ORCAMENTO_MS;
  if (req.method !== "POST") return json(405, { ok: false, erro: "method_not_allowed" });

  const token = Deno.env.get("HUBSPOT_TOKEN");
  const url = Deno.env.get("SUPABASE_URL");
  const chave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!token) return json(500, { ok: false, erro: "HUBSPOT_TOKEN ausente nos secrets" });
  if (!url || !chave) return json(500, { ok: false, erro: "ambiente do supabase incompleto" });

  const db = createClient(url, chave, { auth: { persistSession: false, autoRefreshToken: false } });

  const corpo = await req.json().catch(() => ({})) as {
    token?: string;
    executar?: boolean;
    limite?: number;
    deslocamento?: number;
    emails?: string[];
  };

  const { data: cfg } = await db.rpc("analise_config");
  const esperado = (cfg as { analise_token?: string } | null)?.analise_token;
  if (!esperado || !corpo.token || corpo.token !== esperado) {
    return json(401, { ok: false, erro: "unauthorized" });
  }

  const executar = corpo.executar === true;

  const intro = await escopos(token);
  const conhecidos = intro.lista !== null;
  const podeLer = !conhecidos || intro.lista!.includes("crm.objects.contacts.read");
  const podeEscrever = !conhecidos || intro.lista!.includes("crm.objects.contacts.write");
  if (!podeLer) return json(500, { ok: false, erro: "token sem crm.objects.contacts.read", scopes: intro.lista });
  if (executar && !podeEscrever) return json(500, { ok: false, erro: "token sem crm.objects.contacts.write", scopes: intro.lista });

  let defs: Definicoes;
  try {
    defs = await definicoes(token);
  } catch (e) {
    return json(500, { ok: false, erro: `propriedades do HubSpot: ${mensagem(e)}` });
  }
  const propriedadesFaltando = PROPRIEDADES_LIDAS.filter((p) => !defs[p]);

  // PostgREST devolve no máximo 1.000 linhas por chamada; o plano tem mais. Pagina até acabar.
  const PAGINA = 1000;
  const planoTodo: Linha[] = [];
  for (let de = 0; ; de += PAGINA) {
    const { data: pagina, error: erroPlano } = await db
      .rpc("mind_credenciamento_hubspot_plano")
      .range(de, de + PAGINA - 1);
    if (erroPlano) return json(500, { ok: false, erro: `plano: ${erroPlano.message}` });
    const lote = (pagina ?? []) as Linha[];
    planoTodo.push(...lote);
    if (lote.length < PAGINA) break;
  }

  let linhas = planoTodo;
  const totalPlano = linhas.length;
  if (Array.isArray(corpo.emails) && corpo.emails.length > 0) {
    const alvo = new Set(corpo.emails.map((e) => String(e).trim().toLowerCase()));
    linhas = linhas.filter((l) => alvo.has(l.email));
  }
  const deslocamento = Math.max(0, Math.trunc(corpo.deslocamento ?? 0));
  const limite = corpo.limite && corpo.limite > 0 ? Math.trunc(corpo.limite) : linhas.length;
  linhas = linhas.slice(deslocamento, deslocamento + limite);

  let atuais: Map<string, ContatoAtual>;
  try {
    atuais = await lerContatos(token, linhas.map((l) => l.email));
  } catch (e) {
    return json(500, { ok: false, erro: `leitura dos contatos: ${mensagem(e)}` });
  }

  const decisoes = linhas.map((l) => planejar(l, atuais.get(l.email) ?? null, defs));

  const totais = {
    plano: totalPlano,
    recorte: linhas.length,
    existentes_no_hubspot: atuais.size,
    criar: decisoes.filter((d) => d.acao === "criar").length,
    atualizar: decisoes.filter((d) => d.acao === "atualizar").length,
    nada: decisoes.filter((d) => d.acao === "nada").length,
    pular: decisoes.filter((d) => d.acao === "pular").length,
    so_por_terceiro: linhas.filter((l) => l.so_por_terceiro).length,
    reembolso_confirmado: linhas.filter((l) => l.reembolsado).length,
    reembolso_nao_confirmado: linhas.filter((l) => l.reembolso_nao_confirmado).length,
  };

  const porPropriedade: Record<string, { escritas: number; conflitos: number; ignorados: number }> = {};
  const conta = (prop: string) => porPropriedade[prop] ??= { escritas: 0, conflitos: 0, ignorados: 0 };
  for (const d of decisoes) {
    if (d.acao === "criar" || d.acao === "atualizar") {
      for (const prop of Object.keys(d.propriedades)) conta(prop).escritas += 1;
    }
    for (const c of d.conflitos) conta(c.propriedade).conflitos += 1;
    for (const i of d.ignorados) conta(i.propriedade).ignorados += 1;
  }

  const conflitos = decisoes.flatMap((d) => d.conflitos);
  const ignorados = decisoes.flatMap((d) => d.ignorados);
  const substituicoes = decisoes.flatMap((d) => d.substituicoes);
  const ignoradosPorMotivo: Record<string, number> = {};
  for (const i of ignorados) ignoradosPorMotivo[`${i.propriedade}: ${i.motivo} (${i.valor})`] = (ignoradosPorMotivo[`${i.propriedade}: ${i.motivo} (${i.valor})`] ?? 0) + 1;

  const amostra = decisoes
    .filter((d) => d.acao === "criar" || d.acao === "atualizar")
    .slice(0, 6)
    .map((d) => ({ email: d.email, acao: d.acao, propriedades: d.propriedades }));

  const erros: string[] = [];
  let escrita: Escrita | null = null;
  if (executar) escrita = await escrever(token, decisoes, erros, prazo);

  return json(200, {
    ok: erros.length === 0 && !(escrita?.incompleto),
    executar,
    escopos: { introspeccao_http: intro.http, conhecidos, ler: podeLer, escrever: podeEscrever },
    propriedades_faltando: propriedadesFaltando,
    totais,
    por_propriedade: porPropriedade,
    conflitos: { total: conflitos.length, lista: conflitos.slice(0, MAX_LISTA) },
    substituicoes,
    ignorados: { total: ignorados.length, por_motivo: ignoradosPorMotivo, lista: ignorados.slice(0, 60) },
    amostra,
    escrita,
    erros,
    ms: Date.now() - inicio,
  });
});
