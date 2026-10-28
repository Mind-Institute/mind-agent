/* ============================================================
   OS PASSOS DA ESPERA — o que a tela diz enquanto a MIA pensa
   ============================================================
   O turno da MIA dura de 20 a 45 segundos (`ORCAMENTO_TURNO_MS` e
   `ORCAMENTO_TURNO_COMPLEXO_MS` em `supabase/functions/_shared/
   agent-intelligence.ts`). Os passos antigos acabavam aos 6s: a pessoa
   passava mais de vinte segundos olhando uma lista parada. A demora não
   vinha do tempo — vinha do silêncio depois do sexto segundo.

   Dois compromissos sustentam o que está escrito na tela, e é o que
   este arquivo trava:

   1. O TEMA É REAL. O destaque do segundo passo só pode nomear um dos
      mapas temáticos que o acervo tem de fato
      (`summit_2026.knowledge_documents`, `tipo_conteudo =
      'mapa_tematico'`, `ativo = true`). Inventar assunto para a tela
      ficar bonita é dizer à pessoa que procuramos onde não existe nada.

   2. A PALAVRA É DE QUEM PERGUNTOU. O tema sai do texto da pergunta,
      por palavra inteira. Sem isso, "guerra" vira "erro" e a tela
      afirma um assunto que ninguém trouxe.

   O que estes passos NÃO são: relato. Eles são a expectativa do caminho
   normal dela, e continuam sendo substituídos pelo relato real
   (`relatoDoTurno`) quando a resposta chega — inclusive por "Respondeu
   sem consultar o acervo", quando foi isso que aconteceu.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte } from './helpers/ler-fonte.mjs';

const bloco = lerFonte(new URL('../learnworlds/mia-embed.html', import.meta.url));

/* O teste roda o CÓDIGO do bloco, não uma cópia dele: recorta o trecho
   do arquivo e o executa. Se alguém mexer no matcher lá, é o matcher
   mexido que responde aqui. */
const inicio = bloco.indexOf('function passosDaEspera(tema) {');
const fim = bloco.indexOf('var NOME_DA_FERRAMENTA');
assert.ok(inicio > 0 && fim > inicio,
  'não achei o trecho dos passos no bloco: `passosDaEspera` ou '
  + '`NOME_DA_FERRAMENTA` mudaram de nome e este teste ficou cego');

const { passosDaEspera, temaDaPergunta, TEMA_POR_PALAVRA } = new Function(
  bloco.slice(inicio, fim)
  + 'return { passosDaEspera: passosDaEspera, temaDaPergunta: temaDaPergunta,'
  + ' TEMA_POR_PALAVRA: TEMA_POR_PALAVRA };')();

/* Os 31 mapas temáticos vivos, como o banco os nomeia (consultado em
   28/10/2026). O banco escreve tudo em caixa baixa; a tela escreve
   "ROI", "IA" e "NR-1" em caixa alta porque são siglas e é assim que se
   lê. A comparação ignora caixa de propósito — o que precisa bater é o
   assunto, não a tipografia. */
const MAPAS_DO_ACERVO = [
  'aprendizagem e erro', 'autocompaixão', 'burnout', 'carreira',
  'conversas difíceis', 'cultura organizacional', 'dados, mensuração e roi',
  'desenho do trabalho', 'diversidade e inclusão',
  'emoções positivas e felicidade', 'engajamento e propósito',
  'feedback e reconhecimento', 'finitude e sentido', 'foco e atenção',
  'futuro do trabalho e ia', 'governança e compliance', 'gratidão',
  'investidores e negócio', 'liderança', 'liderança feminina',
  'longevidade e corpo', 'nr-1 e riscos psicossociais', 'parentalidade',
  'produtividade sustentável', 'programas de bem-estar',
  'relações e vínculos', 'resiliência', 'saúde mental',
  'segurança psicológica', 'tecnologia e distração', 'trabalho híbrido',
];

/* ============================================================
   O ROTEIRO COBRE A ESPERA INTEIRA
   ============================================================ */

test('o roteiro vai até perto do teto do turno, não morre aos 6 segundos', () => {
  const passos = passosDaEspera(null);
  const ultimo = passos[passos.length - 1][0];
  assert.ok(ultimo >= 30000,
    `o último passo entra aos ${ultimo / 1000}s e o turno complexo vai até 45s: `
    + 'a lista volta a congelar no meio da espera');
  assert.ok(ultimo < 45000,
    'o último passo entra depois do teto de 45s do servidor — nunca seria visto');
});

test('nenhum trecho da espera fica mudo por muito tempo', () => {
  const quandos = passosDaEspera(null).map((p) => p[0]);
  for (let i = 1; i < quandos.length; i++) {
    const silencio = quandos[i] - quandos[i - 1];
    assert.ok(silencio <= 12000,
      `${silencio / 1000}s parados entre "${passosDaEspera(null)[i - 1][1]}" e o `
      + 'passo seguinte: é esse silêncio que vira sensação de travado');
  }
});

test('os passos entram em ordem crescente e o primeiro é imediato', () => {
  const quandos = passosDaEspera(null).map((p) => p[0]);
  assert.equal(quandos[0], 0, 'a primeira linha precisa aparecer junto com a pergunta');
  for (let i = 1; i < quandos.length; i++) {
    assert.ok(quandos[i] > quandos[i - 1],
      'dois passos no mesmo instante: um deles nunca é lido');
  }
});

/* ============================================================
   O TEMA É DO ACERVO, E SÓ DO ACERVO
   ============================================================ */

test('todo tema que a tela pode exibir existe como mapa temático', () => {
  const vivos = new Set(MAPAS_DO_ACERVO.map((t) => t.toLowerCase()));
  for (const [palavra, tema] of TEMA_POR_PALAVRA) {
    assert.ok(vivos.has(tema.toLowerCase()),
      `"${palavra}" promete "${tema}", que não é mapa temático nenhum: a tela `
      + 'diria que procurou num assunto que o acervo não tem');
  }
});

test('o segundo passo nomeia o tema quando a pergunta traz um', () => {
  const passo = passosDaEspera('burnout')[1][1];
  assert.equal(typeof passo, 'object',
    'o tema precisa vir em pedaço próprio, para ser destacado sem virar HTML');
  assert.equal(passo.destaque, 'burnout');
  assert.match(passo.antes + passo.destaque + passo.depois,
    /Procurando sobre burnout no acervo do Summit/);
});

test('sem tema reconhecido, o passo fica genérico em vez de chutar', () => {
  const passo = passosDaEspera(null)[1][1];
  assert.equal(typeof passo, 'string',
    'sem tema não existe destaque: nada a emoldurar');
  assert.equal(passo, 'Procurando no acervo do Summit');
});

/* ============================================================
   A PALAVRA SAI DA PERGUNTA
   ============================================================ */

test('reconhece o assunto em perguntas escritas como as pessoas escrevem', () => {
  const casos = [
    ['minha equipe está exausta, o que fazer?', 'burnout'],
    ['preciso ter uma conversa difícil com meu time', 'conversas difíceis'],
    /* "feedback difícil" tem os dois assuntos dentro, e os dois existem no
       acervo. Fica com feedback porque é a palavra que a pessoa escolheu
       para nomear a coisa — a conversa aqui é adjetivo. */
    ['como dar feedback difícil pra alguém mais velho', 'feedback e reconhecimento'],
    ['o que falaram sobre NR-1?', 'NR-1 e riscos psicossociais'],
    ['como criar segurança psicológica no time', 'segurança psicológica'],
    ['teve alguma sessão sobre mulheres na liderança?', 'liderança feminina'],
    ['meu chefe não me escuta', 'liderança'],
    ['como medir o ROI de um programa de bem-estar', 'dados, mensuração e ROI'],
    ['o que disseram sobre inteligência artificial no trabalho', 'futuro do trabalho e IA'],
    ['trabalho híbrido funciona mesmo?', 'trabalho híbrido'],
    ['não consigo ter foco', 'foco e atenção'],
  ];
  for (const [pergunta, esperado] of casos) {
    assert.equal(temaDaPergunta(pergunta), esperado,
      `"${pergunta}" devia cair em "${esperado}"`);
  }
});

test('acento na pergunta não muda o resultado', () => {
  assert.equal(temaDaPergunta('como ser um bom lider'), 'liderança');
  assert.equal(temaDaPergunta('como ser um bom líder'), 'liderança');
  assert.equal(temaDaPergunta('falaram de gratidao?'), 'gratidão');
});

test('o específico ganha do geral', () => {
  assert.equal(temaDaPergunta('liderança feminina no Summit'), 'liderança feminina',
    'caiu em "liderança": a pessoa perguntou de algo mais estreito e a tela '
    + 'responderia mais largo');
  assert.equal(temaDaPergunta('segurança psicológica'), 'segurança psicológica');
});

test('casa por palavra inteira, não por pedaço de palavra', () => {
  /* Sem a borda, "erro" mora dentro de "guerra" e "ferro", e "foco" dentro
     de "sufoco". A tela afirmaria um assunto que ninguém trouxe. */
  assert.notEqual(temaDaPergunta('como falar sobre a guerra no trabalho'),
    'aprendizagem e erro');
  assert.notEqual(temaDaPergunta('estou naquele sufoco de sempre'), 'foco e atenção');
  assert.equal(temaDaPergunta('qual o horário do credenciamento?'), null,
    'pergunta sem assunto do acervo não devia ganhar tema nenhum');
});

/* ============================================================
   O PASSO NOVO ENTRA EMBAIXO, E SÓ ELE
   ============================================================
   Cada passo redesenhava a lista inteira: os de cima eram destruídos e
   recriados, a animação de entrada (`mia-entra`) recomeçava em todos, e
   a lista piscava e pulava a cada linha nova. Quem está lendo a terceira
   linha não pode ter a primeira arrancada debaixo do olho.

   A única troca completa legítima é no fim do turno, quando a lista
   deixa de ser expectativa e vira relato — ali é outro conteúdo, não
   mais um passo. */

const corpoDoTurno = bloco.slice(bloco.indexOf('function abrirTurno(tema) {'),
                                 bloco.indexOf('function maquinaDeEscrever'));

test('durante a espera, cada passo é acrescentado — a lista não é refeita', () => {
  const espera = corpoDoTurno.slice(corpoDoTurno.indexOf('passosDaEspera(tema).forEach'),
                                    corpoDoTurno.indexOf('function pararEspera'));
  assert.match(espera, /acrescentar\(/,
    'o laço da espera voltou a redesenhar a lista inteira a cada passo');
  assert.doesNotMatch(espera, /escrever\(/,
    '`escrever` apaga e refaz tudo: na espera ela reinicia a animação de '
    + 'entrada dos passos que já estão na tela');
});

test('acrescentar só encosta no passo que sai e no que entra', () => {
  const fn = corpoDoTurno.slice(corpoDoTurno.indexOf('function acrescentar('),
                                corpoDoTurno.indexOf('function escrever('));
  assert.doesNotMatch(fn, /innerHTML/,
    'acrescentar mexeu no innerHTML da lista: isso recria os passos de cima');
  assert.match(fn, /passos\.appendChild/,
    'o passo novo precisa entrar no fim da lista, embaixo dos que já estão lá');
  assert.match(fn, /classList\.remove\('mia-andando'\)/,
    'o passo anterior continuaria com o ponto pulsando: dois passos "em '
    + 'andamento" ao mesmo tempo');
  assert.match(fn, /mia-brilho/,
    'o brilho ficaria no passo que já passou');
});

test('a lista inteira só é trocada quando vira relato', () => {
  const vezes = (corpoDoTurno.match(/passos\.innerHTML\s*=/g) || []).length;
  assert.equal(vezes, 1,
    'apareceu outro lugar apagando a lista toda; a troca completa é só a do '
    + 'fim do turno');
  const escrever = corpoDoTurno.slice(corpoDoTurno.indexOf('function escrever('));
  assert.match(escrever.slice(0, 200), /passos\.innerHTML\s*=\s*''/,
    'a troca completa saiu de dentro de `escrever`');
});

/* ============================================================
   O RELATO REAL NÃO FALA EM NOME DE VARIÁVEL
   ============================================================
   Quando a resposta chega, os passos provisórios somem e entra o que o
   servidor diz ter feito. Um tipo de fonte sem tradução aparece cru: na
   primeira prova desta rodada a tela escreveu "Contexto: knowledge (4)"
   para uma pergunta sobre burnout. */

test('todo tipo de fonte que o servidor manda tem nome em português', () => {
  const servidor = lerFonte(
    new URL('../supabase/functions/mindagent-chat/index.ts', import.meta.url));
  const trecho = servidor.slice(servidor.indexOf('function sourceSummary'),
                                servidor.indexOf('function sourceSummary') + 700);
  const tipos = [...trecho.matchAll(/type:\s*"([a-z]+)"/g)].map((m) => m[1])
    .concat((trecho.match(/for \(const key of \[([^\]]+)\]/) || [, ''])[1]
      .match(/"([a-z]+)"/g) || []).map((s) => s.replace(/"/g, ''));
  assert.ok(tipos.length >= 5, 'não consegui ler os tipos de fonte no servidor');

  const tabela = bloco.slice(bloco.indexOf('var NOME_DA_FONTE'),
                             bloco.indexOf('function relatoDoTurno'));
  for (const tipo of tipos) {
    assert.match(tabela, new RegExp('\\b' + tipo + ':'),
      `o servidor manda fontes do tipo "${tipo}" e o bloco não traduz: a tela `
      + `escreveria "Contexto: ${tipo}" para quem perguntou`);
  }
});

test('pergunta vazia ou estranha não derruba o reconhecimento', () => {
  for (const entrada of [null, undefined, '', '   ', 42, {}, '???', '🙂']) {
    assert.doesNotThrow(() => temaDaPergunta(entrada),
      `"${String(entrada)}" quebrou o matcher: o turno inteiro cairia antes de começar`);
  }
});
