import { z } from 'zod';
import { registroBaseSchema } from './common';

export const CANAIS = ['chat_proprio', 'whatsapp', 'widget'] as const;
export const ROTULO_CANAL: Record<(typeof CANAIS)[number], string> = {
  chat_proprio: 'Chat próprio',
  whatsapp: 'WhatsApp (Treble)',
  widget: 'Widget do site',
};

export const STATUS_CONVERSA = ['aberta', 'resolvida', 'handoff', 'abandonada'] as const;
export const ROTULO_STATUS_CONVERSA: Record<(typeof STATUS_CONVERSA)[number], string> = {
  aberta: 'Aberta',
  resolvida: 'Resolvida',
  handoff: 'Handoff',
  abandonada: 'Abandonada',
};

export const mensagemSchema = z.object({
  id: z.string(),
  autor: z.enum(['participante', 'agente', 'humano']),
  texto: z.string(),
  enviadaEm: z.string(),
});
export type Mensagem = z.infer<typeof mensagemSchema>;

/**
 * Conversas são SOMENTE LEITURA no painel.
 *
 * `participanteNome` e `participanteContato` chegam já reduzidos e ainda
 * passam por `mascarar*` na exibição. Nenhum dado pessoal real entra nos
 * mocks — as pessoas aqui são fictícias.
 */
export const conversaSchema = registroBaseSchema.extend({
  participanteNome: z.string().nullable(),
  participanteContato: z.string().nullable(),
  canal: z.enum(CANAIS),
  iniciadaEm: z.string(),
  ultimaAtividadeEm: z.string(),
  totalMensagens: z.number(),
  assuntos: z.array(z.string()),
  handoff: z.boolean(),
  status: z.enum(STATUS_CONVERSA),
  mensagens: z.array(mensagemSchema),
});
export type Conversa = z.infer<typeof conversaSchema>;
