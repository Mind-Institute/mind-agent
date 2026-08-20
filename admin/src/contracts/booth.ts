import { z } from 'zod';
import { registroBaseSchema } from './common';

export const CATEGORIAS_ESTANDE = [
  'patrocinio',
  'saude',
  'tecnologia',
  'educacao',
  'servicos',
  'institucional',
  'alimentacao',
] as const;
export const ROTULO_CATEGORIA_ESTANDE: Record<(typeof CATEGORIAS_ESTANDE)[number], string> = {
  patrocinio: 'Patrocínio',
  saude: 'Saúde',
  tecnologia: 'Tecnologia',
  educacao: 'Educação',
  servicos: 'Serviços',
  institucional: 'Institucional',
  alimentacao: 'Alimentação',
};

export const estandeFormSchema = z.object({
  nome: z.string().min(2, 'Informe o nome do estande.'),
  slug: z
    .string()
    .min(2, 'Informe o slug.')
    .regex(/^[a-z0-9-]+$/, 'Use apenas letras minúsculas, números e hífen.'),
  categoria: z.enum(CATEGORIAS_ESTANDE),
  descricao: z.string().max(2000).default(''),
  espacoId: z.string().nullable().default(null),
  site: z.string().url('Informe uma URL válida.').or(z.literal('')).default(''),
  contato: z.string().max(160).default(''),
  ativo: z.boolean().default(true),
});
export type EstandeForm = z.infer<typeof estandeFormSchema>;

export const estandeSchema = registroBaseSchema.extend({
  nome: z.string(),
  slug: z.string(),
  categoria: z.enum(CATEGORIAS_ESTANDE),
  descricao: z.string(),
  espacoId: z.string().nullable(),
  site: z.string(),
  contato: z.string(),
  ativo: z.boolean(),
});
export type Estande = z.infer<typeof estandeSchema>;
