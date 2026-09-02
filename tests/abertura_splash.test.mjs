/* ============================================================
   A ABERTURA NÃO PODE VOLTAR A PARECER TELA TRAVADA
   ============================================================
   Do lado de quem espera não existe diferença entre uma animação longa e um
   app que não carrega. A abertura durava quase oito segundos e voltava
   inteira a cada recarga — e recarregar é justamente o que a pessoa faz
   quando acha que travou, então a punição caía sobre quem já estava
   incomodado.

   Este arquivo trava as três decisões nos bytes vivos: quanto tempo a
   abertura pode durar, que ela some ao toque em qualquer lugar, e que não
   se repete na mesma sessão. Nenhuma delas é visível num diff de uma linha
   — mudar `LEITURA` de 1500 para 4000 parece inofensivo.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');

/* A frase digitada, para a conta do tempo sair do texto real e não de um
   número chutado: se alguém aumentar a fala, o teto vale sobre ela. */
function tamanhoDaFala() {
  const bloco = app.slice(app.indexOf('const FALA = ['), app.indexOf('(function digitar()'));
  const trechos = [...bloco.matchAll(/\['([^']*)'/g)].map((m) => m[1]);
  assert.ok(trechos.length > 0, 'não achei a fala da abertura');
  return trechos.join('').length;
}

function constante(nome) {
  const m = app.match(new RegExp('const\\s+' + nome + '\\s*=\\s*(\\d+)'));
  assert.ok(m, `a constante ${nome} sumiu da abertura`);
  return Number(m[1]);
}

test('a abertura inteira cabe em 5 segundos', () => {
  const total = constante('ATRASO') + tamanhoDaFala() * constante('PASSO') + constante('LEITURA');
  assert.ok(total <= 5000,
    `a abertura leva ${total}ms até começar a sair, mais 550ms de fade. `
    + 'Acima de 5s ela volta a ser lida como app que não carrega — foi assim que chegou a 7,2s.');
});

test('a espera depois da frase pronta não domina a abertura', () => {
  const digitando = constante('ATRASO') + tamanhoDaFala() * constante('PASSO');
  assert.ok(constante('LEITURA') <= digitando,
    'a pausa com a frase parada na tela passou a ser maior que a animação inteira; '
    + 'era esse o desequilíbrio original (4000ms de pausa para 3200ms de escrita)');
});

test('tocar em qualquer lugar fecha a abertura', () => {
  assert.match(app, /splash\.addEventListener\('click',\s*fecharSplash\)/,
    'o único escape voltou a ser a pílula de 13px no canto; quem olha o símbolo no meio '
    + 'da tela não procura lá');
});

test('a abertura não se repete na mesma sessão', () => {
  assert.match(app, /sessionStorage\.getItem\(CHAVE_ABERTURA\)/,
    'a guarda de sessão sumiu: a abertura voltaria a rodar inteira a cada recarga');
  assert.match(app, /if \(jaViuAbertura\) \{ splash\.remove\(\); return; \}/,
    'quem já viu a abertura precisa entrar direto, sem fade nem animação');
});

test('o botão Pular continua existindo', () => {
  const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  assert.match(html, /id="pular"/, 'o Pular explícito continua sendo o caminho descobrível');
  assert.match(app, /getElementById\('pular'\)\.addEventListener\('click', fecharSplash\)/,
    'o Pular parou de fechar a abertura');
});
