/* ============================================================
   mindagent-knowledge — control plane de Knowledge/RAG no Admin
   ============================================================

   Serve apenas o painel administrativo. O navegador nunca acessa
   ecossistema.* diretamente; a função valida a sessão do admin e usa
   portas RPC fechadas para service_role.

   ROTAS
     GET   /admin/knowledge_collections
     GET   /admin/knowledge_collections/:id
     GET   /admin/knowledge_sources
     GET   /admin/knowledge_assets
     GET   /admin/knowledge_assets/:id
     GET   /admin/agent_knowledge_access
     GET   /admin/agent_knowledge_access/:id
     PATCH /admin/agent_knowledge_access/:id
     GET   /admin/business_intelligence
     GET   /admin/customer_intelligence
     GET   /admin/agent_intelligence_access
     PATCH /admin/agent_intelligence_access/:id
     POST  /admin/knowledge_search
     GET   /health
*/

import { createClient } from "npm:@supabase/supabase-js@2.112.3";

type AdminRole = "administrador" | "editor" | "aprovador" | "atendimento" | "analista";
type AccessRecord = { display_name: string | null; role: AdminRole; active: boolean };

const DEFAULT_ORIGINS = new Set(["http://localhost:5174", "http://127.0.0.1:5174"]);
const WORKER = /^https:\/\/(?:[a-z0-9][a-z0-9-]*-)?mind-agent\.adriana-3eb\.workers\.dev$/;
const PAPEIS: AdminRole[] = ["administrador", "editor", "aprovador", "atendimento", "analista"];

const RECURSOS = {
  knowledge_collections: { ler: "mind_admin_read_knowledge_collections", idParam: "p_chave" },
  knowledge_sources: { ler: "mind_admin_read_knowledge_sources", idParam: "p_id" },
  knowledge_assets: { ler: "mind_admin_read_knowledge_assets", idParam: "p_id" },
  agent_knowledge_access: { ler: "mind_admin_read_agent_knowledge_access", idParam: "p_id" },
  business_intelligence: { ler: "mind_admin_read_business_intelligence", idParam: "p_id" },
  customer_intelligence: { ler: "mind_admin_read_customer_intelligence", idParam: "p_id" },
  agent_intelligence_access: { ler: "mind_admin_read_agent_intelligence_access", idParam: "p_id" },
} as const;

function lerChave(nome: "SUPABASE_PUBLISHABLE_KEYS" | "SUPABASE_SECRET_KEYS", alternativa: string) {
  const cru = Deno.env.get(nome);
  if (cru) {
    try {
      const lido = JSON.parse(cru) as Record<string, unknown>;
      if (typeof lido.default === "string") return lido.default;
      const primeira = Object.values(lido).find((v) => typeof v === "string");
      if (typeof primeira === "string") return primeira;
    } catch { /* fallback */ }
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
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, if-unmodified-since-version",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
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

function semAcento(v: unknown) {
  return [...String(v ?? "").normalize("NFD")]
    .filter((c) => { const p = c.codePointAt(0) ?? 0; return p < 0x300 || p > 0x36f; })
    .join("").toLowerCase();
}

function combina(item: Record<string, unknown>, url: URL) {
  const busca = semAcento(url.searchParams.get("busca"));
  if (busca) {
    const serial = semAcento(JSON.stringify(item));
    if (!serial.includes(busca)) return false;
  }
  for (const [chave, pedido] of url.searchParams.entries()) {
    if (["busca","pagina","porPagina","ordenar"].includes(chave) || !pedido || pedido === "todos") continue;
    const valor = item[chave];
    if (Array.isArray(valor)) {
      if (!valor.map(String).includes(pedido)) return false;
    } else if (String(valor ?? "") !== pedido) {
      return false;
    }
  }
  return true;
}

function comparar(a: unknown, b: unknown) {
  if (typeof a === "number" && typeof b === "number") return a === b ? 0 : a < b ? -1 : 1;
  return String(a ?? "").localeCompare(String(b ?? ""), "pt-BR");
}

function ordenar(itens: Record<string, unknown>[], pedido: string | null) {
  if (!pedido) return itens;
  const desc = pedido.startsWith("-");
  const campo = desc ? pedido.slice(1) : pedido;
  return [...itens].sort((a,b) => comparar(a[campo], b[campo]) * (desc ? -1 : 1));
}

async function corpo(req: Request) {
  const tamanho = Number(req.headers.get("content-length") ?? 0);
  if (tamanho > 200_000) throw new Error("body_too_large");
  const valor = await req.json();
  if (!valor || Array.isArray(valor) || typeof valor !== "object") throw new Error("invalid_body");
  return valor as Record<string, unknown>;
}

async function embeddingDaQuery(query: string): Promise<number[] | null> {
  const apiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!apiKey) return null;
  const model = (Deno.env.get("OPENAI_EMBEDDING_MODEL") ?? "text-embedding-3-small").trim();
  try {
    const resposta = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        input: query,
        dimensions: 1536,
        encoding_format: "float",
      }),
    });
    if (!resposta.ok) return null;
    const valor = await resposta.json() as { data?: Array<{ embedding?: number[] }> };
    const embedding = valor.data?.[0]?.embedding;
    return Array.isArray(embedding) && embedding.length === 1536 ? embedding : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const url = new URL(req.url);
  const partes = url.pathname.split("/").filter(Boolean).map(decodeURIComponent);

  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cabecalhosCors(req) });
  if (req.method === "GET" && partes.at(-1) === "health") {
    return json(req, 200, { ok: true, service: "mindagent-knowledge", version: "1.0.0" }, requestId);
  }
  if (!origemPermitida(req.headers.get("Origin"))) {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Origem não autorizada." }, requestId);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const chavePublicavel = lerChave("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY");
  const chaveSecreta = lerChave("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !chavePublicavel || !chaveSecreta) {
    return json(req, 503, { codigo: "indisponivel", mensagem: "Serviço indisponível." }, requestId);
  }

  const token = (req.headers.get("Authorization") ?? "").match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return json(req, 401, { codigo: "sessao_expirada", mensagem: "Sessão ausente." }, requestId);

  const publico = createClient(supabaseUrl, chavePublicavel, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: usuario, error: erroUsuario } = await publico.auth.getUser(token);
  if (erroUsuario || !usuario.user) {
    return json(req, 401, { codigo: "sessao_expirada", mensagem: "Sessão inválida ou expirada." }, requestId);
  }

  const segredo = createClient(supabaseUrl, chaveSecreta, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: acesso, error: erroAcesso } = await segredo
    .from("mind_admin_users").select("display_name,role,active")
    .eq("user_id", usuario.user.id).maybeSingle<AccessRecord>();
  if (erroAcesso) return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível validar a permissão." }, requestId);
  if (!acesso?.active || !PAPEIS.includes(acesso.role)) {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Usuário sem acesso ao painel." }, requestId);
  }

  const iAdmin = partes.lastIndexOf("admin");
  const nome = iAdmin >= 0 ? partes[iAdmin + 1] : undefined;
  const id = iAdmin >= 0 ? partes[iAdmin + 2] : undefined;
  const sobra = iAdmin >= 0 ? partes[iAdmin + 3] : undefined;

  if (req.method === "POST" && nome === "knowledge_search" && !id && !sobra) {
    let payload: Record<string, unknown>;
    try { payload = await corpo(req); }
    catch { return json(req, 422, { codigo: "validacao", mensagem: "Corpo inválido." }, requestId); }

    const query = String(payload.query ?? "").trim();
    const agentKey = String(payload.agentKey ?? "knowledge_admin").trim();
    const limit = Math.min(30, Math.max(1, Number(payload.limit ?? 10) || 10));

    if (query.length < 2 || query.length > 4000 || !agentKey) {
      return json(req, 422, { codigo: "validacao", mensagem: "Informe uma consulta válida." }, requestId);
    }

    if (agentKey === "knowledge_admin" && !["administrador","editor","aprovador"].includes(acesso.role)) {
      return json(req, 403, { codigo: "sem_permissao", mensagem: "Seu papel não pode consultar o corpus interno completo." }, requestId);
    }

    const embedding = await embeddingDaQuery(query);
    let resultado = await segredo.rpc("mind_knowledge_buscar_global", {
      p_agent_key: agentKey,
      p_query: query,
      p_query_embedding: embedding,
      p_limit: limit,
    });

    // Se a serialização do vector falhar por configuração do gateway,
    // a busca lexical continua disponível em vez de derrubar o playground.
    if (resultado.error && embedding) {
      resultado = await segredo.rpc("mind_knowledge_buscar_global", {
        p_agent_key: agentKey,
        p_query: query,
        p_query_embedding: null,
        p_limit: limit,
      });
    }

    if (resultado.error) {
      console.error(JSON.stringify({
        request_id: requestId,
        error: "knowledge_search_failed",
        code: resultado.error.code ?? null,
      }));
      return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível buscar no Knowledge." }, requestId);
    }

    return json(req, 200, {
      itens: Array.isArray(resultado.data) ? resultado.data : [],
      query,
      agentKey,
      mode: embedding ? "hybrid" : "lexical",
    }, requestId);
  }

  const recurso = nome && Object.hasOwn(RECURSOS, nome) ? RECURSOS[nome as keyof typeof RECURSOS] : undefined;
  if (!recurso || sobra) return json(req, 404, { codigo: "nao_encontrado", mensagem: "Rota não encontrada." }, requestId);

  if (req.method === "GET") {
    const args: Record<string, unknown> = { [recurso.idParam]: id ?? null };
    const { data, error } = await segredo.rpc(recurso.ler, args);
    if (error) {
      console.error(JSON.stringify({ request_id: requestId, error: "knowledge_read_failed", code: error.code ?? null }));
      return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível ler Knowledge." }, requestId);
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
    return json(req, 200, { itens: filtrados.slice(inicio, inicio + porPagina), total: filtrados.length, pagina, porPagina }, requestId);
  }

  if (req.method === "PATCH" && nome === "agent_intelligence_access" && id) {
    if (!["administrador","editor","aprovador"].includes(acesso.role)) {
      return json(req, 403, { codigo: "sem_permissao", mensagem: "Seu papel não permite alterar Agent Intelligence." }, requestId);
    }
    let payload: Record<string, unknown>;
    try { payload = await corpo(req); }
    catch { return json(req, 422, { codigo: "validacao", mensagem: "Corpo inválido." }, requestId); }

    const [agentKey, namespace, ...knowledgeParts] = id.split("::");
    const knowledgeKey = knowledgeParts.join("::");
    if (!agentKey || !namespace || !knowledgeKey) {
      return json(req, 422, { codigo: "validacao", mensagem: "Identificador de acesso inválido." }, requestId);
    }

    const esperado = req.headers.get("If-Unmodified-Since-Version");
    const { data, error } = await segredo.rpc("mind_admin_upsert_agent_intelligence_access", {
      p_agent_key: agentKey,
      p_namespace: namespace,
      p_knowledge_key: knowledgeKey,
      p_enabled: Boolean(payload.enabled),
      p_priority: Number(payload.priority ?? 50),
      p_access_max: String(payload.accessMax ?? "mind_public"),
      p_customer_scope: payload.customerScope == null ? null : String(payload.customerScope),
      p_updated_at_expected: esperado || null,
    });
    if (error) {
      const m = error.message ?? "";
      if (m.includes("admin_conflict") || error.code === "40001") {
        return json(req, 409, { codigo: "conflito", mensagem: "Este acesso mudou. Recarregue antes de salvar." }, requestId);
      }
      if (m.includes("admin_not_found") || error.code === "P0002") {
        return json(req, 404, { codigo: "nao_encontrado", mensagem: "Knowledge não encontrada." }, requestId);
      }
      if (m.includes("admin_validation") || error.code === "22023") {
        return json(req, 422, { codigo: "validacao", mensagem: "Revise namespace, prioridade e escopo." }, requestId);
      }
      console.error(JSON.stringify({ request_id: requestId, error: "agent_intelligence_write_failed", code: error.code ?? null }));
      return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível salvar Agent Intelligence." }, requestId);
    }
    return json(req, 200, data, requestId);
  }

  if (req.method === "PATCH" && nome === "agent_knowledge_access" && id) {
    if (!["administrador","editor","aprovador"].includes(acesso.role)) {
      return json(req, 403, { codigo: "sem_permissao", mensagem: "Seu papel não permite alterar Knowledge." }, requestId);
    }
    let payload: Record<string, unknown>;
    try { payload = await corpo(req); }
    catch { return json(req, 422, { codigo: "validacao", mensagem: "Corpo inválido." }, requestId); }

    const [agentKey, collectionKey] = id.split("::");
    if (!agentKey || !collectionKey) {
      return json(req, 422, { codigo: "validacao", mensagem: "Identificador de acesso inválido." }, requestId);
    }
    const esperado = req.headers.get("If-Unmodified-Since-Version");
    const { data, error } = await segredo.rpc("mind_admin_upsert_agent_knowledge_access", {
      p_agent_key: agentKey,
      p_collection_key: collectionKey,
      p_enabled: Boolean(payload.enabled),
      p_prioridade: Number(payload.prioridade ?? 50),
      p_acesso_maximo: String(payload.acessoMaximo ?? "mind_public"),
      p_atualizado_em_esperado: esperado || null,
    });
    if (error) {
      const m = error.message ?? "";
      if (m.includes("admin_conflict") || error.code === "40001") {
        return json(req, 409, { codigo: "conflito", mensagem: "Este acesso mudou. Recarregue antes de salvar." }, requestId);
      }
      if (m.includes("admin_not_found") || error.code === "P0002") {
        return json(req, 404, { codigo: "nao_encontrado", mensagem: "Collection não encontrada." }, requestId);
      }
      if (m.includes("admin_validation") || error.code === "22023") {
        return json(req, 422, { codigo: "validacao", mensagem: "Revise prioridade e escopo de acesso." }, requestId);
      }
      console.error(JSON.stringify({ request_id: requestId, error: "knowledge_write_failed", code: error.code ?? null }));
      return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível salvar Knowledge." }, requestId);
    }
    return json(req, 200, data, requestId);
  }

  return json(req, 405, { codigo: "validacao", mensagem: "Operação não disponível para este recurso." }, requestId);
});
