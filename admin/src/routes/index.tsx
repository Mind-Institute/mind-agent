import { Navigate, type RouteObject } from 'react-router-dom';
import { AdminLayout } from '@/layouts/admin-layout';
import { PaginaCatalogo } from '@/pages/catalogo';
import { PaginaAdmins } from '@/pages/admins';
import { PaginaSummitProgramacao } from '@/pages/summit-programacao';
import { PaginaOfertas } from '@/pages/ofertas';
import { PaginaCupons } from '@/pages/cupons';
import { PaginaKnowledge } from '@/pages/knowledge';
import { PaginaBusinessIntelligence } from '@/pages/business-intelligence';
import { PaginaCustomerIntelligence } from '@/pages/customer-intelligence';
import { PaginaAgentIntelligence } from '@/pages/agent-intelligence';
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

      /* O schema `catalogo` inteiro no painel (Adriana, 26/09/2026): ofertas e cupons. */
      { path: 'ofertas', element: <PaginaOfertas /> },
      /* Criar (e duplicar, com a oferta de origem no caminho — na query ela viraria filtro da lista). */
      { path: 'ofertas/nova', element: <PaginaOfertas criando /> },
      { path: 'ofertas/nova/:de', element: <PaginaOfertas criando /> },
      { path: 'ofertas/:id', element: <PaginaOfertas /> },
      { path: 'cupons', element: <PaginaCupons /> },
      { path: 'cupons/:id', element: <PaginaCupons /> },

      { path: 'summit/2026/programacao', element: <PaginaSummitProgramacao /> },
      { path: 'summit/2026/programacao/:id', element: <PaginaSummitProgramacao /> },

      { path: 'knowledge', element: <PaginaKnowledge /> },
      { path: 'business-intelligence', element: <PaginaBusinessIntelligence /> },
      { path: 'customer-intelligence', element: <PaginaCustomerIntelligence /> },
      { path: 'agent-intelligence', element: <PaginaAgentIntelligence /> },

      { path: 'admins', element: <PaginaAdmins /> },
      { path: 'admins/:id', element: <PaginaAdmins /> },

      { path: '*', element: <PaginaNaoEncontrada /> },
    ],
  },
];
