import { z } from 'zod';
import { registroBaseSchema } from './common';

export const rotaFormSchema = z
  .object({
    origemId: z.string().min(1, 'Escolha a origem.'),
    destinoId: z.string().min(1, 'Escolha o destino.'),
    instrucoes: z.string().min(5, 'Descreva o caminho.').max(2000),
    distanciaMetros: z.number().int().min(0).nullable().default(null),
    tempoEstimadoMinutos: z.number().int().min(0).nullable().default(null),
    acessivel: z.boolean().default(true),
    bidirecional: z.boolean().default(true),
    ativo: z.boolean().default(true),
  })
  .refine((v) => v.origemId !== v.destinoId, {
    message: 'Origem e destino precisam ser espaços diferentes.',
    path: ['destinoId'],
  });
export type RotaForm = z.infer<typeof rotaFormSchema>;

export const rotaSchema = registroBaseSchema.extend({
  origemId: z.string(),
  destinoId: z.string(),
  instrucoes: z.string(),
  distanciaMetros: z.number().nullable(),
  tempoEstimadoMinutos: z.number().nullable(),
  acessivel: z.boolean(),
  bidirecional: z.boolean(),
  ativo: z.boolean(),
});
export type Rota = z.infer<typeof rotaSchema>;
