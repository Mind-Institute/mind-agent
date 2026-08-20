import { createContext, useContext, useMemo, type ReactNode } from 'react';
import type { AdminDataProvider } from './admin-data-provider';
import { MockAdminDataProvider } from './mock-admin-data-provider';
import { HttpAdminDataProvider } from './http-admin-data-provider';

/* ============================================================
   ESCOLHA DA IMPLEMENTAÇÃO
   ============================================================
   Uma variável decide: com `VITE_ADMIN_API_BASE_URL` preenchida o
   painel fala HTTP; vazia, ele roda em modo demonstração. As páginas
   não sabem qual dos dois está ativo — nem precisam. */

const Contexto = createContext<AdminDataProvider | null>(null);

export function criarProvedorPadrao(): AdminDataProvider {
  const base = import.meta.env.VITE_ADMIN_API_BASE_URL?.trim();
  if (base) return new HttpAdminDataProvider({ baseUrl: base });
  return new MockAdminDataProvider();
}

export function ProvedorDeDados({
  provider,
  children,
}: {
  provider?: AdminDataProvider;
  children: ReactNode;
}) {
  const valor = useMemo(() => provider ?? criarProvedorPadrao(), [provider]);
  return <Contexto.Provider value={valor}>{children}</Contexto.Provider>;
}

export function useAdminData(): AdminDataProvider {
  const provedor = useContext(Contexto);
  if (!provedor) {
    throw new Error('useAdminData precisa estar dentro de <ProvedorDeDados>.');
  }
  return provedor;
}

/** `true` quando o painel está rodando com dados simulados. */
export function useModoDemonstracao(): boolean {
  return useAdminData().modo === 'mock';
}
