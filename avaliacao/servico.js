/* ============================================================
   AVALIAÇÃO DO DIA — a camada de dados e o rascunho
   ============================================================
   Falar com a Edge Function `mindagent-avaliacao` e guardar o rascunho
   local. Nada aqui desenha tela.

   REGRA QUE VALE PARA O ARQUIVO INTEIRO
   Uma falha da pesquisa NUNCA derruba a home nem o chat. Toda função
   daqui devolve `null` ou lança um erro com mensagem legível — e quem
   chama trata. Nenhuma exceção escapa para o carregamento da página.

   O RASCUNHO É POR PESSOA, POR EVENTO, POR DIA E POR VERSÃO DO
   FORMULÁRIO. A chave carrega uma impressão do participante, não o
   e-mail dele: dois aparelhos compartilhados no credenciamento não
   podem misturar respostas, e o armazenamento local não precisa saber
   quem é ninguém para isso.
*/

import { CONFIG, obterParticipante } from '../config.js';
import { garantirSessaoDeAcesso } from '../chat-service.js';

const PREFIXO = 'mindagent:v1:' + CONFIG.eventSlug + ':avaliacao:';

/* 20 s: a pesquisa é uma gravação curta, não um turno de IA. Passou
   disso, ou o serviço está congestionado ou a rede caiu — e nos dois
   casos o certo é avisar e deixar tentar de novo, com o formulário
   preservado. */
const TEMPO_LIMITE_MS = 20000;

/** A raiz da função, ou `null` quando a pesquisa está desligada. */
function raiz() {
  const url = CONFIG.avaliacaoApiUrl;
  return typeof url === 'string' && url.trim() ? url.trim().replace(/\/+$/, '') : null;
}

export function pesquisaConfigurada() {
  return Boolean(raiz());
}

/* O MESMO token da sessão anônima do chat, pedido a quem é dono dele.
   Não abrimos sessão por conta própria e não lemos a chave do storage
   por fora: criar uma segunda porta de autenticação seria criar um
   segundo problema. Sem token, a pesquisa simplesmente não aparece. */
function token() {
  return garantirSessaoDeAcesso();
}

/* A identidade que a Yazo informou, em cabeçalho — nunca na URL. O
   servidor a usa só para ligar quem nunca conversou à pessoa canônica;
   ela não é autorização, e sozinha não vale nada. */
function cabecalhosDaIdentidade() {
  const p = obterParticipante();
  if (!p.email) return {};
  const h = { 'X-Identidade-Email': p.email };
  if (p.nome) h['X-Identidade-Nome'] = p.nome;
  return h;
}

async function chamar(caminho, opcoes) {
  const base = raiz();
  if (!base) return null;
  const acesso = await token();
  if (!acesso) return null;

  const controlador = new AbortController();
  const relogio = setTimeout(() => controlador.abort(), TEMPO_LIMITE_MS);
  try {
    const r = await fetch(base + caminho, {
      ...opcoes,
      headers: {
        apikey: CONFIG.supabasePublishableKey,
        Authorization: 'Bearer ' + acesso,
        ...(opcoes && opcoes.body ? { 'Content-Type': 'application/json' } : {}),
        ...cabecalhosDaIdentidade(),
      },
      cache: 'no-store',
      signal: controlador.signal,
    });
    const corpo = await r.json().catch(() => ({}));
    return { ok: r.ok, status: r.status, corpo };
  } finally {
    clearTimeout(relogio);
  }
}

/**
 * O estado da pesquisa para quem está com o app aberto.
 * `null` quer dizer "não deu para saber" — desligada, sem sessão, rede
 * caída. É diferente de `{ativo: false}`, que é "está desligada mesmo".
 * Quem chama trata os dois do mesmo jeito na home (não mostra o card) e
 * de jeitos diferentes na tela.
 */
export async function carregarEstado(dia) {
  try {
    const busca = '?event_slug=' + encodeURIComponent(CONFIG.eventSlug) +
      (dia ? '&dia=' + encodeURIComponent(dia) : '');
    const r = await chamar('/estado' + busca, { method: 'GET' });
    if (!r || !r.ok) return null;
    return r.corpo && typeof r.corpo === 'object' ? r.corpo : null;
  } catch (e) {
    return null;
  }
}

/**
 * O envio definitivo.
 *
 * Devolve `{ok: true, ...}` quando o SERVIDOR confirmou — e só então. Em
 * erro, lança com a mensagem já legível e um `codigo` para quem quiser
 * decidir pelo código. O formulário nunca é limpo por esta função.
 */
export async function enviar(resposta) {
  let r;
  try {
    r = await chamar('/enviar', { method: 'POST', body: JSON.stringify(resposta) });
  } catch (e) {
    /* Timeout e queda de rede caem aqui. NÃO sabemos se gravou: quem
       chama precisa perguntar ao servidor antes de concluir qualquer
       coisa, e é isso que `carregarEstado` responde. */
    const erro = new Error('Não deu para confirmar o envio. Vamos verificar.');
    erro.codigo = 'indeterminado';
    throw erro;
  }
  if (!r) {
    const erro = new Error('A avaliação não está disponível agora.');
    erro.codigo = 'desligada';
    throw erro;
  }
  if (r.ok) return { ok: true, ...(r.corpo || {}) };

  const erro = new Error(r.corpo?.mensagem || 'Não consegui enviar agora. Tente de novo.');
  erro.codigo = r.corpo?.codigo || 'erro';
  erro.campo = r.corpo?.campo || null;
  throw erro;
}

/* ============================================================
   O RASCUNHO
   ============================================================
   Uma pessoa pode voltar para a home no meio e continuar depois. O
   rascunho vive no aparelho e some quando o envio é confirmado.

   NÃO GUARDA E-MAIL NEM NOME. A chave leva uma impressão curta da
   identidade, suficiente para não misturar duas pessoas no mesmo
   aparelho e insuficiente para dizer quem elas são. */

function impressaoDaIdentidade() {
  const email = obterParticipante().email;
  if (!email) return 'anon';
  let h = 5381;
  for (let i = 0; i < email.length; i++) h = ((h * 33) ^ email.charCodeAt(i)) >>> 0;
  return h.toString(36);
}

function chaveDoRascunho(dia, versao) {
  return PREFIXO + impressaoDaIdentidade() + ':' + dia + ':v' + (versao || 1);
}

export function lerRascunho(dia, versao) {
  try {
    const cru = localStorage.getItem(chaveDoRascunho(dia, versao));
    const lido = cru ? JSON.parse(cru) : null;
    return lido && typeof lido === 'object' ? lido : null;
  } catch (e) {
    return null;
  }
}

export function salvarRascunho(dia, versao, dados) {
  try {
    localStorage.setItem(chaveDoRascunho(dia, versao), JSON.stringify(dados));
  } catch (e) { /* aba anônima ou cota estourada: o rascunho só não persiste */ }
}

export function limparRascunho(dia, versao) {
  try { localStorage.removeItem(chaveDoRascunho(dia, versao)); }
  catch (e) { /* idem */ }
}
