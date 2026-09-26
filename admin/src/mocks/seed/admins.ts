import type { AdminSistema } from '@/contracts';

/* ============================================================
   ADMINS DO SISTEMA — semente de demonstração
   ============================================================
   Pessoas inventadas, para os testes e para o preview de cada versão
   (montado sem as variáveis do Supabase). O repositório é público:
   nenhum nome ou e-mail real entra aqui. Em produção a lista vem da
   `mindagent-acesso`. */
export const adminsSemente: AdminSistema[] = [
  {
    id: 'adm_ana',
    criadoEm: '2026-09-25T20:00:00+00:00',
    atualizadoEm: '2026-09-25T20:00:00+00:00',
    atualizadoPor: null,
    mindId: '00000000-0000-4000-8000-000000000001',
    nome: 'Ana Exemplo',
    email: 'ana.exemplo@joinmind.com.br',
    papel: 'administrador',
    ativo: true,
    loginLigado: true,
    ultimoLoginEm: '2026-09-26T14:00:00+00:00',
  },
  {
    id: 'adm_bruno',
    criadoEm: '2026-09-26T10:00:00+00:00',
    atualizadoEm: '2026-09-26T10:00:00+00:00',
    atualizadoPor: null,
    mindId: '00000000-0000-4000-8000-000000000002',
    nome: 'Bruno Exemplo',
    email: 'bruno.exemplo@joinmind.com.br',
    papel: 'editor',
    ativo: true,
    loginLigado: false,
    ultimoLoginEm: null,
  },
  {
    id: 'adm_carla',
    criadoEm: '2026-09-20T10:00:00+00:00',
    atualizadoEm: '2026-09-24T18:00:00+00:00',
    atualizadoPor: null,
    mindId: '00000000-0000-4000-8000-000000000003',
    nome: 'Carla Exemplo',
    email: 'carla.exemplo@joinmind.com.br',
    papel: 'analista',
    ativo: false,
    loginLigado: true,
    ultimoLoginEm: '2026-09-21T12:00:00+00:00',
  },
];
