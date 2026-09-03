import { test } from "node:test";
import assert from "node:assert/strict";
import {
  checkoutRastreado,
  escolherCheckoutOficial,
  idEventoCheckout,
  inserirCheckoutNaResposta,
  listarCheckoutsOficiais,
} from "../supabase/functions/_shared/checkout-attribution.ts";

const CONTEXTO = {
  ofertas: {
    ofertas: [{
      codigo: "prime-lote-6",
      checkout_url: "https://sun.eduzz.com/E05XKB2KWX?utm_source=google&utm_medium=cpc&utm_campaign=summit&utm_content=anuncio",
    }, {
      codigo: "upgrade-mind-vip",
      checkout_url: "https://chk.eduzz.com/upgrade?utm_source=mind&utm_medium=chatbot&utm_campaign=mind-summit-2026",
    }],
  },
  regras_comerciais: {
    regras: [{
      config: {
        niveis: [{
          ofertas: {
            vip: { cupom: "AGORA20", checkout_url: "https://sun.eduzz.com/VIP?cupom=AGORA20" },
          },
        }],
      },
    }],
  },
};

test("descobre somente checkouts Eduzz oficiais e nomeia oferta, upgrade e desconto", () => {
  const itens = listarCheckoutsOficiais(CONTEXTO);
  assert.deepEqual(itens.map((item) => item.motivo).sort(), [
    "checkout_prime_preco_regular",
    "checkout_upgrade_mind_vip",
    "checkout_vip_desconto_20",
  ]);
});

test("recusa URL externa e checkout com cupom diferente do Kit", () => {
  assert.equal(escolherCheckoutOficial(CONTEXTO, "https://evil.example/checkout"), null);
  assert.equal(escolherCheckoutOficial(CONTEXTO, "https://sun.eduzz.com/VIP?cupom=AGORA40"), null);
});

test("marca o canal do envio, campanha, agente, motivo e conversa opaca", async () => {
  const checkout = escolherCheckoutOficial(CONTEXTO, CONTEXTO.ofertas.ofertas[0].checkout_url);
  const id = await idEventoCheckout("11111111-1111-4111-8111-111111111111", "msg-1", checkout.url);
  const rastreado = new URL(checkoutRastreado(checkout, id, "app", "mindagent-chat"));

  assert.equal(rastreado.searchParams.get("utm_source"), "app");
  assert.equal(rastreado.searchParams.get("utm_medium"), "ai_agent");
  assert.equal(rastreado.searchParams.get("utm_campaign"), "summit");
  assert.equal(rastreado.searchParams.get("utm_id"), "summit_ai_sales");
  assert.equal(rastreado.searchParams.get("utm_content"), `checkout_prime_preco_regular__ae_${id.replaceAll("-", "")}`);
  assert.equal(rastreado.searchParams.get("utm_term"), `ae_${id.replaceAll("-", "")}`);
  assert.equal(rastreado.searchParams.get("agent_id"), "mindagent-chat");
  assert.equal(rastreado.searchParams.get("conversation_id"), id);
  assert.equal(rastreado.searchParams.get("mind_canal"), "app");
  assert.equal(rastreado.searchParams.get("mind_evento"), id);
});

test("troca defaults do bot pelo canal real e pelo meio ai_agent", async () => {
  const checkout = escolherCheckoutOficial(CONTEXTO, CONTEXTO.ofertas.ofertas[1].checkout_url);
  const id = await idEventoCheckout("11111111-1111-4111-8111-111111111111", "msg-2", checkout.url);
  const rastreado = new URL(checkoutRastreado(checkout, id, "whatsapp", "treble-inbound-agent"));
  assert.equal(rastreado.searchParams.get("utm_source"), "whatsapp");
  assert.equal(rastreado.searchParams.get("utm_medium"), "ai_agent");
  assert.equal(rastreado.searchParams.get("utm_campaign"), "mind_summit_2026");
  assert.equal(rastreado.searchParams.get("utm_id"), "ms26_ai_sales");
});

test("id do envio é estável no retry e muda para outro checkout", async () => {
  const conversa = "11111111-1111-4111-8111-111111111111";
  const a = await idEventoCheckout(conversa, "msg-3", "https://sun.eduzz.com/A");
  const b = await idEventoCheckout(conversa, "msg-3", "https://sun.eduzz.com/A");
  const c = await idEventoCheckout(conversa, "msg-3", "https://sun.eduzz.com/B");
  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.match(a, /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

test("substitui o link existente ou acrescenta o link rastreado uma única vez", () => {
  const checkout = escolherCheckoutOficial(CONTEXTO, CONTEXTO.ofertas.ofertas[1].checkout_url);
  const rastreado = "https://chk.eduzz.com/upgrade?utm_content=rastreado";
  assert.equal(
    inserirCheckoutNaResposta(`Aqui está: ${checkout.url}`, checkout, rastreado, checkout.url),
    `Aqui está: ${rastreado}`,
  );
  assert.equal(inserirCheckoutNaResposta("Aqui está o checkout.", checkout, rastreado, null), `Aqui está o checkout.\n\n${rastreado}`);
});
