import { createClient } from "npm:@supabase/supabase-js@2.112.3";

const VERSION = "1.0.0";
const MODELO = "text-embedding-3-small";
const DIMENSOES = 1536;
const SCHEMAS = new Set(["summit_2026", "institute", "dash", "eventos"]);

function secretKey() {
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      const value = parsed.default ?? Object.values(parsed).find((item) => typeof item === "string");
      if (typeof value === "string") return value;
    } catch {
      // Compatibilidade abaixo.
    }
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

// TODA service key do projeto vale como credencial, não só a `default`.
// `SUPABASE_SECRET_KEYS` é um mapa — o projeto pode ter mais de uma chave
// secreta ativa, e quem chama copia do painel a que estiver à mão. Aceitar
// só uma delas rejeitava credencial legítima e era indistinguível, para
// quem chama, de "a chave está errada". O que continua obrigatório é ser
// uma chave secreta REAL do projeto; nada aqui abre para chave publishable.
function chavesAceitas(): Set<string> {
  const aceitas = new Set<string>();
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (raw) {
    try {
      for (const value of Object.values(JSON.parse(raw) as Record<string, unknown>)) {
        if (typeof value === "string" && value) aceitas.add(value);
      }
    } catch {
      // Compatibilidade abaixo.
    }
  }
  const legada = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legada) aceitas.add(legada);
  return aceitas;
}

function resposta(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return resposta(405, { ok: false, error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = secretKey();
  const openAiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  // O gateway do Supabase recusa `Authorization: Bearer <chave sb_secret_*>`
  // quando `apikey` já carrega uma chave do projeto — "Conflicting API
  // keys", mesmo com o mesmo valor nos dois. Aceitar a chave também via
  // `apikey` (sem prefixo `Bearer`) é o caminho que o próprio gateway deixa
  // passar; a exigência continua sendo uma service key real do projeto.
  const aceitas = chavesAceitas();
  const bearer = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const apikeyHeader = req.headers.get("apikey") ?? "";
  const autorizado = aceitas.has(bearer) || aceitas.has(apikeyHeader);
  if (!autorizado) {
    return resposta(401, { ok: false, error: "unauthorized" });
  }
  if (!supabaseUrl || !openAiKey) return resposta(503, { ok: false, error: "configuration_missing" });

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return resposta(422, { ok: false, error: "invalid_json" });
  }

  const schema = String(payload.schema ?? "summit_2026");
  const limite = Math.max(1, Math.min(100, Math.trunc(Number(payload.limite ?? 50)) || 50));
  if (!SCHEMAS.has(schema)) return resposta(422, { ok: false, error: "invalid_schema" });

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { error: prepararError } = await admin.rpc("mind_knowledge_preparar_chunks", { p_schema: schema });
  if (prepararError) return resposta(502, { ok: false, error: "prepare_failed" });

  const { data, error } = await admin.rpc("mind_intelligence_chunks_pendentes", {
    p_schema: schema,
    p_limite: limite,
  });
  if (error) return resposta(502, { ok: false, error: "read_failed" });

  const chunks = Array.isArray(data) ? data.filter((item): item is { id: string; texto: string } => {
    if (!item || typeof item !== "object" || Array.isArray(item)) return false;
    const candidate = item as Record<string, unknown>;
    return typeof candidate.id === "string" && typeof candidate.texto === "string";
  }) : [];
  if (chunks.length === 0) {
    return resposta(200, { ok: true, version: VERSION, schema, indexed: 0, remaining: false });
  }

  const embeddingResponse = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: { "Authorization": `Bearer ${openAiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ model: MODELO, input: chunks.map((item) => item.texto) }),
  });
  if (!embeddingResponse.ok) return resposta(502, { ok: false, error: "embedding_failed" });

  const embeddingPayload = await embeddingResponse.json() as {
    data?: Array<{ index?: number; embedding?: number[] }>;
  };
  const porIndice = new Map(
    (embeddingPayload.data ?? []).map((item) => [Number(item.index), item.embedding]),
  );

  let indexed = 0;
  for (let i = 0; i < chunks.length; i++) {
    const embedding = porIndice.get(i);
    if (!Array.isArray(embedding) || embedding.length !== DIMENSOES) continue;
    const { data: gravou, error: gravarError } = await admin.rpc(
      "mind_intelligence_embedding_registrar",
      {
        p_schema: schema,
        p_chunk_id: chunks[i].id,
        p_embedding: `[${embedding.join(",")}]`,
        p_modelo: MODELO,
      },
    );
    if (!gravarError && gravou === true) indexed++;
  }

  return resposta(200, {
    ok: indexed === chunks.length,
    version: VERSION,
    schema,
    requested: chunks.length,
    indexed,
    remaining: chunks.length === limite,
  });
});
