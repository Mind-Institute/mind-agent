/* ============================================================
   mindagent-index-global-knowledge — embeddings do control plane
   ============================================================

   Indexa SOMENTE inteligência derivada em
   ecossistema.insights_conhecimento.

   Livros/documentos derived_only nunca entram aqui como texto bruto.
   A fila e a persistência passam por RPCs service-role-only:
     mind_knowledge_embedding_pending(limit)
     mind_knowledge_embedding_save(id, vector, model)

   Segurança:
   - exige sessão Supabase válida;
   - exige mind_admin_users ativo com papel de edição;
   - service_role fica somente no backend;
   - o navegador nunca envia texto bruto de fonte para este endpoint.
*/

import { createClient } from "npm:@supabase/supabase-js@2.112.3";

type AdminRole = "administrador" | "editor" | "aprovador" | "atendimento" | "analista";
type AccessRecord = { role: AdminRole; active: boolean };

const EDIT_ROLES = new Set<AdminRole>(["administrador", "editor", "aprovador"]);
const DEFAULT_ORIGINS = new Set(["http://localhost:5174", "http://127.0.0.1:5174"]);
const WORKER = /^https:\/\/(?:[a-z0-9][a-z0-9-]*-)?mind-agent\.adriana-3eb\.workers\.dev$/;

function lerChave(nome: "SUPABASE_PUBLISHABLE_KEYS" | "SUPABASE_SECRET_KEYS", alternativa: string) {
  const cru = Deno.env.get(nome);
  if (cru) {
    try {
      const lido = JSON.parse(cru) as Record<string, unknown>;
      if (typeof lido.default === "string") return lido.default;
      const primeira = Object.values(lido).find((v) => typeof v === "string");
      if (typeof primeira === "string") return primeira;
    } catch {
      // formato antigo: cai no fallback
    }
  }
  return Deno.env.get(alternativa) ?? "";
}

function origemPermitida(origem: string | null) {
  if (!origem) return true;
  if (WORKER.test(origem)) return true;
  if (DEFAULT_ORIGINS.has(origem)) return true;
  return (Deno.env.get("ADMIN_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((v) => v.trim())
    .filter(Boolean)
    .includes(origem);
}

function cors(req: Request) {
  const origem = req.headers.get("Origin");
  return {
    "Access-Control-Allow-Origin": origemPermitida(origem) && origem ? origem : "null",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(req: Request, status: number, corpo: unknown) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: {
      ...cors(req),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

type Pending = {
  id: string;
  texto: string;
  sourceId?: string;
  sectionId?: string | null;
  insightType?: string;
};

async function autenticarAdmin(req: Request) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const chavePublicavel = lerChave("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY");
  const chaveSecreta = lerChave("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !chavePublicavel || !chaveSecreta) {
    throw new Error("supabase_config_missing");
  }

  const token = (req.headers.get("Authorization") ?? "").match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return { status: 401 as const, erro: "Sessão ausente." };

  const publico = createClient(supabaseUrl, chavePublicavel, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: usuario, error: erroUsuario } = await publico.auth.getUser(token);
  if (erroUsuario || !usuario.user) return { status: 401 as const, erro: "Sessão inválida ou expirada." };

  const admin = createClient(supabaseUrl, chaveSecreta, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: acesso, error: erroAcesso } = await admin
    .from("mind_admin_users")
    .select("role,active")
    .eq("user_id", usuario.user.id)
    .maybeSingle<AccessRecord>();

  if (erroAcesso) throw new Error("admin_lookup_failed");
  if (!acesso?.active || !EDIT_ROLES.has(acesso.role)) {
    return { status: 403 as const, erro: "Usuário sem permissão para indexar Knowledge." };
  }

  return { status: 200 as const, admin };
}

async function embeddings(textos: string[], apiKey: string, model: string) {
  const resposta = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      input: textos,
      dimensions: 1536,
      encoding_format: "float",
    }),
  });

  if (!resposta.ok) {
    const detalhe = (await resposta.text()).slice(0, 600);
    throw new Error(`embedding_api_${resposta.status}:${detalhe}`);
  }

  const corpo = await resposta.json() as {
    data?: Array<{ index: number; embedding: number[] }>;
  };

  if (!Array.isArray(corpo.data) || corpo.data.length !== textos.length) {
    throw new Error("embedding_api_invalid_response");
  }
  return [...corpo.data].sort((a, b) => a.index - b.index).map((x) => x.embedding);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return json(req, 405, { codigo: "metodo", mensagem: "Use POST." });

  const origem = req.headers.get("Origin");
  if (!origemPermitida(origem)) return json(req, 403, { codigo: "origem", mensagem: "Origem não autorizada." });

  try {
    const auth = await autenticarAdmin(req);
    if (auth.status !== 200) return json(req, auth.status, { codigo: "sem_permissao", mensagem: auth.erro });

    const corpo = await req.json().catch(() => ({})) as { limit?: number };
    const limit = Math.max(1, Math.min(500, Number(corpo.limit ?? 200) || 200));

    const openaiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
    if (!openaiKey) return json(req, 503, { codigo: "config", mensagem: "OPENAI_API_KEY ausente." });

    // Mesmo modelo/dimensão do Knowledge existente. Variável permite migração explícita.
    const model = (Deno.env.get("OPENAI_EMBEDDING_MODEL") ?? "text-embedding-3-small").trim();

    const { data: pendentes, error: erroFila } = await auth.admin.rpc(
      "mind_knowledge_embedding_pending",
      { p_limit: limit },
    );
    if (erroFila) throw new Error(`embedding_queue_failed:${erroFila.message}`);

    const itens = (Array.isArray(pendentes) ? pendentes : []) as Pending[];
    if (!itens.length) {
      return json(req, 200, { ok: true, model, processados: 0, restantes: 0 });
    }

    let processados = 0;
    const batchSize = 50;

    for (let inicio = 0; inicio < itens.length; inicio += batchSize) {
      const lote = itens.slice(inicio, inicio + batchSize);
      const vetores = await embeddings(lote.map((x) => x.texto), openaiKey, model);

      for (let i = 0; i < lote.length; i++) {
        const { error } = await auth.admin.rpc("mind_knowledge_embedding_save", {
          p_id: lote[i].id,
          p_embedding: vetores[i],
          p_model: model,
        });
        if (error) throw new Error(`embedding_save_failed:${lote[i].id}:${error.message}`);
        processados += 1;
      }
    }

    const { data: restante, error: erroRestante } = await auth.admin.rpc(
      "mind_knowledge_embedding_pending",
      { p_limit: 1 },
    );
    if (erroRestante) throw new Error(`embedding_remaining_failed:${erroRestante.message}`);

    return json(req, 200, {
      ok: true,
      model,
      processados,
      restantes: Array.isArray(restante) && restante.length ? "sim" : "não",
    });
  } catch (erro) {
    console.error(JSON.stringify({ error: erro instanceof Error ? erro.message : "unknown" }));
    return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível indexar o Knowledge agora." });
  }
});
