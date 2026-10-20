#!/usr/bin/env node
/* ============================================================================
 * FLUXO COMPLETO DO VENDEDOR NO WHATSAPP — Institute, Dash e transferência.
 *
 * Este teste SOBE O HANDLER DE VERDADE. Ele lê o fonte versionado de
 * `treble-inbound-agent/index.ts`, tira os imports, roda o resto num contexto de
 * `node:vm` e exercita o `Deno.serve` que o runtime registra. Banco e OpenAI são
 * dublês determinísticos — não há rede, não há Deno, não há Supabase.
 *
 * Por que harness e não asserção sobre o texto do fonte: as perguntas que esta
 * entrega precisa responder são de COMPORTAMENTO EM SEQUÊNCIA — a agenda do Summit
 * chega ao modelo neste turno? o link sai com a âncora? o reenvio responde duas
 * vezes? Nenhuma delas se prova lendo string.
 *
 * O que ele cobre, na ordem do turno real:
 *   1. mensagem recebida e persistida antes de tudo
 *   2. classificação (atalho comercial e Router)
 *   3. consulta ao Kit e Capability Gate
 *   4. resposta comercial do Institute, com preço válido
 *   5. continuidade da conversa (histórico chega ao modelo)
 *   6. encaminhamento para compra (página oficial com #ancora)
 *   7. transferência para humano (rota de outra lane e Gate fechado)
 *   8. reenvio da mesma mensagem não gera resposta duplicada
 *   9. erro no modelo não gera silêncio
 *
 * O QUE ELE NÃO PROVA, e nenhum teste offline prova: que a Treble chama o endpoint
 * e que a mensagem chega no aparelho. Isso é E2E com WhatsApp controlado.
 *
 *   node tests/vendedor_institute_dash_e2e.mjs
 * ==========================================================================*/

import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
import vm from "node:vm";
import { webcrypto } from "node:crypto";

import { decidirGuardrailPreco, precosOficiais } from "../supabase/functions/treble-inbound-agent/guardrail-preco.ts";
import {
  checkoutCurto,
  checkoutRastreado,
  escolherCheckoutOficial,
  escolherLinkOficial,
  idEventoCheckout,
  inserirCheckoutNaResposta,
  inserirLinkOficialNaResposta,
} from "../supabase/functions/_shared/checkout-attribution.ts";
import { rotaComercialRapida } from "../supabase/functions/_shared/treble-commercial-route.ts";
import {
  executarChamadas,
  esforcoDeRaciocinio,
  extrairChamadas,
  MAX_RODADAS_TOOL,
  ORCAMENTO_TURNO_MS,
  produtoDoContexto,
  toolsDeIntelligence,
} from "../supabase/functions/_shared/agent-intelligence.ts";

let ok = 0;
const falhas = [];
function check(nome, condicao, detalhe) {
  if (condicao) { ok++; console.log(`  ✓ ${nome}`); }
  else { falhas.push(nome); console.log(`  ✗ ${nome}${detalhe ? `\n      ${detalhe}` : ""}`); }
}

/* ------------------------------------------------------------- o fonte vivo */

const FONTE = new URL("../supabase/functions/treble-inbound-agent/index.ts", import.meta.url);

/** Tira os imports — inclusive os de várias linhas, que uma regex por linha perde. */
function semImports(src) {
  const saida = [];
  let dentro = false;
  for (const linha of src.split("\n")) {
    if (dentro) { if (/;\s*$/.test(linha)) dentro = false; continue; }
    if (/^import\b/.test(linha)) { if (!/;\s*$/.test(linha)) dentro = true; continue; }
    saida.push(linha);
  }
  return saida.join("\n");
}

const fonteBruta = readFileSync(FONTE, "utf8");
const codigo = stripTypeScriptTypes(semImports(fonteBruta));
check(
  "o fonte do runtime carrega sem import pendente",
  !/^\s*import\b/m.test(semImports(fonteBruta)),
);

/* ------------------------------------------------------------- o catálogo */
/* Mesma FORMA que `mind_kit_institute_catalogo` devolve em produção (conferida em
 * 20/10/2026), com a âncora que a migration deste commit grava em
 * `intelligence.config.institute_catalogo_links`. */

const KIT_INSTITUTE = {
  institute_catalogo: {
    bloco: "institute_catalogo",
    como_comprar: "Na página oficial do programa, o botão de inscrição leva ao pagamento seguro.",
    contato_time_institute: {
      time_institute_whatsapp: "(11) 93020-7733",
      time_institute_link: "https://wa.me/5511930207733",
    },
    programas: [
      {
        nome: "Certificação Avançada em Liderança Positiva",
        codigo: "certificacao-lideranca-positiva",
        pagina_oficial: "https://joinmind.com.br/certificacao-avancada#inscricao",
        inicio: "16/02/2027",
        ofertas: [{
          nome: "Certificação Avançada em Liderança Positiva",
          faixa: "preço regular (sem prazo)",
          a_vista: "R$ 4.997",
          parcelado: "12x de R$ 416",
        }],
      },
      {
        nome: "Mind Journey",
        codigo: "mind-journey",
        pagina_oficial: "https://joinmind.com.br/programa/mind-journey#inscricao",
        inicio: "01/10/2026",
        ofertas: [{
          nome: "Mind Journey",
          faixa: "preço regular (sem prazo)",
          a_vista: "R$ 1.997",
          parcelado: "12x de R$ 166",
        }],
      },
    ],
  },
  product_intelligence: { bloco: "product_intelligence", produtos: ["institute"] },
};

const KIT_DASH = {
  product_intelligence: {
    bloco: "product_intelligence",
    produtos: ["dash"],
    resumo: "Diagnóstico, desenho, implementação e acompanhamento de transformação organizacional.",
  },
};

/* A agenda do Summit, como `mindagent_chat_search` a devolve. Ela é a tentação: se
 * chegar ao modelo num turno de Institute, a resposta vira Summit. */
const AGENDA_SUMMIT = {
  sessions: [{ titulo: "Abertura do Mind Summit 2026", dia: "2026-09-16" }],
  speakers: [{ nome: "Adriana Drulla" }],
  mind: { evento: "Mind Summit 2026" },
};

/* ------------------------------------------------------------- o laboratório */

function montarAmbiente({
  rotaDoRouter = "institute",
  gate = { ok: true, pode_executar: true, needs_human: false, reason: null },
  kitStructured = KIT_INSTITUTE,
  playbook = "VOCÊ É O AGENTE DO MIND INSTITUTE. Você vende o Mind Institute.",
  kitDisponivel = true,
  respostaDoModelo,
  historico = [],
  jaRespondida = null,
  modeloQuebra = false,
} = {}) {
  const chamadas = { rpc: [], openaiInputs: [], routerChamado: 0 };

  const rpcRespostas = {
    treble_agent_config: {
      webhook_token: "tok-teste",
      openai_model: "gpt-5.4",
      timeout_ms: "20000",
      router_timeout_ms: "12000",
      bloco_agenda_busca: "true",
      produto_padrao: "mind-summit-2026",
    },
    analise_config: { analise_token: "router-tok" },
    treble_agent_start: {
      conversation_id: "11111111-1111-4111-8111-111111111111",
      mensagem_id: "22222222-2222-4222-8222-222222222222",
      mensagem_duplicada: false,
      pessoa_encontrada: true,
      participante_id: "33333333-3333-4333-8333-333333333333",
      perfil: { nome: "Renata" },
      historico,
      audience: null,
      nome_contato: "Renata",
    },
    treble_agent_resposta_repetida: jaRespondida,
    mindagent_chat_search: AGENDA_SUMMIT,
    mind_rota_capacidade: gate,
    mind_agent_kit: {
      meta: { kit_disponivel: kitDisponivel },
      structured: kitStructured,
      playbook,
      tools: [],
      decisioning: null,
    },
    mind_identificador_validar: { valido: true, motivo: null },
    mind_turno_registrar: { ok: true },
    treble_agent_identificar: { pessoa_encontrada: true },
    mind_pessoa_completar: { ok: true },
    mind_checkout_envio_registrar: { ok: true },
  };

  const createClientFake = () => ({
    rpc: async (nome, args) => {
      chamadas.rpc.push({ nome, args });
      if (!(nome in rpcRespostas)) return { data: null, error: { message: `rpc_desconhecida_${nome}` } };
      return { data: rpcRespostas[nome], error: null };
    },
  });

  const fetchFake = async (url, opcoes) => {
    const alvo = String(url);
    if (alvo.includes("/functions/v1/router")) {
      chamadas.routerChamado++;
      return new Response(JSON.stringify({
        ok: true,
        conversa_id: "11111111-1111-4111-8111-111111111111",
        rota: rotaDoRouter,
        precisa_esclarecer: rotaDoRouter === null,
        candidatas: rotaDoRouter === null ? ["institute", "dash"] : [],
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    if (alvo.includes("api.openai.com")) {
      chamadas.openaiInputs.push(JSON.parse(opcoes.body));
      if (modeloQuebra) return new Response("erro", { status: 500 });
      return new Response(JSON.stringify({
        output_text: JSON.stringify(respostaDoModelo),
      }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    throw new Error(`fetch inesperado: ${alvo}`);
  };

  let handler;
  const contexto = {
    Request, Response, URL, URLSearchParams, TextEncoder, TextDecoder,
    AbortController, DOMException, setTimeout, clearTimeout,
    crypto: webcrypto,
    console: { info() {}, warn() {}, error() {}, log() {} },
    fetch: fetchFake,
    createClient: createClientFake,
    decidirGuardrailPreco, precosOficiais,
    checkoutCurto, checkoutRastreado, escolherCheckoutOficial, escolherLinkOficial,
    idEventoCheckout, inserirCheckoutNaResposta, inserirLinkOficialNaResposta,
    rotaComercialRapida,
    executarChamadas, esforcoDeRaciocinio, extrairChamadas, MAX_RODADAS_TOOL,
    ORCAMENTO_TURNO_MS, produtoDoContexto, toolsDeIntelligence,
    Deno: {
      serve: (fn) => { handler = fn; },
      env: {
        get: (k) => ({
          SUPABASE_URL: "https://teste.supabase.co",
          SUPABASE_SERVICE_ROLE_KEY: "service-key",
          OPENAI_API_KEY: "openai-key",
        })[k],
      },
    },
  };

  vm.runInNewContext(codigo, contexto);
  return { handler, chamadas };
}

function respostaPadrao(extra = {}) {
  return {
    answer: "resposta",
    audience: "institute",
    intent: "duvida",
    ticket_interest: null,
    objection: null,
    needs_human: false,
    checkout_sent: false,
    checkout_url: null,
    stage: "descoberta",
    desfecho: null,
    nome_informado: null,
    email_informado: null,
    whatsapp_informado: null,
    empresa_informada: null,
    cargo_informado: null,
    ...extra,
  };
}

async function turno(ambiente, mensagem, extras = {}) {
  const req = new Request("https://teste.supabase.co/functions/v1/treble-inbound-agent?token=tok-teste", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      session_external_id: "sessao-1",
      actual_response: mensagem,
      cellphone: "+5511999999999",
      ...extras,
    }),
  });
  const res = await ambiente.handler(req);
  return { status: res.status, body: await res.json() };
}

const chave = (body, k) =>
  (body.user_session_keys ?? []).find((e) => e.key === k)?.value ?? null;

/* ========================================================================== */

console.log("\n1. INSTITUTE — classificação, kit, resposta comercial e preço\n");
{
  const amb = montarAmbiente({
    rotaDoRouter: "institute",
    respostaDoModelo: respostaPadrao({
      answer: "A Certificação Avançada em Liderança Positiva sai R$ 4.997 à vista ou 12x de R$ 416.",
      intent: "preco",
      stage: "orientando_escolha",
    }),
  });
  const { status, body } = await turno(amb, "Quanto custa a Certificação Avançada?");

  check("o turno responde 200", status === 200, `status=${status}`);
  check("a fala é persistida antes de tudo (treble_agent_start é a 1ª RPC de turno)",
    amb.chamadas.rpc.findIndex((c) => c.nome === "treble_agent_start") <
      amb.chamadas.rpc.findIndex((c) => c.nome === "mind_rota_capacidade"));
  check("o Router foi consultado", amb.chamadas.routerChamado === 1);
  check("o Capability Gate foi consultado",
    amb.chamadas.rpc.some((c) => c.nome === "mind_rota_capacidade"));
  check("o Kit foi carregado para institute",
    amb.chamadas.rpc.some((c) => c.nome === "mind_agent_kit" && c.args.p_rota === "institute"));
  check("o preço oficial do catálogo NÃO é barrado pelo guardrail",
    chave(body, "resposta_ia")?.includes("R$ 4.997"), chave(body, "resposta_ia"));
  check("não pede humano", chave(body, "needs_human") === "false");
  check("audience derivada da rota", chave(body, "audience") === "institute");
}

console.log("\n2. INSTITUTE — o preço inventado continua barrado\n");
{
  const amb = montarAmbiente({
    rotaDoRouter: "institute",
    respostaDoModelo: respostaPadrao({
      answer: "A Certificação Avançada sai por R$ 2.500 à vista.",
    }),
  });
  const { body } = await turno(amb, "Quanto custa?");
  check("preço fora do catálogo vira transferência",
    chave(body, "needs_human") === "true", chave(body, "resposta_ia"));
  check("o valor inventado não chega ao lead",
    !String(chave(body, "resposta_ia")).includes("2.500"));
}

console.log("\n3. INSTITUTE — encaminhamento para compra com a âncora\n");
{
  const amb = montarAmbiente({
    rotaDoRouter: "institute",
    respostaDoModelo: respostaPadrao({
      answer: "Perfeito. A Certificação Avançada é R$ 4.997 à vista.",
      checkout_sent: true,
      checkout_url: "https://joinmind.com.br/certificacao-avancada#inscricao",
      desfecho: "checkout_enviado",
    }),
  });
  const { body } = await turno(amb, "Quero me inscrever");
  const resposta = String(chave(body, "resposta_ia"));

  check("o link oficial sai na resposta",
    resposta.includes("https://joinmind.com.br/certificacao-avancada#inscricao"), resposta);
  check("a âncora #inscricao é preservada", resposta.includes("#inscricao"));
  check("checkout_sent é verdadeiro", chave(body, "checkout_sent") === "true");
  check("NÃO registra evento de checkout (página oficial não é carrinho)",
    !amb.chamadas.rpc.some((c) => c.nome === "mind_checkout_envio_registrar"));
  check("o link não ganha UTM de rastreio", !resposta.includes("utm_source"));
}

console.log("\n4. INSTITUTE — link que o Kit não mandou não sai\n");
{
  const amb = montarAmbiente({
    rotaDoRouter: "institute",
    respostaDoModelo: respostaPadrao({
      answer: "Segue o link.",
      checkout_sent: true,
      checkout_url: "https://joinmind.com.br/promocao-secreta#inscricao",
    }),
  });
  const { body } = await turno(amb, "Manda o link");
  check("URL inventada vira transferência, não link",
    chave(body, "needs_human") === "true");
  check("a URL inventada não chega ao lead",
    !String(chave(body, "resposta_ia")).includes("promocao-secreta"));
}

console.log("\n5. A PERGUNTA SOBRE FERRAMENTAS NÃO VIRA SUMMIT  [bloqueia lançamento]\n");
{
  for (
    const pergunta of [
      "Quais ferramentas vocês têm para trabalhar isso?",
      "O que vocês oferecem para desenvolver meu time?",
      "Vocês têm formação para RH?",
      "Quero desenvolver minhas competências de liderança",
    ]
  ) {
    const amb = montarAmbiente({
      rotaDoRouter: "institute",
      respostaDoModelo: respostaPadrao({ answer: "Posso te ajudar com isso." }),
    });
    await turno(amb, pergunta);

    const entrada = amb.chamadas.openaiInputs.at(-1);
    const payload = JSON.parse(entrada.input[0].content);

    check(`o Router decide a rota, o atalho não sequestra — "${pergunta.slice(0, 34)}…"`,
      amb.chamadas.routerChamado === 1);
    check(`a agenda do Summit NÃO vai ao modelo — "${pergunta.slice(0, 34)}…"`,
      Object.keys(payload.AGENDA_E_PALESTRANTES ?? {}).length === 0,
      JSON.stringify(payload.AGENDA_E_PALESTRANTES));
    check(`nenhuma sessão/palestrante do Summit no payload — "${pergunta.slice(0, 34)}…"`,
      !JSON.stringify(payload).includes("Mind Summit 2026"));
  }
}

console.log("\n6. A agenda do Summit continua chegando em turno de Summit\n");
{
  const amb = montarAmbiente({
    rotaDoRouter: "summit_b2c",
    kitStructured: { ofertas: { bloco: "ofertas", ofertas: [] } },
    playbook: "playbook do summit",
    respostaDoModelo: respostaPadrao({ answer: "Oi!", audience: "b2c" }),
  });
  await turno(amb, "Quero um ingresso para o Summit");
  const payload = JSON.parse(amb.chamadas.openaiInputs.at(-1).input[0].content);
  check("em summit_b2c a agenda vai ao modelo",
    Object.keys(payload.AGENDA_E_PALESTRANTES ?? {}).length > 0);
}

console.log("\n7. DASH — consultivo, e qualquer preço é barrado\n");
{
  const amb = montarAmbiente({
    rotaDoRouter: "dash",
    kitStructured: KIT_DASH,
    playbook: "VOCÊ É O AGENTE DO MIND DASH. Não invente preço nem proposta.",
    respostaDoModelo: respostaPadrao({
      answer: "Entendi o problema. Um diagnóstico organizacional olharia clima e liderança.",
      audience: "dash",
    }),
  });
  const { body } = await turno(amb, "Preciso estruturar um diagnóstico de clima");
  check("dash executa e responde", chave(body, "needs_human") === "false");
  check("audience derivada da rota", chave(body, "audience") === "dash");

  const amb2 = montarAmbiente({
    rotaDoRouter: "dash",
    kitStructured: KIT_DASH,
    playbook: "playbook do dash",
    respostaDoModelo: respostaPadrao({
      answer: "Um projeto desses fica em torno de R$ 80.000.",
      audience: "dash",
    }),
  });
  const r2 = await turno(amb2, "Quanto custa um projeto?");
  check("preço no Dash é barrado (kit sem oferta não autoriza valor)",
    chave(r2.body, "needs_human") === "true");
  check("o valor não chega ao lead",
    !String(chave(r2.body, "resposta_ia")).includes("80.000"));
}

console.log("\n8. TRANSFERÊNCIA — cliente_suporte e Gate fechado\n");
{
  const amb = montarAmbiente({
    rotaDoRouter: "cliente_suporte",
    gate: { ok: true, pode_executar: true, needs_human: false, reason: null },
    respostaDoModelo: respostaPadrao(),
  });
  const { status, body } = await turno(amb, "Meu pagamento deu erro");
  check("cliente_suporte transfere (rota de outra lane)", chave(body, "needs_human") === "true");
  check("transferência responde 200, não erro", status === 200);
  check("o Kit NÃO é carregado para rota que este runtime não executa",
    !amb.chamadas.rpc.some((c) => c.nome === "mind_agent_kit"));

  const amb2 = montarAmbiente({
    rotaDoRouter: "institute",
    gate: { ok: true, pode_executar: false, needs_human: true, reason: "missing_kit" },
    respostaDoModelo: respostaPadrao(),
  });
  const r2 = await turno(amb2, "Quanto custa a formação?");
  check("Gate fechado força transferência mesmo em rota executável",
    chave(r2.body, "needs_human") === "true");
}

console.log("\n9. CONTINUIDADE — o histórico chega ao modelo\n");
{
  const amb = montarAmbiente({
    rotaDoRouter: "institute",
    historico: [
      { papel: "lead", conteudo: "Trabalho com RH numa indústria" },
      { papel: "agente", conteudo: "Legal! O que você quer desenvolver?" },
    ],
    respostaDoModelo: respostaPadrao({ answer: "Pelo que você contou do RH..." }),
  });
  await turno(amb, "Quero algo sobre segurança psicológica");
  const payload = JSON.parse(amb.chamadas.openaiInputs.at(-1).input[0].content);
  check("a conversa anterior vai no payload",
    JSON.stringify(payload).includes("Trabalho com RH numa indústria"));
}

console.log("\n10. REENVIO — a mesma mensagem não gera resposta duplicada\n");
{
  const amb = montarAmbiente({
    rotaDoRouter: "institute",
    jaRespondida: "A Certificação Avançada sai R$ 4.997 à vista.",
    respostaDoModelo: respostaPadrao({ answer: "resposta NOVA que não deveria existir" }),
  });
  const { status, body } = await turno(amb, "Quanto custa a Certificação Avançada?");

  check("reenvio responde 200", status === 200);
  check("devolve a MESMA resposta de antes",
    chave(body, "resposta_ia") === "A Certificação Avançada sai R$ 4.997 à vista.");
  check("não responde duas coisas diferentes",
    !String(chave(body, "resposta_ia")).includes("NOVA"));
  check("não chama o modelo de novo", amb.chamadas.openaiInputs.length === 0);
  check("não registra um segundo turno",
    !amb.chamadas.rpc.some((c) => c.nome === "mind_turno_registrar"));
}

console.log("\n11. ERRO — falha do modelo não vira silêncio\n");
{
  const amb = montarAmbiente({
    rotaDoRouter: "institute",
    modeloQuebra: true,
    respostaDoModelo: respostaPadrao(),
  });
  const { status, body } = await turno(amb, "Quanto custa?");
  check("falha do modelo responde 200 (a Treble precisa receber algo)", status === 200);
  check("a falha traz fala para o lead", Boolean(chave(body, "resposta_ia")));
  check("a falha aciona transferência", chave(body, "needs_human") === "true");
}

console.log("\n12. TOKEN — integração mal configurada continua alta\n");
{
  const amb = montarAmbiente({ respostaDoModelo: respostaPadrao() });
  const req = new Request("https://teste.supabase.co/functions/v1/treble-inbound-agent?token=errado", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ session_external_id: "s", actual_response: "oi" }),
  });
  const res = await amb.handler(req);
  check("token errado é 401, não transferência", res.status === 401);
}

/* ========================================================================== */

console.log(`\n${ok}/${ok + falhas.length} verificações passaram.`);
if (falhas.length) {
  console.log(`\n✗ ${falhas.length} falha(s):`);
  for (const f of falhas) console.log(`   - ${f}`);
  process.exit(1);
}
