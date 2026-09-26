import { Navigate, type RouteObject } from 'react-router-dom';
import { AdminLayout } from '@/layouts/admin-layout';
import { PaginaOfertas } from '@/pages/ofertas';
import { PaginaCatalogo } from '@/pages/catalogo';
import { PaginaConteudo } from '@/pages/conteudo';
import { PaginaDocumentos } from '@/pages/documentos';
import { PaginaConversas } from '@/pages/conversas';
import { PaginaPerguntas } from '@/pages/perguntas';
import { PaginaUsuarios } from '@/pages/usuarios';
import { PaginaAuditoria } from '@/pages/auditoria';
import { PaginaConfiguracoes } from '@/pages/configuracoes';
import { PaginaAvaliacaoDoDia } from '@/pages/avaliacao-do-dia';
import { PaginaAvaliacaoDoEvento } from '@/pages/avaliacao-do-evento';
import { PaginaNaoEncontrada } from '@/pages/nao-encontrada';

/* ============================================================
   ROTAS
   ============================================================
   Os módulos com edição em drawer têm duas entradas para a MESMA
   página: `/catalogo` e `/catalogo/:id`. A listagem continua montada
   atrás do drawer e o endereço é compartilhável.

   A raiz leva ao Catálogo. Decisão da Adriana (26/09/2026): a visão
   geral, o Evento e a Home V3 eram do app do Summit e saíram do painel,
   que é o painel de controle da inteligência do Mind. A tela inicial
   fica no Catálogo até ela definir outra. */
export const rotasAdmin: RouteObject[] = [
  {
    path: '/',
    element: <AdminLayout />,
    children: [
      { index: true, element: <Navigate to="catalogo" replace /> },

      { path: 'catalogo', element: <PaginaCatalogo /> },
      { path: 'catalogo/:id', element: <PaginaCatalogo /> },

      { path: 'ofertas', element: <PaginaOfertas /> },
      { path: 'ofertas/:id', element: <PaginaOfertas /> },

      { path: 'conteudo', element: <PaginaConteudo /> },
      { path: 'conteudo/:id', element: <PaginaConteudo /> },

      { path: 'documentos', element: <PaginaDocumentos /> },
      { path: 'documentos/:id', element: <PaginaDocumentos /> },

      { path: 'conversas', element: <PaginaConversas /> },
      { path: 'conversas/:id', element: <PaginaConversas /> },

      { path: 'perguntas', element: <PaginaPerguntas /> },
      { path: 'perguntas/:id', element: <PaginaPerguntas /> },

      { path: 'avaliacao-do-dia', element: <PaginaAvaliacaoDoDia /> },
      { path: 'avaliacao-do-evento', element: <PaginaAvaliacaoDoEvento /> },

      { path: 'usuarios', element: <PaginaUsuarios /> },
      { path: 'auditoria', element: <PaginaAuditoria /> },
      { path: 'configuracoes', element: <PaginaConfiguracoes /> },

      { path: '*', element: <PaginaNaoEncontrada /> },
    ],
  },
];
