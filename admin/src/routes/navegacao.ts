import { CalendarDays, ListOrdered, Package, UserCog, type LucideIcon } from 'lucide-react';
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
   Programação (pedido dela no mesmo dia). Por último, a Administração:
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
