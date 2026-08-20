import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react';
import type { Papel } from '@/contracts';
import { pode, type Acao } from '@/lib/permissions';

/* ============================================================
   SESSÃO SIMULADA
   ============================================================
   Enquanto o Supabase Auth não está ligado, o painel trabalha com um
   "usuário atual" de mentira, trocável pelo seletor do topo. Serve
   para revisar como cada papel vê a interface.

   Quando o Auth entrar, este contexto passa a ler
   `supabase.auth.getUser()` e o papel vem de uma tabela do banco —
   nunca de `user_metadata`. A assinatura do hook não muda. */

export interface SessaoAdmin {
  nome: string;
  papel: Papel;
  /** `true` enquanto o papel vem do seletor, e não de um login real. */
  simulada: boolean;
}

interface ValorContexto extends SessaoAdmin {
  definirPapel: (papel: Papel) => void;
  pode: (acao: Acao) => boolean;
}

const Contexto = createContext<ValorContexto | null>(null);

export function ProvedorDeSessao({
  children,
  papelInicial = 'administrador',
  nome = 'Você (demonstração)',
}: {
  children: ReactNode;
  papelInicial?: Papel;
  nome?: string;
}) {
  const [papel, setPapel] = useState<Papel>(papelInicial);

  const definirPapel = useCallback((novo: Papel) => setPapel(novo), []);

  const valor = useMemo<ValorContexto>(
    () => ({
      nome,
      papel,
      simulada: true,
      definirPapel,
      pode: (acao: Acao) => pode(papel, acao),
    }),
    [nome, papel, definirPapel],
  );

  return <Contexto.Provider value={valor}>{children}</Contexto.Provider>;
}

export function useSessao(): ValorContexto {
  const valor = useContext(Contexto);
  if (!valor) throw new Error('useSessao precisa estar dentro de <ProvedorDeSessao>.');
  return valor;
}
