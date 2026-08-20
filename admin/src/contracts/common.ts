import { z } from 'zod';

/* ============================================================
   FLUXO EDITORIAL
   ============================================================
   rascunho → em_revisao → publicado → arquivado

   IMPORTANTE: as regras abaixo governam o que a INTERFACE mostra.
   A autorização de verdade é do backend — ver `src/lib/permissions.ts`
   e a seção "Limites" do README. */
export const STATUS_EDITORIAL = ['rascunho', 'em_revisao', 'publicado', 'arquivado'] as const;
export const statusEditorialSchema = z.enum(STATUS_EDITORIAL);
export type StatusEditorial = z.infer<typeof statusEditorialSchema>;

export const ROTULO_STATUS_EDITORIAL: Record<StatusEditorial, string> = {
  rascunho: 'Rascunho',
  em_revisao: 'Em revisão',
  publicado: 'Publicado',
  arquivado: 'Arquivado',
};

/* ============================================================
   METADADOS COMUNS
   ============================================================ */
export const registroBaseSchema = z.object({
  id: z.string(),
  criadoEm: z.string(),
  atualizadoEm: z.string(),
  atualizadoPor: z.string().nullable(),
});
export type RegistroBase = z.infer<typeof registroBaseSchema>;

export const registroEditorialSchema = registroBaseSchema.extend({
  status: statusEditorialSchema,
  publicadoEm: z.string().nullable(),
  publicadoPor: z.string().nullable(),
});
export type RegistroEditorial = z.infer<typeof registroEditorialSchema>;

/* ============================================================
   LISTAGEM
   ============================================================ */
export interface ListFilters {
  /** Busca textual livre. O que ela varre é decidido por recurso. */
  busca?: string;
  /** Página começando em 1. */
  pagina?: number;
  /** Itens por página. */
  porPagina?: number;
  /** Campo de ordenação e direção (`titulo`, `-atualizadoEm`). */
  ordenar?: string;
  /** Filtros específicos do recurso (dia, espaço, tema, status…). */
  [chave: string]: string | number | boolean | string[] | undefined;
}

export interface ListResult<T> {
  itens: T[];
  total: number;
  pagina: number;
  porPagina: number;
}

/* ============================================================
   ERROS
   ============================================================
   Um tipo só para os dois provedores. A página não pergunta "foi
   HTTP 409?", pergunta `erro.codigo === 'conflito'`. */
export type CodigoErroAdmin =
  | 'nao_encontrado'
  | 'sem_permissao'
  | 'conflito'
  | 'validacao'
  | 'rede'
  | 'indisponivel'
  | 'desconhecido';

export class AdminApiError extends Error {
  readonly codigo: CodigoErroAdmin;
  readonly detalhes?: unknown;
  readonly requestId?: string;

  constructor(
    codigo: CodigoErroAdmin,
    mensagem: string,
    opcoes?: { detalhes?: unknown; requestId?: string },
  ) {
    super(mensagem);
    this.name = 'AdminApiError';
    this.codigo = codigo;
    this.detalhes = opcoes?.detalhes;
    this.requestId = opcoes?.requestId;
  }
}

export function ehErroAdmin(erro: unknown): erro is AdminApiError {
  return erro instanceof AdminApiError;
}

export function codigoDoErro(erro: unknown): CodigoErroAdmin {
  return ehErroAdmin(erro) ? erro.codigo : 'desconhecido';
}

/* ============================================================
   CONTROLE DE CONCORRÊNCIA
   ============================================================
   Toda escrita manda o `atualizadoEm` que a tela viu. Se o registro
   mudou desde então, o provedor devolve `conflito` em vez de
   sobrescrever o trabalho de outra pessoa. */
export interface OpcoesEscrita {
  atualizadoEmEsperado?: string | null;
}

/** Aviso de qualidade de dado exibido junto do registro. */
export interface Alerta {
  nivel: 'info' | 'atencao' | 'erro';
  mensagem: string;
}
