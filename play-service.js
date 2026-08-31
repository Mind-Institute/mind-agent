/* ============================================================
   PLAY — AÇÕES DO PARTICIPANTE
   ============================================================
   O que o participante DIZ sobre o que viveu: nota de sessão, o que
   ficou, NPS do evento, percepção da operação e coletas tipadas
   (votação, retorno de masterclass/workshop).

   Este arquivo é só o CONTRATO DO CLIENTE. Ele não decide, não pontua,
   não recomenda e não escreve nada sozinho — monta a chamada de uma
   ferramenta já registrada e entrega para o runtime executar.

   PORQUE ELE NÃO FALA COM O BANCO
   -------------------------------
   As funções que gravam (`public.mind_play_*`) são SECURITY DEFINER com
   EXECUTE só para `service_role`. O navegador tem a publishable key e um
   JWT anônimo — e é assim que tem de ser. Quem executa é o runtime do
   Concierge, do lado do servidor, que também é quem sabe QUEM é a pessoa:
   o `pessoa_id` nunca sai daqui, ele é resolvido pela sessão.

   O CONTRATO É O DA FERRAMENTA JÁ REGISTRADA
   ------------------------------------------
   `argumentos` é o objeto literal do `json_schema` de
   `concierge.ferramentas`. Nada é traduzido no caminho:

     registrar_feedback_sessao  { sessao_id, nota, relevancia, insight,
                                  intencao_aplicar, o_que_faltou, comentario }
     registrar_nps              { nota, comentario }
     registrar_feedback_evento  { categoria, sentimento, severidade,
                                  comentario, local }
     registrar_feedback         { tipo, valor, contexto }

   O corpo enviado ao runtime:

     { ferramenta, argumentos, event_slug, session, client_action_id }

   A resposta esperada:

     { ok: true,  resultado: <jsonb da RPC> }
     { ok: false, error: { code, message } }

   ENQUANTO O ENDPOINT NÃO EXISTE
   ------------------------------
   `CONFIG.playActionUrl` nasce nula, do mesmo jeito que `apiBaseUrl`
   nasceu antes do `mindagent-bootstrap`. Nula, toda chamada devolve
   `{ ok:false, motivo:'sem_endpoint' }` — e quem chama tem de dizer a
   verdade na tela em vez de fingir que gravou.

   IDENTIDADE — E POR QUE ELA NÃO EXIGE CONVERSA ANTES
   ---------------------------------------------------
   v1 NÃO aceita coleta anônima (decisão congelada): sem pessoa, a coleta
   não executa. Mas "person-bound" NÃO quer dizer "só depois de conversar
   com o Concierge". Quem chega identificado e vai direto ao Play — sem
   nunca ter aberto o chat — tem de conseguir registrar.

   Por isso o que viaja é a IDENTIDADE (a mesma que o `chat-service.js`
   manda para o `mindagent-chat`), e a `session` só quando já existe. Quem
   resolve identidade → `pessoa_id` e quem estabelece/vincula a sessão é o
   runtime canônico do Concierge, do lado do servidor. Aqui não há segundo
   lifecycle de sessão: a autenticação vem do `chat-service.js`, que é o
   dono dela, por `garantirAutenticacao()`.

   Sem identidade e sem sessão não há pessoa: devolve
   `{ ok:false, motivo:'sem_identidade' }`.
*/

import { CONFIG, obterParticipante } from './config.js';
import { garantirAutenticacao } from './chat-service.js';

/* A sessão de conversa, quando já existe, é lida daqui. Escrever nela é do
   `chat-service.js`. */
const CHAVE_SESSAO = 'mindagent:v1:' + CONFIG.eventSlug + ':chat-session';

/* Nomes das ferramentas já registradas em `concierge.ferramentas`.
   Exportado para que a tela nomeie a ferramenta em vez de repetir string
   solta — e para que uma renomeação apareça num lugar só. */
export const FERRAMENTAS = {
  feedbackSessao: 'registrar_feedback_sessao',
  nps: 'registrar_nps',
  feedbackEvento: 'registrar_feedback_evento',
  coleta: 'registrar_feedback',
};

function ler(chave) {
  try { return JSON.parse(localStorage.getItem(chave)); }
  catch { return null; }
}

function id() {
  if (crypto.randomUUID) return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0;
    return (c === 'x' ? r : (r & 3 | 8)).toString(16);
  });
}

/* Só os campos preenchidos vão no corpo. Mandar `nota: null` faria o
   writer entender "sem nota" e apagar nada — mas mandar chave vazia é
   ruído no contrato, e o preenchimento parcial existe justamente para
   completar aos poucos. */
function limpar(argumentos) {
  const saida = {};
  Object.entries(argumentos || {}).forEach(([chave, valor]) => {
    if (valor === null || valor === undefined) return;
    if (typeof valor === 'string' && valor.trim() === '') return;
    saida[chave] = typeof valor === 'string' ? valor.trim() : valor;
  });
  return saida;
}

/**
 * Executa uma ferramenta do Play. Nunca lança: a recusa é dado, igual à
 * taxonomia do lado do banco, para a tela poder decidir o que dizer.
 *
 * @returns {Promise<{ok:boolean, resultado?:object, motivo?:string, mensagem?:string}>}
 */
export async function executar(ferramenta, argumentos) {
  /* Sessão de conversa é opcional: quem nunca falou com o Concierge não tem
     uma, e ainda assim pode registrar. Quando existe, viaja — a coleta fica
     ligada à conversa em que aconteceu. */
  const bruta = ler(CHAVE_SESSAO);
  const session = (bruta?.id && bruta?.conversation_id && bruta?.token) ? bruta : undefined;

  /* v1 é person-bound: a identidade da Yazo basta, a conversa não é
     pré-requisito. Esta checagem vem ANTES da do endpoint de propósito —
     ser anônimo é recusa de produto, e vale esteja o endpoint no ar ou não.
     Se o endpoint viesse primeiro, a recusa certa ficaria mascarada por uma
     circunstância de deploy, e o dia em que a URL fosse preenchida mudaria
     silenciosamente o motivo. */
  const p = obterParticipante();
  const identity = p.email ? { email: p.email, name: p.nome || undefined, source: p.origem || 'yazo_url' } : undefined;
  if (!identity && !session) {
    return { ok: false, motivo: 'sem_identidade' };
  }

  if (!CONFIG.playActionUrl) {
    return { ok: false, motivo: 'sem_endpoint' };
  }

  let auth;
  try {
    auth = await garantirAutenticacao();
  } catch {
    return { ok: false, motivo: 'sem_sessao' };
  }
  if (!auth?.access_token) return { ok: false, motivo: 'sem_sessao' };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);
  try {
    const resposta = await fetch(CONFIG.playActionUrl, {
      method: 'POST',
      headers: {
        apikey: CONFIG.supabasePublishableKey,
        Authorization: 'Bearer ' + auth.access_token,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        ferramenta,
        argumentos: limpar(argumentos),
        event_slug: CONFIG.eventSlug,
        /* Quem resolve identidade -> pessoa_id e estabelece/vincula a sessão
           é o runtime do Concierge. `session` vai só quando já existe. */
        identity,
        session,
        /* Rede repete; a pessoa não. A chave viaja para o runtime poder
           deduplicar a MESMA tentativa. Os writers já são idempotentes
           por chave natural — isto é a camada de transporte. */
        client_action_id: id(),
      }),
      cache: 'no-store',
      signal: controller.signal,
    });

    const payload = await resposta.json().catch(() => ({}));
    if (!resposta.ok || !payload?.ok) {
      return {
        ok: false,
        motivo: payload?.error?.code || 'falhou',
        mensagem: payload?.error?.message,
      };
    }
    return { ok: true, resultado: payload.resultado };
  } catch (e) {
    return { ok: false, motivo: e?.name === 'AbortError' ? 'timeout' : 'sem_rede' };
  } finally {
    clearTimeout(timeout);
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Nota e/ou o que ficou de uma sessão. Preenchimento parcial é esperado.
 *
 * `sessao_id` tem de ser o id CANÔNICO de `summit_2026.sessions`. Hoje a
 * programação chega ao app pelo `dados/summit.json`, cujos ids são slugs
 * (`d1-09_00-abertura`), porque `public.mindagent_bootstrap` está quebrada em
 * produção — ela lê `summit.*`/`comum.*`, schemas que foram renomeados (é uma
 * das 19 da §8 do `BACKLOG.md`; o efeito no Play está na §14.8).
 *
 * A recusa acontece aqui, e não no banco, de propósito: a tela precisa saber
 * que não deu para vincular, e não faz sentido gastar uma chamada de
 * ferramenta e um registro de falha para descobrir o que já se sabe.
 */
export function registrarFeedbackSessao(argumentos) {
  if (!UUID.test(String(argumentos?.sessao_id || ''))) {
    return Promise.resolve({ ok: false, motivo: 'sessao_sem_id_canonico' });
  }
  return executar(FERRAMENTAS.feedbackSessao, argumentos);
}

/** NPS do Summit: nota 0–10 e comentário. Uma por pessoa. */
export function registrarNps(argumentos) {
  return executar(FERRAMENTAS.nps, argumentos);
}

/** Percepção sobre a operação do evento (alimentação, acesso, espaço…). */
export function registrarFeedbackEvento(argumentos) {
  return executar(FERRAMENTAS.feedbackEvento, argumentos);
}

/** Coleta tipada: votação, retorno de masterclass/workshop, joinha. */
export function registrarColeta(argumentos) {
  return executar(FERRAMENTAS.coleta, argumentos);
}
