import { afterEach } from 'vitest';
import { act, render, type RenderResult } from '@testing-library/react';
import { RouterProvider, createMemoryRouter } from 'react-router-dom';
import type { QueryClient } from '@tanstack/react-query';
import type { Papel, PerfilAdmin, SessaoAuth } from '@/contracts';
import { Provedores, criarClienteDeConsulta } from '@/App';
import { rotasAdmin } from '@/routes';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { HttpAdminDataProvider } from '@/services/http-admin-data-provider';
import { HybridAdminDataProvider } from '@/services/hybrid-admin-data-provider';
import type { AdminDataProvider } from '@/services/admin-data-provider';
import type { FabricaProvedor } from '@/services/provider-context';
import type { PortaAutenticacao } from '@/services/auth';

/* ============================================================
   AJUDANTES DE TESTE
   ============================================================
   Cada teste monta o painel inteiro — rotas, provedores e um banco
   novo em memória. É o mais próximo do uso real que dá para chegar sem
   navegador, e garante que a troca de página passa pelo roteador de
   verdade.

   Nada de rede: `vite.config.ts` zera as variáveis de ambiente em modo
   de teste, e quem precisa de HTTP injeta um `fetch` falso. Nenhum
   cliente real do Supabase é criado — se fosse, o timer de renovação
   de token manteria o processo do Vitest vivo depois do último teste. */

/* Os QueryClients criados aqui têm timers de coleta de lixo. Sem este
   encerramento eles ficam pendurados no processo — é a causa clássica
   de suíte que passa mas não devolve o terminal. */
const clientesVivos = new Set<QueryClient>();

afterEach(() => {
  for (const cliente of clientesVivos) {
    cliente.cancelQueries();
    cliente.unmount();
    cliente.clear();
  }
  clientesVivos.clear();
});

export interface OpcoesRender {
  rota?: string;
  papel?: Papel;
  provedor?: AdminDataProvider | FabricaProvedor;
  agora?: number;
  /** Ausente = modo simulado, sem login. */
  porta?: PortaAutenticacao | null;
  baseUrlApi?: string;
  chavePublicavel?: string | null;
  fetchImpl?: typeof fetch;
  /** Prefixo do roteador, como em produção (`/admin`). */
  basename?: string;
}

export interface ResultadoRender extends RenderResult {
  /**
   * O provedor em uso, para o teste inspecionar o banco depois de uma
   * escrita. Quando `provedor` é uma FÁBRICA, quem quiser a instância
   * captura ela dentro da própria fábrica — aqui o campo não se aplica.
   */
  provedor: MockAdminDataProvider;
}

export function renderizarPainel({
  rota = '/',
  papel = 'administrador',
  provedor,
  agora,
  porta,
  baseUrlApi,
  chavePublicavel = null,
  fetchImpl,
  basename,
}: OpcoesRender = {}): ResultadoRender {
  const usado = provedor ?? new MockAdminDataProvider({ latenciaMs: 0, agora });
  const instancia = typeof usado === 'function' ? null : usado;
  const roteador = createMemoryRouter(rotasAdmin, { initialEntries: [rota], basename });
  const cliente = criarClienteDeConsulta();
  clientesVivos.add(cliente);

  const resultado = render(
    <Provedores
      provider={usado}
      papelInicial={papel}
      queryClient={cliente}
      porta={porta}
      baseUrlApi={baseUrlApi}
      chavePublicavel={chavePublicavel}
      fetchImpl={fetchImpl}
    >
      <RouterProvider router={roteador} />
    </Provedores>,
  );

  return Object.assign(resultado, { provedor: instancia as MockAdminDataProvider });
}

/** Conta as linhas de dados da tabela atual. */
export function contarLinhas(container: HTMLElement): number {
  return container.querySelectorAll('tbody tr').length;
}

/* ============================================================
   PORTA DE AUTENTICAÇÃO FALSA
   ============================================================ */

export const SESSAO_DE_TESTE: SessaoAuth = {
  accessToken: 'token-de-teste-abc123',
  usuarioId: 'usr-teste',
  email: 'ana.ribeiro@exemplo.com.br',
  /* Bem no futuro: `obterToken` só renova quando falta menos de um
     minuto, e nenhum teste quer exercitar isso por acidente. */
  expiraEm: Math.floor(Date.now() / 1000) + 3600,
};

export interface PortaFalsa extends PortaAutenticacao {
  /** Empurra uma sessão (ou `null`) como se o Supabase tivesse avisado. */
  emitir: (sessao: SessaoAuth | null) => void;
  chamadas: { entrar: number; sair: number; encerrar: number };
  ouvintes: number;
}

export function criarPortaFalsa(
  opcoes: {
    sessaoInicial?: SessaoAuth | null;
    aoEntrar?: (email: string, senha: string) => Promise<SessaoAuth>;
    aoSair?: () => Promise<void>;
  } = {},
): PortaFalsa {
  let sessao = opcoes.sessaoInicial ?? null;
  const ouvintes = new Set<(s: SessaoAuth | null) => void>();
  const chamadas = { entrar: 0, sair: 0, encerrar: 0 };

  const porta: PortaFalsa = {
    chamadas,
    get ouvintes() {
      return ouvintes.size;
    },
    async obterSessao() {
      return sessao;
    },
    aoMudarSessao(ouvinte) {
      ouvintes.add(ouvinte);
      return () => ouvintes.delete(ouvinte);
    },
    async entrar(email, senha) {
      chamadas.entrar += 1;
      const nova = opcoes.aoEntrar
        ? await opcoes.aoEntrar(email, senha)
        : { ...SESSAO_DE_TESTE, email };
      sessao = nova;
      return nova;
    },
    async sair() {
      chamadas.sair += 1;
      await opcoes.aoSair?.();
      sessao = null;
      ouvintes.forEach((o) => o(null));
    },

    encerrar() {
      chamadas.encerrar += 1;
    },
    emitir(nova) {
      sessao = nova;
      /* Evento externo (o Supabase avisando) mexe no estado do React.
         Sem `act` o React reclama, e com razão: o teste afirmaria
         sobre uma árvore que ainda não terminou de atualizar. */
      act(() => {
        ouvintes.forEach((o) => o(nova));
      });
    },
  };

  return porta;
}

/* ============================================================
   FETCH FALSO
   ============================================================ */

export interface ChamadaHttp {
  url: string;
  metodo: string;
  cabecalhos: Record<string, string>;
}

export interface FetchFalso {
  fetch: typeof fetch;
  chamadas: ChamadaHttp[];
  /** Última chamada para um caminho que contenha o trecho dado. */
  ultima: (trecho: string) => ChamadaHttp | undefined;
}

export interface RotaFalsa {
  status?: number;
  corpo?: unknown;
  erroDeRede?: boolean;
}

/**
 * `fetch` de mentira dirigido por rotas.
 *
 * A chave é um trecho do caminho (`/admin/me`), opcionalmente com o
 * método na frente (`PATCH /admin/sessions/x`). Vence a chave MAIS
 * ESPECÍFICA — a que casa o caminho mais longo, e entre empates a que
 * declara método. Sem isso `/admin/sessions` capturaria também
 * `/admin/sessions/:id`, e o teste do item receberia uma lista.
 */
export function criarFetchFalso(rotas: Record<string, RotaFalsa>): FetchFalso {
  const chamadas: ChamadaHttp[] = [];

  const definicoes = Object.entries(rotas).map(([chave, rota]) => {
    const partes = chave.trim().split(' ');
    const temMetodo = partes.length > 1;
    return {
      metodo: temMetodo ? partes[0].toUpperCase() : null,
      caminho: temMetodo ? partes.slice(1).join(' ') : chave,
      rota,
    };
  });

  function escolher(url: string, metodo: string): RotaFalsa | undefined {
    const candidatas = definicoes.filter(
      (d) => url.includes(d.caminho) && (!d.metodo || d.metodo === metodo),
    );
    if (candidatas.length === 0) return undefined;
    candidatas.sort((a, b) => {
      const porCaminho = b.caminho.length - a.caminho.length;
      if (porCaminho !== 0) return porCaminho;
      return (b.metodo ? 1 : 0) - (a.metodo ? 1 : 0);
    });
    return candidatas[0].rota;
  }

  const impl = (async (entrada: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof entrada === 'string' ? entrada : entrada.toString();
    const metodo = (init?.method ?? 'GET').toUpperCase();
    const cabecalhos: Record<string, string> = {};
    const brutos = init?.headers;
    if (brutos) {
      if (brutos instanceof Headers) brutos.forEach((v, k) => (cabecalhos[k] = v));
      else Object.assign(cabecalhos, brutos as Record<string, string>);
    }
    chamadas.push({ url, metodo, cabecalhos });

    const rota = escolher(url, metodo);
    if (!rota) {
      return new Response(JSON.stringify({ codigo: 'nao_encontrado', mensagem: 'sem rota falsa' }), {
        status: 404,
        headers: { 'content-type': 'application/json' },
      });
    }
    if (rota.erroDeRede) throw new TypeError('Failed to fetch');

    return new Response(rota.corpo === undefined ? null : JSON.stringify(rota.corpo), {
      status: rota.status ?? 200,
      headers: { 'content-type': 'application/json', 'x-request-id': 'req_teste_0001' },
    });
  }) as unknown as typeof fetch;

  return {
    fetch: impl,
    chamadas,
    ultima: (trecho) => [...chamadas].reverse().find((c) => c.url.includes(trecho)),
  };
}

export const PERFIL_ADMINISTRADOR: PerfilAdmin = {
  id: 'usr-teste',
  email: 'ana.ribeiro@exemplo.com.br',
  nome: 'Ana Ribeiro',
  papel: 'administrador',
  permissoes: null,
};

/* ============================================================
   PAINEL EM MODO HÍBRIDO
   ============================================================
   Monta o painel autenticado com o HybridAdminDataProvider ligado a um
   `fetch` falso. É o ambiente dos testes de API real: nenhuma
   requisição sai, e cada chamada fica registrada para o teste afirmar
   método, URL e cabeçalhos. */

export const API_FALSA = 'https://api.exemplo.invalido/mindagent-admin';

/** Publicável de mentira. A real nunca entra em teste nem em commit. */
export const CHAVE_FALSA = 'sb_publishable_de_teste';

export const PERFIL_HTTP = {
  id: 'usr-teste',
  email: 'ana.ribeiro@exemplo.com.br',
  nome: 'Ana Ribeiro',
  papel: 'administrador',
};

export interface OpcoesHibrido {
  rota?: string;
  /** Rotas do `fetch` falso, além de `/admin/me`. */
  rotas?: Record<string, RotaFalsa>;
  perfil?: unknown;
}

export function renderizarHibrido({ rota = '/', rotas = {}, perfil }: OpcoesHibrido = {}) {
  const porta = criarPortaFalsa({ sessaoInicial: SESSAO_DE_TESTE });
  const falso = criarFetchFalso({
    '/admin/me': { corpo: perfil ?? PERFIL_HTTP },
    ...rotas,
  });
  const mock = new MockAdminDataProvider({ latenciaMs: 0 });

  const tela = renderizarPainel({
    rota,
    porta,
    baseUrlApi: API_FALSA,
    chavePublicavel: CHAVE_FALSA,
    fetchImpl: falso.fetch,
    provedor: (o) =>
      new HybridAdminDataProvider(
        new HttpAdminDataProvider({
          baseUrl: API_FALSA,
          fetchImpl: falso.fetch,
          chavePublicavel: CHAVE_FALSA,
          obterToken: o.obterToken,
          aoNaoAutorizado: o.aoNaoAutorizado,
        }),
        mock,
      ),
  });

  return { ...tela, falso, porta, mock };
}

/** Resposta de listagem no formato que a API devolve. */
export function lista(itens: unknown[], extra: { total?: number; pagina?: number; porPagina?: number } = {}) {
  return {
    itens,
    total: extra.total ?? itens.length,
    pagina: extra.pagina ?? 1,
    porPagina: extra.porPagina ?? Math.max(itens.length, 1),
  };
}
