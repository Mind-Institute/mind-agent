import { z } from 'zod';
import { registroEditorialSchema, statusEditorialSchema } from './common';

export const TIPOS_SESSAO = [
  'abertura',
  'palestra',
  'painel',
  'workshop',
  'masterclass',
  'experiencia',
  'lancamento',
  'autografos',
] as const;
export const ROTULO_TIPO_SESSAO: Record<(typeof TIPOS_SESSAO)[number], string> = {
  abertura: 'Abertura',
  palestra: 'Palestra',
  painel: 'Painel',
  workshop: 'Workshop',
  masterclass: 'Masterclass',
  experiencia: 'Experiência',
  lancamento: 'Lançamento de livro',
  autografos: 'Autógrafos',
};

export const FORMATOS_SESSAO = ['presencial', 'online', 'hibrido'] as const;
export const ROTULO_FORMATO_SESSAO: Record<(typeof FORMATOS_SESSAO)[number], string> = {
  presencial: 'Presencial',
  online: 'Online',
  hibrido: 'Híbrido',
};

export const NIVEIS_SESSAO = ['introdutorio', 'intermediario', 'avancado'] as const;
export const ROTULO_NIVEL_SESSAO: Record<(typeof NIVEIS_SESSAO)[number], string> = {
  introdutorio: 'Introdutório',
  intermediario: 'Intermediário',
  avancado: 'Avançado',
};

export const TRILHAS = ['mind', 'vip', 'prime'] as const;
export const ROTULO_TRILHA: Record<(typeof TRILHAS)[number], string> = {
  mind: 'Mind',
  vip: 'VIP',
  prime: 'Prime',
};

const HORA = /^([01]\d|2[0-3]):[0-5]\d$/;

export const sessaoFormSchema = z
  .object({
    titulo: z.string().min(3, 'Informe o título da sessão.'),
    descricao: z.string().max(4000, 'Máximo de 4000 caracteres.').default(''),
    dia: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Escolha o dia.'),
    inicio: z.string().regex(HORA, 'Use o formato HH:MM.'),
    /* Coquetel e sessão de autógrafos não têm hora de término no
       `summit.json` — vazio é um valor válido, não um erro de digitação. */
    fim: z
      .string()
      .regex(HORA, 'Use o formato HH:MM.')
      .or(z.literal(''))
      .default(''),
    espacoId: z.string().min(1, 'Escolha o espaço.'),
    tipo: z.enum(TIPOS_SESSAO),
    formato: z.enum(FORMATOS_SESSAO),
    trilhas: z.array(z.enum(TRILHAS)).min(1, 'Selecione ao menos uma trilha.'),
    temas: z.array(z.string()).default([]),
    palestranteIds: z.array(z.string()).default([]),
    necessitaReserva: z.boolean().default(false),
    vagasTotais: z.number().int().min(0).nullable().default(null),
    vagasDisponiveis: z.number().int().min(0).nullable().default(null),
    nivel: z.enum(NIVEIS_SESSAO).nullable().default(null),
    resultadosEsperados: z.array(z.string()).default([]),
    status: statusEditorialSchema,
  })
  .refine((v) => v.fim === '' || v.fim > v.inicio, {
    message: 'O horário final precisa ser depois do inicial.',
    path: ['fim'],
  })
  .refine((v) => !v.necessitaReserva || (v.vagasTotais ?? 0) > 0, {
    message: 'Sessão com reserva precisa de vagas totais.',
    path: ['vagasTotais'],
  })
  .refine(
    (v) =>
      v.vagasTotais === null ||
      v.vagasDisponiveis === null ||
      v.vagasDisponiveis <= v.vagasTotais,
    { message: 'Vagas disponíveis não podem exceder as totais.', path: ['vagasDisponiveis'] },
  );

export type SessaoForm = z.infer<typeof sessaoFormSchema>;

export const sessaoSchema = registroEditorialSchema.extend({
  titulo: z.string(),
  descricao: z.string(),
  dia: z.string(),
  inicio: z.string(),
  /** `null` em sessão aberta (coquetel, autógrafos). */
  fim: z.string().nullable(),
  espacoId: z.string().nullable(),
  tipo: z.enum(TIPOS_SESSAO),
  formato: z.enum(FORMATOS_SESSAO),
  trilhas: z.array(z.enum(TRILHAS)),
  temas: z.array(z.string()),
  palestranteIds: z.array(z.string()),
  /** Texto original de `summit.json` — preservado enquanto a ligação
   *  com `palestranteIds` não estiver completa. */
  quemTexto: z.string(),
  necessitaReserva: z.boolean(),
  vagasTotais: z.number().nullable(),
  vagasDisponiveis: z.number().nullable(),
  nivel: z.enum(NIVEIS_SESSAO).nullable(),
  resultadosEsperados: z.array(z.string()),
});

export type Sessao = z.infer<typeof sessaoSchema>;
