import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';

/* Agent Intelligence no painel: canais, kit e prompts por agente, pela
   mindagent-knowledge. Só administrador escreve (Adriana, 22/10/2026). */
const source = readFileSync(new URL('../supabase/functions/mindagent-knowledge/index.ts', import.meta.url), 'utf8');
const code = stripTypeScriptTypes(source.replace(/^import .*;\n/gm, ''));
const USUARIO = '33333333-3333-4333-8333-333333333333';

async function call({ method = 'GET', path, role = 'administrador', body, headers = {}, rpcError = null } = {}) {
  let handler;
  const rpcs = [];
  const chain = {
    select() { return this; },
    eq() { return this; },
    async maybeSingle() { return { data: { display_name: 'Teste', role, active: true }, error: null }; },
  };
  const client = {
    auth: { getUser: async () => ({ data: { user: { id: USUARIO } }, error: null }) },
    from: () => chain,
    rpc: async (nome, args) => {
      /* Os argumentos nascem no contexto do vm: JSON os traz para o realm do teste. */
      rpcs.push(JSON.parse(JSON.stringify({ nome, args })));
      if (rpcError) return { data: null, error: rpcError };
      return { data: nome.startsWith('mind_admin_read_') ? [{ id: 'x' }] : { id: 'x' }, error: null };
    },
  };
  vm.runInNewContext(code, {
    Request, Response, URL, crypto: webcrypto, console: { error() {} }, createClient: () => client,
    Deno: {
      serve: (fn) => { handler = fn; },
      env: { get: (key) => ({ SUPABASE_URL: 'https://test.supabase.co', SUPABASE_ANON_KEY: 'fake-anon', SUPABASE_SERVICE_ROLE_KEY: 'fake-service' })[key] },
    },
  });
  const init = { method, headers: { Authorization: 'Bearer valid', ...headers } };
  if (body !== undefined) {
    init.body = JSON.stringify(body);
    init.headers['Content-Type'] = 'application/json';
  }
  const response = await handler(new Request('https://test.invalid/functions/v1/mindagent-knowledge' + path, init));
  return { status: response.status, body: await response.json(), rpcs };
}

test('lista canais, kit e prompts pelas portas de leitura', async () => {
  for (const [path, rpc] of [
    ['/admin/agent_channels', 'mind_admin_read_agent_channels'],
    ['/admin/agent_kit_blocks', 'mind_admin_read_agent_kit'],
    ['/admin/agent_prompts', 'mind_admin_read_agent_prompts'],
  ]) {
    const r = await call({ path, role: 'analista' });
    assert.equal(r.status, 200);
    assert.deepEqual(r.rpcs, [{ nome: rpc, args: { p_id: null } }]);
  }
});

test('abrir um prompt pede o histórico pela chave', async () => {
  const r = await call({ path: '/admin/agent_prompts/playbook_mia_summit_2026' });
  assert.equal(r.status, 200);
  assert.deepEqual(r.rpcs[0].args, { p_id: 'playbook_mia_summit_2026' });
});

for (const role of ['editor', 'aprovador', 'analista']) {
  test(`${role} não altera prompt, kit nem canal`, async () => {
    for (const [method, path] of [
      ['PATCH', '/admin/agent_prompts/playbook_mia_summit_2026'],
      ['PATCH', '/admin/agent_kit_blocks/mia_summit_2026%3A%3Aevento'],
      ['POST', '/admin/agent_kit_blocks'],
      ['PATCH', '/admin/agent_channels/mindagent-web%3A%3Amia_summit_2026'],
    ]) {
      const r = await call({ method, path, role, body: { ativo: true } });
      assert.equal(r.status, 403);
      assert.equal(r.rpcs.length, 0);
    }
  });
}

test('salvar prompt repassa o usuário e a versão esperada', async () => {
  const r = await call({
    method: 'PATCH',
    path: '/admin/agent_prompts/playbook_mia_summit_2026',
    body: { conteudo: 'novo texto', ativo: false },
    headers: { 'If-Unmodified-Since-Version': '2026-10-22T12:05:12.019284+00:00' },
  });
  assert.equal(r.status, 200);
  assert.deepEqual(r.rpcs, [{
    nome: 'mind_admin_update_agent_prompt',
    args: {
      p_chave: 'playbook_mia_summit_2026', p_titulo: null, p_conteudo: 'novo texto', p_ativo: false,
      p_ator: USUARIO, p_atualizado_em_esperado: '2026-10-22T12:05:12.019284+00:00',
    },
  }]);
});

test('prompt gigante é recusado antes do banco', async () => {
  const r = await call({ method: 'PATCH', path: '/admin/agent_prompts/base', body: { conteudo: 'x'.repeat(100_001) } });
  assert.equal(r.status, 422);
  assert.equal(r.rpcs.length, 0);
});

test('acrescentar bloco ao kit usa agente e bloco do corpo, sem versão esperada', async () => {
  const r = await call({
    method: 'POST',
    path: '/admin/agent_kit_blocks',
    body: { rota: 'mia_summit_2026', bloco: 'product_decisioning', ativo: true, obrigatorio: false },
    headers: { 'If-Unmodified-Since-Version': 'ignorada' },
  });
  assert.equal(r.status, 201);
  assert.deepEqual(r.rpcs[0], {
    nome: 'mind_admin_upsert_agent_kit_block',
    args: {
      p_rota: 'mia_summit_2026', p_bloco: 'product_decisioning', p_ativo: true, p_obrigatorio: false,
      p_ator: USUARIO, p_atualizado_em_esperado: null,
    },
  });
});

test('bloco sem agente ou sem nome não chega ao banco', async () => {
  const r = await call({ method: 'POST', path: '/admin/agent_kit_blocks', body: { rota: 'mia_summit_2026' } });
  assert.equal(r.status, 422);
  assert.equal(r.rpcs.length, 0);
});

test('ligar canal repassa o canal::rota da URL', async () => {
  const r = await call({ method: 'PATCH', path: '/admin/agent_channels/mindagent-web%3A%3Amia_summit_2026', body: { ativo: true } });
  assert.equal(r.status, 200);
  assert.equal(r.rpcs[0].nome, 'mind_admin_update_agent_channel');
  assert.equal(r.rpcs[0].args.p_id, 'mindagent-web::mia_summit_2026');
  assert.equal(r.rpcs[0].args.p_ativo, true);
  assert.equal(r.rpcs[0].args.p_observacao, null);
});

for (const [nome, error, status] of [
  ['conflito', { code: '40001', message: 'admin_conflict' }, 409],
  ['papel recusado no banco', { code: '42501', message: 'admin_forbidden' }, 403],
  ['não encontrado', { code: 'P0002', message: 'admin_not_found' }, 404],
  ['validação', { code: '22023', message: 'admin_validation:rota' }, 422],
  ['falha qualquer', { code: 'XX000', message: 'boom' }, 503],
]) {
  test(`recusa do banco: ${nome}`, async () => {
    const r = await call({ method: 'PATCH', path: '/admin/agent_kit_blocks/mia_summit_2026%3A%3Aevento', body: { ativo: false }, rpcError: error });
    assert.equal(r.status, status);
  });
}
