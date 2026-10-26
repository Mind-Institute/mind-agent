/* ============================================================
   RÓTULOS DE CATEGORIA
   ============================================================
   A regra é uma: categoria que o painel não conhece aparece com o
   PRÓPRIO CÓDIGO, nunca traduzida para a categoria mais parecida.

   O motivo é prático. Se o backend passar a usar `em-curadoria` com
   hífen, ou criar `mesa_redonda`, o painel que "arredonda" para
   `palestra` faz o operador editar uma coisa acreditando ser outra —
   e ninguém descobre. Mostrando o código cru, a divergência salta aos
   olhos na primeira listagem. */

export interface Rotulo {
  texto: string;
  /** `false` quando o valor não está no vocabulário do painel. */
  conhecido: boolean;
}

export interface OpcaoCategoria {
  valor: string;
  rotulo: string;
}

/**
 * Opções de um select de categoria, garantindo que o valor ATUAL do
 * registro esteja na lista.
 *
 * Sem isso, um registro com categoria que o painel não conhece abriria
 * o select em branco — e o primeiro salvamento trocaria a categoria
 * por outra sem ninguém pedir. Aqui ela aparece marcada como valor da
 * API e sobrevive à edição de qualquer outro campo.
 */
export function opcoesComAtual(conhecidas: OpcaoCategoria[], atual: string): OpcaoCategoria[] {
  if (!atual || conhecidas.some((o) => o.valor === atual)) return conhecidas;
  return [...conhecidas, { valor: atual, rotulo: `${atual} — valor da API` }];
}
