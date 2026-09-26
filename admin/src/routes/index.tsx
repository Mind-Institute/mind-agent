import { Navigate, type RouteObject } from 'react-router-dom';
import { AdminLayout } from '@/layouts/admin-layout';
import { PaginaCatalogo } from '@/pages/catalogo';
import { PaginaAdmins } from '@/pages/admins';
import { PaginaNaoEncontrada } from '@/pages/nao-encontrada';

/* ============================================================
   ROTAS
   ============================================================
   Os módulos com edição em drawer têm duas entradas para a MESMA
   página: `/catalogo` e `/catalogo/:id`, `/admins` e `/admins/:id`. A listagem continua montada
   atrás do drawer e o endereço é compartilhável.

   A raiz leva ao Catálogo. Decisões da Adriana (26/09/2026): a visão
   geral, o Evento e a Home V3 eram do app do Summit e saíram do painel,
   que é o painel de controle da inteligência do Mind; e saiu também tudo
   o que não era dado real (ofertas, conteúdo, documentos, conversas,
   perguntas, usuários e auditoria em demonstração). A tela inicial fica
   no Catálogo até ela definir outra. */
export const rotasAdmin: RouteObject[] = [
  {
    path: '/',
    element: <AdminLayout />,
    children: [
      { index: true, element: <Navigate to="catalogo" replace /> },

      { path: 'catalogo', element: <PaginaCatalogo /> },
      { path: 'catalogo/:id', element: <PaginaCatalogo /> },

      { path: 'admins', element: <PaginaAdmins /> },
      { path: 'admins/:id', element: <PaginaAdmins /> },

      { path: '*', element: <PaginaNaoEncontrada /> },
    ],
  },
];
