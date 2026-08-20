/* ============================================================
   SEMENTES PEQUENAS — o que não vem do summit.json
   ============================================================
   Rotas, estandes, ofertas, conteúdo institucional, documentos,
   fontes, usuários. São poucos registros de propósito: o objetivo é
   exercitar cada tela (inclusive os estados ruins), não simular o
   evento inteiro.

   NENHUM DADO PESSOAL REAL. As pessoas aqui são fictícias e os
   endereços usam domínios de exemplo. */

import type {
  Conteudo,
  Documento,
  Estande,
  Fonte,
  Oferta,
  Rota,
  Sessao,
  Usuario,
} from '@/contracts';

const CRIADO_EM = '2026-08-05T10:00:00.000Z';
const POR = 'Equipe Mind';

/* ------------------------------------------------------------------ */
/* Sessão de demonstração — choque de horário                          */
/* ------------------------------------------------------------------ */
/**
 * A grade real do `summit.json` não tem nenhum conflito de horário, o
 * que é ótimo para o evento e péssimo para revisar a tela: a detecção
 * de conflito nunca apareceria.
 *
 * Este registro é a exceção, e é declarado como tal — ele NÃO vem do
 * arquivo importado, o título diz o que ele é, e ele nasce em rascunho.
 * Some junto com os mocks quando o painel passar a ler do backend.
 */
export const sessoesDemonstracao: Sessao[] = [
  {
    id: 'ses_demo_conflito',
    titulo: 'Sessão de demonstração — choque de horário na Arena Mind',
    descricao:
      'Registro de demonstração do painel. Existe para a detecção de conflito ter o que mostrar: ele ocupa a Arena Mind no mesmo horário da Abertura.',
    dia: '2026-09-16',
    inicio: '09:00',
    fim: '09:30',
    espacoId: 'esp_arena-mind',
    tipo: 'experiencia',
    formato: 'presencial',
    trilhas: ['mind'],
    temas: ['cultura'],
    palestranteIds: [],
    quemTexto: 'Equipe Mind',
    necessitaReserva: false,
    vagasTotais: null,
    vagasDisponiveis: null,
    nivel: null,
    resultadosEsperados: [],
    status: 'rascunho',
    publicadoEm: null,
    publicadoPor: null,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
];

/* ------------------------------------------------------------------ */
/* Rotas entre espaços                                                 */
/* ------------------------------------------------------------------ */
export const rotasSemente: Rota[] = [
  {
    id: 'rot_001',
    origemId: 'esp_arena-mind',
    destinoId: 'esp_arena-sextante',
    instrucoes:
      'Saindo da Arena Mind pela lateral direita, siga o corredor central até o cruzamento com a área de patrocinadores. A Arena Sextante fica logo à direita.',
    distanciaMetros: 120,
    tempoEstimadoMinutos: 3,
    acessivel: true,
    bidirecional: true,
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'rot_002',
    origemId: 'esp_arena-mind',
    destinoId: 'esp_sala-workshop-1',
    instrucoes:
      'Da Arena Mind, vá até o café e vire à esquerda. A Sala Workshop 1 é a primeira porta.',
    distanciaMetros: 85,
    tempoEstimadoMinutos: 2,
    acessivel: true,
    bidirecional: true,
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'rot_003',
    origemId: 'esp_arena-mind',
    destinoId: 'esp_prime-lounge',
    instrucoes:
      'Pela escada ao lado da Arena Mind, suba ao mezanino. O acesso é conferido na porta — só credencial Prime.',
    distanciaMetros: 60,
    tempoEstimadoMinutos: 3,
    /* Só escada: a rota acessível ainda não foi mapeada — e a tela diz isso. */
    acessivel: false,
    bidirecional: true,
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'rot_004',
    origemId: 'esp_sala-workshop-1',
    destinoId: 'esp_sala-workshop-2',
    instrucoes: 'Portas vizinhas, no mesmo corredor.',
    distanciaMetros: 15,
    tempoEstimadoMinutos: 1,
    acessivel: true,
    bidirecional: true,
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'rot_005',
    origemId: 'esp_arena-sextante',
    destinoId: 'esp_livraria-da-vila',
    instrucoes:
      'Saindo da Arena Sextante, siga pela área expositiva. A Livraria da Vila fica no final, à esquerda.',
    distanciaMetros: 140,
    tempoEstimadoMinutos: 4,
    acessivel: true,
    bidirecional: false,
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
];

/* ------------------------------------------------------------------ */
/* Estandes                                                            */
/* ------------------------------------------------------------------ */
export const estandesSemente: Estande[] = [
  {
    id: 'est_mind',
    nome: 'Mind Institute',
    slug: 'mind-institute',
    categoria: 'institucional',
    descricao: 'Estande da Mind: demonstração das plataformas e conversa com o time.',
    espacoId: 'esp_arena-mind',
    site: 'https://exemplo.mind.com.br',
    contato: 'estande@exemplo.com.br',
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'est_sextante',
    nome: 'Editora Sextante',
    slug: 'editora-sextante',
    categoria: 'patrocinio',
    descricao: 'Lançamentos e sessões de autógrafos dos autores do Summit.',
    espacoId: 'esp_arena-sextante',
    site: 'https://exemplo.sextante.com.br',
    contato: 'contato@exemplo.com.br',
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'est_saude',
    nome: 'Espaço Saúde',
    slug: 'espaco-saude',
    categoria: 'saude',
    descricao: 'Aferição, orientação e acolhimento durante os dois dias.',
    espacoId: null,
    site: '',
    contato: '',
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'est_cafe',
    nome: 'Café do Summit',
    slug: 'cafe-do-summit',
    categoria: 'alimentacao',
    descricao: '',
    espacoId: null,
    site: '',
    contato: '',
    ativo: false,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
];

/* ------------------------------------------------------------------ */
/* Ingressos e ofertas                                                 */
/* ------------------------------------------------------------------ */
export const ofertasSemente: Oferta[] = [
  {
    id: 'ofe_mind',
    codigo: 'MIND-2026',
    nome: 'Ingresso Mind',
    descricao: 'Acesso aos dois dias, à Arena Mind e às áreas abertas.',
    moeda: 'BRL',
    valorCentavos: 89000,
    condicoesPagamento: 'Em até 6x sem juros no cartão, ou Pix à vista.',
    checkoutUrl: 'https://exemplo.checkout.com.br/mind-2026',
    elegibilidade: 'Aberto ao público.',
    publico: 'geral',
    dataInicio: '2026-03-01',
    dataFim: '2026-09-15',
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'ofe_vip',
    codigo: 'VIP-2026',
    nome: 'Ingresso VIP',
    descricao: 'Tudo do Mind, mais os workshops com vaga limitada.',
    moeda: 'BRL',
    valorCentavos: 149000,
    condicoesPagamento: 'Em até 10x sem juros no cartão.',
    checkoutUrl: 'https://exemplo.checkout.com.br/vip-2026',
    elegibilidade: 'Aberto ao público.',
    publico: 'geral',
    dataInicio: '2026-03-01',
    dataFim: '2026-09-15',
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'ofe_prime',
    codigo: 'PRIME-2026',
    nome: 'Ingresso Prime',
    /* Sem checkout: a oferta existe, mas ninguém consegue comprar. O agente
       precisa saber disso antes de recomendar. */
    descricao: 'Masterclasses, Prime Lounge e autógrafos exclusivos.',
    moeda: 'BRL',
    valorCentavos: 249000,
    condicoesPagamento: 'Consultar o comercial.',
    checkoutUrl: '',
    elegibilidade: 'Vagas limitadas, sujeito a aprovação.',
    publico: 'convidado',
    dataInicio: '2026-03-01',
    dataFim: '2026-09-10',
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'ofe_lote1',
    codigo: 'LOTE1',
    nome: 'Primeiro lote',
    descricao: 'Lote promocional de lançamento.',
    moeda: 'BRL',
    valorCentavos: 69000,
    condicoesPagamento: '',
    checkoutUrl: 'https://exemplo.checkout.com.br/lote-1',
    elegibilidade: 'Encerrado.',
    publico: 'geral',
    dataInicio: '2026-01-10',
    /* Oferta vencida: continua na base e a tela precisa marcar. */
    dataFim: '2026-04-30',
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'ofe_corp',
    codigo: 'CORP-10',
    nome: 'Pacote corporativo (10 ingressos)',
    descricao: 'Compra em bloco para times.',
    moeda: 'BRL',
    /* Valor ausente: o agente não pode responder "quanto custa". */
    valorCentavos: null,
    condicoesPagamento: 'Faturamento em 30 dias mediante contrato.',
    checkoutUrl: '',
    elegibilidade: 'Empresas com CNPJ ativo.',
    publico: 'corporativo',
    dataInicio: '2026-03-01',
    dataFim: '2026-09-01',
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
];

/* ------------------------------------------------------------------ */
/* Conteúdo institucional da Mind                                      */
/* ------------------------------------------------------------------ */
export const conteudosSemente: Conteudo[] = [
  {
    id: 'con_sobre',
    categoria: 'sobre',
    slug: 'quem-e-a-mind',
    titulo: 'Quem é a Mind',
    conteudo:
      'A Mind trabalha saúde mental e cultura organizacional com método e evidência. Atua com diagnóstico, formação de lideranças e acompanhamento contínuo dentro das empresas.',
    publico: 'publico',
    validoAte: '',
    status: 'publicado',
    publicadoEm: '2026-08-06T13:00:00.000Z',
    publicadoPor: 'Ana Ribeiro',
    criadoEm: CRIADO_EM,
    atualizadoEm: '2026-08-06T13:00:00.000Z',
    atualizadoPor: 'Ana Ribeiro',
  },
  {
    id: 'con_metodo',
    categoria: 'metodologia',
    slug: 'metodologia-mind',
    titulo: 'A metodologia Mind',
    conteudo:
      'Três frentes que andam juntas: medir o que hoje é invisível, formar quem lidera e sustentar a mudança com ritual e acompanhamento. Sem as três, o programa vira campanha.',
    publico: 'publico',
    validoAte: '',
    status: 'publicado',
    publicadoEm: '2026-08-06T13:10:00.000Z',
    publicadoPor: 'Ana Ribeiro',
    criadoEm: CRIADO_EM,
    atualizadoEm: '2026-08-06T13:10:00.000Z',
    atualizadoPor: 'Ana Ribeiro',
  },
  {
    id: 'con_produtos',
    categoria: 'produtos',
    slug: 'plataformas-e-produtos',
    titulo: 'Plataformas e produtos',
    conteudo:
      'Rascunho inicial da página de produtos. Falta alinhar nomes comerciais com o time de marketing antes de publicar.',
    publico: 'publico',
    validoAte: '',
    status: 'rascunho',
    publicadoEm: null,
    publicadoPor: null,
    criadoEm: CRIADO_EM,
    atualizadoEm: '2026-08-12T09:30:00.000Z',
    atualizadoPor: 'Bruno Lemos',
  },
  {
    id: 'con_comercial',
    categoria: 'comercial',
    slug: 'como-contratar',
    titulo: 'Como contratar a Mind',
    conteudo:
      'O contato comercial começa por um diagnóstico gratuito de 30 minutos. A partir dele o time monta a proposta com escopo, prazo e investimento.',
    publico: 'publico',
    validoAte: '2026-12-31',
    status: 'em_revisao',
    publicadoEm: null,
    publicadoPor: null,
    criadoEm: CRIADO_EM,
    atualizadoEm: '2026-08-14T16:45:00.000Z',
    atualizadoPor: 'Bruno Lemos',
  },
  {
    id: 'con_historia',
    categoria: 'historia',
    slug: 'linha-do-tempo',
    titulo: 'Linha do tempo da Mind',
    conteudo:
      'Da primeira turma de formação ao Summit: os marcos da Mind ano a ano, com os números de cada etapa.',
    publico: 'publico',
    validoAte: '',
    status: 'publicado',
    publicadoEm: '2026-08-07T11:00:00.000Z',
    publicadoPor: 'Ana Ribeiro',
    criadoEm: CRIADO_EM,
    atualizadoEm: '2026-08-07T11:00:00.000Z',
    atualizadoPor: 'Ana Ribeiro',
  },
  {
    id: 'con_contato',
    categoria: 'contato',
    slug: 'canais-de-contato',
    titulo: 'Canais de contato',
    conteudo:
      'Atendimento pelo WhatsApp do Summit e pelo formulário do site. O tempo médio de resposta é de um dia útil.',
    publico: 'publico',
    validoAte: '',
    status: 'publicado',
    publicadoEm: '2026-08-07T11:20:00.000Z',
    publicadoPor: 'Ana Ribeiro',
    criadoEm: CRIADO_EM,
    atualizadoEm: '2026-08-07T11:20:00.000Z',
    atualizadoPor: 'Ana Ribeiro',
  },
];

/* ------------------------------------------------------------------ */
/* Fontes e documentos                                                 */
/* ------------------------------------------------------------------ */
export const fontesSemente: Fonte[] = [
  {
    id: 'fon_site',
    nome: 'Site do Mind Summit',
    tipo: 'site',
    descricao: 'Páginas públicas do evento, varridas por URL.',
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'fon_notion',
    nome: 'Base de conhecimento (Notion)',
    tipo: 'notion',
    descricao: 'Manual de atendimento e respostas padrão do time.',
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'fon_upload',
    nome: 'Envio manual',
    tipo: 'upload',
    descricao: 'PDFs e planilhas enviados pelo painel.',
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
];

export const documentosSemente: Documento[] = [
  {
    id: 'doc_faq_geral',
    titulo: 'FAQ geral do Summit',
    fonteId: 'fon_site',
    tipoConteudo: 'faq',
    urlOrigem: 'https://exemplo.mindsummit.com.br/faq',
    previa:
      'Como chego ao evento? Posso transferir meu ingresso? O que está incluído em cada trilha? Onde retiro a credencial?',
    agentes: ['mind_agent', 'treble'],
    statusIndexacao: 'indexado',
    indexadoEm: '2026-08-10T08:00:00.000Z',
    erroIndexacao: null,
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: '2026-08-10T08:00:00.000Z',
    atualizadoPor: POR,
  },
  {
    id: 'doc_politica_reembolso',
    titulo: 'Política de reembolso e transferência',
    fonteId: 'fon_site',
    tipoConteudo: 'politica',
    urlOrigem: 'https://exemplo.mindsummit.com.br/politica',
    previa:
      'Reembolso integral até 30 dias antes do evento. Transferência de titularidade permitida até 48 horas antes.',
    agentes: ['mind_agent', 'treble'],
    /* Conteúdo mudou depois da última indexação: o agente responde o texto velho. */
    statusIndexacao: 'desatualizado',
    indexadoEm: '2026-07-02T08:00:00.000Z',
    erroIndexacao: null,
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: '2026-08-15T10:20:00.000Z',
    atualizadoPor: POR,
  },
  {
    id: 'doc_manual_atendimento',
    titulo: 'Manual de atendimento — tom e limites',
    fonteId: 'fon_notion',
    tipoConteudo: 'guia',
    urlOrigem: 'https://exemplo.notion.site/manual-atendimento',
    previa:
      'O agente mostra o caminho; quem confirma é a pessoa. Nunca prometer vaga, nunca reservar no lugar de ninguém.',
    agentes: ['mind_agent', 'treble'],
    statusIndexacao: 'indexado',
    indexadoEm: '2026-08-11T09:00:00.000Z',
    erroIndexacao: null,
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: '2026-08-11T09:00:00.000Z',
    atualizadoPor: POR,
  },
  {
    id: 'doc_mapa_pdf',
    titulo: 'Mapa do pavilhão (PDF)',
    fonteId: 'fon_upload',
    tipoConteudo: 'pdf',
    urlOrigem: '',
    previa: 'Planta baixa com a numeração dos estandes e a localização das arenas.',
    agentes: ['mind_agent'],
    statusIndexacao: 'nao_indexado',
    indexadoEm: null,
    erroIndexacao: null,
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'doc_precos',
    titulo: 'Tabela de preços e lotes',
    fonteId: 'fon_upload',
    tipoConteudo: 'planilha',
    urlOrigem: '',
    previa: 'Lotes, valores por trilha e condições de pagamento por público.',
    agentes: ['treble'],
    statusIndexacao: 'erro',
    indexadoEm: null,
    erroIndexacao: 'Planilha sem cabeçalho na primeira aba — o extrator não encontrou colunas.',
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: '2026-08-13T14:00:00.000Z',
    atualizadoPor: POR,
  },
  {
    id: 'doc_acessibilidade',
    titulo: 'Guia de acessibilidade do evento',
    fonteId: 'fon_site',
    tipoConteudo: 'pagina',
    urlOrigem: 'https://exemplo.mindsummit.com.br/acessibilidade',
    previa:
      'Acessos, banheiros adaptados, atendimento prioritário e recursos de audiodescrição nas arenas.',
    agentes: ['mind_agent', 'treble'],
    statusIndexacao: 'na_fila',
    indexadoEm: null,
    erroIndexacao: null,
    ativo: true,
    criadoEm: CRIADO_EM,
    atualizadoEm: '2026-08-18T17:00:00.000Z',
    atualizadoPor: POR,
  },
];

/* ------------------------------------------------------------------ */
/* Usuários                                                            */
/* ------------------------------------------------------------------ */
/* Pessoas fictícias, domínio de exemplo. O e-mail é mascarado na tela. */
export const usuariosSemente: Usuario[] = [
  {
    id: 'usr_ana',
    nome: 'Ana Ribeiro',
    email: 'ana.ribeiro@exemplo.com.br',
    papel: 'administrador',
    ativo: true,
    ultimoAcessoEm: '2026-08-19T18:20:00.000Z',
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'usr_bruno',
    nome: 'Bruno Lemos',
    email: 'bruno.lemos@exemplo.com.br',
    papel: 'editor',
    ativo: true,
    ultimoAcessoEm: '2026-08-19T12:05:00.000Z',
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'usr_carla',
    nome: 'Carla Nunes',
    email: 'carla.nunes@exemplo.com.br',
    papel: 'aprovador',
    ativo: true,
    ultimoAcessoEm: '2026-08-18T09:40:00.000Z',
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'usr_diego',
    nome: 'Diego Farias',
    email: 'diego.farias@exemplo.com.br',
    papel: 'atendimento',
    ativo: true,
    ultimoAcessoEm: '2026-08-20T08:15:00.000Z',
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
  {
    id: 'usr_elisa',
    nome: 'Elisa Prado',
    email: 'elisa.prado@exemplo.com.br',
    papel: 'analista',
    ativo: false,
    ultimoAcessoEm: null,
    criadoEm: CRIADO_EM,
    atualizadoEm: CRIADO_EM,
    atualizadoPor: POR,
  },
];
