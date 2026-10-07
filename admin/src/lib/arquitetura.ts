/* ============================================================
   ARQUITETURA DO SISTEMA — AS DECISÕES E ONDE ELAS ESTÃO
   ============================================================
   Pedido da Adriana (07/10/2026): um espelho das decisões congeladas
   (D1–D6, `PROJECT_STATE.md` e `READ_ME_FIRST.md`) e um mapa de onde
   cada uma está aplicada, para ela decidir quais ficam.

   O texto de cada decisão é o do `PROJECT_STATE.md`; os lugares são os
   arquivos do repo que citam a decisão e as casas do banco que ela
   governa. Os números foram medidos no banco em 07/10/2026 e são uma
   fotografia — não se atualizam sozinhos. Quando o documento mudar,
   este arquivo muda junto. */

export const MEDIDO_EM = '07/10/2026';

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
  titulo: string;
  data: string;
  /** Resumo do texto congelado em `PROJECT_STATE.md`. */
  resumo: string;
  situacao: Situacao;
  /** Por que a situação é essa — o que existe e o que falta. */
  leitura: string;
  lugares: LugarAplicado[];
}

export const DECISOES: Decisao[] = [
  {
    id: 'D1',
    titulo: 'O Supabase é a fonte da verdade do histórico do cliente e alimenta o HubSpot',
    data: '21/09/2026',
    resumo:
      'O HubSpot deixa de ser origem e vira destino. O banco recebe Eduzz, credenciamento e Yazo e organiza a inteligência. Decide a direção do fluxo; ligar a escrita no HubSpot continua atrás de gate.',
    situacao: 'parcial',
    leitura:
      'Os escritores para o HubSpot existem, mas a casa do histórico consolidado (crm.pessoa_produtos) continua vazia e o registro de fontes (registry.fontes) não tem nenhuma linha.',
    lugares: [
      { camada: 'documentos', onde: 'PROJECT_STATE.md §8', oQueFaz: 'Tabela "quem manda em cada fato".' },
      { camada: 'banco', onde: 'crm.pessoa_produtos', oQueFaz: 'Casa do histórico consolidado — 0 linhas, sem escritor.' },
      { camada: 'banco', onde: 'registry.fontes', oQueFaz: 'Classificação de autoridade fonte por fonte — 0 linhas.' },
      { camada: 'funcoes', onde: 'migration 20260923050715_source_registry.sql', oQueFaz: 'Cria o registro de fontes por causa de D1.' },
      { camada: 'funcoes', onde: 'migration 20260923055232_participantes_primeiro_nome_sobrenome.sql', oQueFaz: 'Divide nome e sobrenome para escrever no HubSpot.' },
      { camada: 'funcoes', onde: 'migration 20260923064049_credenciamento_hubspot_plano.sql', oQueFaz: 'Plano de escrita do credenciamento no HubSpot.' },
      { camada: 'edge', onde: 'hubspot-credenciamento-writeback', oQueFaz: 'Escreve o credenciamento do Summit no HubSpot.' },
      { camada: 'edge', onde: 'hubspot-perfil-writeback', oQueFaz: 'Escreve o perfil da pessoa no HubSpot.' },
      { camada: 'contratos', onde: 'tests/credenciamento_hubspot_plano_contract.sql', oQueFaz: 'Confere o plano de escrita.' },
    ],
  },
  {
    id: 'D2',
    titulo: 'Uma única aprovadora: a Adriana',
    data: '21/09/2026',
    resumo:
      'Mudança estrutural de banco — tabela nova, schema novo, troca de quem manda num fato — só com a aprovação dela antes. Dentro de uma casa que já existe, a mudança segue sem passar por ela.',
    situacao: 'aplicada',
    leitura:
      'É uma regra de processo: vale nas instruções de quem trabalha no repo e fica registrada no cabeçalho das migrations que precisaram (ou não) da aprovação.',
    lugares: [
      { camada: 'documentos', onde: 'CLAUDE.md, AGENTS.md, PROJECT_STATE.md §3', oQueFaz: 'Regra para toda IA e pessoa que mexe no banco.' },
      { camada: 'funcoes', onde: 'migration 20260923081119_intelligence_icp_jtbd_catalogos.sql', oQueFaz: 'Tabela nova aprovada por ela (D2).' },
      { camada: 'funcoes', onde: 'migration 20260926201053_catalogo_ofertas_forma_historico_e_cupons.sql', oQueFaz: 'Forma das ofertas aprovada por ela (D2).' },
      { camada: 'funcoes', onde: 'migration 20260926210134_ofertas_edicao_no_painel.sql', oQueFaz: 'Registra que não precisou de D2 (casa existente).' },
    ],
  },
  {
    id: 'D3',
    titulo: 'Escopo do histórico do cliente: Summit completo, Institute parcial, Dash fora',
    data: '21/09/2026',
    resumo:
      'Dash fica fora enquanto não houver dado de cliente ali. Prometer as três verticais hoje seria ficção de dado.',
    situacao: 'so-documento',
    leitura: 'Nenhum código, tabela ou função aplica esta decisão: ela vive só nos documentos.',
    lugares: [
      { camada: 'documentos', onde: 'PROJECT_STATE.md (v9)', oQueFaz: 'Texto da decisão.' },
      { camada: 'documentos', onde: 'docs/CORE_UNIVERSAL.md — "D3 — até onde o histórico do cliente vai hoje"', oQueFaz: 'Tabela por vertical e o porquê.' },
    ],
  },
  {
    id: 'D4',
    titulo: 'Ligar NPS de verdade (0–10), separado das notas 0–5 do Summit',
    data: '21/09/2026',
    resumo:
      'As tabelas de NPS já existem. Falta o escritor e a decisão de produto de onde perguntar, quando e com que frequência.',
    situacao: 'so-documento',
    leitura: 'As duas tabelas existem desde antes da decisão e estão vazias; nada escreve nelas.',
    lugares: [
      { camada: 'documentos', onde: 'PROJECT_STATE.md (v9 e §8)', oQueFaz: 'Texto da decisão.' },
      { camada: 'banco', onde: 'engagement.nps', oQueFaz: 'NPS por participante do evento — 0 linhas.' },
      { camada: 'banco', onde: 'crm.pessoa_nps', oQueFaz: 'NPS por pessoa e produto — 0 linhas.' },
    ],
  },
  {
    id: 'D5',
    titulo: 'Identidade universal — a Regra #1',
    data: '22–23/09/2026',
    resumo:
      'Toda pessoa tem um número único. Quando alguém chega por qualquer canal, o sistema procura antes e só cria se não achar. Ninguém é unificado sem a decisão da Adriana. CPF sozinho não identifica.',
    situacao: 'aplicada',
    leitura:
      '17.243 pessoas (1.648 absorvidas por fusão) e 56.089 identificadores. A porta única roda antes de escrever em 21 tabelas. Fusões: 2.062 feitas, 929 propostas esperando decisão, 2 descartadas.',
    lugares: [
      { camada: 'documentos', onde: 'READ_ME_FIRST.md', oQueFaz: 'A Regra #1 e a tabela de hints.' },
      { camada: 'banco', onde: 'pessoas.pessoas', oQueFaz: 'O registro de todo mundo — 17.243 pessoas.' },
      { camada: 'banco', onde: 'engagement.identidades', oQueFaz: 'E-mail, WhatsApp, CPF e ids de terceiros — 56.089.' },
      { camada: 'banco', onde: 'engagement.identidade_fusoes', oQueFaz: 'Propostas de fusão — 929 pendentes.' },
      { camada: 'funcoes', onde: 'mind_identidade_resolver', oQueFaz: 'A porta única que liga ou cria a pessoa.' },
      { camada: 'funcoes', onde: 'mind_pessoa_antes_de_escrever', oQueFaz: 'Gatilho que passa a linha pela porta — em 21 tabelas.' },
      { camada: 'funcoes', onde: 'mind_fusao_decidir', oQueFaz: 'Única função que funde, por decisão da Adriana.' },
      { camada: 'funcoes', onde: 'mind_pessoa_ligar_tabela', oQueFaz: 'Põe uma tabela nova na regra.' },
      { camada: 'funcoes', onde: 'migrations 20260923024555 a 20260923050355 (d5, d5_2 a d5_5)', oQueFaz: 'A regra, a precedência dos hints e as tabelas da Adriana.' },
      { camada: 'contratos', onde: 'tests/d5_identidade_universal_contract.sql', oQueFaz: 'Confere a regra no banco.' },
      { camada: 'painel', onde: 'Admins do sistema', oQueFaz: 'Só entra quem já existe como pessoa e é da equipe.' },
    ],
  },
  {
    id: 'D6',
    titulo: 'A coluna do número único chama-se mind_id em toda tabela',
    data: '23/09/2026',
    resumo: 'Complemento da D5: o nome da coluna do ID universal é mind_id, em qualquer tabela que fale de pessoa.',
    situacao: 'aplicada',
    leitura: '57 tabelas têm a coluna mind_id.',
    lugares: [
      { camada: 'documentos', onde: 'READ_ME_FIRST.md, CLAUDE.md', oQueFaz: 'O nome da coluna como regra.' },
      { camada: 'banco', onde: '57 tabelas com mind_id', oQueFaz: 'A coluna em toda tabela que fala de pessoa.' },
      { camada: 'funcoes', onde: 'migration 20260923071424_d6_mind_id.sql', oQueFaz: 'Renomeou 51 chaves e 63 funções.' },
      { camada: 'funcoes', onde: 'migration 20260925232508_admins_do_sistema_por_mind_id.sql', oQueFaz: 'Admins do painel por mind_id.' },
      { camada: 'painel', onde: 'Admins do sistema', oQueFaz: 'A lista de admins é por Mind ID.' },
    ],
  },
];

/** As 21 tabelas em que a porta única roda antes de escrever (D5), medidas em 07/10/2026. */
export const TABELAS_NA_PORTA: string[] = [
  'checkout.pedidos',
  'credenciamento_summit_2026."Check Ins Summit"',
  'credenciamento_summit_2026."Relatorio Yazzo Consolidado"',
  'credenciamento_summit_2026."Reservas_Agenda_APP"',
  'credenciamento_summit_2026.controle_de_inscritos_e_presenca',
  'credenciamento_summit_2026.participantes',
  'credenciamento_summit_2026.yazo_espelho',
  'crm.contato_espelho',
  'crm.leads_capturados',
  'crm.pipeline_leads_inbound',
  'crm.status_summit_hs',
  'eduzz.ingressos',
  'eduzz.vendas',
  'engagement.pesquisa_interesse_2025',
  'engagement.pesquisa_summit_2024',
  'engagement.pesquisa_summit_2025',
  'engagement.pesquisa_summit_2026',
  'engagement.verificacoes_email',
  'treble.status_da_conversa',
  'treble.status_hs_contatos',
  'vendasdiretas.espelho',
];
