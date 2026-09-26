import { Package, type LucideIcon } from 'lucide-react';
import type { Acao } from '@/lib/permissions';

/* ============================================================
   MENU LATERAL
   ============================================================
   Uma lista só, consumida pela barra lateral E pelas rotas. Item novo
   aqui aparece nos dois lugares — e nos testes de navegação, que
   percorrem esta mesma lista.

   Um título por vertical — Summit, Institute, Dash —, pedido da
   Adriana (26/09/2026). Por ora são só os títulos: as principais tabelas
   de cada vertical entram quando ela as mapear. */

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
  { id: 'summit', rotulo: 'Summit', itens: [] },
  { id: 'institute', rotulo: 'Institute', itens: [] },
  { id: 'dash', rotulo: 'Dash', itens: [] },
];

export const ITENS_NAVEGACAO: ItemNavegacao[] = NAVEGACAO.flatMap((grupo) => grupo.itens);

export function itemPorCaminho(caminho: string): ItemNavegacao | undefined {
  return ITENS_NAVEGACAO.find((item) =>
    item.caminho === '/' ? caminho === '/' : caminho.startsWith(item.caminho),
  );
}
