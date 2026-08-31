/* ============================================================================
 * STUB DO CLIENTE SUPABASE — só para o harness de teste.
 *
 * O `index.ts` importa `createClient` de `npm:@supabase/supabase-js`, que o
 * Node não resolve. O harness reescreve APENAS esse especificador para este
 * arquivo; nenhuma outra linha do fonte é tocada.
 *
 * O stub não decide nada: ele delega para o cenário do teste corrente, que
 * vive em `globalThis.__MIND_EDGE_TESTE__`. Assim o que se testa é sempre o
 * fluxo real do executor, nunca uma reimplementação dele.
 * ==========================================================================*/

function cenario() {
  const atual = globalThis.__MIND_EDGE_TESTE__;
  if (!atual) throw new Error('nenhum cenário ativo: chame `chamar()` do harness');
  return atual;
}

export function createClient(_url, _key, _options) {
  return {
    auth: {
      getUser: async (token) => cenario().getUser(token),
    },
    rpc: async (nome, args) => cenario().rpc(nome, args),
  };
}
