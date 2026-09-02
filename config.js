/* ============================================================
   CONFIGURAÇÃO CENTRAL
   ============================================================
   O único lugar do frontend que sabe de onde vêm os dados e quem
   está usando a página. Só entra aqui o que é público por definição:
   a URL do bootstrap (abre sem autenticação) e a publishable key do
   Supabase, feita para viver no cliente.

   O que NUNCA entra: `service_role`, secret key, `OPENAI_API_KEY`.
   Essas ficam do lado do servidor — nas Edge Functions. Quem fala com
   a OpenAI é a `mindagent-chat`, nunca o navegador.
*/

export const CONFIG = {
  /* Qual evento esta instância atende. Vira parte do caminho da API
     (`/eventos/mind-summit-2026/summit`) quando houver API. */
  eventSlug: 'mind-summit-2026',

  /* Raiz da API do mindagent-bootstrap — a origem oficial dos dados.
     Nula volta a página para o arquivo local. */
  apiBaseUrl: 'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/mindagent-bootstrap',

  /* A porta da Home V3: avisos e qual composição está no ar. É função
     separada do bootstrap de propósito — o bootstrap responde pela
     programação do evento, e mexer nele é mexer em coisa de outra lane.
     Nula desliga: o app fica com os avisos embutidos. */
  homeApiUrl: 'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/mindagent-home',

  /* O projeto Supabase e a chave pública — usados pelo `chat-service.js`
     para abrir a sessão anônima (Auth) e chamar a função do chat. */
  supabaseUrl: 'https://ymnmotgglsrxmjmonwjz.supabase.co',
  supabasePublishableKey: 'sb_publishable__wYRbYyBgK_MBfqmLpiZNg_Z8iJNxvc',

  /* A Edge Function que conversa com a OpenAI. É ela que mascara e-mail e
     telefone, monta o contexto público e grava mensagens e interesses. */
  chatFunction: 'mindagent-chat',

  /* Rede de segurança: se a API não responder, a página cai no
     `dados/summit.json` do repositório — conteúdo mais antigo, mas
     conteúdo real. Desligar as duas origens deixa a página sem fonte, e
     ela diz isso na tela em vez de inventar. */
  useLocalFallback: true,
};
/* ============================================================
   IDENTIDADE DO PARTICIPANTE
   ============================================================
   Opcional por definição. Fica nula até a Yazo dizer quem abriu a
   página. Sem identidade o agente cumprimenta sem nome — ele nunca
   chuta um, e nunca transforma o que vem antes do @ em nome.

   A Yazo abre o app assim:

       /?email=usuario%40email.com&nome=Usu%C3%A1rio

   A ordem de prioridade é sempre esta:

     1. query string da Yazo
     2. `sessionStorage` (mesma aba, por até 12 horas)
     3. anônimo

   `sessionStorage` e não `localStorage`: identidade morre com a aba.
   Um notebook emprestado no credenciamento não pode entregar o e-mail
   de quem usou antes.

   Depois de capturar, `email` e `nome` saem da URL por
   `history.replaceState()`. O e-mail não fica na barra de endereço, no
   histórico nem em link copiado — e nunca vai para console ou mensagem
   de erro, nem quando é inválido.

   Nada disso acontece só por importar este arquivo. Quem chama
   `capturarIdentidade()` é o `app.js`, de propósito, antes da primeira
   saudação.
*/

export const PARTICIPANTE = {
  nome: null,
  email: null,
  origem: null,
  capturadoEm: null,
  expiraEm: null,
};

const CHAVE_PARTICIPANTE = 'mindagent:v1:' + CONFIG.eventSlug + ':participante';

/* PORTA DE ENTRADA DA CONVERSA — de onde a pessoa veio, não quem ela é.
   Fica numa chave própria de propósito: não é identidade, não tem prazo de
   validade próprio e não entra no lifecycle do participante. O runtime a
   persiste em `engagement.conversas.origem_codigo` na abertura da conversa,
   uma vez só, e é ela que diz que a entrada pelo app oficial já vem com a
   competência decidida — sem passar pelo Router. */
const CHAVE_ORIGEM = 'mindagent:v1:' + CONFIG.eventSlug + ':origem';

/* Identificador, não texto livre: o mesmo formato que o banco valida. Uma URL
   hostil não empurra frase para dentro de um campo de origem. */
const FORMATO_ORIGEM = /^[a-z][a-z0-9_]{1,59}$/;

let ORIGEM_CODIGO;

/* 12 horas: cobre um dia inteiro de evento e não cobre uma aba
   esquecida no dia seguinte. */
const VALIDADE_MS = 12 * 60 * 60 * 1000;

/* Suficiente para reprovar `email-invalido` e aprovar o que os
   provedores de verdade emitem. Validação de formato, não de
   existência: quem confirma que a pessoa existe é o banco. */
const FORMATO_EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/* Nome de gente cabe aqui. O limite existe para que uma URL hostil não
   empurre um parágrafo para dentro da saudação. */
const LIMITE_NOME = 80;

function preenchido(valor) {
  return typeof valor === 'string' && valor.trim() !== '';
}

function normalizarEmail(valor) {
  if (typeof valor !== 'string') return null;
  const limpo = valor.trim().toLowerCase();
  return FORMATO_EMAIL.test(limpo) ? limpo : null;
}

function normalizarNome(valor) {
  if (typeof valor !== 'string') return null;
  /* Só as pontas: espaço no meio e acento são parte do nome. */
  return valor.trim().slice(0, LIMITE_NOME) || null;
}

/** ISO válido vira milissegundos; qualquer outra coisa vira o padrão. */
function instante(valor, padrao) {
  const t = typeof valor === 'string' ? Date.parse(valor) : NaN;
  return Number.isFinite(t) ? t : padrao;
}

function zerar() {
  PARTICIPANTE.nome = null;
  PARTICIPANTE.email = null;
  PARTICIPANTE.origem = null;
  PARTICIPANTE.capturadoEm = null;
  PARTICIPANTE.expiraEm = null;
  return PARTICIPANTE;
}

function guardar() {
  try {
    sessionStorage.setItem(CHAVE_PARTICIPANTE, JSON.stringify({
      nome: PARTICIPANTE.nome,
      email: PARTICIPANTE.email,
      origem: PARTICIPANTE.origem,
      capturadoEm: PARTICIPANTE.capturadoEm,
      expiraEm: PARTICIPANTE.expiraEm,
    }));
  } catch { /* aba privada ou storage cheio: a identidade só não persiste */ }
}

function esquecer() {
  try { sessionStorage.removeItem(CHAVE_PARTICIPANTE); }
  catch { /* nada a fazer — e nada a registrar, log nenhum vê e-mail */ }
}

/* Tira `email` e `nome` da URL e não toca em mais nada: `tutorial`,
   `preview`, utm_*, `origem_codigo` e o hash continuam onde estavam.
   `origem_codigo` fica pela mesma razão que os utm_*: é código de entrada,
   não dado pessoal — e um link copiado deve continuar dizendo por qual porta
   a pessoa chegou. A limpeza existe para e-mail e nome, que são dela. */
function limparUrl(params) {
  try {
    params.delete('email');
    params.delete('nome');
    const query = params.toString();
    history.replaceState(history.state, '',
      location.pathname + (query ? '?' + query : '') + location.hash);
  } catch { /* sem History API a página segue: só a URL fica feia */ }
}

/**
 * Normaliza, valida e persiste uma identidade. Devolve `PARTICIPANTE`.
 *
 * E-mail presente mas fora do formato descarta a identidade inteira: um
 * cadastro pela metade erra mais do que acerta, e nada seria encontrado
 * no banco. E-mail ausente é outro caso — um nome sozinho serve para
 * cumprimentar, e é só isso que ele faz.
 */
export function definirParticipante(dados) {
  const entrada = dados && typeof dados === 'object' ? dados : {};
  const email = normalizarEmail(entrada.email);
  const nome = normalizarNome(entrada.nome);

  if ((preenchido(entrada.email) && !email) || (!email && !nome)) {
    esquecer();
    return zerar();
  }

  const agora = Date.now();
  const capturadoEm = instante(entrada.capturadoEm, agora);
  const expiraEm = instante(entrada.expiraEm, capturadoEm + VALIDADE_MS);

  /* Vale para o registro que voltou do storage e para qualquer data que
     chegue já vencida. A checagem vive num lugar só. */
  if (expiraEm <= agora) {
    esquecer();
    return zerar();
  }

  PARTICIPANTE.nome = nome;
  PARTICIPANTE.email = email;
  PARTICIPANTE.origem = preenchido(entrada.origem) ? entrada.origem.trim() : 'manual';
  PARTICIPANTE.capturadoEm = new Date(capturadoEm).toISOString();
  PARTICIPANTE.expiraEm = new Date(expiraEm).toISOString();
  guardar();
  return PARTICIPANTE;
}

/** Apaga a identidade da memória e da aba. */
export function limparIdentidade() {
  esquecer();
  return zerar();
}

/**
 * Cópia da identidade atual, já conferida contra o prazo — uma aba
 * aberta há treze horas volta anônima aqui, sem depender de recarga.
 * É cópia para que ninguém escreva no original por acidente.
 */
export function obterParticipante() {
  if (PARTICIPANTE.expiraEm && Date.parse(PARTICIPANTE.expiraEm) <= Date.now()) {
    limparIdentidade();
  }
  return {
    nome: PARTICIPANTE.nome,
    email: PARTICIPANTE.email,
    origem: PARTICIPANTE.origem,
    capturadoEm: PARTICIPANTE.capturadoEm,
    expiraEm: PARTICIPANTE.expiraEm,
  };
}

/**
 * O código de entrada desta aba, se houver. Hidrata da aba na primeira
 * leitura — uma pessoa que entrou pelo app e navegou até o chat continua
 * tendo vindo pelo app.
 */
export function obterOrigemCodigo() {
  if (ORIGEM_CODIGO === undefined) {
    try {
      const guardado = sessionStorage.getItem(CHAVE_ORIGEM);
      ORIGEM_CODIGO = FORMATO_ORIGEM.test(guardado || '') ? guardado : null;
    } catch { ORIGEM_CODIGO = null; }
  }
  return ORIGEM_CODIGO;
}

/** Registra a porta de entrada. Só o que tem forma de código entra. */
function definirOrigemCodigo(valor) {
  const limpo = typeof valor === 'string' ? valor.trim().toLowerCase() : '';
  if (!FORMATO_ORIGEM.test(limpo)) return obterOrigemCodigo();
  ORIGEM_CODIGO = limpo;
  try { sessionStorage.setItem(CHAVE_ORIGEM, limpo); }
  catch { /* aba privada: a origem vale só para esta carga da página */ }
  return ORIGEM_CODIGO;
}

/**
 * Lê a identidade de quem abriu a página: Yazo, depois aba, depois
 * anônimo. Chamada de propósito pelo `app.js`, nunca no import.
 */
export function capturarIdentidade() {
  let params = null;
  try { params = new URLSearchParams(location.search); }
  catch { /* URL ilegível não derruba a página */ }

  /* A porta de entrada é lida antes de qualquer coisa e independe de haver
     identidade: quem abre o app oficial sem e-mail na URL continua tendo
     entrado pelo app oficial. */
  if (params && params.has('origem_codigo')) {
    definirOrigemCodigo(params.get('origem_codigo'));
  }

  const daYazo = params && (params.has('email') || params.has('nome'));
  const bruto = daYazo
    ? { email: params.get('email'), nome: params.get('nome'), origem: 'yazo_url' }
    : null;

  /* A URL é limpa antes de qualquer validação, e antes de olhar o modo:
     e-mail torto também é dado pessoal, e privacidade não depende de
     estar em preview. `preview`, `tutorial`, `utm_*` e o hash ficam. */
  if (daYazo) limparUrl(params);

  /* Preview da Central manda: o perfil simulado é o assunto daquela
     tela. A Yazo não atropela — o que veio na URL é descartado aqui,
     depois de já ter saído da barra de endereço. */
  if (params && params.get('preview') === '1') return PARTICIPANTE;

  if (bruto) return definirParticipante(bruto);

  try {
    const guardado = JSON.parse(sessionStorage.getItem(CHAVE_PARTICIPANTE));
    if (guardado && typeof guardado === 'object') return definirParticipante(guardado);
  } catch { /* vazio ou corrompido: segue anônimo */ }

  return limparIdentidade();
}
