import { z } from 'zod';
import { registroBaseSchema } from './common';

/* ============================================================
   TIPOS DE ESPAÇO
   ============================================================
   Além dos lugares onde acontece conteúdo (palco, sala, arena), o
   evento tem espaços de operação e de serviço: acesso, alimentação,
   acessibilidade, ativação de patrocinador, área de estandes.

   Cada um muda a resposta do agente. "Onde fica o banheiro adaptado"
   e "onde fica a Arena Mind" não são a mesma pergunta, e achatar os
   dois em `apoio` apagaria a diferença. */
export const TIPOS_ESPACO = [
  'palco',
  'sala',
  'arena',
  'lounge',
  'area_expositiva',
  'apoio',
  'externo',
  'acessibilidade',
  'acesso',
  'alimentacao',
  'ativacao',
  'estandes',
  'servico',
] as const;

export type TipoEspaco = (typeof TIPOS_ESPACO)[number];

export const ROTULO_TIPO_ESPACO: Record<TipoEspaco, string> = {
  palco: 'Palco',
  sala: 'Sala',
  arena: 'Arena',
  lounge: 'Lounge',
  area_expositiva: 'Área expositiva',
  apoio: 'Apoio',
  externo: 'Externo',
  acessibilidade: 'Acessibilidade',
  acesso: 'Acesso',
  alimentacao: 'Alimentação',
  ativacao: 'Ativação',
  estandes: 'Estandes',
  servico: 'Serviço',
};

export const espacoFormSchema = z.object({
  nome: z.string().min(2, 'Informe o nome do espaço.'),
  slug: z
    .string()
    .min(2, 'Informe o slug.')
    .regex(/^[a-z0-9-]+$/, 'Use apenas letras minúsculas, números e hífen.'),
  /* String, e não enum — ver a nota em session.ts. */
  tipo: z.string().min(1, 'Escolha o tipo.'),
  /**
   * Os aliases são como o participante chama o espaço no chat
   * ("palco principal"). Sem eles o agente não encontra o lugar —
   * por isso palco sem alias vira pendência no painel.
   */
  aliases: z.array(z.string().min(2, 'Alias muito curto.')).default([]),
  descricao: z.string().max(2000).default(''),
  comoChegar: z.string().max(2000).default(''),
  localPrincipal: z.string().max(160).default(''),
  espacoPaiId: z.string().nullable().default(null),
  andar: z.string().max(40).default(''),
  coordenadaX: z.number().nullable().default(null),
  coordenadaY: z.number().nullable().default(null),
  acessivel: z.boolean().default(true),
  observacaoAcessibilidade: z.string().max(500).default(''),
  ativo: z.boolean().default(true),
});
export type EspacoForm = z.infer<typeof espacoFormSchema>;

export const espacoSchema = registroBaseSchema.extend({
  /* Obrigatórios: o nome identifica o lugar em toda resposta do agente,
     e o tipo muda o que ele responde — "onde fica o palco" e "onde fica
     o banheiro adaptado" não são a mesma pergunta.
     String, e não enum: tipo novo no backend chega à tela com o próprio
     código em vez de travar a listagem. */
  nome: z.string().min(1),
  tipo: z.string().min(1),

  slug: z.string().default(''),
  aliases: z.array(z.string()).default([]),
  descricao: z.string().default(''),
  comoChegar: z.string().default(''),
  localPrincipal: z.string().default(''),
  espacoPaiId: z.string().nullable().default(null),
  andar: z.string().default(''),
  coordenadaX: z.number().nullable().default(null),
  coordenadaY: z.number().nullable().default(null),
  /* Default `false`: sem a informação, o painel não promete
     acessibilidade que ninguém confirmou. */
  acessivel: z.boolean().default(false),
  observacaoAcessibilidade: z.string().default(''),
  /* Default `true`: registro que existe está em uso até alguém dizer o
     contrário — é o que a listagem já assume ao filtrar por ativos. */
  ativo: z.boolean().default(true),
});
export type Espaco = z.infer<typeof espacoSchema>;
