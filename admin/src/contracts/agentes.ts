import { z } from 'zod';

/* ============================================================
   AGENTES — canais, kit, prompts, instruções e ferramentas de cada agente
   ============================================================
   Servidos pela `mindagent-knowledge` a partir do schema `agentes`:
   `canal_competencia`, `kit_blocos` e `prompts` (com o histórico em
   `prompts_historico`), e de `concierge.ferramentas`. Mudam o
   comportamento do agente na hora: só o papel administrador edita
   (Adriana, 22/10/2026). */

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
  /** structured | knowledge | tools | decisioning | instrucoes. */
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

/** Uma camada do que o agente recebe antes de responder. */
export const agentInstructionPartSchema = z.object({
  /** base | playbook | instrucoes | decisioning. */
  camada: z.string().min(1),
  /** Chave do prompt em `agentes.prompts`. */
  chave: z.string().min(1),
  titulo: z.string().nullable().default(null),
  /** O texto está ligado (vale em todo lugar onde é usado). */
  promptAtivo: z.boolean(),
  /** O bloco está ligado neste agente. `null` em base e playbook, que não são blocos. */
  blocoAtivo: z.boolean().nullable().default(null),
  /** Ligado e sem texto, o agente não responde. */
  obrigatorio: z.boolean(),
  ordem: z.number().int().nullable().default(null),
  chars: z.number().int(),
  atualizadoEm: z.string().nullable().default(null),
  /** Outros agentes em que o mesmo bloco está ligado. */
  compartilhadoCom: z.array(z.string()).default([]),
  /** Entra de fato no texto que o agente recebe agora. */
  entra: z.boolean(),
});
export type AgentInstructionPart = z.infer<typeof agentInstructionPartSchema>;

/** `public.mind_agent_instrucoes`: a mesma montagem que o runtime usa. */
export const agentInstructionsSchema = z.object({
  /** A rota. */
  id: z.string().min(1),
  rota: z.string().min(1),
  /** Há instrução para o agente: sem isso ele não responde. */
  ok: z.boolean(),
  chars: z.number().int(),
  /** O que impede o agente de ter instrução. */
  faltando: z.array(z.string()).default([]),
  partes: z.array(agentInstructionPartSchema).default([]),
  /** O texto completo, na ordem. Só vem ao abrir um agente. */
  texto: z.string().nullable().default(null),
});
export type AgentInstructions = z.infer<typeof agentInstructionsSchema>;

export const agentToolVersionSchema = z.object({
  versao: z.number().int().nullable().default(null),
  conteudo: z.string().nullable().default(null),
  vigenteDesde: z.string().nullable().default(null),
  substituidaEm: z.string().min(1),
  substituidaPor: z.string().nullable().default(null),
});
export type AgentToolVersion = z.infer<typeof agentToolVersionSchema>;

/** `concierge.ferramentas`: as skills. A descrição é instrução: o modelo a lê para decidir quando usar. */
export const agentToolSchema = z.object({
  /** O nome. */
  id: z.string().min(1),
  nome: z.string().min(1),
  descricao: z.string().nullable().default(null),
  parametros: z.unknown().optional(),
  ativo: z.boolean(),
  escrita: z.boolean(),
  versao: z.number().int().nullable().default(null),
  atualizadoEm: z.string().min(1),
  /** Agentes em que a ferramenta está ligada. */
  usadoPor: z.array(z.string()).default([]),
  /** Descrições anteriores, mais recente primeiro. Só vem ao abrir uma ferramenta. */
  historico: z.array(agentToolVersionSchema).default([]),
});
export type AgentTool = z.infer<typeof agentToolSchema>;
