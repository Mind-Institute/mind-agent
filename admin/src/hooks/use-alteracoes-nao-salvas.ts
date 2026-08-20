import { useEffect } from 'react';
import { useBlocker } from 'react-router-dom';

/* ============================================================
   ALTERAÇÕES NÃO SALVAS
   ============================================================
   Duas saídas possíveis, duas defesas:

   1. Trocar de rota dentro do painel → `useBlocker` do React Router
      segura a navegação e a página abre o diálogo de confirmação.
   2. Fechar a aba ou recarregar → `beforeunload`, que só o navegador
      desenha (não dá para customizar o texto, e tudo bem). */

export interface BloqueioNavegacao {
  bloqueado: boolean;
  confirmar: () => void;
  cancelar: () => void;
}

export function useAlteracoesNaoSalvas(temAlteracoes: boolean): BloqueioNavegacao {
  const bloqueador = useBlocker(
    ({ currentLocation, nextLocation }) =>
      temAlteracoes && currentLocation.pathname !== nextLocation.pathname,
  );

  useEffect(() => {
    if (!temAlteracoes) return undefined;
    const aoSair = (evento: BeforeUnloadEvent) => {
      evento.preventDefault();
      /* Navegadores modernos ignoram a mensagem, mas o valor precisa
         estar definido para o diálogo padrão aparecer. */
      evento.returnValue = '';
    };
    window.addEventListener('beforeunload', aoSair);
    return () => window.removeEventListener('beforeunload', aoSair);
  }, [temAlteracoes]);

  return {
    bloqueado: bloqueador.state === 'blocked',
    confirmar: () => bloqueador.proceed?.(),
    cancelar: () => bloqueador.reset?.(),
  };
}
