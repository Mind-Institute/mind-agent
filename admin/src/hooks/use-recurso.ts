import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import type {
  ListFilters,
  ListResult,
  MapaRecursos,
  NomeRecurso,
  OpcoesEscrita,
} from '@/contracts';
import { chaves } from '@/services/query-keys';
import { useAdminData } from '@/services/provider-context';

/* ============================================================
   ACESSO A RECURSOS
   ============================================================
   As páginas usam estes hooks e nunca o provedor direto. Cada escrita
   invalida o recurso inteiro: todas as listas filtradas caem junto. */

export function useLista<K extends NomeRecurso>(
  recurso: K,
  filtros: ListFilters = {},
  opcoes: { enabled?: boolean } = {},
) {
  const provedor = useAdminData();
  return useQuery<ListResult<MapaRecursos[K]>>({
    queryKey: chaves.lista(recurso, filtros),
    queryFn: () => provedor.list(recurso, filtros),
    enabled: opcoes.enabled ?? true,
    retry: false,
  });
}

export function useItem<K extends NomeRecurso>(
  recurso: K,
  id: string | undefined,
  opcoes: { enabled?: boolean } = {},
) {
  const provedor = useAdminData();
  return useQuery<MapaRecursos[K]>({
    queryKey: chaves.item(recurso, id ?? ''),
    queryFn: () => provedor.get(recurso, id as string),
    enabled: Boolean(id) && (opcoes.enabled ?? true),
    retry: false,
  });
}

function useInvalidar(recurso: NomeRecurso) {
  const cliente = useQueryClient();
  return () => {
    void cliente.invalidateQueries({ queryKey: chaves.recurso(recurso) });
  };
}

export function useCriar<K extends NomeRecurso>(recurso: K) {
  const provedor = useAdminData();
  const invalidar = useInvalidar(recurso);
  return useMutation({
    mutationFn: (payload: Partial<MapaRecursos[K]>) => provedor.create(recurso, payload),
    onSuccess: invalidar,
  });
}

export function useAtualizar<K extends NomeRecurso>(recurso: K) {
  const provedor = useAdminData();
  const invalidar = useInvalidar(recurso);
  return useMutation({
    mutationFn: (args: {
      id: string;
      payload: Partial<MapaRecursos[K]>;
      opcoes?: OpcoesEscrita;
    }) => provedor.update(recurso, args.id, args.payload, args.opcoes),
    onSuccess: invalidar,
  });
}

export function usePublicar<K extends NomeRecurso>(recurso: K) {
  const provedor = useAdminData();
  const invalidar = useInvalidar(recurso);
  return useMutation({
    mutationFn: (args: { id: string; opcoes?: OpcoesEscrita }) =>
      provedor.publish(recurso, args.id, args.opcoes),
    onSuccess: invalidar,
  });
}

export function useArquivar<K extends NomeRecurso>(recurso: K) {
  const provedor = useAdminData();
  const invalidar = useInvalidar(recurso);
  return useMutation({
    mutationFn: (args: { id: string; opcoes?: OpcoesEscrita }) =>
      provedor.archive(recurso, args.id, args.opcoes),
    onSuccess: invalidar,
  });
}
