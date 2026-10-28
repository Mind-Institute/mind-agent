/* ============================================================
   O CAMPO DE PERGUNTA — a barra de rolagem não bate no botão
   ============================================================
   O campo rola quando a pergunta passa de três linhas. A barra nativa
   do Windows tem 17px e nasce colada na borda direita; o botão de
   enviar mora a 6px dessa borda. Medido rodando: a barra entrava 11px
   por baixo do botão, com as setas do sistema ao lado dele. Foi o que
   o Vinícius viu em 28/10/2026.

   O arquivo existe por causa de uma armadilha específica, que custou
   uma tentativa: declarar `scrollbar-width: thin` no campo PIORA a
   correção. Quando essa propriedade está presente, o Chromium obedece a
   ela e IGNORA a largura do `::-webkit-scrollbar` — a barra saiu de
   17px para 12px em vez de 6px e continuou batendo no botão. `thin` não
   é um tamanho; é "o fino que o sistema quiser".

   Nada disso aparece lendo o CSS: as duas regras parecem concordar.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte } from './helpers/ler-fonte.mjs';

const bloco = lerFonte(new URL('../learnworlds/mia-embed.html', import.meta.url));
const estilo = bloco.slice(bloco.indexOf('<style>'), bloco.indexOf('</style>'));

/* Só as DECLARAÇÕES do campo, sem os comentários — que citam de propósito a
   propriedade proibida, para explicar por que ela não está lá. */
const regrasDoCampo = estilo.replace(/\/\*[\s\S]*?\*\//g, '')
  .split('}')
  .filter((r) => /\.mia-form textarea/.test(r))
  .join('}');

test('a barra do campo é estreita o bastante para caber antes do botão', () => {
  assert.match(regrasDoCampo, /::-webkit-scrollbar \{[^}]*width: 6px/,
    'sumiu a largura da barra: ela volta aos 17px do sistema e entra por '
    + 'baixo do botão de enviar');
});

test('`scrollbar-width` não volta ao campo', () => {
  assert.doesNotMatch(regrasDoCampo, /scrollbar-width/,
    'com `scrollbar-width` declarado, o Chromium ignora a largura do '
    + '`::-webkit-scrollbar` e a barra volta a bater no botão — foi medido, '
    + 'deu 12px em vez de 6px');
});

test('as setas do sistema não aparecem ao lado do botão', () => {
  assert.match(regrasDoCampo, /::-webkit-scrollbar-track \{[^}]*background: transparent/,
    'sem o trilho transparente, a barra desenha a calha cinza e as setas do '
    + 'sistema encostadas no botão');
});

test('o botão de enviar fica por cima quando a colisão acontece', () => {
  /* O Firefox só entende a propriedade que foi descartada, então lá a barra
     é larga. O `z-index` não evita a colisão: decide quem fica por cima. */
  const regraDoBotao = estilo.replace(/\/\*[\s\S]*?\*\//g, '')
    .split('}').find((r) => /\.mia-form button \{/.test(r));
  assert.ok(regraDoBotao && /z-index: 1/.test(regraDoBotao),
    'sem `z-index`, no navegador de barra larga o botão volta a ser cortado');
});
