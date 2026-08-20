import { z } from 'zod';
import { registroEditorialSchema, statusEditorialSchema } from './common';

export const CATEGORIAS_CONTEUDO = [
  'sobre',
  'produtos',
  'metodologia',
  'servicos',
  'historia',
  'contato',
  'comercial',
] as const;
export const ROTULO_CATEGORIA_CONTEUDO: Record<(typeof CATEGORIAS_CONTEUDO)[number], string> = {
  sobre: 'Sobre a Mind',
  produtos: 'Produtos',
  metodologia: 'Metodologia',
  servicos: 'Serviços',
  historia: 'História',
  contato: 'Contato',
  comercial: 'Comercial',
};

export const PUBLICOS_CONTEUDO = ['publico', 'participante', 'interno'] as const;
export const ROTULO_PUBLICO_CONTEUDO: Record<(typeof PUBLICOS_CONTEUDO)[number], string> = {
  publico: 'Público',
  participante: 'Participantes',
  interno: 'Interno',
};

export const conteudoFormSchema = z.object({
  categoria: z.enum(CATEGORIAS_CONTEUDO),
  slug: z
    .string()
    .min(2, 'Informe o slug.')
    .regex(/^[a-z0-9-]+$/, 'Use apenas letras minúsculas, números e hífen.'),
  titulo: z.string().min(3, 'Informe o título.'),
  conteudo: z.string().min(20, 'O conteúdo precisa de ao menos 20 caracteres.').max(20000),
  publico: z.enum(PUBLICOS_CONTEUDO),
  validoAte: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, 'Use o formato AAAA-MM-DD.')
    .or(z.literal(''))
    .default(''),
  status: statusEditorialSchema,
});
export type ConteudoForm = z.infer<typeof conteudoFormSchema>;

export const conteudoSchema = registroEditorialSchema.extend({
  categoria: z.enum(CATEGORIAS_CONTEUDO),
  slug: z.string(),
  titulo: z.string(),
  conteudo: z.string(),
  publico: z.enum(PUBLICOS_CONTEUDO),
  validoAte: z.string(),
});
export type Conteudo = z.infer<typeof conteudoSchema>;
