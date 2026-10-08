/* Tipos e legenda do mapa. As decisões vêm de arquitetura.decisoes,
   pela leitura autenticada de mindagent-home. Nenhum texto aprovado é
   mantido manualmente neste módulo. */

export type Camada = 'documentos' | 'banco' | 'funcoes' | 'edge' | 'contratos' | 'painel';

export const CAMADAS: { id: Camada; rotulo: string }[] = [
  { id: 'documentos', rotulo: 'Documentos' },
  { id: 'banco', rotulo: 'Banco (tabelas)' },
  { id: 'funcoes', rotulo: 'Funções e gatilhos' },
  { id: 'edge', rotulo: 'Edge Functions' },
  { id: 'contratos', rotulo: 'Testes de contrato' },
  { id: 'painel', rotulo: 'Painel' },
];

export type Situacao = 'aplicada' | 'parcial' | 'so-documento';

export const ROTULO_SITUACAO: Record<Situacao, string> = {
  aplicada: 'Aplicada no sistema',
  parcial: 'Aplicada em parte',
  'so-documento': 'Só no papel',
};

export interface LugarAplicado {
  camada: Camada;
  /** Arquivo, tabela ou função — como aparece no repo ou no banco. */
  onde: string;
  oQueFaz: string;
}

export interface Decisao {
  id: string;
  texto: string;
  significado: string;
  aprovadaPor: string;
  vigencia: string;
  substituidaPor: string | null;
  medidoEm: string | null;
  titulo: string;
  data: string;
  situacao: Situacao | null;
  /** Por que a situação é essa — o que existe e o que falta. */
  leitura: string;
  lugares: LugarAplicado[];
}
