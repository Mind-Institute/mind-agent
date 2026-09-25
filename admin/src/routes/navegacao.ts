import {
  Building2,
  CalendarDays,
  ClipboardList,
  FileQuestion,
  FileText,
  LayoutDashboard,
  MapPin,
  Megaphone,
  MessagesSquare,
  MonitorSmartphone,
  Package,
  Route,
  Settings,
  ShieldCheck,
  Star,
  Store,
  Ticket,
  Users,
  UsersRound,
  type LucideIcon,
} from 'lucide-react';
import type { Acao } from '@/lib/permissions';

/* ============================================================
   MENU LATERAL
   ============================================================
   Uma lista só, consumida pela barra lateral E pelas rotas. Item novo
   aqui aparece nos dois lugares — e nos testes de navegação, que
   percorrem esta mesma lista. */

export interface ItemNavegacao {
  id: string;
  rotulo: string;
  caminho: string;
  icone: LucideIcon;
  /** Permissão que o item exige para aparecer habilitado. */
  permissao?: Acao;
  descricao: string;
}

export interface GrupoNavegacao {
  id: string;
  rotulo: string | null;
  itens: ItemNavegacao[];
}

export const NAVEGACAO: GrupoNavegacao[] = [
  {
    id: 'painel',
    rotulo: null,
    itens: [
      {
        id: 'visao-geral',
        rotulo: 'Visão geral',
        caminho: '/',
        icone: LayoutDashboard,
        descricao: 'Números do evento e o que ainda falta preencher.',
      },
    ],
  },
  {
    id: 'home-v3',
    rotulo: 'Home V3',
    itens: [
      {
        id: 'home-visualizacao',
        rotulo: 'Visualização',
        caminho: '/home/visualizacao',
        icone: MonitorSmartphone,
        descricao: 'Qual das quatro telas está no ar, na mão ou por horário.',
      },
      {
        id: 'home-avisos',
        rotulo: 'Avisos',
        caminho: '/home/avisos',
        icone: Megaphone,
        descricao: 'O que aparece em "Avisos importantes", agora ou agendado.',
      },
    ],
  },
  {
    id: 'evento',
    rotulo: 'Evento',
    itens: [
      {
        id: 'evento',
        rotulo: 'Evento',
        caminho: '/evento',
        icone: CalendarDays,
        descricao: 'Nome, datas, local, fuso e regras gerais.',
      },
      {
        id: 'programacao',
        rotulo: 'Programação',
        caminho: '/programacao',
        icone: ClipboardList,
        descricao: 'Sessões, horários, espaços e trilhas.',
      },
      {
        id: 'palestrantes',
        rotulo: 'Palestrantes',
        caminho: '/palestrantes',
        icone: UsersRound,
        descricao: 'Quem fala, sobre o quê, com que biografia.',
      },
      {
        id: 'espacos',
        rotulo: 'Espaços',
        caminho: '/espacos',
        icone: MapPin,
        descricao: 'Palcos, salas e como o participante chega neles.',
      },
      {
        id: 'rotas',
        rotulo: 'Rotas',
        caminho: '/rotas',
        icone: Route,
        descricao: 'Caminhos entre espaços, com distância e acessibilidade.',
      },
      {
        id: 'estandes',
        rotulo: 'Estandes',
        caminho: '/estandes',
        icone: Store,
        descricao: 'Quem expõe e onde.',
      },
    ],
  },
  {
    id: 'conteudo',
    rotulo: 'Conteúdo e comercial',
    itens: [
      {
        id: 'catalogo',
        rotulo: 'Catálogo',
        caminho: '/catalogo',
        icone: Package,
        descricao: 'A lista oficial de produtos do Mind — a origem de tudo.',
      },
      {
        id: 'ofertas',
        rotulo: 'Ingressos e ofertas',
        caminho: '/ofertas',
        icone: Ticket,
        descricao: 'Códigos, valores, checkout e vigência.',
      },
      {
        id: 'conteudo',
        rotulo: 'Conteúdo da Mind',
        caminho: '/conteudo',
        icone: Building2,
        descricao: 'Textos institucionais que o agente usa para falar da Mind.',
      },
      {
        id: 'documentos',
        rotulo: 'FAQ e documentos',
        caminho: '/documentos',
        icone: FileText,
        descricao: 'Fontes, documentos e estado de indexação.',
      },
    ],
  },
  {
    id: 'atendimento',
    rotulo: 'Atendimento',
    itens: [
      {
        id: 'conversas',
        rotulo: 'Conversas',
        caminho: '/conversas',
        icone: MessagesSquare,
        permissao: 'ver_conversas',
        descricao: 'Histórico somente leitura, com dado pessoal mascarado.',
      },
      {
        id: 'perguntas',
        rotulo: 'Perguntas sem resposta',
        caminho: '/perguntas',
        icone: FileQuestion,
        descricao: 'A fila de melhoria do agente.',
      },
      {
        id: 'avaliacao-do-dia',
        rotulo: 'Avaliação do dia',
        caminho: '/avaliacao-do-dia',
        icone: Star,
        descricao: 'O que os participantes responderam sobre cada dia, de 0 a 5.',
      },
      {
        id: 'avaliacao-do-evento',
        rotulo: 'Avaliação do evento',
        caminho: '/avaliacao-do-evento',
        icone: Star,
        descricao: 'O que eles responderam sobre o Summit inteiro, depois que ele acabou.',
      },
    ],
  },
  {
    id: 'administracao',
    rotulo: 'Administração',
    itens: [
      {
        id: 'usuarios',
        rotulo: 'Usuários e permissões',
        caminho: '/usuarios',
        icone: Users,
        permissao: 'gerir_usuarios',
        descricao: 'Papéis do painel. A autorização real é do backend.',
      },
      {
        id: 'auditoria',
        rotulo: 'Auditoria',
        caminho: '/auditoria',
        icone: ShieldCheck,
        permissao: 'ver_auditoria',
        descricao: 'Quem mudou o quê, quando, e o que havia antes.',
      },
      {
        id: 'configuracoes',
        rotulo: 'Configurações',
        caminho: '/configuracoes',
        icone: Settings,
        descricao: 'Modo de dados, integrações futuras e limites desta versão.',
      },
    ],
  },
];

export const ITENS_NAVEGACAO: ItemNavegacao[] = NAVEGACAO.flatMap((grupo) => grupo.itens);

export function itemPorCaminho(caminho: string): ItemNavegacao | undefined {
  return ITENS_NAVEGACAO.find((item) =>
    item.caminho === '/' ? caminho === '/' : caminho.startsWith(item.caminho),
  );
}
