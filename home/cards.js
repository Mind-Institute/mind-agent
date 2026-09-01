/* ============================================================
   HOME V3 — os componentes
   ============================================================
   Cada card é uma função pequena que recebe um bloco de `estado.js` e
   devolve um nó. Nenhuma delas conhece texto de negócio nem sabe em que
   momento do evento está: só desenha o que recebeu.

   `aoAgir` é o único canal de saída. Os cards não navegam, não abrem
   chat e não chamam backend — eles avisam qual ação foi pedida e quem
   monta a home decide. É isso que deixa a integração desacoplada. */

import { AVISOS } from './estado.js';

/* Estados previstos para qualquer card, quando fizer sentido:
   'disponivel' (padrão) · 'ativo' · 'concluido' · e `oculto`, que é a
   ausência do bloco na lista. O motor de regras que escolhe entre eles
   ainda não existe; a classe já sai no DOM para quando existir. */
const CLASSE_ESTADO = (b) => (b.estado ? ' e-' + b.estado : '');

function no(tag, classe, dentro) {
  const el = document.createElement(tag);
  if (classe) el.className = classe;
  if (dentro != null) el.innerHTML = dentro;
  return el;
}

const SETA = '<svg class="seta" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h13M12.5 5.5L19 12l-6.5 6.5"/></svg>';
const CHEVRON = '<svg class="chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 5.5L15.5 12 9 18.5"/></svg>';

/* ---------- Cabeçalho: saudação, título, resumo ----------
   A saudação só existe quando há nome. Sem nome, o bloco some inteiro em
   vez de virar "Olá ," — o agente não inventa identidade. */
export function heroSaudacao({ etiqueta, contagem, saudacao, comoTitulo, titulo, resumo, nome, cumprimento }) {
  const el = no('header', 'v3-hero');
  if (etiqueta) {
    /* O relógio entra num nó próprio para poder ser atualizado a cada
       segundo sem redesenhar a home inteira. Sem `aria-live`: um leitor
       de tela anunciando o segundo seria insuportável. */
    el.appendChild(no('p', 'v3-etq', contagem
      ? etiqueta + ' <span class="v3-relogio" id="v3-contagem"></span>'
      : etiqueta));
  }

  if (comoTitulo) {
    /* Neste momento o cumprimento É o título. */
    el.appendChild(no('h1', 'v3-titulo', nome ? cumprimento + ', ' + escapar(nome) + '.' : cumprimento + '.'));
  } else {
    if (saudacao && nome) el.appendChild(no('p', 'v3-ola', 'Olá, ' + escapar(nome) + '.'));
    if (titulo) el.appendChild(no('h1', 'v3-titulo', titulo));
  }

  if (resumo) el.appendChild(no('p', 'v3-resumo', resumo));
  return el;
}

/* O nome vem da URL e `normalizarNome` só apara pontas e tamanho — não
   remove marcação. Entra escapado, nunca cru em innerHTML. */
function escapar(txt) {
  const d = document.createElement('div');
  d.textContent = txt;
  return d.innerHTML;
}

/* ---------- Destaque: a ação principal do momento ---------- */
export function cardDestaque(b, aoAgir) {
  const el = no('button', 'v3-destaque' + (b.variante ? ' ' + b.variante : '') + CLASSE_ESTADO(b));
  el.type = 'button';
  el.innerHTML =
    (b.ico ? '<span class="v3-ico">' + b.ico + '</span>' : '') +
    (b.selo ? '<span class="v3-selo">' + escapar(b.selo) + '</span>' : '') +
    '<strong class="v3-pergunta">' + b.pergunta + '</strong>' +
    '<span class="v3-cta">' + b.cta + SETA + '</span>';
  el.addEventListener('click', () => aoAgir(b.acao, b));
  return el;
}

/* ---------- Linha: ícone, título, apoio, chevron ---------- */
export function cardLinha(b, aoAgir) {
  const el = no('button', 'v3-linha' + CLASSE_ESTADO(b));
  el.type = 'button';
  el.innerHTML =
    '<span class="v3-ico">' + b.ico + '</span>' +
    '<span class="v3-corpo"><strong>' + b.titulo + '</strong><small>' + b.texto + '</small></span>' +
    CHEVRON;
  el.addEventListener('click', () => aoAgir(b.acao, b));
  return el;
}

/* ---------- Próxima atividade ----------
   Sem chevron e sem ícone: o que importa aqui é hora, nome e quem fala. */
export function cardProxima(b, aoAgir) {
  /* Sem `acao`, sai como bloco de leitura e não como botão: um botão que
     não faz nada é pior do que texto — ele promete. */
  const el = no(b.acao ? 'button' : 'div', 'v3-proxima' + (b.acao ? '' : ' parado') + CLASSE_ESTADO(b));
  if (b.acao) el.type = 'button';
  el.innerHTML =
    '<span class="v3-hora">' + b.hora + '</span>' +
    '<strong>' + b.titulo + '</strong>' +
    (b.texto ? '<small>' + b.texto + '</small>' : '');
  if (b.acao) el.addEventListener('click', () => aoAgir(b.acao, b));
  return el;
}

/* Aviso: o bloco traz só o id, e o conteúdo sai da lista de `estado.js`.
   Assim o mesmo aviso aparece igual na home e na página de todos. */
export function cardAviso(b, aoAgir) {
  const a = AVISOS.find((x) => x.id === b.id);
  if (!a) return document.createComment('aviso ' + b.id + ' não existe');
  return cardLinha({ ico: a.ico, titulo: a.titulo, texto: a.resumo, acao: 'aviso:' + a.id }, aoAgir);
}

/* ---------- Tour: convite, não recado ----------
   Desenho deliberadamente diferente da linha de aviso. O ícone é sólido
   em vez de vazado, a borda é verde em vez de cinza, e o fecho é seta em
   vez de chevron: seta é "vai acontecer algo", chevron é "tem mais texto
   aí dentro". */
export function cardTour(b, aoAgir) {
  const el = no('button', 'v3-tour' + CLASSE_ESTADO(b));
  el.type = 'button';
  el.innerHTML =
    '<span class="v3-play"><svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">' +
      '<path d="M9 6.8v10.4a1 1 0 0 0 1.5.87l8.4-5.2a1 1 0 0 0 0-1.74l-8.4-5.2A1 1 0 0 0 9 6.8z"/>' +
    '</svg></span>' +
    '<span class="v3-corpo">' +
      '<strong>' + b.titulo + '</strong>' +
      '<small>' + b.texto + (b.duracao ? ' <i>· ' + b.duracao + '</i>' : '') + '</small>' +
    '</span>' +
    SETA;
  el.addEventListener('click', () => aoAgir(b.acao, b));
  return el;
}

/* ---------- Título de seção, com atalho à direita ---------- */
export function tituloSecao(b, aoAgir) {
  const el = no('div', 'v3-secao');
  el.innerHTML = '<h2>' + b.titulo + '</h2>';
  if (b.link) {
    const a = no('button', 'v3-link', b.link);
    a.type = 'button';
    a.addEventListener('click', () => aoAgir(b.acao || 'secao', b));
    el.appendChild(a);
  }
  return el;
}

/* ---------- Progresso da entrevista ---------- */
export function barraProgresso(b) {
  const el = no('div', 'v3-progresso');
  el.setAttribute('role', 'progressbar');
  el.setAttribute('aria-valuemin', '0');
  el.setAttribute('aria-valuemax', String(b.etapas));
  el.setAttribute('aria-valuenow', String(b.feito));
  el.setAttribute('aria-label', 'Etapa ' + b.feito + ' de ' + b.etapas);
  for (let i = 0; i < b.etapas; i++) el.appendChild(no('i', i < b.feito ? 'feito' : ''));
  return el;
}

/* ---------- Painel: etiqueta, título, texto e botão opcional ---------- */
export function cardPainel(b, aoAgir) {
  const el = no('article', 'v3-painel' + CLASSE_ESTADO(b));
  el.innerHTML =
    '<p class="v3-etiqueta">' + b.etiqueta + '</p>' +
    '<strong>' + b.titulo + '</strong>' +
    '<p class="v3-texto">' + b.texto + '</p>';
  if (b.botao) {
    const bt = no('button', 'v3-botao', b.botao);
    bt.type = 'button';
    bt.addEventListener('click', () => aoAgir(b.acao, b));
    el.appendChild(bt);
  }
  return el;
}

/* ---------- O montador ----------
   Um bloco sem componente correspondente é ignorado em silêncio: assim o
   backend pode mandar um tipo novo antes de a tela saber desenhá-lo, sem
   quebrar a home de quem já está no evento. */
const COMPONENTES = {
  destaque: cardDestaque,
  linha: cardLinha,
  aviso: cardAviso,
  tour: cardTour,
  proxima: cardProxima,
  secao: tituloSecao,
  progresso: (b) => barraProgresso(b),
  painel: cardPainel,
};

export function montarBlocos(blocos, aoAgir) {
  const frag = document.createDocumentFragment();
  (blocos || []).forEach((b) => {
    if (b.estado === 'oculto') return;
    const faz = COMPONENTES[b.tipo];
    if (faz) frag.appendChild(faz(b, aoAgir));
  });
  return frag;
}
