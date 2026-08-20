import { z } from 'zod';
import { registroBaseSchema } from './common';

/* ============================================================
   INDEXAÇÃO
   ============================================================
   Os seis estados são de leitura: quem muda é o pipeline do backend.
   Nesta fase, "Solicitar reindexação" apenas ENFILEIRA (`na_fila`) e
   diz na tela que nada foi indexado de verdade. */
export const STATUS_INDEXACAO = [
  'nao_indexado',
  'na_fila',
  'indexando',
  'indexado',
  'erro',
  'desatualizado',
] as const;
export const statusIndexacaoSchema = z.enum(STATUS_INDEXACAO);
export type StatusIndexacao = z.infer<typeof statusIndexacaoSchema>;

export const ROTULO_STATUS_INDEXACAO: Record<StatusIndexacao, string> = {
  nao_indexado: 'Não indexado',
  na_fila: 'Na fila',
  indexando: 'Indexando',
  indexado: 'Indexado',
  erro: 'Erro',
  desatualizado: 'Desatualizado',
};

export const TIPOS_CONTEUDO_DOCUMENTO = ['faq', 'politica', 'guia', 'pagina', 'planilha', 'pdf'] as const;
export const ROTULO_TIPO_DOCUMENTO: Record<(typeof TIPOS_CONTEUDO_DOCUMENTO)[number], string> = {
  faq: 'FAQ',
  politica: 'Política',
  guia: 'Guia',
  pagina: 'Página',
  planilha: 'Planilha',
  pdf: 'PDF',
};

/** Quais agentes podem consumir o documento. */
export const AGENTES = ['mind_agent', 'treble'] as const;
export const ROTULO_AGENTE: Record<(typeof AGENTES)[number], string> = {
  mind_agent: 'Mind Agent (chat próprio)',
  treble: 'Treble (WhatsApp)',
};

export const fonteSchema = registroBaseSchema.extend({
  nome: z.string(),
  tipo: z.enum(['site', 'notion', 'drive', 'upload', 'manual']),
  descricao: z.string(),
  ativo: z.boolean(),
});
export type Fonte = z.infer<typeof fonteSchema>;

export const documentoFormSchema = z.object({
  titulo: z.string().min(3, 'Informe o título do documento.'),
  fonteId: z.string().min(1, 'Escolha a fonte.'),
  tipoConteudo: z.enum(TIPOS_CONTEUDO_DOCUMENTO),
  urlOrigem: z.string().url('Informe uma URL válida.').or(z.literal('')).default(''),
  previa: z.string().max(5000).default(''),
  agentes: z.array(z.enum(AGENTES)).min(1, 'Selecione ao menos um agente.'),
  ativo: z.boolean().default(true),
});
export type DocumentoForm = z.infer<typeof documentoFormSchema>;

export const documentoSchema = registroBaseSchema.extend({
  titulo: z.string(),
  fonteId: z.string(),
  tipoConteudo: z.enum(TIPOS_CONTEUDO_DOCUMENTO),
  urlOrigem: z.string(),
  previa: z.string(),
  agentes: z.array(z.enum(AGENTES)),
  statusIndexacao: statusIndexacaoSchema,
  indexadoEm: z.string().nullable(),
  erroIndexacao: z.string().nullable(),
  ativo: z.boolean(),
});
export type Documento = z.infer<typeof documentoSchema>;

/** Recibo do pedido de reindexação. Deixa explícito que é mock. */
export interface ReciboReindexacao {
  documentoId: string;
  statusAnterior: StatusIndexacao;
  statusAtual: StatusIndexacao;
  enfileiradoEm: string;
  /** `true` nesta fase: nada foi indexado de verdade. */
  simulado: boolean;
  mensagem: string;
}
