import type { ProdutoCatalogo } from './product';

/**
 * O nome do recurso é o mesmo na URL da Edge Function
 * (`GET /admin/products`) e na chave do TanStack Query. Um nome só,
 * escrito em um lugar só.
 *
 * Só o Catálogo. Decisão da Adriana (26/09/2026): o painel mostra apenas
 * dado real — saíram o evento, a Home V3, a visão geral e os módulos que
 * eram demonstração (ofertas, conteúdo, documentos, conversas, perguntas,
 * usuários e auditoria). Recurso novo entra aqui quando ela definir o
 * módulo e ele tiver fonte real.
 */
export interface MapaRecursos {
  /* Catálogo: `catalogo.produtos`, a origem de tudo. */
  products: ProdutoCatalogo;
}

export type NomeRecurso = keyof MapaRecursos;

export const NOMES_RECURSOS: NomeRecurso[] = ['products'];

export const ROTULO_RECURSO: Record<NomeRecurso, string> = {
  products: 'Produto',
};
