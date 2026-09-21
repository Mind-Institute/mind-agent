/* ============================================================
   O DOMÍNIO DA PESQUISA — o que ele não pode entregar
   ============================================================
   `avaliacao.mindsummit.com.br` aponta para o mesmo Worker do app. A
   promessa feita ali é negativa: naquele domínio NÃO existe app do
   evento, agente nem painel. Promessa negativa é a que apodrece calada
   — o dia em que alguém acrescentar um arquivo e ele vazar para lá, a
   tela não vai dar erro nenhum.

   E há uma segunda garantia, que esta mudança quase derrubou: o Worker
   passou a atender TODOS os caminhos para poder olhar o Host. Antes,
   quem impedia o fallback de SPA do painel de valer para o site inteiro
   era o recorte do `run_worker_first`. Agora é código — e código se
   testa.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte } from './helpers/ler-fonte.mjs';
import {
  HOST_DA_PESQUISA, PAGINA_DA_PESQUISA,
  decidirApos404, decidirNaPesquisa, ehDaPesquisa, ehDoPainel,
} from '../cloudflare/roteamento.js';

const worker = lerFonte(new URL('../cloudflare/worker.ts', import.meta.url));
const wrangler = lerFonte(new URL('../wrangler.jsonc', import.meta.url));
const pagina = lerFonte(new URL('../avaliacao.html', import.meta.url));
const build = lerFonte(new URL('../scripts/build-cloudflare.mjs', import.meta.url));

/* ============================================================
   QUEM É O DOMÍNIO
   ============================================================ */

test('reconhece o domínio da pesquisa, e só ele', () => {
  assert.equal(ehDaPesquisa(HOST_DA_PESQUISA), true);
  assert.equal(ehDaPesquisa(HOST_DA_PESQUISA.toUpperCase()), true);
  for (const outro of ['mind-agent.adriana-3eb.workers.dev', 'mindsummit.com.br',
                       'avaliacao.mindsummit.com.br.evil.com', 'localhost', '', null]) {
    assert.equal(ehDaPesquisa(outro), false, `${outro} não é o domínio da pesquisa`);
  }
});

/* ============================================================
   O QUE ELE ENTREGA
   ============================================================ */

test('a raiz entrega a pesquisa', () => {
  assert.equal(decidirNaPesquisa('/').tipo, 'pesquisa');
  assert.equal(decidirNaPesquisa(PAGINA_DA_PESQUISA).tipo, 'pesquisa');
});

test('entrega os arquivos de que a pesquisa precisa, e só eles', () => {
  for (const p of ['/config.js', '/chat-service.js', '/teclado.js', '/styles.css',
                   '/avaliacao/evento.js', '/avaliacao/servico.js',
                   '/avaliacao/componentes.js', '/avaliacao/avaliacao.css',
                   '/assets/favicon.svg', '/assets/simbolo-mind-verde.png']) {
    assert.equal(decidirNaPesquisa(p).tipo, 'asset', `${p} devia ser servido`);
  }
});

test('NÃO entrega o app do evento nem o agente', () => {
  for (const p of ['/app.js', '/index.html', '/data-service.js',
                   '/home/home.js', '/home/estado.js', '/home/cards.js',
                   '/classic.html', '/app-classic.js']) {
    assert.equal(decidirNaPesquisa(p).tipo, 'recusado', `${p} NÃO pode ser servido aqui`);
  }
});

test('NÃO entrega o painel — nem o índice, nem os arquivos dele', () => {
  assert.equal(decidirNaPesquisa('/admin/index.html').tipo, 'recusado');
  assert.equal(decidirNaPesquisa('/admin/assets/index-abc123.js').tipo, 'recusado');
  /* `/admin/` e `/admin/programacao` não têm ponto, então caem na regra
     de navegação: viram a pesquisa, e não o painel. O que importa é que
     em nenhum caso o painel apareça. */
  for (const p of ['/admin', '/admin/', '/admin/programacao']) {
    assert.notEqual(decidirNaPesquisa(p).tipo, 'asset', `${p} não pode servir o painel`);
  }
});

test('navegação desconhecida volta para a pesquisa; arquivo, não', () => {
  /* Um link com barra a mais, ou alguém que apaga o fim da URL, continua
     chegando onde devia. */
  assert.equal(decidirNaPesquisa('/avaliacao').tipo, 'pesquisa');
  assert.equal(decidirNaPesquisa('/qualquer/coisa').tipo, 'pesquisa');
  /* Já um arquivo que não existe precisa ser 404: devolver HTML faria o
     navegador tentar executar `<!doctype`, e o erro no console não teria
     relação com a causa. */
  assert.equal(decidirNaPesquisa('/nao-existe.js').tipo, 'recusado');
  assert.equal(decidirNaPesquisa('/nao-existe.css').tipo, 'recusado');
});

/* ============================================================
   O QUE A MUDANÇA QUASE DERRUBOU
   ============================================================ */

test('o fallback de SPA continua sendo SÓ do painel', () => {
  /* A regra pura continua respondendo `indice` para navegação — ela não
     sabe de host nem de prefixo. Quem restringe é o Worker. */
  assert.equal(decidirApos404('GET', '/qualquer-coisa').tipo, 'indice');
  assert.equal(ehDoPainel('/qualquer-coisa'), false);
  assert.equal(ehDoPainel('/admin/programacao'), true);

  /* E o Worker confere isso ANTES de aplicar o fallback. Sem esta linha,
     `/qualquer-coisa` no chat devolveria o painel em vez de 404. */
  assert.match(worker, /if \(!ehDoPainel\(url\.pathname\)\) return resposta;/);
  const ordem = worker.indexOf('!ehDoPainel(url.pathname)');
  assert.ok(ordem > 0 && ordem < worker.indexOf('decidirApos404(request.method'),
    'a conferência precisa vir antes de decidir pelo índice');
});

test('o Worker atende todos os caminhos, e o wrangler diz por quê', () => {
  assert.match(wrangler, /"run_worker_first": \["\/\*"\]/);
  /* `"/"` JUNTO DE `"/*"` FAZ O WRANGLER RECUSAR O DEPLOY — "rule '/*'
     makes it redundant". E ele recusa lá, no build da Cloudflare, não
     aqui: ficou cinco minutos falhando em silêncio até eu rodar o
     `--dry-run`. Por isso a asserção é negativa também. */
  assert.ok(!/"run_worker_first": \["\/",/.test(wrangler),
    'a raiz junto do curinga derruba o deploy');
  assert.match(wrangler, /avaliacao\.mindsummit\.com\.br/);
  assert.match(wrangler, /ehDoPainel/);
});

test('o domínio da pesquisa é decidido antes de tudo no Worker', () => {
  const iPesquisa = worker.indexOf('ehDaPesquisa(url.hostname)');
  assert.ok(iPesquisa > 0);
  /* Antes do checkout, antes do painel, antes de qualquer asset: se
     viesse depois, `/admin/` naquele domínio já teria sido servido. */
  assert.ok(iPesquisa < worker.indexOf('mindagent-checkout'));
  assert.ok(iPesquisa < worker.indexOf('decidirAntes(request.method'));
});

test('a URL do navegador não muda ao servir a pesquisa', () => {
  /* Redirecionar mostraria um `/avaliacao.html` que a pessoa não pediu.
     O Worker busca a página e devolve o conteúdo. */
  const bloco = worker.slice(worker.indexOf("decisao.tipo === 'pesquisa'"),
    worker.indexOf("return env.ASSETS.fetch(request);"));
  assert.match(bloco, /env\.ASSETS\.fetch\(new Request\(pagina, request\)\)/);
  assert.ok(!/Response\.redirect/.test(bloco), 'não redireciona');
});

/* ============================================================
   A PÁGINA
   ============================================================ */

test('a página não carrega o app do evento nem o agente', () => {
  for (const proibido of ['app.js', 'data-service.js', 'home/', 'chat', 'splash']) {
    assert.ok(!new RegExp('src="[^"]*' + proibido).test(pagina),
      `a página não pode carregar ${proibido}`);
  }
  /* O que ela carrega é o mínimo: a tela, a sessão, o teclado. */
  assert.match(pagina, /from '\.\/avaliacao\/evento\.js'/);
  assert.match(pagina, /from '\.\/teclado\.js'/);
});

test('a página não oferece voltar — não há home atrás dela', () => {
  assert.ok(!/c-voltar/.test(pagina));
  assert.match(pagina, /abrirAvaliacaoDoEvento\(\s*corpo,\s*null,/);
});

test('a casca que o CSS exige está lá', () => {
  /* `.vista` é `display: none` sem `.ativa`: sem isso a página abre em
     branco, e nada no console explica por quê. */
  assert.match(pagina, /class="vista ativa"/);
  assert.match(pagina, /id="avaliacao-corpo"/);
  assert.match(pagina, /avaliacao\/avaliacao\.css/);
});

test('a página entra no build', () => {
  assert.match(build, /'avaliacao\.html'/);
});

test('o Worker segue o redirecionamento do pipeline de assets', () => {
  /* `avaliacao.html` é servido em `/avaliacao`, e o caminho com extensão
     recebe 307 (`html_handling`). Repassar esse 307 mandava o navegador
     para `/avaliacao`, que voltava por aqui e recebia outro 307 — laço,
     e a página nunca aparecia. Aconteceu no primeiro deploy. */
  const bloco = worker.slice(worker.indexOf("decisao.tipo === 'pesquisa'"),
    worker.indexOf("return env.ASSETS.fetch(request);"));
  assert.match(bloco, /resposta\.status >= 300 && resposta\.status < 400/);
  assert.match(bloco, /headers\.get\('Location'\)/);
  /* E o destino é forçado para a nossa origem: seguir cegamente o que
     vier no cabeçalho seria deixar outro escolher para onde vamos. */
  assert.match(bloco, /seguinte\.host = url\.host;/);
});
