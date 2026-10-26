import { z } from 'zod';
import { registroBaseSchema } from './common';
import { PAPEIS } from './user';

/* ============================================================
   ADMINS DO SISTEMA — quem entra no Mind Intelligence Admin
   ============================================================
   Uma linha de `public.mind_admin_users`, como a `mindagent-acesso`
   devolve: nome e e-mail vêm do Mind ID da pessoa; papel e situação são
   da linha. A lista nunca cria pessoa — dar acesso exige que ela já
   exista no Mind ID, marcada como equipe. Quem confere é o banco
   (`mind_admin_mutate_admins`); a tela só evita o pedido que ele recusaria. */

export const DOMINIO_DA_MIND = '@joinmind.com.br';

export const adminSistemaSchema = registroBaseSchema.extend({
  /* A conta antiga, de senha, é anterior ao Mind ID e não tem pessoa. */
  mindId: z.string().nullable().default(null),
  nome: z.string().nullable().default(null),
  email: z.string().nullable().default(null),
  /* `string`, não enum: papel novo no banco aparece cru na tela em vez
     de travar a lista — a mesma regra de `tipo` no catálogo. */
  papel: z.string().min(1),
  /* Obrigatórios: são o que a tela existe para mostrar. Chutar `false`
     diria que alguém não entra quando talvez entre. */
  ativo: z.boolean(),
  loginLigado: z.boolean(),
  ultimoLoginEm: z.string().nullable().default(null),
});
export type AdminSistema = z.infer<typeof adminSistemaSchema>;

/* Dar acesso: o e-mail da Mind, que é com o que a pessoa entra pelo
   Google, e o papel — escolhido, sem valor pronto: é nível de acesso. */
export const darAcessoFormSchema = z.object({
  email: z
    .string()
    .trim()
    .toLowerCase()
    .min(1, 'Informe o e-mail da pessoa.')
    .email('Informe um e-mail válido.')
    .refine(
      (v) => v.endsWith(DOMINIO_DA_MIND),
      'Use o e-mail da Mind (@joinmind.com.br): é com ele que a pessoa entra, pelo Google.',
    ),
  papel: z.enum(PAPEIS, { errorMap: () => ({ message: 'Escolha o papel.' }) }),
});
export type DarAcessoForm = z.infer<typeof darAcessoFormSchema>;

/* Na linha, só papel e situação mudam — é o que a porta aceita. O papel
   é `string` pelo mesmo motivo do registro: o valor atual, mesmo
   desconhecido, sobrevive a salvar só a situação. */
export const adminSistemaFormSchema = z.object({
  papel: z.string().min(1, 'Escolha o papel.'),
  ativo: z.boolean(),
});
export type AdminSistemaForm = z.infer<typeof adminSistemaFormSchema>;
