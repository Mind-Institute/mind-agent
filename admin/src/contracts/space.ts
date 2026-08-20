import { z } from 'zod';
import { registroBaseSchema } from './common';

export const TIPOS_ESPACO = [
  'palco',
  'sala',
  'arena',
  'lounge',
  'area_expositiva',
  'apoio',
  'externo',
] as const;
export const ROTULO_TIPO_ESPACO: Record<(typeof TIPOS_ESPACO)[number], string> = {
  palco: 'Palco',
  sala: 'Sala',
  arena: 'Arena',
  lounge: 'Lounge',
  area_expositiva: 'Área expositiva',
  apoio: 'Apoio',
  externo: 'Externo',
};

export const espacoFormSchema = z.object({
  nome: z.string().min(2, 'Informe o nome do espaço.'),
  slug: z
    .string()
    .min(2, 'Informe o slug.')
    .regex(/^[a-z0-9-]+$/, 'Use apenas letras minúsculas, números e hífen.'),
  tipo: z.enum(TIPOS_ESPACO),
  /**
   * Os aliases são como o participante chama o espaço no chat
   * ("palco principal"). Sem eles o agente não encontra o lugar —
   * por isso palco sem alias vira pendência no painel.
   */
  aliases: z.array(z.string().min(2, 'Alias muito curto.')).default([]),
  descricao: z.string().max(2000).default(''),
  comoChegar: z.string().max(2000).default(''),
  localPrincipal: z.string().max(160).default(''),
  espacoPaiId: z.string().nullable().default(null),
  andar: z.string().max(40).default(''),
  coordenadaX: z.number().nullable().default(null),
  coordenadaY: z.number().nullable().default(null),
  acessivel: z.boolean().default(true),
  observacaoAcessibilidade: z.string().max(500).default(''),
  ativo: z.boolean().default(true),
});
export type EspacoForm = z.infer<typeof espacoFormSchema>;

export const espacoSchema = registroBaseSchema.extend({
  nome: z.string(),
  slug: z.string(),
  tipo: z.enum(TIPOS_ESPACO),
  aliases: z.array(z.string()),
  descricao: z.string(),
  comoChegar: z.string(),
  localPrincipal: z.string(),
  espacoPaiId: z.string().nullable(),
  andar: z.string(),
  coordenadaX: z.number().nullable(),
  coordenadaY: z.number().nullable(),
  acessivel: z.boolean(),
  observacaoAcessibilidade: z.string(),
  ativo: z.boolean(),
});
export type Espaco = z.infer<typeof espacoSchema>;
