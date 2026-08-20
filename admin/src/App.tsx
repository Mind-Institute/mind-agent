import type { ReactNode } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { RouterProvider, createBrowserRouter } from 'react-router-dom';
import type { Papel } from '@/contracts';
import type { AdminDataProvider } from '@/services/admin-data-provider';
import { ProvedorDeDados } from '@/services/provider-context';
import { ProvedorDeSessao } from '@/hooks/use-sessao';
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
 */
export function Provedores({
  children,
  provider,
  queryClient,
  papelInicial,
}: {
  children: ReactNode;
  provider?: AdminDataProvider;
  queryClient?: QueryClient;
  papelInicial?: Papel;
}) {
  const cliente = queryClient ?? criarClienteDeConsulta();
  return (
    <QueryClientProvider client={cliente}>
      <ProvedorDeDados provider={provider}>
        <ProvedorDeSessao papelInicial={papelInicial}>{children}</ProvedorDeSessao>
      </ProvedorDeDados>
    </QueryClientProvider>
  );
}

/* Sinalizadores do React Router 7 ligados desde já: adotar o
   comportamento novo agora evita uma migração surpresa depois. */
export const FUTURO_ROTEADOR = {
  v7_relativeSplatPath: true,
  v7_fetcherPersist: true,
  v7_normalizeFormMethod: true,
  v7_partialHydration: true,
  v7_skipActionErrorRevalidation: true,
} as const;

export const FUTURO_PROVEDOR = { v7_startTransition: true } as const;

const roteador = createBrowserRouter(rotasAdmin, { future: FUTURO_ROTEADOR });

export function App() {
  return (
    <Provedores>
      <RouterProvider router={roteador} future={FUTURO_PROVEDOR} />
    </Provedores>
  );
}
