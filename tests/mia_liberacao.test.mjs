/* ============================================================
   A LIBERAÇÃO PELA PESQUISA — o portão, e o que ele não é
   ============================================================
   A MIA só abre para quem já respondeu a pesquisa. A tela pergunta ao
   servidor a cada entrada; a função `mia-liberacao` responde sim ou não.

   Duas regras duras, e os testes existem por elas:

   1. FALHA FECHA. Não saber se a pessoa pode entrar nunca pode virar
      "pode". Vale no servidor (erro de banco → `liberada: false`) e no
      cliente (resposta que não chega → bloqueado).
   2. SÓ UM BOOLEANO ATRAVESSA. Resposta de pesquisa é dado pessoal; o
      navegador precisa de um sim ou não, e é só isso que ele recebe.

   E uma verdade desconfortável que fica escrita aqui para ninguém se
   enganar depois: isto é uma CORTINA, não uma fechadura. O e-mail do
   LearnWorlds não é assinado e a chave publishable é pública, então a
   `mindagent-chat` continua respondendo a quem a chamar direto. Serve para
   sequenciar a experiência de quem é honesto.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte, semComentarios } from './helpers/ler-fonte.mjs';

const bloco = lerFonte(new URL('../learnworlds/mia-embed.html', import.meta.url));
const funcao = lerFonte(new URL('../supabase/functions/mia-liberacao/index.ts', import.meta.url));
const codigoDaFuncao = semComentarios(funcao);

/* ============================================================
   O CSS DO BLOCO PRECISA ANALISAR
   ============================================================
   Este teste nasceu de um defeito que chegou à produção. Em 28/10 um
   comentário meu ficou com um fechamento sobrando: o texto solto virou lixo
   para o parser de CSS, que engoliu a regra seguinte —
   `.mia-lw .mia-palavra` com o seu `display: inline-block`.

   Não quebrou nada visível. `filter` e `opacity` valem em caixa inline,
   então o desfoque e a opacidade continuaram funcionando; `transform`, não.
   A subida de 10px da palavra simplesmente não aconteceu em produção, e eu
   não vi porque medi o desfoque, não o `transform`.

   Um comentário desbalanceado é invisível na revisão e caro na tela. Este
   teste é barato. */

const css = bloco.slice(bloco.indexOf('<style>') + 7, bloco.indexOf('</style>'));

test('os comentários do CSS do bloco abrem e fecham na mesma conta', () => {
  const abre = (css.match(/\/\*/g) || []).length;
  const fecha = (css.match(/\*\//g) || []).length;
  assert.equal(abre, fecha,
    `${abre} comentários abertos e ${fecha} fechados: uma abertura ou um `
    + 'fechamento sobrando faz o parser engolir a regra seguinte, em silêncio '
    + 'e sem erro no console');
});

test('nenhum fechamento de comentário fica órfão no meio do CSS', () => {
  /* A conta acima empata quando sobra um de cada. Esta varredura pega o
     caso real que aconteceu: um fechamento que fecha o que já estava
     fechado. */
  let dentro = false;
  for (let i = 0; i < css.length - 1; i++) {
    const par = css[i] + css[i + 1];
    if (!dentro && par === '/*') { dentro = true; i++; continue; }
    if (dentro && par === '*/') { dentro = false; i++; continue; }
    assert.ok(!(!dentro && par === '*/'),
      'achei um fechamento de comentário fora de comentário por volta de: '
      + JSON.stringify(css.slice(Math.max(0, i - 70), i + 2).trim().slice(-70)));
  }
  assert.equal(dentro, false, 'um comentário do CSS ficou aberto até o fim do bloco');
});

test('a regra que faz a palavra subir continua valendo', () => {
  /* `transform` não vale em caixa inline. Sem `inline-block`, o surgir
     perde a subida e ninguém percebe. */
  assert.match(css, /\.mia-lw \.mia-palavra \{[^}]*display: inline-block/,
    'sumiu o `inline-block` da palavra: o `translateY` do surgir para de valer');
});

/* ============================================================
   O PORTÃO, NO SERVIDOR
   ============================================================ */

test('a costura da pesquisa é uma função só, e está marcada', () => {
  assert.match(funcao, /function respondeuAPesquisa\(/,
    'a costura mudou de nome: quem for ligar a pesquisa não vai achar onde');
  assert.match(funcao, /É AQUI QUE A PESQUISA ENTRA, E SÓ AQUI/,
    'sumiu a marca que diz onde trocar quando a pesquisa existir');
});

test('enquanto a pesquisa não existe, o portão fica fechado', () => {
  assert.match(codigoDaFuncao, /return \{ liberada: false, motivo: "pesquisa_nao_configurada" \}/,
    'o portão sem pesquisa configurada precisa negar: um portão que ainda não '
    + 'sabe quem passa não pode ficar aberto');
});

test('erro de banco fecha o portão, não abre', () => {
  const captura = codigoDaFuncao.slice(codigoDaFuncao.indexOf('catch (erro)'));
  assert.match(captura, /liberada: false/,
    'o `catch` precisa devolver bloqueado: não saber nunca vira "pode entrar"');
});

test('e-mail inválido não vira acesso por acidente', () => {
  const trecho = codigoDaFuncao.slice(codigoDaFuncao.indexOf('EMAIL.test(email)'));
  assert.match(trecho.slice(0, 400), /liberada: false/,
    'sem e-mail válido o portão precisa negar');
});

test('só um booleano atravessa — nunca a resposta da pesquisa', () => {
  /* O corpo devolvido é montado em dois lugares, e os dois só carregam
     `ok`, `liberada` e `motivo`. */
  const devolvidos = [...codigoDaFuncao.matchAll(/json\(req, \d+, \{([^}]*)\}/g)]
    .map((m) => m[1]);
  assert.ok(devolvidos.length >= 3, 'não consegui ler as respostas da função');
  for (const corpo of devolvidos) {
    assert.doesNotMatch(corpo, /email|nome|respost|data|pessoa|mind_id/i,
      `uma resposta leva dado pessoal para o navegador: {${corpo.trim()}}`);
  }
});

/* ============================================================
   O PORTÃO, NA TELA
   ============================================================ */

const portao = bloco.slice(bloco.indexOf('A LIBERAÇÃO PELA PESQUISA'));
const codigoDoPortao = semComentarios(portao);

test('sem o atributo, o bloco é o de sempre', () => {
  /* Opt-in: quem já colou o bloco não ganha portão nenhum por acidente. */
  assert.match(codigoDoPortao, /if \(raiz\.getAttribute\('data-liberacao'\) !== 'pesquisa'\) return;/,
    'o portão deixou de ser opt-in: todo bloco já colado por aí passaria a '
    + 'esconder a MIA atrás de uma pesquisa');
});

test('a tela parte do estado carregando, com a capa na frente', () => {
  const ordem = codigoDoPortao.indexOf('carregando();');
  const chamada = codigoDoPortao.indexOf('fetch(SUPABASE');
  assert.ok(ordem > 0 && ordem < chamada,
    'a tela precisa abrir carregando, antes de perguntar: se abrisse no chat, '
    + 'quem não está liberado veria a MIA por um instante');
});

test('resposta que não chega deixa a MIA fechada', () => {
  /* Procura o `catch` DA CHAMADA, e não o primeiro do arquivo: o primeiro é
     o do `r.json()`, que só devolve um objeto vazio quando o corpo não é
     JSON. Mirar nele faria o teste passar sem provar nada. */
  assert.match(codigoDoPortao, /\.catch\(function \(\) \{\s*bloquear\(\);\s*\}\)/,
    'o `catch` da chamada precisa bloquear: falha de rede não pode abrir a MIA');
});

test('só `liberada: true` abre', () => {
  assert.match(codigoDoPortao, /p\.liberada === true\) abrir\(\); else bloquear\(\)/,
    'a comparação precisa ser estrita: um corpo estranho com `liberada: "nao"` '
    + 'abriria a MIA se o teste fosse por veracidade');
});
