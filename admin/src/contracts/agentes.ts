import { z } from 'zod';

/* ============================================================
   AGENTES — canais, kit e prompts de cada agente
   ============================================================
   Servidos pela `mindagent-knowledge` a partir do schema `agentes`:
   `canal_competencia`, `kit_blocos` e `prompts` (com o histórico em
   `prompts_historico`). Mudam o comportamento do agente na hora: só o
   papel administrador edita (Adriana, 22/10/2026). */

/** `agentes.canal_competencia`: em que canal o agente pode atuar. */
export const agentChannelSchema = z.object({
  /** `canal::rota`. */
  id: z.string().min(1),
  canal: z.string().min(1),
  rota: z.string().min(1),
  ativo: z.boolean(),
  observacao: z.string().nullable().default(null),
  atualizadoEm: z.string().min(1),
});
export type AgentChannel = z.infer<typeof agentChannelSchema>;

/** `agentes.kit_blocos`: as informações e ferramentas que o agente recebe. */
export const agentKitBlockSchema = z.object({
  /** `rota::bloco`. */
  id: z.string().min(1),
  rota: z.string().min(1),
  bloco: z.string().min(1),
  provider: z.string().min(1),
  /** structured | knowledge | tools | decisioning. */
  secao: z.string().min(1),
  obrigatorio: z.boolean(),
  ativo: z.boolean(),
  atualizadoEm: z.string().min(1),
});
export type AgentKitBlock = z.infer<typeof agentKitBlockSchema>;

export const agentPromptVersionSchema = z.object({
  versao: z.number().int().nullable().default(null),
  titulo: z.string().nullable().default(null),
  conteudo: z.string().nullable().default(null),
  ativo: z.boolean(),
  vigenteDesde: z.string().nullable().default(null),
  substituidaEm: z.string().min(1),
  substituidaPor: z.string().nullable().default(null),
});
export type AgentPromptVersion = z.infer<typeof agentPromptVersionSchema>;

/** `agentes.prompts`. `rota` existe quando a chave é `playbook_<rota>`. */
export const agentPromptSchema = z.object({
  /** A própria chave. */
  id: z.string().min(1),
  chave: z.string().min(1),
  titulo: z.string().nullable().default(null),
  conteudo: z.string().nullable().default(null),
  ativo: z.boolean(),
  versao: z.number().int().nullable().default(null),
  produtoCodigo: z.string().nullable().default(null),
  atualizadoEm: z.string().min(1),
  rota: z.string().nullable().default(null),
  /** Rotas que usam este prompt como bloco de decisioning no kit. */
  usadoPor: z.array(z.string()).default([]),
  /** Versões anteriores, mais recente primeiro. Só vem ao abrir um prompt. */
  historico: z.array(agentPromptVersionSchema).default([]),
});
export type AgentPrompt = z.infer<typeof agentPromptSchema>;
