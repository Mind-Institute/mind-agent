import { z } from 'zod';

export const knowledgeCollectionSchema = z.object({
  id: z.string().min(1),
  chave: z.string().min(1),
  nome: z.string().min(1),
  descricao: z.string().nullable().default(null),
  ativo: z.boolean(),
  acessoPadrao: z.enum(['mind_only', 'mind_public']),
  sources: z.number(),
  assets: z.number(),
  agents: z.number(),
  atualizadoEm: z.string().min(1),
});
export type KnowledgeCollection = z.infer<typeof knowledgeCollectionSchema>;

const assetCollectionSchema = z.object({
  chave: z.string().min(1),
  nome: z.string().min(1),
  principal: z.boolean(),
  peso: z.number(),
});

export const knowledgeAssetSchema = z.object({
  id: z.string().uuid(),
  parentAssetId: z.string().uuid().nullable().default(null),
  assetType: z.string().min(1),
  originSchema: z.string().min(1),
  originTable: z.string().min(1),
  originId: z.string().min(1),
  titulo: z.string().min(1),
  acesso: z.enum(['mind_only', 'mind_public']),
  publicavel: z.boolean(),
  ativo: z.boolean(),
  pendenciaDecisao: z.string().nullable().default(null),
  collections: z.array(assetCollectionSchema).default([]),
  metadata: z.record(z.unknown()).default({}),
  criadoEm: z.string().min(1),
  atualizadoEm: z.string().min(1),
});
export type KnowledgeAsset = z.infer<typeof knowledgeAssetSchema>;

export const knowledgeSourceSchema = z.object({
  id: z.string().uuid(),
  titulo: z.string().min(1),
  tituloOriginal: z.string().nullable().default(null),
  autores: z.array(z.string()).default([]),
  ano: z.number().int().nullable().default(null),
  tipoFonte: z.string().nullable().default(null),
  evidenceRole: z.string().nullable().default(null),
  studyDesign: z.string().nullable().default(null),
  peerReviewed: z.boolean().nullable().default(null),
  doi: z.string().nullable().default(null),
  isbn: z.string().nullable().default(null),
  idioma: z.string().nullable().default(null),
  acesso: z.enum(['mind_only', 'mind_public']),
  publicavel: z.boolean(),
  statusIngestao: z.string().nullable().default(null),
  statusValidacao: z.string().nullable().default(null),
  modoIngestao: z.string().nullable().default(null),
  direitosUso: z.string().nullable().default(null),
  pendenciaDecisao: z.string().nullable().default(null),
  drivePath: z.string().nullable().default(null),
  collections: z.array(z.object({
    chave: z.string().min(1),
    nome: z.string().min(1),
  })).default([]),
  metadata: z.record(z.unknown()).default({}),
  criadoEm: z.string().min(1),
  atualizadoEm: z.string().min(1),
});
export type KnowledgeSource = z.infer<typeof knowledgeSourceSchema>;

export const agentKnowledgeAccessSchema = z.object({
  id: z.string().min(1),
  agentKey: z.string().min(1),
  collectionKey: z.string().min(1),
  collectionName: z.string().min(1),
  enabled: z.boolean(),
  prioridade: z.number().int().min(0).max(100),
  acessoMaximo: z.enum(['mind_only', 'mind_public']),
  pendenciaDecisao: z.string().nullable().default(null),
  metadata: z.record(z.unknown()).default({}),
  atualizadoEm: z.string().min(1),
});
export type AgentKnowledgeAccess = z.infer<typeof agentKnowledgeAccessSchema>;


export const businessKnowledgeGovernanceSchema = z.object({
  id: z.string().uuid(),
  collectionKey: z.string().min(1),
  collectionName: z.string().min(1),
  knowledgeType: z.string().min(1),
  vertical: z.string().min(1),
  sourceSchema: z.string().min(1),
  sourceTable: z.string().min(1),
  sourceFilter: z.record(z.unknown()).default({}),
  sourceLocator: z.string().nullable().default(null),
  description: z.string().nullable().default(null),
  defaultAccess: z.enum(['mind_only', 'mind_public']),
  retrievable: z.boolean(),
  priority: z.number().int().min(0).max(100),
  active: z.boolean(),
  metadata: z.record(z.unknown()).default({}),
  updatedAt: z.string().min(1),
});
export type BusinessKnowledgeGovernance = z.infer<typeof businessKnowledgeGovernanceSchema>;

export const customerKnowledgeGovernanceSchema = z.object({
  id: z.string().uuid(),
  collectionKey: z.string().min(1),
  collectionName: z.string().min(1),
  intelligenceType: z.string().min(1),
  sourceSchema: z.string().min(1),
  sourceTable: z.string().min(1),
  sourceFilter: z.record(z.unknown()).default({}),
  sourceLocator: z.string().nullable().default(null),
  description: z.string().nullable().default(null),
  granularity: z.enum(['individual', 'company', 'conversation', 'segment', 'aggregate', 'mixed']),
  sensitivity: z.enum(['internal', 'personal', 'sensitive']),
  rowScopePolicy: z.string().min(1),
  purposes: z.array(z.string()).default([]),
  retrievable: z.boolean(),
  priority: z.number().int().min(0).max(100),
  active: z.boolean(),
  metadata: z.record(z.unknown()).default({}),
  updatedAt: z.string().min(1),
});
export type CustomerKnowledgeGovernance = z.infer<typeof customerKnowledgeGovernanceSchema>;

export const agentIntelligenceAccessSchema = z.object({
  id: z.string().min(1),
  agentKey: z.string().min(1),
  namespace: z.enum(['global', 'business', 'customer']),
  knowledgeKey: z.string().min(1),
  knowledgeName: z.string().min(1),
  description: z.string().nullable().default(null),
  ownerScope: z.string().nullable().default(null),
  sourceCount: z.number().int().min(0),
  sensitivity: z.enum(['internal', 'personal', 'sensitive']).nullable().default(null),
  enabled: z.boolean(),
  priority: z.number().int().min(0).max(100),
  accessMax: z.enum(['mind_only', 'mind_public']),
  customerScope: z.string().nullable().default(null),
  pendingDecision: z.string().nullable().default(null),
  metadata: z.record(z.unknown()).default({}),
  updatedAt: z.string().min(1),
});
export type AgentIntelligenceAccess = z.infer<typeof agentIntelligenceAccessSchema>;

/* O que o agente lê de verdade no turno: `agentes.canal_competencia` (onde está ligado, com o
   veredito do Capability Gate) e `agentes.kit_blocos` (o Kit). Diferente da matriz acima, que
   é plugável e ainda não chega a nenhum agente. Fonte: mind_admin_read_agent_runtime. */
export const agentRuntimeCanalSchema = z.object({
  canal: z.string().min(1),
  ativo: z.boolean(),
  observacao: z.string().nullable().default(null),
  podeExecutar: z.boolean(),
  motivo: z.string().nullable().default(null),
  atualizadoEm: z.string().nullable().default(null),
});
export type AgentRuntimeCanal = z.infer<typeof agentRuntimeCanalSchema>;

export const agentRuntimeBlocoSchema = z.object({
  bloco: z.string().min(1),
  provider: z.string().nullable().default(null),
  secao: z.string().min(1),
  obrigatorio: z.boolean(),
  ativo: z.boolean(),
});
export type AgentRuntimeBloco = z.infer<typeof agentRuntimeBlocoSchema>;

export const agentRuntimeSchema = z.object({
  id: z.string().min(1),
  agentKey: z.string().min(1),
  playbook: z.object({
    chave: z.string().min(1),
    titulo: z.string().nullable().default(null),
    versao: z.number().int().nullable().default(null),
    ativo: z.boolean(),
    produtoCodigo: z.string().nullable().default(null),
    atualizadoEm: z.string().nullable().default(null),
  }).nullable().default(null),
  canais: z.array(agentRuntimeCanalSchema).default([]),
  kit: z.array(agentRuntimeBlocoSchema).default([]),
  updatedAt: z.string().min(1),
});
export type AgentRuntime = z.infer<typeof agentRuntimeSchema>;
