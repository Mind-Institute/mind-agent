import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chamar, KIT_COMPLETO } from './helpers/edge-harness.mjs';

/* PLAYGROUND (Adriana, 22/10/2026): o mesmo motor do chat, numa conversa de
   teste. Quem diz que é teste é a conversa (`agente = 'mindagent-playground'`,
   gravado pelo banco só para administrador), nunca o corpo da requisição. Em
   teste: a rota vale mesmo com o canal desligado, o Gate tolera só
   `canal_incompativel`, e nada sobre a pessoa é gravado. */

const CONTEXTO_DE_TESTE = {
  participant_profile: { participant_id: '22222222-2222-4222-8222-222222222222', interests: [] },
  expires_at: '2026-09-03T12:00:00+00:00',
  messages: [],
  agente: 'mindagent-playground',
  rota_ativa: 'mia_summit_2026',
};
const CANAL_SEM_A_MIA = { ok: true, canal: 'mindagent-web', rotas: ['cliente_suporte', 'concierge_summit'] };
const GATE_CANAL_DESLIGADO = { ok: true, pode_executar: false, needs_human: true, reason: 'canal_incompativel' };
const SESSAO = { id: '55555555-5555-4555-8555-555555555555', conversation_id: '66666666-6666-4666-8666-666666666666', token: 'a'.repeat(64) };

function kitDaMia() {
  const kit = structuredClone(KIT_COMPLETO);
  kit.meta.rota = 'mia_summit_2026';
  return kit;
}

test('abrir conversa com playground.rota usa a porta de teste do banco', async () => {
  const r = await chamar({
    corpo: { message: 'oi', playground: { rota: 'mia_summit_2026' } },
    rpc: { mindagent_chat_get_context: CONTEXTO_DE_TESTE, mind_canal_rotas: CANAL_SEM_A_MIA, mind_rota_capacidade: GATE_CANAL_DESLIGADO, mind_agent_kit: kitDaMia() },
  });
  assert.equal(r.status, 200, JSON.stringify(r.corpo));
  assert.ok(r.rpcs.includes('mindagent_playground_start'));
  assert.ok(!r.rpcs.includes('mindagent_chat_start'));
  assert.equal(r.corpo.teste, true);
  assert.equal(r.corpo.rota, 'mia_summit_2026');
  assert.equal(r.corpo.rota_origem, 'rota_ativa');
});

test('em teste a rota vale com o canal desligado e nada sobre a pessoa é gravado', async () => {
  const r = await chamar({
    corpo: { message: 'me chamo Ana, meu whatsapp é 11999999999', session: SESSAO },
    rpc: { mindagent_chat_get_context: CONTEXTO_DE_TESTE, mind_canal_rotas: CANAL_SEM_A_MIA, mind_rota_capacidade: GATE_CANAL_DESLIGADO, mind_agent_kit: kitDaMia() },
    modelo: {
      answer: 'Oi, Ana.', interests: [{ key: 'burnout', label: 'burnout', confidence: 0.9, sensitivity: 'none' }],
      checkout_sent: false, checkout_url: null, next_route: null,
      nome_informado: 'Ana Lima', email_informado: null, whatsapp_informado: '[whatsapp_1]',
      empresa_informada: 'Mind', cargo_informado: 'CEO',
    },
  });
  assert.equal(r.status, 200, JSON.stringify(r.corpo));
  for (const proibida of ['mindagent_chat_save_interests', 'mind_identidade_resolver', 'mind_identificador_declarado_registrar', 'mind_pessoa_completar', 'mindagent_chat_bind_identity', 'mind_checkout_envio_registrar']) {
    assert.ok(!r.rpcs.includes(proibida), `em teste não pode chamar ${proibida}`);
  }
  /* A conversa de teste em si é gravada: é o transcrito do Playground. */
  assert.ok(r.rpcs.includes('mindagent_chat_save_message'));
  assert.deepEqual(r.corpo.ferramentas, []);
});

test('fora do teste, canal desligado continua fechando o Gate e rota ativa proibida é ignorada', async () => {
  const r = await chamar({
    corpo: { message: 'oi', session: SESSAO },
    rpc: {
      mindagent_chat_get_context: { ...CONTEXTO_DE_TESTE, agente: 'mindagent-chat' },
      mind_canal_rotas: CANAL_SEM_A_MIA,
      analise_config: { analise_token: '' },
      mind_rota_capacidade: GATE_CANAL_DESLIGADO,
      mind_agent_kit: kitDaMia(),
    },
  });
  assert.equal(r.status, 503);
  assert.equal(r.corpo.error.code, 'rota_indisponivel');
});

test('em teste, faltar playbook ou dados oficiais continua fechando', async () => {
  const r = await chamar({
    corpo: { message: 'oi', session: SESSAO },
    rpc: {
      mindagent_chat_get_context: CONTEXTO_DE_TESTE, mind_canal_rotas: CANAL_SEM_A_MIA,
      mind_rota_capacidade: { ok: true, pode_executar: false, needs_human: true, reason: 'missing_playbook' },
      mind_agent_kit: kitDaMia(),
    },
  });
  assert.equal(r.status, 503);
  assert.equal(r.corpo.error.code, 'rota_indisponivel');
});
