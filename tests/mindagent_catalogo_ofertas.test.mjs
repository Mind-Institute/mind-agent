/* ============================================================
   mindagent-catalogo — ofertas e cupons, rodando
   ============================================================
   Carrega o handler REAL de `supabase/functions/mindagent-catalogo/index.ts`
   no Node, com `Deno` e o cliente Supabase stubados (o mesmo stub dos
   outros testes da função). O fonte não é reescrito além do especificador
   `npm:`.

   Pedido da Adriana (26/09/2026): preço, oferta, order bump e cupom moram
   no schema `catalogo`, e o painel é o controle dele. Desde a `1.3.0` a
   função serve `offers` e `coupons` — por enquanto só leitura; a edição é
   o Passo 4 de docs/PLANO_OFERTAS_PASSO_A_PASSO.md. */

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
  const arquivo = join(mkdtempSync(join(tmpdir(), 'catalogo-ofertas-')), 'index.mts');
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

/* Ofertas como a `mind_admin_read_ofertas` devolve, só com o que importa aqui. Inventadas. */
const OFERTAS = [
  { id: '11111111-1111-4111-8111-111111111111', codigo: 'balcao-a', nome: 'Formação A', tipo: 'base',
    situacao: 'no_ar', situacaoOrdem: 1, historico: false, noSite: true, verticais: ['institute'],
    produtos: ['formacao-a'], iniciaEm: null,
    precos: [{ codigo: 'formacao-a-balcao', nome: null, produtoCodigo: 'formacao-a', produtoNome: 'Formação A' }] },
  { id: '22222222-2222-4222-8222-222222222222', codigo: 'lote-1', nome: 'Evento — Lote 1', tipo: 'periodo',
    situacao: 'historico', situacaoOrdem: 6, historico: true, noSite: false, verticais: ['summit'],
    produtos: ['evento-mind', 'evento-vip'], iniciaEm: '2026-06-01T03:00:00+00:00',
    precos: [
      { codigo: 'mind-lote-1-2026', nome: 'Experiência Mind — Lote 1', produtoCodigo: 'evento-mind', produtoNome: 'Evento — Mind' },
      { codigo: 'vip-lote-1-2026', nome: 'Experiência VIP — Lote 1', produtoCodigo: 'evento-vip', produtoNome: 'Evento — VIP' },
    ] },
  { id: '33333333-3333-4333-8333-333333333333', codigo: 'upgrade-x', nome: 'Upgrade Mind para VIP', tipo: 'condicional',
    situacao: 'historico', situacaoOrdem: 6, historico: true, noSite: false, verticais: ['summit'],
    produtos: ['evento-vip'], iniciaEm: null, precos: [] },
];

const CUPONS = [
  { id: '44444444-4444-4444-8444-444444444444', codigo: 'CUPOM-A', descricao: 'Cupom de exemplo', tipo: 'valor',
    valor: 100, usos: 0, situacao: 'valendo', situacaoOrdem: 1, sistema: 'checkout_proprio', historico: false, ativo: true },
  { id: '55555555-5555-4555-8555-555555555555', codigo: 'CUPOM-B', descricao: 'Antigo', tipo: 'percentual',
    valor: 10, usos: 3, situacao: 'historico', situacaoOrdem: 6, sistema: 'eduzz', historico: true, ativo: false },
];

let portasChamadas = [];

function cenario(papel = 'analista') {
  portasChamadas = [];
  globalThis.__MIND_EDGE_TESTE__ = {
    getUser: async () => ({ data: { user: { id: 'ator' } }, error: null }),
    from: () => ({ select: () => ({ eq: () => ({
      maybeSingle: async () => ({ data: { display_name: 'Ana', role: papel, active: true }, error: null }),
    }) }) }),
    rpc: async (nome, args) => {
      portasChamadas.push({ nome, args });
      if (nome === 'mind_admin_read_ofertas') {
        const lista = structuredClone(OFERTAS);
        return { data: args.p_id ? lista.filter((o) => o.id === args.p_id) : lista, error: null };
      }
      if (nome === 'mind_admin_read_cupons') {
        const lista = structuredClone(CUPONS);
        return { data: args.p_id ? lista.filter((c) => c.id === args.p_id) : lista, error: null };
      }
      throw new Error(`porta inesperada: ${nome}`);
    },
  };
}

async function pedir(caminho, init = {}) {
  const h = await carregar();
  return h(new Request(`${BASE}${caminho}`, {
    ...init,
    headers: { Origin: ORIGEM, Authorization: 'Bearer token', ...(init.headers ?? {}) },
  }));
}

const codigos = (corpo) => corpo.itens.map((i) => i.codigo);

test('ofertas: a lista vem da porta de ofertas, na ordem do banco', async () => {
  cenario();
  const r = await pedir('/admin/offers');
  assert.equal(r.status, 200);
  const corpo = await r.json();
  assert.deepEqual(codigos(corpo), ['balcao-a', 'lote-1', 'upgrade-x']);
  assert.equal(corpo.total, 3);
  assert.deepEqual(portasChamadas.map((c) => c.nome), ['mind_admin_read_ofertas']);
  assert.equal(portasChamadas[0].args.p_id, null);
});

test('ofertas: filtro de lista combina quando a oferta contém o valor', async () => {
  cenario();
  assert.deepEqual(codigos(await (await pedir('/admin/offers?verticais=summit')).json()), ['lote-1', 'upgrade-x']);
  assert.deepEqual(codigos(await (await pedir('/admin/offers?produtos=evento-mind')).json()), ['lote-1']);
  assert.deepEqual(codigos(await (await pedir('/admin/offers?situacao=no_ar')).json()), ['balcao-a']);
  assert.deepEqual(codigos(await (await pedir('/admin/offers?tipo=condicional')).json()), ['upgrade-x']);
  assert.deepEqual(codigos(await (await pedir('/admin/offers?noSite=true')).json()), ['balcao-a']);
});

test('ofertas: a busca olha o código vendável e o nome de cada preço', async () => {
  cenario();
  assert.deepEqual(codigos(await (await pedir('/admin/offers?busca=vip-lote-1')).json()), ['lote-1']);
  assert.deepEqual(codigos(await (await pedir('/admin/offers?busca=experiencia%20mind')).json()), ['lote-1']);
});

test('ofertas: a situação ordena como número, e o vazio vai para o fim', async () => {
  cenario();
  assert.deepEqual(codigos(await (await pedir('/admin/offers?ordenar=-situacaoOrdem')).json())[2], 'balcao-a');
  assert.deepEqual(codigos(await (await pedir('/admin/offers?ordenar=iniciaEm')).json()), ['lote-1', 'balcao-a', 'upgrade-x']);
});

test('ofertas: uma oferta, e id que não é UUID não chega ao banco', async () => {
  cenario();
  const r = await pedir(`/admin/offers/${OFERTAS[1].id}`);
  assert.equal(r.status, 200);
  assert.equal((await r.json()).codigo, 'lote-1');
  assert.equal(portasChamadas[0].args.p_id, OFERTAS[1].id);

  cenario();
  const nao = await pedir('/admin/offers/lote-1');
  assert.equal(nao.status, 404);
  assert.equal((await nao.json()).mensagem, 'Oferta não encontrada.');
  assert.equal(portasChamadas.length, 0);
});

test('ofertas e cupons: escrever é recusado, só leitura por enquanto', async () => {
  for (const [metodo, caminho] of [
    ['PATCH', `/admin/offers/${OFERTAS[0].id}`],
    ['POST', '/admin/offers'],
    ['PATCH', `/admin/coupons/${CUPONS[0].id}`],
  ]) {
    cenario('administrador');
    const r = await pedir(caminho, {
      method: metodo,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ nome: 'x' }),
    });
    assert.equal(r.status, 405, `${metodo} ${caminho}`);
    assert.match((await r.json()).mensagem, /só leitura/);
    assert.equal(portasChamadas.length, 0);
  }
});

test('cupons: a lista vem da porta de cupons, com filtro e ordem', async () => {
  cenario();
  const corpo = await (await pedir('/admin/coupons?ordenar=-usos')).json();
  assert.deepEqual(codigos(corpo), ['CUPOM-B', 'CUPOM-A']);
  assert.deepEqual(portasChamadas.map((c) => c.nome), ['mind_admin_read_cupons']);
  cenario();
  assert.deepEqual(codigos(await (await pedir('/admin/coupons?situacao=valendo')).json()), ['CUPOM-A']);
  cenario();
  assert.deepEqual(codigos(await (await pedir('/admin/coupons?sistema=eduzz')).json()), ['CUPOM-B']);
});

test('recurso que não existe é rota não encontrada', async () => {
  for (const caminho of ['/admin/precos', '/admin/constructor', '/admin/__proto__', '/admin/toString']) {
    cenario();
    const r = await pedir(caminho);
    assert.equal(r.status, 404, caminho);
    assert.equal(portasChamadas.length, 0, caminho);
  }
});

test('health diz a versão 1.3.0', async () => {
  const r = await pedir('/health');
  assert.equal(r.status, 200);
  assert.equal((await r.json()).version, '1.3.0');
});
