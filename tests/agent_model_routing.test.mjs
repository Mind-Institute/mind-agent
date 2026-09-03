import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  bucketDeRollout,
  modeloInicialDoTurno,
  podeExecutarTool,
  podeTentarModelo,
  saidaEstruturadaMinimaValida,
} from '../supabase/functions/_shared/agent-model-routing.ts';

const FAST = 'gpt-5.4-mini';
const COMPLEX = 'gpt-5.4';
const edge = readFileSync(
  new URL('../supabase/functions/mindagent-chat/index.ts', import.meta.url),
  'utf8',
);

test('modelo rápido fica restrito a fatos simples do Concierge', () => {
  assert.deepEqual(
    modeloInicialDoTurno('Onde fica o credenciamento?', 'concierge_summit', 2, FAST, COMPLEX),
    { model: FAST, reason: 'factual_simples' },
  );
  assert.deepEqual(
    modeloInicialDoTurno('Que horas começa?', 'concierge_summit', 0, FAST, COMPLEX),
    { model: FAST, reason: 'factual_simples' },
  );
});

test('venda, recomendação, sessão específica e outra rota ficam no completo', () => {
  assert.equal(
    modeloInicialDoTurno('Qual ingresso vale mais a pena?', 'concierge_summit', 0, FAST, COMPLEX).model,
    COMPLEX,
  );
  assert.equal(
    modeloInicialDoTurno('O que você recomenda para minha equipe?', 'concierge_summit', 0, FAST, COMPLEX).model,
    COMPLEX,
  );
  assert.equal(
    modeloInicialDoTurno('Onde fica a palestra da Amy?', 'concierge_summit', 0, FAST, COMPLEX).model,
    COMPLEX,
  );
  assert.equal(
    modeloInicialDoTurno('Onde fica?', 'summit_b2c', 0, FAST, COMPLEX).model,
    COMPLEX,
  );
});

test('follow-up e histórico cheio nunca caem no rápido', () => {
  assert.equal(
    modeloInicialDoTurno('E onde fica?', 'concierge_summit', 2, FAST, COMPLEX).model,
    COMPLEX,
  );
  assert.equal(
    modeloInicialDoTurno('Onde fica o banheiro?', 'concierge_summit', 4, FAST, COMPLEX).model,
    COMPLEX,
  );
  assert.equal(
    modeloInicialDoTurno('Que horas começa?', 'concierge_summit', 8, FAST, COMPLEX).model,
    COMPLEX,
  );
  for (const mensagem of ['Que horas ela começa?', 'Onde fica isso?', 'Qual é a sala dessa?']) {
    assert.equal(
      modeloInicialDoTurno(mensagem, 'concierge_summit', 2, FAST, COMPLEX).model,
      COMPLEX,
      mensagem,
    );
  }
});

test('rollout é estável e pode desligar o modelo rápido sem deploy', () => {
  assert.equal(bucketDeRollout('mesma-pessoa'), bucketDeRollout('mesma-pessoa'));
  assert.ok(bucketDeRollout('mesma-pessoa') >= 0 && bucketDeRollout('mesma-pessoa') < 100);
  assert.deepEqual(
    modeloInicialDoTurno('Onde fica o banheiro?', 'concierge_summit', 0, FAST, COMPLEX, false),
    { model: COMPLEX, reason: 'fora_do_rollout' },
  );
  assert.deepEqual(
    modeloInicialDoTurno('Onde fica o banheiro?', 'concierge_summit', 0, COMPLEX, COMPLEX),
    { model: COMPLEX, reason: 'config_unica' },
  );
});

test('retry de modelo não consome o orçamento independente de tools', () => {
  assert.equal(podeTentarModelo(1, 5), true);
  assert.equal(podeExecutarTool(0, 2), true);
  assert.equal(podeTentarModelo(4, 5), true);
  assert.equal(podeTentarModelo(5, 5), false);
  assert.equal(podeExecutarTool(1, 2), true);
  assert.equal(podeTentarModelo(2, 4), true);
  assert.equal(podeExecutarTool(2, 2), false);
});

test('validação mínima só aceita JSON com resposta não vazia', () => {
  assert.equal(saidaEstruturadaMinimaValida('{"answer":"Fica no térreo."}'), true);
  assert.equal(saidaEstruturadaMinimaValida('{"answer":"  "}'), false);
  assert.equal(saidaEstruturadaMinimaValida('não é json'), false);
  assert.equal(saidaEstruturadaMinimaValida('[]'), false);
});

test('Edge reconcilia lote e usa contadores separados nos fail-safes', () => {
  assert.match(edge, /journey_signals\?: unknown/);
  assert.match(edge, /function journeySignals/);
  assert.match(edge, /const VERSION = "1\.13\.0"/);
  assert.match(edge, /DEFAULT_MODEL_FAST = "gpt-5\.4-mini"/);
  assert.match(edge, /OPENAI_FAST_ROLLOUT_PERCENT/);
  assert.match(edge, /!podeExecutarTool\(rodadasTool, MAX_RODADAS_TOOL\) \|\|/);
  assert.match(edge, /!podeTentarModelo\(tentativaModelo \+ 1, MAX_TENTATIVAS_MODELO\)/);
  assert.match(edge, /podeTentarModelo\(tentativaModelo \+ 1, MAX_TENTATIVAS_MODELO\)/);
  [
    'ferramenta_solicitada',
    'abstinencia_exige_busca',
    'saida_invalida',
    'modelo_rapido_indisponivel',
  ].forEach((reason) => assert.match(edge, new RegExp(reason)));
  [
    'openai_ms', 'tool_ms', 'kit_ms', 'ai_context_chars',
    'instructions_chars', 'history_chars', 'schema_chars', 'tools_chars',
    'tool_result_chars', 'tentativas_modelo', 'model_reason',
  ].forEach((field) => assert.match(edge, new RegExp(field)));
});
