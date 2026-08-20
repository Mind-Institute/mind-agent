import { useCallback, useMemo } from 'react';
import { useSearchParams } from 'react-router-dom';
import type { ListFilters } from '@/contracts';

/* ============================================================
   FILTROS NA URL
   ============================================================
   O estado dos filtros vive na query string: assim um link de
   pendência da visão geral (`/programacao?espacoId=null`) já abre a
   listagem no recorte certo, e a tela é compartilhável.

   Só metadado entra aqui — dia, espaço, status. Nunca dado pessoal:
   URL vaza em histórico, log de proxy e print de tela. */

export function useFiltrosUrl(padrao: Record<string, string> = {}) {
  const [params, setParams] = useSearchParams();

  const filtros = useMemo<Record<string, string>>(() => {
    const resultado: Record<string, string> = { ...padrao };
    params.forEach((valor, chave) => {
      resultado[chave] = valor;
    });
    return resultado;
  }, [params, padrao]);

  const definir = useCallback(
    (chave: string, valor: string | null) => {
      const proximos = new URLSearchParams(params);
      if (valor === null || valor === '' || valor === 'todos') proximos.delete(chave);
      else proximos.set(chave, valor);
      setParams(proximos, { replace: true });
    },
    [params, setParams],
  );

  const limpar = useCallback(() => setParams(new URLSearchParams(), { replace: true }), [setParams]);

  const ativos = useMemo(
    () => Array.from(params.keys()).filter((c) => params.get(c)),
    [params],
  );

  /** Formato aceito pelo `AdminDataProvider.list`. */
  const paraProvedor = useMemo<ListFilters>(() => {
    const saida: ListFilters = {};
    for (const [chave, valor] of Object.entries(filtros)) {
      if (valor === '' || valor === 'todos') continue;
      saida[chave] = valor;
    }
    return saida;
  }, [filtros]);

  return { filtros, paraProvedor, definir, limpar, ativos };
}
