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

import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, copyFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { randomUUID } from 'node:crypto';

const FONTE = new URL('../../supabase/functions/mindagent-chat/index.ts', import.meta.url);
const CHECKOUT_SHARED = new URL('../../supabase/functions/_shared/checkout-attribution.ts', import.meta.url);
const INTELLIGENCE_SHARED = new URL('../../supabase/functions/_shared/agent-intelligence.ts', import.meta.url);
const CONTACT_SHARED = new URL('../../supabase/functions/_shared/contact-profile.ts', import.meta.url);
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
  const pastaFuncao = join(dir, 'functions', 'mindagent-chat');
  const pastaShared = join(dir, 'functions', '_shared');
  mkdirSync(pastaFuncao, { recursive: true });
  mkdirSync(pastaShared, { recursive: true });
  copyFileSync(CHECKOUT_SHARED, join(pastaShared, 'checkout-attribution.ts'));
  copyFileSync(INTELLIGENCE_SHARED, join(pastaShared, 'agent-intelligence.ts'));
  copyFileSync(CONTACT_SHARED, join(pastaShared, 'contact-profile.ts'));
  const arquivo = join(pastaFuncao, 'index.mts');
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
    // Forma REAL de `mind_mensagem_registrar`, para onde
    // `mindagent_chat_save_message` delega: `{mensagem_id, duplicada, papel}`.
    // O stub antigo devolvia `{id}` e por isso deixou passar a evidência nula.
    mindagent_chat_save_message: (args) => ({
      mensagem_id: randomUUID(), duplicada: false, papel: args.p_role,
    }),
    mind_rota_capacidade: { ok: true, pode_executar: true, reason: null },
    mind_canal_rotas: { ok: true, canal: 'mindagent-web', rotas: ['cliente_suporte', 'concierge_summit'] },
    mind_agent_kit: KIT_COMPLETO,
    mind_pessoa_fatos: {
      ok: true,
      perfil: { primeiro_nome: 'Adriana', sobrenome: 'Drulla', empresa: 'Mind', cargo: 'CEO' },
      identificadores: [
        { canal: 'email', identificador: 'adriana@example.com' },
        { canal: 'whatsapp', identificador: '5511999999999' },
      ],
      conflitos_perfil: [],
    },
    mind_checkout_envio_registrar: (args) => ({
      ok: true,
      event_id: args.p_evento_id,
      conversation_id: args.p_conversa_id,
      channel: args.p_canal,
      agent_id: args.p_agente,
      reason: args.p_motivo,
    }),
    mindagent_chat_save_interests: { ok: true, saved: 1 },
    // Ledger de idempotência do Play. O padrão é o caminho sem repetição;
    // quem testa retry passa um ledger com estado (ver `ledgerEmMemoria`).
    mind_play_chamada_iniciar: () => ({ ok: true, estado: 'nova', chamada_id: randomUUID() }),
    mind_play_chamada_concluir: { ok: true },
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
  modelo = {
    answer: 'Resposta oficial de teste.', interests: [], checkout_sent: false,
    checkout_url: null, next_route: null, nome_informado: null,
    email_informado: null, whatsapp_informado: null,
    empresa_informada: null, cargo_informado: null,
  },
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
