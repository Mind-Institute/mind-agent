/* ============================================================
   HOME V3 — a montagem
   ============================================================
   Junta conteúdo (`estado.js`) com componentes (`cards.js`) e liga as
   ações ao que o app já sabe fazer. É a única peça que conhece as duas
   pontas; os cards seguem sem saber que existe chat ou tour.

   Quando o backend chegar, é aqui que `CONTEUDO[momento]` vira uma
   resposta de API. Nada mais precisa mudar. */

import { PARTICIPANTE } from '../config.js';
import { CONTEUDO, MOMENTOS, PLACEHOLDER_CONCIERGE, momentoAtual, definirMomento } from './estado.js';
import { heroSaudacao, montarBlocos } from './cards.js';


/* O nome que a home mostra. A Yazo manda por `?nome=`; `capturarIdentidade()`
   já guardou em PARTICIPANTE antes de qualquer tela subir. Sem nome, a
   saudação não aparece — `heroSaudacao` cuida disso. Nada de "undefined",
   nada de string vazia, e nunca o e-mail. */
function nomeDoParticipante() {
  const n = PARTICIPANTE.nome && PARTICIPANTE.nome.trim();
  return n || null;
}

/** Monta a home inteira dentro de `raiz`. `aoAgir(acao, bloco)` recebe
 *  tudo que a pessoa tocar. */
export function montarHome(raiz, aoAgir) {
  const momento = momentoAtual();
  const c = CONTEUDO[momento];
  if (!c) return;

  raiz.innerHTML = '';
  raiz.dataset.momento = momento;

  raiz.appendChild(seletorDeMomento(momento, () => montarHome(raiz, aoAgir)));
  raiz.appendChild(heroSaudacao({ ...c, nome: nomeDoParticipante() }));
  raiz.appendChild(montarBlocos(c.blocos, aoAgir));
}

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
