import { z } from 'zod';
import { registroBaseSchema } from './common';

/** Formulário do evento. É o que o RHF valida. */
export const eventoFormSchema = z.object({
  nome: z.string().min(3, 'Informe o nome do evento.'),
  slug: z
    .string()
    .min(3, 'Informe o slug.')
    .regex(/^[a-z0-9-]+$/, 'Use apenas letras minúsculas, números e hífen.'),
  dataInicio: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use o formato AAAA-MM-DD.'),
  dataFim: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Use o formato AAAA-MM-DD.'),
  local: z.string().min(2, 'Informe o local.'),
  cidade: z.string().min(2, 'Informe a cidade.'),
  fusoHorario: z.string().min(3, 'Informe o fuso horário.'),
  descricao: z.string().max(2000, 'Máximo de 2000 caracteres.').default(''),
  regraReserva: z.string().max(1000).default(''),
  regraVagas: z.string().max(1000).default(''),
  ativo: z.boolean().default(true),
}).refine((v) => v.dataFim >= v.dataInicio, {
  message: 'A data final não pode ser anterior à inicial.',
  path: ['dataFim'],
});

export type EventoForm = z.infer<typeof eventoFormSchema>;

export const eventoSchema = registroBaseSchema.extend({
  nome: z.string(),
  slug: z.string(),
  dataInicio: z.string(),
  dataFim: z.string(),
  local: z.string(),
  cidade: z.string(),
  fusoHorario: z.string(),
  descricao: z.string(),
  regraReserva: z.string(),
  regraVagas: z.string(),
  ativo: z.boolean(),
  /**
   * Locais que aparecem em fontes diferentes do projeto. O painel NÃO
   * escolhe entre eles — mostra a divergência para alguém decidir.
   *
   * Opcional porque a API real pode não enviar a lista. Quando ela não
   * vem, `divergenciasDeLocal()` monta as candidatas a partir do que o
   * painel consegue ver: o cadastro oficial, as regras logísticas e a
   * cópia congelada em `dados/summit.json`.
   */
  locaisCandidatos: z
    .array(z.object({ valor: z.string(), origem: z.string() }))
    .default([]),
});

export type Evento = z.infer<typeof eventoSchema>;
