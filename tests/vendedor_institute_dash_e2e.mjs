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
  gatePorRota = null,
  kitStructured = KIT_INSTITUTE,
  playbook = "VOCÊ É O AGENTE DO MIND INSTITUTE. Você vende o Mind Institute.",
  kitDisponivel = true,
  respostaDoModelo,
  historico = [],
  jaRespondida = null,
  mensagemDuplicada = false,
  modeloQuebra = false,
  rotaAtiva = null,
  rotasDoCanal = ["cliente_suporte", "dash", "institute"],
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
      mensagem_duplicada: mensagemDuplicada,
      pessoa_encontrada: true,
      participante_id: "33333333-3333-4333-8333-333333333333",
      perfil: { nome: "Renata" },
      historico,
      audience: null,
      nome_contato: "Renata",
      rota_ativa: rotaAtiva,
    },
    treble_agent_resposta_repetida: jaRespondida,
    mindagent_chat_search: AGENDA_SUMMIT,
    mind_canal_rotas: { ok: true, canal: "whatsapp", rotas: rotasDoCanal },
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
      // O Gate é consultado duas vezes num turno com troca: pela rota do turno e
      // pela rota de destino. `gatePorRota` permite responder diferente para cada.
      if (nome === "mind_rota_capacidade" && gatePorRota && args?.p_rota in gatePorRota) {
        return { data: gatePorRota[args.p_rota], error: null };
      }
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
    next_route: null,
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

console.log("\n10. DUPLICIDADE — reentrega do evento vs. duas falas com o mesmo texto\n");
{
  // (a) A MESMA ENTREGA, de novo. A ingestão reconhece pelo client_msg_id e marca
  // `mensagem_duplicada`. Tem de devolver a resposta daquele turno, sem modelo.
  const amb = montarAmbiente({
    rotaDoRouter: "institute",
    mensagemDuplicada: true,
    jaRespondida: "A Certificação Avançada sai R$ 4.997 à vista.",
    respostaDoModelo: respostaPadrao({ answer: "resposta NOVA que não deveria existir" }),
  });
  const { status, body } = await turno(amb, "Quanto custa a Certificação Avançada?", { message_id: "evt-1" });

  check("reentrega responde 200", status === 200);
  check("reentrega devolve a MESMA resposta de antes",
    chave(body, "resposta_ia") === "A Certificação Avançada sai R$ 4.997 à vista.");
  check("reentrega não chama o modelo", amb.chamadas.openaiInputs.length === 0);
  check("reentrega não registra um segundo turno",
    !amb.chamadas.rpc.some((c) => c.nome === "mind_turno_registrar"));
  check("a reentrega não é limitada a 90 s",
    amb.chamadas.rpc.find((c) => c.nome === "treble_agent_resposta_repetida")
      ?.args?.p_janela_segundos > 90,
    String(amb.chamadas.rpc.find((c) => c.nome === "treble_agent_resposta_repetida")?.args?.p_janela_segundos));

  // (b) DUAS MENSAGENS DISTINTAS COM O MESMO TEXTO. Evento novo, id novo. A pessoa
  // disse "sim" de novo e espera resposta nova — não pode ser engolido.
  const amb2 = montarAmbiente({
    rotaDoRouter: "institute",
    mensagemDuplicada: false,
    jaRespondida: "Resposta do primeiro 'sim' — não pode voltar.",
    respostaDoModelo: respostaPadrao({ answer: "Claro, te explico de novo." }),
  });
  const r2 = await turno(amb2, "sim", { message_id: "evt-2" });

  check("fala repetida COM id de evento é respondida de novo",
    chave(r2.body, "resposta_ia") === "Claro, te explico de novo.",
    String(chave(r2.body, "resposta_ia")));
  check("e o modelo é chamado", amb2.chamadas.openaiInputs.length === 1);
  check("e a janela de texto nem é consultada",
    !amb2.chamadas.rpc.some((c) => c.nome === "treble_agent_resposta_repetida"));
  check("e o turno é registrado",
    amb2.chamadas.rpc.some((c) => c.nome === "mind_turno_registrar"));

  // (c) SEM id de evento não há como distinguir: a janela de texto continua sendo a
  // única defesa, e continua valendo 90 s.
  const amb3 = montarAmbiente({
    rotaDoRouter: "institute",
    mensagemDuplicada: false,
    jaRespondida: "Resposta anterior.",
    respostaDoModelo: respostaPadrao({ answer: "resposta nova" }),
  });
  const r3 = await turno(amb3, "sim");
  check("sem id de evento, a janela de texto ainda protege",
    chave(r3.body, "resposta_ia") === "Resposta anterior.");
  check("e ela continua sendo de 90 s",
    amb3.chamadas.rpc.find((c) => c.nome === "treble_agent_resposta_repetida")
      ?.args?.p_janela_segundos === 90);

  // (d) Reentrega de um evento que NUNCA foi respondido não pode virar silêncio.
  const amb4 = montarAmbiente({
    rotaDoRouter: "institute",
    mensagemDuplicada: true,
    jaRespondida: null,
    respostaDoModelo: respostaPadrao({ answer: "Agora sim, respondendo." }),
  });
  const r4 = await turno(amb4, "Quanto custa?", { message_id: "evt-3" });
  check("reentrega sem resposta anterior é processada, não engolida",
    chave(r4.body, "resposta_ia") === "Agora sim, respondendo.",
    String(chave(r4.body, "resposta_ia")));
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

console.log("\n12. TROCA DE ASSUNTO — next_route, do pedido à efetivação\n");
{
  // O enum de next_route sai da política do canal, não de lista no código.
  const amb = montarAmbiente({
    rotaDoRouter: "institute",
    respostaDoModelo: respostaPadrao({ answer: "Posso ajudar." }),
  });
  await turno(amb, "Oi");
  const schema = amb.chamadas.openaiInputs.at(-1).text.format.schema;
  check("o schema expõe next_route", "next_route" in schema.properties);
  check("o enum de next_route vem da política do canal",
    JSON.stringify(schema.properties.next_route.enum) ===
      JSON.stringify(["cliente_suporte", "dash", "institute", null]),
    JSON.stringify(schema.properties.next_route.enum));
  check("next_route é obrigatório na saída", schema.required.includes("next_route"));

  // Institute -> Dash: o modelo pede, o Gate aprova, o estado persiste.
  const amb2 = montarAmbiente({
    rotaDoRouter: "institute",
    gatePorRota: {
      institute: { ok: true, pode_executar: true, needs_human: false, reason: null },
      dash: { ok: true, pode_executar: true, needs_human: false, reason: null },
    },
    respostaDoModelo: respostaPadrao({
      answer: "Pelo que você descreve, o caminho é diagnóstico organizacional. Qual é o resultado que você precisa atingir?",
      next_route: "dash",
    }),
  });
  await turno(amb2, "Na verdade minha empresa precisa diagnosticar e medir, não me formar");
  const registro = amb2.chamadas.rpc.find((c) => c.nome === "mind_turno_registrar");
  check("a troca aprovada persiste rota_ativa no estado",
    registro?.args?.p_estado?.rota_ativa === "dash",
    JSON.stringify(registro?.args?.p_estado));
  check("o Gate foi consultado para a rota de DESTINO",
    amb2.chamadas.rpc.filter((c) => c.nome === "mind_rota_capacidade")
      .some((c) => c.args.p_rota === "dash"));
  check("a troca é registrada no meta do turno",
    registro?.args?.p_meta?.next_route === "dash");

  // Gate recusa o destino: a conversa continua onde está, sem silêncio.
  const amb3 = montarAmbiente({
    rotaDoRouter: "institute",
    gatePorRota: {
      institute: { ok: true, pode_executar: true, needs_human: false, reason: null },
      dash: { ok: true, pode_executar: false, needs_human: true, reason: "missing_kit" },
    },
    respostaDoModelo: respostaPadrao({ answer: "Entendi, vou te passar.", next_route: "dash" }),
  });
  const r3 = await turno(amb3, "Quero falar de diagnóstico");
  const reg3 = amb3.chamadas.rpc.find((c) => c.nome === "mind_turno_registrar");
  check("troca recusada pelo Gate NÃO persiste rota_ativa",
    reg3?.args?.p_estado?.rota_ativa === undefined,
    JSON.stringify(reg3?.args?.p_estado));
  check("troca recusada não vira silêncio: a resposta sai normalmente",
    String(chave(r3.body, "resposta_ia")).includes("Entendi"));

  // Pedir a própria rota não é troca.
  const amb4 = montarAmbiente({
    rotaDoRouter: "institute",
    respostaDoModelo: respostaPadrao({ answer: "Sigo aqui.", next_route: "institute" }),
  });
  await turno(amb4, "Me fala mais");
  const reg4 = amb4.chamadas.rpc.find((c) => c.nome === "mind_turno_registrar");
  check("pedir a rota atual não grava rota_ativa",
    reg4?.args?.p_estado?.rota_ativa === undefined);
  check("e não gasta uma segunda ida ao Gate",
    amb4.chamadas.rpc.filter((c) => c.nome === "mind_rota_capacidade").length === 1);
}

console.log("\n13. CONTINUIDADE DA TROCA — o turno seguinte já nasce na nova rota\n");
{
  const amb = montarAmbiente({
    rotaAtiva: "dash",
    rotaDoRouter: "institute", // o Router NÃO deve ser chamado
    kitStructured: KIT_DASH,
    playbook: "playbook do dash",
    respostaDoModelo: respostaPadrao({ answer: "Seguindo no diagnóstico.", audience: "dash" }),
  });
  await turno(amb, "Então, sobre o diagnóstico");

  check("a rota ativa vence o Router", amb.chamadas.routerChamado === 0);
  check("a rota ativa vence o atalho comercial",
    amb.chamadas.rpc.some((c) => c.nome === "mind_agent_kit" && c.args.p_rota === "dash"));
  check("o Kit carregado é o da rota ativa",
    amb.chamadas.rpc.find((c) => c.nome === "mind_agent_kit")?.args?.p_rota === "dash");

  // Rota ativa que saiu da política do canal é ignorada, não obedecida.
  const amb2 = montarAmbiente({
    rotaAtiva: "summit_b2c",
    rotaDoRouter: "institute",
    respostaDoModelo: respostaPadrao({ answer: "Oi." }),
  });
  await turno(amb2, "Oi");
  check("rota ativa fora da política do canal é ignorada",
    amb2.chamadas.routerChamado === 1);
  check("e o turno cai na rota que o Router decidiu",
    amb2.chamadas.rpc.find((c) => c.nome === "mind_agent_kit")?.args?.p_rota === "institute");
}

console.log("\n14. SUPORTE CONTINUA COM O TIME — e não tranca a conversa\n");
{
  // `cliente_suporte` está na política do canal e o Gate responde pode_executar=true,
  // mas quem atende é o TIME (decisão de 20/10) e este runtime não executa a rota.
  // Persistir isso como rota ativa prendia a conversa em transferência para sempre:
  // nada limpa `rota_ativa`, então a pessoa nunca mais voltava a ser atendida — nem
  // quando mudasse de assunto. Passar ao time é estado do TURNO, não da conversa.
  const amb = montarAmbiente({
    rotaDoRouter: "institute",
    gatePorRota: {
      institute: { ok: true, pode_executar: true, needs_human: false, reason: null },
      cliente_suporte: { ok: true, pode_executar: true, needs_human: false, reason: null },
    },
    respostaDoModelo: respostaPadrao({
      answer: "Isso é com o time de atendimento. Já te encaminho.",
      next_route: "cliente_suporte",
    }),
  });
  const r1 = await turno(amb, "Meu pagamento do ano passado deu erro");
  const reg = amb.chamadas.rpc.find((c) => c.nome === "mind_turno_registrar");

  check("o turno vai para o time", chave(r1.body, "needs_human") === "true");
  check("a resposta do agente chega junto, sem silêncio",
    String(chave(r1.body, "resposta_ia")).includes("time de atendimento"));
  check("NÃO persiste rota_ativa de lane que este runtime não serve",
    reg?.args?.p_estado?.rota_ativa === undefined,
    JSON.stringify(reg?.args?.p_estado));

  // E a conversa segue viva: o turno seguinte é classificado normalmente.
  const amb2 = montarAmbiente({
    rotaDoRouter: "institute",
    respostaDoModelo: respostaPadrao({ answer: "Claro! A Certificação começa em 16/02/2027." }),
  });
  const r2 = await turno(amb2, "Deixa pra lá. Me fala da Certificação");
  check("depois do suporte, a pessoa volta a ser atendida",
    chave(r2.body, "needs_human") === "false", String(chave(r2.body, "resposta_ia")));
  check("e o turno é roteado de novo, não preso",
    amb2.chamadas.routerChamado === 1);
}

console.log("\n14B. A ROTA ATIVA RESPEITA A INTENÇÃO ATUAL\n");
{
  // Em dash, a pessoa volta a querer formação. O modelo pede a volta e o Gate aprova.
  const amb = montarAmbiente({
    rotaAtiva: "dash",
    kitStructured: KIT_DASH,
    playbook: "playbook do dash",
    gatePorRota: {
      dash: { ok: true, pode_executar: true, needs_human: false, reason: null },
      institute: { ok: true, pode_executar: true, needs_human: false, reason: null },
    },
    respostaDoModelo: respostaPadrao({
      answer: "Pelo que você diz agora, o caminho é desenvolver a competência.",
      next_route: "institute",
      audience: "dash",
    }),
  });
  await turno(amb, "Na verdade quero me formar nisso, não contratar diagnóstico");
  const reg = amb.chamadas.rpc.find((c) => c.nome === "mind_turno_registrar");
  check("a volta para institute é persistida", reg?.args?.p_estado?.rota_ativa === "institute");
  check("o turno atual ainda responde pelo dash (a troca vale do próximo em diante)",
    amb.chamadas.rpc.find((c) => c.nome === "mind_agent_kit")?.args?.p_rota === "dash");

  // Rota ativa cuja execução o Gate fechou não prende a conversa.
  const amb2 = montarAmbiente({
    rotaAtiva: "institute",
    gate: { ok: true, pode_executar: false, needs_human: true, reason: "missing_kit" },
    respostaDoModelo: respostaPadrao(),
  });
  const r2 = await turno(amb2, "E aí?");
  check("rota ativa com Gate fechado transfere, em vez de responder sem Kit",
    chave(r2.body, "needs_human") === "true");
}

console.log("\n15. TOKEN — integração mal configurada continua alta\n");
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
