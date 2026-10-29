/* ============================================================================
 * HISTÓRICO DE CONVERSAS — `mindagent-chat`
 *
 * O aluno sai da página e volta: a conversa tem de estar lá, e as outras
 * também. Três peças, e este arquivo trava as três no handler REAL:
 *
 *   1. listar e abrir saem ANTES do Gate, do Kit e do modelo — ler banco não
 *      paga o preço de um turno;
 *   2. a identidade do LearnWorlds é aceita e vai ao banco COM o id do aluno,
 *      que é o que liga a conversa à conta em vez de ao navegador;
 *   3. o título é pedido só no primeiro turno e viaja em `state`, a mesma
 *      estrada de `rota_ativa`.
 *
 * Como rodar:  npm run test:edge
 * ==========================================================================*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chamar, KIT_COMPLETO, PESSOA_ID } from './helpers/edge-harness.mjs';

const SESSAO = {
  id: '55555555-5555-4555-8555-555555555555',
  conversation_id: '66666666-6666-4666-8666-666666666666',
  token: 'a'.repeat(64),
};
const OUTRA_CONVERSA = '77777777-7777-4777-8777-777777777777';

const IDENTIDADE_LW = {
  email: 'aluno@exemplo.com',
  name: 'Aluno de Teste',
  source: 'learnworlds',
  learnworlds_user_id: '6a8ccfdec7bbf584c706bead',
};

const contexto = {
  participant_profile: { participant_id: PESSOA_ID, interests: [] },
  expires_at: '2026-11-01T12:00:00+00:00',
  messages: [],
  history: [],
};

const resposta = (extra = {}) => ({
  answer: 'Resposta oficial de teste.', interests: [], checkout_sent: false,
  checkout_url: null, next_route: null, nome_informado: null,
  email_informado: null, whatsapp_informado: null,
  empresa_informada: null, cargo_informado: null,
  ...extra,
});

test('listar conversas não chama Gate, Kit nem modelo', async () => {
  const r = await chamar({
    corpo: { historico: 'listar', session: SESSAO },
    rpc: {
      mindagent_chat_get_context: contexto,
      mindagent_chat_conversas: {
        ok: true,
        conversas: [{ id: OUTRA_CONVERSA, titulo: 'Burnout e desenho do trabalho', mensagens: 4 }],
      },
    },
  });

  assert.equal(r.status, 200, JSON.stringify(r.corpo));
  assert.equal(r.corpo.conversas[0].titulo, 'Burnout e desenho do trabalho');
  // O ponto do atalho: nada do caminho caro foi tocado.
  for (const caro of ['mind_rota_capacidade', 'mind_agent_kit', 'mindagent_chat_get_context']) {
    assert.ok(!r.rpcs.includes(caro), `listar não pode chamar ${caro}`);
  }
  assert.equal(r.openai.length, 0, 'listar não pode chamar o modelo');
  // A sessão volta junto: ela pode ter nascido agora.
  assert.equal(r.corpo.session.id, SESSAO.id);
});

test('abrir uma conversa devolve as mensagens e passa a sessão para ela', async () => {
  const r = await chamar({
    corpo: { historico: OUTRA_CONVERSA, session: SESSAO },
    rpc: {
      mindagent_chat_get_context: contexto,
      mindagent_chat_abrir: {
        ok: true,
        conversation_id: OUTRA_CONVERSA,
        titulo: 'Plano de 30 dias',
        mensagens: [
          { papel: 'user', conteudo: 'me monta um plano' },
          { papel: 'assistant', conteudo: 'Semana 1 — diagnóstico' },
        ],
      },
    },
  });

  assert.equal(r.status, 200, JSON.stringify(r.corpo));
  assert.equal(r.corpo.mensagens.length, 2);
  assert.equal(r.corpo.titulo, 'Plano de 30 dias');
  // Sem isto o bloco mostraria o histórico e mandaria a próxima mensagem para
  // a conversa errada.
  assert.equal(r.corpo.session.conversation_id, OUTRA_CONVERSA);
  assert.equal(r.openai.length, 0);
});

test('conversa de outra pessoa não abre, e o erro não diz qual dos dois motivos', async () => {
  const r = await chamar({
    corpo: { historico: OUTRA_CONVERSA, session: SESSAO },
    rpc: {
      mindagent_chat_get_context: contexto,
      mindagent_chat_abrir: { __erro: 'invalid_chat_conversation' },
    },
  });

  assert.equal(r.status, 404);
  assert.equal(r.corpo.error.code, 'conversa_nao_encontrada');
  assert.doesNotMatch(JSON.stringify(r.corpo), /outra pessoa|nao e sua|not yours/i);
});

test('a identidade do LearnWorlds chega ao banco com o id do aluno', async () => {
  // Antes de 29/10 o runtime só aceitava `yazo_url` e esta chamada não acontecia:
  // a pessoa nascia do usuário anônimo do Supabase, uma por navegador.
  const r = await chamar({
    corpo: { message: 'oi', session: SESSAO, identity: IDENTIDADE_LW },
    rpc: { mindagent_chat_get_context: contexto },
  });

  assert.equal(r.status, 200, JSON.stringify(r.corpo));
  const bind = r.chamada('mindagent_chat_bind_identity');
  assert.ok(bind, 'a identidade do LearnWorlds precisa ser vinculada');
  assert.equal(bind.args.p_email, 'aluno@exemplo.com');
  assert.equal(bind.args.p_learnworlds_user_id, '6a8ccfdec7bbf584c706bead');
});

test('id do aluno fora de formato não vira identificador', async () => {
  const r = await chamar({
    corpo: {
      message: 'oi', session: SESSAO,
      identity: { ...IDENTIDADE_LW, learnworlds_user_id: 'curto' },
    },
    rpc: { mindagent_chat_get_context: contexto },
  });

  assert.equal(r.status, 200);
  assert.equal(r.chamada('mindagent_chat_bind_identity').args.p_learnworlds_user_id, null);
});

test('o título é pedido no primeiro turno e vai ao writer por state', async () => {
  const r = await chamar({
    corpo: { message: 'me explica burnout', session: SESSAO },
    rpc: { mindagent_chat_get_context: contexto },
    modelo: resposta({ titulo: 'Burnout e desenho do trabalho' }),
  });

  assert.equal(r.status, 200, JSON.stringify(r.corpo));
  const schema = r.openai.find((c) => c.url.endsWith('/v1/responses')).corpo.text.format.schema;
  assert.ok(schema.properties.titulo, 'o primeiro turno precisa pedir título');
  assert.ok(schema.required.includes('titulo'), 'strict exige o campo em required');

  const salva = r.chamadasDe('mindagent_chat_save_message').at(-1);
  assert.deepEqual(salva.args.p_blocks.state, { titulo: 'Burnout e desenho do trabalho' });
});

test('com histórico, o título não é pedido de novo', async () => {
  // Renomear a conversa a cada turno trocaria o nome dela debaixo do aluno.
  const r = await chamar({
    corpo: { message: 'e sobre cinismo?', session: SESSAO },
    rpc: {
      mindagent_chat_get_context: {
        ...contexto,
        history: [{ role: 'user', content: 'me explica burnout' }],
      },
    },
  });

  assert.equal(r.status, 200, JSON.stringify(r.corpo));
  const schema = r.openai.find((c) => c.url.endsWith('/v1/responses')).corpo.text.format.schema;
  assert.equal(schema.properties.titulo, undefined);
  assert.ok(!schema.required.includes('titulo'));
});
