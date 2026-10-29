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
const inicio = bloco.indexOf('function passosDaEspera(');
const fim = bloco.indexOf('var NOME_DA_FERRAMENTA');
assert.ok(inicio > 0 && fim > inicio,
  'não achei o trecho dos passos no bloco: `passosDaEspera` ou '
  + '`NOME_DA_FERRAMENTA` mudaram de nome e este teste ficou cego');

const { passosDaEspera, temaDaPergunta, TEMA_POR_PALAVRA,
        situacaoDoTurno, lembrarDoTurno } = new Function(
  bloco.slice(inicio, fim)
  + 'return { passosDaEspera: passosDaEspera, temaDaPergunta: temaDaPergunta,'
  + ' TEMA_POR_PALAVRA: TEMA_POR_PALAVRA, situacaoDoTurno: situacaoDoTurno,'
  + ' lembrarDoTurno: lembrarDoTurno };')();

/* Os três roteiros, para os testes de cadência não precisarem repetir isto. */
const ROTEIROS = {
  abre: passosDaEspera({ modo: 'abre', tema: null }),
  aprofunda: passosDaEspera({ modo: 'aprofunda', tema: 'burnout' }),
  muda: passosDaEspera({ modo: 'muda', tema: 'liderança' }),
};

/* O texto de um passo, seja ele string ou o pedaço com tema destacado. */
function frase(p) {
  const t = p[1];
  return typeof t === 'string' ? t : t.antes + t.destaque + (t.depois || '');
}

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

test('os três roteiros vão até perto do teto do turno', () => {
  for (const [modo, passos] of Object.entries(ROTEIROS)) {
    const ultimo = passos[passos.length - 1][0];
    assert.ok(ultimo >= 30000,
      `no roteiro "${modo}" o último passo entra aos ${ultimo / 1000}s e o turno `
      + 'complexo vai até 45s: a lista congela no meio da espera');
    assert.ok(ultimo < 45000,
      `no roteiro "${modo}" o último passo entra depois do teto de 45s do `
      + 'servidor — nunca seria visto');
  }
});

test('nenhum trecho da espera fica mudo por muito tempo', () => {
  for (const [modo, passos] of Object.entries(ROTEIROS)) {
    for (let i = 1; i < passos.length; i++) {
      const silencio = passos[i][0] - passos[i - 1][0];
      assert.ok(silencio <= 12000,
        `no roteiro "${modo}", ${silencio / 1000}s parados depois de `
        + `"${frase(passos[i - 1])}": é esse silêncio que vira sensação de travado`);
    }
  }
});

test('os passos entram em ordem crescente e o primeiro é imediato', () => {
  for (const [modo, passos] of Object.entries(ROTEIROS)) {
    assert.equal(passos[0][0], 0,
      `no roteiro "${modo}" a primeira linha não aparece junto com a pergunta`);
    for (let i = 1; i < passos.length; i++) {
      assert.ok(passos[i][0] > passos[i - 1][0],
        `no roteiro "${modo}" dois passos caem no mesmo instante`);
    }
  }
});

/* ============================================================
   A TELA SÓ DIZ O QUE O SERVIDOR FAZ
   ============================================================
   As ferramentas da MIA são duas — `buscar_intelligence` e
   `ler_intelligence` — e o relato real do turno diz PROCUROU e LEU. A
   primeira versão destes passos narrava três atos que não existem:
   "Abrindo as fichas das sessões", "Vendo o que cada palestrante disse" e
   "Conferindo em que minuto aparece". Detalhe inventado para a lista ficar
   comprida, e o Vinícius viu rodando.

   As transcrições até têm marca de tempo (55 de 55, conferido no banco em
   29/10/2026), mas ela LÊ o documento — não vai conferir minuto nenhum. */

test('nenhum passo narra um ato que o servidor não relata', () => {
  const proibidas = [/ficha/i, /minuto/i, /palestrante disse/i];
  for (const [modo, passos] of Object.entries(ROTEIROS)) {
    for (const p of passos) {
      for (const proibida of proibidas) {
        assert.doesNotMatch(frase(p), proibida,
          `o roteiro "${modo}" voltou a afirmar um ato que o servidor não faz: `
          + `"${frase(p)}"`);
      }
    }
  }
});

test('os três atos reais aparecem, e nessa ordem', () => {
  for (const [modo, passos] of Object.entries(ROTEIROS)) {
    const frases = passos.map(frase).join(' | ');
    assert.match(frases, /acervo/i,
      `o roteiro "${modo}" não diz que ela foi ao acervo, e ela sempre vai`);
    assert.match(frases, /Escrevendo a resposta/,
      `o roteiro "${modo}" não chega a escrever`);
    const procura = passos.findIndex((p) => /acervo/i.test(frase(p)));
    const escreve = passos.findIndex((p) => /Escrevendo a resposta/.test(frase(p)));
    assert.ok(procura < escreve,
      `no roteiro "${modo}" ela escreve antes de procurar`);
  }
});

/* ============================================================
   A SITUAÇÃO DO TURNO
   ============================================================
   Três turnos medidos contra o servidor real em 29/10/2026:

       turno              procurou  leu   contexto                  tempo
       abre o assunto        1×     1×    acervo (4)                 29s
       aprofunda o mesmo     1×     3×    palestrantes (2), acervo   36s
       muda de assunto       1×     3×    palestrantes (1)           34s

   A medição derruba a suposição natural: ela NÃO responde do contexto
   quando a pessoa se aprofunda — volta ao acervo toda vez. Por isso o
   roteiro de aprofundamento continua indo ao acervo; o que ele não pode é
   falar como se fosse a primeira pergunta. */

test('a primeira pergunta da conversa abre o assunto', () => {
  assert.equal(situacaoDoTurno('o que falaram sobre burnout?').modo, 'abre');
});

test('aprofundar sem nomear assunto não é assunto novo', () => {
  /* O caso que fazia a tela repetir a abertura: "me aprofunda nisso" não
     traz tema nenhum, e antes caía no roteiro de primeira pergunta. */
  lembrarDoTurno({ tema: 'segurança psicológica' }, { sources: [] });
  for (const seguida of ['me aprofunda nisso', 'e daí?', 'me dá um exemplo concreto']) {
    const s = situacaoDoTurno(seguida);
    assert.equal(s.modo, 'aprofunda', `"${seguida}" devia ser aprofundamento`);
    assert.equal(s.tema, 'segurança psicológica',
      'o aprofundamento perdeu o assunto que estava em jogo');
  }
});

test('repetir o mesmo assunto também é aprofundar', () => {
  lembrarDoTurno({ tema: 'burnout' }, { sources: [] });
  assert.equal(situacaoDoTurno('mais sobre burnout, por favor').modo, 'aprofunda');
});

test('trazer outro assunto muda de assunto', () => {
  lembrarDoTurno({ tema: 'burnout' }, { sources: [] });
  const s = situacaoDoTurno('e sobre NR-1, o que disseram?');
  assert.equal(s.modo, 'muda');
  assert.equal(s.tema, 'NR-1 e riscos psicossociais');
});

test('o roteiro de aprofundamento não repete a abertura', () => {
  const abre = ROTEIROS.abre.map(frase);
  const aprofunda = ROTEIROS.aprofunda.map(frase);
  const repetidas = aprofunda.filter((f) => abre.includes(f)
    && !/Escrevendo a resposta/.test(f));
  assert.deepEqual(repetidas, [],
    'o aprofundamento repete frases da abertura: é isso que faz a tela parecer '
    + 'que ela começou do zero de novo');
});

test('o aprofundamento diz que está voltando, e cita a conversa', () => {
  const frases = ROTEIROS.aprofunda.map(frase).join(' | ');
  assert.match(frases, /Voltando ao acervo/,
    'a medição mostra que ela volta ao acervo: a tela precisa dizer isso');
  assert.match(frases, /já te respondi/,
    'o turno chega com a conversa junto, e é isso que distingue o '
    + 'aprofundamento de uma pergunta nova');
});

test('mudar de assunto é anunciado, para não parecer que ela ignorou', () => {
  assert.match(ROTEIROS.muda.map(frase).join(' | '), /Assunto novo/);
});

test('palestrante no passo só entra quando o turno anterior trouxe um', () => {
  /* Não é chute: `sources` do turno anterior é relato do servidor. */
  lembrarDoTurno({ tema: 'liderança' }, { sources: [{ type: 'speakers', count: 2 }] });
  const com = passosDaEspera(situacaoDoTurno('e como isso aparece na prática?'))
    .map(frase).join(' | ');
  assert.match(com, /sessões e os palestrantes que citei/);

  lembrarDoTurno({ tema: 'liderança' }, { sources: [{ type: 'knowledge', count: 3 }] });
  const sem = passosDaEspera(situacaoDoTurno('e como isso aparece na prática?'))
    .map(frase).join(' | ');
  assert.doesNotMatch(sem, /palestrantes que citei/,
    'a tela afirmou palestrante sem o servidor ter trazido nenhum');
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
  const passo = passosDaEspera({ modo: 'abre', tema: 'burnout' })[1][1];
  assert.equal(typeof passo, 'object',
    'o tema precisa vir em pedaço próprio, para ser destacado sem virar HTML');
  assert.equal(passo.destaque, 'burnout');
  assert.match(passo.antes + passo.destaque + passo.depois,
    /Procurando sobre burnout no acervo do Summit/);
});

test('sem tema reconhecido, o passo fica genérico em vez de chutar', () => {
  const passo = passosDaEspera({ modo: 'abre', tema: null })[1][1];
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

const corpoDoTurno = bloco.slice(bloco.indexOf('function abrirTurno(situacao) {'),
                                 bloco.indexOf('function maquinaDeEscrever'));

test('durante a espera, cada passo é acrescentado — a lista não é refeita', () => {
  const espera = corpoDoTurno.slice(corpoDoTurno.indexOf('passosDaEspera(situacao).forEach'),
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
