// GUARDRAIL DE PREÇO — quais valores em R$ o agente pode dizer.
//
// POR QUE ISTO SAIU DE DENTRO DO index.ts
//
// A primeira versão montava a lista de preços permitidos assim:
//
//     JSON.stringify({ dadosOficiais, agendaSegura }).match(/\d+(?:\.\d+)?/g)
//
// Qualquer número em qualquer lugar do JSON virava preço oficial. Já era frouxo com o
// `treble_agent_context`; com o Kit ficou materialmente pior, porque o payload passou a
// carregar datas (2026, 16, 17), percentuais de desconto (10, 20, 30, 35, 40),
// quantidades (4 workshops, 90 dias, 5/10/15/20 ingressos), número de lote e IDs de
// produto da Eduzz. `R$ 90`, `R$ 35` e `R$ 20` passavam só porque esses números existem
// em campos que não têm nada de monetário.
//
// A lista vem de CAMPOS, não de uma varredura. Só é preço oficial:
//
//   1. o valor de um campo monetário autoritativo, quando ele é um NÚMERO —
//      `inclusoes` usa a mesma chave `valor` para texto de comparativo ("✓",
//      "4 à sua escolha", "Área Mind"), e texto nunca vira dinheiro;
//   2. um valor em R$ escrito dentro de um campo de pagamento ("12x de R$ 137" → 137).
//      O `12` não entra: parcela é dinheiro, número de parcelas não.
//
// ------------------------------------------------------------------------------
// TOTAL DE GRUPO — POR QUE "MÚLTIPLO DE ALGUM UNITÁRIO" NÃO BASTA
//
// A segunda versão aceitava qualquer valor que fosse múltiplo inteiro de qualquer
// unitário monetário. Isso deixava passar duas coisas erradas:
//
//   • `R$ 330` como "2 × 165", onde 165 é `economia_por_ingresso` — economia não é
//     preço de ingresso, e um total nunca se forma a partir dela;
//   • `Para 10 pessoas fica R$ 14.820`, que é 10 × 1.482 — o unitário da faixa de
//     5–9. Dez ingressos usam a faixa de 20%, cujo unitário é 1.318, e o total certo
//     é 13.180. O guardrail aceitava um total calculado na FAIXA ERRADA.
//
// Um total só é aceito quando está amarrado às duas coisas ao mesmo tempo:
//
//     quantidade dita na própria resposta  ×  unitário da faixa que contém essa
//                                             quantidade (`valor_por_ingresso_com_desconto`)
//
// Sem quantidade explícita na resposta, ou com uma quantidade que nenhuma faixa
// cobre, o total é barrado. Errar para o lado de chamar gente é o lado certo aqui.
//
// A agenda (`mindagent_chat_search`) ficou de fora de propósito: não é fonte
// autoritativa de preço, e um número solto num texto de sessão ou FAQ não deve
// autorizar uma cotação.
//
// Este módulo não tem import: é função pura sobre o payload, para poder ser testado
// sem subir a Edge Function (`tests/vendedor_guardrail_preco.mjs`).

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

const R$_NO_TEXTO = /R\$\s?([\d.]+)/g;

// Quantidade de ingressos dita na própria resposta. Só conta número colado num
// substantivo de gente/ingresso — "12x" e "90 dias" não são quantidade de compra.
const QUANTIDADE_NA_RESPOSTA =
  /(\d{1,4})\s*(pessoas?|ingressos?|participantes?|colaboradores?|convites?|vagas?|lugares?)/gi;

/** Uma linha de `precos_por_volume`: a partir de quantos ingressos, e por quanto cada. */
export type FaixaVolume = { aPartirDe: number; unitario: number };

export type PrecosOficiais = {
  /** Valores que podem ser ditos exatamente como estão. */
  exatos: Set<number>;
  /** Faixas de volume, únicas fontes de unitário para formar um total de grupo. */
  faixas: FaixaVolume[];
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
 * Percorre o payload que foi realmente enviado ao modelo e devolve só o que nele é
 * dinheiro. Nenhuma varredura global: campo desconhecido não vira preço.
 *
 * As faixas são reconhecidas pela FORMA da linha — ter `a_partir_de_ingressos` e
 * `valor_por_ingresso_com_desconto` juntos —, não pelo caminho dentro do JSON. O
 * guardrail não precisa saber que o bloco se chama `precos_por_volume`.
 */
export function precosOficiais(dadosOficiais: unknown): PrecosOficiais {
  const exatos = new Set<number>();
  const faixas: FaixaVolume[] = [];

  const anda = (no: unknown): void => {
    if (Array.isArray(no)) {
      no.forEach(anda);
      return;
    }
    if (!no || typeof no !== "object") return;

    const obj = no as Record<string, unknown>;

    const aPartirDe = obj["a_partir_de_ingressos"];
    const unitario = obj["valor_por_ingresso_com_desconto"];
    if (typeof aPartirDe === "number" && Number.isFinite(aPartirDe) && aPartirDe > 0 &&
        typeof unitario === "number" && Number.isFinite(unitario) && unitario > 0) {
      faixas.push({ aPartirDe: Math.round(aPartirDe), unitario: Math.round(unitario) });
    }

    for (const [chave, valor] of Object.entries(obj)) {
      // Campo monetário só conta quando o valor é NÚMERO. `inclusoes` reusa a chave
      // `valor` para texto de comparativo, e "4 à sua escolha" não é R$ 4.
      if (CAMPOS_MONETARIOS.includes(chave) && typeof valor === "number" && Number.isFinite(valor)) {
        exatos.add(Math.round(valor));
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
  return { exatos, faixas };
}

/** As quantidades de ingresso que a própria resposta afirma. */
export function quantidadesDitas(answer: string): number[] {
  const saida = new Set<number>();
  for (const achado of answer.matchAll(QUANTIDADE_NA_RESPOSTA)) {
    const n = Number(achado[1]);
    if (Number.isFinite(n) && n > 0) saida.add(n);
  }
  return [...saida];
}

/**
 * Os totais que essas quantidades autorizam: para cada quantidade, a faixa que a
 * contém — a de maior `aPartirDe` que ainda cabe — e os unitários dessa faixa (um por
 * experiência). Quantidade que nenhuma faixa cobre não autoriza total nenhum.
 */
export function totaisPermitidos(quantidades: number[], faixas: FaixaVolume[]): Set<number> {
  const totais = new Set<number>();
  for (const n of quantidades) {
    const cabem = faixas.filter((f) => f.aPartirDe <= n);
    if (cabem.length === 0) continue;
    const degrau = Math.max(...cabem.map((f) => f.aPartirDe));
    for (const f of faixas) {
      if (f.aPartirDe === degrau) totais.add(n * f.unitario);
    }
  }
  return totais;
}

export function precoEhOficial(
  valor: number,
  oficiais: PrecosOficiais,
  totais: Set<number>,
): boolean {
  if (!Number.isFinite(valor)) return false;
  return oficiais.exatos.has(valor) || totais.has(valor);
}

/**
 * O primeiro valor em R$ da resposta que NÃO é oficial, como o agente escreveu — ou
 * `null` quando a resposta só cita dinheiro que veio dos dados.
 */
export function precoInventado(answer: string, oficiais: PrecosOficiais): string | null {
  const totais = totaisPermitidos(quantidadesDitas(answer), oficiais.faixas);
  for (const achado of answer.matchAll(R$_NO_TEXTO)) {
    if (!precoEhOficial(comoNumero(achado[1]), oficiais, totais)) return achado[0];
  }
  return null;
}
