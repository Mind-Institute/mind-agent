import type { ProdutoCatalogo } from './product';
import type { AdminSistema } from './admin-sistema';
import type { SessaoSummit2026 } from './summit';
import type { CupomCatalogo, OfertaCatalogo } from './offer';
import type {
  AgentKnowledgeAccess,
  KnowledgeAsset,
  KnowledgeCollection,
  BusinessKnowledgeGovernance,
  CustomerKnowledgeGovernance,
  AgentIntelligenceAccess,
} from './knowledge';

/**
 * O nome do recurso é o mesmo na URL da Edge Function
 * (`GET /admin/products`) e na chave do TanStack Query. Um nome só,
 * escrito em um lugar só.
 *
 * Só dado real. Decisão da Adriana (26/09/2026): saíram o evento, a Home
 * V3, a visão geral e os módulos que eram demonstração (ofertas,
 * conteúdo, documentos, conversas, perguntas, usuários e auditoria).
 * Ficaram o Catálogo e, pedidos dela no mesmo dia, os admins do sistema,
 * a programação do Mind Summit 2026 e as ofertas e os cupons do schema
 * `catalogo` ("o painel é o controle deste schema").
 * Recurso novo entra aqui quando ela definir o módulo e ele tiver fonte
 * real.
 */
export interface MapaRecursos {
  /* Catálogo: `catalogo.produtos`, a origem de tudo. */
  products: ProdutoCatalogo;
  /* Quem entra no painel: `public.mind_admin_users`, pela `mindagent-acesso`. */
  admins: AdminSistema;
  /* Programação do Mind Summit 2026: `summit_2026.sessions`, pela `mindagent-summit`. Só leitura. */
  summit_2026_sessions: SessaoSummit2026;
  /* Ofertas do catálogo: `catalogo.ofertas` com preços, bônus e bump/upgrade, pela `mindagent-catalogo`. */
  offers: OfertaCatalogo;
  /* Cupons do catálogo: `catalogo.cupons`, pela `mindagent-catalogo`. */
  coupons: CupomCatalogo;
  /* Control plane transversal do Knowledge/RAG. */
  knowledge_collections: KnowledgeCollection;
  knowledge_assets: KnowledgeAsset;
  agent_knowledge_access: AgentKnowledgeAccess;
  business_intelligence: BusinessKnowledgeGovernance;
  customer_intelligence: CustomerKnowledgeGovernance;
  agent_intelligence_access: AgentIntelligenceAccess;
}

export type NomeRecurso = keyof MapaRecursos;

export const NOMES_RECURSOS: NomeRecurso[] = [
  'products', 'admins', 'summit_2026_sessions', 'offers', 'coupons',
  'knowledge_collections', 'knowledge_assets', 'agent_knowledge_access',
  'business_intelligence', 'customer_intelligence', 'agent_intelligence_access',
];

export const ROTULO_RECURSO: Record<NomeRecurso, string> = {
  products: 'Produto',
  admins: 'Admin',
  summit_2026_sessions: 'Sessão',
  offers: 'Oferta',
  coupons: 'Cupom',
  knowledge_collections: 'Collection',
  knowledge_assets: 'Knowledge asset',
  agent_knowledge_access: 'Acesso de agente',
  business_intelligence: 'Business Intelligence',
  customer_intelligence: 'Customer Intelligence',
  agent_intelligence_access: 'Agent Intelligence',
};
