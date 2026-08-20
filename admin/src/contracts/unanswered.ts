import { z } from 'zod';
import { registroBaseSchema } from './common';
import { CANAIS } from './conversation';

export const STATUS_PERGUNTA = ['nova', 'em_analise', 'respondida', 'descartada'] as const;
export const ROTULO_STATUS_PERGUNTA: Record<(typeof STATUS_PERGUNTA)[number], string> = {
  nova: 'Nova',
  em_analise: 'Em análise',
  respondida: 'Respondida',
  descartada: 'Descartada',
};

export const perguntaSemRespostaSchema = registroBaseSchema.extend({
  pergunta: z.string(),
  ocorrencias: z.number(),
  canal: z.enum(CANAIS),
  ultimaOcorrenciaEm: z.string(),
  categoriaSugerida: z.string(),
  responsavel: z.string().nullable(),
  status: z.enum(STATUS_PERGUNTA),
  /** Preenchido quando a pergunta vira FAQ ou é ligada a um conteúdo. */
  conteudoVinculadoId: z.string().nullable(),
});
export type PerguntaSemResposta = z.infer<typeof perguntaSemRespostaSchema>;

export const perguntaFormSchema = z.object({
  categoriaSugerida: z.string().min(2, 'Informe a categoria.'),
  responsavel: z.string().nullable().default(null),
  status: z.enum(STATUS_PERGUNTA),
  conteudoVinculadoId: z.string().nullable().default(null),
});
export type PerguntaForm = z.infer<typeof perguntaFormSchema>;
