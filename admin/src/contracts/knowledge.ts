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
