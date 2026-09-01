/* ============================================================
   HOME V3 — a montagem
   ============================================================
   Junta conteúdo (`estado.js`) com componentes (`cards.js`) e liga as
   ações ao que o app já sabe fazer. É a única peça que conhece as duas
   pontas; os cards seguem sem saber que existe chat ou tour.

   Quando o backend chegar, é aqui que `CONTEUDO[momento]` vira uma
   resposta de API. Nada mais precisa mudar. */

import { PARTICIPANTE } from '../config.js';
import { CONTEUDO, MOMENTOS, AVISOS, PLACEHOLDER_CONCIERGE, momentoAtual, definirMomento } from './estado.js';
import { heroSaudacao, montarBlocos } from './cards.js';


/* O nome que a home mostra. A Yazo manda por `?nome=`; `capturarIdentidade()`
   já guardou em PARTICIPANTE antes de qualquer tela subir. Sem nome, a
   saudação não aparece — `heroSaudacao` cuida disso. Nada de "undefined",
   nada de string vazia, e nunca o e-mail. */
function nomeDoParticipante() {
  const n = PARTICIPANTE.nome && PARTICIPANTE.nome.trim();
  return n || null;
}

/* Bom dia até meio-dia, boa tarde até as 18h, boa noite depois. */
export function cumprimentoDaHora(hora) {
  const h = typeof hora === 'number' ? hora : new Date().getHours();
  if (h < 12) return 'Bom dia';
  if (h < 18) return 'Boa tarde';
  return 'Boa noite';
}

/** Monta a home inteira dentro de `raiz`.
 *  `aoAgir(acao, bloco)` recebe tudo que a pessoa tocar.
 *  `contexto` traz o que a home não sabe calcular sozinha — hoje, a
 *  próxima sessão da grade e a hora do evento. */
export function montarHome(raiz, aoAgir, contexto) {
  const ctx = contexto || {};
  const momento = momentoAtual();
  const c = CONTEUDO[momento];
  if (!c) return;

  raiz.innerHTML = '';
  raiz.dataset.momento = momento;

  if (mostrarSeletor()) {
    raiz.appendChild(seletorDeMomento(momento, () => montarHome(raiz, aoAgir, contexto)));
  }

  raiz.appendChild(heroSaudacao({
    ...c,
    nome: nomeDoParticipante(),
    cumprimento: cumprimentoDaHora(ctx.hora),
    /* No dia do evento o resumo é calculado; nos outros, é o do conteúdo. */
    resumo: c.resumo || ctx.resumoDaProxima || null,
  }));

  /* O bloco da próxima é preenchido pela grade. Sem sessão à frente, ele
     simplesmente não existe — a home não inventa uma. */
  const blocos = (c.blocos || []).map((b) => {
    if (b.tipo !== 'proxima' || !b.daGrade) return b;
    return ctx.proxima ? { ...b, ...ctx.proxima } : { ...b, estado: 'oculto' };
  });

  raiz.appendChild(montarBlocos(blocos, aoAgir));
}

/* O seletor de momento é ferramenta de desenvolvimento, não produto:
   aparece em localhost e quando `?dev=1` pede, nunca no ar. */
function mostrarSeletor() {
  try {
    if (new URLSearchParams(location.search).get('dev') === '1') return true;
    const h = location.hostname;
    return h === 'localhost' || h === '127.0.0.1' || h === '[::1]' || h.endsWith('.local');
  } catch (e) { return false; }
}

export { AVISOS };

/* Seletor de momento — andaime, não produto.
   Existe para percorrer os quatro estados sem depender da data real.
   Sai no dia em que o momento vier do evento. */
function seletorDeMomento(atual, aoTrocar) {
  const el = document.createElement('nav');
  el.className = 'v3-momentos';
  el.setAttribute('aria-label', 'Momento do evento (demonstração)');
  MOMENTOS.forEach((m) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = m.rotulo;
    b.className = m.id === atual ? 'on' : '';
    b.setAttribute('aria-pressed', String(m.id === atual));
    b.addEventListener('click', () => { definirMomento(m.id); aoTrocar(); });
    el.appendChild(b);
  });
  return el;
}

export { PLACEHOLDER_CONCIERGE };
