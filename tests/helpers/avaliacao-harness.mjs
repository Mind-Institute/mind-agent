/* ============================================================================
 * HARNESS DA EDGE `mindagent-avaliacao`
 *
 * Carrega o handler REAL dentro do Node, com `Deno` e o cliente Supabase
 * stubados. O fonte não é reescrito além do especificador `npm:` do
 * supabase-js, que o Node não resolve.
 *
 * Por que isto e não leitura de fonte: resolução de identidade, recusa de
 * `participante_id` vindo do cliente, permissão de admin e tradução de erro
 * são COMPORTAMENTO. Um refactor mantém o texto e perde o comportamento.
 * ==========================================================================*/

import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const FONTE = new URL('../../supabase/functions/mindagent-avaliacao/index.ts', import.meta.url);
const STUB = new URL('./supabase-stub-avaliacao.mjs', import.meta.url);
const IMPORT_VIVO = '"npm:@supabase/supabase-js@2.112.3"';

export const AUTH_USER_ID = '11111111-1111-4111-8111-111111111111';
export const SESSAO_VALIDA = 'dd7bc146-110c-4085-ab3a-4548a17b15f7';

const ENV_PADRAO = {
  SUPABASE_URL: 'https://projeto.supabase.co',
  SUPABASE_ANON_KEY: 'chave-publicavel-de-teste',
  SUPABASE_SERVICE_ROLE_KEY: 'chave-secreta-de-teste',
};

export const erroRpc = (mensagem, code) => ({ __erro: mensagem, __code: code });

let handler = null;
let estado = null;

async function carregarHandler() {
  if (handler) return handler;

  const fonte = readFileSync(FONTE, 'utf8');
  const partes = fonte.split(IMPORT_VIVO);
  if (partes.length !== 2) {
    throw new Error('o import do supabase-js mudou — o harness precisa ser revisto');
  }
  const pasta = mkdtempSync(join(tmpdir(), 'avaliacao-'));
  const arquivo = join(pasta, 'index.mts');
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

function estadoPadrao() {
  return {
    ativo: true,
    identificado: true,
    evento: { slug: 'mind-summit-2026', nome: 'Mind Summit 2026', fuso: 'America/Sao_Paulo',
              dias: ['2026-09-16', '2026-09-17'] },
    dia: '2026-09-16',
    formularioVersao: 1,
    enviado: false,
    enviadoEm: null,
    experienciaSugerida: 'prime',
    atividades: [
      { id: SESSAO_VALIDA, titulo: 'Do benefício à transformação', inicio: '09:15', fim: '09:40',
        espaco: 'Arena Mind', tipo: 'palestra', ingressos: ['mind', 'vip', 'prime', 'camarote'],
        operacional: false, palestrantes: ['Adriana Drulla'] },
    ],
  };
}

function respostasPadrao() {
  return {
    mind_avaliacao_do_dia_estado: estadoPadrao(),
    mind_avaliacao_do_dia_registrar: { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                                       jaRegistrado: false, dia: '2026-09-16' },
    mind_identidade_resolver: { pessoa_id: '22222222-2222-4222-8222-222222222222' },
    mind_avaliacao_do_dia_relatorio: { kpis: { respondentes: 0 }, porAtividade: [] },
    mind_avaliacao_do_dia_respostas: { total: 0, pagina: 1, porPagina: 50, itens: [] },

    /* A pesquisa do evento inteiro: sem dia, sem atividades, e com a
       janela no lugar da grade. */
    mind_avaliacao_do_evento_estado: {
      ativo: true, motivo: null, identificado: true,
      evento: { slug: 'mind-summit-2026', nome: 'Mind Summit 2026', fuso: 'America/Sao_Paulo',
                dias: ['2026-09-16', '2026-09-17'] },
      janela: { abre: '2026-09-18', fecha: '2026-09-30' },
      formularioVersao: 1, enviado: false, enviadoEm: null, experienciaSugerida: 'prime',
    },
    mind_avaliacao_do_evento_registrar: { id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                                          jaRegistrado: false },
    mind_avaliacao_do_evento_relatorio: { kpis: { respondentes: 0 } },
    mind_avaliacao_do_evento_respostas: { total: 0, pagina: 1, porPagina: 50, itens: [] },
  };
}

/**
 * Executa uma chamada real contra o handler versionado.
 * Devolve `{ resposta, corpo, chamadas }`.
 */
export async function chamar({
  metodo = 'GET',
  caminho = '/functions/v1/mindagent-avaliacao/estado',
  busca = '',
  corpo,
  env = {},
  rpc = {},
  usuario = { id: AUTH_USER_ID },
  autorizacao = 'Bearer token-de-acesso-de-teste',
  cabecalhos = {},
  papelAdmin = { display_name: 'Adriana', role: 'administrador', active: true },
} = {}) {
  const fn = await carregarHandler();
  const chamadas = [];

  estado = { env: { ...ENV_PADRAO, ...env }, rpc: { ...respostasPadrao(), ...rpc } };

  globalThis.__MIND_AVALIACAO_TESTE__ = {
    getUser: async () => (usuario
      ? { data: { user: usuario }, error: null }
      : { data: { user: null }, error: { message: 'invalid token' } }),
    tabela: async () => ({ data: papelAdmin, error: null }),
    rpc: async (nome, args) => {
      chamadas.push({ nome, args });
      const tem = Object.prototype.hasOwnProperty.call(estado.rpc, nome);
      const definido = tem ? estado.rpc[nome] : undefined;
      if (definido === undefined) {
        return { data: null, error: { message: `rpc fora do cenário: ${nome}` } };
      }
      const valor = typeof definido === 'function' ? definido(args) : definido;
      if (valor && valor.__erro) {
        return { data: null, error: { message: valor.__erro, code: valor.__code } };
      }
      return { data: valor, error: null };
    },
  };

  const cabecalhosDoPedido = { Origin: 'http://localhost:5174', ...cabecalhos };
  if (autorizacao) cabecalhosDoPedido.Authorization = autorizacao;
  if (corpo !== undefined) {
    cabecalhosDoPedido['content-type'] = 'application/json';
    cabecalhosDoPedido['content-length'] = String(JSON.stringify(corpo).length);
  }

  const pedido = new Request('https://projeto.supabase.co' + caminho + busca, {
    method: metodo,
    headers: cabecalhosDoPedido,
    body: corpo === undefined ? undefined : JSON.stringify(corpo),
  });

  const resposta = await fn(pedido);
  const texto = await resposta.text();
  let lido = null;
  try { lido = texto ? JSON.parse(texto) : null; } catch { lido = texto; }
  return { resposta, corpo: lido, chamadas };
}

/** Uma resposta completa e válida, para os testes partirem dela. */
export function respostaValida(extra = {}) {
  return {
    eventSlug: 'mind-summit-2026',
    dia: '2026-09-16',
    experiencia: 'prime',
    profissao: 'Gerente de RH',
    expectativas: 'Entender como medir bem-estar.',
    notaRelevancia: 4,
    notaProgramacao: 5,
    maisGostou: null,
    melhorar: null,
    comentario: null,
    atividades: [{ sessaoId: SESSAO_VALIDA, nota: 0 }],
    ...extra,
  };
}
