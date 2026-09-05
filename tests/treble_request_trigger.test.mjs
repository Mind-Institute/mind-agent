import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  atualizarSessaoTreble,
  chavesSessaoDaResposta,
  requestTriggerHabilitado,
  respostaDoLeadTreble,
} from "../supabase/functions/_shared/treble-request-trigger.ts";

test("lê a fala do lead pelo campo oficial actual_response da Treble", () => {
  const payloadOficial = {
    session_id: "sessao-1",
    question: { type: "open", text: "Como posso ajudar?" },
    actual_response: "Quero entender melhor o Prime",
    classified_answer: { text: "outra classificação" },
  };
  assert.equal(respostaDoLeadTreble(payloadOficial), "Quero entender melhor o Prime");
});

test("nunca confunde question.text com a resposta da pessoa", () => {
  assert.equal(respostaDoLeadTreble({
    question: { type: "open", text: "Como posso ajudar?" },
  }), "");
  assert.equal(respostaDoLeadTreble({
    question: { type: "closed", text: "Escolha uma opção" },
    classified_answer: { text: "VIP" },
  }), "VIP");
});

test("Request Trigger é opt-in e não muda a URL síncrona existente", () => {
  assert.equal(requestTriggerHabilitado(new URL("https://edge.test/inbound?token=x")), false);
  assert.equal(requestTriggerHabilitado(new URL("https://edge.test/inbound?request_trigger=1")), true);
  assert.equal(requestTriggerHabilitado(new URL("https://edge.test/inbound?request_trigger=true")), true);
  assert.equal(requestTriggerHabilitado(new URL("https://edge.test/inbound?request_trigger=0")), false);
});

test("callback reaproveita somente user_session_keys válidas da resposta real", () => {
  assert.deepEqual(chavesSessaoDaResposta({
    user_session_keys: [
      { key: "resposta_ia", value: "Resposta pronta" },
      { key: "needs_human", value: "false" },
      { key: "", value: "ignorar" },
      { key: "intent", value: 123 },
    ],
  }), [
    { key: "resposta_ia", value: "Resposta pronta" },
    { key: "needs_human", value: "false" },
  ]);
});

test("callback atualiza a mesma sessão pela API oficial da Treble", async () => {
  const chamadas = [];
  await atualizarSessaoTreble({
    sessionExternalId: "sessão/com espaço",
    apiKey: "segredo-teste",
    userSessionKeys: [{ key: "resposta_ia", value: "Oi!" }],
    fetchImpl: async (url, init) => {
      chamadas.push({ url: String(url), init });
      return new Response("ok", { status: 200 });
    },
  });

  assert.equal(chamadas.length, 1);
  assert.equal(
    chamadas[0].url,
    "https://main.treble.ai/session/sess%C3%A3o%2Fcom%20espa%C3%A7o/update",
  );
  assert.equal(chamadas[0].init.method, "POST");
  assert.equal(chamadas[0].init.headers.Authorization, "segredo-teste");
  assert.deepEqual(JSON.parse(chamadas[0].init.body), {
    user_session_keys: [{ key: "resposta_ia", value: "Oi!" }],
  });
});

test("callback falha alto quando a Treble recusa a atualização", async () => {
  await assert.rejects(
    atualizarSessaoTreble({
      sessionExternalId: "sessao-1",
      apiKey: "segredo-teste",
      userSessionKeys: [{ key: "needs_human", value: "true" }],
      fetchImpl: async () => new Response("indisponível", { status: 503 }),
    }),
    /treble_update_failed_503/,
  );
});

test("runtime confirma 202 e mantém o processamento existente em background", () => {
  const src = readFileSync(
    new URL("../supabase/functions/treble-inbound-agent/index.ts", import.meta.url),
    "utf8",
  );
  assert.match(src, /EdgeRuntime\.waitUntil\(concluirTurnoAssincrono/);
  assert.match(src, /return json\(202,\s*\{\s*ok:\s*true,\s*accepted:\s*true/);
  assert.match(src, /const response = await processarTurno\(req, requestId, ORCAMENTO_TURNO_MS\)/);
  assert.match(src, /if \(req\.method !== "POST" \|\| !requestTriggerHabilitado\(url\)\) \{\s*return processarTurno\(req, crypto\.randomUUID\(\), ORCAMENTO_TREBLE_SINCRONO_MS\)/);
});

test("modo síncrono termina antes do timeout de 10 segundos da Treble", () => {
  const src = readFileSync(
    new URL("../supabase/functions/treble-inbound-agent/index.ts", import.meta.url),
    "utf8",
  );
  const match = src.match(/const ORCAMENTO_TREBLE_SINCRONO_MS = ([\d_]+);/);
  assert.ok(match, "orçamento síncrono não foi declarado");
  assert.ok(Number(match[1].replaceAll("_", "")) < 10_000);
  assert.match(src, /const fimDoOrcamento = startedAt \+ orcamentoTurnoMs/);
});

test("falha posterior à ingestão é registrada sem bloquear o fallback", () => {
  const src = readFileSync(
    new URL("../supabase/functions/treble-inbound-agent/index.ts", import.meta.url),
    "utf8",
  );
  assert.match(src, /const registrarFalhaPersistente =/);
  assert.match(src, /EdgeRuntime\.waitUntil\(\(async \(\) =>/);
  assert.match(src, /erro_runtime: codigo/);
  assert.match(src, /registrarFalhaPersistente\(codigo, statusOrigem/);
});
