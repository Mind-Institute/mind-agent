import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';

/* O Router (supabase/functions/router) escolhe SÓ entre o que o painel marcou
   como roteável no canal (`mind_canal_rotas.roteaveis`), e não tem lista
   própria de rotas (Adriana, 22/10/2026). Handler real, banco e OpenAI
   simulados. */
const source = readFileSync(new URL('../supabase/functions/router/index.ts', import.meta.url), 'utf8');
const code = stripTypeScriptTypes(source.replace(/^import .*;\n/gm, ''));
const CONVERSA = '44444444-4444-4444-8444-444444444444';

async function rotear({ politica, saidaDoModelo = { rota: 'institute', precisa_esclarecer: false, candidatas: [] }, mensagens } = {}) {
  let handler;
  const pedidosAoModelo = [];
  const client = {
    rpc: async (nome, args) => {
      const respostas = {
        analise_config: { analise_token: 'segredo', openai_model: 'modelo-de-teste' },
        mind_agent_context: {
          ok: true,
          conversation: { canal: 'mindagent-web', mensagens: mensagens ?? [{ papel: 'lead', conteudo: 'quero um curso' }] },
        },
        mind_canal_rotas: politica,
        analise_prompt: { conteudo: 'PROMPT DO ROTEADOR' },
      };
      assert.ok(nome in respostas, `rpc fora do cenário: ${nome}`);
      return { data: JSON.parse(JSON.stringify(respostas[nome])), error: null, args };
    },
  };
  const fetch = async (_url, init) => {
    pedidosAoModelo.push(JSON.parse(init.body));
    return new Response(JSON.stringify({ output_text: JSON.stringify(saidaDoModelo) }), { status: 200 });
  };
  vm.runInNewContext(code, {
    Request, Response, URL, fetch, crypto: webcrypto, AbortController, DOMException, setTimeout, clearTimeout,
    console: { error() {}, warn() {}, info() {} }, createClient: () => client,
    Deno: {
      serve: (fn) => { handler = fn; },
      env: { get: (k) => ({ SUPABASE_URL: 'https://test.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'x', OPENAI_API_KEY: 'k' })[k] },
    },
  });
  const resposta = await handler(new Request('https://test.invalid/functions/v1/router?token=segredo', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ conversa_id: CONVERSA, canal: 'mindagent-web' }),
  }));
  return { status: resposta.status, body: await resposta.json(), pedidosAoModelo };
}

const POLITICA = {
  ok: true, canal: 'mindagent-web',
  rotas: ['cliente_suporte', 'concierge_summit', 'institute', 'mia_summit_2026'],
  roteaveis: ['cliente_suporte', 'institute'],
};

test('o modelo só pode escolher entre as roteáveis, não entre tudo que o canal atende', async () => {
  const r = await rotear({ politica: POLITICA });
  assert.equal(r.status, 200);
  assert.equal(r.body.rota, 'institute');
  const pedido = r.pedidosAoModelo[0];
  assert.deepEqual(pedido.text.format.schema.properties.rota.enum, ['cliente_suporte', 'institute', null]);
  assert.deepEqual(pedido.text.format.schema.properties.candidatas.items.enum, ['cliente_suporte', 'institute']);
  assert.deepEqual(JSON.parse(pedido.input[0].content).competencias_disponiveis, ['cliente_suporte', 'institute']);
});

test('uma rota atendida pelo canal mas não roteável é rejeitada mesmo que o modelo a devolva', async () => {
  const r = await rotear({ politica: POLITICA, saidaDoModelo: { rota: 'mia_summit_2026', precisa_esclarecer: false, candidatas: [] } });
  assert.equal(r.status, 502);
  assert.equal(r.body.error, 'saida_invalida');
});

test('canal sem nada roteável não chama o modelo', async () => {
  const r = await rotear({ politica: { ...POLITICA, roteaveis: [] } });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { ok: false, motivo: 'canal_sem_competencia' });
  assert.equal(r.pedidosAoModelo.length, 0);
});

test('o fonte não tem lista própria de rotas', () => {
  assert.doesNotMatch(source, /const ROTAS\s*=/);
  assert.match(source, /politica\.roteaveis/);
});
