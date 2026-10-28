/* ============================================================
   A MÁQUINA DE ESCREVER — ritmo de leitura, e saída para quem já leu
   ============================================================
   A resposta chega inteira do servidor; isto não é streaming, é ritmo.
   Então tudo aqui é escolha de quanto tempo da pessoa a gente gasta com
   um efeito — e é por isso que os números ficam travados.

   Eram 5ms por letra com teto de 1,8s: uma resposta de mil caracteres
   passava em menos de dois segundos, cerca de treze letras por quadro.
   Não se lia aquilo — borrava e estava escrito.

   16ms por letra, a 60 quadros por segundo, é UMA LETRA POR QUADRO: o
   reveal mais suave que a tela permite. Abaixo disso o quadro cospe
   letra em bloco, e é o borrão de volta.

   O teto existe pelo motivo de sempre: prender a leitura de um texto que
   já está na mão é cobrar da pessoa o preço de um efeito. E o teto só não
   vira prisão porque existe saída — um toque completa o texto.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte, semComentarios } from './helpers/ler-fonte.mjs';

const bloco = lerFonte(new URL('../learnworlds/mia-embed.html', import.meta.url));
const maquina = bloco.slice(bloco.indexOf('function maquinaDeEscrever('),
                            bloco.indexOf('var emAndamento'));

assert.ok(maquina.length > 500, 'não achei a máquina de escrever no bloco');

/* Os comentários daqui CITAM o que não se deve fazer: está escrito neles que
   o efeito não é `requestAnimationFrame` e que não há `preventDefault`. Um
   teste que procura essas palavras no texto inteiro acha a frase que explica
   a regra e acusa justamente o código que a cumpre. */
const codigo = semComentarios(maquina);

/* O número do ritmo, lido do próprio código. */
const formula = maquina.match(
  /var duracao = Math\.max\((\d+), Math\.min\((\d+), total \* (\d+)\)\)/);
assert.ok(formula, 'a fórmula da duração mudou de forma e este teste ficou cego');
const [, piso, teto, porLetra] = formula.map(Number);

/* ============================================================
   O RITMO
   ============================================================ */

test('cada letra ganha pelo menos um quadro inteiro', () => {
  /* O `setInterval` do efeito bate de 16 em 16ms. Com menos de 16ms por
     letra, cada batida precisa revelar mais de uma — que é exatamente o
     borrão que estávamos vendo. */
  const intervalo = Number((maquina.match(/setInterval\(passo, (\d+)\)/) || [])[1]);
  assert.equal(intervalo, 16, 'o relógio do efeito deixou de ser de 60 quadros');
  assert.ok(porLetra >= intervalo,
    `${porLetra}ms por letra contra um quadro de ${intervalo}ms: a tela volta a `
    + `revelar ${Math.ceil(intervalo / porLetra)} letras de uma vez`);
});

test('uma resposta típica leva segundos, não um piscar', () => {
  /* 923 caracteres é a mediana real das respostas da MIA (34 respostas
     medidas no banco em 27/10/2026). */
  const duracao = Math.max(piso, Math.min(teto, 923 * porLetra));
  assert.ok(duracao >= 3000,
    `a resposta mediana aparece em ${duracao}ms: rápido demais para acompanhar`);
});

test('o efeito não prende a leitura de um texto que já chegou', () => {
  assert.ok(teto <= 8000,
    `o teto de ${teto}ms cobra tempo demais da pessoa por um texto que já está `
    + 'na mão dela');
  const duracao = Math.max(piso, Math.min(teto, 4000 * porLetra));
  assert.equal(duracao, teto, 'uma resposta longa precisa bater no teto');
});

test('uma resposta curta não some antes de ser vista', () => {
  assert.ok(piso >= 500,
    `"Claro, posso ajudar." apareceria em ${piso}ms — some antes do olho pegar`);
});

/* ============================================================
   A SAÍDA
   ============================================================ */

test('um toque na resposta completa o texto', () => {
  /* `pular` era devolvido desde sempre e nunca tinha sido ligado em lugar
     nenhum: não havia como escapar do efeito. Com o teto maior, isso deixa
     de ser detalhe. */
  assert.match(maquina, /destino\.addEventListener\('click'/,
    'não existe como completar o texto: quem quer só ler fica esperando a letra');
  assert.match(maquina, /function aoTocar\(\)\s*\{\s*if \(vivo\) tudo\(\); \}/,
    'o atalho precisa terminar o efeito, e só quando ele ainda está vivo');
});

test('o toque não atrapalha um link dentro da resposta', () => {
  assert.doesNotMatch(codigo, /preventDefault/,
    'cancelar o clique mataria os links que a MIA manda na resposta');
});

test('o atalho é desligado quando o texto termina', () => {
  const tudo = maquina.slice(maquina.indexOf('function tudo()'),
                             maquina.indexOf('function aoTocar'));
  assert.match(tudo, /removeEventListener\('click', aoTocar\)/,
    'o ouvinte fica preso na bolha depois do efeito acabar');
});

/* ============================================================
   O QUE NÃO PODE VOLTAR
   ============================================================ */

test('o efeito não depende de quadro de animação', () => {
  /* O navegador não chama `requestAnimationFrame` em aba que não está na
     frente. Com o efeito preso nele, quem trocava de aba enquanto a MIA
     respondia voltava para uma resposta VAZIA. Aconteceu aqui no teste, e
     aconteceria com o aluno que abre o vídeo da aula na aba ao lado. */
  assert.doesNotMatch(codigo, /requestAnimationFrame/,
    'a resposta volta a sumir para quem troca de aba enquanto ela escreve');
  assert.match(maquina, /garantia = setTimeout\(tudo, duracao \+ \d+\)/,
    'sumiu a garantia final: passe o que passar, a resposta precisa aparecer '
    + 'inteira');
});

test('quem pediu menos movimento recebe o texto de uma vez', () => {
  assert.match(maquina, /prefers-reduced-motion: reduce[\s\S]{0,80}tudo\(\)/,
    'o efeito ignora quem desligou animação no sistema');
});
