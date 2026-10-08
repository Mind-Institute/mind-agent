/* ============================================================
   mindagent-summit — a programação do Summit 2026 no painel, rodando
   ============================================================
   Carrega o handler REAL de `supabase/functions/mindagent-summit/index.ts`
   no Node, com `Deno` e o cliente Supabase stubados (o mesmo stub das outras
   funções do painel). O fonte não é reescrito além do especificador `npm:`.

   Pedido da Adriana (26/09/2026): a tabela de programação "conforme está no
   backend", só leitura. Quem monta a linha é o banco
   (`mind_admin_read_summit_2026_sessoes`, contrato em
   `tests/summit_programacao_contract.sql`); aqui se confere o que é da porta:
   sessão e papel antes de ler, só GET, busca, filtros e ordem na lista
   inteira antes de paginar. */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const FONTE = new URL('../supabase/functions/mindagent-summit/index.ts', import.meta.url);
const STUB = new URL('./helpers/supabase-stub.mjs', import.meta.url);
const IMPORT_VIVO = '"npm:@supabase/supabase-js@2.112.3"';
const BASE = 'https://projeto.supabase.co/functions/v1/mindagent-summit';
const ORIGEM = 'https://admin.minddash.pro';
const ID = '0f8e2a4c-1b3d-4e5f-8a9b-0c1d2e3f4a5b';

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
  const arquivo = join(mkdtempSync(join(tmpdir(), 'summit-')), 'index.mts');
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

/* Sessões como o banco devolve (nomes das colunas do banco). Inventadas. */
const SESSOES = [
  { id: ID, dia: '2026-09-16', inicio: '2026-09-16T12:00:00+00:00', titulo: 'Abertura', tipo: 'abertura',
    espaco_id: 'e1', espaco: 'Palco Principal', palestrantes: ['Ana Exemplo'], precisa_reserva: false,
    vagas_disponiveis: null, descricao: null },
  { id: 'b', dia: '2026-09-16', inicio: '2026-09-16T14:00:00+00:00', titulo: 'Workshop de liderança',
    tipo: 'workshop', espaco_id: 'e2', espaco: 'Sala Ágora', palestrantes: ['Bruno Exemplo'],
    precisa_reserva: true, vagas_disponiveis: 9, descricao: 'Prática em grupo' },
  { id: 'c', dia: '2026-09-17', inicio: '2026-09-17T13:00:00+00:00', titulo: 'Almoço', tipo: 'almoco',
    espaco_id: null, espaco: null, palestrantes: [], precisa_reserva: false, vagas_disponiveis: null,
    descricao: null },
  { id: 'd', dia: '2026-09-17', inicio: '2026-09-17T15:00:00+00:00', titulo: 'Masterclass', tipo: 'masterclass',
    espaco_id: 'e2', espaco: 'Sala Ágora', palestrantes: ['Carla Exemplo'], precisa_reserva: true,
    vagas_disponiveis: 10, descricao: null },
];

async function chamar({ metodo = 'GET', caminho, token = 'token-valido', papel = 'analista', ativo = true, rpc }) {
  const chamadas = [];
  globalThis.__MIND_EDGE_TESTE__ = {
    getUser: async (t) => (t === 'token-valido'
      ? { data: { user: { id: 'ator' } }, error: null }
      : { data: { user: null }, error: { message: 'jwt inválido' } }),
    from: () => ({ select: () => ({ eq: () => ({
      maybeSingle: async () => ({ data: papel ? { display_name: 'Ana', role: papel, active: ativo } : null, error: null }),
    }) }) }),
    rpc: async (nome, args) => {
      chamadas.push({ nome, args });
      return rpc ?? { data: structuredClone(SESSOES), error: null };
    },
  };
  const h = await carregar();
  const headers = { Origin: ORIGEM };
  if (token) headers.Authorization = `Bearer ${token}`;
  const r = await h(new Request(BASE + caminho, { method: metodo, headers }));
  const texto = await r.text();
  return { r, corpo: texto ? JSON.parse(texto) : null, chamadas };
}

const titulos = (corpo) => corpo.itens.map((i) => i.titulo);

test('sem sessão, ou sem lugar na lista do painel, não se chega ao banco', async () => {
  const semToken = await chamar({ caminho: '/admin/summit_2026_sessions', token: null });
  assert.equal(semToken.r.status, 401);
  assert.equal(semToken.chamadas.length, 0);
  const inativo = await chamar({ caminho: '/admin/summit_2026_sessions', ativo: false });
  assert.equal(inativo.r.status, 403);
  assert.equal(inativo.chamadas.length, 0);
});

test('qualquer papel lê; a lista vem da porta certa, na ordem do banco', async () => {
  const { r, corpo, chamadas } = await chamar({ caminho: '/admin/summit_2026_sessions' });
  assert.equal(r.status, 200);
  assert.deepEqual(chamadas[0], { nome: 'mind_admin_read_summit_2026_sessoes', args: { p_id: null } });
  assert.deepEqual(titulos(corpo), ['Abertura', 'Workshop de liderança', 'Almoço', 'Masterclass']);
  assert.equal(corpo.total, 4);
});

test('é só leitura: escrever é recusado antes de tudo', async () => {
  const { r, chamadas } = await chamar({ metodo: 'PATCH', caminho: `/admin/summit_2026_sessions/${ID}` });
  assert.equal(r.status, 405);
  assert.equal(chamadas.length, 0);
});

test('uma sessão pelo id; id que não é uuid e recurso desconhecido não chegam ao banco', async () => {
  const um = await chamar({ caminho: `/admin/summit_2026_sessions/${ID}`, rpc: { data: [SESSOES[0]], error: null } });
  assert.equal(um.r.status, 200);
  assert.equal(um.corpo.titulo, 'Abertura');
  assert.deepEqual(um.chamadas[0].args, { p_id: ID });
  for (const caminho of ['/admin/summit_2026_sessions/nao-e-uuid', '/admin/outra_tabela']) {
    const ruim = await chamar({ caminho });
    assert.equal(ruim.r.status, 404, caminho);
    assert.equal(ruim.chamadas.length, 0, caminho);
  }
});

test('busca em título, descrição, espaço e palestrantes, sem acento', async () => {
  assert.deepEqual(titulos((await chamar({ caminho: '/admin/summit_2026_sessions?busca=agora' })).corpo),
    ['Workshop de liderança', 'Masterclass']);
  assert.deepEqual(titulos((await chamar({ caminho: '/admin/summit_2026_sessions?busca=carla' })).corpo),
    ['Masterclass']);
  assert.deepEqual(titulos((await chamar({ caminho: '/admin/summit_2026_sessions?busca=pratica' })).corpo),
    ['Workshop de liderança']);
});

test('filtra por dia, tipo, reserva e sessão sem espaço', async () => {
  assert.deepEqual(titulos((await chamar({ caminho: '/admin/summit_2026_sessions?dia=2026-09-17' })).corpo),
    ['Almoço', 'Masterclass']);
  assert.deepEqual(titulos((await chamar({ caminho: '/admin/summit_2026_sessions?precisa_reserva=true' })).corpo),
    ['Workshop de liderança', 'Masterclass']);
  assert.deepEqual(titulos((await chamar({ caminho: '/admin/summit_2026_sessions?espaco_id=null' })).corpo),
    ['Almoço']);
});

test('ordena número como número e vazio no fim, na lista inteira antes de paginar', async () => {
  /* 9 antes de 10: como texto, "10" viria antes de "9". */
  assert.deepEqual(titulos((await chamar({ caminho: '/admin/summit_2026_sessions?ordenar=vagas_disponiveis' })).corpo),
    ['Workshop de liderança', 'Masterclass', 'Abertura', 'Almoço']);
  assert.deepEqual(titulos((await chamar({ caminho: '/admin/summit_2026_sessions?ordenar=-espaco' })).corpo),
    ['Workshop de liderança', 'Masterclass', 'Abertura', 'Almoço']);
  const pagina2 = (await chamar({ caminho: '/admin/summit_2026_sessions?ordenar=titulo&porPagina=2&pagina=2' })).corpo;
  assert.deepEqual(titulos(pagina2), ['Masterclass', 'Workshop de liderança']);
  assert.equal(pagina2.total, 4);
});

test('erro do banco não vaza detalhe', async () => {
  const { r, corpo } = await chamar({
    caminho: '/admin/summit_2026_sessions',
    rpc: { data: null, error: { message: 'relation "x" does not exist', code: '42P01' } },
  });
  assert.equal(r.status, 503);
  assert.doesNotMatch(JSON.stringify(corpo), /relation/);
});
