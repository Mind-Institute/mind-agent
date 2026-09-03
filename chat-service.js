import { CONFIG, obterParticipante, obterOrigemCodigo } from './config.js';

const PREFIXO = 'mindagent:v1:' + CONFIG.eventSlug + ':';
const CHAVES = {
  auth: PREFIXO + 'auth',
  session: PREFIXO + 'chat-session',
  device: PREFIXO + 'device-id',
};

function ler(chave) {
  try { return JSON.parse(localStorage.getItem(chave)); }
  catch { return null; }
}

function salvar(chave, valor) {
  localStorage.setItem(chave, JSON.stringify(valor));
}

function remover(chave) {
  localStorage.removeItem(chave);
}

function id() {
  if (crypto.randomUUID) return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0;
    return (c === 'x' ? r : (r & 3 | 8)).toString(16);
  });
}

function dispositivo() {
  let atual = localStorage.getItem(CHAVES.device);
  if (!atual) {
    atual = id();
    localStorage.setItem(CHAVES.device, atual);
  }
  return atual;
}

async function authRequest(caminho, body) {
  const response = await fetch(CONFIG.supabaseUrl + caminho, {
    method: 'POST',
    headers: {
      apikey: CONFIG.supabasePublishableKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
    cache: 'no-store',
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload.access_token) {
    throw new Error(payload.msg || 'Não foi possível iniciar a sessão segura.');
  }
  const auth = {
    access_token: payload.access_token,
    refresh_token: payload.refresh_token,
    expires_at: payload.expires_at || Math.floor(Date.now() / 1000) + (payload.expires_in || 3600),
  };
  salvar(CHAVES.auth, auth);
  return auth;
}

async function autenticar(forcarNova = false) {
  if (forcarNova) remover(CHAVES.auth);
  const atual = ler(CHAVES.auth);
  const agora = Math.floor(Date.now() / 1000);
  if (atual?.access_token && Number(atual.expires_at) > agora + 60) return atual;

  if (atual?.refresh_token) {
    try {
      return await authRequest('/auth/v1/token?grant_type=refresh_token', {
        refresh_token: atual.refresh_token,
      });
    } catch {
      remover(CHAVES.auth);
      remover(CHAVES.session);
    }
  }
  return authRequest('/auth/v1/signup', {});
}

/* A identidade que vai para a NOSSA Edge Function — nunca para a OpenAI.
   É a `mindagent-chat` que procura o e-mail em `mind.people`, amarra o
   `participante_id` e monta o contexto público. O frontend só entrega o
   que a Yazo disse, e só quando há e-mail válido: sem e-mail não existe
   ninguém para procurar, e o campo nem aparece no corpo. */
function identidade() {
  const p = obterParticipante();
  if (!p.email) return undefined;
  return {
    email: p.email,
    name: p.nome || undefined,
    source: p.origem || 'yazo_url',
  };
}

async function chamar(message, clientMessageId, extra) {
  const auth = await autenticar();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 32000);
  try {
    const response = await fetch(
      CONFIG.supabaseUrl + '/functions/v1/' + CONFIG.chatFunction,
      {
        method: 'POST',
        headers: {
          apikey: CONFIG.supabasePublishableKey,
          Authorization: 'Bearer ' + auth.access_token,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message,
          event_slug: CONFIG.eventSlug,
          device_id: dispositivo(),
          client_message_id: clientMessageId,
          session: ler(CHAVES.session) || undefined,
          identity: identidade(),
          /* Porta de entrada, não identidade. Só tem efeito na abertura da
             conversa — depois disso o banco já gravou e não reescreve. */
          origem_codigo: obterOrigemCodigo() || undefined,
          ...(extra || {}),
        }),
        cache: 'no-store',
        signal: controller.signal,
      },
    );
    const payload = await response.json().catch(() => ({}));
    return { response, payload };
  } finally {
    clearTimeout(timeout);
  }
}

export async function enviarMensagem(message) {
  const texto = String(message || '').trim();
  if (!texto) throw new Error('Escreva uma mensagem.');
  const clientMessageId = id();

  let resultado = await chamar(texto, clientMessageId);
  if (resultado.response.status === 401) {
    remover(CHAVES.auth);
    remover(CHAVES.session);
    await autenticar(true);
    resultado = await chamar(texto, clientMessageId);
  } else if (resultado.payload?.error?.code === 'session_expired') {
    remover(CHAVES.session);
    resultado = await chamar(texto, clientMessageId);
  }

  if (!resultado.response.ok || !resultado.payload?.ok) {
    throw new Error(resultado.payload?.error?.message || 'Não consegui responder agora. Tente novamente.');
  }
  if (resultado.payload.session) salvar(CHAVES.session, resultado.payload.session);
  return resultado.payload;
}

/* Respostas de botão também são conversa. Elas usam a mesma sessão e vão ao
   Core sem chamar o LLM. A chave permanece igual no retry para que a evidência
   não duplique quando a rede oscila. */
export async function enviarSinalJornada(field, values) {
  const lista = (Array.isArray(values) ? values : [values])
    .filter((item) => typeof item === 'string' && item.trim())
    .map((item) => item.trim());
  if (!field || !lista.length) throw new Error('Resposta da jornada vazia.');
  const clientActionId = id();
  const extra = { journey_signal: { field, values: lista }, client_action_id: clientActionId };

  let resultado = await chamar('', clientActionId, extra);
  if (resultado.response.status === 401) {
    remover(CHAVES.auth);
    remover(CHAVES.session);
    await autenticar(true);
    resultado = await chamar('', clientActionId, extra);
  } else if (resultado.payload?.error?.code === 'session_expired') {
    remover(CHAVES.session);
    resultado = await chamar('', clientActionId, extra);
  }
  if (!resultado.response.ok || !resultado.payload?.ok) {
    throw new Error(resultado.payload?.error?.message || 'Não consegui guardar esta resposta.');
  }
  if (resultado.payload.session) salvar(CHAVES.session, resultado.payload.session);
  return resultado.payload;
}
