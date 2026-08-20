import { z } from 'zod';

export const ACOES_AUDITORIA = [
  'criar',
  'atualizar',
  'publicar',
  'arquivar',
  'reindexar',
  'login',
] as const;
export const ROTULO_ACAO_AUDITORIA: Record<(typeof ACOES_AUDITORIA)[number], string> = {
  criar: 'Criar',
  atualizar: 'Atualizar',
  publicar: 'Publicar',
  arquivar: 'Arquivar',
  reindexar: 'Reindexar',
  login: 'Login',
};

export const registroAuditoriaSchema = z.object({
  id: z.string(),
  usuario: z.string(),
  acao: z.enum(ACOES_AUDITORIA),
  recurso: z.string(),
  registroId: z.string(),
  registroRotulo: z.string(),
  antes: z.record(z.unknown()).nullable(),
  depois: z.record(z.unknown()).nullable(),
  ocorridoEm: z.string(),
  requestId: z.string(),
});
export type RegistroAuditoria = z.infer<typeof registroAuditoriaSchema>;
