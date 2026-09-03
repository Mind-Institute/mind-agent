import assert from "node:assert/strict";
import test from "node:test";
import {
  mapCommercialAnalysis,
  STAGES,
  stablePayload,
} from "../supabase/functions/hubspot-commercial-writeback/mapping.ts";

test("compra confirmada prevalece sobre handoff", () => {
  const result = mapCommercialAnalysis({
    buyer_state: "TRANSACTIONAL",
    human_required: true,
    transaction: { purchase_status: "purchased" },
  }, null);
  assert.equal(result.stage, STAGES.WON);
});

test("perda explícita vai para perdido", () => {
  assert.equal(mapCommercialAnalysis({
    buyer_state: "CLOSED_LOST",
    transaction: { deal_status: "closed_lost" },
  }, null).stage, STAGES.LOST);
});

test("handoff pendente prevalece sobre negociação", () => {
  assert.equal(mapCommercialAnalysis({
    buyer_state: "BLOCKED",
    ownership: { handoff_status: "requested" },
  }, null).stage, STAGES.HUMAN);
});

test("estados avançados vão para negociação", () => {
  for (const state of ["COMMITTED", "TRANSACTIONAL", "BLOCKED", "AWAITING_EXTERNAL"]) {
    assert.equal(mapCommercialAnalysis({ buyer_state: state }, null).stage, STAGES.NEGOTIATION);
  }
});

test("estados de exploração vão para lead em contato", () => {
  for (const state of ["ORIENTING", "CHOOSING", "PREFERENCE_SHOWN", "VALIDATING", "DEFERRED"]) {
    assert.equal(mapCommercialAnalysis({ buyer_state: state }, null).stage, STAGES.CONTACT);
  }
});

test("lead terminal nunca é reaberto por análise não terminal", () => {
  const result = mapCommercialAnalysis({ buyer_state: "ORIENTING" }, STAGES.WON);
  assert.equal(result.stage, null);
  assert.equal(result.blockedReason, "lead_terminal_nao_pode_ser_alterado");
});

test("lead perdido não vira ganho automaticamente", () => {
  const result = mapCommercialAnalysis({
    buyer_state: "TRANSACTIONAL",
    transaction: { purchase_status: "purchased" },
  }, STAGES.LOST);
  assert.equal(result.stage, null);
  assert.equal(result.blockedReason, "lead_terminal_nao_pode_ser_alterado");
});

test("intenção vira temperatura sem adivinhar valor ausente", () => {
  assert.equal(mapCommercialAnalysis({ buyer_state: "ORIENTING", purchase_intent: "high" }, null).label, "HOT");
  assert.equal(mapCommercialAnalysis({ buyer_state: "ORIENTING", purchase_intent: "medium" }, null).label, "WARM");
  assert.equal(mapCommercialAnalysis({ buyer_state: "ORIENTING", purchase_intent: "low" }, null).label, "COLD");
  assert.equal(mapCommercialAnalysis({ buyer_state: "ORIENTING" }, null).label, null);
});

test("payload de criação é determinístico e usa somente propriedades aprováveis", () => {
  assert.deepEqual(stablePayload({
    action: "create",
    contactId: "123",
    leadId: null,
    leadName: "Ada - Mind",
    pipeline: "918902366",
    stage: STAGES.CONTACT,
    label: "WARM",
  }), {
    action: "create",
    contact_id: "123",
    lead_id: null,
    properties: {
      hs_lead_label: "WARM",
      hs_lead_name: "Ada - Mind",
      hs_lead_type: "NEW_BUSINESS",
      hs_pipeline: "918902366",
      hs_pipeline_stage: STAGES.CONTACT,
    },
  });
});

test("atualização preserva nome, pipeline e tipo administrados no HubSpot", () => {
  assert.deepEqual(stablePayload({
    action: "update",
    contactId: "123",
    leadId: "456",
    leadName: "nome ignorado",
    pipeline: "918902366",
    stage: STAGES.NEGOTIATION,
    label: "HOT",
  }).properties, {
    hs_lead_label: "HOT",
    hs_pipeline_stage: STAGES.NEGOTIATION,
  });
});
