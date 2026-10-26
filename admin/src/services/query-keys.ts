import type { ListFilters, NomeRecurso } from '@/contracts';

/* ============================================================
   CHAVES DO TANSTACK QUERY
   ============================================================
   Montadas em um lugar só para que invalidar seja previsível:
   escreveu em `products` → invalida `['products']` inteiro, e todas as
   listas filtradas caem junto. */

export const chaves = {
  recurso: (recurso: NomeRecurso) => [recurso] as const,
  lista: (recurso: NomeRecurso, filtros?: ListFilters) =>
    [recurso, 'lista', filtros ?? {}] as const,
  item: (recurso: NomeRecurso, id: string) => [recurso, 'item', id] as const,
};
