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

async function call({ method = 'GET', path, role = 'administrador', body, headers = {}, rpcError = null, indexador } = {}) {
  let handler;
  const rpcs = [];
  const buscas = [];
  /* O indexador (mindagent-index-knowledge) como a rede o devolveria. */
  const fetch = async (url, init) => {
    buscas.push(JSON.parse(JSON.stringify({ url, headers: init.headers, body: JSON.parse(init.body) })));
    if (indexador === 'rede') throw new TypeError('fetch failed');
    const { status = 200, corpo = { ok: true, requested: 100, indexed: 100, remaining: true } } = indexador ?? {};
    return new Response(JSON.stringify(corpo), { status, headers: { 'Content-Type': 'application/json' } });
  };
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
    Request, Response, URL, fetch, crypto: webcrypto, console: { error() {} }, createClient: () => client,
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
  return { status: response.status, body: await response.json(), rpcs, buscas };
}

test('lista canais, kit e prompts pelas portas de leitura', async () => {
  for (const [path, rpc] of [
    ['/admin/agent_channels', 'mind_admin_read_agent_channels'],
    ['/admin/agent_kit_blocks', 'mind_admin_read_agent_kit'],
    ['/admin/agent_prompts', 'mind_admin_read_agent_prompts'],
    ['/admin/agent_instructions', 'mind_admin_read_agent_instructions'],
    ['/admin/agent_tools', 'mind_admin_read_agent_tools'],
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
  test(`${role} não altera prompt, kit, canal, instrução nem ferramenta`, async () => {
    for (const [method, path] of [
      ['PATCH', '/admin/agent_prompts/playbook_mia_summit_2026'],
      ['PATCH', '/admin/agent_kit_blocks/mia_summit_2026%3A%3Aevento'],
      ['POST', '/admin/agent_kit_blocks'],
      ['PATCH', '/admin/agent_channels/mindagent-web%3A%3Amia_summit_2026'],
      ['POST', '/admin/agent_instructions'],
      ['PATCH', '/admin/agent_tools/buscar_intelligence'],
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

/* Fase 1 da ficha do agente (Adriana, 22/10/2026): o que o agente recebe, com
   liga/desliga, instrução própria e descrição das ferramentas. */
test('abrir as instruções de um agente pede o texto montado pela rota', async () => {
  const r = await call({ path: '/admin/agent_instructions/mia_summit_2026', role: 'analista' });
  assert.equal(r.status, 200);
  assert.deepEqual(r.rpcs, [{ nome: 'mind_admin_read_agent_instructions', args: { p_id: 'mia_summit_2026' } }]);
});

test('criar voz própria repassa agente, chave, texto, o bloco substituído e o usuário', async () => {
  const r = await call({
    method: 'POST',
    path: '/admin/agent_instructions',
    body: { rota: 'mia_summit_2026', chave: 'tom_de_voz_mia_summit_2026', titulo: 'Voz da MIA', conteudo: 'texto', substitui: 'tom_de_voz' },
  });
  assert.equal(r.status, 201);
  assert.deepEqual(r.rpcs, [{
    nome: 'mind_admin_create_agent_instruction',
    args: {
      p_rota: 'mia_summit_2026', p_chave: 'tom_de_voz_mia_summit_2026', p_titulo: 'Voz da MIA',
      p_conteudo: 'texto', p_substitui: 'tom_de_voz', p_ator: USUARIO,
    },
  }]);
});

test('chave repetida volta com a frase certa', async () => {
  const r = await call({
    method: 'POST', path: '/admin/agent_instructions', body: { rota: 'mia_summit_2026', chave: 'base', titulo: 't', conteudo: 'x' },
    rpcError: { code: '22023', message: 'admin_validation:chave_existe' },
  });
  assert.equal(r.status, 422);
  assert.match(r.body.mensagem, /Já existe/);
});

test('descrição de ferramenta repassa o nome da URL e a versão esperada', async () => {
  const r = await call({
    method: 'PATCH', path: '/admin/agent_tools/buscar_intelligence', body: { descricao: 'nova' },
    headers: { 'If-Unmodified-Since-Version': '2026-10-22T13:12:51+00:00' },
  });
  assert.equal(r.status, 200);
  assert.deepEqual(r.rpcs, [{
    nome: 'mind_admin_update_agent_tool',
    args: { p_nome: 'buscar_intelligence', p_descricao: 'nova', p_ator: USUARIO, p_atualizado_em_esperado: '2026-10-22T13:12:51+00:00' },
  }]);
});

test('descrição gigante de ferramenta é recusada antes do banco', async () => {
  const r = await call({ method: 'PATCH', path: '/admin/agent_tools/buscar_intelligence', body: { descricao: 'x'.repeat(4_001) } });
  assert.equal(r.status, 422);
  assert.equal(r.rpcs.length, 0);
});

/* Botão "Gerar embeddings" (Adriana, 22/10/2026): o painel não tem a chave
   secreta; a mindagent-knowledge confere o admin e chama o indexador. */
test('gerar embeddings chama o indexador com a chave secreta em apikey', async () => {
  const r = await call({ method: 'POST', path: '/admin/knowledge_embeddings', role: 'editor', body: { schema: 'summit_2026' } });
  assert.equal(r.status, 200);
  assert.deepEqual(r.body, { schema: 'summit_2026', processados: 100, pedidos: 100, restantes: true });
  assert.equal(r.buscas.length, 1);
  assert.equal(r.buscas[0].url, 'https://test.supabase.co/functions/v1/mindagent-index-knowledge');
  assert.equal(r.buscas[0].headers.apikey, 'fake-service');
  assert.equal(r.buscas[0].headers.Authorization, undefined);
  assert.deepEqual(r.buscas[0].body, { schema: 'summit_2026', limite: 100 });
});

test('analista não gera embeddings', async () => {
  const r = await call({ method: 'POST', path: '/admin/knowledge_embeddings', role: 'analista', body: { schema: 'summit_2026' } });
  assert.equal(r.status, 403);
  assert.equal(r.buscas.length, 0);
});

test('base desconhecida não chega ao indexador', async () => {
  const r = await call({ method: 'POST', path: '/admin/knowledge_embeddings', body: { schema: 'public' } });
  assert.equal(r.status, 422);
  assert.equal(r.buscas.length, 0);
});

test('a última rodada diz que não resta nada', async () => {
  const r = await call({
    method: 'POST', path: '/admin/knowledge_embeddings', body: { schema: 'summit_2026' },
    indexador: { corpo: { ok: true, requested: 40, indexed: 40, remaining: false } },
  });
  assert.deepEqual(r.body, { schema: 'summit_2026', processados: 40, pedidos: 40, restantes: false });
});

for (const [nome, indexador] of [
  ['indexador recusa', { status: 500, corpo: { error: 'embedding_failed' } }],
  ['rede cai', 'rede'],
]) {
  test(`falha do indexador vira 503 sem vazar o motivo: ${nome}`, async () => {
    const r = await call({ method: 'POST', path: '/admin/knowledge_embeddings', body: { schema: 'summit_2026' }, indexador });
    assert.equal(r.status, 503);
    assert.equal(r.body.codigo, 'indisponivel');
    assert.equal(JSON.stringify(r.body).includes('embedding_failed'), false);
  });
}
