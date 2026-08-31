/* ============================================================================
 * HARNESS DE COMPORTAMENTO DA EDGE `mindagent-chat`
 *
 * Carrega o handler REAL de `supabase/functions/mindagent-chat/index.ts` dentro
 * do Node e o executa com `Deno`, cliente Supabase e OpenAI stubados. O fonte
 * não é reescrito além do especificador do `npm:@supabase/supabase-js`, que o
 * Node não resolve — se esse import mudar, o harness falha alto em vez de
 * testar outra coisa.
 *
 * Por que isso e não só leitura de fonte: ordem de RPC, fail-closed, recusa
 * person-bound e repasse de `sensitivity` são COMPORTAMENTO. Um refactor pode
 * manter o texto e perder o comportamento.
 * ==========================================================================*/

import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { randomUUID } from 'node:crypto';

const FONTE = new URL('../../supabase/functions/mindagent-chat/index.ts', import.meta.url);
const STUB = new URL('./supabase-stub.mjs', import.meta.url);
const IMPORT_VIVO = '"npm:@supabase/supabase-js@2.112.3"';

export const AUTH_USER_ID = '11111111-1111-4111-8111-111111111111';
export const PESSOA_ID = '22222222-2222-4222-8222-222222222222';

const ENV_PADRAO = {
  SUPABASE_URL: 'https://projeto.supabase.co',
  SUPABASE_ANON_KEY: 'chave-publicavel-de-teste',
  SUPABASE_SERVICE_ROLE_KEY: 'chave-secreta-de-teste',
  OPENAI_API_KEY: 'chave-openai-de-teste',
  OPENAI_MODEL: 'gpt-5.4-mini',
};

/** Marca uma RPC como falha do banco (o cliente devolve `{data:null, error}`). */
export const erroRpc = (mensagem) => ({ __erro: mensagem });

/** Kit completo: os dois blocos obrigatórios + playbook não vazio. */
export const KIT_COMPLETO = {
  ok: true,
  meta: { kit_disponivel: true, rota: 'concierge_summit' },
  playbook: 'PLAYBOOK CANÔNICO DO CONCIERGE (v7, vindo do Kit).',
  tools: [],
  structured: {
    evento: { slug: 'mind-summit-2026', nome: 'Mind Summit 2026' },
    programacao: {
      sessions: [{ id: 's1', title: 'Abertura', starts_at_local: '09:00', ends_at_local: '09:40' }],
      speakers: [{ id: 'p1', name: 'Palestrante Oficial' }],
      locations: [{ id: 'l1', name: 'Auditório' }],
    },
  },
};

let estado = null;
let handler = null;

async function carregarHandler() {
  if (handler) return handler;

  const original = readFileSync(FONTE, 'utf8');
  const partes = original.split(IMPORT_VIVO);
  if (partes.length !== 2) {
    throw new Error('o import do cliente Supabase mudou — ajuste o harness antes de confiar nos testes');
  }
  const dir = mkdtempSync(join(tmpdir(), 'mindagent-edge-'));
  const arquivo = join(dir, 'index.mts');
  writeFileSync(arquivo, partes.join(JSON.stringify(STUB.href)));

  let capturado = null;
  globalThis.Deno = {
    env: { get: (nome) => (estado && estado.env[nome] != null ? estado.env[nome] : undefined) },
    serve: (fn) => { capturado = fn; return { finished: Promise.resolve() }; },
  };
  await import(pathToFileURL(arquivo).href);
  if (typeof capturado !== 'function') throw new Error('Deno.serve não recebeu o handler');
  handler = capturado;
  return handler;
}

function respostasPadrao() {
  const sessionId = randomUUID();
  const conversationId = randomUUID();
  return {
    mindagent_chat_start: {
      session_id: sessionId,
      conversation_id: conversationId,
      expires_at: '2026-09-01T12:00:00+00:00',
    },
    mindagent_chat_bind_identity: { found: true, conflict: false },
    mindagent_chat_get_context: {
      participant_profile: {
        participant_id: PESSOA_ID,
        name: 'Adriana',
        role: 'CEO',
        company: 'Mind',
        interests: [{ label: 'saúde mental corporativa' }],
      },
      expires_at: '2026-09-01T12:00:00+00:00',
      messages: [],
    },
    mindagent_chat_save_message: (args) => ({ id: randomUUID(), role: args.p_role }),
    mind_rota_capacidade: { ok: true, pode_executar: true, reason: null },
    mind_agent_kit: KIT_COMPLETO,
    mindagent_chat_save_interests: { ok: true, saved: 1 },
    mind_play_feedback_sessao: { ok: true, id: randomUUID() },
    mind_play_nps: { ok: true, id: randomUUID() },
    mind_play_feedback_evento: { ok: true, id: randomUUID() },
    mind_play_feedback: { ok: true, id: randomUUID() },
  };
}

/**
 * Executa um turno real contra o handler versionado.
 *
 * `rpc` sobrescreve as respostas padrão por nome; `undefined` como valor
 * significa "esta RPC não deveria ser chamada" e devolve erro.
 */
export async function chamar({
  corpo = {},
  env = {},
  rpc = {},
  usuario = { id: AUTH_USER_ID },
  autorizacao = 'Bearer token-de-acesso-de-teste',
  modelo = { answer: 'Resposta oficial de teste.', interests: [] },
  openaiStatus = 200,
  metodo = 'POST',
  caminho = '/functions/v1/mindagent-chat',
} = {}) {
  const fn = await carregarHandler();
  const chamadas = [];
  const openai = [];

  estado = {
    env: { ...ENV_PADRAO, ...env },
    rpc: { ...respostasPadrao(), ...rpc },
  };

  globalThis.__MIND_EDGE_TESTE__ = {
    getUser: async () => (usuario
      ? { data: { user: usuario }, error: null }
      : { data: { user: null }, error: { message: 'invalid token' } }),
    rpc: async (nome, args) => {
      chamadas.push({ nome, args });
      const tem = Object.prototype.hasOwnProperty.call(estado.rpc, nome);
      const definido = tem ? estado.rpc[nome] : undefined;
      if (definido === undefined) {
        return { data: null, error: { message: `rpc fora do cenário: ${nome}` } };
      }
      const valor = typeof definido === 'function' ? definido(args) : definido;
      if (valor && valor.__erro) return { data: null, error: { message: valor.__erro } };
      return { data: valor, error: null };
    },
  };

  // O executor loga JSON estruturado em toda decisão. Aqui os logs viram dado
  // do teste — e param de poluir a saída do runner.
  const logs = [];
  const consoleOriginal = { info: console.info, warn: console.warn, error: console.error };
  for (const nivel of ['info', 'warn', 'error']) {
    console[nivel] = (linha) => {
      try { logs.push({ nivel, ...JSON.parse(linha) }); } catch { logs.push({ nivel, linha }); }
    };
  }

  const fetchOriginal = globalThis.fetch;
  globalThis.fetch = async (recurso, init = {}) => {
    const corpoEnviado = init.body ? JSON.parse(init.body) : null;
    openai.push({ url: String(recurso), corpo: corpoEnviado, headers: init.headers ?? {} });
    const carga = openaiStatus === 200
      ? { output_text: JSON.stringify(modelo) }
      : { error: { code: 'erro_de_teste', type: 'invalid_request_error' } };
    return new Response(JSON.stringify(carga), {
      status: openaiStatus,
      headers: { 'Content-Type': 'application/json' },
    });
  };

  let resposta;
  try {
    const req = new Request(`https://projeto.supabase.co${caminho}`, {
      method: metodo,
      headers: {
        'Authorization': autorizacao,
        'Content-Type': 'application/json',
        'Origin': 'https://app.exemplo.com',
      },
      ...(metodo === 'GET' ? {} : { body: JSON.stringify(corpo) }),
    });
    resposta = await fn(req);
  } finally {
    globalThis.fetch = fetchOriginal;
    globalThis.__MIND_EDGE_TESTE__ = null;
    Object.assign(console, consoleOriginal);
  }

  const texto = await resposta.text();
  return {
    status: resposta.status,
    corpo: texto ? JSON.parse(texto) : null,
    chamadas,
    rpcs: chamadas.map((c) => c.nome),
    openai,
    logs,
    evento: (nome) => logs.find((l) => l.event === nome),
    chamada: (nome) => chamadas.find((c) => c.nome === nome),
    chamadasDe: (nome) => chamadas.filter((c) => c.nome === nome),
  };
}
