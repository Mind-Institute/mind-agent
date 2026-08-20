/* ============================================================
   AdminDataProvider — a única porta de dados do painel
   ============================================================
   Nenhuma página chama `fetch`. Todas falam com esta interface, do
   mesmo jeito que o chat da raiz fala com `data-service.js`.

   É o que permite trocar `MockAdminDataProvider` por
   `HttpAdminDataProvider` sem reescrever tela nenhuma: os métodos, os
   tipos e os erros são os mesmos nos dois lados. */

import type {
  ListFilters,
  ListResult,
  MapaRecursos,
  NomeRecurso,
  OpcoesEscrita,
  ReciboReindexacao,
  ResumoPainel,
} from '@/contracts';

export interface AdminDataProvider {
  /** Qual implementação está ativa. A interface mostra isso no topo. */
  readonly modo: 'mock' | 'http' | 'hybrid';

  list<K extends NomeRecurso>(
    resource: K,
    filters?: ListFilters,
  ): Promise<ListResult<MapaRecursos[K]>>;

  get<K extends NomeRecurso>(resource: K, id: string): Promise<MapaRecursos[K]>;

  create<K extends NomeRecurso>(
    resource: K,
    payload: Partial<MapaRecursos[K]>,
  ): Promise<MapaRecursos[K]>;

  update<K extends NomeRecurso>(
    resource: K,
    id: string,
    payload: Partial<MapaRecursos[K]>,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]>;

  /** Arquivar, não apagar: o registro sai de circulação e continua auditável. */
  archive<K extends NomeRecurso>(
    resource: K,
    id: string,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]>;

  publish<K extends NomeRecurso>(
    resource: K,
    id: string,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]>;

  /** Enfileira o documento para reindexação. Não indexa aqui. */
  requestReindex(documentId: string): Promise<ReciboReindexacao>;

  getDashboard(): Promise<ResumoPainel>;
}

/** Quem escreve fica no registro e na auditoria. */
export interface ContextoAutor {
  nome: string;
}
