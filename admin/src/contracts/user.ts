import { z } from 'zod';

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

/* O que cada papel faz HOJE no painel, que tem o Catálogo e os Admins do
   sistema. Aparece na hora de dar acesso, para ajudar a escolher — quem
   autoriza de verdade é o banco. Módulo novo que mude o que um papel faz
   muda esta frase junto. */
export const DESCRICAO_PAPEL: Record<Papel, string> = {
  administrador: 'Edita o catálogo e decide quem entra no painel.',
  editor: 'Edita o catálogo.',
  aprovador: 'Edita o catálogo.',
  atendimento: 'Só vê.',
  analista: 'Só vê.',
};
