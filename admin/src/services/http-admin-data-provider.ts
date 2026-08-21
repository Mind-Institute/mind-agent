/* ============================================================
   HttpAdminDataProvider — fala com a Edge Function administrativa
   ============================================================
   Mesmos métodos, mesmos tipos e mesmos erros do mock: trocar um pelo
   outro não mexe em nenhuma página.

   REGRAS QUE NÃO PODEM SER QUEBRADAS AQUI
   ---------------------------------------
   - O navegador NUNCA fala com o Postgres direto. Só com Edge Function.
   - `service_role` e secret key não existem neste código, nem em
     variável, nem em header. Quem tem chave administrativa é o backend.
   - O token vai no header `Authorization`, NUNCA na URL: endereço vaza
     em histórico, log de proxy e print de tela.
   - Nenhum `console.log` de token, header ou corpo de resposta.
   - Nenhum dado pessoal (e-mail, telefone) em query string. Filtro é
     metadado: dia, espaço, status. */

import {
  AdminApiError,
  type ListFilters,
  type ListResult,
  type MapaRecursos,
  type NomeRecurso,
  type OpcoesEscrita,
  type ReciboReindexacao,
  type ResumoPainel,
} from '@/contracts';
import type { AdminDataProvider } from './admin-data-provider';
import { erroDaResposta, erroDeRede } from './http-erros';
import { validarLista, validarRegistro } from './validacao-api';

/** Header de concorrência otimista, aceito pela Edge Function. */
function cabecalhoVersao(opcoes?: OpcoesEscrita): Record<string, string> {
  return opcoes?.atualizadoEmEsperado
    ? { 'If-Unmodified-Since-Version': opcoes.atualizadoEmEsperado }
    : {};
}

/** Como o painel obtém o token da sessão vigente. */
export type ProvedorDeToken = () => Promise<string | null>;

export interface OpcoesHttp {
  baseUrl: string;
  /**
   * Ligado ao Supabase Auth em `use-sessao.tsx`: devolve o
   * `access_token` da sessão atual, ou `null` quando não há sessão.
   * Sem token a Edge Function responde 401 — que é o correto.
   */
  obterToken?: ProvedorDeToken;
  /**
   * Chave publicável do projeto (anon). É pública por design e o
   * gateway do Supabase a exige junto do token. NUNCA `service_role`.
   */
  chavePublicavel?: string;
  /** Chamado quando a API recusa por sessão expirada (401). */
  aoNaoAutorizado?: (erro: AdminApiError) => void;
  fetchImpl?: typeof fetch;
}

export class HttpAdminDataProvider implements AdminDataProvider {
  readonly modo = 'http' as const;

  origemDoRecurso(): 'http' {
    return 'http';
  }

  private readonly baseUrl: string;
  private readonly obterToken: ProvedorDeToken;
  private readonly chavePublicavel: string | null;
  private readonly aoNaoAutorizado?: (erro: AdminApiError) => void;
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
    this.chavePublicavel = opcoes.chavePublicavel?.trim() || null;
    this.aoNaoAutorizado = opcoes.aoNaoAutorizado;
    this.fetchImpl = opcoes.fetchImpl ?? globalThis.fetch.bind(globalThis);
  }

  private caminho(partes: (string | number)[], filtros?: ListFilters): string {
    const url = new URL(
      `${this.baseUrl}/admin/${partes.map((p) => encodeURIComponent(String(p))).join('/')}`,
    );
    if (filtros) {
      for (const [chave, valor] of Object.entries(filtros)) {
        if (valor === undefined || valor === null || valor === '') continue;
        if (Array.isArray(valor)) valor.forEach((v) => url.searchParams.append(chave, String(v)));
        else url.searchParams.set(chave, String(valor));
      }
    }
    return url.toString();
  }

  private async pedir<T>(url: string, init: RequestInit & { corpo?: unknown } = {}): Promise<T> {
    const { corpo, ...resto } = init;
    const token = await this.obterToken();

    const cabecalhos: Record<string, string> = {
      Accept: 'application/json',
      ...(corpo !== undefined ? { 'Content-Type': 'application/json' } : {}),
      ...((resto.headers as Record<string, string>) ?? {}),
    };
    if (this.chavePublicavel) cabecalhos.apikey = this.chavePublicavel;
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
      throw erroDeRede(erro);
    }

    if (!resposta.ok) {
      const erro = await erroDaResposta(resposta);
      /* Sessão caiu no meio do uso: quem sabe o que fazer com isso é a
         camada de sessão, não a página que pediu a lista. */
      if (erro.codigo === 'sessao_expirada') this.aoNaoAutorizado?.(erro);
      throw erro;
    }

    if (resposta.status === 204) return undefined as T;
    return (await resposta.json()) as T;
  }

  /* ---------------------------------------------------------------- */
  /* GET /admin/:resource · GET /admin/:resource/:id                   */
  /* ---------------------------------------------------------------- */

  async list<K extends NomeRecurso>(
    resource: K,
    filters: ListFilters = {},
  ): Promise<ListResult<MapaRecursos[K]>> {
    return validarLista(
      resource,
      await this.pedir(this.caminho([resource], filters)),
      `GET /admin/${resource}`,
    );
  }

  async get<K extends NomeRecurso>(resource: K, id: string): Promise<MapaRecursos[K]> {
    return validarRegistro(
      resource,
      await this.pedir(this.caminho([resource, id])),
      `GET /admin/${resource}/${id}`,
    );
  }

  /* ---------------------------------------------------------------- */
  /* POST /admin/:resource · PATCH /admin/:resource/:id                */
  /* ---------------------------------------------------------------- */

  async create<K extends NomeRecurso>(
    resource: K,
    payload: Partial<MapaRecursos[K]>,
  ): Promise<MapaRecursos[K]> {
    return validarRegistro(
      resource,
      await this.pedir(this.caminho([resource]), { method: 'POST', corpo: payload }),
      `POST /admin/${resource}`,
    );
  }

  async update<K extends NomeRecurso>(
    resource: K,
    id: string,
    payload: Partial<MapaRecursos[K]>,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    return validarRegistro(
      resource,
      await this.pedir(this.caminho([resource, id]), {
        method: 'PATCH',
        corpo: payload,
        /* Controle de concorrência otimista. A Edge Function aceita
           este header — ele está no `access-control-allow-headers`. */
        headers: cabecalhoVersao(opcoes),
      }),
      `PATCH /admin/${resource}/${id}`,
    );
  }

  /* ---------------------------------------------------------------- */
  /* POST /admin/:resource/:id/publish · /archive                      */
  /* ---------------------------------------------------------------- */

  async publish<K extends NomeRecurso>(
    resource: K,
    id: string,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    return validarRegistro(
      resource,
      await this.pedir(this.caminho([resource, id, 'publish']), {
        method: 'POST',
        corpo: { atualizadoEmEsperado: opcoes?.atualizadoEmEsperado ?? null },
        headers: cabecalhoVersao(opcoes),
      }),
      `POST /admin/${resource}/${id}/publish`,
    );
  }

  async archive<K extends NomeRecurso>(
    resource: K,
    id: string,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    return validarRegistro(
      resource,
      await this.pedir(this.caminho([resource, id, 'archive']), {
        method: 'POST',
        corpo: { atualizadoEmEsperado: opcoes?.atualizadoEmEsperado ?? null },
        headers: cabecalhoVersao(opcoes),
      }),
      `POST /admin/${resource}/${id}/archive`,
    );
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
