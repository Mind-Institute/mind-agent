import { Bot, BrainCircuit, Landmark, BriefcaseBusiness, CalendarDays, ListOrdered, Package, Tag, TicketPercent, UserCog, UsersRound, type LucideIcon } from 'lucide-react';
import type { Acao } from '@/lib/permissions';

/* ============================================================
   MENU LATERAL
   ============================================================
   Uma lista só, consumida pela barra lateral E pelas rotas. Item novo
   aqui aparece nos dois lugares — e nos testes de navegação, que
   percorrem esta mesma lista.

   Um título por vertical — Summit, Institute, Dash —, pedido da
   Adriana (26/09/2026). Por ora são só os títulos: as principais tabelas
   de cada vertical entram quando ela as mapear. Dentro de uma vertical,
   um submenu agrupa as tabelas de um produto: SUMMIT → Mind Summit 2026 →
   Programação (pedido dela no mesmo dia). No topo, o schema `catalogo`
   inteiro — produtos, ofertas e cupons —, porque "o painel é o controle
   deste schema" (Adriana, 26/09/2026). Por último, a Administração:
   quem entra no painel. */

export interface ItemNavegacao {
  id: string;
  rotulo: string;
  caminho: string;
  icone: LucideIcon;
  /** Permissão que o item exige para aparecer habilitado. */
  permissao?: Acao;
  descricao: string;
}

/** Um título dentro do grupo, com itens embaixo: "Mind Summit 2026" → "Programação". */
export interface SubmenuNavegacao {
  id: string;
  rotulo: string;
  icone: LucideIcon;
  itens: ItemNavegacao[];
}

export interface GrupoNavegacao {
  id: string;
  rotulo: string | null;
  itens: ItemNavegacao[];
  submenus?: SubmenuNavegacao[];
}

export const NAVEGACAO: GrupoNavegacao[] = [
  {
    id: 'catalogo',
    rotulo: null,
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
        rotulo: 'Ofertas',
        caminho: '/ofertas',
        icone: Tag,
        descricao: 'Preços, condições, bônus, order bumps e upgrades do schema catalogo.',
      },
      {
        id: 'cupons',
        rotulo: 'Cupons',
        caminho: '/cupons',
        icone: TicketPercent,
        descricao: 'Os cupons de desconto do schema catalogo.',
      },
      {
        id: 'knowledge',
        rotulo: 'Global Knowledge',
        caminho: '/knowledge',
        icone: BrainCircuit,
        descricao: 'Conhecimento científico, metodológico e transversal do Mind.',
      },
      {
        id: 'business-intelligence',
        rotulo: 'Business Intelligence',
        caminho: '/business-intelligence',
        icone: BriefcaseBusiness,
        descricao: 'Governança do conhecimento de produto, oferta, comercial e operação.',
      },
      {
        id: 'customer-intelligence',
        rotulo: 'Customer Intelligence',
        caminho: '/customer-intelligence',
        icone: UsersRound,
        descricao: 'Governança do conhecimento sobre clientes, empresas, conversas e sinais.',
      },
      {
        id: 'agent-intelligence',
        rotulo: 'Agent Intelligence',
        caminho: '/agent-intelligence',
        icone: Bot,
        descricao: 'Matriz Agent × Knowledge para Global, Business e Customer Intelligence.',
      },
    ],
  },
  {
    id: 'summit',
    rotulo: 'Summit',
    itens: [],
    submenus: [
      {
        id: 'summit-2026',
        rotulo: 'Mind Summit 2026',
        icone: CalendarDays,
        itens: [
          {
            id: 'summit-2026-programacao',
            rotulo: 'Programação',
            caminho: '/summit/2026/programacao',
            icone: ListOrdered,
            descricao: 'A programação do Mind Summit 2026 como está no banco (summit_2026.sessions).',
          },
        ],
      },
    ],
  },
  { id: 'institute', rotulo: 'Institute', itens: [] },
  { id: 'dash', rotulo: 'Dash', itens: [] },
  /* Pedido da Adriana (07/10/2026): o espelho das decisões oficiais e o mapa
     de onde cada uma está aplicada. */
  {
    id: 'arquitetura',
    rotulo: 'Arquitetura do sistema',
    itens: [
      {
        id: 'arquitetura-decisoes',
        rotulo: 'Decisões',
        caminho: '/arquitetura/decisoes',
        icone: Landmark,
        descricao: 'As decisões oficiais no Supabase e o mapa de implementação.',
      },
    ],
  },
  {
    id: 'administracao',
    rotulo: 'Administração',
    itens: [
      {
        id: 'admins',
        rotulo: 'Admins do sistema',
        caminho: '/admins',
        icone: UserCog,
        permissao: 'gerir_usuarios',
        descricao: 'Quem entra no Mind Intelligence Admin — por Mind ID, só da equipe.',
      },
    ],
  },
];

export const ITENS_NAVEGACAO: ItemNavegacao[] = NAVEGACAO.flatMap((grupo) => [
  ...grupo.itens,
  ...(grupo.submenus ?? []).flatMap((submenu) => submenu.itens),
]);

export function itemPorCaminho(caminho: string): ItemNavegacao | undefined {
  return ITENS_NAVEGACAO.find((item) =>
    item.caminho === '/' ? caminho === '/' : caminho.startsWith(item.caminho),
  );
}
