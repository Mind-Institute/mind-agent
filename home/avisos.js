/* ============================================================
   AVISOS — a página, e o que já foi lido
   ============================================================
   Deixou de ser uma folha que sobe: virou tela, com voltar próprio. Um
   aviso pode ser longo, e ler texto longo numa gaveta de meia altura é
   pior do que numa página inteira.

   São dois níveis: a LISTA de todos os avisos e a LEITURA de um deles.
   Voltar da leitura devolve para a lista; voltar da lista devolve para
   a home. O botão é sempre o mesmo, e sempre no mesmo lugar.

   ---------- O que foi lido ----------
   Hoje mora no navegador de quem lê. Isso tem um limite honesto: trocar
   de aparelho zera a marcação, e o painel não consegue saber quantas
   pessoas leram um aviso.

   `lidos()` e `marcarLido()` são a única porta desse dado. Quando a
   tabela existir no Supabase, é só essas duas funções passarem a falar
   com ela — nenhuma tela muda. */

import { AVISOS } from './estado.js';

const CHAVE = 'mindagent:v1:avisos-lidos';

/** Ids que esta pessoa já abriu. */
export function lidos() {
  /* API: virá de `GET /avisos/lidos` para o participante identificado. */
  try {
    const cru = localStorage.getItem(CHAVE);
    const lista = cru ? JSON.parse(cru) : [];
    return Array.isArray(lista) ? lista : [];
  } catch (e) {
    return [];   /* aba anônima ou dado corrompido: ninguém leu nada */
  }
}

export function marcarLido(id) {
  /* API: virá de `POST /avisos/{id}/lido`. */
  try {
    const atuais = lidos();
    if (atuais.includes(id)) return atuais;
    const novos = [...atuais, id];
    localStorage.setItem(CHAVE, JSON.stringify(novos));
    return novos;
  } catch (e) {
    return lidos();
  }
}

/** Quantos avisos esta pessoa ainda não abriu. */
export function naoLidos() {
  const jaLidos = lidos();
  return AVISOS.filter((a) => !jaLidos.includes(a.id)).length;
}

/* ---------- Desenho ---------- */

function no(tag, classe, dentro) {
  const el = document.createElement(tag);
  if (classe) el.className = classe;
  if (dentro != null) el.innerHTML = dentro;
  return el;
}

const CHEVRON =
  '<svg class="chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 5.5L15.5 12 9 18.5"/></svg>';

/** A lista inteira. `aoAbrir(id)` recebe o aviso escolhido. */
export function listaDeAvisos(aoAbrir) {
  const jaLidos = lidos();
  const el = no('div', 'av-lista');
  AVISOS.forEach((a) => {
    const naoLido = !jaLidos.includes(a.id);
    const b = no('button', 'av-item' + (naoLido ? ' novo' : ''));
    b.type = 'button';
    b.innerHTML =
      '<span class="av-ico">' + a.ico + '</span>' +
      '<span class="av-corpo">' +
        '<strong>' + a.titulo + '</strong>' +
        '<small>' + a.resumo + '</small>' +
        '<em>' + a.quando + '</em>' +
      '</span>' +
      (naoLido ? '<span class="av-ponto" aria-label="Não lido"></span>' : '') +
      CHEVRON;
    b.addEventListener('click', () => aoAbrir(a.id));
    el.appendChild(b);
  });
  return el;
}

/** Um aviso aberto. `aoVerNoApp(tela)` é opcional. */
export function leituraDeAviso(id, aoVerNoApp) {
  const a = AVISOS.find((x) => x.id === id);
  if (!a) return no('p', 'av-vazio', 'Este aviso não existe mais.');

  const el = no('article', 'av-leitura');
  el.innerHTML =
    '<span class="av-ico grande">' + a.ico + '</span>' +
    '<p class="av-quando">' + a.quando + '</p>' +
    '<h2>' + a.titulo + '</h2>' +
    (a.resumo ? '<p class="av-resumo">' + a.resumo + '</p>' : '') +
    '<p class="av-texto">' + a.mensagem + '</p>';

  if (a.verNoApp && aoVerNoApp) {
    const b = no('button', 'av-acao', a.botaoVerNoApp || 'Ver no app');
    b.type = 'button';
    b.addEventListener('click', () => aoVerNoApp(a.verNoApp));
    el.appendChild(b);
  }
  return el;
}

export { AVISOS };
