/* ============================================================
   A RESPOSTA SURGINDO — palavra a palavra, saindo do desfoque
   ============================================================
   A resposta chega inteira do servidor; isto não é streaming, é ritmo.
   Então tudo aqui é escolha de quanto tempo da pessoa a gente gasta com
   um efeito — e é por isso que os números ficam travados.

   O MECANISMO MUDOU em 28/10/2026, e estes testes mudaram com ele. Antes
   os nós de texto eram esvaziados e repostos LETRA a letra por um
   `setInterval`; agora a unidade é a PALAVRA, cada uma num `span`, e a
   entrada é animação de CSS com `animation-delay` escalonado. A troca veio
   do pedido de desfoque: para borrar uma letra é preciso um elemento para
   ela, e um elemento por letra numa resposta longa é mais de mil camadas
   de composição na tela de um celular.

   A troca pagou uma dívida velha. O efeito antigo já tinha sido
   `requestAnimationFrame`, que a aba escondida simplesmente não chama:
   quem trocava de aba enquanto a MIA respondia voltava para uma resposta
   VAZIA. Depois virou `setInterval`, que é estrangulado mas dispara. Agora
   o texto está no DOM desde o primeiro quadro e o que entra é a OPACIDADE:
   nenhuma aba esconde resposta, porque não há nada a repor.

   O que estes testes guardam é isso — e os números do ritmo, que são
   decisão de produto e não detalhe de implementação.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte, semComentarios } from './helpers/ler-fonte.mjs';

const bloco = lerFonte(new URL('../learnworlds/mia-embed.html', import.meta.url));
const maquina = bloco.slice(bloco.indexOf('function maquinaDeEscrever('),
                            bloco.indexOf('var emAndamento'));
const estilo = bloco.slice(bloco.indexOf('<style>'), bloco.indexOf('</style>'));

assert.ok(maquina.length > 500, 'não achei a máquina de escrever no bloco');

/* Os comentários daqui CITAM o que não se deve fazer: está escrito neles que
   o efeito não é `requestAnimationFrame` e que não há `preventDefault`. Um
   teste que procura essas palavras no texto inteiro acha a frase que explica
   a regra e acusa justamente o código que a cumpre. */
const codigo = semComentarios(maquina);

const formula = maquina.match(
  /var duracao = Math\.max\((\d+), Math\.min\((\d+), letras \* (\d+)\)\)/);
assert.ok(formula, 'a fórmula da duração mudou de forma e este teste ficou cego');
const [, piso, teto, porLetra] = formula.map(Number);

/* ============================================================
   O RITMO
   ============================================================ */

test('uma resposta típica leva segundos, não um piscar', () => {
  /* 923 caracteres é a mediana real das respostas da MIA (34 respostas
     medidas no banco em 27/10/2026). */
  const duracao = Math.max(piso, Math.min(teto, 923 * porLetra));
  assert.ok(duracao >= 6000,
    `a resposta mediana aparece em ${duracao}ms: rápido demais para acompanhar`);
});

test('quem manda na resposta longa é o teto, não a taxa', () => {
  /* Isto está aqui para não se perder: mexer no ms por letra não muda nada
     para a resposta típica dela, porque o teto corta antes. Quando a queixa
     for "está rápido demais", é o teto que precisa subir. */
  const mediana = 923 * porLetra;
  assert.ok(mediana > teto,
    `a resposta mediana (923 letras) dura ${mediana}ms pela taxa e o teto é `
    + `${teto}ms: a taxa passou a mandar, e quem mexer no teto achando que `
    + 'muda o ritmo vai se enganar');
});

test('o efeito não prende a leitura de um texto que já chegou', () => {
  /* O teto cresceu de 1,8s para 12s ao longo desta lane. Ele só pode ser
     deste tamanho porque existe a saída por toque — sem ela, doze segundos
     seriam prisão, e o número certo seria outro. Os dois andam juntos: quem
     derrubar um precisa rever o outro. */
  assert.ok(teto <= 15000,
    `o teto de ${teto}ms cobra tempo demais da pessoa por um texto que já está `
    + 'na mão dela');
  assert.match(codigo, /destino\.addEventListener\('click'/,
    `com teto de ${teto}ms e sem como pular, o efeito vira prisão`);
});

test('uma resposta curta não some antes de ser vista', () => {
  assert.ok(piso >= 500,
    `"Claro, posso ajudar." apareceria em ${piso}ms — some antes do olho pegar`);
});

test('a última palavra cabe dentro da duração, não começa nela', () => {
  assert.match(codigo, /corrida = Math\.max\(0, duracao - SURGIR_MS\)/,
    'o escalonamento voltou a usar a duração inteira: a última palavra começa '
    + 'a surgir quando o efeito já devia ter acabado');
});

/* ============================================================
   NENHUMA ABA ESCONDE RESPOSTA
   ============================================================
   Esta é a regra mais cara da lane: já custou uma resposta VAZIA em teste,
   e custaria a resposta do aluno que abre o vídeo da aula na aba ao lado. */

test('o texto está no DOM desde o início — o que entra é a opacidade', () => {
  assert.doesNotMatch(codigo, /nodeValue\s*=\s*''/,
    'o texto voltou a ser esvaziado e reposto: se o efeito não rodar, a '
    + 'resposta fica em branco na tela da pessoa');
  assert.match(estilo, /@keyframes mia-surge[\s\S]{0,160}opacity: 1/,
    'a animação deixou de ser de opacidade; se ela não revela o texto que já '
    + 'está lá, alguma coisa precisa repor o texto — e é aí que ele some');
});

test('o efeito não depende de quadro de animação nem de relógio nosso', () => {
  assert.doesNotMatch(codigo, /requestAnimationFrame/,
    'o navegador não chama rAF em aba escondida: a resposta volta a sumir');
  assert.doesNotMatch(codigo, /setInterval/,
    'voltou um relógio nosso contando o efeito; quem conta o tempo é o CSS');
});

test('o estado final é do CSS, e a limpeza tem rede de segurança', () => {
  assert.match(estilo, /animation: mia-surge [^;]*both/,
    '`both` é o que segura o estado final da palavra quando a animação '
    + 'termina; sem ele a palavra volta a ficar invisível');
  assert.match(codigo, /garantia = setTimeout\(tudo,/,
    'sumiu a rede de segurança que tira a classe no fim do efeito');
});

/* ============================================================
   O DESFOQUE NÃO PODE FICAR NA TELA DEPOIS
   ============================================================ */

test('a classe do efeito sai quando ele acaba', () => {
  /* `filter`, mesmo em `blur(0)`, mantém uma camada de composição por
     palavra enquanto estiver aplicado. Numa resposta longa são centenas
     delas, e o celular paga por todas. */
  assert.match(codigo, /classList\.remove\('mia-escrevendo'\)/,
    'a classe fica no balão para sempre: cada palavra da conversa inteira '
    + 'continua custando uma camada de composição');
  assert.match(estilo, /\.mia-escrevendo \.mia-palavra \{[\s\S]{0,120}filter: blur/,
    'o desfoque deixou de estar preso à classe do efeito — e aí não há como '
    + 'tirá-lo da tela depois');
});

/* ============================================================
   NADA DO SERVIDOR VIRA MARCAÇÃO
   ============================================================ */

test('a palavra é montada com textContent', () => {
  const envolve = codigo.slice(codigo.indexOf("createElement('span')"),
                               codigo.indexOf('palavras.push'));
  assert.match(envolve, /\.textContent = parte/,
    'a palavra passou a ser escrita como HTML: o texto da resposta vira '
    + 'marcação dentro do balão');
  assert.doesNotMatch(envolve, /innerHTML/, 'innerHTML no caminho da palavra');
});

test('percorrer os filhos não pula metade deles', () => {
  /* Trocar um nó enquanto se percorre `childNodes` — que é coleção viva —
     salta o nó seguinte. Metade das palavras ficaria sem span, e metade da
     resposta apareceria de uma vez. */
  assert.match(codigo, /for \(var i = 0; i < no\.childNodes\.length; i\+\+\) filhos\.push/,
    'a lista de filhos deixou de ser copiada antes da troca');
});

/* ============================================================
   A SAÍDA
   ============================================================ */

test('um toque na resposta completa o texto', () => {
  assert.match(codigo, /function aoTocar\(\)\s*\{\s*tudo\(\); \}/,
    'o atalho precisa terminar o efeito');
  assert.match(codigo, /destino\.addEventListener\('click', aoTocar\)/,
    'não existe como completar o texto: quem quer só ler fica esperando');
});

test('o toque não atrapalha um link dentro da resposta', () => {
  assert.doesNotMatch(codigo, /preventDefault/,
    'cancelar o clique mataria os links que a MIA manda na resposta');
});

test('o atalho é desligado quando o texto termina', () => {
  assert.match(codigo, /removeEventListener\('click', aoTocar\)/,
    'o ouvinte fica preso na bolha depois do efeito acabar');
});

test('quem pediu menos movimento não recebe efeito nenhum', () => {
  const trecho = codigo.slice(codigo.indexOf('prefers-reduced-motion'));
  assert.ok(trecho.indexOf("classList.add('mia-escrevendo')") === -1
            || trecho.indexOf('return') < trecho.indexOf("classList.add('mia-escrevendo')"),
    'a classe do efeito é posta mesmo para quem desligou animação no sistema');
  assert.match(estilo, /prefers-reduced-motion[\s\S]{0,700}\.mia-escrevendo \.mia-palavra \{[\s\S]{0,120}opacity: 1/,
    'falta o segundo cinto no CSS: se a classe entrar por outro caminho, o '
    + 'texto fica borrado para quem pediu para nada se mexer');
});

/* ============================================================
   A FRENTE DE ONDA — texto grande não surge em fila indiana
   ============================================================
   Em fila, o atraso vem da ORDEM da palavra. Numa frase isso é certo;
   num bloco de dez linhas vira um ponto correndo sozinho pela página
   enquanto o resto espera, e o olho persegue o ponto em vez de ler.

   Na diagonal o atraso vem da POSIÇÃO: `linha + direita × ABERTURA`.
   Como a posição horizontal vale ABERTURA linhas, a frente toca
   ABERTURA + 1 linhas ao mesmo tempo.

   A função é medida pura — recebe retângulos e devolve milissegundos —,
   então o teste roda o CÓDIGO DO BLOCO com retângulos de mentira. Se
   alguém mexer na conta lá, é a conta mexida que responde aqui.
*/

const diagonalFonte = bloco.slice(bloco.indexOf('var ABERTURA_DIAGONAL'),
                                  bloco.indexOf('function maquinaDeEscrever('));
const { atrasosEmDiagonal, ABERTURA_DIAGONAL, LINHAS_PARA_DIAGONAL } = new Function(
  diagonalFonte + 'return { atrasosEmDiagonal: atrasosEmDiagonal,'
  + ' ABERTURA_DIAGONAL: ABERTURA_DIAGONAL,'
  + ' LINHAS_PARA_DIAGONAL: LINHAS_PARA_DIAGONAL };')();

/* Um parágrafo de mentira: `linhas` linhas de 5 palavras, numa caixa de
   400px de largura e linha de 24px. */
function paragrafo(linhas) {
  /* As palavras chegam perto da borda direita, como numa linha de texto de
     verdade. A primeira versão deste parágrafo parava em 70% da largura, e
     isso sozinho estreitava a frente de onda em uma linha inteira: a conta da
     diagonal é sobre ONDE a palavra está, então um parágrafo de mentira com
     margem que não existe mede outra coisa. */
  const LARGURA = 400, ALTURA_LINHA = 24, X = [0, 90, 180, 270, 360];
  const destino = { getBoundingClientRect: () => ({ top: 0, left: 0, width: LARGURA }) };
  const palavras = [];
  for (let l = 0; l < linhas; l++) {
    for (const x of X) {
      palavras.push({
        linha: l, x,
        getBoundingClientRect: () => ({ top: l * ALTURA_LINHA, left: x }),
      });
    }
  }
  return { destino, palavras };
}

test('texto curto continua em fila — não há diagonal numa frase', () => {
  const { destino, palavras } = paragrafo(LINHAS_PARA_DIAGONAL - 1);
  assert.equal(atrasosEmDiagonal(palavras, destino, 10000), null,
    'a diagonal entrou num texto de poucas linhas, onde ela não se percebe e '
    + 'só embaralha a ordem de leitura à toa');
});

test('texto grande ganha a diagonal', () => {
  const { destino, palavras } = paragrafo(LINHAS_PARA_DIAGONAL);
  assert.notEqual(atrasosEmDiagonal(palavras, destino, 10000), null);
});

test('mais de uma linha está surgindo ao mesmo tempo', () => {
  /* O pedido, na letra: mais de uma palavra, de mais de uma linha, por vez.
     Numa fila, duas palavras com atraso parecido são sempre vizinhas na
     mesma linha. */
  const { destino, palavras } = paragrafo(10);
  const atrasos = atrasosEmDiagonal(palavras, destino, 10000);
  /* "Ao mesmo tempo" é a duração da animação de uma palavra: enquanto ela
     dura, aquela palavra está visivelmente surgindo. Duas palavras com
     atrasos dentro dessa janela estão em movimento na mesma hora. */
  const JUNTAS_MS = 600;
  let maiorFrente = 0;
  atrasos.forEach((a) => {
    const linhasNaFrente = new Set(
      atrasos.map((b, i) => (Math.abs(b - a) <= JUNTAS_MS ? palavras[i].linha : null))
             .filter((l) => l !== null));
    maiorFrente = Math.max(maiorFrente, linhasNaFrente.size);
  });
  assert.ok(maiorFrente >= 3,
    `a frente mais larga toca ${maiorFrente} linha(s) de cada vez: com `
    + `ABERTURA = ${ABERTURA_DIAGONAL} ela devia tocar ${ABERTURA_DIAGONAL + 1}`);
});

test('a frente desce da direita de uma linha para a esquerda da de baixo', () => {
  /* É isto que faz a diagonal, e é uma troca consciente: a ordem ESTRITA de
     leitura cede. Sem a troca, a frente seria uma régua horizontal. */
  const { destino, palavras } = paragrafo(10);
  const atrasos = atrasosEmDiagonal(palavras, destino, 10000);
  const fimDaPrimeira = atrasos[4];
  const comecoDaSegunda = atrasos[5];
  assert.ok(comecoDaSegunda < fimDaPrimeira,
    'o começo da segunda linha só entra depois do fim da primeira: a frente '
    + 'virou régua horizontal e a diagonal sumiu');
});

test('o sentido geral é respeitado — o fim não vem antes do começo', () => {
  const { destino, palavras } = paragrafo(10);
  const atrasos = atrasosEmDiagonal(palavras, destino, 10000);
  assert.equal(atrasos[0], 0, 'a primeira palavra do bloco não abre o surgir');
  const ultimaLinha = atrasos.slice(-5);
  const primeiraLinha = atrasos.slice(0, 5);
  assert.ok(Math.min(...ultimaLinha) > Math.max(...primeiraLinha),
    'alguma palavra da última linha surge antes de alguma da primeira');
});

test('o texto grande leva o mesmo tempo que levava em fila', () => {
  const { destino, palavras } = paragrafo(10);
  const atrasos = atrasosEmDiagonal(palavras, destino, 10000);
  assert.equal(Math.max(...atrasos), 10000,
    'a onda não foi esticada até o fim da corrida: o texto grande passou a '
    + 'levar um tempo diferente do que a duração promete');
  assert.ok(Math.min(...atrasos) === 0);
});

test('a diagonal é medida antes de a classe entrar', () => {
  /* A classe põe `translateY` nas palavras, e `getBoundingClientRect`
     devolve a posição JÁ transformada: mediria o lugar de onde elas vêm. */
  assert.ok(codigo.indexOf('atrasosEmDiagonal(palavras, destino, corrida)')
            < codigo.indexOf("classList.add('mia-escrevendo')"),
    'a medida sai depois da classe: a diagonal é calculada sobre a posição '
    + 'deslocada das palavras');
});

test('negrito e link no meio da frase não viram linhas só deles', () => {
  /* Palavras da mesma linha não têm o topo exatamente igual quando há
     `<strong>` ou `<a>` no meio; sem o degrau de arredondamento, cada uma
     dessas viraria uma linha de uma palavra só e a diagonal se desmancharia. */
  const destino = { getBoundingClientRect: () => ({ top: 0, left: 0, width: 400 }) };
  const palavras = [];
  for (let l = 0; l < 6; l++) {
    for (let i = 0; i < 5; i++) {
      /* meio pixel de diferença, como o navegador devolve de verdade */
      const top = l * 24 + (i === 2 ? 0.5 : 0);
      palavras.push({ getBoundingClientRect: () => ({ top, left: i * 70 }) });
    }
  }
  assert.notEqual(atrasosEmDiagonal(palavras, destino, 10000), null,
    'as linhas se multiplicaram com a diferença de meio pixel');
});

/* ============================================================
   O BALÃO SOBE ANTES DE A RESPOSTA SURGIR
   ============================================================ */

const subir = bloco.slice(bloco.indexOf('function subirBalao('),
                          bloco.indexOf('function bolha('));

test('existe espaço embaixo para o balão poder alcançar o topo', () => {
  /* Sem isto o pedido de subir não faz nada: a resposta é o último elemento
     da conversa, então não há conteúdo abaixo dela para onde rolar. */
  assert.match(semComentarios(subir), /paddingBottom = Math\.round\(base \+ falta\)/,
    'sumiu o espaço calculado embaixo da conversa: o balão pede para subir e '
    + 'fica onde está');
});

test('o espaço some quando chega pergunta nova', () => {
  const perguntar = bloco.slice(bloco.indexOf('function perguntar(texto)'),
                                bloco.indexOf('function ajustarAltura'));
  assert.match(semComentarios(perguntar), /mensagens\.style\.paddingBottom = ''/,
    'o espaço da resposta anterior fica para trás e a pergunta nova aparece '
    + 'com um vão embaixo');
});

test('a resposta sobe antes de a primeira palavra surgir', () => {
  assert.ok(codigo.indexOf('if (aoMontar) aoMontar();')
            < codigo.indexOf("classList.add('mia-escrevendo')"),
    'o texto começa a surgir antes de o balão subir: a primeira palavra '
    + 'aparece no pé da tela');
});
