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
  /** O roteador pode escolher este agente neste canal. */
  roteavel: z.boolean().default(false),
  /** Entradas (origem_codigo) deste canal que abrem a conversa direto neste agente. */
  entradasDiretas: z.array(z.string()).default([]),
  observacao: z.string().nullable().default(null),
  atualizadoEm: z.string().min(1),
});
export type AgentChannel = z.infer<typeof agentChannelSchema>;

/** `agentes.rotas`: o cadastro de cada agente — nome e o que ele faz. */
export const agentSchema = z.object({
  /** A rota. */
  id: z.string().min(1),
  rota: z.string().min(1),
  nome: z.string().min(1),
  descricao: z.string().nullable().default(null),
  /** As conversas deste agente passam pela análise pós-conversa. */
  analisaConversas: z.boolean().default(true),
  /** Modelo da OpenAI que este agente usa; nulo = padrão do runtime (gpt-5.4). */
  modelo: z.string().nullable().default(null),
  atualizadoEm: z.string().min(1),
});
export type Agent = z.infer<typeof agentSchema>;

/** Peso de palestrantes e sessões para a MIA Summit 2026 (Adriana, 22/10/2026). */
export const PESOS_MIA = ['principal', 'relevante', 'complementar'] as const;
export type PesoMia = (typeof PESOS_MIA)[number];
export const ROTULO_PESO: Record<PesoMia, string> = {
  principal: 'Principal',
  relevante: 'Relevante',
  complementar: 'Complementar',
};
export const summitPesoSchema = z.object({
  /** `palestrante:<id>` ou `sessao:<uuid>`. */
  id: z.string().min(1),
  tipo: z.enum(['palestrante', 'sessao']),
  nome: z.string().min(1),
  detalhe: z.string().nullable().default(null),
  peso: z.enum(PESOS_MIA),
  /* Palestrante */
  destaque: z.boolean().optional(),
  fichaCurada: z.boolean().optional(),
  sessoes: z.array(z.object({ id: z.string(), titulo: z.string(), tipo: z.string().nullable() })).default([]),
  /* Sessão */
  tipoSessao: z.string().nullable().optional(),
  temTranscricao: z.boolean().optional(),
  pesoEfetivo: z.enum(PESOS_MIA).optional(),
  palestrantes: z.array(z.object({ id: z.union([z.string(), z.number()]), nome: z.string(), peso: z.enum(PESOS_MIA) })).default([]),
  atualizadoEm: z.string().nullable().default(null),
});
export type SummitPeso = z.infer<typeof summitPesoSchema>;

/** `engagement.origens`: por onde a pessoa chega ao WhatsApp (botões e popups do site). Só leitura. */
export const channelEntrySchema = z.object({
  /** O código da origem. */
  id: z.string().min(1),
  codigo: z.string().min(1),
  canal: z.string().min(1),
  site: z.string().nullable().default(null),
  rotulo: z.string().nullable().default(null),
  descricao: z.string().nullable().default(null),
  audienciaSugerida: z.string().nullable().default(null),
  ativo: z.boolean(),
  atualizadoEm: z.string().min(1),
});
export type ChannelEntry = z.infer<typeof channelEntrySchema>;

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

export const agentConversationTurnSchema = z.object({
  papel: z.string().min(1),
  /** Já sem telefone e e-mail: a porta do banco mascara. */
  texto: z.string().nullable().default(null),
  criadoEm: z.string().min(1),
  rota: z.string().nullable().default(null),
  modelo: z.string().nullable().default(null),
  duracaoMs: z.number().nullable().default(null),
  ferramentas: z.array(z.object({ nome: z.string().nullable().default(null), ok: z.boolean().nullable().default(null) })).default([]),
});
export type AgentConversationTurn = z.infer<typeof agentConversationTurnSchema>;

export const agentConversationAnalysisSchema = z.object({
  analisador: z.string().min(1),
  analisadoEm: z.string().min(1),
  modelo: z.string().nullable().default(null),
  dados: z.unknown().optional(),
});
export type AgentConversationAnalysis = z.infer<typeof agentConversationAnalysisSchema>;

/** Uma conversa real atendida por um agente nosso. Só administrador vê; nunca traz telefone nem e-mail. */
export const agentConversationSchema = z.object({
  id: z.string().min(1),
  canal: z.string().min(1),
  /** mindagent-chat | treble-inbound-agent | mindagent-playground (teste). */
  agente: z.string().nullable().default(null),
  teste: z.boolean().default(false),
  /** O agente que respondeu por último. */
  rota: z.string().nullable().default(null),
  /** Todos os agentes que responderam nela. */
  rotas: z.array(z.string()).default([]),
  primeiroNome: z.string().nullable().default(null),
  iniciadaEm: z.string().nullable().default(null),
  ultimaAtividade: z.string().nullable().default(null),
  mensagens: z.number().int().default(0),
  skills: z.array(z.string()).default([]),
  analisadores: z.array(z.string()).default([]),
  /** Só ao abrir uma conversa. */
  falas: z.array(agentConversationTurnSchema).default([]),
  analises: z.array(agentConversationAnalysisSchema).default([]),
});
export type AgentConversation = z.infer<typeof agentConversationSchema>;

/** Uma execução da análise pós-conversa (`intelligence.analise_conversa`) e o que ela gravou. Só administrador. */
export const analysisRunSchema = z.object({
  id: z.string().min(1),
  conversaId: z.string().min(1),
  analisador: z.string().min(1),
  funcao: z.string().nullable().default(null),
  vertical: z.string().nullable().default(null),
  modelo: z.string().nullable().default(null),
  promptVersao: z.number().int().nullable().default(null),
  analisadoEm: z.string().min(1),
  canal: z.string().nullable().default(null),
  agente: z.string().nullable().default(null),
  rota: z.string().nullable().default(null),
  primeiroNome: z.string().nullable().default(null),
  memoriasGravadas: z.number().int().default(0),
  continuidade: z.string().nullable().default(null),
  /** Só ao abrir uma execução; mascarado. */
  dados: z.unknown().nullable().optional(),
  memorias: z.array(z.object({
    tipo: z.string().nullable().default(null),
    chave: z.string().nullable().default(null),
    status: z.string().nullable().default(null),
    confianca: z.number().nullable().default(null),
    valor: z.unknown().optional(),
  })).default([]),
});
export type AnalysisRun = z.infer<typeof analysisRunSchema>;
