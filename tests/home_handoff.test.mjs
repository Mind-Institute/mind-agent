/* ============================================================
   O QUE O HANDOFF DE 02/09 DECIDIU, E QUE SOME SEM AVISAR
   ============================================================
   Este arquivo não abre navegador. Ele trava, nos bytes vivos, as
   decisões da home "antes" e da tela de avisos que um diff de uma linha
   desfaz sem parecer errado — e cujo estrago só aparece num celular.

   A prova de aparência foi feita em navegador, sobre o build, comparando
   com o protótipo do handoff em 393x852, 375x667 e 360x740. O que roda
   sempre é isto aqui.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const css = readFileSync(new URL('../styles.css', import.meta.url), 'utf8');
const estado = readFileSync(new URL('../home/estado.js', import.meta.url), 'utf8');
const cards = readFileSync(new URL('../home/cards.js', import.meta.url), 'utf8');
const avisos = readFileSync(new URL('../home/avisos.js', import.meta.url), 'utf8');
const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');

test('os quatro atalhos levam a destinos que existem', () => {
  /* Um atalho é uma promessa: "toque e você chega em Meu ingresso". Se o
     destino não existir, `acaoDaHome` cai no `irParaConversa(null)` do
     fim e a pessoa vai parar no chat — sem erro nenhum na tela, que é o
     que torna isto invisível em revisão. */
  const bloco = estado.slice(estado.indexOf("tipo: 'atalhos'"), estado.indexOf("tipo: 'secao', titulo: 'Avisos"));
  const destinos = [...bloco.matchAll(/acao: '([^']+)'/g)].map((m) => m[1]);
  assert.deepEqual(destinos, ['tour:qrcode', 'tour:minha-agenda', 'tour', 'roteiro:mapa'],
    'os destinos dos Atalhos mudaram');

  /* `roteiro:` faz o CAMINHO, `tour:` mostra a tela. O mapa mora dentro do
     Menu: abrir a tela pronta mostraria o mapa e esconderia o caminho, que
     é justamente o que precisa ser ensinado. */
  assert.match(app, /if \(acao\.startsWith\('roteiro:'\)\) return abrirTourCompleto/,
    'a ação de roteiro guiado deixou de ser tratada');
  assert.match(app, /mapa: \{\s*\n\s*de: 'menu',/,
    'o roteiro do mapa deixou de começar no Menu e voltou a pular para a tela');

  /* `tour` e `tour:` são tratados; e cada tela citada precisa existir em
     TELAS, senão `abrirTutorialEm` abre o tour vazio. */
  assert.match(app, /if \(acao === 'tour'\) return abrirTourCompleto\(\)/,
    'o destino do atalho de reservas deixou de ser tratado');
  assert.match(app, /if \(acao\.startsWith\('tour:'\)\) return abrirTutorialEm/,
    'os destinos com tela deixaram de ser tratados');
  for (const tela of ['qrcode', 'minha-agenda', 'mapa']) {
    assert.ok(app.includes("'" + tela + "': {"),
      'a tela ' + tela + ' saiu do tour, e o atalho que aponta para ela virou promessa vazia');
  }
});

test('nenhum bloco da home encolhe para caber', () => {
  /* Numa coluna flex que transborda, `flex-shrink` vale 1 e o navegador
     espreme os filhos em vez de rolar. Foi assim que a descrição do aviso
     saiu 4,8px por baixo da borda do próprio card. */
  assert.match(css, /\.v3-rolagem\s*>\s*\*\s*\{[^}]*flex:\s*none/,
    'a defesa contra o esmagamento dos blocos sumiu: texto de duas linhas '
    + 'volta a vazar para fora do card');
});

test('o modificador do card de marca não é uma classe solta', () => {
  /* `variante: 'marca'` casou com `.marca` do tour — `position: absolute` —
     e jogou o card do Concierge para fora da tela. Modificador de card
     carrega o nome do card. */
  assert.match(cards, /' destaque-marca'/,
    'o card de marca voltou a usar um nome de classe genérico');
  assert.doesNotMatch(estado, /variante: 'marca'/,
    'o conteúdo voltou a injetar `marca` como classe solta no DOM');
});

test('a escala grande do hero fica presa à tela que foi desenhada', () => {
  /* O handoff desenhou só a tela "antes". Soltar `.v3-titulo` em 34px
     mudaria "Bom dia." do dia do evento e as outras duas telas sem
     ninguém ter olhado. */
  assert.match(css, /\.v3-hero\.decorado \.v3-titulo\s*\{[^}]*font-size:\s*34px/,
    'a escala de display do hero saiu do modificador');
  const solto = css.match(/\n\.v3-titulo\s*\{[^}]*\}/);
  assert.ok(solto && !/34px/.test(solto[0]),
    'a escala de 34px vazou para o `.v3-titulo` solto e agora vale nas quatro telas');
});

test('categoria de aviso é dado, com queda para o verde', () => {
  for (const c of ['antes_de_ir', 'no_evento', 'reservas', 'ingressos']) {
    assert.ok(estado.includes("'" + c + "'"), 'a categoria ' + c + ' sumiu de estado.js');
  }
  assert.match(estado, /categoriaValida\(a\.categoria \|\| a\.cat\)/,
    'a leitura da categoria vinda do banco mudou de forma');
  /* Aviso gravado antes da coluna existir chega sem categoria. Ele tem
     que aparecer assim mesmo — um aviso é para ser lido. */
  assert.match(estado, /CATEGORIAS_AVISO\.some\(\(c\) => c\.id === id\) \? id : 'antes_de_ir'/,
    'categoria desconhecida deixou de cair no verde e pode sumir da tela');
  assert.match(css, /\.c-no_evento \.v3-ico[^}]*var\(--roxo\)/, 'a tinta roxa sumiu');
  assert.match(css, /\.c-reservas \.v3-ico[^}]*var\(--coral\)/, 'a tinta coral sumiu');
});

test('o filtro de avisos não mostra chip que não tem o que filtrar', () => {
  assert.match(avisos, /CATEGORIAS_AVISO\.filter\(\(c\) => AVISOS\.some\(/,
    'os chips voltaram a ser fixos: aparece "Reservas" mesmo sem nenhum aviso de reserva');
  assert.match(avisos, /Nenhum aviso nesta categoria agora/,
    'filtro sem resultado voltou a devolver tela em branco, que é lida como erro');
});

test('a home não rola para os lados', () => {
  /* `overflow-y: auto` sozinho não basta: quando um eixo deixa de ser
     `visible`, o CSS transforma o outro em `auto`. Foi assim que o halo
     do hero, sangrando 70px para fora da direita, virou 50px de rolagem
     lateral — a tela deslizando como carrossel. */
  const i = css.indexOf('.v3-rolagem {');
  const regra = css.slice(i, css.indexOf('\n}', i));
  assert.match(regra, /overflow-x:\s*hidden/,
    'a home voltou a poder rolar na horizontal; o halo do hero sangra 70px e '
    + 'é ele que vira barra de rolagem');
});

test('o atalho abre UMA tela, não um roteiro', () => {
  /* O atalho trocava a tela e deixava as missões da reserva rodando por
     baixo: a barra dizia "Reservar seu lugar" e o anel circulava
     "Programação" enquanto a pessoa estava em "Minha Agenda". */
  assert.match(app, /function abrirTutorialEm\(tela\)\s*\{[\s\S]{0,220}telaAvulsa = tela;[\s\S]{0,80}MISSOES = \[\];/,
    'abrirTutorialEm parou de limpar o roteiro: o atalho volta a arrastar as '
    + 'missões da reserva para dentro da tela pedida');
  assert.match(app, /telaAvulsa = null;\s*\n\s*MISSOES = roteiro\.missoes;/,
    'o roteiro completo parou de desligar a bandeira de tela avulsa');
});

test('arrastar volta, e não teleporta na primeira tela', () => {
  assert.match(app, /function temVolta\(\)/,
    'a guarda que impede o arrastar de cair no `|| \'menu\'` de voltar() sumiu');
  assert.match(app, /if \(temVolta\(\)\) voltar\(\); else avisar\(/,
    'o arrastar voltou a chamar voltar() sem checar se há para onde voltar');
  /* Arrastar por cima de um alvo não pode abrir o alvo. */
  assert.match(app, /addEventListener\('click',[\s\S]{0,140}arrastou[\s\S]{0,160}\}, true\)/,
    'o clique que fecha o arrastar deixou de ser engolido na captura');
  /* A imagem não pode ser arrastável: o gesto nativo do navegador rouba
     o ponteiro no primeiro milímetro e o arrastar nunca acontece. */
  assert.match(css, /\.frame img\s*\{[^}]*user-drag:\s*none/,
    'a captura voltou a ser arrastável e o gesto de voltar morre no primeiro pixel');
});
