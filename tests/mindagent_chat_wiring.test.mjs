/* ============================================================================
 * CONTRATO DE WIRING DA EDGE `mindagent-chat`
 *
 * Este arquivo é TESTE, e é OFFLINE: não chama a Edge, não chama o banco e não
 * precisa de Deno. Ele lê o fonte versionado em
 * `supabase/functions/mindagent-chat/index.ts` e trava as decisões de wiring
 * que não dá para provar em SQL — porque vivem no executor, não no dado.
 *
 * O que ele NÃO faz: não substitui o E2E. Gate fechado, Kit incompleto e ação
 * do Play com pessoa real só se provam com a Function publicada. O que ele
 * garante é que o código versionado não perdeu, num refactor, a ordem e os
 * limites que a supervisão fechou.
 *
 * Como rodar:  npm run test:edge
 * ==========================================================================*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const FONTE = new URL('../supabase/functions/mindagent-chat/index.ts', import.meta.url);
const src = readFileSync(FONTE, 'utf8');
const migracaoRecuperacao = readFileSync(
  new URL('../supabase/migrations/20260903160000_concierge_busca_antes_de_abster.sql', import.meta.url),
  'utf8',
);

const pos = (agulha) => {
  const i = src.indexOf(agulha);
  assert.notEqual(i, -1, `esperado encontrar no fonte: ${agulha}`);
  return i;
};

/* --------------------------------------------------------------- CHAT */

test('a fala do usuário é persistida ANTES do Gate e do Kit', () => {
  // Gate fechado ou Kit indisponível custam a resposta, nunca o registro do
  // que a pessoa disse. Se o save descer para depois, uma recusa apaga a fala.
  const save = pos('p_role: "user"');
  const gate = pos('"mind_rota_capacidade"');
  const kit = pos('"mind_agent_kit"');
  assert.ok(save < gate, 'save_message(user) precisa vir antes do Gate');
  assert.ok(save < kit, 'save_message(user) precisa vir antes do Kit');
});

test('credenciamento person-bound entra no contexto do modelo', () => {
  assert.match(src, /sessionContext\.credenciamento/);
  assert.match(src, /participant_credential/);
  assert.ok(
    pos('participant_credential: sessionContext.credenciamento') < pos('user_question: maskedContact.text'),
    'credenciamento precisa ser montado junto do contexto, antes da pergunta ao modelo',
  );
});

test('Router escolhe dentro do canal e o Gate valida a rota escolhida', () => {
  assert.match(src, /mind_canal_rotas/);
  assert.match(src, /decidirRota/);
  assert.match(src, /p_rota: rotaDecidida/);
  assert.match(src, /p_canal: CANAL/);
});

test('o Kit falha fechado antes de chamar o modelo', () => {
  const kitOk = pos('const kitOk');
  const openai = pos('https://api.openai.com/v1/responses');
  assert.ok(kitOk < openai, 'a verificação do Kit precisa vir antes da OpenAI');

  for (const exigencia of [
    'kit.ok !== false',
    'kit.meta?.kit_disponivel === true',
    'typeof kit.playbook === "string"',
    'Object.keys(structuredDoKit).length > 0',
  ]) {
    assert.ok(src.includes(exigencia), `fail-closed precisa exigir: ${exigencia}`);
  }
});

test('o executor não pré-carrega retrieval — a lupa só abre por tool call', () => {
  assert.doesNotMatch(src, /mindagent_chat_search/);
  assert.doesNotMatch(src, /personalizedSearchQuery/);
  assert.match(src, /extrairChamadas\(openAiPayload\)/);
  assert.match(src, /executarChamadas\(admin, chamadas/);
});

test('necessidade atual e memória viajam em campos separados', () => {
  // `pergunta` seleciona; `interesses` só reordena. Concatenar os dois apagava
  // a listagem de agenda e fazia pergunta sem lastro receber conteúdo de
  // interesse.
  assert.match(src, /pergunta: message/);
  assert.match(src, /interesses: personalizationProfile\?\.interesses/);
  assert.match(src, /event_slug: eventSlug/);
});

test('a competência vem do playbook do Kit, não de texto no código', () => {
  assert.doesNotMatch(src, /SYSTEM_INSTRUCTIONS/);
  assert.match(src, /const instrucoes = kit\.playbook as string/);
  assert.match(src, /instructions: instrucoes/);
});

test('o runtime limita a lupa por orçamento e número de rodadas', () => {
  assert.match(src, /MAX_RODADAS_TOOL/);
  assert.match(src, /ORCAMENTO_TURNO_MS/);
  assert.match(src, /tool_choice: volta >= MAX_RODADAS_TOOL/);
  assert.match(src, /forcarBuscaNaProximaVolta/,
    'uma abstinência inicial precisa poder forçar a lupa antes da resposta final');
});

test('o playbook manda buscar antes de abster e proíbe expor o encanamento', () => {
  assert.match(migracaoRecuperacao, /use buscar_intelligence antes de concluir/);
  assert.match(migracaoRecuperacao, /use ler_intelligence/);
  assert.match(migracaoRecuperacao, /Nunca mencione JSON/);
  assert.match(migracaoRecuperacao, /position\('RECUPERAÇÃO ANTES DE DIZER QUE NÃO SABE'/,
    'a migração precisa ser idempotente');
});

/* -------------------------------------------------------- SENSITIVITY */

test('sensitivity é obrigatório no schema de cada interesse', () => {
  assert.match(src, /sensitivity:\s*\{\s*type: "string", enum: \[\.\.\.SENSIBILIDADES\]/);
  assert.match(src, /required: \["key", "label", "confidence", "sensitivity"\]/);
});

test('o enum de sensibilidade é `none` mais as chaves ativas de memoria_bloqueios', () => {
  // Espelha `intelligence.memoria_bloqueios` (chaves ativas em 31/08/2026). A
  // autoridade é o gate da Lane D; este enum existe porque json_schema strict
  // exige literal. Chave nova que este enum não conheça é bloqueada do outro
  // lado — que é o lado certo para errar.
  const bloco = src.slice(pos('const SENSIBILIDADES'), pos('] as const;'));
  const esperado = [
    'none',
    'afastamento_titular',
    'diagnostico_titular',
    'filiacao_sindical',
    'medicacao_titular',
    'opiniao_politica',
    'orientacao_sexual',
    'origem_racial',
    'religiao',
    'saude_de_pessoa_citada',
    'saude_do_titular',
  ];
  const achado = [...bloco.matchAll(/"([a-z_]+)"/g)].map((m) => m[1]);
  assert.deepEqual(achado.sort(), esperado.sort());
});

test('sensitivity é repassado intacto, sem política no executor', () => {
  assert.match(src, /sensitivity: typeof interest\.sensitivity === "string"/);
  // Desconhecido não vira `none`: vira desconhecido, e desconhecido é
  // bloqueado pelo gate do banco.
  assert.match(src, /: "desconhecido"/);
  assert.doesNotMatch(src, /sensitivity[^\n]*\?\?\s*"none"/);
});

test('a assinatura de save_interests não foi tocada', () => {
  // O writer e a política de memória são da Lane D. Aqui só se acrescenta o
  // campo dentro de cada item.
  for (const arg of [
    'p_auth_user_id', 'p_session_id', 'p_token_hash', 'p_interests', 'p_evidence_message_id',
  ]) {
    assert.ok(
      src.includes(`${arg}:`),
      `save_interests precisa manter o parâmetro ${arg}`,
    );
  }
});

/* --------------------------------------------------------------- PLAY */

test('as ferramentas do Play são uma allowlist estática', () => {
  const bloco = src.slice(pos('const FERRAMENTAS_PLAY'), pos('// RECUSA DO WRITER'));
  const mapa = Object.fromEntries(
    [...bloco.matchAll(/(\w+):\s*\{\s*rpc:\s*"(\w+)",\s*vinculo:\s*"(\w+)"\s*\}/g)]
      .map((m) => [m[1], { rpc: m[2], vinculo: m[3] }]),
  );
  assert.deepEqual(mapa, {
    registrar_feedback_sessao: { rpc: 'mind_play_feedback_sessao', vinculo: 'conversa' },
    registrar_nps:             { rpc: 'mind_play_nps',             vinculo: 'conversa' },
    registrar_feedback_evento: { rpc: 'mind_play_feedback_evento', vinculo: 'mensagem' },
    registrar_feedback:        { rpc: 'mind_play_feedback',        vinculo: 'nenhum' },
  });
});

test('o nome vindo do cliente nunca vira nome de RPC', () => {
  // A ferramenta pedida é chave de consulta na allowlist; o que executa é o
  // `rpc` do mapa. `admin.rpc(ferramenta, ...)` seria RPC dinâmica arbitrária.
  assert.doesNotMatch(src, /rpc\(\s*ferramenta/);
  assert.match(src, /admin\.rpc\(alvo\.rpc, args\)/);
  assert.match(src, /hasOwnProperty\.call\(FERRAMENTAS_PLAY, ferramenta\)/);
});

test('a ação do Play não chama modelo nenhum', () => {
  const inicio = pos('if (modoAcao) {');
  const fim = pos('// ==================================================== MODO CHAT');
  const bloco = src.slice(inicio, fim);
  assert.ok(!bloco.includes('api.openai.com'), 'a ação não pode chamar a OpenAI');
  assert.ok(!bloco.includes('instructions'), 'a ação não monta prompt');
  // E a falta da chave da OpenAI não pode derrubar uma coleta que não a usa.
  assert.match(src, /!openAiKey && !modoAcao/);
});

test('a ação reutiliza sessão, identidade e conversa do chat', () => {
  // Sem segunda Edge, sem segundo lifecycle: quem chega da Yazo sem nunca ter
  // falado com o Concierge tem a sessão canônica criada pelo mesmo caminho.
  const acao = pos('if (modoAcao) {');
  for (const compartilhado of [
    'mindagent_chat_start',
    'mindagent_chat_bind_identity',
    'mindagent_chat_get_context',
  ]) {
    assert.ok(pos(`"${compartilhado}"`) < acao, `${compartilhado} precisa rodar antes do modo ação`);
  }
  assert.match(src, /p_conversa_id = conversationId/);
});

test('sem pessoa não há coleta, e a recusa é dado — não erro de servidor', () => {
  assert.match(src, /code: "sem_pessoa"/);
  const idx = pos('code: "sem_pessoa"');
  const trecho = src.slice(idx - 200, idx);
  assert.match(trecho, /json\(req, 200,/, 'recusa person-bound responde 200 com ok:false');
});

test('a resposta da ação segue o contrato do play-service', () => {
  // `{ok:true, resultado}` no sucesso; `{ok:false, error:{code,message}}` na
  // recusa — que é o que o `play-service.js` lê no TOP-LEVEL.
  assert.match(src, /ok: true,\n\s+resultado,/);
  assert.match(src, /json\(req, status, \{ ok: false, error: \{ code, message \} \}, requestId\)/);
  for (const code of [
    '"ferramenta_desconhecida"', '"argumentos_invalidos"', '"acao_falhou"',
    '"sem_pessoa"', '"acao_em_andamento"', '"chave_conflitante"',
  ]) {
    assert.ok(src.includes(code), `o contrato precisa manter o código ${code}`);
  }
});

test('sucesso do Play exige o contrato do writer, não só a ausência de erro', () => {
  // As `mind_play_*` devolvem recusa de domínio como DADO. Olhar só o
  // `acaoError` fazia a Edge responder top-level ok:true carregando um
  // `{ok:false}` dentro — e o cliente lê o top-level.
  assert.match(src, /if \(escrita\?\.ok !== true\)/);
  assert.match(src, /function codigoDeRecusa/);
  // O motivo do writer vira o código; nada é traduzido nem inventado.
  assert.match(src, /\/\^\[a-z\]\[a-z0-9_\]\{1,39\}\$\//);
});

test('a idempotência do Play usa a casa que já existe, e reserva antes de executar', () => {
  const reserva = pos('"mind_play_chamada_iniciar"');
  const escrita = pos('admin.rpc(alvo.rpc, args)');
  assert.ok(reserva < escrita, 'reservar precisa vir antes de executar o writer');
  assert.match(src, /p_idempotency_key: chaveAcao/);
  assert.match(src, /"mind_play_chamada_concluir"/);
  // Sem chave, o comportamento é o de hoje: executa.
  assert.match(src, /if \(chaveAcao\) \{/);
});

/* ------------------------------------------------- CONTRATO PRESERVADO */

test('o contrato HTTP do chat não mudou', () => {
  for (const campo of [
    'answer', 'session', 'device_id', 'identity_verified', 'identity_received',
    'profile_loaded', 'interests', 'sources', 'request_id',
  ]) {
    assert.ok(src.includes(`${campo},`) || src.includes(`${campo}:`), `resposta precisa manter ${campo}`);
  }
});

test('as fontes passam a vir do Kit, mantendo o formato {type, count}', () => {
  assert.match(src, /function sourceSummary\(structured: Record<string, unknown>\)/);
  assert.match(src, /structured\.programacao/);
  assert.match(src, /sources\.push\(\{ type: key, count: value\.length \}\)/);
});
