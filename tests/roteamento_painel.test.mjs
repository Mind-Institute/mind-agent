/* ============================================================
   O DOMÍNIO DO PAINEL — `admin.minddash.pro`
   ============================================================
   Pedido da Adriana (26/09/2026): o painel abre em admin.minddash.pro,
   que aponta para o mesmo Worker do app, e app e painel são duas coisas em
   dois endereços. A promessa é dupla: ali só existe o painel, e em nenhum
   outro endereço de produção o painel roda. Promessa negativa apodrece
   calada — daí o teste.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte } from './helpers/ler-fonte.mjs';
import {
  HOST_DO_WORKER, HOST_DO_PAINEL, HOST_DA_PESQUISA,
  decidirNoHostDoPainel, destinoDoPainelForaDoDominio, ehDaPesquisa, ehDoHostDoPainel,
  ehEnderecoDeTeste,
} from '../cloudflare/roteamento.js';

const worker = lerFonte(new URL('../cloudflare/worker.ts', import.meta.url));

test('reconhece o domínio do painel, e só ele', () => {
  assert.equal(ehDoHostDoPainel(HOST_DO_PAINEL), true);
  assert.equal(ehDoHostDoPainel(HOST_DO_PAINEL.toUpperCase()), true);
  for (const outro of [HOST_DO_WORKER, 'minddash.pro', 'admin.minddash.pro.evil.com',
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

test('em qualquer outro endereço, o painel leva para o domínio dele; o app fica', () => {
  /* O workers.dev, um domínio do app, um domínio ligado amanhã: nenhum
     precisa estar listado para o painel sair dele. */
  for (const host of [HOST_DO_WORKER, 'app.exemplo.com.br', 'mindagent.mindsummit.com.br', 'MIND-AGENT.adriana-3eb.workers.dev']) {
    assert.equal(destinoDoPainelForaDoDominio(host, '/admin/catalogo'),
      'https://admin.minddash.pro/admin/catalogo', host);
    assert.equal(destinoDoPainelForaDoDominio(host, '/admin'), 'https://admin.minddash.pro/admin', host);
    for (const doApp of ['/', '/app.js', '/programacao', '/administrador', '/c/00000000-0000-0000-0000-000000000000']) {
      assert.equal(destinoDoPainelForaDoDominio(host, doApp), null, `${host}${doApp} é do app`);
    }
  }
  assert.equal(destinoDoPainelForaDoDominio(HOST_DO_PAINEL, '/admin/'), null);
});

test('só os endereços de teste seguem com o painel no próprio endereço', () => {
  for (const host of ['claude-x-mind-agent.adriana-3eb.workers.dev', '11967bf4-mind-agent.adriana-3eb.workers.dev',
                      'localhost', '127.0.0.1']) {
    assert.equal(ehEnderecoDeTeste(host), true, `${host} é de teste`);
    assert.equal(destinoDoPainelForaDoDominio(host, '/admin/'), null, host);
  }
  for (const host of [HOST_DO_WORKER, HOST_DO_PAINEL, '-mind-agent.adriana-3eb.workers.dev',
                      'xmind-agent.adriana-3eb.workers.dev', 'claude-x-mind-agent.adriana-3eb.workers.dev.exemplo.com',
                      'app.exemplo.com.br', '', null]) {
    assert.equal(ehEnderecoDeTeste(host), false, `${host} NÃO é de teste`);
  }
});

test('no Worker, o domínio do painel é decidido antes do checkout e dos assets', () => {
  const iPainel = worker.indexOf('ehDoHostDoPainel(url.hostname)');
  assert.ok(iPainel > 0);
  assert.ok(iPainel > worker.indexOf('ehDaPesquisa(url.hostname)'), 'a pesquisa continua primeiro');
  assert.ok(iPainel < worker.indexOf('mindagent-checkout'));
  assert.ok(iPainel < worker.indexOf('decidirAntes(request.method'));
  assert.match(worker, /destinoDoPainelForaDoDominio\(url\.hostname, url\.pathname\)/);
});
