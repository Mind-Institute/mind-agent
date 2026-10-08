import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';
const source = readFileSync(new URL('../supabase/functions/mindagent-home/index.ts', import.meta.url), 'utf8');
const code = stripTypeScriptTypes(source.replace(/^import .*;\n/gm, ''));
async function call({ method = 'GET', token = 'valid', active = true, authError = false, dbError = false, origin, path = '/admin/decisoes' } = {}) {
  let handler; const reads = [];
  const row = { codigo: 'D27', titulo: 'Teste', implementacao: { situacao: 'parcial', leitura: 'Teste mapa', lugares: [], medido_em: '2026-10-07' } };
  const chain = { select() { return this; }, eq() { return this; }, async maybeSingle() { return { data: { active, role: 'analista' }, error: null }; },
    async order() { return { data: [row], error: dbError ? { code: 'TEST' } : null }; } };
  const client = { auth: { getUser: async () => ({ data: { user: authError ? null : { id: 'test-user' } }, error: authError }) },
    from: () => chain, schema: (schema) => ({ from: (table) => { reads.push({ schema, table }); return chain; } }) };
  vm.runInNewContext(code, { Request, Response, URL, crypto: webcrypto, console: { error() {} }, createClient: () => client,
    Deno: { serve: (fn) => { handler = fn; }, env: { get: (key) => ({ SUPABASE_URL: 'https://test.supabase.co', SUPABASE_ANON_KEY: 'fake-anon', SUPABASE_SERVICE_ROLE_KEY: 'fake-service' })[key] } } });
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (origin) headers.Origin = origin;
  const response = await handler(new Request('https://test.invalid'+path, { method, headers }));
  return { status: response.status, body: await response.json(), reads };
}
test('lê somente o schema arquitetura após conferir o admin ativo', async () => {
  const result = await call();
  assert.equal(result.status, 200); assert.deepEqual(result.reads, [{ schema: 'arquitetura', table: 'decisoes' }]);
  assert.equal(result.body.fonte, 'arquitetura.decisoes'); assert.equal(result.body.itens[0].codigo, 'D27');
  assert.equal(result.body.itens[0].situacao, 'parcial'); assert.equal(result.body.itens[0].implementacao, undefined);
});
for (const [name, options, status] of [
  ['sem login', { token: null }, 401], ['token inválido', { authError: true }, 401],
  ['admin desativado', { active: false }, 403], ['origem estranha', { origin: 'https://strange.invalid' }, 403],
  ['escrita recusada', { method: 'POST' }, 405], ['rota extra', { path: '/admin/decisoes/D1' }, 404],
]) test(name, async () => { const r = await call(options); assert.equal(r.status, status); assert.equal(r.reads.length, 0); });
test('erro de banco não devolve cópia local', async () => { const r = await call({ dbError: true }); assert.equal(r.status, 503); assert.equal(r.body.itens, undefined); });
