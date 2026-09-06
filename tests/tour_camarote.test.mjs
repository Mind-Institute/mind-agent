/* Contrato do tour do Camarote.
   ============================================================
   O ladrilho "Masterclass Heineken" NÃO existe no Menu de quem não tem
   Camarote. Por isso este roteiro não é uma variação cosmética: mostrá-lo
   à pessoa errada ensina um caminho que ela não tem.

   Determinístico e offline: lê o fonte, não sobe navegador nem app.

     node --test tests/tour_camarote.test.mjs
*/
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');
const app = readFileSync(join(RAIZ, 'app.js'), 'utf8');

/* O trecho do roteiro, para afirmar sobre ele sem pegar o arquivo inteiro. */
const roteiroCamarote = app.slice(
  app.indexOf('reserva_camarote: {'),
  app.indexOf('let roteiroAtual'),
);
const roteiroPadrao = app.slice(
  app.indexOf('  reserva: {'),
  app.indexOf('  mapa: {'),
);

test('a escolha do roteiro é fail-closed: só Camarote confirmado entra', () => {
  /* Sem `?email=` na URL, sem rede ou com tipo que o app não reconhece,
     `ingressoDoParticipante` é null. Nesses casos a pessoa TEM de cair no
     roteiro de todo mundo — errar para o outro lado mostra a um VIP um
     menu que ele não tem. */
  assert.match(app, /function ehCamarote\(\) \{\s*return String\(ingressoDoParticipante \|\| ''\)/,
    'a checagem do Camarote deixou de tolerar tipo ausente');
  assert.match(app, /\.trim\(\)\.toLowerCase\(\) === 'camarote'/,
    'a checagem deixou de comparar o tipo exato do espelho');
  assert.doesNotMatch(app, /ehCamarote\(\)[^\n]*\|\|[^\n]*'reserva_camarote'/,
    'o roteiro do Camarote virou padrão em vez de exceção');
  assert.match(app, /qual = qual \|\| \(ehCamarote\(\) \? 'reserva_camarote' : 'reserva'\)/,
    'a seleção por ingresso saiu de `abrirTourCompleto`, ou deixou de respeitar o roteiro pedido');
});

test('o roteiro de quem não tem Camarote não alcança nenhuma tela da Heineken', () => {
  /* A separação é o contrato inteiro: se `reserva` conseguisse chegar a
     uma tela `hnk-`, o tour ensinaria o menu da Heineken a quem não o vê. */
  assert.doesNotMatch(roteiroPadrao, /hnk-/,
    'o roteiro padrão passou a referenciar uma tela do Camarote');
  assert.doesNotMatch(roteiroPadrao, /abas:/,
    'o roteiro padrão passou a redirecionar abas, o que é do Camarote');
  assert.match(roteiroCamarote, /abas: \{ menu: 'hnk-menu', minha: 'hnk-minha-agenda' \}/,
    'o Camarote deixou de redirecionar as abas e cairia nas capturas de quem não o tem');
});

test('o Camarote ensina os dois caminhos e termina nos dois juntos', () => {
  /* Arenas e workshops pela Programação, masterclass pelo menu da
     Heineken, e o fecho é a agenda com as duas — que é a razão do tour. */
  assert.match(roteiroCamarote, /tela: 'detalhe', alvo: 'reservar'/,
    'sumiu o passo de reservar workshop/arena, que é igual para todos');
  assert.match(roteiroCamarote, /tela: 'hnk-masterclass', alvo: 'reservar'/,
    'sumiu o passo de reservar a masterclass');
  assert.match(roteiroCamarote, /tela: 'hnk-minha-agenda'/,
    'o tour deixou de terminar na agenda com as duas reservas');
});

test('a missão que fecha é a do roteiro, não um id preso ao alvo', () => {
  /* "Reservar lugar", no detalhe da sessão, serve aos dois roteiros. Com o
     id escrito dentro do alvo era preciso duplicar a tela só para trocar o
     nome da missão. */
  assert.doesNotMatch(app, /missao: '/,
    'voltou id de missão dentro de um alvo, prendendo a tela a um roteiro');
  assert.match(app, /const telaDoToque = telaAtual;/,
    'a tela do toque deixou de ser guardada — `concluir` roda depois de `irPara`, quando `telaAtual` já mudou');
  assert.match(app, /m\.tela === telaDoToque && m\.alvo === a\.id/,
    'a conclusão da missão deixou de casar tela + alvo com a missão atual');
});

test('as cinco capturas do Camarote existem', () => {
  /* Sem o arquivo, `prontaTela` desiste em 3s e a etapa fica sem foto —
     falha silenciosa, que é a pior num tour que existe para mostrar a
     tela real. */
  for (const nome of ['hnk-menu', 'hnk-agenda', 'hnk-masterclass',
                      'hnk-masterclass-ok', 'hnk-minha-agenda']) {
    assert.ok(existsSync(join(RAIZ, 'assets', 'tour', nome + '.webp')),
      'falta a captura assets/tour/' + nome + '.webp');
    assert.match(app, new RegExp("'" + nome + "': \\{"),
      'a tela ' + nome + ' saiu de TELAS');
  }
});

test('a barra de abas respeita o roteiro', () => {
  assert.match(app, /irPara\(destinoDaAba\(aba\), 'troca'\)/,
    'a aba voltou a ir sempre para o destino fixo, ignorando o roteiro');
  assert.match(app, /return \(r && r\.abas && r\.abas\[aba\.id\]\) \|\| aba\.vai;/,
    'o desvio de aba deixou de cair no destino de sempre quando o roteiro não pede outro');
});
