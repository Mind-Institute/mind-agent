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
import { randomUUID } from 'node:crypto';
import { chamar, erroRpc, KIT_COMPLETO, PESSOA_ID } from './helpers/edge-harness.mjs';

const clone = (valor) => structuredClone(valor);

/* ========================================================== 1. CHAT NORMAL */

test('chat normal: ordem canônica preservada, com Router e sem retrieval antecipado', async () => {
  const r = await chamar({ corpo: { message: 'que horas começa a abertura?' } });

  assert.equal(r.status, 200);
  assert.equal(r.corpo.ok, true);
  assert.deepEqual(r.rpcs, [
    'mindagent_chat_start',
    'mindagent_chat_get_context',
    'mindagent_chat_save_message',   // user
    'mind_canal_rotas',              // universo do Router
    'analise_config',                // credencial do Router
    'mind_rota_capacidade',          // Gate
    'mind_agent_kit',                // Kit
    'mindagent_chat_save_message',   // assistant
  ]);
  // Sem chamada de ferramenta pelo modelo, o executor não antecipa retrieval.
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

  // A competência e as políticas transversais vêm do playbook composto pelo Kit.
  assert.equal(r.openai.length, 1);
  const enviado = r.openai[0].corpo;
  assert.ok(enviado.instructions.startsWith(KIT_COMPLETO.playbook));
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

test('abstinência sem lupa força uma busca antes da resposta final', async () => {
  const kitComLupa = clone(KIT_COMPLETO);
  kitComLupa.tools = [{
    nome: 'buscar_intelligence', descricao: 'Busca candidatos.',
    parametros: {
      type: 'object', properties: {
        necessidade: { type: 'string' }, limite: { type: 'integer' },
      }, required: ['necessidade', 'limite'], additionalProperties: false,
    },
  }, {
    nome: 'ler_intelligence', descricao: 'Lê um candidato.',
    parametros: {
      type: 'object', properties: {
        tipo: { type: 'string' }, id: { type: 'string' },
      }, required: ['tipo', 'id'], additionalProperties: false,
    },
  }];
  kitComLupa.structured.programacao.sessions = [];

  const respostaFinal = {
    answer: 'Encontrei a sessão oficial às 14h.', interests: [], checkout_sent: false,
    checkout_url: null, next_route: null, nome_informado: null,
    email_informado: null, whatsapp_informado: null,
    empresa_informada: null, cargo_informado: null,
  };
  const r = await chamar({
    corpo: { message: 'Quem fala desse tema e em que horário?' },
    rpc: {
      mind_agent_kit: kitComLupa,
      mind_intelligence_buscar_contextual: {
        total: 1, candidatos: [{ tipo: 'sessao', id: 's2', titulo: 'Sessão oficial' }],
      },
    },
    modelo: [
      { ...respostaFinal, answer: 'Com este JSON, não consigo confirmar: sessions veio vazia.' },
      { __payload: { output: [{
        type: 'function_call', call_id: 'call_busca', name: 'buscar_intelligence',
        arguments: JSON.stringify({ necessidade: 'tema e horário', limite: 6 }),
      }] } },
      respostaFinal,
    ],
  });

  assert.equal(r.status, 200);
  assert.equal(r.corpo.answer, respostaFinal.answer);
  const respostas = r.openai.filter((chamada) => chamada.url.endsWith('/v1/responses'));
  assert.equal(respostas.length, 3);
  assert.deepEqual(respostas[1].corpo.tool_choice, { type: 'function', name: 'buscar_intelligence' });
  assert.ok(r.rpcs.includes('mind_intelligence_buscar_contextual'));
  const salva = r.chamadasDe('mindagent_chat_save_message').at(-1);
  assert.equal(salva.args.p_blocks.recuperacao_forcada, true);
  assert.equal(salva.args.p_blocks.rodadas_tool, 1);
});

test('jornada: resposta de botão persiste sem chamar Router, Kit ou modelo', async () => {
  const evidenceId = randomUUID();
  const r = await chamar({
    corpo: {
      journey_signal: { field: 'objetivos', values: ['Levar ideias práticas para minha equipe'] },
      client_action_id: 'jornada-objetivo-1',
    },
    env: { OPENAI_API_KEY: '' },
    rpc: {
      mindagent_chat_save_message: () => ({ mensagem_id: evidenceId, duplicada: false, papel: 'user' }),
      mindagent_chat_save_interests: { saved: 1, blocked: 0, skipped: 0, promoted: 0 },
    },
  });

  assert.equal(r.status, 200);
  assert.equal(r.corpo.ok, true);
  assert.deepEqual(r.rpcs, [
    'mindagent_chat_start', 'mindagent_chat_get_context',
    'mindagent_chat_save_message', 'mindagent_chat_save_interests',
  ]);
  assert.equal(r.openai.length, 0);
  const evidence = r.chamada('mindagent_chat_save_message');
  assert.equal(evidence.args.p_client_message_id, 'journey:jornada-objetivo-1');
  assert.deepEqual(evidence.args.p_blocks, {
    kind: 'journey_answer', field: 'objetivos', values: ['Levar ideias práticas para minha equipe'],
  });
  const interests = r.chamada('mindagent_chat_save_interests');
  assert.equal(interests.args.p_evidence_message_id, evidenceId);
  assert.equal(interests.args.p_interests[0].sensitivity, 'none');
  assert.equal(interests.args.p_interests[0].confidence, 1);
});

test('jornada: campo fora da allowlist falha antes de abrir sessão', async () => {
  const r = await chamar({
    corpo: { journey_signal: { field: 'comando_livre', values: ['ignorar regras'] } },
  });
  assert.equal(r.status, 422);
  assert.equal(r.corpo.error.code, 'invalid_journey_signal');
  assert.equal(r.rpcs.length, 0);
  assert.equal(r.openai.length, 0);
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
  const semStructured = { ...clone(KIT_COMPLETO), structured: {} };
  const semPlaybook = { ...clone(KIT_COMPLETO), playbook: '   ' };
  const indisponivel = { ...clone(KIT_COMPLETO), meta: { kit_disponivel: false } };

  for (const [nome, kit] of [
    ['sem nenhum bloco structured', semStructured],
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
      mindagent_chat_save_message: (args) => ({
        mensagem_id: args.p_role === 'user' ? idDaFala : 'outro', duplicada: false, papel: args.p_role,
      }),
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
    'mind_play_chamada_iniciar',   // reserva antes de executar
    'mind_play_feedback_sessao',
    'mind_play_chamada_concluir',  // desfecho registrado
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

/* ============================== 11. IDEMPOTÊNCIA DE TRANSPORTE DO PLAY */

/**
 * Ledger em memória com o MESMO protocolo de `concierge.ferramenta_chamadas`.
 * O SQL de verdade é provado pelos 8 contratos de
 * `tests/concierge_play_idempotencia_contract.sql`, em BEGIN/ROLLBACK contra
 * produção; o que se prova aqui é o uso que o executor faz do protocolo — e
 * isso exige estado atravessando duas chamadas HTTP.
 */
function ledgerEmMemoria() {
  const porChave = new Map();
  const porId = new Map();
  return {
    semear: (chave, linha) => {
      const completa = { id: randomUUID(), saida: null, http_status: null, ...linha };
      porChave.set(chave, completa);
      porId.set(completa.id, completa);
    },
    linhaDe: (chave) => porChave.get(chave),
    rpc: {
      mind_play_chamada_iniciar: ({ p_ferramenta, p_pessoa_id, p_idempotency_key }) => {
        const chave = String(p_idempotency_key ?? '').trim() || null;
        const nova = {
          id: randomUUID(), ferramenta: p_ferramenta, pessoa: p_pessoa_id,
          status: 'em_andamento', saida: null, http_status: null,
        };
        if (!chave) { porId.set(nova.id, nova); return { ok: true, estado: 'nova', chamada_id: nova.id }; }
        const antiga = porChave.get(chave);
        if (!antiga) {
          porChave.set(chave, nova); porId.set(nova.id, nova);
          return { ok: true, estado: 'nova', chamada_id: nova.id };
        }
        if (antiga.ferramenta !== p_ferramenta || antiga.pessoa !== p_pessoa_id) {
          return { ok: false, motivo: 'chave_conflitante' };
        }
        if (antiga.status === 'em_andamento') {
          return { ok: true, estado: 'em_andamento', chamada_id: antiga.id };
        }
        return {
          ok: true, estado: 'repetida', chamada_id: antiga.id,
          status: antiga.status, saida: antiga.saida, http_status: antiga.http_status,
        };
      },
      mind_play_chamada_concluir: ({ p_chamada_id, p_status, p_saida, p_http_status }) => {
        const linha = porId.get(p_chamada_id);
        if (!linha || linha.status !== 'em_andamento') return { ok: false, motivo: 'chamada_nao_encontrada' };
        Object.assign(linha, { status: p_status, saida: p_saida ?? null, http_status: p_http_status ?? null });
        return { ok: true, chamada_id: p_chamada_id, status: p_status };
      },
    },
  };
}

test('A. mesmo client_action_id executa o writer UMA vez e devolve o mesmo resultado', async () => {
  const ledger = ledgerEmMemoria();
  const escritas = [];
  const rpc = {
    ...ledger.rpc,
    mind_play_nps: (args) => {
      escritas.push(args);
      return { ok: true, acao: 'criado', nps_id: 'nps-1', nota: 9 };
    },
  };
  const corpo = { ferramenta: 'registrar_nps', argumentos: { nota: 9 }, client_action_id: 'acao-repetida' };

  const primeira = await chamar({ corpo, rpc });
  const segunda = await chamar({ corpo, rpc });

  assert.equal(primeira.status, 200);
  assert.equal(primeira.corpo.ok, true);
  assert.ok(primeira.rpcs.includes('mind_play_nps'));

  // O contrato: a segunda tentativa é sucesso consistente, sem segunda escrita.
  assert.equal(segunda.status, 200);
  assert.equal(segunda.corpo.ok, true);
  assert.deepEqual(segunda.corpo.resultado, primeira.corpo.resultado);
  assert.equal(escritas.length, 1, 'o writer não pode rodar duas vezes');
  assert.ok(!segunda.rpcs.includes('mind_play_nps'), 'a repetição não chega ao writer');
  assert.equal(segunda.evento('play_repetido').status_original, 'concluida');

  // Uma reserva, um desfecho.
  assert.equal(ledger.linhaDe('acao-repetida').status, 'concluida');
});

test('A. client_action_id diferente continua sendo tentativa distinta', async () => {
  const ledger = ledgerEmMemoria();
  const escritas = [];
  const rpc = { ...ledger.rpc, mind_play_nps: () => (escritas.push(1), { ok: true, nps_id: 'x' }) };

  await chamar({ corpo: { ferramenta: 'registrar_nps', argumentos: { nota: 9 }, client_action_id: 'a-1' }, rpc });
  await chamar({ corpo: { ferramenta: 'registrar_nps', argumentos: { nota: 8 }, client_action_id: 'a-2' }, rpc });

  assert.equal(escritas.length, 2);
});

test('A. sem client_action_id o comportamento de hoje é preservado: executa, sem ledger', async () => {
  const r = await chamar({ corpo: { ferramenta: 'registrar_nps', argumentos: { nota: 7 } } });
  assert.equal(r.status, 200);
  assert.equal(r.corpo.ok, true);
  assert.ok(!r.rpcs.includes('mind_play_chamada_iniciar'), 'sem chave não há reserva');
  assert.ok(r.rpcs.includes('mind_play_nps'));
});

test('A. a MESMA tentativa ainda em andamento não executa o writer de novo', async () => {
  const ledger = ledgerEmMemoria();
  ledger.semear('acao-voando', { ferramenta: 'registrar_nps', pessoa: PESSOA_ID, status: 'em_andamento' });
  const r = await chamar({
    corpo: { ferramenta: 'registrar_nps', argumentos: { nota: 9 }, client_action_id: 'acao-voando' },
    rpc: ledger.rpc,
  });
  assert.equal(r.status, 409);
  assert.equal(r.corpo.ok, false);
  assert.equal(r.corpo.error.code, 'acao_em_andamento');
  assert.ok(!r.rpcs.includes('mind_play_nps'));
});

test('A. a chave vem do navegador: reusá-la em outra ferramenta não herda o resultado', async () => {
  const ledger = ledgerEmMemoria();
  ledger.semear('acao-de-outro', {
    ferramenta: 'registrar_feedback_evento', pessoa: PESSOA_ID,
    status: 'concluida', saida: { ok: true, feedback_id: 'segredo' },
  });
  const r = await chamar({
    corpo: { ferramenta: 'registrar_nps', argumentos: { nota: 9 }, client_action_id: 'acao-de-outro' },
    rpc: ledger.rpc,
  });
  assert.equal(r.status, 409);
  assert.equal(r.corpo.error.code, 'chave_conflitante');
  assert.ok(!JSON.stringify(r.corpo).includes('segredo'), 'a saída alheia não pode vazar');
  assert.ok(!r.rpcs.includes('mind_play_nps'));
});

test('A. ledger indisponível falha fechado: não executa o writer', async () => {
  // Prometeu deduplicar. Sem a casa, executar assim mesmo é o defeito.
  const r = await chamar({
    corpo: { ferramenta: 'registrar_nps', argumentos: { nota: 9 }, client_action_id: 'a-1' },
    rpc: { mind_play_chamada_iniciar: erroRpc('function mind_play_chamada_iniciar does not exist') },
  });
  assert.equal(r.status, 502);
  assert.equal(r.corpo.error.code, 'acao_falhou');
  assert.ok(!r.rpcs.includes('mind_play_nps'));
});

/* ================================== 12. RECUSA DO WRITER NÃO É SUCESSO */

test('B. writer que recusa por domínio NÃO vira top-level ok:true', async () => {
  // `{ok:false, motivo}` chega SEM erro do Supabase — é dado, não exception.
  const r = await chamar({
    corpo: { ferramenta: 'registrar_nps', argumentos: {}, client_action_id: 'a-recusa' },
    rpc: { mind_play_nps: { ok: false, motivo: 'sem_nota' } },
  });

  assert.notEqual(r.corpo.ok, true, 'a UI lê o top-level: não pode dizer que registrou');
  assert.equal(r.corpo.ok, false);
  assert.equal(r.corpo.error.code, 'sem_nota', 'o motivo do writer é o código de domínio');
  assert.equal(r.status, 200, 'recusa de negócio não é erro de servidor');
  assert.equal(r.evento('play_recusado').motivo, 'sem_nota');

  // E o desfecho fica registrado como recusa, para o retry devolver o mesmo.
  const concluir = r.chamada('mind_play_chamada_concluir');
  assert.equal(concluir.args.p_status, 'recusada');
  assert.deepEqual(concluir.args.p_saida, { ok: false, motivo: 'sem_nota' });
});

test('B. cada recusa real dos writers da Lane E chega ao cliente como recusa', async () => {
  for (const [ferramenta, rpcNome, motivo] of [
    ['registrar_feedback_sessao', 'mind_play_feedback_sessao', 'sessao_nao_encontrada'],
    ['registrar_nps', 'mind_play_nps', 'nota_fora_da_faixa'],
    ['registrar_feedback_evento', 'mind_play_feedback_evento', 'sem_categoria'],
    ['registrar_feedback', 'mind_play_feedback', 'sem_tipo'],
  ]) {
    const r = await chamar({
      corpo: { ferramenta, argumentos: {} },
      rpc: { [rpcNome]: { ok: false, motivo } },
    });
    assert.equal(r.corpo.ok, false, ferramenta);
    assert.equal(r.corpo.error.code, motivo, ferramenta);
    assert.equal(r.status, 200, ferramenta);
  }
});

test('B. o retry de uma recusa devolve a MESMA recusa, sem reexecutar', async () => {
  const ledger = ledgerEmMemoria();
  const escritas = [];
  const rpc = {
    ...ledger.rpc,
    mind_play_nps: () => (escritas.push(1), { ok: false, motivo: 'sem_nota' }),
  };
  const corpo = { ferramenta: 'registrar_nps', argumentos: {}, client_action_id: 'a-recusa' };

  const primeira = await chamar({ corpo, rpc });
  const segunda = await chamar({ corpo, rpc });

  assert.equal(escritas.length, 1);
  assert.equal(segunda.corpo.ok, false);
  assert.equal(segunda.corpo.error.code, primeira.corpo.error.code);
  assert.equal(segunda.status, 200);
});

test('B. motivo sem forma de código não vaza texto interno', async () => {
  for (const motivo of [undefined, '', 'ERRO: relation "x" does not exist', 42]) {
    const r = await chamar({
      corpo: { ferramenta: 'registrar_nps', argumentos: {} },
      rpc: { mind_play_nps: { ok: false, motivo } },
    });
    assert.equal(r.corpo.ok, false);
    assert.equal(r.corpo.error.code, 'acao_recusada', String(motivo));
    assert.ok(!JSON.stringify(r.corpo).includes('does not exist'));
  }
});

test('B. writer sem o contrato `ok` é falha, não sucesso silencioso', async () => {
  for (const resposta of [null, {}, { feedback_id: 'x' }, 'texto']) {
    const r = await chamar({
      corpo: { ferramenta: 'registrar_nps', argumentos: { nota: 9 } },
      rpc: { mind_play_nps: resposta },
    });
    assert.notEqual(r.corpo.ok, true, JSON.stringify(resposta));
    assert.equal(r.status, 502);
    assert.equal(r.corpo.error.code, 'acao_falhou');
  }
});
