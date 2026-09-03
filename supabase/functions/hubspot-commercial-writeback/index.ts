import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";
import { INBOUND_PIPELINE, mapCommercialAnalysis, stablePayload } from "./mapping.ts";

const HUBSPOT = "https://api.hubapi.com";
const MAX_LIMIT = 50;

type Candidate = {
  analysis_id: string;
  conversation_id: string;
  person_id: string;
  contact_id: string | null;
  existing_lead_id: string | null;
  lead_count: number;
  lead_name: string;
  pipeline_id: string | null;
  current_stage: string | null;
  analysis: Record<string, unknown>;
};

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

function validTimestamp(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && Number.isFinite(Date.parse(value));
}

async function sha256(value: unknown) {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const body = await req.json().catch(() => ({})) as {
    mode?: "preview" | "apply";
    after?: string;
    limit?: number;
  };
  const mode = body.mode ?? "preview";
  if (mode !== "preview" && mode !== "apply") return json({ error: "invalid_mode" }, 400);

  const after = body.after ?? Deno.env.get("HUBSPOT_COMMERCIAL_WRITEBACK_AFTER");
  if (!validTimestamp(after)) {
    return json({
      error: "after_required",
      message: "Informe um corte temporal ISO-8601. Backfill histórico nunca é implícito.",
    }, 400);
  }

  const limit = Math.max(1, Math.min(MAX_LIMIT, Math.trunc(body.limit ?? 25)));
  if (mode === "apply" && Deno.env.get("HUBSPOT_COMMERCIAL_WRITEBACK_ENABLED") !== "true") {
    return json({ error: "writeback_disabled" }, 403);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data, error } = await supabase.rpc("hubspot_commercial_candidates", {
    p_limit: limit,
    p_after: after,
  });
  if (error) return json({ error: "candidate_query_failed", detail: error.message }, 500);

  const candidates = (data ?? []) as Candidate[];
  const preview: Array<Record<string, unknown>> = [];
  const applied: Array<Record<string, unknown>> = [];
  const token = mode === "apply" ? Deno.env.get("HUBSPOT_TOKEN") : null;
  if (mode === "apply" && !token) return json({ error: "hubspot_token_missing" }, 500);

  for (const candidate of candidates) {
    let blockedReason: string | null = null;
    if (!candidate.contact_id) blockedReason = "contato_hubspot_ausente";
    else if (candidate.lead_count > 1) blockedReason = "multiplos_leads_inbound";
    else if (!candidate.pipeline_id) blockedReason = "pipeline_inbound_ausente_na_config";

    const mapping = mapCommercialAnalysis(candidate.analysis ?? {}, candidate.current_stage);
    blockedReason ??= mapping.blockedReason;
    const action = candidate.existing_lead_id ? "update" : "create";

    if (blockedReason || !candidate.contact_id || !candidate.pipeline_id || !mapping.stage) {
      preview.push({
        analysis_id: candidate.analysis_id,
        person_id: candidate.person_id,
        action: "blocked",
        reason: blockedReason,
      });
      continue;
    }

    const payload = stablePayload({
      action,
      contactId: candidate.contact_id,
      leadId: candidate.existing_lead_id,
      leadName: candidate.lead_name,
      pipeline: candidate.pipeline_id || INBOUND_PIPELINE,
      stage: mapping.stage,
      label: mapping.label,
    });
    // Não envia null para propriedade enumerada: ausência de confiança mantém o valor atual.
    if (!mapping.label) delete (payload.properties as Record<string, unknown>).hs_lead_label;
    const payloadHash = await sha256(payload);

    const item = {
      analysis_id: candidate.analysis_id,
      person_id: candidate.person_id,
      lead_id: candidate.existing_lead_id,
      action,
      from_stage: candidate.current_stage,
      to_stage: mapping.stage,
      label: mapping.label,
      payload_hash: payloadHash,
    };
    preview.push(item);
    if (mode === "preview") continue;

    const { data: reserved, error: reserveError } = await supabase.rpc(
      "hubspot_commercial_reserve",
      {
        p_analysis_id: candidate.analysis_id,
        p_payload_hash: payloadHash,
        p_conversation_id: candidate.conversation_id,
        p_person_id: candidate.person_id,
        p_contact_id: candidate.contact_id,
        p_lead_id: candidate.existing_lead_id,
        p_action: action,
        p_payload: payload,
      },
    );
    if (reserveError || reserved !== true) {
      applied.push({ ...item, result: reserveError ? "reserve_failed" : "already_reserved" });
      continue;
    }

    try {
      const properties = payload.properties;
      const path = action === "create"
        ? "/crm/objects/2026-03/leads"
        : `/crm/objects/2026-03/leads/${encodeURIComponent(candidate.existing_lead_id!)}`;
      const requestBody = action === "create"
        ? {
          properties,
          associations: [{
            to: { id: candidate.contact_id },
            types: [{ associationCategory: "HUBSPOT_DEFINED", associationTypeId: 578 }],
          }],
        }
        : { properties };
      const response = await fetch(`${HUBSPOT}${path}`, {
        method: action === "create" ? "POST" : "PATCH",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify(requestBody),
      });
      const responseText = await response.text();
      if (!response.ok) throw new Error(`hubspot_${response.status}: ${responseText.slice(0, 300)}`);
      const responseBody = JSON.parse(responseText) as { id?: string };
      const leadId = responseBody.id ?? candidate.existing_lead_id;
      if (!leadId) throw new Error("hubspot_response_without_lead_id");

      const { error: confirmError } = await supabase.rpc("hubspot_commercial_confirm", {
        p_analysis_id: candidate.analysis_id,
        p_payload_hash: payloadHash,
        p_lead_id: leadId,
      });
      if (confirmError) throw new Error(`confirm_failed: ${confirmError.message}`);
      applied.push({ ...item, lead_id: leadId, result: "sent" });
    } catch (caught) {
      const message = caught instanceof Error ? caught.message : "unknown_error";
      await supabase.rpc("hubspot_commercial_fail", {
        p_analysis_id: candidate.analysis_id,
        p_payload_hash: payloadHash,
        p_error: message,
      });
      applied.push({ ...item, result: "failed", error: message });
    }
  }

  return json({ ok: true, mode, after, candidates: preview, applied });
});
