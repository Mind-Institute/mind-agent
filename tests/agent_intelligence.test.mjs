import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  executarChamadas,
  esforcoDeRaciocinio,
  extrairChamadas,
  MAX_RODADAS_TOOL,
  ORCAMENTO_TURNO_MS,
  produtoDoContexto,
  toolsDeIntelligence,
} from '../supabase/functions/_shared/agent-intelligence.ts';

const ferramentas = [
  {
    nome: 'buscar_intelligence',
    descricao: 'Busca candidatos.',
    parametros: {
      type: 'object',
      properties: { necessidade: { type: 'string' }, limite: { type: 'integer' } },
      required: ['necessidade'],
      additionalProperties: false,
    },
  },
  {
    nome: 'ler_intelligence',
    descricao: 'Lê um candidato.',
    parametros: {
      type: 'object',
      properties: { tipo: { type: 'string' }, id: { type: 'string' } },
      required: ['tipo', 'id'],
      additionalProperties: false,
    },
  },
];

test('o mesmo Core expõe somente ferramentas de leitura allowlisted', () => {
  const { tools, semExecutor } = toolsDeIntelligence([
    ...ferramentas,
    { nome: 'apagar_tudo', descricao: 'não pode', parametros: { type: 'object' } },
  ]);
  assert.deepEqual(tools.map((tool) => tool.name), ['buscar_intelligence', 'ler_intelligence']);
  assert.equal(semExecutor, 1);
  assert.ok(tools.every((tool) => tool.strict === true));
});

test('o Core encontra o produto escopado sem depender do canal', () => {
  assert.equal(produtoDoContexto({
    product_intelligence: { produto_da_rota: { produto_codigo: 'mind-summit-2026' } },
  }), 'mind-summit-2026');
  assert.equal(produtoDoContexto({ product_intelligence: { produtos: [{ codigo: 'institute' }] } }), 'institute');
  assert.equal(produtoDoContexto({ product_intelligence: { produtos: [{ codigo: 'a' }, { codigo: 'b' }] } }), null);
});

test('o raciocínio sobe só quando há lupa e complexidade comercial', () => {
  assert.equal(esforcoDeRaciocinio('compare as alternativas para aprovar a delegação', 0), 'none');
  assert.equal(esforcoDeRaciocinio('qual o horário?', 2), 'low');
  assert.equal(esforcoDeRaciocinio('compare as alternativas para aprovar a delegação', 2), 'medium');
  assert.equal(MAX_RODADAS_TOOL, 2);
  assert.equal(ORCAMENTO_TURNO_MS, 30_000);
});

test('tool calls são extraídas e executadas com escopo de rota, canal e produto', async () => {
  const calls = extrairChamadas({
    output: [{
      type: 'function_call', call_id: 'call_1', name: 'buscar_intelligence',
      arguments: JSON.stringify({ necessidade: 'NR-1 e liderança', limite: 99 }),
    }],
  });
  const recebidas = [];
  const resultado = await executarChamadas({
    rpc: async (name, args) => {
      recebidas.push({ name, args });
      return { data: { candidatos: [] }, error: null };
    },
  }, calls, {
    rota: 'summit_b2b', canal: 'whatsapp', produtoCodigo: 'mind-summit-2026',
  });

  assert.equal(resultado[0].ok, true);
  assert.equal(recebidas[0].name, 'mind_intelligence_buscar_contextual');
  assert.deepEqual(recebidas[0].args, {
    p_necessidade: 'NR-1 e liderança',
    p_limite: 10,
    p_rota: 'summit_b2b',
    p_canal: 'whatsapp',
    p_produto_codigo: 'mind-summit-2026',
    p_embedding: null,
  });
});
