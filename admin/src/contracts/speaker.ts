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
  /* Obrigatório: é como a pessoa é identificada em toda a interface. */
  nome: z.string().min(1),

  /* O resto é conteúdo editorial — vazio é estado legítimo, e o painel
     já mostra "falta biografia" como pendência. */
  cargo: z.string().default(''),
  organizacao: z.string().default(''),
  biografia: z.string().default(''),
  foto: z.string().default(''),
  temas: z.array(z.string()).default([]),
  destaque: z.boolean().default(false),
  /** Preenchido pelo provedor a partir das sessões — leitura apenas. */
  sessaoIds: z.array(z.string()).default([]),
});
export type Palestrante = z.infer<typeof palestranteSchema>;
