/* ============================================================
   BANCO EM MEMÓRIA
   ============================================================
   Um objeto por recurso, com o mesmo nome que a Edge Function usa na URL
   (`products`). O `MockAdminDataProvider` lê e escreve aqui; ao
   recarregar a página tudo volta ao estado inicial — nada é persistido,
   e o painel diz isso na tela.

   Existe para os testes e para o preview de cada versão, que é montado
   sem as variáveis do Supabase. Em produção o painel só mostra dado real
   (decisão da Adriana, 26/09/2026): o Catálogo vem da `mindagent-catalogo`.

   `criarBanco()` devolve uma instância NOVA a cada chamada: cada teste
   trabalha no seu próprio banco, sem herdar a escrita do anterior. */

import type { MapaRecursos, NomeRecurso } from '@/contracts';
import { produtosSemente } from './seed/catalogo';

export type BancoMock = {
  [K in NomeRecurso]: MapaRecursos[K][];
};

/** Cópia profunda simples — o suficiente para dados JSON puros. */
function clonar<T>(valor: T): T {
  return JSON.parse(JSON.stringify(valor)) as T;
}

export function criarBanco(): BancoMock {
  return {
    products: clonar(produtosSemente),
  };
}
