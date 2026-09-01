import { createContext, useContext, useMemo, type ReactNode } from 'react';
import type { AdminApiError, NomeRecurso } from '@/contracts';
import { useSessaoOpcional } from '@/hooks/use-sessao';
import type { AdminDataProvider } from './admin-data-provider';
import { MockAdminDataProvider } from './mock-admin-data-provider';
import { HttpAdminDataProvider, type ProvedorDeToken } from './http-admin-data-provider';
import { HybridAdminDataProvider } from './hybrid-admin-data-provider';

/* ============================================================
   ESCOLHA DA IMPLEMENTAÇÃO
   ============================================================
   Duas variáveis decidem, e as páginas não sabem de nenhuma das duas:

   - sem `VITE_ADMIN_API_BASE_URL` → `mock`, sempre. Sem endereço o
     painel não inventa um.
   - com a URL, `VITE_ADMIN_DATA_MODE` escolhe entre `mock`, `hybrid`
     (núcleo do evento na API, módulos de apoio em memória — quais são
     quais está em `RECURSOS_REAIS`) e `http` (tudo na API). Ausente, o
     padrão é `hybrid`, o estado desta etapa. */

export type ModoDados = 'mock' | 'http' | 'hybrid';

const MODOS: ModoDados[] = ['mock', 'http', 'hybrid'];

export function modoConfigurado(): ModoDados {
  const base = import.meta.env.VITE_ADMIN_API_BASE_URL?.trim();
  if (!base) return 'mock';
  const declarado = import.meta.env.VITE_ADMIN_DATA_MODE?.trim() as ModoDados | undefined;
  return declarado && MODOS.includes(declarado) ? declarado : 'hybrid';
}

/** Fábrica: recebe o acesso à sessão e devolve o provedor montado. */
export type FabricaProvedor = (opcoes: OpcoesFabrica) => AdminDataProvider;

export interface OpcoesFabrica {
  obterToken?: ProvedorDeToken;
  aoNaoAutorizado?: (erro: AdminApiError) => void;
}

export function criarProvedorPadrao(opcoes: OpcoesFabrica = {}): AdminDataProvider {
  const base = import.meta.env.VITE_ADMIN_API_BASE_URL?.trim();
  const modo = modoConfigurado();
  if (modo === 'mock' || !base) return new MockAdminDataProvider();

  const http = new HttpAdminDataProvider({
    baseUrl: base,
    obterToken: opcoes.obterToken,
    chavePublicavel: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
    aoNaoAutorizado: opcoes.aoNaoAutorizado,
  });

  if (modo === 'http') return http;
  return new HybridAdminDataProvider(http, new MockAdminDataProvider());
}

const Contexto = createContext<AdminDataProvider | null>(null);

export function ProvedorDeDados({
  provider,
  children,
}: {
  /**
   * Instância pronta, ou uma fábrica que recebe `obterToken` e
   * `aoNaoAutorizado`. A fábrica existe para os testes montarem o
   * provedor HTTP ligado à sessão de verdade — é assim que dá para
   * verificar o token no header e o 401 voltando para o login.
   */
  provider?: AdminDataProvider | FabricaProvedor;
  children: ReactNode;
}) {
  /* `obterToken` e `marcarSessaoExpirada` têm identidade estável (são
     `useCallback` sem dependências, lendo refs), então o provedor é
     construído uma vez e não se recria a cada renovação de token. */
  const sessao = useSessaoOpcional();
  const obterToken = sessao?.obterToken;
  const aoNaoAutorizado = sessao?.marcarSessaoExpirada;

  const valor = useMemo(() => {
    if (typeof provider === 'function') return provider({ obterToken, aoNaoAutorizado });
    return provider ?? criarProvedorPadrao({ obterToken, aoNaoAutorizado });
  }, [provider, obterToken, aoNaoAutorizado]);

  return <Contexto.Provider value={valor}>{children}</Contexto.Provider>;
}

export function useAdminData(): AdminDataProvider {
  const provedor = useContext(Contexto);
  if (!provedor) {
    throw new Error('useAdminData precisa estar dentro de <ProvedorDeDados>.');
  }
  return provedor;
}


export function useModoDados(): ModoDados {
  return useAdminData().modo;
}

/**
 * De onde ESTE recurso vem agora.
 *
 * As páginas usam isto para não mentir depois de salvar: em módulo real
 * a confirmação fala do backend; em módulo simulado ela avisa que nada
 * saiu do navegador.
 */
export function useOrigemRecurso(resource: NomeRecurso): 'http' | 'mock' {
  return useAdminData().origemDoRecurso(resource);
}

/** `true` quando o recurso é servido pela API real. */
export function useRecursoReal(resource: NomeRecurso): boolean {
  return useOrigemRecurso(resource) === 'http';
}
