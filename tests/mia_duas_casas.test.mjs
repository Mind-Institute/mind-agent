/* ============================================================
   A MIA MORA EM DUAS CASAS, E ELAS TÊM DE CONCORDAR
   ============================================================
   O desenho da MIA existe em dois lugares:

   - `learnworlds/mia-embed.html`, o bloco COLADO dentro do LearnWorlds —
     sem build, sem import, ES5 num arquivo só;
   - `mia-turno.js`, módulo do app, servido em
     `/?origem_codigo=institute_learnworlds`.

   Isso é duplicação de verdade. Ela existe porque os dois lados não podem
   compartilhar arquivo — um é colado na página de terceiro —, e não porque
   alguém achou melhor assim.

   Enquanto as duas existirem, o perigo não é o código repetido: é as duas
   DIVERGIREM em silêncio. Mudar a cadência dos passos num lado e não no
   outro não quebra nada, não dá erro, e produz duas MIAs com
   comportamentos diferentes para a mesma pessoa — uma na aula, outra no
   link. Ninguém descobre até alguém reclamar.

   Este arquivo é o alarme. Ele não cobra código igual (um é ES5, o outro
   não); cobra as DECISÕES iguais: os tempos, os temas do acervo, os nomes
   que a pessoa lê e os números do surgir.

   A saída definitiva é gerar o bloco a partir do módulo no
   `build-cloudflare.mjs`, ou o LearnWorlds carregar a página hospedada num
   iframe. As duas são decisão de arquitetura; até lá, vale o alarme.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte, semComentarios } from './helpers/ler-fonte.mjs';

const bloco = lerFonte(new URL('../learnworlds/mia-embed.html', import.meta.url));
const modulo = lerFonte(new URL('../mia-turno.js', import.meta.url));

/* ============================================================
   OS TEMPOS DA ESPERA
   ============================================================ */

function roteiros(fonte) {
  const inicio = fonte.indexOf('function passosDaEspera(');
  const fim = fonte.indexOf('ultimoTurno = null');
  assert.ok(inicio > 0 && fim > inicio,
    'não achei os roteiros: `passosDaEspera` ou `ultimoTurno` mudaram de nome '
    + 'e este teste ficou cego');
  /* Sem os comentários: os dois arquivos explicam a mesma decisão com
     palavras diferentes, e CITAM as frases antigas para dizer por que elas
     saíram. Comparar comentário faria este teste acusar divergência onde há
     só prosa — e é o código que precisa concordar. */
  return semComentarios(fonte.slice(inicio, fim));
}

function cadencia(fonte) {
  return [...roteiros(fonte).matchAll(/\[(\d+),/g)].map((m) => Number(m[1]));
}

test('os passos entram nos mesmos tempos nas duas casas', () => {
  const noBloco = cadencia(bloco);
  const noModulo = cadencia(modulo);
  assert.ok(noBloco.length >= 6, 'não consegui ler a cadência do bloco');
  assert.deepEqual(noModulo, noBloco,
    'a cadência dos passos divergiu: a MIA da aula e a MIA do link passaram a '
    + 'esperar em ritmos diferentes');
});

test('os passos dizem as mesmas frases nas duas casas', () => {
  /* `[^'\n]` e não `[^']`: sem proibir a quebra de linha, o regex emparelha a
     aspa de FECHO de uma frase com a de ABERTURA da seguinte e captura a
     indentação entre as duas. A primeira versão deste teste fazia isso e
     passava por sorte, porque os dois arquivos tinham o mesmo recuo — quando
     o bloco ganhou um nível a mais, ele acusou divergência em 15 "frases" que
     eram espaço em branco. O que precisa bater é o que a pessoa lê. */
  const frases = (fonte) =>
    [...roteiros(fonte).matchAll(/'([^'\n]{4,})'/g)].map((m) => m[1]);
  assert.deepEqual(frases(modulo), frases(bloco),
    'a tela diz coisas diferentes nos dois lugares enquanto ela pensa');
});

/* ============================================================
   OS TEMAS DO ACERVO
   ============================================================ */

function temas(fonte) {
  const trecho = fonte.slice(fonte.indexOf('TEMA_POR_PALAVRA = ['),
                             fonte.indexOf('function semAcento'));
  return [...trecho.matchAll(/\['([^']+)',\s*'([^']+)'\]/g)].map((m) => m[1] + ' → ' + m[2]);
}

test('a tabela de temas é a mesma, e na mesma ordem', () => {
  const noBloco = temas(bloco);
  const noModulo = temas(modulo);
  assert.ok(noBloco.length > 50, 'não consegui ler a tabela de temas do bloco');
  /* A ORDEM faz parte da decisão: a primeira palavra que casa vence, então o
     específico vem antes do geral. Duas tabelas com os mesmos pares em ordens
     diferentes respondem coisas diferentes para a mesma pergunta. */
  assert.deepEqual(noModulo, noBloco,
    'as tabelas de tema divergiram: a mesma pergunta ganha assuntos diferentes '
    + 'na aula e no link');
});

/* ============================================================
   OS NOMES QUE A PESSOA LÊ
   ============================================================ */

function dicionario(fonte, nome) {
  const inicio = fonte.indexOf(nome);
  const trecho = fonte.slice(inicio, fonte.indexOf('}', inicio));
  return [...trecho.matchAll(/(\w+):\s*'([^']+)'/g)].map((m) => m[1] + '=' + m[2]).sort();
}

test('as ferramentas e as fontes têm os mesmos nomes nas duas casas', () => {
  assert.deepEqual(dicionario(modulo, 'NOME_DA_FERRAMENTA'),
                   dicionario(bloco, 'NOME_DA_FERRAMENTA'),
    'o relato do que ela fez mudou de palavra num dos lados');
  assert.deepEqual(dicionario(modulo, 'NOME_DA_FONTE'),
                   dicionario(bloco, 'NOME_DA_FONTE'),
    'um tipo de fonte tem nome em português de um lado e não do outro — e o '
    + 'que não é traduzido aparece cru para a pessoa');
});

/* ============================================================
   OS NÚMEROS DO SURGIR
   ============================================================ */

test('a resposta surge no mesmo ritmo nas duas casas', () => {
  const ritmo = (fonte) => {
    const m = fonte.match(/Math\.max\((\d+), Math\.min\((\d+), letras \* (\d+)\)\)/);
    assert.ok(m, 'não achei a fórmula da duração');
    return { piso: m[1], teto: m[2], porLetra: m[3] };
  };
  assert.deepEqual(ritmo(modulo), ritmo(bloco),
    'o texto aparece em velocidades diferentes na aula e no link');
});

test('os números da diagonal e do surgir são os mesmos', () => {
  for (const constante of ['SURGIR_MS', 'PASSO_MAX_MS',
                           'ABERTURA_DIAGONAL', 'LINHAS_PARA_DIAGONAL']) {
    const valor = (fonte) => {
      const m = fonte.match(new RegExp(constante + '\\s*=\\s*(\\d+)'));
      assert.ok(m, `não achei ${constante}`);
      return m[1];
    };
    assert.equal(valor(modulo), valor(bloco),
      `${constante} divergiu entre o bloco e o módulo do app`);
  }
});

test('o desfoque e a curva são os mesmos nas duas folhas', () => {
  const folha = lerFonte(new URL('../styles.css', import.meta.url));
  const surge = (fonte) => {
    const m = fonte.match(/opacity: 0; filter: blur\((\d+)px\); transform: translateY\((\d+)px\);\s*\n\s*animation: mia-surge ([^;]+);/);
    assert.ok(m, 'não achei a regra do surgir');
    /* Espaço dentro do `cubic-bezier` não é divergência de desenho: as duas
       folhas seguem a formatação da casa delas. O que precisa bater é o
       valor. */
    return { desfoque: m[1], subida: m[2], animacao: m[3].replace(/\s+/g, '') };
  };
  assert.deepEqual(surge(folha), surge(bloco),
    'o surgir da resposta tem desenho diferente na aula e no link');
});

/* ============================================================
   O QUE A PORTA LIGA
   ============================================================ */

test('só a porta da MIA recebe o turno dela', () => {
  const app = lerFonte(new URL('../app.js', import.meta.url));
  assert.match(app, /const TURNO_DA_MIA = PORTA\?\.pele === 'mia'/,
    'o turno da MIA deixou de ser decidido pela pele: o Concierge do Summit '
    + 'passa a se apresentar como um produto à parte, que ele não é');
  assert.match(app, /if \(TURNO_DA_MIA\) return responderComoMia/,
    'o caminho da MIA saiu de `responder`');
});
