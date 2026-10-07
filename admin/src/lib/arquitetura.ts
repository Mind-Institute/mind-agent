/* ============================================================
   ARQUITETURA DO SISTEMA — as decisões congeladas
   ============================================================
   Pedido da Adriana (07/10/2026): as decisões de arquitetura no painel,
   num menu "Arquitetura do sistema". A fonte continua sendo
   `PROJECT_STATE.md` (D1–D6) e `CLAUDE.md` (as regras posteriores, ainda
   sem número); esta lista só as resume, com as palavras dela quando o
   documento as traz. Decisão nova entra primeiro lá e depois aqui — o
   teste `arquitetura.test.tsx` lê o `PROJECT_STATE.md` e falha se uma
   decisão numerada estiver de um lado e não do outro. */

export interface DecisaoArquitetura {
  codigo: string;
  data: string;
  titulo: string;
  resumo: string;
  /** Frase dela, como está registrada no documento. */
  palavras?: string;
  /** Onde a decisão está aplicada ou detalhada. */
  ondeVive: string[];
}

export interface RegraPosterior {
  data: string;
  titulo: string;
  resumo: string;
}

export const REPOSITORIO = 'https://github.com/mind-institute/mind-agent/blob/main';

export const DECISOES: DecisaoArquitetura[] = [
  {
    codigo: 'D1',
    data: '21/09/2026',
    titulo: 'O Supabase é a fonte da verdade do histórico do cliente e passa a alimentar o HubSpot',
    resumo:
      'O HubSpot deixa de ser origem e vira destino. O fato bruto continua pertencendo a quem o observou (Eduzz, Yazo…); o histórico consolidado do cliente é do Mind. Ligar a escrita no HubSpot continua atrás do gate existente: D1 decide a direção do fluxo, não autoriza o disparo.',
    palavras:
      'O HubSpot estava com essa informação primária antes da gente. Só que agora a gente já tem o espelho da Eduzz. A gente recebe a informação da Eduzz ou de quem é o checkout, e a gente também é quem recebe a informação da Yazo sobre quem foi. É a gente que precisa organizar nossa inteligência para entender, inclusive, como alimentar o HubSpot.',
    ondeVive: ['PROJECT_STATE.md — §8 "Quem manda em cada fato"', 'crm.pessoa_produtos (a casa do histórico consolidado)'],
  },
  {
    codigo: 'D2',
    data: '21/09/2026',
    titulo: 'Um único aprovador: a Adriana',
    resumo:
      'Ela é a única aprovadora de mudança estrutural de banco: tabela nova, schema novo, fonte nova ou troca de quem manda num fato. Dentro de casa existente e comentada, a mudança segue sem passar por ela.',
    ondeVive: ['PROJECT_STATE.md — §3 "Modo operacional vigente"', 'CLAUDE.md — "Papéis vigentes"'],
  },
  {
    codigo: 'D3',
    data: '21/09/2026',
    titulo: 'Escopo do histórico do cliente',
    resumo:
      'Summit completo, Institute parcial e Dash declarado fora enquanto não houver dado de cliente ali. Prometer as três verticais hoje seria ficção de dado.',
    ondeVive: ['PROJECT_STATE.md — topo (v9)'],
  },
  {
    codigo: 'D4',
    data: '21/09/2026',
    titulo: 'Ligar NPS de verdade',
    resumo:
      'NPS na escala 0–10, separado das notas 0–5 das avaliações do Summit, que não são NPS. As tabelas já existem (engagement.nps e crm.pessoa_nps); falta o escritor e a decisão de produto de onde perguntar, quando e com que frequência.',
    ondeVive: ['PROJECT_STATE.md — topo (v9) e §8', 'engagement.nps · crm.pessoa_nps'],
  },
  {
    codigo: 'D5',
    data: '23/09/2026',
    titulo: 'Identidade universal',
    resumo:
      'Toda pessoa, de qualquer fonte, existe uma vez em pessoas.pessoas. Toda tabela que fala de pessoa tem o ID dela, resolvido ou criado pela porta única mind_identidade_resolver antes da escrita. CPF e CNPJ só apoiam, nunca decidem sozinhos; o nome veta. Fusão de pessoas nunca é automática: é decisão dela, em mind_fusao_decidir.',
    palavras:
      'Toda tabela que tem pessoas deve ter obrigatoriamente o ID da pessoa: resolver ID ou criar antes de escrever a pessoa no sistema, sempre.',
    ondeVive: [
      'READ_ME_FIRST.md — Regra #1',
      'PROJECT_STATE.md — §7 "Identidade e casas canônicas"',
      'Gatilho zz_d5_pessoa_antes_de_escrever em cada tabela de pessoa',
      'supabase/migrations/20260923024555_d5_identidade_universal.sql',
    ],
  },
  {
    codigo: 'D6',
    data: '23/09/2026',
    titulo: 'O ID universal chama-se mind_id',
    resumo:
      'Em toda tabela que fala de pessoa a coluna do ID universal é mind_id (antes pessoa_id, participante_id, participant_id, person_id), acompanhada de mind_id_criterio e mind_id_resolvido_em. Os contratos de API (payloads das funções e views api.*) mantêm os nomes antigos.',
    palavras: 'Renomeie a coluna como universal MIND ID.',
    ondeVive: ['PROJECT_STATE.md — §7', 'supabase/migrations/20260923071424_d6_mind_id.sql'],
  },
];

export const REGRAS_POSTERIORES: RegraPosterior[] = [
  {
    data: '25/09/2026',
    titulo: 'Função nova nasce fechada',
    resumo:
      'O banco não dá mais permissão de execução a todos em função nova. Cada migration concede só a quem chama: o sistema (service_role) ou, de propósito, o app e o site.',
  },
  {
    data: '26/09/2026',
    titulo: 'Preço, oferta, order bump e cupom moram no schema catalogo',
    resumo: 'Em tabelas separadas, e este painel é o controle dele: o que importa ali aparece e se edita aqui.',
  },
  {
    data: '26/09/2026',
    titulo: 'Agente nunca tem preço, oferta, cupom ou prazo escrito',
    resumo:
      'Nem no playbook nem no prompt: o agente sempre aponta para onde estão os preços e as ofertas atuais (o catalogo, pelos blocos do Kit).',
  },
];
