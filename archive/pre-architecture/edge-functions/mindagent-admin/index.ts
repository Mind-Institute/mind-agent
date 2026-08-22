import { createClient } from "npm:@supabase/supabase-js@2.112.3";

type AdminRole = "administrador" | "editor" | "aprovador" | "atendimento" | "analista";
type AccessRecord = { display_name: string | null; role: AdminRole; active: boolean };
type DashboardCounts = Record<string, number | string> & { generated_at: string };

const DEFAULT_ORIGINS = new Set(["http://localhost:5174", "http://127.0.0.1:5174", "https://mind-agent.adriana-3eb.workers.dev"]);
const RESOURCES = new Set(["event", "sessions", "speakers", "spaces", "themes"]);
const ROLE_ACTIONS: Record<AdminRole, Set<string>> = {
  administrador: new Set(["view", "edit", "create", "publish", "archive", "reindex", "manage_users", "view_audit", "view_conversations", "configure"]),
  editor: new Set(["view", "edit", "create", "reindex", "view_conversations"]),
  aprovador: new Set(["view", "edit", "publish", "archive", "view_audit", "view_conversations"]),
  atendimento: new Set(["view", "view_conversations"]),
  analista: new Set(["view", "view_audit"]),
};

function readKey(name: "SUPABASE_PUBLISHABLE_KEYS" | "SUPABASE_SECRET_KEYS", fallback: string) {
  const raw = Deno.env.get(name);
  if (raw) try {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    if (typeof parsed.default === "string") return parsed.default;
    const first = Object.values(parsed).find((value) => typeof value === "string");
    if (typeof first === "string") return first;
  } catch { /* legacy fallback */ }
  return Deno.env.get(fallback) ?? "";
}

function allowedOrigins() {
  const configured = (Deno.env.get("ADMIN_ALLOWED_ORIGINS") ?? "").split(",").map((v) => v.trim()).filter(Boolean);
  return new Set([...DEFAULT_ORIGINS, ...configured]);
}

function corsHeaders(req: Request) {
  const origin = req.headers.get("Origin");
  const allowed = !origin || allowedOrigins().has(origin);
  return {
    "Access-Control-Allow-Origin": allowed && origin ? origin : "null",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, if-unmodified-since-version",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
    "Access-Control-Expose-Headers": "x-request-id",
    "Vary": "Origin",
  };
}

function json(req: Request, status: number, body: unknown, requestId: string) {
  return new Response(JSON.stringify(body), { status, headers: {
    ...corsHeaders(req), "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff", "X-Request-Id": requestId,
  }});
}

function metric(chave: string, rotulo: string, valor: number, destino: string, tom: "neutro" | "atencao" = "neutro") {
  return { chave, rotulo, valor, destino, tom };
}
function pendingGroup(categoria: string, titulo: string, descricao: string, total: number, destino: string) {
  return { categoria, titulo, descricao, total, itens: [], destino };
}
function dashboardPayload(c: DashboardCounts) {
  const n = (key: string) => Number(c[key] ?? 0);
  return {
    metricas: [
      metric("sessions", "Sessões", n("sessions"), "/programacao"), metric("speakers", "Palestrantes", n("speakers"), "/palestrantes"),
      metric("spaces", "Espaços", n("spaces"), "/espacos"), metric("booths", "Estandes", n("booths"), "/estandes"),
      metric("offers", "Ofertas ativas", n("active_offers"), "/ofertas"), metric("documents", "Documentos publicados", n("documents"), "/documentos"),
      metric("documents_pending", "Documentos aguardando indexação", n("documents_pending"), "/documentos", n("documents_pending") > 0 ? "atencao" : "neutro"),
      metric("unanswered", "Perguntas sem resposta", n("unanswered"), "/perguntas", n("unanswered") > 0 ? "atencao" : "neutro"),
      metric("conversations_24h", "Conversas nas últimas 24 horas", n("conversations_24h"), "/conversas"),
    ],
    pendencias: [
      pendingGroup("sessoes_sem_espaco", "Sessões sem espaço", "Sessões que ainda não têm local definido.", n("sessions_without_space"), "/programacao?espacoId=null"),
      pendingGroup("sessoes_sem_palestrante", "Sessões sem palestrante", "Sessões sem pessoa vinculada.", n("sessions_without_speaker"), "/programacao"),
      pendingGroup("espacos_sem_localizacao", "Espaços sem localização", "Espaços sem instrução de como chegar.", n("spaces_without_directions"), "/espacos"),
      pendingGroup("palcos_sem_alias", "Palcos sem aliases", "Palcos que podem não ser encontrados por nomes alternativos.", n("stages_without_alias"), "/espacos"),
      pendingGroup("ofertas_sem_checkout", "Ofertas sem checkout", "Ofertas ativas sem URL de compra.", n("offers_without_checkout"), "/ofertas"),
      pendingGroup("documentos_sem_indexacao", "Documentos sem indexação", "Documentos ainda indisponíveis para busca semântica.", n("documents_pending"), "/documentos"),
    ].filter((g) => g.total > 0),
    alertas: n("documents_pending") > 0 ? [{ id: "documents_pending", nivel: "atencao", titulo: "Documentos aguardando indexação", descricao: `${n("documents_pending")} documento(s) ainda não estão prontos para consulta pelos agentes.`, destino: "/documentos" }] : [],
    geradoEm: c.generated_at,
  };
}

function normalized(value: unknown) {
  return String(value ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}
function matches(resource: string, item: Record<string, unknown>, url: URL) {
  const busca = normalized(url.searchParams.get("busca"));
  if (busca) {
    const haystack = resource === "sessions" ? [item.titulo, item.descricao, item.quemTexto]
      : resource === "speakers" ? [item.nome, item.cargo, item.organizacao]
      : resource === "spaces" ? [item.nome, item.descricao, item.comoChegar, ...(Array.isArray(item.aliases) ? item.aliases : [])]
      : [item.nome, item.local, item.cidade];
    if (!haystack.some((v) => normalized(v).includes(busca))) return false;
  }
  const equal = (param: string, field: string) => {
    const wanted = url.searchParams.get(param); if (!wanted) return true;
    if (wanted === "null") return item[field] === null || item[field] === "";
    return String(item[field]) === wanted;
  };
  if (!equal("dia", "dia") || !equal("espacoId", "espacoId") || !equal("tipo", "tipo") || !equal("status", "status") || !equal("ativo", "ativo")) return false;
  const contains = (param: string, field: string) => {
    const wanted = url.searchParams.get(param); if (!wanted) return true;
    return Array.isArray(item[field]) && (item[field] as unknown[]).map(String).includes(wanted);
  };
  return contains("tema", "temas") && contains("palestranteId", "palestranteIds");
}

const SORT_FIELDS: Record<string, Set<string>> = {
  event: new Set(["nome", "atualizadoEm"]), sessions: new Set(["dia", "inicio", "titulo", "atualizadoEm"]),
  speakers: new Set(["nome", "atualizadoEm"]), spaces: new Set(["nome", "tipo", "atualizadoEm"]), themes: new Set(["codigo", "rotulo"]),
};
function sortItems(resource: string, items: Record<string, unknown>[], requested: string | null) {
  const raw = requested || (resource === "sessions" ? "dia" : resource === "themes" ? "codigo" : "nome");
  const desc = raw.startsWith("-"); const field = desc ? raw.slice(1) : raw;
  if (!SORT_FIELDS[resource]?.has(field)) return items;
  return [...items].sort((a, b) => String(a[field] ?? "").localeCompare(String(b[field] ?? ""), "pt-BR") * (desc ? -1 : 1));
}

async function body(req: Request) {
  const length = Number(req.headers.get("content-length") ?? 0);
  if (length > 1_000_000) throw new Error("body_too_large");
  const value = await req.json();
  if (!value || Array.isArray(value) || typeof value !== "object") throw new Error("invalid_body");
  return value as Record<string, unknown>;
}

function rpcError(req: Request, error: { message?: string; code?: string }, requestId: string) {
  const message = error.message ?? "";
  if (message.includes("admin_conflict")) return json(req, 409, { codigo: "conflito", mensagem: "O registro foi alterado por outra pessoa. Recarregue antes de salvar." }, requestId);
  if (message.includes("admin_forbidden") || error.code === "42501") return json(req, 403, { codigo: "sem_permissao", mensagem: "Você não tem permissão para esta operação." }, requestId);
  if (message.includes("admin_not_found") || error.code === "P0002") return json(req, 404, { codigo: "nao_encontrado", mensagem: "Registro não encontrado." }, requestId);
  if (message.includes("admin_validation") || error.code === "22023") return json(req, 422, { codigo: "validacao", mensagem: "Revise os campos enviados." }, requestId);
  console.error(JSON.stringify({ request_id: requestId, error: "admin_rpc_failed", code: error.code ?? null }));
  return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível concluir a operação." }, requestId);
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const origin = req.headers.get("Origin");
  if (origin && !allowedOrigins().has(origin)) return json(req, 403, { codigo: "sem_permissao", mensagem: "Origem não autorizada." }, requestId);
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });

  const url = new URL(req.url); const parts = url.pathname.split("/").filter(Boolean);
  if (req.method === "GET" && parts.at(-1) === "health") return json(req, 200, { ok: true, service: "mindagent-admin", version: "2.0.0" }, requestId);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const publishableKey = readKey("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY");
  const secretKey = readKey("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !publishableKey || !secretKey) return json(req, 503, { codigo: "indisponivel", mensagem: "API administrativa indisponível." }, requestId);

  const token = (req.headers.get("Authorization") ?? "").match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return json(req, 401, { codigo: "sessao_expirada", mensagem: "Sessão ausente." }, requestId);
  const authClient = createClient(supabaseUrl, publishableKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await authClient.auth.getUser(token);
  if (userError || !userData.user) return json(req, 401, { codigo: "sessao_expirada", mensagem: "Sessão inválida ou expirada." }, requestId);

  const adminClient = createClient(supabaseUrl, secretKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: access, error: accessError } = await adminClient.from("mind_admin_users").select("display_name,role,active").eq("user_id", userData.user.id).maybeSingle<AccessRecord>();
  if (accessError) return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível validar a permissão." }, requestId);
  if (!access?.active || !ROLE_ACTIONS[access.role]) return json(req, 403, { codigo: "sem_permissao", mensagem: "Usuário sem acesso ao painel." }, requestId);

  const adminIndex = parts.lastIndexOf("admin"); const resource = adminIndex >= 0 ? parts[adminIndex + 1] : undefined;
  const id = adminIndex >= 0 ? parts[adminIndex + 2] : undefined; const action = adminIndex >= 0 ? parts[adminIndex + 3] : undefined;
  if (resource === "me" && req.method === "GET") return json(req, 200, { id: userData.user.id, nome: access.display_name ?? "Administrador", email: userData.user.email ?? null, papel: access.role, ativo: access.active }, requestId);
  if (resource === "dashboard" && req.method === "GET") {
    const { data, error } = await adminClient.rpc("mind_admin_dashboard_counts");
    return error || !data ? rpcError(req, error ?? {}, requestId) : json(req, 200, dashboardPayload(data as DashboardCounts), requestId);
  }
  if (!resource || !RESOURCES.has(resource)) return json(req, 404, { codigo: "nao_encontrado", mensagem: "Rota administrativa não encontrada." }, requestId);
  if (!ROLE_ACTIONS[access.role].has("view")) return json(req, 403, { codigo: "sem_permissao", mensagem: "Sem permissão para visualizar este recurso." }, requestId);

  if (req.method === "GET") {
    const { data, error } = await adminClient.rpc("mind_admin_read_resource", { p_resource: resource, p_id: id ?? null });
    if (error) return rpcError(req, error, requestId);
    const items = (Array.isArray(data) ? data : []) as Record<string, unknown>[];
    if (id) return items[0] ? json(req, 200, items[0], requestId) : json(req, 404, { codigo: "nao_encontrado", mensagem: "Registro não encontrado." }, requestId);
    const filtered = sortItems(resource, items.filter((item) => matches(resource, item, url)), url.searchParams.get("ordenar"));
    const pagina = Math.max(1, Number(url.searchParams.get("pagina") ?? 1) || 1);
    const porPagina = Math.min(200, Math.max(1, Number(url.searchParams.get("porPagina") ?? 100) || 100));
    const start = (pagina - 1) * porPagina;
    return json(req, 200, { itens: filtered.slice(start, start + porPagina), total: filtered.length, pagina, porPagina }, requestId);
  }

  let requiredAction: string; let dbAction: string; let payload: Record<string, unknown> = {};
  try { payload = await body(req); } catch { return json(req, 422, { codigo: "validacao", mensagem: "Corpo JSON inválido." }, requestId); }
  if (req.method === "POST" && !id) { requiredAction = "create"; dbAction = "criar"; }
  else if (req.method === "PATCH" && id && !action) { requiredAction = "edit"; dbAction = "atualizar"; }
  else if (req.method === "POST" && id && action === "publish") { requiredAction = "publish"; dbAction = "publicar"; }
  else if (req.method === "POST" && id && action === "archive") { requiredAction = "archive"; dbAction = "arquivar"; }
  else return json(req, 405, { codigo: "validacao", mensagem: "Método não permitido para esta rota." }, requestId);
  if (!ROLE_ACTIONS[access.role].has(requiredAction)) return json(req, 403, { codigo: "sem_permissao", mensagem: "Você não tem permissão para esta operação." }, requestId);
  if (resource === "themes") return json(req, 405, { codigo: "validacao", mensagem: "Temas são somente leitura nesta etapa." }, requestId);

  const expected = req.headers.get("If-Unmodified-Since-Version") ?? (typeof payload.atualizadoEmEsperado === "string" ? payload.atualizadoEmEsperado : null);
  const { data, error } = await adminClient.rpc("mind_admin_mutate_resource", {
    p_action: dbAction, p_resource: resource, p_id: id ?? null, p_payload: payload,
    p_expected_updated_at: expected, p_actor_id: userData.user.id, p_request_id: requestId,
  });
  if (error) return rpcError(req, error, requestId);
  return json(req, dbAction === "criar" ? 201 : 200, data, requestId);
});

