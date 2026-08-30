// GUARDRAIL DE PREÇO — quais valores em R$ o agente pode dizer.
//
// POR QUE ISTO SAIU DE DENTRO DO index.ts
//
// A versão anterior montava a lista de preços permitidos assim:
//
//     JSON.stringify({ dadosOficiais, agendaSegura }).match(/\d+(?:\.\d+)?/g)
//
// Qualquer número em qualquer lugar do JSON virava preço oficial. Isso já era
// frouxo com o `treble_agent_context`; com o Kit ficou materialmente pior,
// porque o payload passou a carregar datas (2026, 16, 17), percentuais de
// desconto (10, 20, 30, 35, 40), quantidades (4 workshops, 90 dias, 5/10/15/20
// ingressos), número de lote e IDs de produto da Eduzz. Uma resposta inventada
// com `R$ 90`, `R$ 35` ou `R$ 20` passava pelo guardrail só porque esses
// números existem em campos que não têm nada de monetário.
//
// A lista agora vem de CAMPOS, não de uma varredura. Só é preço oficial:
//
//   1. o valor de um campo monetário autoritativo, quando ele é um NÚMERO —
//      `inclusoes` usa a mesma chave `valor` para texto de comparativo ("✓",
//      "4 à sua escolha", "Área Mind"), e texto nunca vira dinheiro;
//   2. um valor em R$ escrito dentro de um campo de pagamento
//      ("12x de R$ 137" → 137). O `12` não entra: parcela é dinheiro, número
//      de parcelas não é.
//
// A agenda (`mindagent_chat_search`) ficou de fora de propósito. Ela não é
// fonte autoritativa de preço — estruturado autoritativo primeiro —, e um
// número solto num texto de sessão ou FAQ não deve autorizar uma cotação. O
// custo é conhecido: se um dia a resposta precisar citar um preço que só
// existe em texto de conhecimento, o guardrail derruba o turno para handoff.
// Errar para o lado de chamar gente é o lado certo de errar aqui.
//
// Este módulo não tem import: é função pura sobre o payload, para poder ser
// testado sem subir a Edge Function (`tests/vendedor_guardrail_preco.mjs`).

// Campos cujo valor numérico É dinheiro, na Intelligence comercial do Summit.
const CAMPOS_MONETARIOS = [
  "valor",
  "valor_cheio_por_ingresso",
  "valor_por_ingresso_com_desconto",
  "economia_por_ingresso",
];

// Campos de texto onde o dinheiro aparece escrito em R$.
const CAMPOS_DE_PAGAMENTO = [
  "condicoes_pagamento",
  "parcelamento_com_desconto",
];

// Um total de grupo é aceito como múltiplo inteiro de um unitário oficial.
// A faixa existe para não transformar qualquer número pequeno em base de
// multiplicação, e o teto para não aceitar uma conta absurda.
const UNITARIO_MIN = 100;
const UNITARIO_MAX = 100000;
const MULTIPLO_MIN = 2;
const MULTIPLO_MAX = 60;

const R$_NO_TEXTO = /R\$\s?([\d.]+)/g;

export type PrecosOficiais = {
  /** Valores que podem ser ditos exatamente como estão. */
  exatos: Set<number>;
  /** Unitários que podem ser multiplicados para formar um total de grupo. */
  unitarios: number[];
};

/** "R$ 1.647" → 1647. Ponto é separador de milhar em pt-BR, nunca decimal. */
function comoNumero(bruto: string): number {
  return Number(bruto.replace(/\./g, ""));
}

function valoresEmReais(texto: string): number[] {
  const saida: number[] = [];
  for (const achado of texto.matchAll(R$_NO_TEXTO)) {
    const n = comoNumero(achado[1]);
    if (Number.isFinite(n) && n > 0) saida.push(Math.round(n));
  }
  return saida;
}

/**
 * Percorre o payload que foi realmente enviado ao modelo e devolve só o que
 * nele é dinheiro. Nenhuma varredura global: campo desconhecido não vira preço.
 */
export function precosOficiais(dadosOficiais: unknown): PrecosOficiais {
  const exatos = new Set<number>();
  const unitarios: number[] = [];

  const anda = (no: unknown): void => {
    if (Array.isArray(no)) {
      no.forEach(anda);
      return;
    }
    if (!no || typeof no !== "object") return;

    for (const [chave, valor] of Object.entries(no as Record<string, unknown>)) {
      // Campo monetário só conta quando o valor é NÚMERO. `inclusoes` reusa a
      // chave `valor` para texto de comparativo, e "4 à sua escolha" não é R$ 4.
      if (CAMPOS_MONETARIOS.includes(chave) && typeof valor === "number" && Number.isFinite(valor)) {
        const n = Math.round(valor);
        exatos.add(n);
        if (n >= UNITARIO_MIN && n <= UNITARIO_MAX) unitarios.push(n);
        continue;
      }

      if (CAMPOS_DE_PAGAMENTO.includes(chave) && typeof valor === "string") {
        for (const n of valoresEmReais(valor)) exatos.add(n);
        continue;
      }

      anda(valor);
    }
  };

  anda(dadosOficiais);
  return { exatos, unitarios };
}

/** Total de grupo: múltiplo inteiro de um unitário oficial, dentro da faixa. */
function ehMultiploDeOficial(valor: number, unitarios: number[]): boolean {
  return unitarios.some((u) =>
    u > 0 && valor % u === 0 &&
    valor / u >= MULTIPLO_MIN && valor / u <= MULTIPLO_MAX
  );
}

export function precoEhOficial(valor: number, oficiais: PrecosOficiais): boolean {
  if (!Number.isFinite(valor)) return false;
  return oficiais.exatos.has(valor) || ehMultiploDeOficial(valor, oficiais.unitarios);
}

/**
 * O primeiro valor em R$ da resposta que NÃO é oficial, como o agente escreveu
 * — ou `null` quando a resposta só cita dinheiro que veio dos dados.
 */
export function precoInventado(answer: string, oficiais: PrecosOficiais): string | null {
  for (const achado of answer.matchAll(R$_NO_TEXTO)) {
    if (!precoEhOficial(comoNumero(achado[1]), oficiais)) return achado[0];
  }
  return null;
}
