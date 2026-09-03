import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { chamar, KIT_COMPLETO } from "./helpers/edge-harness.mjs";

const APP = readFileSync(new URL("../supabase/functions/mindagent-chat/index.ts", import.meta.url), "utf8");
const WHATSAPP = readFileSync(new URL("../supabase/functions/treble-inbound-agent/index.ts", import.meta.url), "utf8");

test("os dois runtimes validam e registram o checkout pelo mesmo contrato", () => {
  for (const [nome, fonte, canal, agente] of [
    ["app", APP, "app", "mindagent-chat"],
    ["whatsapp", WHATSAPP, "whatsapp", "treble-inbound-agent"],
  ]) {
    assert.match(fonte, /escolherCheckoutOficial/);
    assert.match(fonte, /checkoutRastreado/);
    assert.match(fonte, /mind_checkout_envio_registrar/);
    assert.ok(fonte.includes(`p_canal: "${canal}"`), `${nome}: canal real precisa ir ao ledger`);
    assert.ok(fonte.includes(`p_agente: "${agente}"`), `${nome}: Agent real precisa ir ao ledger`);
  }
});

test("app mantém concierge como entrada, mas pode trocar para summit_b2c", () => {
  assert.match(APP, /mind_summit_app:\s*"concierge_summit"/);
  assert.match(APP, /Peça summit_b2c quando houver intenção explícita de compra ou upgrade/);
  assert.doesNotMatch(APP, /mind_summit_app:\s*"summit_b2c"/);
});

test("app registra e devolve checkout rastreado quando a rota ativa é de venda", async () => {
  const checkout = "https://sun.eduzz.com/E05XKB2KWX?utm_source=mind&utm_medium=chatbot&utm_campaign=mind-summit-2026";
  const kit = structuredClone(KIT_COMPLETO);
  kit.meta.rota = "summit_b2c";
  kit.structured = {
    ofertas: {
      ofertas: [{ codigo: "prime-lote-6", nome: "Prime", checkout_url: checkout }],
    },
  };

  const r = await chamar({
    corpo: { message: "quero fazer upgrade", client_message_id: "upgrade-123" },
    rpc: {
      mindagent_chat_get_context: {
        participant_profile: { participant_id: null, interests: [] },
        expires_at: "2026-09-03T12:00:00+00:00",
        messages: [],
        origem_codigo: "mind_summit_app",
        rota_ativa: "summit_b2c",
      },
      mind_canal_rotas: {
        ok: true,
        canal: "mindagent-web",
        rotas: ["cliente_suporte", "concierge_summit", "summit_b2c"],
      },
      mind_agent_kit: kit,
    },
    modelo: {
      answer: `Aqui está o upgrade: ${checkout}`,
      interests: [],
      checkout_sent: true,
      checkout_url: checkout,
      next_route: null,
    },
  });

  assert.equal(r.status, 200);
  assert.equal(r.corpo.ok, true);
  assert.equal(r.corpo.checkout_sent, true);
  const url = new URL(r.corpo.answer.match(/https:\/\/\S+/)[0]);
  assert.equal(url.searchParams.get("utm_source"), "app");
  assert.equal(url.searchParams.get("utm_medium"), "ai_agent");
  assert.equal(url.searchParams.get("utm_campaign"), "mind_summit_2026");
  assert.equal(url.searchParams.get("utm_id"), "ms26_ai_sales");
  assert.match(url.searchParams.get("utm_content"), /^checkout_prime_preco_regular__ae_[0-9a-f]{32}$/);
  assert.equal(url.searchParams.get("agent_id"), "mindagent-chat");
  assert.equal(url.searchParams.get("conversation_id"), url.searchParams.get("mind_evento"));
  assert.equal(url.searchParams.get("mind_canal"), "app");

  const evento = r.chamada("mind_checkout_envio_registrar");
  assert.equal(evento.args.p_conversa_id, r.corpo.session.conversation_id);
  assert.equal(evento.args.p_canal, "app");
  assert.equal(evento.args.p_agente, "mindagent-chat");
  assert.equal(evento.args.p_rota, "summit_b2c");
  assert.equal(evento.args.p_motivo, "checkout_prime_preco_regular");
  assert.equal(evento.args.p_request_id, "upgrade-123");

  const mensagens = r.chamadasDe("mindagent_chat_save_message");
  assert.equal(mensagens[1].args.p_content, r.corpo.answer);
  assert.equal(mensagens[1].args.p_blocks.checkout_event_id, evento.args.p_evento_id);
});

test("app não entrega checkout que não estava no Kit", async () => {
  const r = await chamar({
    corpo: { message: "me manda o link" },
    modelo: {
      answer: "Aqui está.",
      interests: [],
      checkout_sent: true,
      checkout_url: "https://sun.eduzz.com/INVENTADO",
      next_route: null,
    },
  });
  assert.equal(r.status, 502);
  assert.equal(r.corpo.error.code, "official_checkout_unavailable");
  assert.equal(r.chamadasDe("mind_checkout_envio_registrar").length, 0);
  assert.equal(r.chamadasDe("mindagent_chat_save_message").length, 1, "somente a fala da pessoa fica gravada");
});
