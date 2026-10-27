// learnworlds-sync — espelho de leitura do LearnWorlds (Fase 1, aprovada pela Adriana em 23/10/2026).
//
// Lê a escola do Mind Institute e grava nas tabelas de ENTRADA do schema `learnworlds` (D9: como a
// API devolve, sem tratamento):
//   cursos      GET /v2/courses
//   programas   GET /v2/bundles e /v2/subscription-plans
//   usuarios    GET /v2/users (200 por página; retomável entre rodadas)
//   matriculas  GET /v2/courses/{id}/users e /v2/users/by-product (por produto; retomável)
// Nada é escrito no LearnWorlds. Pessoa: `usuarios` e `matriculas` estão na Regra #1
// (`mind_pessoa_ligar_tabela`), então a porta única resolve o `mind_id` antes da escrita.
//
// Credenciais: secrets LEARNWORLDS_CLIENT_ID e LEARNWORLDS_CLIENT_SECRET (OAuth2 client credentials).
// Endereço: LEARNWORLDS_API_URL, ou o da escola (registrado em platform.integracoes, codigo learnworlds).
// Auth desta função: ?token=<intelligence.config.analise_token>, igual às outras chamadas por cron.
// Limite da API: 30 chamadas a cada 10 s. Aqui: uma chamada a cada 350 ms; 429 espera 10 s e tenta de novo.
//
// ?modo=diagnostico só lê: confere as credenciais e devolve os cursos e o tamanho de cada lista.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.112.3";

const VERSION = "1.0.0";
const API_PADRAO = "https://my.mindinstitute.com.br/admin/api";
const ESPACO_MS = 350;
const ORCAMENTO_MS = 120_000;
const POR_PAGINA = 200;
// Pessoa nova passa pela porta única de identidade (~20-50 ms cada) e o banco corta a chamada em 8 s:
// a página de 200 vai ao banco em lotes de 50.
const POR_LOTE = 50;

type Meta = { page?: number; totalPages?: number; totalItems?: number; itemsPerPage?: number };
type Pagina = { data?: Record<string, unknown>[]; meta?: Meta };
type Produto = { id: string; tipo: "course" | "bundle" | "subscription" };

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

class ErroLW extends Error {
  constructor(public onde: string, public status: number, public corpo: string) {
    super(`${onde}: ${status}`);
  }
}

let ultimaChamada = 0;
async function esperarVez() {
  const falta = ultimaChamada + ESPACO_MS - Date.now();
  if (falta > 0) await new Promise((r) => setTimeout(r, falta));
  ultimaChamada = Date.now();
}

class LearnWorlds {
  private constructor(private base: string, private clientId: string, private token: string) {}

  static async conectar(base: string, clientId: string, clientSecret: string) {
    await esperarVez();
    const res = await fetch(`${base}/oauth2/access_token`, {
      method: "POST",
      headers: {
        "Lw-Client": clientId,
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: "data=" + encodeURIComponent(JSON.stringify({
        client_id: clientId, client_secret: clientSecret, grant_type: "client_credentials",
      })),
    });
    const corpo = await res.json().catch(() => ({})) as { tokenData?: { access_token?: string } };
    const token = corpo?.tokenData?.access_token;
    if (!res.ok || !token) throw new ErroLW("auth", res.status, JSON.stringify(corpo).slice(0, 300));
    return new LearnWorlds(base, clientId, token);
  }

  async pagina(caminho: string, params: Record<string, string | number> = {}): Promise<Pagina> {
    const url = new URL(`${this.base}/v2${caminho}`);
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v));
    for (let tentativa = 0; ; tentativa++) {
      await esperarVez();
      const res = await fetch(url, {
        headers: { "Lw-Client": this.clientId, Authorization: `Bearer ${this.token}`, Accept: "application/json" },
      });
      if (res.status === 429 && tentativa < 3) {
        await new Promise((r) => setTimeout(r, 10_000));
        continue;
      }
      if (!res.ok) throw new ErroLW(caminho, res.status, (await res.text()).slice(0, 300));
      return await res.json() as Pagina;
    }
  }

  // Lista pequena (cursos, programas): todas as páginas de uma vez. Lista vazia o LearnWorlds
  // responde com 404 ("Subscription plans not found"), não com uma página sem itens.
  async tudo(caminho: string, params: Record<string, string | number> = {}) {
    const itens: Record<string, unknown>[] = [];
    for (let pagina = 1; ; pagina++) {
      let p: Pagina;
      try {
        p = await this.pagina(caminho, { ...params, page: pagina });
      } catch (e) {
        if (e instanceof ErroLW && e.status === 404 && /not found/i.test(e.corpo)) break;
        throw e;
      }
      itens.push(...(p.data ?? []));
      if (!p.data?.length || pagina >= (p.meta?.totalPages ?? 1)) break;
    }
    return itens;
  }
}

async function gravar(sb: SupabaseClient, entidade: string, itens: unknown, contexto: Record<string, unknown> = {}) {
  const { data, error } = await sb.rpc("learnworlds_espelho_gravar", {
    p_entidade: entidade, p_itens: itens, p_contexto: contexto,
  });
  if (error) throw new Error(`gravar ${entidade}: ${error.message}`);
  return data as Record<string, number>;
}

async function gravarEmLotes(sb: SupabaseClient, entidade: string, itens: unknown[], contexto: Record<string, unknown> = {}) {
  const total = { inseridos: 0, atualizados: 0 };
  for (let i = 0; i < itens.length; i += POR_LOTE) {
    const r = await gravar(sb, entidade, itens.slice(i, i + POR_LOTE), contexto);
    total.inseridos += r.inseridos ?? 0;
    total.atualizados += r.atualizados ?? 0;
  }
  return total;
}

async function estado(sb: SupabaseClient, fonte: string, patch: Record<string, unknown> | null = null) {
  const { data, error } = await sb.rpc("learnworlds_espelho_estado", { p_fonte: fonte, p_patch: patch });
  if (error) throw new Error(`estado ${fonte}: ${error.message}`);
  return (data ?? {}) as Record<string, unknown>;
}

// Pessoas: 200 por página, da mais recente para a mais antiga. Quem se cadastra no meio da varredura
// empurra as outras para a frente: a varredura pode reler alguém, mas não pula ninguém.
async function sincronizarUsuarios(sb: SupabaseClient, lw: LearnWorlds, prazo: number) {
  const fonte = "learnworlds_usuarios";
  const atual = await estado(sb, fonte);
  let pagina = atual.status === "parcial" ? Number(atual.cursor ?? 1) || 1 : 1;
  let lidos = atual.status === "parcial" ? Number(atual.registros_lidos ?? 0) : 0;
  let gravados = atual.status === "parcial" ? Number(atual.registros_gravados ?? 0) : 0;
  await estado(sb, fonte, {
    status: "rodando", tabela_destino: "learnworlds.usuarios", chave_destino: "id",
    ...(atual.status === "parcial" ? {} : { iniciado_em: new Date().toISOString() }),
  });
  for (;;) {
    const p = await lw.pagina("/users", { page: pagina, items_per_page: POR_PAGINA, include_suspended: "true" });
    const itens = p.data ?? [];
    const r = await gravarEmLotes(sb, "usuarios", itens);
    lidos += itens.length;
    gravados += (r.inseridos ?? 0) + (r.atualizados ?? 0);
    const ultima = !itens.length || pagina >= (p.meta?.totalPages ?? 1);
    if (ultima) {
      await estado(sb, fonte, {
        status: "concluido", cursor: null, registros_lidos: lidos, registros_gravados: gravados,
        concluido_em: new Date().toISOString(), carga_completa_em: new Date().toISOString(), erro: null,
      });
      return { completo: true, paginas: pagina, lidos };
    }
    pagina++;
    if (Date.now() > prazo) {
      await estado(sb, fonte, { status: "parcial", cursor: String(pagina), registros_lidos: lidos, registros_gravados: gravados });
      return { completo: false, proxima_pagina: pagina, lidos };
    }
  }
}

// Matrículas: produto a produto (cursos, bundles e planos). Ao terminar a lista de um produto, quem
// não apareceu nela fica marcado como ausente (saiu do curso no LearnWorlds). Cursor: produto e página.
async function sincronizarMatriculas(sb: SupabaseClient, lw: LearnWorlds, produtos: Produto[], prazo: number) {
  const fonte = "learnworlds_matriculas";
  const atual = await estado(sb, fonte);
  let pos = { produto: 0, pagina: 1, inicio: new Date().toISOString() };
  if (atual.status === "parcial" && typeof atual.cursor === "string") {
    try { pos = { ...pos, ...JSON.parse(atual.cursor) }; } catch { /* recomeça */ }
  }
  let lidos = atual.status === "parcial" ? Number(atual.registros_lidos ?? 0) : 0;
  await estado(sb, fonte, {
    status: "rodando", tabela_destino: "learnworlds.matriculas", chave_destino: "usuario_id,produto_tipo,produto_id",
    ...(atual.status === "parcial" ? {} : { iniciado_em: pos.inicio }),
  });
  while (pos.produto < produtos.length) {
    const prod = produtos[pos.produto];
    let p: Pagina;
    try {
      p = prod.tipo === "course"
        ? await lw.pagina(`/courses/${encodeURIComponent(prod.id)}/users`, {
          page: pos.pagina, items_per_page: POR_PAGINA, include_suspended: "true",
        })
        : await lw.pagina("/users/by-product", {
          product_id: prod.id, product_type: prod.tipo, page: pos.pagina, include_suspended: "true",
        });
    } catch (e) {
      // Produto sem ninguém: o LearnWorlds responde 404 "not found".
      if (!(e instanceof ErroLW && e.status === 404 && /not found/i.test(e.corpo))) throw e;
      p = { data: [], meta: { totalPages: 1 } };
    }
    const itens = p.data ?? [];
    await gravarEmLotes(sb, "matriculas", itens, { produto_id: prod.id, produto_tipo: prod.tipo });
    lidos += itens.length;
    if (!itens.length || pos.pagina >= (p.meta?.totalPages ?? 1)) {
      await gravar(sb, "matriculas_fim", [], { produto_id: prod.id, produto_tipo: prod.tipo, inicio: pos.inicio });
      pos = { ...pos, produto: pos.produto + 1, pagina: 1 };
    } else {
      pos = { ...pos, pagina: pos.pagina + 1 };
    }
    if (pos.produto < produtos.length && Date.now() > prazo) {
      await estado(sb, fonte, { status: "parcial", cursor: JSON.stringify(pos), registros_lidos: lidos });
      return { completo: false, produto: pos.produto, de: produtos.length, lidos };
    }
  }
  await estado(sb, fonte, {
    status: "concluido", cursor: null, registros_lidos: lidos, registros_gravados: lidos,
    concluido_em: new Date().toISOString(), carga_completa_em: new Date().toISOString(), erro: null,
  });
  return { completo: true, produtos: produtos.length, lidos };
}

Deno.serve(async (req: Request) => {
  const inicio = Date.now();
  const prazo = inicio + ORCAMENTO_MS;
  if (req.method !== "POST") return json(405, { ok: false, error: "method_not_allowed" });

  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { data: cfg } = await sb.rpc("analise_config");
  const esperado = cfg?.analise_token as string | undefined;
  const url = new URL(req.url);
  if (!esperado || url.searchParams.get("token") !== esperado) {
    return json(401, { ok: false, error: "unauthorized" });
  }

  const clientId = Deno.env.get("LEARNWORLDS_CLIENT_ID") ?? "";
  const clientSecret = Deno.env.get("LEARNWORLDS_CLIENT_SECRET") ?? "";
  const faltam = [!clientId && "LEARNWORLDS_CLIENT_ID", !clientSecret && "LEARNWORLDS_CLIENT_SECRET"].filter(Boolean);
  if (faltam.length) return json(503, { ok: false, error: "secrets_ausentes", faltam, version: VERSION });
  const base = (Deno.env.get("LEARNWORLDS_API_URL") || API_PADRAO).replace(/\/+$/, "");

  try {
    const lw = await LearnWorlds.conectar(base, clientId, clientSecret);

    if (url.searchParams.get("modo") === "diagnostico") {
      const cursos = await lw.tudo("/courses");
      const bundles = await lw.tudo("/bundles");
      const planos = await lw.tudo("/subscription-plans");
      const usuarios = await lw.pagina("/users", { page: 1, items_per_page: 1 });
      return json(200, {
        ok: true, version: VERSION, base, modo: "diagnostico",
        cursos: cursos.map((c) => ({ id: c.id, titulo: c.title, acesso: c.access })),
        bundles: bundles.map((b) => ({ id: b.id, titulo: b.title, acesso: b.access, produtos: b.products })),
        planos: planos.map((p) => ({ id: p.id, titulo: p.title, acesso: p.access })),
        usuarios_meta: usuarios.meta,
        chaves_usuario: Object.keys(usuarios.data?.[0] ?? {}),
        ms: Date.now() - inicio,
      });
    }

    // Cursos e programas são poucos: relidos inteiros a cada rodada.
    const cursos = await lw.tudo("/courses");
    const rCursos = await gravar(sb, "cursos", cursos);
    const bundles = await lw.tudo("/bundles");
    const rBundles = await gravar(sb, "programas", bundles, { tipo: "bundle" });
    const planos = await lw.tudo("/subscription-plans");
    const rPlanos = await gravar(sb, "programas", planos, { tipo: "subscription" });

    const usuarios = await sincronizarUsuarios(sb, lw, prazo);
    let matriculas: unknown = { adiada: "a varredura de pessoas ainda não terminou" };
    if (usuarios.completo && Date.now() < prazo) {
      const produtos: Produto[] = [
        ...cursos.map((c) => ({ id: String(c.id), tipo: "course" as const })),
        ...bundles.map((b) => ({ id: String(b.id), tipo: "bundle" as const })),
        ...planos.map((p) => ({ id: String(p.id), tipo: "subscription" as const })),
      ];
      matriculas = await sincronizarMatriculas(sb, lw, produtos, prazo);
    }

    return json(200, {
      ok: true, version: VERSION,
      cursos: { lidos: cursos.length, ...rCursos },
      programas: { bundles: bundles.length, planos: planos.length, ...rBundles, planos_gravados: rPlanos },
      usuarios, matriculas, ms: Date.now() - inicio,
    });
  } catch (e) {
    const erro = e instanceof ErroLW
      ? { onde: e.onde, status: e.status, corpo: e.corpo }
      : { mensagem: e instanceof Error ? e.message : String(e) };
    console.error(JSON.stringify({ event: "learnworlds_sync_falhou", ...erro }));
    return json(502, { ok: false, error: "learnworlds_sync_falhou", ...erro, version: VERSION, ms: Date.now() - inicio });
  }
});
