import type { ReactNode } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { RouterProvider, createBrowserRouter } from 'react-router-dom';
import type { Papel } from '@/contracts';
import type { AdminDataProvider } from '@/services/admin-data-provider';
import type { PortaAutenticacao } from '@/services/auth';
import { criarPortaSupabaseDoAmbiente } from '@/services/auth-supabase';
import { ProvedorDeDados, type FabricaProvedor } from '@/services/provider-context';
import { ProvedorDeSessao } from '@/hooks/use-sessao';
import { GuardaAutenticacao } from '@/components/admin/guarda-autenticacao';
import { rotasAdmin } from '@/routes';

export function criarClienteDeConsulta() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        /* O painel é ferramenta de trabalho: dado velho na tela é pior
           que uma volta a mais no servidor. */
        staleTime: 10_000,
        retry: false,
        refetchOnWindowFocus: false,
      },
      mutations: { retry: false },
    },
  });
}

/**
 * Provedores da aplicação, sem o roteador — é o que os testes montam
 * em volta de um `MemoryRouter` próprio.
 *
 * A ordem importa: a sessão vem ANTES do provedor de dados, porque é
 * dela que sai o `obterToken` que o `HttpAdminDataProvider` usa no
 * header `Authorization`.
 */
export function Provedores({
  children,
  provider,
  queryClient,
  papelInicial,
  porta,
  baseUrlApi = import.meta.env.VITE_ADMIN_API_BASE_URL,
  chavePublicavel = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
  fetchImpl,
}: {
  children: ReactNode;
  provider?: AdminDataProvider | FabricaProvedor;
  queryClient?: QueryClient;
  papelInicial?: Papel;
  /** Ausente = modo simulado (sem login). */
  porta?: PortaAutenticacao | null;
  /** Explícito nos testes, para `/admin/me` não depender do ambiente. */
  baseUrlApi?: string;
  chavePublicavel?: string | null;
  fetchImpl?: typeof fetch;
}) {
  const cliente = queryClient ?? criarClienteDeConsulta();
  return (
    <QueryClientProvider client={cliente}>
      <ProvedorDeSessao
        porta={porta}
        papelInicial={papelInicial}
        baseUrlApi={baseUrlApi}
        chavePublicavel={chavePublicavel}
        fetchImpl={fetchImpl}
      >
        <ProvedorDeDados provider={provider}>
          <GuardaAutenticacao>{children}</GuardaAutenticacao>
        </ProvedorDeDados>
      </ProvedorDeSessao>
    </QueryClientProvider>
  );
}

/* React Router 7: os sinalizadores `v7_*` da versão 6 viraram o
   comportamento padrão, e o `future` do RouterProvider deixou de
   existir. Nada a declarar aqui.

   O `basename` sai do `base` do Vite (`/admin/`), então rota e asset
   nunca discordam: o painel é servido sob /admin ao lado do chat, que
   fica na raiz. Em teste, `BASE_URL` é `/` e o MemoryRouter das suítes
   não passa por aqui. */
const raiz = import.meta.env.BASE_URL.replace(/\/+$/, '');
const roteador = createBrowserRouter(rotasAdmin, raiz ? { basename: raiz } : undefined);

/* Sem Supabase configurado, `porta` é `null` e o painel roda em modo
   demonstração — que é como ele nasceu e continua utilizável. */
const portaSupabase = criarPortaSupabaseDoAmbiente();

export function App() {
  return (
    <Provedores porta={portaSupabase}>
      <RouterProvider router={roteador} />
    </Provedores>
  );
}
