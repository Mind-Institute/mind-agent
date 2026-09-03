import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";
import {
  contactEnrichment,
  contactFromPersonFacts,
  type ContactFields,
  mapCommercialAnalysis,
  stablePayload,
} from "./mapping.ts";

const HUBSPOT = "https://api.hubapi.com";
const MAX_LIMIT = 50;
const LEAD_TO_CONTACT_ASSOCIATION_TYPE = 578;

type Candidate = {
  analysis_id: string;
  conversation_id: string;
  participant_id: string;
  contact_id: string | null;
  contact_count: number;
  contact_mirror_missing_count: number;
  identity_pending: boolean;
  existing_lead_id: string | null;
  lead_count: number;
  lead_name: string;
  pipeline_id: string | null;
  pipeline_config_count: number;
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

function constantTimeEqual(provided: string, secret: string): boolean {
  const expected = new TextEncoder().encode(secret);
  const actual = new TextEncoder().encode(provided);
  if (expected.length !== actual.length) return false;

  let difference = 0;
  for (let index = 0; index < expected.length; index += 1) {
    difference |= expected[index] ^ actual[index];
  }
  return difference === 0;
}

function adminCredentials(): { clientKey: string; acceptedKeys: string[] } | null {
  const legacyKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  let secretKey = "";
  try {
    const configured = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as {
      default?: unknown;
    };
    if (typeof configured.default === "string") secretKey = configured.default;
  } catch {
    return null;
  }

  const acceptedKeys = [...new Set([secretKey, legacyKey].filter(Boolean))];
  const clientKey = secretKey || legacyKey;
  return clientKey && acceptedKeys.length > 0 ? { clientKey, acceptedKeys } : null;
}

function adminAuthorized(req: Request, acceptedKeys: string[]): boolean {
  const authorization = req.headers.get("authorization") ?? "";
  const bearer = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  const apiKey = req.headers.get("apikey") ?? "";
  return acceptedKeys.some((secret) =>
    (apiKey.length > 0 && constantTimeEqual(apiKey, secret)) ||
    (bearer.length > 0 && constantTimeEqual(bearer, secret))
  );
}

async function sha256(value: unknown) {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

const CONTACT_PROPERTIES = ["firstname", "lastname", "email", "phone", "company", "jobtitle"];

type HubSpotContact = { id: string; properties?: Record<string, unknown> };

async function hubspotRequest(
  token: string,
  path: string,
  init: RequestInit = {},
  allowNotFound = false,
): Promise<Record<string, unknown> | null> {
  const response = await fetch(`${HUBSPOT}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
    signal: AbortSignal.timeout(15_000),
  });
  if (allowNotFound && response.status === 404) return null;
  const body = await response.text();
  if (!response.ok) throw new Error(`hubspot_contact_${response.status}: ${body.slice(0, 300)}`);
  return body ? JSON.parse(body) as Record<string, unknown> : {};
}

async function ensureHubSpotContact(
  token: string,
  knownContactId: string | null,
  fields: ContactFields,
): Promise<{ id: string; action: "created" | "enriched" | "matched" }> {
  const propertiesQuery = encodeURIComponent(CONTACT_PROPERTIES.join(","));
  let contact: HubSpotContact | null = null;

  if (knownContactId) {
    contact = await hubspotRequest(
      token,
      `/crm/objects/2026-03/contacts/${encodeURIComponent(knownContactId)}?properties=${propertiesQuery}`,
    ) as HubSpotContact;
  } else {
    contact = await hubspotRequest(
      token,
      `/crm/objects/2026-03/contacts/${encodeURIComponent(fields.email)}?idProperty=email&properties=${propertiesQuery}`,
      {},
      true,
    ) as HubSpotContact | null;

    if (!contact) {
      const phoneSearch = await hubspotRequest(token, "/crm/objects/2026-03/contacts/search", {
        method: "POST",
        body: JSON.stringify({
          filterGroups: [
            { filters: [{ propertyName: "phone", operator: "EQ", value: fields.phone }] },
            { filters: [{ propertyName: "mobilephone", operator: "EQ", value: fields.phone }] },
          ],
          properties: [...CONTACT_PROPERTIES, "mobilephone"],
          limit: 2,
        }),
      });
      const results = Array.isArray(phoneSearch?.results)
        ? phoneSearch.results as HubSpotContact[]
        : [];
      if (results.length > 1) throw new Error("hubspot_contact_phone_ambiguous");
      contact = results[0] ?? null;
      const existingEmail = String(contact?.properties?.email ?? "").trim().toLowerCase();
      if (existingEmail && existingEmail !== fields.email.toLowerCase()) {
        throw new Error("hubspot_contact_email_conflict");
      }
    }
  }

  if (!contact) {
    const created = await hubspotRequest(token, "/crm/objects/2026-03/contacts", {
      method: "POST",
      body: JSON.stringify({ properties: fields }),
    }) as HubSpotContact;
    if (!created?.id) throw new Error("hubspot_contact_create_without_id");
    return { id: created.id, action: "created" };
  }

  const enrichment = contactEnrichment(fields, contact.properties ?? {});
  if (Object.keys(enrichment).length === 0) return { id: contact.id, action: "matched" };
  await hubspotRequest(token, `/crm/objects/2026-03/contacts/${encodeURIComponent(contact.id)}`, {
    method: "PATCH",
    body: JSON.stringify({ properties: enrichment }),
  });
  return { id: contact.id, action: "enriched" };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const credentials = adminCredentials();
  if (!supabaseUrl || !credentials) return json({ error: "supabase_configuration_missing" }, 500);
  if (!adminAuthorized(req, credentials.acceptedKeys)) return json({ error: "unauthorized" }, 401);

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

  const supabase = createClient(supabaseUrl, credentials.clientKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await supabase.rpc("hubspot_commercial_candidates", {
    p_limit: limit,
    p_after: after,
  });
  if (error) return json({ error: "candidate_query_failed", detail: error.message }, 500);

  const candidates = (data ?? []) as Candidate[];
  const preview: Array<Record<string, unknown>> = [];
  const applied: Array<Record<string, unknown>> = [];
  const seenParticipants = new Set<string>();
  const hubspotToken = mode === "apply" ? Deno.env.get("HUBSPOT_TOKEN") : null;
  if (mode === "apply" && !hubspotToken) return json({ error: "hubspot_token_missing" }, 500);

  for (const candidate of candidates) {
    if (seenParticipants.has(candidate.participant_id)) {
      preview.push({
        analysis_id: candidate.analysis_id,
        participant_id: candidate.participant_id,
        action: "blocked",
        reason: "participante_duplicado_no_lote",
      });
      continue;
    }
    seenParticipants.add(candidate.participant_id);

    let blockedReason: string | null = null;
    if (candidate.pipeline_config_count !== 1 || !candidate.pipeline_id) {
      blockedReason = candidate.pipeline_config_count > 1
        ? "pipeline_inbound_ambiguo_na_config"
        : "pipeline_inbound_ausente_na_config";
    } else if (candidate.identity_pending) {
      blockedReason = "pendencia_de_identidade_aberta";
    } else if (candidate.lead_count > 1) {
      blockedReason = "multiplos_leads_inbound";
    } else if (candidate.contact_count > 1 && !candidate.contact_id) {
      blockedReason = "multiplos_contatos_hubspot_sem_lead_unico";
    } else if (!candidate.existing_lead_id && candidate.contact_mirror_missing_count > 0) {
      blockedReason = "contato_hubspot_sem_espelho_crm";
    }

    const { data: personFacts, error: personError } = await supabase.rpc(
      "mind_pessoa_fatos",
      { p_pessoa_id: candidate.participant_id },
    );
    const contactPlan = contactFromPersonFacts(personFacts);
    if (personError) blockedReason ??= "pessoa_fatos_indisponivel";
    else blockedReason ??= contactPlan.blockedReason;

    const mapping = mapCommercialAnalysis(candidate.analysis ?? {}, candidate.current_stage);
    blockedReason ??= mapping.blockedReason;
    const action = candidate.existing_lead_id ? "update" : "create";

    if (blockedReason || !contactPlan.fields || !candidate.pipeline_id || !mapping.stage) {
      preview.push({
        analysis_id: candidate.analysis_id,
        participant_id: candidate.participant_id,
        action: "blocked",
        reason: blockedReason,
        missing: contactPlan.missing,
      });
      continue;
    }

    const previewItem = {
      analysis_id: candidate.analysis_id,
      participant_id: candidate.participant_id,
      lead_id: candidate.existing_lead_id,
      action,
      contact_action: candidate.contact_id ? "enrich_if_missing" : "resolve_or_create",
      from_stage: candidate.current_stage,
      to_stage: mapping.stage,
      label: mapping.label,
    };
    preview.push(previewItem);
    if (mode === "preview") continue;

    let payloadHash: string | null = null;
    let item: Record<string, unknown> = previewItem;
    let reserved = false;
    let retryable = false;
    try {
      const contact = await ensureHubSpotContact(
        hubspotToken!,
        candidate.contact_id,
        contactPlan.fields,
      );
      const { data: linked, error: linkError } = await supabase.rpc("pessoa_vincular_hubspot", {
        p_pessoa_id: candidate.participant_id,
        p_hubspot_id: contact.id,
      });
      const linkedIdentity = linked?.identidade;
      if (
        linkError ||
        linked?.ok !== true ||
        linkedIdentity?.conflito != null ||
        linkedIdentity?.pessoa_id !== candidate.participant_id
      ) {
        throw new Error(
          `hubspot_contact_link_failed: ${
            linkError?.message ??
            linkedIdentity?.conflito?.tipo ??
            linked?.motivo ??
            "identity_conflict_or_mismatch"
          }`,
        );
      }

      const payload = stablePayload({
        action,
        contactId: contact.id,
        leadId: candidate.existing_lead_id,
        leadName: candidate.lead_name,
        pipeline: candidate.pipeline_id,
        stage: mapping.stage,
        label: mapping.label,
      });
      // Ausência de confiança não apaga a propriedade enumerada atual do HubSpot.
      if (!mapping.label) delete (payload.properties as Record<string, unknown>).hs_lead_label;
      payloadHash = await sha256(payload);
      item = { ...previewItem, contact_id: contact.id, contact_result: contact.action, payload_hash: payloadHash };

      const { data: reservation, error: reserveError } = await supabase.rpc(
        "hubspot_commercial_reserve",
        {
          p_analysis_id: candidate.analysis_id,
          p_payload_hash: payloadHash,
          p_conversation_id: candidate.conversation_id,
          p_contact_id: contact.id,
          p_lead_id: candidate.existing_lead_id,
          p_action: action,
          p_payload: payload,
        },
      );
      if (reserveError || reservation !== true) {
        applied.push({ ...item, result: reserveError ? "reserve_failed" : "not_reserved" });
        continue;
      }
      reserved = true;
      retryable = action === "update";

      const properties = payload.properties;
      const path = action === "create"
        ? "/crm/objects/2026-03/leads"
        : `/crm/objects/2026-03/leads/${encodeURIComponent(candidate.existing_lead_id!)}`;
      const requestBody = action === "create"
        ? {
          properties,
          associations: [{
            to: { id: contact.id },
            types: [{
              associationCategory: "HUBSPOT_DEFINED",
              associationTypeId: LEAD_TO_CONTACT_ASSOCIATION_TYPE,
            }],
          }],
        }
        : { properties };
      const response = await fetch(`${HUBSPOT}${path}`, {
        method: action === "create" ? "POST" : "PATCH",
        headers: { Authorization: `Bearer ${hubspotToken}`, "Content-Type": "application/json" },
        body: JSON.stringify(requestBody),
        signal: AbortSignal.timeout(15_000),
      });
      const responseText = await response.text();
      if (!response.ok) {
        retryable = action === "update" &&
          (response.status === 408 || response.status === 429 || response.status >= 500);
        throw new Error(`hubspot_${response.status}: ${responseText.slice(0, 300)}`);
      }

      const responseBody = responseText
        ? JSON.parse(responseText) as { id?: string }
        : {};
      const leadId = responseBody.id ?? candidate.existing_lead_id;
      if (!leadId) throw new Error("hubspot_response_without_lead_id");

      const { data: confirmed, error: confirmError } = await supabase.rpc(
        "hubspot_commercial_confirm",
        {
          p_analysis_id: candidate.analysis_id,
          p_payload_hash: payloadHash,
          p_lead_id: leadId,
        },
      );
      if (confirmError || confirmed !== true) {
        throw new Error(confirmError
          ? `confirm_failed: ${confirmError.message}`
          : "confirm_failed: ledger_row_not_reserved");
      }
      applied.push({ ...item, lead_id: leadId, result: "sent" });
    } catch (caught) {
      const message = caught instanceof Error ? caught.message : "unknown_error";
      let failureRecorded: unknown = null;
      let failError: { message?: string } | null = null;
      if (reserved && payloadHash) {
        const failure = await supabase.rpc("hubspot_commercial_fail", {
          p_analysis_id: candidate.analysis_id,
          p_payload_hash: payloadHash,
          p_error: message,
          p_retryable: retryable,
        });
        failureRecorded = failure.data;
        failError = failure.error;
      }
      applied.push({
        ...item,
        result: reserved
          ? (failError || failureRecorded !== true ? "failed_ledger_unconfirmed" : "failed")
          : "contact_writeback_failed",
        retryable,
        error: message,
      });
    }
  }

  return json({ ok: true, mode, after, candidates: preview, applied });
});
