/* ============================================================
   HOME V3 — a montagem
   ============================================================
   Junta conteúdo (`estado.js`) com componentes (`cards.js`) e liga as
   ações ao que o app já sabe fazer. É a única peça que conhece as duas
   pontas; os cards seguem sem saber que existe chat ou tour.

   Quando o backend chegar, é aqui que `CONTEUDO[momento]` vira uma
   resposta de API. Nada mais precisa mudar. */

import { primeiroNome } from '../config.js';
import { CONTEUDO, MOMENTOS, AVISOS, PLACEHOLDER_CONCIERGE, momentoAtual, definirMomento } from './estado.js';
import { heroSaudacao, montarBlocos } from './cards.js';


/* O nome que a home mostra: o PRIMEIRO, que é como a pessoa é chamada.
   A Yazo manda por `?nome=`, com o nome inteiro do cadastro;
   `capturarIdentidade()` já guardou antes de qualquer tela subir. Sem
   nome, a saudação não aparece — `heroSaudacao` cuida disso. Nada de
   "undefined", nada de string vazia, e nunca o e-mail. */
function nomeDoParticipante() {
  return primeiroNome();
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
    /* Remonta pelo caminho completo de quem chamou — `montarHome` sozinho
       redesenha os cards, mas não religa o relógio da contagem nem o
       contador de avisos, que vivem fora dela. */
    const remontar = ctx.remontar || (() => montarHome(raiz, aoAgir, contexto));
    raiz.appendChild(seletorDeMomento(momento, remontar));
  }

  raiz.appendChild(heroSaudacao({
    ...c,
    /* "EXPERIÊNCIA VIP" no lugar de "MIND SUMMIT", quando o espelho do
       credenciamento sabe o tipo do ingresso. Só SUBSTITUI sobrancelha
       que já existe: numa tela que não tem etiqueta, acrescentar uma
       criaria uma linha onde o desenho não tem nenhuma. */
    etiqueta: ctx.ingresso && c.etiqueta ? 'Experiência ' + ctx.ingresso : c.etiqueta,
    nome: nomeDoParticipante(),
    cumprimento: cumprimentoDaHora(ctx.hora),
    /* No dia do evento o resumo é calculado; nos outros, é o do conteúdo. */
    resumo: c.resumo || ctx.resumoDaProxima || null,
  }));

  /* Dois blocos são preenchidos de fora. O da próxima vem da grade: sem
     sessão à frente ele simplesmente não existe — a home não inventa uma.
     O de insight ganha o nome da palestra que a pessoa disse estar
     assistindo; o texto continua sendo do conteúdo, aqui só se escolhe
     qual dos dois usar. */
  const blocos = (c.blocos || []).map((b) => {
    if (b.tipo === 'proxima' && b.daGrade) {
      return ctx.proxima ? { ...b, ...ctx.proxima } : { ...b, estado: 'oculto' };
    }
    if (b.daSessao && ctx.sessaoDoInsight) {
      return { ...b, selo: ctx.sessaoDoInsight, cta: b.ctaComSessao || b.cta };
    }
    return b;
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
