import { z } from 'zod';
import { registroEditorialSchema, statusEditorialSchema } from './common';

export const palestranteFormSchema = z.object({
  nome: z.string().min(3, 'Informe o nome.'),
  cargo: z.string().max(160).default(''),
  organizacao: z.string().max(160).default(''),
  biografia: z.string().min(10, 'A biografia precisa de ao menos 10 caracteres.').max(4000),
  foto: z.string().max(300).default(''),
  temas: z.array(z.string()).default([]),
  destaque: z.boolean().default(false),
  status: statusEditorialSchema,
});
export type PalestranteForm = z.infer<typeof palestranteFormSchema>;

export const palestranteSchema = registroEditorialSchema.extend({
  nome: z.string(),
  cargo: z.string(),
  organizacao: z.string(),
  biografia: z.string(),
  foto: z.string(),
  temas: z.array(z.string()),
  destaque: z.boolean(),
  /** Preenchido pelo provedor a partir das sessões — leitura apenas. */
  sessaoIds: z.array(z.string()),
});
export type Palestrante = z.infer<typeof palestranteSchema>;
