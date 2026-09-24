import type { RouteObject } from 'react-router-dom';
import { AdminLayout } from '@/layouts/admin-layout';
import { PaginaVisaoGeral } from '@/pages/visao-geral';
import { PaginaEvento } from '@/pages/evento';
import { PaginaProgramacao } from '@/pages/programacao';
import { PaginaPalestrantes } from '@/pages/palestrantes';
import { PaginaEspacos } from '@/pages/espacos';
import { PaginaRotas } from '@/pages/rotas';
import { PaginaEstandes } from '@/pages/estandes';
import { PaginaOfertas } from '@/pages/ofertas';
import { PaginaConteudo } from '@/pages/conteudo';
import { PaginaDocumentos } from '@/pages/documentos';
import { PaginaConversas } from '@/pages/conversas';
import { PaginaPerguntas } from '@/pages/perguntas';
import { PaginaUsuarios } from '@/pages/usuarios';
import { PaginaAuditoria } from '@/pages/auditoria';
import { PaginaConfiguracoes } from '@/pages/configuracoes';
import { PaginaHomeVisualizacao } from '@/pages/home-visualizacao';
import { PaginaHomeAvisos } from '@/pages/home-avisos';
import { PaginaNaoEncontrada } from '@/pages/nao-encontrada';

/* ============================================================
   ROTAS
   ============================================================
   Os módulos com edição em drawer têm duas entradas para a MESMA
   página: `/programacao` e `/programacao/:id`. A listagem continua
   montada atrás do drawer, o endereço é compartilhável e o link de
   pendência da visão geral abre direto no registro. */
export const rotasAdmin: RouteObject[] = [
  {
    path: '/',
    element: <AdminLayout />,
    children: [
      { index: true, element: <PaginaVisaoGeral /> },

      { path: 'evento', element: <PaginaEvento /> },

      { path: 'programacao', element: <PaginaProgramacao /> },
      { path: 'programacao/:id', element: <PaginaProgramacao /> },

      { path: 'palestrantes', element: <PaginaPalestrantes /> },
      { path: 'palestrantes/:id', element: <PaginaPalestrantes /> },

      { path: 'espacos', element: <PaginaEspacos /> },
      { path: 'espacos/:id', element: <PaginaEspacos /> },

      { path: 'rotas', element: <PaginaRotas /> },
      { path: 'rotas/:id', element: <PaginaRotas /> },

      { path: 'estandes', element: <PaginaEstandes /> },
      { path: 'estandes/:id', element: <PaginaEstandes /> },

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

      { path: 'home/visualizacao', element: <PaginaHomeVisualizacao /> },
      { path: 'home/avisos', element: <PaginaHomeAvisos /> },
      { path: 'home/avisos/:id', element: <PaginaHomeAvisos /> },

      { path: 'usuarios', element: <PaginaUsuarios /> },
      { path: 'auditoria', element: <PaginaAuditoria /> },
      { path: 'configuracoes', element: <PaginaConfiguracoes /> },

      { path: '*', element: <PaginaNaoEncontrada /> },
    ],
  },
];
