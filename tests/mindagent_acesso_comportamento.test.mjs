/* ============================================================
   mindagent-acesso — a porta dos admins do sistema, rodando
   ============================================================
   Carrega o handler REAL de `supabase/functions/mindagent-acesso/index.ts`
   no Node, com `Deno` e o cliente Supabase stubados (o mesmo stub da
   `mindagent-chat`). O fonte não é reescrito além do especificador `npm:`.

   A tela de admins do sistema é pedido da Adriana (26/09/2026): ver e
   cadastrar quem entra no Mind Intelligence Admin. Quem decide é o banco
   (`mind_admin_read_admins`, `mind_admin_mutate_admins`, contrato em
   `tests/admins_no_painel_contract.sql`); aqui se confere o que é da
   porta: sessão validada antes, o ator é o dono do token, a versão vai
   junto no PATCH, e cada recusa do banco chega à tela na frase certa. */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const FONTE = new URL('../supabase/functions/mindagent-acesso/index.ts', import.meta.url);
const STUB = new URL('./helpers/supabase-stub.mjs', import.meta.url);
const IMPORT_VIVO = '"npm:@supabase/supabase-js@2.112.3"';
const BASE = 'https://projeto.supabase.co/functions/v1/mindagent-acesso';
const ORIGEM = 'https://admin.minddash.pro';
const ATOR = '11111111-1111-4111-8111-111111111111';
const LINHA = '33333333-3333-4333-8333-333333333333';

const ENV = {
  SUPABASE_URL: 'https://projeto.supabase.co',
  SUPABASE_ANON_KEY: 'chave-publicavel-de-teste',
  SUPABASE_SERVICE_ROLE_KEY: 'chave-secreta-de-teste',
  ADMIN_ALLOWED_ORIGINS: ORIGEM,
};

let handler = null;

async function carregar() {
  if (handler) return handler;
  const partes = readFileSync(FONTE, 'utf8').split(IMPORT_VIVO);
  if (partes.length !== 2) throw new Error('o import do supabase-js mudou — revise o teste');
  const arquivo = join(mkdtempSync(join(tmpdir(), 'acesso-')), 'index.mts');
  writeFileSync(arquivo, partes.join(JSON.stringify(STUB.href)));
  let capturado = null;
  globalThis.Deno = {
    env: { get: (nome) => ENV[nome] },
    serve: (fn) => { capturado = fn; return { finished: Promise.resolve() }; },
  };
  await import(pathToFileURL(arquivo).href);
  handler = capturado;
  return handler;
}

const ADMINS = [
  { id: LINHA, nome: 'Ana Ribeiro', email: 'ana@joinmind.com.br', papel: 'editor', ativo: true,
    loginLigado: true, atualizadoEm: '2026-09-26T14:00:00.123456+00:00' },
  { id: '44444444-4444-4444-8444-444444444444', nome: 'João Conceição', email: 'joao@joinmind.com.br',
    papel: 'analista', ativo: false, loginLigado: false, atualizadoEm: '2026-09-26T14:00:00+00:00' },
];

/** Roda um pedido; `rpc` responde por nome e devolve { data, error }. */
async function chamar({ metodo = 'GET', caminho, corpo, token = 'token-valido', cabecalhos = {}, rpc = {} }) {
  const chamadas = [];
  globalThis.__MIND_EDGE_TESTE__ = {
    getUser: async (t) => (t === 'token-valido'
      ? { data: { user: { id: ATOR } }, error: null }
      : { data: { user: null }, error: { message: 'jwt inválido' } }),
    rpc: async (nome, args) => {
      chamadas.push({ nome, args });
      const r = rpc[nome];
      const saida = typeof r === 'function' ? r(args) : r;
      return saida ?? { data: null, error: { message: 'sem resposta no teste' } };
    },
  };
  const h = await carregar();
  const headers = { Origin: ORIGEM, ...cabecalhos };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (corpo !== undefined) headers['Content-Type'] = 'application/json';
  const resposta = await h(new Request(BASE + caminho, {
    method: metodo, headers, body: corpo === undefined ? undefined : JSON.stringify(corpo),
  }));
  const texto = await resposta.text();
  return { resposta, corpo: texto ? JSON.parse(texto) : null, chamadas };
}

test('o preflight libera o que a tela de admins usa', async () => {
  const h = await carregar();
  const r = await h(new Request(BASE + '/admin/admins', { method: 'OPTIONS', headers: { Origin: ORIGEM } }));
  assert.equal(r.status, 204);
  assert.match(r.headers.get('Access-Control-Allow-Methods'), /PATCH/);
  assert.match(r.headers.get('Access-Control-Allow-Headers'), /if-unmodified-since-version/);
  assert.equal(r.headers.get('Access-Control-Allow-Origin'), ORIGEM);
});

test('sem sessão não se chega ao banco', async () => {
  const { resposta, chamadas } = await chamar({ caminho: '/admin/admins', token: null });
  assert.equal(resposta.status, 401);
  assert.equal(chamadas.length, 0);
});

test('origem de fora é recusada antes de tudo', async () => {
  const h = await carregar();
  const r = await h(new Request(BASE + '/admin/admins', {
    headers: { Origin: 'https://site-qualquer.com', Authorization: 'Bearer token-valido' },
  }));
  assert.equal(r.status, 403);
});

test('a lista vem do banco com o dono do token como ator, e a busca ignora acento', async () => {
  const { resposta, corpo, chamadas } = await chamar({
    caminho: '/admin/admins?busca=CONCEICAO',
    rpc: { mind_admin_read_admins: { data: ADMINS, error: null } },
  });
  assert.equal(resposta.status, 200);
  assert.deepEqual(chamadas[0], { nome: 'mind_admin_read_admins', args: { p_actor_id: ATOR, p_id: null } });
  assert.deepEqual(corpo.itens.map((i) => i.nome), ['João Conceição']);
  assert.equal(corpo.total, 1);
});

test('filtra por ativo e por papel', async () => {
  const { corpo } = await chamar({
    caminho: '/admin/admins?ativo=true&papel=editor',
    rpc: { mind_admin_read_admins: { data: ADMINS, error: null } },
  });
  assert.deepEqual(corpo.itens.map((i) => i.id), [LINHA]);
});

test('uma linha pelo id; id que não é uuid não chega ao banco', async () => {
  const um = await chamar({
    caminho: `/admin/admins/${LINHA}`,
    rpc: { mind_admin_read_admins: { data: [ADMINS[0]], error: null } },
  });
  assert.equal(um.resposta.status, 200);
  assert.equal(um.corpo.id, LINHA);
  assert.deepEqual(um.chamadas[0].args, { p_actor_id: ATOR, p_id: LINHA });

  const ruim = await chamar({ caminho: '/admin/admins/nao-e-uuid' });
  assert.equal(ruim.resposta.status, 404);
  assert.equal(ruim.chamadas.length, 0);
});

test('dar acesso manda só e-mail e papel, com o ator do token', async () => {
  const { resposta, chamadas } = await chamar({
    metodo: 'POST', caminho: '/admin/admins',
    corpo: { email: 'nova@joinmind.com.br', papel: 'editor', mindId: 'forjado', ativo: false },
    rpc: { mind_admin_mutate_admins: { data: { ...ADMINS[0], id: 'novo' }, error: null } },
  });
  assert.equal(resposta.status, 201);
  const { nome, args } = chamadas[0];
  assert.equal(nome, 'mind_admin_mutate_admins');
  assert.equal(args.p_action, 'conceder');
  assert.equal(args.p_actor_id, ATOR);
  assert.deepEqual(args.p_payload, { email: 'nova@joinmind.com.br', papel: 'editor' });
});

test('mudar papel e ativo leva a versão que a tela viu, e só esses dois campos', async () => {
  const { resposta, chamadas } = await chamar({
    metodo: 'PATCH', caminho: `/admin/admins/${LINHA}`,
    corpo: { papel: 'analista', ativo: false, email: 'trocado@joinmind.com.br' },
    cabecalhos: { 'If-Unmodified-Since-Version': ADMINS[0].atualizadoEm },
    rpc: { mind_admin_mutate_admins: { data: { ...ADMINS[0], papel: 'analista', ativo: false }, error: null } },
  });
  assert.equal(resposta.status, 200);
  const { args } = chamadas[0];
  assert.equal(args.p_action, 'atualizar');
  assert.equal(args.p_id, LINHA);
  assert.equal(args.p_expected_updated_at, ADMINS[0].atualizadoEm);
  assert.deepEqual(args.p_payload, { papel: 'analista', ativo: false });
});

test('cada recusa do banco chega na frase que a tela mostra', async () => {
  const casos = [
    [{ message: 'admin_validation:nao_e_equipe', code: '22023' }, 422, /não está marcada como equipe/],
    [{ message: 'admin_validation:pessoa_nao_encontrada', code: '22023' }, 422, /não é de ninguém no Mind ID/],
    [{ message: 'admin_validation:dominio', code: '22023' }, 422, /@joinmind\.com\.br/],
    [{ message: 'admin_validation:proprio_acesso', code: '22023' }, 422, /próprio acesso/],
    [{ message: 'admin_forbidden:so_administrador', code: '42501' }, 403, /Só administrador/],
    [{ message: 'admin_conflict', code: '40001' }, 409, /alterado por outra pessoa/],
    [{ message: 'admin_not_found', code: 'P0002' }, 404, /não encontrado/],
  ];
  for (const [erro, status, frase] of casos) {
    const { resposta, corpo } = await chamar({
      metodo: 'POST', caminho: '/admin/admins', corpo: { email: 'x@joinmind.com.br', papel: 'editor' },
      rpc: { mind_admin_mutate_admins: { data: null, error: erro } },
    });
    assert.equal(resposta.status, status, erro.message);
    assert.match(corpo.mensagem, frase, erro.message);
  }
});

test('o primeiro login continua ligando a conta, como antes', async () => {
  const { resposta, corpo, chamadas } = await chamar({
    metodo: 'POST', caminho: '/admin/vincular',
    rpc: { mind_admin_vincular_login: { data: { vinculado: true, role: 'administrador', active: true, display_name: 'Ana' }, error: null } },
  });
  assert.equal(resposta.status, 200);
  assert.deepEqual(corpo, { vinculado: true, papel: 'administrador', nome: 'Ana' });
  assert.deepEqual(chamadas[0], { nome: 'mind_admin_vincular_login', args: { p_user_id: ATOR } });
});
