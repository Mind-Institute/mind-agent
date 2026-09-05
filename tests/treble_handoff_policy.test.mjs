import { test } from "node:test";
import assert from "node:assert/strict";
import { decidirHandoff, HANDOFF_REASONS } from "../supabase/functions/_shared/treble-handoff.ts";

test("troca de VIP para Prime não transfere sem motivo humano real", () => {
  assert.deepEqual(decidirHandoff(false, null, false), {
    needsHuman: false,
    reason: null,
    suppressed: false,
  });
});

test("modelo não consegue transferir sem motivo enumerado", () => {
  assert.deepEqual(decidirHandoff(true, null, false), {
    needsHuman: false,
    reason: null,
    suppressed: true,
  });
  assert.deepEqual(decidirHandoff(true, "perguntou_sobre_prime", false), {
    needsHuman: false,
    reason: null,
    suppressed: true,
  });
});

test("pedido humano explícito e regras B2B válidas continuam transferindo", () => {
  for (const reason of ["pedido_humano", "b2b_5_9_alta_intencao", "volume_10_mais"]) {
    assert.equal(HANDOFF_REASONS.includes(reason), true);
    assert.deepEqual(decidirHandoff(true, reason, false), {
      needsHuman: true,
      reason,
      suppressed: false,
    });
  }
});

test("Capability Gate continua soberano sem inventar motivo comercial", () => {
  assert.deepEqual(decidirHandoff(false, null, true), {
    needsHuman: true,
    reason: null,
    suppressed: false,
  });
});
