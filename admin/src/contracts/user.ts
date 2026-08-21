import { z } from 'zod';
import { registroBaseSchema } from './common';

/* ============================================================
   PAPÉIS
   ============================================================
   Estes papéis desenham a INTERFACE — escondem botão, marcam página
   como "sem permissão". Eles não são o controle de acesso.

   O controle de acesso existe e é do backend: a Edge Function lê o papel
   em `mind_admin_users` e a função SQL `mind_admin_mutate_resource`
   valida de novo antes de escrever. O papel nunca sai de
   `user_metadata`, que é editável pelo próprio usuário.

   O painel recebe o papel em `GET /admin/me` — mesma fonte que autoriza
   — então esta lista e a do backend não divergem por acidente. */
export const PAPEIS = ['administrador', 'editor', 'aprovador', 'atendimento', 'analista'] as const;
export const papelSchema = z.enum(PAPEIS);
export type Papel = z.infer<typeof papelSchema>;

export const ROTULO_PAPEL: Record<Papel, string> = {
  administrador: 'Administrador',
  editor: 'Editor',
  aprovador: 'Aprovador',
  atendimento: 'Atendimento',
  analista: 'Analista',
};

export const DESCRICAO_PAPEL: Record<Papel, string> = {
  administrador: 'Acesso completo, inclusive usuários, auditoria e configurações.',
  editor: 'Cria e edita conteúdo. Salva rascunho e envia para revisão; não publica.',
  aprovador: 'Revisa, publica e arquiva conteúdo enviado pelos editores.',
  atendimento: 'Lê conversas e trabalha a fila de perguntas sem resposta.',
  analista: 'Somente leitura: visão geral, listagens e auditoria.',
};

export const usuarioFormSchema = z.object({
  nome: z.string().min(3, 'Informe o nome.'),
  email: z.string().email('Informe um e-mail válido.'),
  papel: papelSchema,
  ativo: z.boolean().default(true),
});
export type UsuarioForm = z.infer<typeof usuarioFormSchema>;

export const usuarioSchema = registroBaseSchema.extend({
  nome: z.string(),
  email: z.string(),
  papel: papelSchema,
  ativo: z.boolean(),
  ultimoAcessoEm: z.string().nullable(),
});
export type Usuario = z.infer<typeof usuarioSchema>;
