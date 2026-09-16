/* ============================================================================
 * STUB DO CLIENTE SUPABASE — só para o harness da `mindagent-avaliacao`.
 *
 * Arquivo próprio, e não o `supabase-stub.mjs` do chat, por um motivo: esta
 * Edge usa `.from(...).select(...).eq(...).maybeSingle()` para ler o papel do
 * administrador, e aquele stub só conhece `auth` e `rpc`. Estender o de lá
 * mudaria a base de testes de outra lane.
 *
 * O stub não decide nada: delega para o cenário corrente em
 * `globalThis.__MIND_AVALIACAO_TESTE__`.
 * ==========================================================================*/

function cenario() {
  const atual = globalThis.__MIND_AVALIACAO_TESTE__;
  if (!atual) throw new Error('nenhum cenário ativo: chame `chamar()` do harness');
  return atual;
}

export function createClient(_url, _key, _options) {
  return {
    auth: {
      getUser: async (token) => cenario().getUser(token),
    },
    rpc: async (nome, args) => cenario().rpc(nome, args),
    from: (tabela) => {
      const consulta = {
        select: () => consulta,
        eq: () => consulta,
        maybeSingle: async () => cenario().tabela(tabela),
      };
      return consulta;
    },
  };
}
