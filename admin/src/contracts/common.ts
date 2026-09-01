import { z } from 'zod';

/* ============================================================
   FLUXO EDITORIAL
   ============================================================
   rascunho → em_revisao → publicado → arquivado

   As regras abaixo governam o que a INTERFACE mostra. Quem autoriza a
   escrita é o backend, em duas camadas — ver `src/lib/permissions.ts`. */
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
/* A fronteira entre OBRIGATÓRIO e OPCIONAL aqui não é estética: ela
   decide o que o painel aceita da API real.

   - `id` e `atualizadoEm` são obrigatórios. Sem id não há como abrir
     nem editar o registro; sem `atualizadoEm` a escrita perde o
     `If-Unmodified-Since-Version` e passa a sobrescrever o trabalho de
     outra pessoa em silêncio. Preencher esses dois por conta própria
     seria esconder uma quebra de contrato.
   - `criadoEm` e `atualizadoPor` são descritivos: aparecem em texto e
     nada depende deles. Ausentes, ganham default explícito. */
export const registroBaseSchema = z.object({
  id: z.string().min(1),
  criadoEm: z.string().default(''),
  atualizadoEm: z.string().min(1),
  atualizadoPor: z.string().nullable().default(null),
});

export const registroEditorialSchema = registroBaseSchema.extend({
  /* Obrigatório: o selo editorial e o botão de publicar saem daqui.
     Chutar "rascunho" faria o painel mostrar como não publicado algo
     que talvez esteja no ar. */
  status: statusEditorialSchema,
  publicadoEm: z.string().nullable().default(null),
  publicadoPor: z.string().nullable().default(null),
});

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
  | 'sessao_expirada'
  | 'credenciais_invalidas'
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
