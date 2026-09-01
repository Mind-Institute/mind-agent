import { z } from 'zod';
import { registroBaseSchema } from './common';

/* ============================================================
   HOME V3 — o que o participante vê, e quando
   ============================================================
   Dois assuntos no mesmo módulo, porque são a mesma pergunta vista de
   dois lados: o que está na tela agora.

   1. O MOMENTO — a home tem quatro composições e uma delas está no ar.
      Pode ser trocada na mão ou por horário programado.
   2. OS AVISOS — o que aparece na lista de "Avisos importantes", com
      disparo imediato ou agendado.

   Os nomes dos recursos (`home_state`, `home_schedule`, `home_notices`)
   são os mesmos que a Edge Function vai usar na URL. */

/* ---------------- Momento ---------------- */

export const MOMENTOS_HOME = ['antes', 'no-evento', 'entre-dias', 'depois'] as const;
export type MomentoHome = (typeof MOMENTOS_HOME)[number];

export const ROTULO_MOMENTO: Record<MomentoHome, string> = {
  antes: 'Antes',
  'no-evento': 'No evento',
  'entre-dias': 'Entre dias',
  depois: 'Depois',
};

/** O que cada momento coloca na frente da pessoa. Aparece no painel para
 *  quem troca saber o que está trocando. */
export const RESUMO_MOMENTO: Record<MomentoHome, string> = {
  antes: 'Recomendações, diagnóstico e os avisos de preparação.',
  'no-evento': 'A próxima sessão da grade e o registro de insight.',
  'entre-dias': 'Fechamento do dia e preparação do Dia 2.',
  depois: 'Entrevista guiada, insights e o plano pós-Summit.',
};

/* O estado é único: existe uma home no ar por vez. Vive como um registro
   só, do mesmo jeito que `event`. */
export const estadoHomeSchema = registroBaseSchema.extend({
  /* O que está no ar agora. */
  momento: z.enum(MOMENTOS_HOME),
  /* `manual` ignora a programação; `programado` deixa os horários
     mandarem. A distinção existe para o dia do evento: alguém precisa
     poder assumir o controle sem apagar a agenda inteira. */
  modo: z.enum(['manual', 'programado']),
});
export type EstadoHome = z.infer<typeof estadoHomeSchema>;

export const estadoHomeFormSchema = z.object({
  momento: z.enum(MOMENTOS_HOME),
  modo: z.enum(['manual', 'programado']).default('manual'),
});
export type EstadoHomeForm = z.infer<typeof estadoHomeFormSchema>;

/* ---------------- Programação de troca ---------------- */

export const trocaHomeFormSchema = z.object({
  quando: z.string().min(1, 'Informe a data e a hora da troca.'),
  momento: z.enum(MOMENTOS_HOME),
  nota: z.string().max(200).default(''),
});
export type TrocaHomeForm = z.infer<typeof trocaHomeFormSchema>;

export const trocaHomeSchema = registroBaseSchema.extend({
  /* ISO local do evento. */
  quando: z.string(),
  momento: z.enum(MOMENTOS_HOME),
  nota: z.string(),
  /* Vira `true` quando o horário passou e a troca foi aplicada. Guardar
     em vez de apagar deixa o histórico auditável. */
  aplicada: z.boolean(),
});
export type TrocaHome = z.infer<typeof trocaHomeSchema>;

/* ---------------- Avisos ---------------- */

/* Ícones que o participante já vê no app. A lista é fechada de
   propósito: ícone livre viraria emoji, e o app tem uma linguagem. */
export const ICONES_AVISO = [
  'megafone',
  'lugar',
  'relogio',
  'ingresso',
  'fone',
  'agenda',
  'alerta',
  'estrela',
] as const;
export type IconeAviso = (typeof ICONES_AVISO)[number];

export const ROTULO_ICONE_AVISO: Record<IconeAviso, string> = {
  megafone: 'Megafone — comunicado geral',
  lugar: 'Local — mudança de sala ou espaço',
  relogio: 'Relógio — horário',
  ingresso: 'Ingresso — credencial e entrada',
  fone: 'Fone — tradução e áudio',
  agenda: 'Agenda — programação',
  alerta: 'Alerta — atenção imediata',
  estrela: 'Estrela — destaque',
};

export const avisoHomeFormSchema = z
  .object({
    icone: z.enum(ICONES_AVISO).default('megafone'),
    titulo: z.string().min(3, 'Informe o título do aviso.').max(80),
    subtitulo: z.string().max(120).default(''),
    descricao: z.string().min(3, 'Escreva a mensagem que a pessoa vai ler.').max(1200),
    /* Imediato ignora o horário. É o caminho do dia do evento. */
    imediato: z.boolean().default(false),
    disparoEm: z.string().default(''),
  })
  .refine((v) => v.imediato || v.disparoEm.trim() !== '', {
    message: 'Escolha o horário de disparo ou marque disparo imediato.',
    path: ['disparoEm'],
  });
export type AvisoHomeForm = z.infer<typeof avisoHomeFormSchema>;

export const avisoHomeSchema = registroBaseSchema.extend({
  icone: z.enum(ICONES_AVISO),
  titulo: z.string(),
  /* O subtítulo é a linha de apoio no card da home. */
  subtitulo: z.string(),
  /* A descrição é o que abre quando a pessoa toca. */
  descricao: z.string(),
  imediato: z.boolean(),
  disparoEm: z.string(),
  /* `rascunho` ainda não vai para ninguém; `agendado` espera o horário;
     `no-ar` está visível na home; `encerrado` saiu de circulação. */
  situacao: z.enum(['rascunho', 'agendado', 'no-ar', 'encerrado']),
});
export type AvisoHome = z.infer<typeof avisoHomeSchema>;

export const ROTULO_SITUACAO_AVISO: Record<AvisoHome['situacao'], string> = {
  rascunho: 'Rascunho',
  agendado: 'Agendado',
  'no-ar': 'No ar',
  encerrado: 'Encerrado',
};
