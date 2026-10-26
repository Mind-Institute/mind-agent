/* ============================================================
   mindagent-summit — as tabelas do Summit no painel
   ============================================================
   Pedido da Adriana, 26/09/2026: no menu SUMMIT, "Mind Summit 2026", e
   dentro dele a tabela de programação "conforme está no backend". Esta
   função serve o que o menu do Summit mostrar; hoje, só a programação.

   ROTAS

     GET   /admin/summit_2026_sessions        lista, com busca, filtros, ordem e paginação
     GET   /admin/summit_2026_sessions/:id    uma sessão
     GET   /health

   SÓ LEITURA. Quem lê é quem entra no painel, com qualquer papel — a mesma
   verificação da `mindagent-catalogo` (`mind_admin_users`). O banco devolve
   a sessão como está em `summit_2026.sessions`, mais o nome do espaço e dos
   palestrantes (`mind_admin_read_summit_2026_sessoes`, só service_role).

   O CONTRATO É O MESMO das outras funções do painel — `{itens,total,
   pagina,porPagina}` na lista, registro cru no resto, os mesmos códigos
   de erro —, porque o painel usa o mesmo cliente HTTP para todas.
*/

import { createClient } from "npm:@supabase/supabase-js@2.112.3";

type AdminRole = "administrador" | "editor" | "aprovador" | "atendimento" | "analista";
type AccessRecord = { display_name: string | null; role: AdminRole; active: boolean };

/* O painel em desenvolvimento, na porta de sempre. */
const DEFAULT_ORIGINS = new Set(["http://localhost:5174", "http://127.0.0.1:5174"]);

/* O worker publicado E os previews de branch — o mesmo recorte da `mindagent-catalogo`. */
const WORKER = /^https:\/\/(?:[a-z0-9][a-z0-9-]*-)?mind-agent\.adriana-3eb\.workers\.dev$/;

const PAPEIS: AdminRole[] = ["administrador", "editor", "aprovador", "atendimento", "analista"];

/* Recurso do painel → porta de leitura no banco. Tabela nova do Summit entra aqui. */
const RECURSOS: Record<string, string> = {
  summit_2026_sessions: "mind_admin_read_summit_2026_sessoes",
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function lerChave(nome: "SUPABASE_PUBLISHABLE_KEYS" | "SUPABASE_SECRET_KEYS", alternativa: string) {
  const cru = Deno.env.get(nome);
  if (cru) {
    try {
      const lido = JSON.parse(cru) as Record<string, unknown>;
      if (typeof lido.default === "string") return lido.default;
      const primeira = Object.values(lido).find((v) => typeof v === "string");
      if (typeof primeira === "string") return primeira;
    } catch { /* formato antigo, cai no fallback */ }
  }
  return Deno.env.get(alternativa) ?? "";
}

function origemPermitida(origem: string | null) {
  if (!origem) return true;
  if (WORKER.test(origem)) return true;
  if (DEFAULT_ORIGINS.has(origem)) return true;
  return (Deno.env.get("ADMIN_ALLOWED_ORIGINS") ?? "")
    .split(",").map((v) => v.trim()).filter(Boolean).includes(origem);
}

function cabecalhosCors(req: Request) {
  const origem = req.headers.get("Origin");
  return {
    "Access-Control-Allow-Origin": origemPermitida(origem) && origem ? origem : "null",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Expose-Headers": "x-request-id",
    "Vary": "Origin",
  };
}

function json(req: Request, status: number, corpo: unknown, requestId: string) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: {
      ...cabecalhosCors(req),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "X-Request-Id": requestId,
    },
  });
}

/* Tira os acentos sem escape unicode no código: o caminho de publicação
   converte o escape no caractere invisível, e a versão no ar deixaria de
   bater com a do repositório. */
function semAcento(v: unknown) {
  return [...String(v ?? "").normalize("NFD")]
    .filter((c) => { const p = c.codePointAt(0) ?? 0; return p < 0x300 || p > 0x36f; })
    .join("").toLowerCase();
}

/* Busca e filtros da tela. O filtro chega como texto na query string:
   `dia=2026-09-16`, `espaco_id=null` (sem espaço), `precisa_reserva=true`. */
function combina(item: Record<string, unknown>, url: URL) {
  const busca = semAcento(url.searchParams.get("busca"));
  if (busca) {
    const palestrantes = Array.isArray(item.palestrantes) ? item.palestrantes : [];
    if (![item.titulo, item.descricao, item.espaco, ...palestrantes].some((v) => semAcento(v).includes(busca))) {
      return false;
    }
  }
  for (const chave of ["dia", "tipo", "espaco_id", "precisa_reserva"]) {
    const pedido = url.searchParams.get(chave);
    if (!pedido || pedido === "todos") continue;
    const valor = item[chave];
    if (pedido === "null" ? valor !== null && valor !== undefined : String(valor) !== pedido) return false;
  }
  return true;
}

/* As colunas que a tela ordena. */
const CAMPOS_ORDEM = new Set([
  "dia", "inicio", "fim", "titulo", "tipo", "espaco", "precisa_reserva",
  "vagas_total", "vagas_disponiveis", "duracao_min", "atualizado_em",
]);

/* Instante compara como instante; número como número; o resto como texto,
   no alfabeto do português. Vazio vai para o fim nos dois sentidos. */
const INSTANTE = /^\d{4}-\d{2}-\d{2}T/;

function comparar(a: unknown, b: unknown) {
  if (typeof a === "number" && typeof b === "number") return a === b ? 0 : a < b ? -1 : 1;
  if (typeof a === "string" && typeof b === "string" && INSTANTE.test(a) && INSTANTE.test(b)) {
    const ta = Date.parse(a);
    const tb = Date.parse(b);
    if (!Number.isNaN(ta) && !Number.isNaN(tb)) return ta === tb ? 0 : ta < tb ? -1 : 1;
  }
  return String(a).localeCompare(String(b), "pt-BR");
}

function ordenar(itens: Record<string, unknown>[], pedido: string | null) {
  /* Sem pedido, fica a ordem do banco: dia, início, título. */
  const cru = pedido ?? "";
  const desc = cru.startsWith("-");
  const campo = desc ? cru.slice(1) : cru;
  if (!campo || !CAMPOS_ORDEM.has(campo)) return itens;
  const vazio = (v: unknown) => v === null || v === undefined || v === "";
  return [...itens].sort((a, b) => {
    const x = a[campo];
    const y = b[campo];
    if (vazio(x) || vazio(y)) return vazio(x) === vazio(y) ? 0 : vazio(x) ? 1 : -1;
    return comparar(x, y) * (desc ? -1 : 1);
  });
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const url = new URL(req.url);
  const partes = url.pathname.split("/").filter(Boolean);

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cabecalhosCors(req) });
  }
  if (req.method === "GET" && partes.at(-1) === "health") {
    return json(req, 200, { ok: true, service: "mindagent-summit", version: "1.0.0" }, requestId);
  }

  const origem = req.headers.get("Origin");
  if (!origemPermitida(origem)) {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Origem não autorizada." }, requestId);
  }
  if (req.method !== "GET") {
    return json(req, 405, { codigo: "validacao", mensagem: "As tabelas do Summit são só leitura no painel." }, requestId);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const chavePublicavel = lerChave("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY");
  const chaveSecreta = lerChave("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !chavePublicavel || !chaveSecreta) {
    return json(req, 503, { codigo: "indisponivel", mensagem: "Serviço indisponível." }, requestId);
  }

  const token = (req.headers.get("Authorization") ?? "").match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return json(req, 401, { codigo: "sessao_expirada", mensagem: "Sessão ausente." }, requestId);

  const comChavePublica = createClient(supabaseUrl, chavePublicavel, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: usuario, error: erroUsuario } = await comChavePublica.auth.getUser(token);
  if (erroUsuario || !usuario.user) {
    return json(req, 401, { codigo: "sessao_expirada", mensagem: "Sessão inválida ou expirada." }, requestId);
  }

  const comSegredo = createClient(supabaseUrl, chaveSecreta, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: acesso, error: erroAcesso } = await comSegredo
    .from("mind_admin_users").select("display_name,role,active")
    .eq("user_id", usuario.user.id).maybeSingle<AccessRecord>();
  if (erroAcesso) {
    return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível validar a permissão." }, requestId);
  }
  if (!acesso?.active || !PAPEIS.includes(acesso.role)) {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Usuário sem acesso ao painel." }, requestId);
  }

  const iAdmin = partes.lastIndexOf("admin");
  const recurso = iAdmin >= 0 ? partes[iAdmin + 1] : undefined;
  const id = iAdmin >= 0 ? partes[iAdmin + 2] : undefined;
  const sobra = iAdmin >= 0 ? partes[iAdmin + 3] : undefined;
  const porta = recurso ? RECURSOS[recurso] : undefined;

  if (!porta || sobra) {
    return json(req, 404, { codigo: "nao_encontrado", mensagem: "Rota não encontrada." }, requestId);
  }
  if (id && !UUID.test(id)) {
    return json(req, 404, { codigo: "nao_encontrado", mensagem: "Registro não encontrado." }, requestId);
  }

  const { data, error } = await comSegredo.rpc(porta, { p_id: id ?? null });
  if (error) {
    console.error(JSON.stringify({ request_id: requestId, error: "summit_rpc_failed", code: error.code ?? null }));
    return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível ler a tabela." }, requestId);
  }

  const itens = (Array.isArray(data) ? data : []) as Record<string, unknown>[];
  if (id) {
    return itens[0]
      ? json(req, 200, itens[0], requestId)
      : json(req, 404, { codigo: "nao_encontrado", mensagem: "Registro não encontrado." }, requestId);
  }
  const filtrados = ordenar(itens.filter((i) => combina(i, url)), url.searchParams.get("ordenar"));
  const pagina = Math.max(1, Number(url.searchParams.get("pagina") ?? 1) || 1);
  const porPagina = Math.min(500, Math.max(1, Number(url.searchParams.get("porPagina") ?? 100) || 100));
  const inicio = (pagina - 1) * porPagina;
  return json(req, 200, {
    itens: filtrados.slice(inicio, inicio + porPagina),
    total: filtrados.length, pagina, porPagina,
  }, requestId);
});
