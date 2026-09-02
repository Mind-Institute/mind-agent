/* ============================================================
   O TECLADO — ancorar o app no viewport VISUAL
   ============================================================

   O QUE ESTAVA ERRADO, e por que não era estético.

   O app é uma coluna flex de altura `100dvh` com `overflow: hidden`. Isso
   funciona enquanto a altura da janela é a altura visível. No iOS não é: o
   teclado NÃO encolhe o viewport de layout e NÃO muda `100dvh` nem
   `window.innerHeight`. Ele encolhe só o viewport VISUAL.

   O resultado é que a página continua sendo desenhada com a altura inteira —
   header, conversa e campo somam mais do que sobrou na tela — e o Safari
   resolve isso do jeito dele: ROLA O VIEWPORT DE LAYOUT para trazer o campo
   focado para dentro da área visível. Quem sobe não é o campo; é a página. Por
   isso o header some para cima, o layout parece recalculado e aparece faixa
   vazia onde o navegador acha que ainda há conteúdo.

   Ou seja: o salto não é um bug de estilo que se conserta com margem. É o
   navegador compensando uma altura que mentimos para ele.

   O CONSERTO É PARAR DE MENTIR. A altura do app passa a vir de
   `visualViewport.height`, que é a única medida que já desconta o teclado. Com
   a caixa do app do tamanho exato do que se vê, o Safari não tem o que
   compensar e não rola nada. O header fica onde está, e quem encolhe é só a
   área de mensagens — de graça, porque ela já é `flex: 1 1 0; min-height: 0`
   dentro da coluna.

   NÃO HÁ TRANSIÇÃO CSS na altura de propósito. O iOS dispara `resize` do
   viewport visual várias vezes ao longo da animação nativa do teclado; seguir
   evento a evento faz o campo subir junto com ele. Uma transição própria
   competiria com essa animação e chegaria atrasada — é exatamente o efeito de
   "duas coisas se mexendo" que se quer eliminar.

   O QUE ESTE MÓDULO NÃO FAZ: não mexe em scroll de nenhuma tela que não seja a
   conversa, não força foco, não some com elemento por conta própria. Ele mede,
   publica a medida em `--app-altura` e diz, em `data-teclado`, se o teclado
   está aberto. Quem decide o que fazer com isso é o CSS.
*/

const raiz = document.documentElement;
const vv = window.visualViewport || null;

/* Quanto a altura precisa cair para ser teclado, e não a barra de endereço do
   Safari se recolhendo. A barra come algo perto de 60px; um teclado, nunca
   menos de 200. 120 separa os dois com folga dos dois lados. */
const LIMIAR_TECLADO = 120;

/* A maior altura já vista com o teclado fechado. É a referência para saber
   quanto caiu — comparar com `innerHeight` não serve, porque em alguns
   Androids o teclado encolhe o viewport de layout também, e aí os dois caem
   juntos e a diferença some. */
let alturaBase = 0;
let aberto = false;

function alturaVisivel() {
  /* Sem `visualViewport` (navegador antigo), `innerHeight` é o melhor que há.
     O app continua correto; só não sabe do teclado. */
  return vv ? vv.height : window.innerHeight;
}

/* Com zoom por pinça a altura do viewport visual deixa de ser comparável — ela
   passa a descrever a lupa, não a janela. Nesse estado a medida é ignorada e
   vale a última boa: melhor uma altura levemente velha do que o app encolhendo
   junto com o zoom. */
function medidaConfiavel() {
  return !vv || Math.abs(vv.scale - 1) < 0.02;
}

function publicarAltura(h) {
  raiz.style.setProperty('--app-altura', h + 'px');
}

/* A CONVERSA NÃO PODE PULAR. Quando a área de mensagens encolhe, o navegador
   preserva `scrollTop` — que é a distância até o TOPO. Numa conversa o que
   importa é a distância até o FUNDO: é lá que está a mensagem mais recente e é
   dela que o olho não deve sair. Guardar a distância do fundo antes e restaurar
   depois mantém a última mensagem no lugar, esteja a pessoa no fim da conversa
   ou lendo mais acima. */
function distanciaDoFundo(el) {
  return el.scrollHeight - el.scrollTop - el.clientHeight;
}

function restaurarDistanciaDoFundo(el, distancia) {
  el.scrollTop = Math.max(0, el.scrollHeight - el.clientHeight - distancia);
}

function aoMedir() {
  if (!medidaConfiavel()) return;

  const conversa = document.getElementById('mensagens');
  const distancia = conversa ? distanciaDoFundo(conversa) : null;

  const h = alturaVisivel();
  publicarAltura(h);

  if (h > alturaBase) alturaBase = h;
  const agoraAberto = (alturaBase - h) > LIMIAR_TECLADO;
  if (agoraAberto !== aberto) {
    aberto = agoraAberto;
    raiz.dataset.teclado = aberto ? 'aberto' : 'fechado';
  }

  /* Ler `clientHeight` aqui já força o recálculo com a altura nova, então a
     restauração acontece sobre a caixa correta e não sobre a anterior. */
  if (conversa && distancia !== null) restaurarDistanciaDoFundo(conversa, distancia);

  desfazerRolagemDoNavegador();
}

/* O Safari ainda tenta rolar o documento ao focar um campo, mesmo com o app
   preso no lugar. Como não há para onde rolar, isso vira um deslocamento
   residual do viewport de layout — pouco, mas o suficiente para a tela dar um
   tranco. Zerar é o que sobra do velho salto. */
function desfazerRolagemDoNavegador() {
  if (window.scrollY !== 0 || window.scrollX !== 0) window.scrollTo(0, 0);
}

/* Girar o aparelho muda a altura de referência: sem zerar, a base ficaria com a
   altura do retrato e o app acharia que está de teclado aberto em paisagem. O
   `setTimeout` espera o navegador terminar de reportar o novo tamanho. */
function aoGirar() {
  setTimeout(() => {
    alturaBase = 0;
    aoMedir();
  }, 250);
}

export function ligarTeclado() {
  publicarAltura(alturaVisivel());
  alturaBase = alturaVisivel();
  raiz.dataset.teclado = 'fechado';

  if (vv) {
    vv.addEventListener('resize', aoMedir);
    /* `scroll` do viewport visual é o evento em que o deslocamento do Safari
       aparece; sem ele, o tranco do primeiro toque escaparia. */
    vv.addEventListener('scroll', desfazerRolagemDoNavegador);
  } else {
    window.addEventListener('resize', aoMedir);
  }
  window.addEventListener('orientationchange', aoGirar);
}

/* Para quem já está no fim da conversa continuar no fim depois de uma mensagem
   nova. Fica aqui porque é a mesma pergunta — "onde a conversa deve estar?" —
   e não convém ter duas respostas em arquivos diferentes. */
export function tecladoAberto() {
  return aberto;
}
