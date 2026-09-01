/* ============================================================
   HOME V3 — os componentes
   ============================================================
   Cada card é uma função pequena que recebe um bloco de `estado.js` e
   devolve um nó. Nenhuma delas conhece texto de negócio nem sabe em que
   momento do evento está: só desenha o que recebeu.

   `aoAgir` é o único canal de saída. Os cards não navegam, não abrem
   chat e não chamam backend — eles avisam qual ação foi pedida e quem
   monta a home decide. É isso que deixa a integração desacoplada. */

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
export function heroSaudacao({ etiqueta, saudacao, saudacaoBomDia, titulo, resumo, nome }) {
  const el = no('header', 'v3-hero');
  if (etiqueta) el.appendChild(no('p', 'v3-etq', etiqueta));

  if (saudacaoBomDia) {
    /* Neste momento o cumprimento É o título. */
    el.appendChild(no('h1', 'v3-titulo', nome ? 'Bom dia, ' + escapar(nome) + '.' : 'Bom dia.'));
  } else {
    if (saudacao && nome) el.appendChild(no('p', 'v3-ola', 'Olá ' + escapar(nome) + '.'));
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
    (b.selo ? '<span class="v3-selo">' + b.selo + '</span>' : '') +
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
  const el = no('button', 'v3-proxima' + CLASSE_ESTADO(b));
  el.type = 'button';
  el.innerHTML =
    '<span class="v3-hora">' + b.hora + '</span>' +
    '<strong>' + b.titulo + '</strong>' +
    '<small>' + b.texto + '</small>';
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
