/* Contrato de geometria do tour.
   ============================================================
   Os alvos do tour são escritos em PORCENTAGEM e desenhados sobre a caixa
   que contém a foto. Isso só aponta para o lugar certo enquanto a caixa
   tiver a mesma proporção da captura: aí "65,7% da caixa" e "65,7% da
   foto" são o mesmo ponto.

   Quando as proporções divergem, `object-fit: cover` amplia a captura para
   preencher a caixa e corta o que sobra. A foto desce, o anel fica onde
   estava, e o erro CRESCE com a profundidade do alvo — perto do topo é
   invisível, no rodapé é um dedo inteiro. Foi o que aconteceu: o anel de
   "Reservar lugar", a 65,7%, caía ~50px acima, em cima da linha "Reserva
   exclusiva por horário". Falha silenciosa: nada quebra, nada loga, o
   tour só ensina o gesto errado.

   Dois pilares seguram o alinhamento, e este arquivo trava os dois.

   Determinístico e offline: lê o fonte e o cabeçalho dos arquivos.

     node --test tests/tour_geometria.test.mjs
*/
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');
const css = readFileSync(join(RAIZ, 'styles.css'), 'utf8');
const app = readFileSync(join(RAIZ, 'app.js'), 'utf8');

/* A proporção que todo o tour assume. Mudar aqui é mudar todas as
   coordenadas de TELAS — por isso o número aparece nos dois lugares. */
const LARGURA = 780;
const ALTURA = 1421;

/* Dimensões de um WebP sem dependência externa: as capturas do tour são
   VP8X (estendido) ou VP8 (com perdas), e os dois guardam o tamanho em
   lugares diferentes. */
function tamanhoWebp(buf) {
  assert.equal(buf.toString('ascii', 0, 4), 'RIFF');
  assert.equal(buf.toString('ascii', 8, 12), 'WEBP');
  const tipo = buf.toString('ascii', 12, 16);
  if (tipo === 'VP8X') {
    return { w: buf.readUIntLE(24, 3) + 1, h: buf.readUIntLE(27, 3) + 1 };
  }
  if (tipo === 'VP8 ') {
    /* pula o chunk header (8B) e o frame tag (3B) + start code (3B) */
    return { w: buf.readUInt16LE(26) & 0x3fff, h: buf.readUInt16LE(28) & 0x3fff };
  }
  throw new Error('formato WebP não previsto neste contrato: ' + tipo);
}

test('a caixa da foto nasce com a proporção da captura', () => {
  /* Sem isto o alinhamento passa a depender do formato do aparelho de
     quem abre o tour: medimos 0,646 a 360px, 0,606 a 393px e 0,581 a
     430px de largura — nenhuma delas igual a 0,549 da captura. Nenhum
     ajuste de coordenada resolveria, porque o erro muda com a tela. */
  assert.match(css, /\.conteudo \{[^}]*aspect-ratio: 780 \/ 1421;/s,
    '`.conteudo` deixou de declarar a proporção da captura — o anel volta a errar o alvo');
  assert.match(css, /\.conteudo \{[^}]*margin: auto;/s,
    '`.conteudo` deixou de se centrar na sobra do quadro');
  assert.match(css, /\.conteudo \{[^}]*max-width: 100%; max-height: 100%;/s,
    '`.conteudo` perdeu o teto e pode transbordar o quadro em vez de caber nele');

  /* A proporção não pode vir de `.fone`: ele declara 780/1570 e NÃO
     consegue honrar, porque a barra de abas tem largura mínima própria e
     impede o quadro de estreitar, então `max-height` apara a altura. */
  assert.match(css, /\.frame \{[^}]*position: relative/s,
    '`.frame` deixou de ser a âncora do posicionamento absoluto da foto');
});

test('toda captura do tour tem exatamente 780x1421', () => {
  /* Uma captura com outro tamanho reintroduz o desencontro em UMA tela
     só, o que é ainda mais difícil de ver do que o bug original. */
  const dir = join(RAIZ, 'assets', 'tour');
  const arquivos = readdirSync(dir).filter((n) => n.endsWith('.webp'));
  assert.ok(arquivos.length >= 15, 'as capturas do tour sumiram de assets/tour');
  for (const nome of arquivos) {
    const { w, h } = tamanhoWebp(readFileSync(join(dir, nome)));
    assert.deepEqual({ w, h }, { w: LARGURA, h: ALTURA },
      `assets/tour/${nome} está ${w}x${h}; o tour inteiro assume ${LARGURA}x${ALTURA}`);
  }
});

test('os alvos continuam escritos em porcentagem', () => {
  /* O contrato acima só vale porque a coordenada é relativa. Um alvo em
     px passaria a depender do tamanho do quadro na tela de quem abre. */
  assert.match(app, /b\.style\.left = a\.x \+ '%';/,
    'o alvo deixou de ser posicionado em % — a coordenada vira refém do tamanho da tela');
  assert.match(app, /b\.style\.top = a\.y \+ '%';/, 'o topo do alvo saiu de %');
  assert.match(app, /b\.style\.width = a\.w \+ '%';/, 'a largura do alvo saiu de %');
  assert.match(app, /b\.style\.height = a\.h \+ '%';/, 'a altura do alvo saiu de %');
});
