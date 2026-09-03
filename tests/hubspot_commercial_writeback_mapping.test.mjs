import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
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

test("vocabulário real do analisador para ganho e perda é aceito", () => {
  assert.equal(mapCommercialAnalysis({
    buyer_state: "CLOSED_WON",
    transaction: { deal_status: "won", purchase_status: "unknown" },
  }, null).stage, STAGES.WON);
  assert.equal(mapCommercialAnalysis({
    buyer_state: "DEFERRED",
    transaction: { deal_status: "lost", purchase_status: "not_purchased" },
  }, null).stage, STAGES.LOST);
});

test("sinais terminais contraditórios bloqueiam a escrita", () => {
  const result = mapCommercialAnalysis({
    buyer_state: "CLOSED_LOST",
    transaction: { deal_status: "lost", purchase_status: "purchased" },
  }, null);
  assert.equal(result.stage, null);
  assert.equal(result.blockedReason, "sinais_terminais_conflitantes");
});

test("handoff pendente prevalece sobre negociação", () => {
  assert.equal(mapCommercialAnalysis({
    buyer_state: "BLOCKED",
    ownership: { handoff_status: "requested" },
  }, null).stage, STAGES.HUMAN);
});

test("handoff marcado como required também exige humano", () => {
  assert.equal(mapCommercialAnalysis({
    buyer_state: "ORIENTING",
    ownership: { handoff_status: "required" },
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

test("contrato SQL usa apenas coletores canônicos e preserva o ledger", () => {
  const sql = readFileSync(
    new URL("../supabase/migrations/20260903090000_hubspot_commercial_writeback.sql", import.meta.url),
    "utf8",
  );

  assert.match(sql, /public\.mind_crm_comercial\(s\.participante_id\)/);
  assert.match(sql, /public\.mind_pessoa_fatos\(s\.participante_id\)/);
  assert.doesNotMatch(sql, /engagement\.identidades/);
  assert.doesNotMatch(sql, /pessoas\.hubspot_id/);
  assert.doesNotMatch(sql, /on delete cascade/i);
  assert.doesNotMatch(sql, /918902366/);
  assert.match(sql, /w\.action = 'update'/);
  assert.match(sql, /w\.attempt_count < 3/);
  assert.match(sql, /interval '15 minutes'/);
});

test("runtime não contém fallback de pipeline e exige service role", () => {
  const index = readFileSync(
    new URL("../supabase/functions/hubspot-commercial-writeback/index.ts", import.meta.url),
    "utf8",
  );
  const mapping = readFileSync(
    new URL("../supabase/functions/hubspot-commercial-writeback/mapping.ts", import.meta.url),
    "utf8",
  );

  assert.doesNotMatch(index, /918902366|INBOUND_PIPELINE/);
  assert.doesNotMatch(mapping, /918902366|INBOUND_PIPELINE/);
  assert.match(index, /serviceRoleAuthorized/);
  assert.match(index, /p_retryable: retryable/);
});
