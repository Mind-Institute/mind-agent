/* ============================================================
   O DOMÍNIO DA PESQUISA — desligado
   ============================================================
   `avaliacao.mindsummit.com.br` servia uma pesquisa avulsa, apagada a
   pedido da Adriana (24/09/2026). Enquanto o domínio apontar para o
   mesmo Worker do app, nada pode ser servido nele: sem a trava, a raiz
   entregaria o app inteiro, inclusive /admin/.

   E a segunda garantia continua: o Worker atende TODOS os caminhos para
   poder olhar o Host, então o fallback de SPA precisa estar restrito ao
   painel no código.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { lerFonte } from './helpers/ler-fonte.mjs';
import {
  HOST_DA_PESQUISA, decidirApos404, ehDaPesquisa, ehDoPainel,
} from '../cloudflare/roteamento.js';

const worker = lerFonte(new URL('../cloudflare/worker.ts', import.meta.url));
const wrangler = lerFonte(new URL('../wrangler.jsonc', import.meta.url));
const build = lerFonte(new URL('../scripts/build-cloudflare.mjs', import.meta.url));

test('reconhece o domínio da pesquisa, e só ele', () => {
  assert.equal(ehDaPesquisa(HOST_DA_PESQUISA), true);
  assert.equal(ehDaPesquisa(HOST_DA_PESQUISA.toUpperCase()), true);
  for (const outro of ['mind-agent.adriana-3eb.workers.dev', 'mindsummit.com.br',
                       'avaliacao.mindsummit.com.br.evil.com', 'localhost', '', null]) {
    assert.equal(ehDaPesquisa(outro), false, `${outro} não é o domínio da pesquisa`);
  }
});

test('o domínio da pesquisa devolve 404 em tudo, antes de qualquer outra regra', () => {
  const i = worker.indexOf('if (ehDaPesquisa(url.hostname))');
  assert.ok(i > 0);
  const bloco = worker.slice(i, worker.indexOf('}', worker.indexOf('status: 404', i)) + 1);
  assert.match(bloco, /status: 404/);
  assert.ok(!/ASSETS\.fetch/.test(bloco), 'nada daquele domínio chega aos assets');
  /* Antes do checkout, antes do painel, antes de qualquer asset. */
  assert.ok(i < worker.indexOf('mindagent-checkout'));
  assert.ok(i < worker.indexOf('decidirAntes(request.method'));
  assert.ok(i < worker.indexOf('env.ASSETS.fetch(request)'));
});

test('a página avulsa saiu do repositório e do build', () => {
  assert.equal(existsSync(new URL('../avaliacao.html', import.meta.url)), false);
  assert.ok(!/'avaliacao\.html'/.test(build));
});

test('o fallback de SPA continua sendo SÓ do painel', () => {
  assert.equal(decidirApos404('GET', '/qualquer-coisa').tipo, 'indice');
  assert.equal(ehDoPainel('/qualquer-coisa'), false);
  assert.equal(ehDoPainel('/admin/programacao'), true);
  assert.match(worker, /if \(!ehDoPainel\(url\.pathname\)\) return resposta;/);
  const ordem = worker.indexOf('!ehDoPainel(url.pathname)');
  assert.ok(ordem > 0 && ordem < worker.indexOf('decidirApos404(request.method'),
    'a conferência precisa vir antes de decidir pelo índice');
});

test('o Worker atende todos os caminhos, e o wrangler diz por quê', () => {
  assert.match(wrangler, /"run_worker_first": \["\/\*"\]/);
  /* `"/"` junto de `"/*"` faz o wrangler recusar o deploy. */
  assert.ok(!/"run_worker_first": \["\/",/.test(wrangler),
    'a raiz junto do curinga derruba o deploy');
  assert.match(wrangler, /avaliacao\.mindsummit\.com\.br/);
  assert.match(wrangler, /ehDoPainel/);
});
