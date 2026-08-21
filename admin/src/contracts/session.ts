import { z } from 'zod';
import { registroEditorialSchema, statusEditorialSchema } from './common';

/* ============================================================
   TIPOS DE SESSÃO
   ============================================================
   A lista vem do que a API real usa. Além dos formatos de conteúdo,
   a grade tem blocos operacionais (credenciamento, almoço, intervalo)
   e o marcador de conteúdo ainda não fechado (`em_curadoria`).

   Categoria desconhecida NÃO é convertida em outra: ela aparece na
   tela com o próprio código, via `rotuloTipoSessao`. Traduzir em
   silêncio esconderia mudança de vocabulário do backend — e o painel
   passaria a mentir sobre o que está na base. */
export const TIPOS_SESSAO = [
  'abertura',
  'palestra',
  'painel',
  'workshop',
  'masterclass',
  'experiencia',
  'lancamento',
  'autografos',
  'credenciamento',
  'almoco',
  'intervalo',
  'em_curadoria',
] as const;

export type TipoSessao = (typeof TIPOS_SESSAO)[number];

export const ROTULO_TIPO_SESSAO: Record<TipoSessao, string> = {
  abertura: 'Abertura',
  palestra: 'Palestra',
  painel: 'Painel',
  workshop: 'Workshop',
  masterclass: 'Masterclass',
  experiencia: 'Experiência',
  lancamento: 'Lançamento de livro',
  autografos: 'Autógrafos',
  credenciamento: 'Credenciamento',
  almoco: 'Almoço',
  intervalo: 'Intervalo',
  em_curadoria: 'Em curadoria',
};

export const FORMATOS_SESSAO = ['presencial', 'online', 'hibrido', 'remoto'] as const;
export type FormatoSessao = (typeof FORMATOS_SESSAO)[number];

export const ROTULO_FORMATO_SESSAO: Record<FormatoSessao, string> = {
  presencial: 'Presencial',
  online: 'Online',
  hibrido: 'Híbrido',
  remoto: 'Remoto',
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
    /* Coquetel e sessão de autógrafos não têm hora de término —
       vazio é um valor válido, não um erro de digitação. */
    fim: z.string().regex(HORA, 'Use o formato HH:MM.').or(z.literal('')).default(''),
    espacoId: z.string().min(1, 'Escolha o espaço.'),
    /* String, e não enum: se a API usar uma categoria que o painel
       ainda não conhece, o formulário PRESERVA o valor em vez de
       recusar o registro ou trocar por um parecido. */
    tipo: z.string().min(1, 'Escolha o tipo.'),
    formato: z.string().min(1, 'Escolha o formato.'),
    trilhas: z.array(z.string()).min(1, 'Selecione ao menos uma trilha.'),
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
  /* Obrigatórios: sem eles a linha da grade não existe. */
  titulo: z.string().min(1),
  dia: z.string().min(1),
  inicio: z.string().min(1),
  /* Tipo e formato são STRING, não enum: categoria nova no backend
     chega à tela com o próprio código em vez de travar a listagem. O
     tipo é exigido — ele é a identidade do bloco na grade. */
  tipo: z.string().min(1),
  formato: z.string().default(''),

  /* Opcionais de verdade, com default explícito. */
  descricao: z.string().default(''),
  /** `null` em sessão aberta (coquetel, autógrafos). */
  fim: z.string().nullable().default(null),
  /** `null` = sessão sem espaço, que o painel já trata como pendência. */
  espacoId: z.string().nullable().default(null),
  trilhas: z.array(z.string()).default([]),
  temas: z.array(z.string()).default([]),
  palestranteIds: z.array(z.string()).default([]),
  /** Texto original de `quem`, preservado enquanto a ligação com
   *  `palestranteIds` não estiver completa. */
  quemTexto: z.string().default(''),
  necessitaReserva: z.boolean().default(false),
  vagasTotais: z.number().nullable().default(null),
  vagasDisponiveis: z.number().nullable().default(null),
  nivel: z.enum(NIVEIS_SESSAO).nullable().default(null),
  resultadosEsperados: z.array(z.string()).default([]),
});

export type Sessao = z.infer<typeof sessaoSchema>;
