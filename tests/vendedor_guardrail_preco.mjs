#!/usr/bin/env node
// Contrato do guardrail de preço do Vendedor Summit.
//
// Determinístico e offline: não sobe Edge Function, não chama modelo, não toca banco.
// Exercita `guardrail-preco.ts` contra uma fixture estruturalmente fiel ao payload que
// `public.mind_agent_kit('summit_b2b', …)` devolve hoje em produção — mesmos campos,
// mesmos tipos, mesmos números.
//
// O que ele trava é a correção que motivou o módulo: a lista de preços permitidos sai
// de CAMPOS MONETÁRIOS, não de uma varredura de todos os números do JSON. Datas,
// percentuais de desconto, durações, quantidades de ingresso, número de lote e IDs de
// produto NÃO autorizam uma cotação.
//
//   node tests/vendedor_guardrail_preco.mjs

import { precoInventado, precosOficiais } from "../supabase/functions/treble-inbound-agent/guardrail-preco.ts";

// ---------------------------------------------------------------- fixtures
// Recorte do `structured` real de summit_b2b. Os números não monetários estão aqui de
// propósito: 2026/16/17 (datas), 10/20/30/35/40 (percentuais), 90 (dias de gravação),
// 2 (horas de workshop), 4 (workshops), 5/10/15/20 (quantidades), 6 (lote),
// 3061039 (id da Eduzz).
const KIT = {
  evento: {
    bloco: "evento",
    evento: {
      dias: ["2026-09-16", "2026-09-17"],
      nome: "Mind Summit 2026",
      slug: "mind-summit-2026",
      ativo: true,
      local: "São Paulo Expo",
    },
    produto: { codigo: "mind-summit-2026", ativo: true, vende: true },
  },
  ofertas: {
    bloco: "ofertas",
    ofertas: [
      {
        nome: "Experiência Mind — Lote 6", codigo: "mind-lote-6", moeda: "BRL",
        valor: 1647.00, condicoes_pagamento: "12x de R$ 137",
        elegibilidade: { lote: 6, categoria: "mind", eduzz_product_id: "3061039" },
      },
      {
        nome: "Experiência VIP — Lote 6", codigo: "vip-lote-6", moeda: "BRL",
        valor: 2647.00, condicoes_pagamento: "12x de R$ 221",
        elegibilidade: { lote: 6, categoria: "vip", eduzz_product_id: "3061046" },
      },
      {
        nome: "Experiência Prime — Lote 6", codigo: "prime-lote-6", moeda: "BRL",
        valor: 6297.00, condicoes_pagamento: "12x de R$ 525",
        elegibilidade: { lote: 6, categoria: "prime", eduzz_product_id: "3061050" },
      },
    ],
  },
  inclusoes: {
    bloco: "inclusoes",
    experiencias: [
      {
        chave: "vip", nome: "VIP", ordem: 2,
        inclusoes: {
          grupos: [
            {
              grupo: "experiencias_exclusivas",
              itens: [
                // `valor` aqui é TEXTO de comparativo, não dinheiro.
                { item: "Workshops VIP de 2 horas", valor: "4 à sua escolha" },
                { item: "Masterclasses Prime de 90 min", valor: "—" },
                { item: "Prime Lounge", valor: "—" },
              ],
            },
            { grupo: "gravacoes", itens: [{ item: "Gravações por 90 dias", valor: "Arenas" }] },
          ],
        },
        ofertas_vigentes: [{ codigo: "vip-lote-6", moeda: "BRL", valor: 2647.00 }],
      },
    ],
  },
  precos_por_volume: {
    bloco: "precos_por_volume",
    precos_por_volume: [
      {
        faixa: "5–9 ingressos · 10% off", experiencia: "Experiência Mind — Lote 6",
        desconto_percentual: 10, a_partir_de_ingressos: 5, economia_por_ingresso: 165,
        valor_cheio_por_ingresso: 1647.00, valor_por_ingresso_com_desconto: 1482,
        parcelamento_com_desconto: "12x de R$ 124",
      },
      {
        faixa: "+20 ingressos · 35% off", experiencia: "Experiência Mind — Lote 6",
        desconto_percentual: 35, a_partir_de_ingressos: 20, economia_por_ingresso: 576,
        valor_cheio_por_ingresso: 1647.00, valor_por_ingresso_com_desconto: 1071,
        parcelamento_com_desconto: "12x de R$ 89",
      },
    ],
  },
  regras_comerciais: {
    bloco: "regras_comerciais",
    regras: [{
      chave: "desconto_por_volume",
      config: { tiers: [{ min: 20, off: 0.35 }, { min: 5, off: 0.1 }, { min: 0, off: 0 }] },
    }],
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

// ------------------------------------------------------------------ casos
const OFICIAIS_KIT = precosOficiais(KIT);
const OFICIAIS_LEGADO = precosOficiais(LEGADO);

const CASOS = [
  // 1. Falsos positivos que a varredura global deixava passar. Cada número existe no
  //    payload — como percentual, duração ou quantidade —, e nenhum é dinheiro.
  ["rejeita R$ 90 (duração de masterclass/gravação)", "Sai por R$ 90 no lote atual.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 35 (percentual de desconto)", "Fica R$ 35 por pessoa.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 20 (quantidade de ingressos / percentual)", "São R$ 20 cada.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 2026 (ano do evento)", "O ingresso custa R$ 2026.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 6 (número do lote)", "Hoje está R$ 6.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 4 (texto de comparativo, não dinheiro)", "Cada workshop sai R$ 4.", OFICIAIS_KIT, "rejeita"],
  ["rejeita R$ 3.061.039 (id de produto da Eduzz)", "O valor é R$ 3.061.039.", OFICIAIS_KIT, "rejeita"],

  // 2. Os valores monetários que estão de fato no Kit vigente.
  ["aceita R$ 1.647 (valor da oferta Mind)", "A Experiência Mind está R$ 1.647.", OFICIAIS_KIT, "aceita"],
  ["aceita R$ 137 (parcela de condicoes_pagamento)", "Dá para parcelar em 12x de R$ 137.", OFICIAIS_KIT, "aceita"],
  ["aceita R$ 1.482 (valor por ingresso com desconto)", "No tier de 5, R$ 1.482 por pessoa.", OFICIAIS_KIT, "aceita"],
  ["aceita R$ 124 (parcelamento com desconto)", "Fica 12x de R$ 124.", OFICIAIS_KIT, "aceita"],
  ["aceita R$ 165 (economia por ingresso)", "Você economiza R$ 165 por ingresso.", OFICIAIS_KIT, "aceita"],
  ["aceita R$ 6.297 (valor do Prime)", "O Prime está R$ 6.297.", OFICIAIS_KIT, "aceita"],

  // 3. Total de grupo como múltiplo inteiro de um unitário oficial.
  ["aceita total de 5 × 1.482 = R$ 7.410", "Para 5 pessoas fica R$ 7.410 no total.", OFICIAIS_KIT, "aceita"],
  ["aceita total de 20 × 1.071 = R$ 21.420", "Para 20 pessoas, R$ 21.420.", OFICIAIS_KIT, "aceita"],

  // 4. Total que não é múltiplo de nenhum valor monetário oficial.
  ["rejeita total R$ 7.500 (não é múltiplo de unitário oficial)", "Para 5 pessoas fica R$ 7.500.", OFICIAIS_KIT, "rejeita"],
  ["rejeita total R$ 9.999", "Fecha em R$ 9.999.", OFICIAIS_KIT, "rejeita"],

  // 5. O caminho legado continua cotando o que sempre cotou.
  ["legado aceita R$ 1.647", "A Experiência Mind está R$ 1.647.", OFICIAIS_LEGADO, "aceita"],
  ["legado aceita R$ 137", "São 12x de R$ 137.", OFICIAIS_LEGADO, "aceita"],
  ["legado rejeita R$ 1.500", "Consigo fazer por R$ 1.500.", OFICIAIS_LEGADO, "rejeita"],

  // 6. Resposta sem preço nenhum nunca é barrada.
  ["aceita resposta sem valor em R$", "O Summit é nos dias 16 e 17 de setembro, no São Paulo Expo.", OFICIAIS_KIT, "aceita"],

  // 7. O primeiro preço inventado derruba o turno mesmo vindo depois de um oficial.
  ["rejeita quando mistura oficial e inventado", "Mind por R$ 1.647 e VIP por R$ 2.000.", OFICIAIS_KIT, "rejeita"],
];

// A agenda não pode autorizar preço: 45 e 3 existem lá, e só lá.
const OFICIAIS_COM_AGENDA = precosOficiais({ ...KIT, __agenda: AGENDA });
CASOS.push(
  ["agenda não autoriza R$ 45", "Sai R$ 45.", OFICIAIS_COM_AGENDA, "rejeita"],
  ["agenda não autoriza R$ 3", "Sai R$ 3.", OFICIAIS_COM_AGENDA, "rejeita"],
);

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

console.log(`\nWhitelist montada a partir do Kit:`);
console.log(`  exatos    ${[...OFICIAIS_KIT.exatos].sort((a, b) => a - b).join(", ")}`);
console.log(`  unitários ${[...OFICIAIS_KIT.unitarios].sort((a, b) => a - b).join(", ")}`);

console.log(`\n${CASOS.length - falhas}/${CASOS.length} casos passaram.`);
process.exit(falhas ? 1 : 0);
