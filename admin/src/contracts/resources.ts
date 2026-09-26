import type { ProdutoCatalogo } from './product';
import type { AdminSistema } from './admin-sistema';

/**
 * O nome do recurso é o mesmo na URL da Edge Function
 * (`GET /admin/products`) e na chave do TanStack Query. Um nome só,
 * escrito em um lugar só.
 *
 * Só dado real. Decisão da Adriana (26/09/2026): saíram o evento, a Home
 * V3, a visão geral e os módulos que eram demonstração (ofertas,
 * conteúdo, documentos, conversas, perguntas, usuários e auditoria).
 * Ficaram o Catálogo e, pedido dela no mesmo dia, os admins do sistema.
 * Recurso novo entra aqui quando ela definir o módulo e ele tiver fonte
 * real.
 */
export interface MapaRecursos {
  /* Catálogo: `catalogo.produtos`, a origem de tudo. */
  products: ProdutoCatalogo;
  /* Quem entra no painel: `public.mind_admin_users`, pela `mindagent-acesso`. */
  admins: AdminSistema;
}

export type NomeRecurso = keyof MapaRecursos;

export const NOMES_RECURSOS: NomeRecurso[] = ['products', 'admins'];

export const ROTULO_RECURSO: Record<NomeRecurso, string> = {
  products: 'Produto',
  admins: 'Admin',
};
