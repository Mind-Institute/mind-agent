// hubspot-perfil-writeback — leva o perfil profissional (cargo, empresa, ICP e JTBD) ao HubSpot.
//
// Pedido da Adriana em 23/09/2026, na direção de D1 (o banco alimenta o HubSpot). Irmã de
// hubspot-credenciamento-writeback: mesma porta, mesmo relatório, mesmo ENSAIO por padrão.
// O plano por pessoa vem de `mind_hubspot_perfil_plano()`; os catálogos (ICP, JTBD) vêm de
// `mind_hubspot_perfil_definicoes()`; a decisão do que escrever é `mapping.ts` (puro,
// testado no Node); aqui só há I/O.
//
// Regras dela:
// - cargo (jobtitle) e empresa (company) são o que a pessoa escreveu no credenciamento:
//   atualizam o HubSpot, mas SEM duplicar por typo/grafia; quando trocam de verdade, a troca
//   aparece em `substituicoes` para ela rever.
// - ICP só preenche o que está vazio (valor manual do HubSpot nunca é sobrescrito; a
//   diferença vai para `conflitos`). Junto vai `icp_confianca` (0–10).
// - JTBD (multi-seleção) recebe a união do que já está lá com o que o Mind vê.
// - Esta função NÃO cria contatos; quem cria é a irmã de credenciamento.
//
// Chamada: POST com JSON { token, acao?, executar?, limite?, deslocamento?, emails? }.
//   token        obrigatório — intelligence.config.analise_token (mesma porta dos outros
//                disparos internos). Além do JWT que o gateway exige.
//   acao         "contatos" (padrão) escreve nos contatos; "propriedades" garante as
//                definições de `icp` (opções) e `jtbd` (cria se faltar) a partir dos catálogos.
//   executar     false por padrão: ENSAIO, nada é escrito, o relatório diz o que seria.
//   limite / deslocamento / emails  recortam o plano (piloto, retomada).
//
// Escreve em lotes de 100 (batch API); se um lote falha, refaz um a um para isolar o erro
// em vez de perder o lote inteiro. Respeita 429 com espera. Escrever definição de
// propriedade exige o escopo crm.schemas.contacts.write no app privado; sem ele o
// relatório diz `escopo_faltando` em vez de um erro genérico.
//
// Publicação manual (este repo não tem supabase/config.toml). Antes de publicar,
// diferencie contra a versão no ar — supabase/functions/README.md.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";
import {
  type Catalogos,
  type ContatoAtual,
  type Decisao,
  type Definicoes,
  type DiffOpcoes,
  type Linha,
  montarOpcoes,
  type OpcaoHubSpot,
  planejar,
  PROPRIEDADES_LIDAS,
} from "./mapping.ts";

const HUBSPOT = "https://api.hubapi.com";
const LOTE = 100;
const ORCAMENTO_MS = 110_000; // o gateway derruba a chamada em 150 s; a função devolve antes
const MAX_LISTA = 400;
const PAGINA = 1000; // PostgREST devolve no máximo 1.000 linhas por chamada
const ESCOPO_ESQUEMA = "crm.schemas.contacts.write";

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

// O HubSpot recusa a escrita inteira quando UMA propriedade é inválida. O corpo do 400
// nomeia a propriedade: {"isValid":false,"error":"INVALID_OPTION","name":"icp"}.
function propriedadesRecusadas(e: unknown): string[] {
  if (!(e instanceof HubSpotErro) || e.status !== 400) return [];
  const nomes = new Set<string>();
  for (const m of e.corpo.matchAll(/\\?"name\\?":\\?"([a-z0-9_]+)\\?"/g)) nomes.add(m[1]);
  return [...nomes];
}

// 403 ao escrever definição de propriedade é falta do escopo crm.schemas.contacts.write no
// app privado — o relatório diz isso com todas as letras em vez de um erro genérico.
function escopoFaltandoEm(e: unknown): string | null {
  return e instanceof HubSpotErro && e.status === 403 ? ESCOPO_ESQUEMA : null;
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
      options: Array.isArray(p.options) ? p.options as OpcaoHubSpot[] : [],
    };
  }
  return defs;
}

type PropriedadeHubSpot = {
  name: string;
  label?: string;
  type?: string;
  fieldType?: string;
  groupName?: string;
  options?: OpcaoHubSpot[];
};

/** Definição de uma propriedade; null quando ela não existe (404). */
async function lerPropriedade(token: string, nome: string): Promise<PropriedadeHubSpot | null> {
  try {
    return await hubspot(token, `/crm/v3/properties/contacts/${encodeURIComponent(nome)}`) as PropriedadeHubSpot;
  } catch (e) {
    if (e instanceof HubSpotErro && e.status === 404) return null;
    throw e;
  }
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

async function lerContatosPorId(token: string, ids: string[]): Promise<Map<string, ContatoAtual>> {
  const mapa = new Map<string, ContatoAtual>();
  for (const fatia of fatiar(ids, LOTE)) {
    const r = await hubspot(token, "/crm/v3/objects/contacts/batch/read", {
      method: "POST",
      body: JSON.stringify({
        inputs: fatia.map((id) => ({ id })),
        properties: PROPRIEDADES_LIDAS,
      }),
    });
    for (const c of (r.results ?? []) as Array<{ id: string | number; properties?: Record<string, string | null> }>) {
      mapa.set(String(c.id), { id: String(c.id), properties: c.properties ?? {} });
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
  const propriedades = { ...d.propriedades };
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

type Escrita = { atualizados: number; incompleto: boolean };

// Só atualiza: esta função não cria contatos.
async function escrever(
  token: string,
  decisoes: Decisao[],
  erros: string[],
  prazo: () => boolean,
): Promise<Escrita> {
  const resultado: Escrita = { atualizados: 0, incompleto: false };

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

  return resultado;
}

type RelatorioPropriedade = {
  existe: boolean;
  acao: "criar" | "atualizar" | "nada";
  opcoes: number;
  diff: DiffOpcoes | null;
  executado: boolean;
  erro?: string;
};

type Contexto = {
  token: string;
  executar: boolean;
  escopoFaltando: string | null;
  erros: string[];
};

/** Aplica ao HubSpot (ou só relata, em ENSAIO) as opções de uma enumeração existente. */
async function alinharOpcoes(
  ctx: Contexto,
  nome: string,
  atual: PropriedadeHubSpot,
  catalogo: Catalogos[keyof Catalogos],
): Promise<RelatorioPropriedade> {
  const m = montarOpcoes(atual.options ?? [], catalogo ?? []);
  const rel: RelatorioPropriedade = {
    existe: true,
    acao: m.mudou ? "atualizar" : "nada",
    opcoes: m.opcoes.length,
    diff: m.diff,
    executado: false,
  };
  if (!m.mudou || !ctx.executar || ctx.escopoFaltando) return rel;
  try {
    await hubspot(ctx.token, `/crm/v3/properties/contacts/${encodeURIComponent(nome)}`, {
      method: "PATCH",
      body: JSON.stringify({ options: m.opcoes }),
    });
    rel.executado = true;
  } catch (e) {
    ctx.escopoFaltando = escopoFaltandoEm(e) ?? ctx.escopoFaltando;
    rel.erro = mensagem(e);
    ctx.erros.push(`${nome}: ${mensagem(e).slice(0, 220)}`);
  }
  return rel;
}

/** Cria `jtbd` (multi-seleção) no mesmo grupo de `icp`, com as opções do catálogo. */
async function criarJtbd(
  ctx: Contexto,
  groupName: string | undefined,
  catalogo: Catalogos[keyof Catalogos],
): Promise<RelatorioPropriedade> {
  const m = montarOpcoes([], catalogo ?? []);
  const rel: RelatorioPropriedade = {
    existe: false,
    acao: "criar",
    opcoes: m.opcoes.length,
    diff: m.diff,
    executado: false,
  };
  if (!groupName) {
    rel.erro = "sem groupName: a propriedade icp não foi lida, e jtbd nasce no grupo dela";
    ctx.erros.push(`jtbd: ${rel.erro}`);
    return rel;
  }
  if (m.opcoes.length === 0) {
    rel.erro = "catálogo jtbd vazio em mind_hubspot_perfil_definicoes";
    ctx.erros.push(`jtbd: ${rel.erro}`);
    return rel;
  }
  if (!ctx.executar || ctx.escopoFaltando) return rel;
  try {
    await hubspot(ctx.token, "/crm/v3/properties/contacts", {
      method: "POST",
      body: JSON.stringify({
        name: "jtbd",
        label: "JTBD (Mind)",
        description: "Jobs to be done da pessoa segundo a inteligência do Mind (catálogo intelligence.jtbd). Multi-seleção.",
        groupName,
        type: "enumeration",
        fieldType: "checkbox",
        options: m.opcoes,
      }),
    });
    rel.executado = true;
  } catch (e) {
    ctx.escopoFaltando = escopoFaltandoEm(e) ?? ctx.escopoFaltando;
    rel.erro = mensagem(e);
    ctx.erros.push(`jtbd: ${mensagem(e).slice(0, 220)}`);
  }
  return rel;
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
    acao?: "contatos" | "propriedades";
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
  const acao = corpo.acao ?? "contatos";
  if (acao !== "contatos" && acao !== "propriedades") {
    return json(400, { ok: false, erro: "acao_invalida", aceitas: ["contatos", "propriedades"] });
  }

  const intro = await escopos(token);
  const conhecidos = intro.lista !== null;
  const podeLer = !conhecidos || intro.lista!.includes("crm.objects.contacts.read");
  const podeEscrever = !conhecidos || intro.lista!.includes("crm.objects.contacts.write");
  const podeEsquema = !conhecidos || intro.lista!.includes(ESCOPO_ESQUEMA);
  const escoposRelatorio = { introspeccao_http: intro.http, conhecidos, ler: podeLer, escrever: podeEscrever, esquema: podeEsquema };

  // ------------------------------------------------------------ acao = propriedades
  if (acao === "propriedades") {
    const { data: cat, error: erroCat } = await db.rpc("mind_hubspot_perfil_definicoes");
    if (erroCat) return json(500, { ok: false, erro: `definicoes: ${erroCat.message}` });
    const catalogos = (cat ?? {}) as Catalogos;

    const ctx: Contexto = { token, executar, escopoFaltando: podeEsquema ? null : ESCOPO_ESQUEMA, erros: [] };
    const propriedades: Record<string, RelatorioPropriedade> = {};

    let icpAtual: PropriedadeHubSpot | null;
    let jtbdAtual: PropriedadeHubSpot | null;
    try {
      icpAtual = await lerPropriedade(token, "icp");
      jtbdAtual = await lerPropriedade(token, "jtbd");
    } catch (e) {
      return json(500, { ok: false, erro: `propriedades do HubSpot: ${mensagem(e)}` });
    }

    // `icp` é pré-existente no HubSpot (6 opções manuais); esta função alinha as opções,
    // nunca a cria nem apaga valor.
    if (!icpAtual) {
      propriedades.icp = {
        existe: false, acao: "nada", opcoes: 0, diff: null, executado: false,
        erro: "propriedade icp não existe no HubSpot; ela é pré-existente e esta função não a cria",
      };
      ctx.erros.push(`icp: ${propriedades.icp.erro}`);
    } else {
      propriedades.icp = await alinharOpcoes(ctx, "icp", icpAtual, catalogos.icp);
    }

    propriedades.jtbd = jtbdAtual
      ? await alinharOpcoes(ctx, "jtbd", jtbdAtual, catalogos.jtbd)
      : await criarJtbd(ctx, icpAtual?.groupName, catalogos.jtbd);

    const pendentes = Object.values(propriedades).filter((p) => p.acao !== "nada" && !p.executado).length;
    return json(200, {
      ok: ctx.erros.length === 0 && !(executar && ctx.escopoFaltando && pendentes > 0),
      executar,
      acao,
      escopos: escoposRelatorio,
      ...(ctx.escopoFaltando ? { escopo_faltando: ctx.escopoFaltando } : {}),
      catalogo: { icp: (catalogos.icp ?? []).length, jtbd: (catalogos.jtbd ?? []).length },
      propriedades,
      erros: ctx.erros,
      ms: Date.now() - inicio,
    });
  }

  // ---------------------------------------------------------------- acao = contatos
  if (!podeLer) return json(500, { ok: false, erro: "token sem crm.objects.contacts.read", scopes: intro.lista });
  if (executar && !podeEscrever) return json(500, { ok: false, erro: "token sem crm.objects.contacts.write", scopes: intro.lista });

  let defs: Definicoes;
  try {
    defs = await definicoes(token);
  } catch (e) {
    return json(500, { ok: false, erro: `propriedades do HubSpot: ${mensagem(e)}` });
  }
  const propriedadesFaltando = PROPRIEDADES_LIDAS.filter((p) => !defs[p]);

  // PostgREST devolve no máximo 1.000 linhas por chamada; o plano pode ter mais. Pagina até acabar.
  const planoTodo: Linha[] = [];
  for (let de = 0; ; de += PAGINA) {
    const { data: pagina, error: erroPlano } = await db
      .rpc("mind_hubspot_perfil_plano")
      .range(de, de + PAGINA - 1);
    if (erroPlano) return json(500, { ok: false, erro: `plano: ${erroPlano.message}` });
    const lote = (pagina ?? []) as Linha[];
    planoTodo.push(...lote);
    if (lote.length < PAGINA) break;
  }

  let linhas = planoTodo.map((l) => ({
    ...l,
    hubspot_id: l.hubspot_id === null || l.hubspot_id === undefined ? null : String(l.hubspot_id).trim() || null,
    email: typeof l.email === "string" && l.email.trim() !== "" ? l.email.trim().toLowerCase() : null,
  }));
  const totalPlano = linhas.length;
  if (Array.isArray(corpo.emails) && corpo.emails.length > 0) {
    const alvo = new Set(corpo.emails.map((e) => String(e).trim().toLowerCase()));
    linhas = linhas.filter((l) => l.email !== null && alvo.has(l.email));
  }
  const deslocamento = Math.max(0, Math.trunc(corpo.deslocamento ?? 0));
  const limite = corpo.limite && corpo.limite > 0 ? Math.trunc(corpo.limite) : linhas.length;
  linhas = linhas.slice(deslocamento, deslocamento + limite);

  // Localiza o contato: por hubspot_id quando houver; senão por e-mail. Se o id não
  // responde (contato fundido/apagado no HubSpot), tenta o e-mail antes de desistir.
  let porId: Map<string, ContatoAtual>;
  let porEmail: Map<string, ContatoAtual>;
  try {
    porId = await lerContatosPorId(token, [...new Set(linhas.flatMap((l) => l.hubspot_id ? [l.hubspot_id] : []))]);
    const emailsSemId = linhas
      .filter((l) => l.email !== null && (l.hubspot_id === null || !porId.has(l.hubspot_id)))
      .map((l) => l.email as string);
    porEmail = await lerContatos(token, [...new Set(emailsSemId)]);
  } catch (e) {
    return json(500, { ok: false, erro: `leitura dos contatos: ${mensagem(e)}` });
  }
  const localizar = (l: Linha): ContatoAtual | null =>
    (l.hubspot_id ? porId.get(l.hubspot_id) : undefined) ??
    (l.email ? porEmail.get(l.email) : undefined) ?? null;

  // Duas linhas do plano no mesmo contato não entram no mesmo lote (o HubSpot recusa o
  // lote inteiro); a segunda é pulada e aparece no relatório.
  const vistos = new Set<string>();
  let existentes = 0;
  const decisoes: Decisao[] = linhas.map((l) => {
    const atual = localizar(l);
    if (atual) existentes += 1;
    if (atual && vistos.has(atual.id)) {
      return {
        mind_id: l.mind_id, email: l.email ?? "", acao: "pular", motivo: "contato_repetido_no_recorte",
        id: atual.id, propriedades: {}, conflitos: [], ignorados: [], substituicoes: [], equivalentes: [],
      };
    }
    if (atual) vistos.add(atual.id);
    return planejar(l, atual, defs);
  });

  const pularPorMotivo: Record<string, number> = {};
  for (const d of decisoes) if (d.acao === "pular") pularPorMotivo[d.motivo ?? "?"] = (pularPorMotivo[d.motivo ?? "?"] ?? 0) + 1;

  const totais = {
    plano: totalPlano,
    recorte: linhas.length,
    existentes_no_hubspot: existentes,
    atualizar: decisoes.filter((d) => d.acao === "atualizar").length,
    nada: decisoes.filter((d) => d.acao === "nada").length,
    pular: decisoes.filter((d) => d.acao === "pular").length,
    pular_por_motivo: pularPorMotivo,
  };

  const porPropriedade: Record<string, { escritas: number; conflitos: number; ignorados: number; substituicoes: number; equivalentes: number }> = {};
  const conta = (prop: string) => porPropriedade[prop] ??= { escritas: 0, conflitos: 0, ignorados: 0, substituicoes: 0, equivalentes: 0 };
  for (const d of decisoes) {
    if (d.acao === "atualizar") for (const prop of Object.keys(d.propriedades)) conta(prop).escritas += 1;
    for (const c of d.conflitos) conta(c.propriedade).conflitos += 1;
    for (const i of d.ignorados) conta(i.propriedade).ignorados += 1;
    for (const s of d.substituicoes) conta(s.propriedade).substituicoes += 1;
    for (const q of d.equivalentes) conta(q.propriedade).equivalentes += 1;
  }

  const conflitos = decisoes.flatMap((d) => d.conflitos);
  const ignorados = decisoes.flatMap((d) => d.ignorados);
  const substituicoes = decisoes.flatMap((d) => d.substituicoes);
  const equivalentes = decisoes.flatMap((d) => d.equivalentes);
  const equivalentesPorMotivo: Record<string, number> = {};
  for (const q of equivalentes) equivalentesPorMotivo[`${q.propriedade}: ${q.motivo}`] = (equivalentesPorMotivo[`${q.propriedade}: ${q.motivo}`] ?? 0) + 1;
  const ignoradosPorMotivo: Record<string, number> = {};
  for (const i of ignorados) {
    const k = `${i.propriedade}: ${i.motivo} (${i.valor})`;
    ignoradosPorMotivo[k] = (ignoradosPorMotivo[k] ?? 0) + 1;
  }

  const fontesPorMind = new Map(linhas.map((l) => [l.mind_id, l.fontes ?? null]));
  const amostra = decisoes
    .filter((d) => d.acao === "atualizar")
    .slice(0, 6)
    .map((d) => ({
      mind_id: d.mind_id,
      email: d.email,
      id: d.id,
      acao: d.acao,
      propriedades: d.propriedades,
      substituicoes: d.substituicoes,
      fontes: fontesPorMind.get(d.mind_id) ?? null,
    }));

  const erros: string[] = [];
  let escrita: Escrita | null = null;
  if (executar) escrita = await escrever(token, decisoes, erros, prazo);

  return json(200, {
    ok: erros.length === 0 && !(escrita?.incompleto),
    executar,
    acao,
    escopos: escoposRelatorio,
    propriedades_faltando: propriedadesFaltando,
    totais,
    por_propriedade: porPropriedade,
    substituicoes: { total: substituicoes.length, lista: substituicoes.slice(0, MAX_LISTA) },
    equivalentes: { total: equivalentes.length, por_motivo: equivalentesPorMotivo, lista: equivalentes.slice(0, 80) },
    conflitos: { total: conflitos.length, lista: conflitos.slice(0, MAX_LISTA) },
    ignorados: { total: ignorados.length, por_motivo: ignoradosPorMotivo, lista: ignorados.slice(0, 60) },
    amostra,
    escrita,
    erros,
    ms: Date.now() - inicio,
  });
});
