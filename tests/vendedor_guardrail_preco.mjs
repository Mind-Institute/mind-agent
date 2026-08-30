#!/usr/bin/env node
// Contrato do guardrail de preço do Vendedor Summit.
//
// Determinístico e offline: não sobe Edge Function, não chama modelo, não toca banco.
// Exercita `guardrail-preco.ts` contra uma fixture com os números REAIS que
// `public.mind_agent_kit('summit_b2b', …)` devolve hoje em produção — as quatro faixas
// de volume, as três experiências, os mesmos unitários, economias e parcelamentos.
//
// O que ele trava, em duas camadas:
//
//   1. a lista de valores permitidos sai de CAMPOS MONETÁRIOS, não de uma varredura de
//      todos os números do JSON — data, percentual, duração, quantidade, lote e id de
//      produto não autorizam cotação;
//   2. um TOTAL DE GRUPO só vale amarrado à quantidade dita na resposta E ao unitário
//      da faixa que contém aquela quantidade. Múltiplo de "algum unitário qualquer"
//      não basta: aceitava 10 × 1.482 (faixa de 5–9) para dez ingressos, que na
//      verdade custam 10 × 1.318.
//
//   node tests/vendedor_guardrail_preco.mjs

import {
  precoInventado,
  precosOficiais,
  quantidadesDitas,
  totaisPermitidos,
} from "../supabase/functions/treble-inbound-agent/guardrail-preco.ts";

// ---------------------------------------------------------------- fixtures
// Números conferidos contra o Kit de produção em 30/08/2026.
//
//            cheio    5–9 (10%)   +10 (20%)   +15 (30%)   +20 (35%)
//   Mind     1647     1482        1318        1153        1071
//   VIP      2647     2382        2118        1853        1721
//   Prime    6297     5667        5038        4408        4093
//
// Os números NÃO monetários estão aqui de propósito: 2026/16/17 (datas),
// 10/20/30/35 (percentuais), 90 (dias de gravação), 2 (horas de workshop),
// 4 (workshops), 5/10/15/20 (quantidades), 6 (lote), 3061039 (id da Eduzz).
const faixa = (aPartirDe, desconto, experiencia, cheio, comDesconto, economia, parcela) => ({
  faixa: `${aPartirDe} ingressos · ${desconto}% off`,
  experiencia,
  desconto_percentual: desconto,
  a_partir_de_ingressos: aPartirDe,
  economia_por_ingresso: economia,
  valor_cheio_por_ingresso: cheio,
  valor_por_ingresso_com_desconto: comDesconto,
  parcelamento_com_desconto: `12x de R$ ${parcela}`,
});

const KIT = {
  evento: {
    bloco: "evento",
    evento: { dias: ["2026-09-16", "2026-09-17"], nome: "Mind Summit 2026", local: "São Paulo Expo" },
    produto: { codigo: "mind-summit-2026", ativo: true, vende: true },
  },
  ofertas: {
    bloco: "ofertas",
    ofertas: [
      { nome: "Experiência Mind — Lote 6", codigo: "mind-lote-6", moeda: "BRL", valor: 1647.00,
        condicoes_pagamento: "12x de R$ 137",
        elegibilidade: { lote: 6, categoria: "mind", eduzz_product_id: "3061039" } },
      { nome: "Experiência VIP — Lote 6", codigo: "vip-lote-6", moeda: "BRL", valor: 2647.00,
        condicoes_pagamento: "12x de R$ 221",
        elegibilidade: { lote: 6, categoria: "vip", eduzz_product_id: "3061046" } },
      { nome: "Experiência Prime — Lote 6", codigo: "prime-lote-6", moeda: "BRL", valor: 6297.00,
        condicoes_pagamento: "12x de R$ 525",
        elegibilidade: { lote: 6, categoria: "prime", eduzz_product_id: "3061050" } },
    ],
  },
  inclusoes: {
    bloco: "inclusoes",
    experiencias: [{
      chave: "vip", nome: "VIP", ordem: 2,
      inclusoes: {
        grupos: [
          { grupo: "experiencias_exclusivas", itens: [
            // `valor` aqui é TEXTO de comparativo, não dinheiro.
            { item: "Workshops VIP de 2 horas", valor: "4 à sua escolha" },
            { item: "Masterclasses Prime de 90 min", valor: "—" },
          ] },
          { grupo: "gravacoes", itens: [{ item: "Gravações por 90 dias", valor: "Arenas" }] },
        ],
      },
      ofertas_vigentes: [{ codigo: "vip-lote-6", moeda: "BRL", valor: 2647.00 }],
    }],
  },
  precos_por_volume: {
    bloco: "precos_por_volume",
    precos_por_volume: [
      faixa(5, 10, "Experiência Mind — Lote 6", 1647.00, 1482, 165, 124),
      faixa(5, 10, "Experiência VIP — Lote 6", 2647.00, 2382, 265, 199),
      faixa(5, 10, "Experiência Prime — Lote 6", 6297.00, 5667, 630, 472),
      faixa(10, 20, "Experiência Mind — Lote 6", 1647.00, 1318, 329, 110),
      faixa(10, 20, "Experiência VIP — Lote 6", 2647.00, 2118, 529, 176),
      faixa(15, 30, "Experiência Mind — Lote 6", 1647.00, 1153, 494, 96),
      faixa(20, 35, "Experiência Mind — Lote 6", 1647.00, 1071, 576, 89),
    ],
  },
  regras_comerciais: {
    bloco: "regras_comerciais",
    regras: [{ chave: "desconto_por_volume", config: { tiers: [{ min: 20, off: 0.35 }, { min: 5, off: 0.1 }] } }],
  },
};

// O piso do caminho legado: `treble_agent_context`, evento + ofertas vigentes.
const LEGADO = {
  evento: { nome: "Mind Summit 2026", dias: ["2026-09-16", "2026-09-17"], local: "São Paulo Expo" },
  ofertas_vigentes: [
    { codigo: "mind-lote-6", nome: "Experiência Mind — Lote 6", valor: 1647.00, condicoes_pagamento: "12x de R$ 137" },
  ],
};

// A agenda NÃO alimenta a whitelist — está aqui só para provar que não alimenta.
const AGENDA = { sessions: [{ titulo: "Burnout e liderança", duracao_min: 45, sala: 3 }] };

const OFICIAIS_KIT = precosOficiais(KIT);
const OFICIAIS_LEGADO = precosOficiais(LEGADO);
const OFICIAIS_COM_AGENDA = precosOficiais({ ...KIT, __agenda: AGENDA });

// ------------------------------------------------------------------ casos
const CASOS = [
  // ── 1. Falsos positivos da varredura global ────────────────────────────────
  ["rejeita R$ 90 (duração de gravação/masterclass)", "Sai por R$ 90 no lote atual.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 35 (percentual do tier de +20)", "Fica R$ 35 por pessoa.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 20 (quantidade e percentual)", "São R$ 20 cada.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 2026 (ano do evento)", "O ingresso custa R$ 2026.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 6 (número do lote)", "Hoje está R$ 6.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 4 (texto de comparativo, não dinheiro)", "Cada workshop sai R$ 4.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 3.061.039 (id de produto da Eduzz)", "O valor é R$ 3.061.039.", OFICIAIS_KIT, "rejeita"],

  // ── 2. Monetários reais do Kit vigente ─────────────────────────────────────
  ["aceita R$ 1.647 (valor da oferta Mind)", "A Experiência Mind está R$ 1.647.", OFICIAIS_KIT, "aceita"],
  ["aceita R$ 137 (parcela de condicoes_pagamento)", "Dá para parcelar em 12x de R$ 137.", OFICIAIS_KIT, "aceita"],
  ["aceita R$ 1.482 (unitário da faixa de 5–9)", "No tier de 5, R$ 1.482 por pessoa.", OFICIAIS_KIT, "aceita"],
  ["aceita R$ 1.318 (unitário da faixa de +10)", "A partir de 10, R$ 1.318 por pessoa.", OFICIAIS_KIT, "aceita"],
  ["aceita R$ 124 (parcelamento com desconto)", "Fica 12x de R$ 124.", OFICIAIS_KIT, "aceita"],
  ["aceita R$ 165 (economia por ingresso, como valor unitário)", "Você economiza R$ 165 por ingresso.", OFICIAIS_KIT, "aceita"],
  ["aceita R$ 6.297 (valor do Prime)", "O Prime está R$ 6.297.", OFICIAIS_KIT, "aceita"],

  // ── 3. economia_por_ingresso NUNCA forma total ─────────────────────────────
  ["rejeita R$ 330 sem quantidade (seria 2 × economia 165)", "Sai R$ 330.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 330 com quantidade (2 pessoas × economia 165)", "Para 2 pessoas fica R$ 330.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 1.650 (10 × economia 165), mesmo com 10 pessoas ditas", "Para 10 pessoas fica R$ 1.650.", OFICIAIS_KIT, "rejeita"],

  // ── 4. Total de grupo tem de usar a FAIXA da quantidade ────────────────────
  ["aceita 5 pessoas = R$ 7.410 (5 × 1.482, faixa 5–9)", "Para 5 pessoas fica R$ 7.410.", OFICIAIS_KIT, "aceita"],
  ["REJEITA 10 pessoas = R$ 14.820 (10 × 1.482, faixa errada)", "Para 10 pessoas fica R$ 14.820.", OFICIAIS_KIT, "rejeita"],
  ["aceita 10 pessoas = R$ 13.180 (10 × 1.318, faixa +10)", "Para 10 pessoas fica R$ 13.180.", OFICIAIS_KIT, "aceita"],
  ["aceita 10 ingressos VIP = R$ 21.180 (10 × 2.118)", "São 10 ingressos VIP: R$ 21.180.", OFICIAIS_KIT, "aceita"],
  ["aceita 15 pessoas = R$ 17.295 (15 × 1.153, faixa +15)", "Para 15 pessoas fica R$ 17.295.", OFICIAIS_KIT, "aceita"],
  ["REJEITA 15 pessoas = R$ 19.770 (15 × 1.318, faixa de +10)", "Para 15 pessoas fica R$ 19.770.", OFICIAIS_KIT, "rejeita"],
  ["aceita 20 pessoas = R$ 21.420 (20 × 1.071, faixa +20)", "Para 20 pessoas, R$ 21.420.", OFICIAIS_KIT, "aceita"],

  // ── 5. Quantidade sem faixa aplicável, ou total sem quantidade ─────────────
  ["rejeita 3 pessoas = R$ 4.941 (nenhuma faixa cobre 3)", "Para 3 pessoas fica R$ 4.941.", OFICIAIS_KIT, "rejeita"],
  ["rejeita total sem quantidade dita", "O total fecha em R$ 7.410.", OFICIAIS_KIT, "rejeita"],
  ["rejeita total que não é múltiplo de nada", "Para 5 pessoas fica R$ 7.500.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 9.999", "Fecha em R$ 9.999.", OFICIAIS_KIT, "rejeita"],
  ["'12x' não é quantidade de ingresso", "São 12x de R$ 1.318 no total de R$ 15.816.", OFICIAIS_KIT, "rejeita"],

  // ── 6. Caminho legado ──────────────────────────────────────────────────────
  ["legado aceita R$ 1.647", "A Experiência Mind está R$ 1.647.", OFICIAIS_LEGADO, "aceita"],
  ["legado aceita R$ 137", "São 12x de R$ 137.", OFICIAIS_LEGADO, "aceita"],
  ["legado rejeita R$ 1.500", "Consigo fazer por R$ 1.500.", OFICIAIS_LEGADO, "rejeita"],
  ["legado rejeita total de grupo (não tem faixa)", "Para 5 pessoas fica R$ 8.235.", OFICIAIS_LEGADO, "rejeita"],

  // ── 7. Agenda não autoriza preço ───────────────────────────────────────────
  ["agenda não autoriza R$ 45", "Sai R$ 45.", OFICIAIS_COM_AGENDA, "rejeita"],
  ["agenda não autoriza R$ 3", "Sai R$ 3.", OFICIAIS_COM_AGENDA, "rejeita"],

  // ── 8. Casos de borda ──────────────────────────────────────────────────────
  ["aceita resposta sem valor em R$", "O Summit é nos dias 16 e 17 de setembro, no São Paulo Expo.", OFICIAIS_KIT, "aceita"],
  ["rejeita quando mistura oficial e inventado", "Mind por R$ 1.647 e VIP por R$ 2.000.", OFICIAIS_KIT, "rejeita"],
  ["aceita unitário e total certos na mesma frase", "Para 10 pessoas, R$ 1.318 cada, total R$ 13.180.", OFICIAIS_KIT, "aceita"],
];

// ------------------------------------------------------------------ run
let falhas = 0;
console.log("\nGuardrail de preço — contrato\n");
for (const [nome, answer, oficiais, esperado] of CASOS) {
  const achado = precoInventado(answer, oficiais);
  const obtido = achado ? "rejeita" : "aceita";
  const ok = obtido === esperado;
  if (!ok) falhas++;
  console.log(`  ${ok ? "✓" : "✗"} ${nome}` +
    (ok ? "" : `\n      esperado=${esperado} obtido=${obtido}${achado ? ` (barrou ${achado})` : ""}`));
}

// Prova direta do mecanismo de faixa, sem passar por texto de resposta.
console.log("\nFaixa aplicável por quantidade:");
for (const n of [3, 5, 9, 10, 14, 15, 20, 50]) {
  const totais = [...totaisPermitidos([n], OFICIAIS_KIT.faixas)].sort((a, b) => a - b);
  console.log(`  ${String(n).padStart(2)} ingressos → ${totais.length ? totais.join(", ") : "(nenhum total autorizado)"}`);
}

console.log("\nWhitelist montada a partir do Kit:");
console.log(`  exatos ${[...OFICIAIS_KIT.exatos].sort((a, b) => a - b).join(", ")}`);
console.log(`  faixas ${OFICIAIS_KIT.faixas.map((f) => `${f.aPartirDe}+→${f.unitario}`).join("  ")}`);
console.log(`  quantidades lidas de "Para 10 pessoas, 12x de R$ 1.318": ` +
  JSON.stringify(quantidadesDitas("Para 10 pessoas, 12x de R$ 1.318")));

console.log(`\n${CASOS.length - falhas}/${CASOS.length} casos passaram.`);
process.exit(falhas ? 1 : 0);
