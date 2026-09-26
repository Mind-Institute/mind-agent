/* ============================================================
   mindagent-catalogo — a ordem das colunas, rodando
   ============================================================
   Carrega o handler REAL de `supabase/functions/mindagent-catalogo/index.ts`
   no Node, com `Deno` e o cliente Supabase stubados (o mesmo stub da
   `mindagent-acesso`). O fonte não é reescrito além do especificador `npm:`.

   Pedido da Adriana (26/09/2026): ordenar os produtos por qualquer coluna
   da tela, crescente e decrescente. A lista inteira é ordenada ANTES de
   paginar — ordenar só a página que a tela vê daria uma ordem falsa. */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const FONTE = new URL('../supabase/functions/mindagent-catalogo/index.ts', import.meta.url);
const STUB = new URL('./helpers/supabase-stub.mjs', import.meta.url);
const IMPORT_VIVO = '"npm:@supabase/supabase-js@2.112.3"';
const BASE = 'https://projeto.supabase.co/functions/v1/mindagent-catalogo';
const ORIGEM = 'https://admin.minddash.pro';

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
  const arquivo = join(mkdtempSync(join(tmpdir(), 'catalogo-')), 'index.mts');
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

/* Produtos como a `mind_admin_read_catalogo` devolve, só com o que importa
   para a ordem. A ordem do banco é a desta lista. */
const PRODUTOS = [
  { codigo: 'mind', nome: 'Mind', vertical: null, tipo: 'empresa', ativo: true, vende: false,
    vendeAte: null, comecaEm: null },
  { codigo: 'mind-summit-2026', nome: 'Mind Summit 2026', vertical: 'summit', tipo: 'evento', ativo: true,
    vende: false, vendeAte: '2026-09-18T02:59:59+00:00', comecaEm: '2026-09-16' },
  { codigo: 'oxford', nome: 'Oxford no Conselho', vertical: 'eventos', tipo: 'evento', ativo: false,
    vende: false, vendeAte: '2025-10-29T15:09:03+00:00', comecaEm: '2025-10-29' },
  { codigo: 'lideranca', nome: 'Liderança Consciente', vertical: 'institute', tipo: 'formacao', ativo: true,
    vende: true, vendeAte: null, comecaEm: '2027-01-28' },
  { codigo: 'engajamento', nome: 'Engajamento e Significado no Trabalho', vertical: 'institute',
    tipo: 'formacao', ativo: true, vende: true, vendeAte: null, comecaEm: '2027-01-28' },
];

async function listar(query) {
  return listarCom(PRODUTOS, query);
}

async function listarCom(produtos, query) {
  globalThis.__MIND_EDGE_TESTE__ = {
    getUser: async () => ({ data: { user: { id: 'ator' } }, error: null }),
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({ data: { display_name: 'Ana', role: 'analista', active: true }, error: null }),
        }),
      }),
    }),
    rpc: async (nome) => {
      assert.equal(nome, 'mind_admin_read_catalogo');
      return { data: structuredClone(produtos), error: null };
    },
  };
  const h = await carregar();
  const r = await h(new Request(`${BASE}/admin/products${query}`, {
    headers: { Origin: ORIGEM, Authorization: 'Bearer token' },
  }));
  assert.equal(r.status, 200);
  return (await r.json());
}

const codigos = (corpo) => corpo.itens.map((i) => i.codigo);

test('sem pedido, fica a ordem do banco', async () => {
  assert.deepEqual(codigos(await listar('')), PRODUTOS.map((p) => p.codigo));
});

test('pelo nome, no alfabeto do português, e ao contrário', async () => {
  assert.deepEqual(codigos(await listar('?ordenar=nome')),
    ['engajamento', 'lideranca', 'mind', 'mind-summit-2026', 'oxford']);
  assert.deepEqual(codigos(await listar('?ordenar=-nome')),
    ['oxford', 'mind-summit-2026', 'mind', 'lideranca', 'engajamento']);
});

test('situação e venda: não antes de sim, e ao contrário', async () => {
  assert.deepEqual(codigos(await listar('?ordenar=ativo'))[0], 'oxford');
  assert.deepEqual(codigos(await listar('?ordenar=-vende')).slice(0, 2), ['lideranca', 'engajamento']);
});

test('data vazia vai para o fim nos dois sentidos', async () => {
  assert.deepEqual(codigos(await listar('?ordenar=comecaEm')),
    ['oxford', 'mind-summit-2026', 'lideranca', 'engajamento', 'mind']);
  assert.deepEqual(codigos(await listar('?ordenar=-comecaEm')),
    ['lideranca', 'engajamento', 'mind-summit-2026', 'oxford', 'mind']);
  assert.deepEqual(codigos(await listar('?ordenar=-vendeAte')).slice(-3).sort(), ['engajamento', 'lideranca', 'mind']);
  assert.deepEqual(codigos(await listar('?ordenar=vendeAte')).slice(0, 2), ['oxford', 'mind-summit-2026']);
});

test('instante com fusos diferentes ordena pelo instante, não pelo texto', async () => {
  const corpo = await listarCom([
    { codigo: 'a', nome: 'A', vendeAte: '2026-09-17T23:30:00-03:00' },
    { codigo: 'b', nome: 'B', vendeAte: '2026-09-18T01:00:00+00:00' },
  ], '?ordenar=vendeAte');
  /* 23:30 em Brasília é 02:30 UTC do dia 18 — depois da 01:00 UTC. */
  assert.deepEqual(codigos(corpo), ['b', 'a']);
});

test('ordena a lista inteira antes de paginar', async () => {
  const pagina2 = await listar('?ordenar=nome&porPagina=2&pagina=2');
  assert.deepEqual(codigos(pagina2), ['mind', 'mind-summit-2026']);
  assert.equal(pagina2.total, 5);
});

test('campo que não é coluna da tela não muda a ordem', async () => {
  assert.deepEqual(codigos(await listar('?ordenar=schemaDados')), PRODUTOS.map((p) => p.codigo));
});

test('a recusa das datas da turma chega na frase certa', async () => {
  globalThis.__MIND_EDGE_TESTE__ = {
    getUser: async () => ({ data: { user: { id: 'ator' } }, error: null }),
    from: () => ({ select: () => ({ eq: () => ({
      maybeSingle: async () => ({ data: { display_name: 'Ana', role: 'editor', active: true }, error: null }),
    }) }) }),
    rpc: async () => ({ data: null, error: { message: 'admin_validation:datas_da_turma', code: '22023' } }),
  };
  const h = await carregar();
  const r = await h(new Request(`${BASE}/admin/products/6f1c2d3e-4b5a-4c6d-8e9f-0a1b2c3d4e5f`, {
    method: 'PATCH',
    headers: { Origin: ORIGEM, Authorization: 'Bearer token', 'Content-Type': 'application/json',
               'If-Unmodified-Since-Version': '2026-09-26T00:00:00+00:00' },
    body: JSON.stringify({ comecaEm: '2030-01-01' }),
  }));
  assert.equal(r.status, 422);
  assert.match((await r.json()).mensagem, /datas vêm da turma/);
});
