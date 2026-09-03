import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";

const VERSION = "1.0.0";
const PROMPT_VERSION = 1;
const DEFAULT_MODEL = "gpt-5.4";

type Candidate = {
  conversation_id: string;
  analysis_id: string;
  inbox_state: "freeform_ready" | "needs_hsm" | "app_inbox";
  objection_group: string;
  heat: string;
  context: Record<string, unknown>;
};

type Draft = {
  summary: string;
  objection: string;
  objection_group: string;
  heat: string;
  recommended_action: string;
  freeform_message: string | null;
  hsm_message: string | null;
};

const GROUPS = [
  "checkout_abandonment", "price", "availability_logistics", "payment_technical", "internal_approval",
  "stopped_replying", "interested_not_bought", "promised_to_return", "other",
] as const;
const HEAT = ["cold", "warm", "hot", "very_hot"] as const;
const TEMPLATE_BY_GROUP: Record<string, string> = Object.fromEntries(
  GROUPS.map((group) => [group, `ms26_recovery_${group}_v1`]),
);

const OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "summary", "objection", "objection_group", "heat", "recommended_action",
    "freeform_message", "hsm_message",
  ],
  properties: {
    summary: { type: "string", minLength: 1, maxLength: 700 },
    objection: { type: "string", minLength: 1, maxLength: 240 },
    objection_group: { type: "string", enum: GROUPS },
    heat: { type: "string", enum: HEAT },
    recommended_action: { type: "string", minLength: 1, maxLength: 300 },
    freeform_message: { type: ["string", "null"], maxLength: 900 },
    hsm_message: { type: ["string", "null"], maxLength: 900 },
  },
} as const;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function constantTimeEqual(provided: string, secret: string) {
  const expected = new TextEncoder().encode(secret);
  const actual = new TextEncoder().encode(provided);
  if (expected.length !== actual.length) return false;
  let difference = 0;
  for (let i = 0; i < expected.length; i++) difference |= expected[i] ^ actual[i];
  return difference === 0;
}

function adminCredentials() {
  const legacyKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  let secretKey = "";
  try {
    const configured = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as { default?: unknown };
    if (typeof configured.default === "string") secretKey = configured.default;
  } catch {
    return null;
  }
  const acceptedKeys = [...new Set([secretKey, legacyKey].filter(Boolean))];
  return acceptedKeys.length ? { clientKey: secretKey || legacyKey, acceptedKeys } : null;
}

function authorized(req: Request, acceptedKeys: string[]) {
  const authorization = req.headers.get("authorization") ?? "";
  const bearer = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  const apiKey = req.headers.get("apikey") ?? "";
  return acceptedKeys.some((secret) =>
    (bearer && constantTimeEqual(bearer, secret)) || (apiKey && constantTimeEqual(apiKey, secret))
  );
}

function extractOutputText(payload: Record<string, unknown>) {
  if (typeof payload.output_text === "string") return payload.output_text;
  const output = Array.isArray(payload.output) ? payload.output : [];
  for (const item of output) {
    if (!item || typeof item !== "object") continue;
    const content = Array.isArray((item as Record<string, unknown>).content)
      ? (item as Record<string, unknown>).content as Array<Record<string, unknown>> : [];
    for (const part of content) if (typeof part?.text === "string") return part.text;
  }
  return "";
}

function clean(value: unknown, max: number) {
  return typeof value === "string" ? value.trim().slice(0, max) : null;
}

async function makeDraft(openAiKey: string, model: string, candidate: Candidate): Promise<Draft> {
  const instructions = `Você é o estrategista de retomada comercial do Mind Summit.
Analise somente as evidências recebidas e prepare o próximo movimento mais provável de gerar resposta.
Não invente preço, desconto, lote, prazo, acesso, palestrante, checkout ou fato. Não trate silêncio como objeção.
Compra confirmada, opt-out, identidade incerta e handoff humano já foram excluídos antes desta etapa.
Escreva em português brasileiro, natural, específico e curto. A mensagem deve retomar o contexto real, entregar valor e terminar com uma pergunta simples que facilite resposta; sem pressão artificial.
freeform_message é usado apenas dentro da janela de 24 horas ou no app. hsm_message é uma proposta de template para fora da janela: não inclua dados pessoais nem URL e use {{1}} apenas para o primeiro nome, se necessário.
Se o estado não corresponder à mensagem, devolva null naquele campo.`;
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${openAiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      instructions,
      input: [{ role: "user", content: JSON.stringify({
        inbox_state: candidate.inbox_state,
        preliminary_group: candidate.objection_group,
        preliminary_heat: candidate.heat,
        evidence: candidate.context,
      }) }],
      reasoning: { effort: "medium" },
      text: { format: { type: "json_schema", name: "recovery_draft", strict: true, schema: OUTPUT_SCHEMA } },
      max_output_tokens: 1800,
      safety_identifier: candidate.conversation_id,
      store: false,
    }),
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) throw new Error(`openai_${response.status}`);
  const payload = await response.json() as Record<string, unknown>;
  const parsed = JSON.parse(extractOutputText(payload)) as Draft;
  const group = GROUPS.includes(parsed.objection_group as typeof GROUPS[number])
    ? parsed.objection_group : candidate.objection_group;
  const heat = HEAT.includes(parsed.heat as typeof HEAT[number]) ? parsed.heat : candidate.heat;
  return {
    summary: clean(parsed.summary, 700) ?? "Contexto insuficiente para resumo.",
    objection: clean(parsed.objection, 240) ?? "não confirmada",
    objection_group: group,
    heat,
    recommended_action: clean(parsed.recommended_action, 300) ?? "revisar manualmente",
    freeform_message: candidate.inbox_state === "needs_hsm" ? null : clean(parsed.freeform_message, 900),
    hsm_message: candidate.inbox_state === "needs_hsm" ? clean(parsed.hsm_message, 900) : null,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const credentials = adminCredentials();
  if (!supabaseUrl || !credentials) return json({ ok: false, error: "supabase_configuration_missing" }, 500);
  if (!authorized(req, credentials.acceptedKeys)) return json({ ok: false, error: "unauthorized" }, 401);
  const body = await req.json().catch(() => ({})) as { mode?: string; limit?: number };
  const mode = body.mode ?? "refresh";
  const limit = Math.max(1, Math.min(mode === "draft" ? 10 : 2000, Math.trunc(body.limit ?? 20)));
  const admin = createClient(supabaseUrl, credentials.clientKey, { auth: { persistSession: false, autoRefreshToken: false } });

  if (mode === "refresh") {
    const { data, error } = await admin.rpc("mind_recovery_refresh", { p_limit: limit });
    if (error) return json({ ok: false, error: "refresh_failed" }, 502);
    const { data: abandonment, error: abandonmentError } = await admin.rpc("mind_checkout_abandonment_refresh");
    return abandonmentError
      ? json({ ok: false, error: "abandonment_refresh_failed" }, 502)
      : json({ ...data, abandonment, version: VERSION });
  }
  if (mode === "prepare") {
    const { data, error } = await admin.rpc("mind_recovery_prepare_queue", { p_limit: limit });
    return error ? json({ ok: false, error: "prepare_failed" }, 502) : json({ ...data, version: VERSION });
  }
  if (mode !== "draft") return json({ ok: false, error: "invalid_mode" }, 422);

  const openAiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!openAiKey) return json({ ok: false, error: "openai_configuration_missing" }, 503);
  const model = Deno.env.get("OPENAI_MODEL_RECOVERY") ?? DEFAULT_MODEL;
  const { data, error } = await admin.rpc("mind_recovery_claim_drafts", { p_limit: limit });
  if (error) return json({ ok: false, error: "claim_failed" }, 502);
  const candidates = (Array.isArray(data) ? data : []) as Candidate[];

  const results = await Promise.all(candidates.map(async (candidate) => {
    try {
      const draft = await makeDraft(openAiKey, model, candidate);
      const { data: saved, error: saveError } = await admin.rpc("mind_recovery_save_draft", {
        p_conversation_id: candidate.conversation_id,
        p_analysis_id: candidate.analysis_id,
        p_summary: draft.summary,
        p_objection: draft.objection,
        p_objection_group: draft.objection_group,
        p_heat: draft.heat,
        p_recommended_action: draft.recommended_action,
        p_freeform_message: draft.freeform_message,
        p_hsm_message: draft.hsm_message,
        p_hsm_template_key: TEMPLATE_BY_GROUP[draft.objection_group] ?? TEMPLATE_BY_GROUP.other,
        p_model: model,
        p_prompt_version: PROMPT_VERSION,
        p_error: null,
      });
      if (saveError || saved?.ok !== true) throw new Error("save_failed");
      return { conversation_id: candidate.conversation_id, ok: true };
    } catch (cause) {
      const code = cause instanceof Error ? cause.message.slice(0, 120) : "draft_failed";
      await admin.rpc("mind_recovery_save_draft", {
        p_conversation_id: candidate.conversation_id,
        p_analysis_id: candidate.analysis_id,
        p_summary: null,
        p_objection: candidate.objection_group,
        p_objection_group: candidate.objection_group,
        p_heat: candidate.heat,
        p_recommended_action: "revisar manualmente",
        p_freeform_message: null,
        p_hsm_message: null,
        p_hsm_template_key: null,
        p_model: model,
        p_prompt_version: PROMPT_VERSION,
        p_error: code,
      });
      return { conversation_id: candidate.conversation_id, ok: false, error: code };
    }
  }));
  return json({ ok: results.every((item) => item.ok), version: VERSION, claimed: candidates.length, results });
});
