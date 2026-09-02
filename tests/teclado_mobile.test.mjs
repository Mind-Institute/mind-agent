/* ============================================================
   O TECLADO NÃO PODE VOLTAR A EMPURRAR A TELA
   ============================================================
   Este arquivo não abre navegador. Ele trava, nos BYTES vivos, as três
   decisões que fazem a tela parar de saltar quando o teclado abre — porque as
   três são fáceis de desfazer sem querer, e o estrago só aparece num iPhone
   real, que ninguém tem na mão ao revisar um diff.

   A prova de comportamento foi feita em navegador, dirigindo o app em três
   tamanhos de tela e simulando o teclado do jeito que o iOS faz (encolhendo só
   o viewport visual, sem mexer no de layout). Esse teste vive em
   `tests/teclado_mobile_navegador.mjs` e precisa do Playwright, que não é
   dependência deste repositório — por isso ele não roda no `npm test`. O que
   roda sempre é isto aqui.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const css = readFileSync(new URL('../styles.css', import.meta.url), 'utf8');
const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
const teclado = readFileSync(new URL('../teclado.js', import.meta.url), 'utf8');

/* Recorta a regra `body { … }` de primeiro nível, que é a que define a caixa
   do app. Procurar `height: 100dvh` no arquivo inteiro daria falso positivo em
   qualquer outra regra que legitimamente use a unidade. */
function regraDoBody() {
  const i = css.indexOf('\nbody {');
  assert.notEqual(i, -1, 'a regra do body sumiu de styles.css');
  const fim = css.indexOf('\n}', i);
  return css.slice(i, fim);
}

test('a altura do app vem do viewport visual, não de 100dvh sozinho', () => {
  const body = regraDoBody();
  assert.match(body, /height:\s*var\(--app-altura/,
    'o body voltou a ter altura fixa; com isso o iOS rola a página inteira ao focar o campo');
  assert.match(body, /position:\s*fixed/,
    'sem `position: fixed` o documento volta a ter para onde rolar');
});

test('o documento não rola — quem rola é a conversa', () => {
  assert.match(css, /html\s*\{[^}]*overflow:\s*hidden/,
    'o html voltou a poder rolar, e é isso que leva o header embora');
  const i = css.indexOf('.mensagens {');
  const mensagens = css.slice(i, css.indexOf('\n}', i));
  assert.match(mensagens, /overscroll-behavior:\s*contain/,
    'sem isto a rolagem da conversa vaza para o documento no fim da lista');
});

test('com o teclado aberto o campo perde o inset de baixo', () => {
  assert.match(css, /html\[data-teclado="aberto"\]\s*\.doca\s*\{[^}]*padding-bottom:\s*8px/,
    'o inset da safe area com o teclado aberto vira faixa vazia entre campo e teclado');
});

test('a barra de abas tem regra para sair de cena com o teclado', () => {
  assert.match(css, /html\[data-teclado="aberto"\]\s*\.barra-abas/,
    'a regra que esconde a barra inferior durante a digitação sumiu');
});

test('nada anima a altura do app — quem anima é o teclado', () => {
  const body = regraDoBody();
  assert.doesNotMatch(body, /transition/,
    'uma transição própria na altura compete com a animação nativa do teclado e chega atrasada');
});

test('o campo de mensagem nunca é desabilitado', () => {
  assert.doesNotMatch(app, /campoChat\.disabled\s*=/,
    'desabilitar o campo focado tira o foco, e no iOS isso fecha o teclado a cada envio — '
    + 'o guarda contra envio duplicado é `respostaEmAndamento`, não o `disabled`');
});

test('o runtime do teclado é ligado antes de qualquer tela', () => {
  assert.match(app, /import\s*\{[^}]*ligarTeclado[^}]*\}\s*from\s*'\.\/teclado\.js'/,
    'app.js parou de importar o módulo do teclado');
  assert.match(app, /^ligarTeclado\(\);$/m,
    'ligarTeclado() precisa rodar na carga: toda vista depende da altura que ele publica');
});

test('o módulo mede o viewport visual e desfaz a rolagem do navegador', () => {
  assert.match(teclado, /visualViewport/, 'a medida do viewport visual sumiu');
  assert.match(teclado, /--app-altura/, 'o módulo parou de publicar a altura');
  assert.match(teclado, /window\.scrollTo\(0,\s*0\)/,
    'sem desfazer o deslocamento residual do Safari, o primeiro toque ainda dá um tranco');
  assert.match(teclado, /scrollHeight\s*-\s*\w+\.scrollTop\s*-\s*\w+\.clientHeight/,
    'a distância até o FUNDO é o que mantém a última mensagem no lugar quando a área encolhe');
});
