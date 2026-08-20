/* ============================================================
   VISÃO GERAL
   ============================================================
   O painel é o sistema operacional do evento: a primeira tela não é
   um relatório bonito, é a lista do que está faltando para o agente
   conseguir responder. */

export interface MetricaPainel {
  chave: string;
  rotulo: string;
  valor: number;
  /** Rota para a listagem que explica o número. */
  destino: string;
  /** `atencao` pinta o cartão de coral quando o número deveria ser zero. */
  tom?: 'neutro' | 'atencao';
  detalhe?: string;
}

export type CategoriaPendencia =
  | 'sessoes_sem_espaco'
  | 'sessoes_sem_palestrante'
  | 'espacos_sem_localizacao'
  | 'palcos_sem_alias'
  | 'ofertas_sem_checkout'
  | 'documentos_sem_indexacao'
  | 'conteudo_em_rascunho';

export interface ItemPendencia {
  id: string;
  rotulo: string;
  /** Link direto para o registro que precisa de conserto. */
  destino: string;
}

export interface GrupoPendencia {
  categoria: CategoriaPendencia;
  titulo: string;
  descricao: string;
  total: number;
  /** Amostra — o total pode ser maior que a lista. */
  itens: ItemPendencia[];
  destino: string;
}

export interface AlertaPainel {
  id: string;
  nivel: 'info' | 'atencao' | 'erro';
  titulo: string;
  descricao: string;
  destino?: string;
}

export interface ResumoPainel {
  metricas: MetricaPainel[];
  pendencias: GrupoPendencia[];
  alertas: AlertaPainel[];
  geradoEm: string;
}
