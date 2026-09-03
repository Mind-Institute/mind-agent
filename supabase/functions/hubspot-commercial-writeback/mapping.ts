export const INBOUND_PIPELINE = "918902366";

export const STAGES = {
  NEW: "1401915457",
  CONTACT: "1401915458",
  HUMAN: "1425802038",
  NEGOTIATION: "1421369479",
  WON: "1401915460",
  DORMANT: "1425802045",
  LOST: "1401915461",
} as const;

const TERMINAL = new Set<string>([STAGES.WON, STAGES.LOST]);
const NEGOTIATION_STATES = new Set([
  "COMMITTED",
  "TRANSACTIONAL",
  "BLOCKED",
  "AWAITING_EXTERNAL",
]);
const CONTACT_STATES = new Set([
  "ORIENTING",
  "CHOOSING",
  "PREFERENCE_SHOWN",
  "VALIDATING",
  "DEFERRED",
]);
const HUMAN_HANDOFF = new Set(["requested", "pending", "accepted"]);

export type Analysis = Record<string, unknown>;

export type Mapping = {
  stage: string | null;
  label: "HOT" | "WARM" | "COLD" | null;
  blockedReason: string | null;
};

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

export function mapCommercialAnalysis(
  analysis: Analysis,
  currentStage: string | null,
): Mapping {
  const transaction = record(analysis.transaction);
  const ownership = record(analysis.ownership);
  const dealStatus = text(transaction.deal_status).toLowerCase();
  const purchaseStatus = text(transaction.purchase_status).toLowerCase();
  const buyerState = text(analysis.buyer_state).toUpperCase();
  const handoffStatus = text(ownership.handoff_status).toLowerCase();
  const humanRequired = analysis.human_required === true || ownership.human_required === true;

  const explicitTerminal = purchaseStatus === "purchased" || dealStatus === "closed_won"
    ? STAGES.WON
    : dealStatus === "closed_lost" || buyerState === "CLOSED_LOST"
    ? STAGES.LOST
    : null;

  if (currentStage && TERMINAL.has(currentStage) && explicitTerminal !== currentStage) {
    return {
      stage: null,
      label: mapLabel(analysis.purchase_intent),
      blockedReason: "lead_terminal_nao_pode_ser_alterado",
    };
  }

  let stage: string | null = explicitTerminal;
  if (!stage && (humanRequired || HUMAN_HANDOFF.has(handoffStatus))) {
    stage = STAGES.HUMAN;
  } else if (!stage && NEGOTIATION_STATES.has(buyerState)) {
    stage = STAGES.NEGOTIATION;
  } else if (!stage && CONTACT_STATES.has(buyerState)) {
    stage = STAGES.CONTACT;
  }

  if (!stage) {
    return {
      stage: null,
      label: mapLabel(analysis.purchase_intent),
      blockedReason: "buyer_state_sem_mapeamento_seguro",
    };
  }

  return { stage, label: mapLabel(analysis.purchase_intent), blockedReason: null };
}

export function mapLabel(value: unknown): Mapping["label"] {
  switch (text(value).toLowerCase()) {
    case "very_high":
    case "high":
      return "HOT";
    case "medium":
      return "WARM";
    case "low":
      return "COLD";
    default:
      return null;
  }
}

export function stablePayload(input: {
  action: "create" | "update";
  contactId: string;
  leadId: string | null;
  leadName: string;
  pipeline: string;
  stage: string;
  label: Mapping["label"];
}) {
  const properties: Record<string, string | null> = {
    hs_lead_label: input.label,
    hs_pipeline_stage: input.stage,
  };
  if (input.action === "create") {
    properties.hs_lead_name = input.leadName;
    properties.hs_lead_type = "NEW_BUSINESS";
    properties.hs_pipeline = input.pipeline;
  }
  return {
    action: input.action,
    contact_id: input.contactId,
    lead_id: input.leadId,
    properties,
  };
}
