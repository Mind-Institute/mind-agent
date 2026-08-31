/* ============================================================================
 * COMPORTAMENTO DA EDGE `mindagent-chat`
 *
 * Aqui o handler versionado RODA. O harness troca só o que não existe no Node
 * — `Deno`, o cliente Supabase e a OpenAI — e observa o que o executor faz:
 * quais RPCs chama, em que ordem, o que persiste antes de recusar, o que
 * repassa intacto e o que se recusa a executar.
 *
 * O arquivo irmão (`mindagent_chat_wiring.test.mjs`) lê o fonte e trava as
 * decisões de escrita. Este trava as decisões de execução: um refactor pode
 * preservar o texto e perder o comportamento.
 *
 * Como rodar:  npm run test:edge
 * ==========================================================================*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chamar, erroRpc, KIT_COMPLETO, PESSOA_ID } from './helpers/edge-harness.mjs';

const clone = (valor) => structuredClone(valor);

/* ========================================================== 1. CHAT NORMAL */

test('chat normal: ordem canônica preservada, sem Router e sem retrieval direto', async () => {
  const r = await chamar({ corpo: { message: 'que horas começa a abertura?' } });

  assert.equal(r.status, 200);
  assert.equal(r.corpo.ok, true);
  assert.deepEqual(r.rpcs, [
    'mindagent_chat_start',
    'mindagent_chat_get_context',
    'mindagent_chat_save_message',   // user
    'mind_rota_capacidade',          // Gate
    'mind_agent_kit',                // Kit
    'mindagent_chat_save_message',   // assistant
  ]);
  // Quem busca é o Kit. O executor não fala com o retrieval.
  assert.ok(!r.rpcs.includes('mindagent_chat_search'));

  const [userMsg, assistantMsg] = r.chamadasDe('mindagent_chat_save_message');
  assert.equal(userMsg.args.p_role, 'user');
  assert.equal(userMsg.args.p_content, 'que horas começa a abertura?');
  assert.equal(assistantMsg.args.p_role, 'assistant');

  const gate = r.chamada('mind_rota_capacidade');
  assert.deepEqual(gate.args, { p_rota: 'concierge_summit', p_canal: 'mindagent-web' });

  // Necessidade e memória em campos separados: `pergunta` seleciona,
  // `interesses` só reordena.
  const kit = r.chamada('mind_agent_kit');
  assert.equal(kit.args.p_rota, 'concierge_summit');
  assert.equal(kit.args.p_necessidade.pergunta, 'que horas começa a abertura?');
  assert.equal(kit.args.p_necessidade.event_slug, 'mind-summit-2026');
  assert.deepEqual(kit.args.p_necessidade.interesses, ['saúde mental corporativa']);

  // A competência vem do playbook do Kit; o contrato do executor vem depois.
  assert.equal(r.openai.length, 1);
  const enviado = r.openai[0].corpo;
  assert.ok(enviado.instructions.startsWith(KIT_COMPLETO.playbook));
  assert.match(enviado.instructions, /starts_at_local\/ends_at_local/);
  assert.equal(enviado.store, false);
  const contexto = JSON.parse(enviado.input[0].content.replace(/^[^{]*/, ''));
  assert.deepEqual(contexto.official_context, KIT_COMPLETO.structured);

  // Contrato HTTP consumido pelo `chat-service.js`.
  for (const campo of [
    'answer', 'session', 'device_id', 'identity_verified', 'identity_received',
    'profile_loaded', 'interests', 'sources', 'request_id',
  ]) {
    assert.ok(campo in r.corpo, `resposta precisa manter ${campo}`);
  }
  assert.deepEqual(r.corpo.sources, [
    { type: 'event', count: 1 },
    { type: 'locations', count: 1 },
    { type: 'sessions', count: 1 },
    { type: 'speakers', count: 1 },
  ]);
  assert.equal(typeof r.corpo.session.token, 'string');
});

test('chat normal: sessão informada é reusada, sem abrir outra', async () => {
  const sessao = {
    id: '33333333-3333-4333-8333-333333333333',
    conversation_id: '44444444-4444-4444-8444-444444444444',
    token: 'a'.repeat(64),
  };
  const r = await chamar({ corpo: { message: 'e o almoço?', session: sessao } });

  assert.equal(r.status, 200);
  assert.ok(!r.rpcs.includes('mindagent_chat_start'), 'sessão válida não recria sessão');
  assert.equal(r.chamada('mind_agent_kit').args.p_conversa_id, sessao.conversation_id);
  assert.equal(r.corpo.session.id, sessao.id);
});

/* ========================================================= 2. GATE FECHADO */

test('Gate fechado: 503, fala do usuário persistida, Kit e modelo intocados', async () => {
  const r = await chamar({
    corpo: { message: 'quais palestras têm no dia 17?' },
    rpc: { mind_rota_capacidade: { ok: true, pode_executar: false, reason: 'missing_playbook' } },
  });

  assert.equal(r.status, 503);
  assert.equal(r.corpo.error.code, 'rota_indisponivel');

  // A recusa custa a resposta, nunca o registro do que a pessoa disse.
  const salvas = r.chamadasDe('mindagent_chat_save_message');
  assert.equal(salvas.length, 1);
  assert.equal(salvas[0].args.p_role, 'user');

  assert.ok(!r.rpcs.includes('mind_agent_kit'), 'Gate fechado não chega ao Kit');
  assert.equal(r.openai.length, 0, 'Gate fechado não chama modelo');
  assert.equal(r.evento('gate_fechado').reason, 'missing_playbook');
});

test('Gate: erro de RPC também fecha, não abre', async () => {
  const r = await chamar({
    corpo: { message: 'onde é o credenciamento?' },
    rpc: { mind_rota_capacidade: erroRpc('permission denied') },
  });
  assert.equal(r.status, 503);
  assert.equal(r.corpo.error.code, 'rota_indisponivel');
  assert.equal(r.openai.length, 0);
});

/* ======================================================== 3. KIT INCOMPLETO */

test('Kit incompleto: fail-closed antes da OpenAI, em cada forma de incompletude', async () => {
  const semProgramacao = clone(KIT_COMPLETO);
  delete semProgramacao.structured.programacao;
  const semEvento = clone(KIT_COMPLETO);
  delete semEvento.structured.evento;
  const semPlaybook = { ...clone(KIT_COMPLETO), playbook: '   ' };
  const indisponivel = { ...clone(KIT_COMPLETO), meta: { kit_disponivel: false } };

  for (const [nome, kit] of [
    ['sem bloco programacao', semProgramacao],
    ['sem bloco evento', semEvento],
    ['playbook vazio', semPlaybook],
    ['kit_disponivel false', indisponivel],
    ['kit recusado', { ok: false, motivo: 'rota_sem_kit' }],
    ['erro de RPC', erroRpc('function does not exist')],
  ]) {
    const r = await chamar({ corpo: { message: 'quem fala às 14:30?' }, rpc: { mind_agent_kit: kit } });
    assert.equal(r.status, 503, nome);
    assert.equal(r.corpo.error.code, 'official_data_unavailable', nome);
    assert.equal(r.openai.length, 0, `${nome}: o modelo não pode ser chamado`);
    assert.equal(r.chamadasDe('mindagent_chat_save_message').length, 1, `${nome}: a fala do usuário fica`);
  }
});

/* ========================================================= 4. EVENT_SLUG */

test('event_slug malformado é recusado antes de tocar o banco', async () => {
  const r = await chamar({ corpo: { message: 'oi', event_slug: 'Mind Summit 2026' } });
  assert.equal(r.status, 422);
  assert.equal(r.corpo.error.code, 'invalid_request');
  assert.equal(r.chamadas.length, 0, 'requisição inválida não abre sessão nem grava nada');
  assert.equal(r.openai.length, 0);
});

test('event_slug de outro evento vai intacto ao Kit — e o Kit é quem recusa', async () => {
  const r = await chamar({
    corpo: { message: 'qual a programação?', event_slug: 'outro-evento-2027' },
    rpc: { mind_agent_kit: { ok: false, motivo: 'evento_desconhecido' } },
  });
  assert.equal(r.chamada('mind_agent_kit').args.p_necessidade.event_slug, 'outro-evento-2027');
  assert.equal(r.status, 503);
  assert.equal(r.corpo.error.code, 'official_data_unavailable');
  assert.equal(r.openai.length, 0, 'não se responde pelo evento errado');
});

/* ============================================== 5. RETRY / client_message_id */

test('retry com o mesmo client_message_id repassa o id verbatim, sem regerar', async () => {
  const corpo = { message: 'confirma o horário?', client_message_id: 'cli-abc-123' };
  const primeira = await chamar({ corpo });
  const segunda = await chamar({ corpo });

  for (const r of [primeira, segunda]) {
    const [user, assistant] = r.chamadasDe('mindagent_chat_save_message');
    assert.equal(user.args.p_client_message_id, 'cli-abc-123');
    assert.equal(assistant.args.p_client_message_id, 'cli-abc-123:assistant');
  }
});

test('sem client_message_id o executor gera um por turno', async () => {
  const a = await chamar({ corpo: { message: 'oi' } });
  const b = await chamar({ corpo: { message: 'oi' } });
  const idA = a.chamadasDe('mindagent_chat_save_message')[0].args.p_client_message_id;
  const idB = b.chamadasDe('mindagent_chat_save_message')[0].args.p_client_message_id;
  assert.match(idA, /^[0-9a-f-]{36}$/);
  assert.notEqual(idA, idB);
});

/* ============================================================ 6/7. SENSITIVITY */

const interesse = (extra) => ({
  key: 'saude_mental_corporativa',
  label: 'Saúde mental corporativa',
  confidence: 0.9,
  confirmed: true,
  ...extra,
});

async function turnoComInteresse(extra) {
  const idDaFala = '55555555-5555-4555-8555-555555555555';
  const r = await chamar({
    corpo: { message: 'quero conteúdo sobre isso' },
    modelo: { answer: 'Certo.', interests: [interesse(extra)] },
    rpc: {
      mindagent_chat_save_message: (args) => ({ id: args.p_role === 'user' ? idDaFala : 'outro' }),
    },
  });
  return { r, idDaFala };
}

test('interesse profissional normal chega ao writer com sensitivity "none"', async () => {
  const { r, idDaFala } = await turnoComInteresse({ sensitivity: 'none' });

  const save = r.chamada('mindagent_chat_save_interests');
  assert.ok(save, 'o interesse precisa chegar ao writer');
  assert.equal(save.args.p_interests.length, 1);
  assert.equal(save.args.p_interests[0].sensitivity, 'none');
  assert.equal(save.args.p_interests[0].key, 'saude_mental_corporativa');
  // A evidência aponta para a fala da pessoa, não para a resposta.
  assert.equal(save.args.p_evidence_message_id, idDaFala);
  assert.equal(r.corpo.interests[0].sensitivity, 'none');
});

test('condição pessoal sensível chega com a chave intacta — nunca "none"', async () => {
  const { r } = await turnoComInteresse({ sensitivity: 'saude_do_titular' });
  const enviado = r.chamada('mindagent_chat_save_interests').args.p_interests[0];
  assert.equal(enviado.sensitivity, 'saude_do_titular');
  assert.notEqual(enviado.sensitivity, 'none');
});

test('sensitivity ausente ou fora do enum vira "desconhecido", nunca "none"', async () => {
  for (const extra of [{}, { sensitivity: '' }, { sensitivity: 42 }, { sensitivity: 'chave_que_nao_existe' }]) {
    const { r } = await turnoComInteresse(extra);
    const enviado = r.chamada('mindagent_chat_save_interests').args.p_interests[0];
    assert.notEqual(enviado.sensitivity, 'none', JSON.stringify(extra));
    if (extra.sensitivity === 'chave_que_nao_existe') {
      // Valor desconhecido é repassado intacto: quem bloqueia é o gate da Lane D.
      assert.equal(enviado.sensitivity, 'chave_que_nao_existe');
    } else {
      assert.equal(enviado.sensitivity, 'desconhecido', JSON.stringify(extra));
    }
  }
});

test('o executor não inventa política: assinatura de save_interests intacta', async () => {
  const { r } = await turnoComInteresse({ sensitivity: 'none' });
  assert.deepEqual(
    Object.keys(r.chamada('mindagent_chat_save_interests').args).sort(),
    ['p_auth_user_id', 'p_evidence_message_id', 'p_interests', 'p_session_id', 'p_token_hash'],
  );
});

/* =================================================================== 8. PLAY */

test('Play: Yazo identificado SEM conversa anterior cria sessão, liga a pessoa e executa', async () => {
  const r = await chamar({
    corpo: {
      ferramenta: 'registrar_feedback_sessao',
      argumentos: { sessao_id: 'abc', nota: 5, comentario: 'ótima' },
      client_action_id: 'acao-1',
      identity: { email: 'participante@exemplo.com', name: 'Participante', source: 'yazo_url' },
    },
  });

  assert.equal(r.status, 200);
  assert.equal(r.corpo.ok, true);
  assert.ok(r.corpo.resultado, 'o resultado da ferramenta volta para a tela');

  // Mesmo lifecycle do chat: sessão canônica, bind de identidade, contexto.
  assert.deepEqual(r.rpcs, [
    'mindagent_chat_start',
    'mindagent_chat_bind_identity',
    'mindagent_chat_get_context',
    'mind_play_feedback_sessao',
  ]);

  const acao = r.chamada('mind_play_feedback_sessao');
  assert.equal(acao.args.p_pessoa_id, PESSOA_ID);
  assert.deepEqual(acao.args.p_payload, { sessao_id: 'abc', nota: 5, comentario: 'ótima' });
  assert.equal(acao.args.p_conversa_id, r.corpo.session.conversation_id);

  // Sessão canônica devolvida para o cliente continuar a conversa.
  assert.equal(typeof r.corpo.session.token, 'string');
  assert.equal(r.openai.length, 0, 'a ação não chama modelo');
  assert.ok(!r.rpcs.includes('mindagent_chat_save_message'), 'ação não é turno de chat');
  assert.ok(!r.rpcs.includes('mind_rota_capacidade'));
});

test('Play: cada ferramenta usa o vínculo da sua assinatura', async () => {
  const nps = await chamar({ corpo: { ferramenta: 'registrar_nps', argumentos: { nota: 9 } } });
  assert.equal(typeof nps.chamada('mind_play_nps').args.p_conversa_id, 'string');

  const evento = await chamar({ corpo: { ferramenta: 'registrar_feedback_evento', argumentos: {} } });
  const argsEvento = evento.chamada('mind_play_feedback_evento').args;
  assert.equal(argsEvento.p_mensagem_id, null);
  assert.ok(!('p_conversa_id' in argsEvento));

  const livre = await chamar({ corpo: { ferramenta: 'registrar_feedback', argumentos: {} } });
  const argsLivre = livre.chamada('mind_play_feedback').args;
  assert.deepEqual(Object.keys(argsLivre).sort(), ['p_payload', 'p_pessoa_id']);
});

test('Play: a ação não depende da OpenAI configurada', async () => {
  const r = await chamar({
    corpo: { ferramenta: 'registrar_nps', argumentos: { nota: 10 } },
    env: { OPENAI_API_KEY: null },
  });
  assert.equal(r.status, 200);
  assert.equal(r.corpo.ok, true);
});

test('Play: falha da RPC vira acao_falhou, sem vazar detalhe', async () => {
  const r = await chamar({
    corpo: { ferramenta: 'registrar_nps', argumentos: { nota: 10 } },
    rpc: { mind_play_nps: erroRpc('function mind_play_nps does not exist') },
  });
  assert.equal(r.status, 502);
  assert.equal(r.corpo.error.code, 'acao_falhou');
  assert.ok(!JSON.stringify(r.corpo).includes('does not exist'));
});

/* ========================================================= 9. PLAY SEM PESSOA */

test('Play sem pessoa identificada não coleta — e a recusa é dado, não erro', async () => {
  const r = await chamar({
    corpo: { ferramenta: 'registrar_nps', argumentos: { nota: 8 } },
    rpc: { mindagent_chat_get_context: { participant_profile: null, expires_at: null } },
  });

  assert.equal(r.status, 200, 'regra de produto responde 200 para a tela poder dizer');
  assert.equal(r.corpo.ok, false);
  assert.equal(r.corpo.error.code, 'sem_pessoa');
  assert.ok(!r.rpcs.some((nome) => nome.startsWith('mind_play_')), 'nada é registrado sem pessoa');
});

/* ====================================================== 10. FORA DA ALLOWLIST */

test('ferramenta fora da allowlist é recusada antes de tocar o banco', async () => {
  for (const ferramenta of [
    'mind_play_nps',            // o nome da RPC não é o nome da ferramenta
    'mindagent_chat_search',
    'registrar_qualquer_coisa',
    '__proto__',
    'constructor',
    'toString',
  ]) {
    const r = await chamar({ corpo: { ferramenta, argumentos: {} } });
    assert.equal(r.status, 400, ferramenta);
    assert.equal(r.corpo.error.code, 'ferramenta_desconhecida', ferramenta);
    assert.equal(r.chamadas.length, 0, `${ferramenta}: recusa não pode abrir sessão nem chamar RPC`);
  }
});

test('argumentos inválidos são recusados antes de tocar o banco', async () => {
  for (const argumentos of [undefined, null, 'texto', [1, 2]]) {
    const r = await chamar({ corpo: { ferramenta: 'registrar_nps', argumentos } });
    assert.equal(r.status, 400, JSON.stringify(argumentos));
    assert.equal(r.corpo.error.code, 'argumentos_invalidos');
    assert.equal(r.chamadas.length, 0);
  }
});
