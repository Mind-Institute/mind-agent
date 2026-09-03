import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  modeloInicialDoTurno,
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

test('venda, recomendação, outra rota e contexto longo ficam no completo', () => {
  assert.equal(
    modeloInicialDoTurno('Qual ingresso vale mais a pena?', 'concierge_summit', 0, FAST, COMPLEX).model,
    COMPLEX,
  );
  assert.equal(
    modeloInicialDoTurno('O que você recomenda para minha equipe?', 'concierge_summit', 0, FAST, COMPLEX).model,
    COMPLEX,
  );
  assert.equal(
    modeloInicialDoTurno('Onde fica?', 'summit_b2c', 0, FAST, COMPLEX).model,
    COMPLEX,
  );
  assert.equal(
    modeloInicialDoTurno('Onde fica o banheiro?', 'concierge_summit', 9, FAST, COMPLEX).model,
    COMPLEX,
  );
});

test('configuração com um modelo só preserva o comportamento anterior', () => {
  assert.deepEqual(
    modeloInicialDoTurno('Onde fica o banheiro?', 'concierge_summit', 0, COMPLEX, COMPLEX),
    { model: COMPLEX, reason: 'config_unica' },
  );
});

test('validação mínima só aceita JSON com resposta não vazia', () => {
  assert.equal(saidaEstruturadaMinimaValida('{"answer":"Fica no térreo."}'), true);
  assert.equal(saidaEstruturadaMinimaValida('{"answer":"  "}'), false);
  assert.equal(saidaEstruturadaMinimaValida('não é json'), false);
  assert.equal(saidaEstruturadaMinimaValida('[]'), false);
});

test('Edge reconcilia lote da jornada e mantém todos os fail-safes observáveis', () => {
  assert.match(edge, /journey_signals\?: unknown/);
  assert.match(edge, /function journeySignals/);
  assert.match(edge, /const VERSION = "1\.13\.0"/);
  assert.match(edge, /DEFAULT_MODEL_FAST = "gpt-5\.4-mini"/);
  [
    'ferramenta_solicitada',
    'abstinencia_exige_busca',
    'saida_invalida',
    'modelo_rapido_indisponivel',
  ].forEach((reason) => assert.match(edge, new RegExp(reason)));
  ['openai_ms', 'tool_ms', 'kit_ms', 'context_chars', 'model_reason']
    .forEach((field) => assert.match(edge, new RegExp(field)));
});
