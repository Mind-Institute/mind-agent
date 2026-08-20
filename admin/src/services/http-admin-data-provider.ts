/* ============================================================
   HttpAdminDataProvider — preparado, não ligado
   ============================================================
   Esta classe existe para provar que a troca de mock por rede não
   mexe em nenhuma página: mesmos métodos, mesmos tipos, mesmos erros.

   Ela NÃO aponta para nenhuma URL real. `VITE_ADMIN_API_BASE_URL` vem
   vazia no `.env.example`, e sem ela o construtor recusa a criação em
   vez de chutar um endereço.

   REGRAS QUE NÃO PODEM SER QUEBRADAS AQUI
   ---------------------------------------
   - O navegador NUNCA fala com o Postgres direto. Só com Edge Function.
   - `service_role` e secret key não existem neste código, nem em
     variável, nem em header. Quem tem chave administrativa é o backend.
   - O token vai no header `Authorization`, nunca na URL.
   - Nenhum dado pessoal (e-mail, telefone) entra em query string: a
     busca vai por `POST`/header quando chegar a hora, ou por id.
   - Nada de `console.log` de token, header ou corpo de resposta. */

import {
  AdminApiError,
  type CodigoErroAdmin,
  type ListFilters,
  type ListResult,
  type MapaRecursos,
  type NomeRecurso,
  type OpcoesEscrita,
  type ReciboReindexacao,
  type ResumoPainel,
} from '@/contracts';
import type { AdminDataProvider } from './admin-data-provider';

/** Como o painel obtém o token da sessão. Hoje devolve `null`. */
export type ProvedorDeToken = () => Promise<string | null>;

export interface OpcoesHttp {
  baseUrl: string;
  /**
   * Será ligado ao Supabase Auth: `supabase.auth.getSession()` →
   * `session.access_token`. Enquanto não existe, devolve `null` e a
   * Edge Function responde 401 — que é o comportamento correto.
   */
  obterToken?: ProvedorDeToken;
  fetchImpl?: typeof fetch;
}

const CODIGO_POR_STATUS: Record<number, CodigoErroAdmin> = {
  400: 'validacao',
  401: 'sem_permissao',
  403: 'sem_permissao',
  404: 'nao_encontrado',
  409: 'conflito',
  422: 'validacao',
  503: 'indisponivel',
};

export class HttpAdminDataProvider implements AdminDataProvider {
  readonly modo = 'http' as const;

  private readonly baseUrl: string;
  private readonly obterToken: ProvedorDeToken;
  private readonly fetchImpl: typeof fetch;

  constructor(opcoes: OpcoesHttp) {
    const base = (opcoes.baseUrl ?? '').trim().replace(/\/+$/, '');
    if (!base) {
      throw new AdminApiError(
        'indisponivel',
        'VITE_ADMIN_API_BASE_URL não está definida. Sem ela o painel não inventa endereço — use o MockAdminDataProvider.',
      );
    }
    this.baseUrl = base;
    this.obterToken = opcoes.obterToken ?? (async () => null);
    this.fetchImpl = opcoes.fetchImpl ?? globalThis.fetch.bind(globalThis);
  }

  private caminho(partes: (string | number)[], filtros?: ListFilters): string {
    const url = new URL(
      `${this.baseUrl}/admin/${partes.map((p) => encodeURIComponent(String(p))).join('/')}`,
    );
    if (filtros) {
      for (const [chave, valor] of Object.entries(filtros)) {
        if (valor === undefined || valor === null || valor === '') continue;
        /* Filtro é sempre metadado (dia, status, espaço). Dado pessoal
           não vira query string — nem para busca. */
        if (Array.isArray(valor)) valor.forEach((v) => url.searchParams.append(chave, String(v)));
        else url.searchParams.set(chave, String(valor));
      }
    }
    return url.toString();
  }

  private async pedir<T>(
    url: string,
    init: RequestInit & { corpo?: unknown } = {},
  ): Promise<T> {
    const { corpo, ...resto } = init;
    const token = await this.obterToken();

    const cabecalhos: Record<string, string> = {
      Accept: 'application/json',
      ...(corpo !== undefined ? { 'Content-Type': 'application/json' } : {}),
      ...((resto.headers as Record<string, string>) ?? {}),
    };
    /* O token vive só neste objeto, no tempo da requisição. Não é
       guardado, não é logado, não vai para a URL. */
    if (token) cabecalhos.Authorization = `Bearer ${token}`;

    let resposta: Response;
    try {
      resposta = await this.fetchImpl(url, {
        ...resto,
        headers: cabecalhos,
        body: corpo !== undefined ? JSON.stringify(corpo) : undefined,
      });
    } catch (erro) {
      throw new AdminApiError('rede', 'Não foi possível falar com a API administrativa.', {
        detalhes: erro instanceof Error ? erro.message : String(erro),
      });
    }

    const requestId = resposta.headers.get('x-request-id') ?? undefined;

    if (!resposta.ok) {
      const codigo = CODIGO_POR_STATUS[resposta.status] ?? 'desconhecido';
      let mensagem = `A API respondeu ${resposta.status}.`;
      let detalhes: unknown;
      try {
        const corpoErro = (await resposta.json()) as { mensagem?: string; detalhes?: unknown };
        if (corpoErro?.mensagem) mensagem = corpoErro.mensagem;
        detalhes = corpoErro?.detalhes;
      } catch {
        /* Resposta sem JSON: a mensagem por status já basta. */
      }
      throw new AdminApiError(codigo, mensagem, { detalhes, requestId });
    }

    if (resposta.status === 204) return undefined as T;
    return (await resposta.json()) as T;
  }

  /* ---------------------------------------------------------------- */
  /* GET /admin/:resource · GET /admin/:resource/:id                   */
  /* ---------------------------------------------------------------- */

  list<K extends NomeRecurso>(
    resource: K,
    filters: ListFilters = {},
  ): Promise<ListResult<MapaRecursos[K]>> {
    return this.pedir<ListResult<MapaRecursos[K]>>(this.caminho([resource], filters));
  }

  get<K extends NomeRecurso>(resource: K, id: string): Promise<MapaRecursos[K]> {
    return this.pedir<MapaRecursos[K]>(this.caminho([resource, id]));
  }

  /* ---------------------------------------------------------------- */
  /* POST /admin/:resource · PATCH /admin/:resource/:id                */
  /* ---------------------------------------------------------------- */

  create<K extends NomeRecurso>(
    resource: K,
    payload: Partial<MapaRecursos[K]>,
  ): Promise<MapaRecursos[K]> {
    return this.pedir<MapaRecursos[K]>(this.caminho([resource]), {
      method: 'POST',
      corpo: payload,
    });
  }

  update<K extends NomeRecurso>(
    resource: K,
    id: string,
    payload: Partial<MapaRecursos[K]>,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    return this.pedir<MapaRecursos[K]>(this.caminho([resource, id]), {
      method: 'PATCH',
      corpo: payload,
      /* Controle de concorrência otimista: a API compara e devolve 409. */
      headers: opcoes?.atualizadoEmEsperado
        ? { 'If-Unmodified-Since-Version': opcoes.atualizadoEmEsperado }
        : {},
    });
  }

  /* ---------------------------------------------------------------- */
  /* POST /admin/:resource/:id/publish · /archive                      */
  /* ---------------------------------------------------------------- */

  publish<K extends NomeRecurso>(
    resource: K,
    id: string,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    return this.pedir<MapaRecursos[K]>(this.caminho([resource, id, 'publish']), {
      method: 'POST',
      corpo: { atualizadoEmEsperado: opcoes?.atualizadoEmEsperado ?? null },
    });
  }

  archive<K extends NomeRecurso>(
    resource: K,
    id: string,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    return this.pedir<MapaRecursos[K]>(this.caminho([resource, id, 'archive']), {
      method: 'POST',
      corpo: { atualizadoEmEsperado: opcoes?.atualizadoEmEsperado ?? null },
    });
  }

  /* ---------------------------------------------------------------- */
  /* POST /admin/documents/:id/reindex · GET /admin/dashboard          */
  /* ---------------------------------------------------------------- */

  requestReindex(documentId: string): Promise<ReciboReindexacao> {
    return this.pedir<ReciboReindexacao>(this.caminho(['documents', documentId, 'reindex']), {
      method: 'POST',
    });
  }

  getDashboard(): Promise<ResumoPainel> {
    return this.pedir<ResumoPainel>(this.caminho(['dashboard']));
  }
}
