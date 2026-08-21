import {
  ROTULO_FORMATO_SESSAO,
  ROTULO_TIPO_ESPACO,
  ROTULO_TIPO_SESSAO,
  type FormatoSessao,
  type TipoEspaco,
  type TipoSessao,
} from '@/contracts';

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

function resolver<T extends string>(mapa: Record<T, string>, valor: string): Rotulo {
  const conhecido = Object.prototype.hasOwnProperty.call(mapa, valor);
  return conhecido
    ? { texto: mapa[valor as T], conhecido: true }
    : { texto: valor || '—', conhecido: false };
}

export function rotuloTipoSessao(tipo: string): Rotulo {
  return resolver<TipoSessao>(ROTULO_TIPO_SESSAO, tipo);
}

export function rotuloFormatoSessao(formato: string): Rotulo {
  return resolver<FormatoSessao>(ROTULO_FORMATO_SESSAO, formato);
}

export function rotuloTipoEspaco(tipo: string): Rotulo {
  return resolver<TipoEspaco>(ROTULO_TIPO_ESPACO, tipo);
}

/** Trilha de ingresso — mesma regra. */
export function rotuloTrilha(trilha: string): Rotulo {
  const mapa: Record<string, string> = { mind: 'Mind', vip: 'VIP', prime: 'Prime' };
  return resolver(mapa, trilha);
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
