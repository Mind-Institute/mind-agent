/* ============================================================================
 * PORTA DE PRODUTO FECHADO É DONA DA CONVERSA — `mindagent-chat`
 *
 * O defeito medido em 27/10/2026: `rota_ativa` vencia a porta de entrada, e
 * NADA limpa `rota_ativa`. Então o primeiro handoff tirava a pessoa da porta
 * para sempre. Das 4 conversas da porta `institute_learnworlds` que receberam
 * handoff, 4 saíram da MIA e nenhuma voltou — uma pergunta de preço mandava o
 * aluno do LearnWorlds para `cliente_suporte`, que não tem ferramenta nem
 * acesso ao acervo do Summit, e a porta nunca mais o recuperava.
 *
 * A correção NÃO é "toda porta vence". A porta do App é uma recepção, e uma
 * compra iniciada ali tem de continuar na lane de venda. Quem retém é a porta
 * de produto fechado, declarada em `PORTAS_QUE_RETEM_A_CONVERSA`.
 *
 * O que estes testes travam:
 *   1. na porta de produto fechado, a porta decide — mesmo com rota ativa presa;
 *   2. handoff a partir dela não vira estado da conversa;
 *   3. o pedido do modelo continua auditável em `blocos.next_route`;
 *   4. na porta do App e sem porta, `rota_ativa` continua valendo como antes.
 *
 * Como rodar:  npm run test:edge
 * ==========================================================================*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chamar, KIT_COMPLETO, PESSOA_ID } from './helpers/edge-harness.mjs';

const CANAL_WEB = {
  ok: true,
  canal: 'mindagent-web',
  rotas: ['cliente_suporte', 'concierge_summit', 'dash', 'institute', 'mia_summit_2026'],
};

/* As portas como estão em `agentes.canal_competencia.entradas_diretas`. */
const PORTAS = (args) => {
  if (args.p_canal !== 'mindagent-web') return null;
  if (args.p_origem === 'institute_learnworlds') return 'mia_summit_2026';
  if (args.p_origem === 'mind_summit_app') return 'concierge_summit';
  return null;
};

const contexto = ({ origem = null, rotaAtiva = null }) => ({
  participant_profile: { participant_id: PESSOA_ID, name: 'Aluno', interests: [] },
  expires_at: '2026-09-01T12:00:00+00:00',
  messages: [],
  ...(origem ? { origem_codigo: origem } : {}),
  ...(rotaAtiva ? { rota_ativa: rotaAtiva } : {}),
});

const kitDa = (rota) => {
  const kit = structuredClone(KIT_COMPLETO);
  kit.meta.rota = rota;
  return kit;
};

const resposta = (extra = {}) => ({
  answer: 'Resposta oficial de teste.', interests: [], checkout_sent: false,
  checkout_url: null, next_route: null, nome_informado: null,
  email_informado: null, whatsapp_informado: null,
  empresa_informada: null, cargo_informado: null,
  ...extra,
});

test('a porta de produto fechado decide o turno mesmo com rota ativa presa em outra competência', async () => {
  const r = await chamar({
    corpo: { message: 'Em que minuto a Maslach fala das seis áreas?' },
    rpc: {
      mindagent_chat_get_context: contexto({
        origem: 'institute_learnworlds',
        rotaAtiva: 'cliente_suporte',
      }),
      mind_canal_rotas: CANAL_WEB,
      mind_origem_rota: PORTAS,
      mind_agent_kit: kitDa('mia_summit_2026'),
    },
  });

  assert.equal(r.status, 200, JSON.stringify(r.corpo));
  assert.equal(r.corpo.rota, 'mia_summit_2026');
  assert.equal(r.corpo.rota_origem, 'origem_autoritativa');
  // O Kit pedido é o da porta, não o da rota presa: é o que leva o acervo do Summit.
  assert.equal(r.chamada('mind_agent_kit').args.p_rota, 'mia_summit_2026');
});

test('handoff a partir da porta de produto fechado NÃO vira estado da conversa', async () => {
  const r = await chamar({
    corpo: { message: 'Quanto custa o ingresso Prime?' },
    rpc: {
      mindagent_chat_get_context: contexto({ origem: 'institute_learnworlds' }),
      mind_canal_rotas: CANAL_WEB,
      mind_origem_rota: PORTAS,
      mind_agent_kit: kitDa('mia_summit_2026'),
    },
    modelo: resposta({
      answer: 'Preço eu não tenho aqui — veja na página de ingressos.',
      next_route: 'cliente_suporte',
    }),
  });

  assert.equal(r.status, 200, JSON.stringify(r.corpo));
  const salva = r.chamadasDe('mindagent_chat_save_message').at(-1);
  assert.equal(salva.args.p_role, 'assistant');

  // O que o modelo pediu continua auditável; o que ficou valendo é nada.
  assert.equal(salva.args.p_blocks.next_route, 'cliente_suporte');
  assert.equal(salva.args.p_blocks.rota_ativa, null);
  assert.equal(salva.args.p_blocks.state, undefined,
    `state não pode carregar rota_ativa: ${JSON.stringify(salva.args.p_blocks.state)}`);

  // E a decisão fica medível no log, não só na ausência de escrita.
  assert.ok(r.evento('handoff_nao_persistido_porta_dedicada'),
    'a retenção pela porta precisa sair no log');

  // A resposta do turno chega inteira: declinar o assunto não é silêncio.
  assert.match(String(r.corpo.answer), /página de ingressos/);
});

test('a porta do App continua sendo recepção: a lane de venda segura a conversa', async () => {
  // Regressão que a correção NÃO pode causar. O concierge existe para despachar, e
  // uma compra iniciada precisa continuar na venda — senão o upgrade volta para a
  // recepção no meio do checkout.
  const r = await chamar({
    corpo: { message: 'quero fazer upgrade' },
    rpc: {
      mindagent_chat_get_context: contexto({
        origem: 'mind_summit_app',
        rotaAtiva: 'summit_b2c',
      }),
      mind_canal_rotas: { ...CANAL_WEB, rotas: [...CANAL_WEB.rotas, 'summit_b2c'] },
      mind_origem_rota: PORTAS,
      mind_agent_kit: kitDa('summit_b2c'),
    },
  });

  assert.equal(r.status, 200, JSON.stringify(r.corpo));
  assert.equal(r.corpo.rota, 'summit_b2c');
  assert.equal(r.corpo.rota_origem, 'rota_ativa');
});

test('sem porta, a rota ativa continua vencendo o Router', async () => {
  const r = await chamar({
    corpo: { message: 'Voltando ao meu caso' },
    rpc: {
      mindagent_chat_get_context: contexto({ rotaAtiva: 'cliente_suporte' }),
      mind_canal_rotas: CANAL_WEB,
      mind_origem_rota: PORTAS,
      mind_agent_kit: kitDa('cliente_suporte'),
      analise_config: undefined,
    },
  });

  assert.equal(r.status, 200, JSON.stringify(r.corpo));
  assert.equal(r.corpo.rota, 'cliente_suporte');
  assert.equal(r.corpo.rota_origem, 'rota_ativa');
  // Sem porta, o Router nem é consultado quando há rota ativa — comportamento antigo.
  assert.ok(!r.rpcs.includes('analise_config'));
});

test('sem porta, o handoff continua sendo persistido', async () => {
  const r = await chamar({
    corpo: { message: 'Quero falar de ingresso' },
    rpc: {
      mindagent_chat_get_context: contexto({ rotaAtiva: 'cliente_suporte' }),
      mind_canal_rotas: CANAL_WEB,
      mind_origem_rota: PORTAS,
      mind_agent_kit: kitDa('cliente_suporte'),
    },
    modelo: resposta({ answer: 'Te levo para o concierge.', next_route: 'concierge_summit' }),
  });

  assert.equal(r.status, 200, JSON.stringify(r.corpo));
  const salva = r.chamadasDe('mindagent_chat_save_message').at(-1);
  assert.equal(salva.args.p_blocks.rota_ativa, 'concierge_summit');
  assert.deepEqual(salva.args.p_blocks.state, { rota_ativa: 'concierge_summit' });
});
