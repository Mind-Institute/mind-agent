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
/* QUEM É A PESSOA, QUANDO A URL NÃO DISSE.
   No app, a Yazo manda nome e e-mail na URL e a pessoa não digita nada.
   Fora do app — um link mandado por fora — não há URL para dizer isso, e
   a própria pessoa escreve. O que ela escreve vale só para esta pesquisa:
   não vira a identidade do app nem do chat, e não é gravado no aparelho.

   É IDENTIDADE AUTODECLARADA, e isso tem consequência: quem digita o
   e-mail de outra pessoa responde no lugar dela. Vale hoje também para a
   URL, que qualquer um pode escrever à mão — a diferença é que o campo
   torna isso fácil. Foi decisão de produto, tomada em 18/09. */
let identidadeDigitada = null;

export function definirIdentidadeDigitada(nome, email) {
  const e = typeof email === 'string' ? email.trim().toLowerCase() : '';
  identidadeDigitada = e ? { nome: (nome || '').trim() || null, email: e } : null;
}

/** A URL disse quem é a pessoa? É isto que decide se o formulário
    pergunta ou não. NÃO se olha a barra de endereço: ela é limpa na
    partida, de propósito, e recarregar a página faria os campos
    aparecerem do nada. Quem sabe é a camada de identidade. */
export function identidadeVeioDaUrl() {
  return Boolean(obterParticipante().email);
}

function cabecalhosDaIdentidade() {
  const p = obterParticipante();
  const fonte = p.email ? p : identidadeDigitada;
  if (!fonte || !fonte.email) return {};
  const h = { 'X-Identidade-Email': fonte.email };
  if (fonte.nome) h['X-Identidade-Nome'] = fonte.nome;
  return h;
}

async function chamar(caminho, opcoes) {
  const base = raiz();
  if (!base) return null;

  /* POR CONVITE NÃO HÁ SESSÃO, e é assim que tem de ser: pedir uma aqui
     abriria uma sessão anônima para quem só veio responder um
     formulário. Quem prova quem é, nesse caminho, é o token — e ele vai
     em cabeçalho, nunca na URL. */
  const porConvite = caminho.startsWith('/convite/');
  const acesso = porConvite ? null : await token();
  if (!porConvite && !acesso) return null;

  const controlador = new AbortController();
  const relogio = setTimeout(() => controlador.abort(), TEMPO_LIMITE_MS);
  try {
    const r = await fetch(base + caminho, {
      ...opcoes,
      headers: {
        apikey: CONFIG.supabasePublishableKey,
        ...(acesso ? { Authorization: 'Bearer ' + acesso } : {}),
        ...(porConvite && convite ? { 'X-Convite': convite } : {}),
        ...(opcoes && opcoes.body ? { 'Content-Type': 'application/json' } : {}),
        /* O e-mail da Yazo não vai junto do convite: ali a identidade já
           está resolvida pelo token, e mandar e-mail seria oferecer um
           segundo jeito de dizer quem é a pessoa numa porta sem login. */
        ...(porConvite ? {} : cabecalhosDaIdentidade()),
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
  const busca = '?event_slug=' + encodeURIComponent(CONFIG.eventSlug) +
    (dia ? '&dia=' + encodeURIComponent(dia) : '');
  return lerEstadoEm('/estado' + busca);
}

async function lerEstadoEm(caminho) {
  try {
    const r = await chamar(caminho, { method: 'GET' });
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
  return enviarEm('/enviar', resposta);
}

/* ============================================================
   A PESQUISA DO EVENTO INTEIRO
   ============================================================
   Mesma porta, mesma sessão, mesmo rascunho, mesmo tratamento de erro —
   muda o caminho e o escopo da chave local. Um segundo arquivo de
   serviço duplicaria token, timeout e cabeçalho de identidade, que é
   justamente onde os dois iam divergir primeiro e em silêncio.

   O RASCUNHO usa `'evento'` onde a pesquisa do dia usa a data. Não
   colide com data nenhuma, e continua sem guardar e-mail. */

export const ESCOPO_DO_EVENTO = 'evento';

/* ============================================================
   O CONVITE
   ============================================================
   Quem chega por link não tem sessão — é o motivo de o link existir. O
   token vem do FRAGMENTO da URL, que o navegador nunca manda ao
   servidor, e vive só nesta variável: não vai para `localStorage`, não
   vai para a barra de endereço depois da primeira leitura e não entra
   em nenhuma URL que esta camada monte.

   Guardar no armazenamento local seria transformar um link de uma
   resposta numa credencial que fica no aparelho — inclusive num aparelho
   emprestado. */
let convite = null;

const FORMATO_CONVITE = /^[0-9a-f]{64}$/;

/** Devolve `true` quando o token tem a cara certa e foi aceito. */
export function definirConvite(token) {
  convite = typeof token === 'string' && FORMATO_CONVITE.test(token) ? token : null;
  return Boolean(convite);
}

export function temConvite() {
  return Boolean(convite);
}

/* AS DUAS PORTAS ATENDEM PELA MESMA FUNÇÃO. Quem chama não escolhe o
   caminho: o caminho é consequência de haver ou não convite. Assim a
   tela é uma só, e não existe a chance de ela chamar a porta errada. */
export async function carregarEstadoDoEvento() {
  if (convite) return lerEstadoEm('/convite/estado?event_slug=' + encodeURIComponent(CONFIG.eventSlug));
  return lerEstadoEm('/evento/estado?event_slug=' + encodeURIComponent(CONFIG.eventSlug));
}

export async function enviarDoEvento(resposta) {
  return enviarEm(convite ? '/convite/enviar' : '/evento/enviar', resposta);
}

async function enviarEm(caminho, resposta) {
  let r;
  try {
    r = await chamar(caminho, { method: 'POST', body: JSON.stringify(resposta) });
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
