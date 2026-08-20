import { z } from 'zod';
import { registroBaseSchema } from './common';

export const PUBLICOS_OFERTA = ['geral', 'corporativo', 'estudante', 'convidado', 'parceiro'] as const;
export const ROTULO_PUBLICO_OFERTA: Record<(typeof PUBLICOS_OFERTA)[number], string> = {
  geral: 'Geral',
  corporativo: 'Corporativo',
  estudante: 'Estudante',
  convidado: 'Convidado',
  parceiro: 'Parceiro',
};

export const ofertaFormSchema = z
  .object({
    codigo: z
      .string()
      .min(2, 'Informe o código.')
      .regex(/^[A-Z0-9_-]+$/, 'Use maiúsculas, números, hífen ou sublinhado.'),
    nome: z.string().min(2, 'Informe o nome da oferta.'),
    descricao: z.string().max(2000).default(''),
    moeda: z.string().length(3, 'Use o código de 3 letras (BRL).').default('BRL'),
    /** Em centavos: evita ponto flutuante em dinheiro. */
    valorCentavos: z.number().int().min(0).nullable().default(null),
    condicoesPagamento: z.string().max(500).default(''),
    checkoutUrl: z.string().url('Informe uma URL válida.').or(z.literal('')).default(''),
    elegibilidade: z.string().max(1000).default(''),
    publico: z.enum(PUBLICOS_OFERTA),
    dataInicio: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use o formato AAAA-MM-DD.'),
    dataFim: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use o formato AAAA-MM-DD.'),
    ativo: z.boolean().default(true),
  })
  .refine((v) => v.dataFim >= v.dataInicio, {
    message: 'A data final não pode ser anterior à inicial.',
    path: ['dataFim'],
  });
export type OfertaForm = z.infer<typeof ofertaFormSchema>;

export const ofertaSchema = registroBaseSchema.extend({
  codigo: z.string(),
  nome: z.string(),
  descricao: z.string(),
  moeda: z.string(),
  valorCentavos: z.number().nullable(),
  condicoesPagamento: z.string(),
  checkoutUrl: z.string(),
  elegibilidade: z.string(),
  publico: z.enum(PUBLICOS_OFERTA),
  dataInicio: z.string(),
  dataFim: z.string(),
  ativo: z.boolean(),
});
export type Oferta = z.infer<typeof ofertaSchema>;
