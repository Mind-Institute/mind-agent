/* ============================================================
   QUEM PODE ENQUADRAR O AGENTE
   ============================================================
   Até esta rodada o Worker não dizia nada sobre enquadramento: sem
   `frame-ancestors` e sem `X-Frame-Options`, QUALQUER site podia pôr o
   app num iframe e montar uma tela em volta dele. Era o item que sobrou
   aberto do P2 em `SUMMIT_2026_AGENTE_CONTEUDO_PROPOSTA.md`.

   Isto NÃO tem a ver com a MIA no LearnWorlds. Aquele embed é um bloco
   colado dentro do curso, que fala direto com o Supabase e nunca carrega
   nada deste app — o porquê está no cabeçalho de `cloudflare/roteamento.js`.

   A lista de quem pode é de permissão, e este arquivo existe para o site
   que alguém acrescentar amanhã não entrar calado, e para
   `X-Frame-Options` não voltar "por segurança": ele só sabe dizer
   "ninguém" ou "a mesma origem", e fecharia a porta que a lista abre.

   SEPARADO DO `embed_institute.test.mjs` de propósito: um arquivo é a cara
   da agente dentro do curso, o outro é política de segurança do site.
   Foram decididos em momentos diferentes e por gente diferente.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte, semComentarios } from './helpers/ler-fonte.mjs';
import { ENQUADRADORES, POLITICA_DE_ENQUADRAMENTO } from '../cloudflare/roteamento.js';

const worker = lerFonte(new URL('../cloudflare/worker.ts', import.meta.url));
const simulador = lerFonte(new URL('../scripts/servir-cloudflare.mjs', import.meta.url));
const workerSemComentarios = semComentarios(worker);

test('a política nomeia o Institute e é lista de permissão', () => {
  assert.match(POLITICA_DE_ENQUADRAMENTO, /^frame-ancestors /);
  assert.ok(ENQUADRADORES.includes('https://my.mindinstitute.com.br'),
    'o endereço do Mind Institute saiu da lista: o embed para de abrir dentro do curso');
  assert.ok(ENQUADRADORES.includes("'self'"),
    "'self' saiu da lista; o app deixaria de poder enquadrar a si mesmo");
  for (const intruso of ['*', "'none'", 'http:', 'https:']) {
    assert.ok(!ENQUADRADORES.includes(intruso),
      `\`${intruso}\` entrou na lista e a transforma em lista de bloqueio: `
      + 'qualquer site volta a poder enquadrar o agente');
  }
});

test('X-Frame-Options não entra junto', () => {
  for (const fonte of [workerSemComentarios, semComentarios(simulador)]) {
    assert.ok(!/X-Frame-Options/i.test(fonte),
      'X-Frame-Options voltou. Ele só sabe dizer "ninguém" ou "a mesma origem" — '
      + 'não sabe abrir para um terceiro, e fecharia a porta que a lista de '
      + 'permissão abre de propósito');
  }
});

test('a política sai por uma porta só, e não por cada return', () => {
  assert.match(workerSemComentarios,
    /async fetch\([^)]*\): Promise<Response> \{\s*return comEnquadramento\(await atender\(request, env\)\)/,
    'o Worker deixou de aplicar o enquadramento na saída única. Pendurado em cada '
    + '`return`, ele deixa de valer no caminho que alguém acrescentar amanhã');
  assert.match(workerSemComentarios, /new Response\(resposta\.body, resposta\)/,
    'a cópia da resposta sumiu: os cabeçalhos que vêm dos assets são imutáveis, '
    + 'e escrever neles lança');
});

test('o simulador local serve a mesma política que sobe', () => {
  assert.match(semComentarios(simulador), /'content-security-policy': POLITICA_DE_ENQUADRAMENTO/,
    'o simulador voltou a servir sem a política: enquadramento que não se prova '
    + 'aqui só aparece quebrado dentro do curso, depois do deploy');
});
