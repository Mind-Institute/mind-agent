/* ============================================================
   O DOMÍNIO DO PAINEL — `admin.minddash.pro`
   ============================================================
   Pedido da Adriana (26/09/2026): o painel abre em admin.minddash.pro,
   que aponta para o mesmo Worker do app. A promessa é dupla: ali só existe
   o painel, e o app público nunca roda naquela origem. Promessa negativa
   apodrece calada — daí o teste.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte } from './helpers/ler-fonte.mjs';
import {
  HOST_ANTIGO_DO_PAINEL, HOST_DO_PAINEL, HOST_DA_PESQUISA,
  decidirNoHostDoPainel, destinoDoPainelAntigo, ehDaPesquisa, ehDoHostDoPainel,
} from '../cloudflare/roteamento.js';

const worker = lerFonte(new URL('../cloudflare/worker.ts', import.meta.url));

test('reconhece o domínio do painel, e só ele', () => {
  assert.equal(ehDoHostDoPainel(HOST_DO_PAINEL), true);
  assert.equal(ehDoHostDoPainel(HOST_DO_PAINEL.toUpperCase()), true);
  for (const outro of [HOST_ANTIGO_DO_PAINEL, 'minddash.pro', 'admin.minddash.pro.evil.com',
                       'x-admin.minddash.pro', HOST_DA_PESQUISA, 'localhost', '', null]) {
    assert.equal(ehDoHostDoPainel(outro), false, `${outro} não é o domínio do painel`);
  }
  /* Os dois domínios dedicados não se confundem. */
  assert.equal(ehDaPesquisa(HOST_DO_PAINEL), false);
});

test('a raiz e a navegação fora do painel levam para /admin/', () => {
  for (const p of ['/', '/programacao', '/qualquer/coisa', '/c/00000000-0000-0000-0000-000000000000']) {
    assert.deepEqual(decidirNoHostDoPainel(p), { tipo: 'redirecionar', para: '/admin/' }, p);
  }
});

test('o painel inteiro é servido: índice, rotas e arquivos de build', () => {
  for (const p of ['/admin', '/admin/', '/admin/catalogo', '/admin/assets/index-abc123.js', '/admin/index.html']) {
    assert.equal(decidirNoHostDoPainel(p).tipo, 'painel', `${p} é do painel`);
  }
});

test('NÃO entrega o app público nem a pesquisa', () => {
  for (const p of ['/app.js', '/index.html', '/config.js', '/chat-service.js', '/styles.css',
                   '/avaliacao.html', '/assets/favicon.svg', '/home/home.js']) {
    assert.equal(decidirNoHostDoPainel(p).tipo, 'recusado', `${p} NÃO pode ser servido aqui`);
  }
});

test('o endereço antigo leva o painel para o domínio novo; o chat fica', () => {
  assert.equal(destinoDoPainelAntigo(HOST_ANTIGO_DO_PAINEL, '/admin/catalogo'),
    'https://admin.minddash.pro/admin/catalogo');
  assert.equal(destinoDoPainelAntigo(HOST_ANTIGO_DO_PAINEL, '/admin'), 'https://admin.minddash.pro/admin');
  assert.equal(destinoDoPainelAntigo(HOST_ANTIGO_DO_PAINEL, '/'), null);
  assert.equal(destinoDoPainelAntigo(HOST_ANTIGO_DO_PAINEL, '/app.js'), null);
  /* Preview de branch continua servindo o painel no próprio endereço. */
  assert.equal(destinoDoPainelAntigo('claude-x-mind-agent.adriana-3eb.workers.dev', '/admin/'), null);
  assert.equal(destinoDoPainelAntigo(HOST_DO_PAINEL, '/admin/'), null);
});

test('no Worker, o domínio do painel é decidido antes do checkout e dos assets', () => {
  const iPainel = worker.indexOf('ehDoHostDoPainel(url.hostname)');
  assert.ok(iPainel > 0);
  assert.ok(iPainel > worker.indexOf('ehDaPesquisa(url.hostname)'), 'a pesquisa continua primeiro');
  assert.ok(iPainel < worker.indexOf('mindagent-checkout'));
  assert.ok(iPainel < worker.indexOf('decidirAntes(request.method'));
  assert.match(worker, /destinoDoPainelAntigo\(url\.hostname, url\.pathname\)/);
});
