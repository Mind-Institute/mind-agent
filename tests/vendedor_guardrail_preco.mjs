#!/usr/bin/env node
// Contrato do guardrail de preço do Vendedor Summit.
//
// Determinístico e offline: não sobe Edge Function, não chama modelo, não toca banco.
//
// A fixture espelha o Kit VIVO: as 12 linhas de `precos_por_volume` que
// `public.mind_precos_por_volume()` devolve hoje em produção — Mind/VIP/Prime nas
// quatro faixas — mais as 3 ofertas, as inclusões e as regras comerciais. Conferido
// contra o banco em 30/08/2026:
//
//              cheio    5+ (10%)   10+ (20%)   15+ (30%)   20+ (35%)
//     Mind     1647     1482       1318        1153        1071
//     VIP      2647     2382       2118        1853        1721
//     Prime    6297     5667       5038        4408        4093
//
// O que ele trava, em três camadas:
//
//   1. valor monetário sai de CAMPO, não de varredura — data, percentual, duração,
//      quantidade, lote e id de produto não autorizam cotação;
//   2. um TOTAL exige quantidade dita E o unitário da faixa que contém essa quantidade;
//   3. o PAPEL do valor tem de bater: 165 é economia, 137 é parcela, e nenhum dos dois é
//      preço do ingresso — mesmo existindo no payload.
//
//   node tests/vendedor_guardrail_preco.mjs

import {
  afirmacoes,
  faixaDe,
  precoInventado,
  precosOficiais,
} from "../supabase/functions/treble-inbound-agent/guardrail-preco.ts";

// ---------------------------------------------------------------- fixtures
const TIERS = [
  // aPartirDe, pct, experiência, cheio, unitário, economia, parcela
  [5, 10, "Mind", 1647.0, 1482, 165, 124], [5, 10, "VIP", 2647.0, 2382, 265, 199], [5, 10, "Prime", 6297.0, 5667, 630, 472],
  [10, 20, "Mind", 1647.0, 1318, 329, 110], [10, 20, "VIP", 2647.0, 2118, 529, 176], [10, 20, "Prime", 6297.0, 5038, 1259, 420],
  [15, 30, "Mind", 1647.0, 1153, 494, 96], [15, 30, "VIP", 2647.0, 1853, 794, 154], [15, 30, "Prime", 6297.0, 4408, 1889, 367],
  [20, 35, "Mind", 1647.0, 1071, 576, 89], [20, 35, "VIP", 2647.0, 1721, 926, 143], [20, 35, "Prime", 6297.0, 4093, 2204, 341],
];

const KIT = {
  evento: {
    bloco: "evento",
    evento: { dias: ["2026-09-16", "2026-09-17"], nome: "Mind Summit 2026", local: "São Paulo Expo" },
    produto: { codigo: "mind-summit-2026", ativo: true, vende: true },
  },
  ofertas: {
    bloco: "ofertas",
    ofertas: [
      { nome: "Experiência Mind — Lote 6", codigo: "mind-lote-6", moeda: "BRL", valor: 1647.0, categoria: "mind",
        condicoes_pagamento: "12x de R$ 137",
        elegibilidade: { lote: 6, categoria: "mind", eduzz_product_id: "3061039" } },
      { nome: "Experiência VIP — Lote 6", codigo: "vip-lote-6", moeda: "BRL", valor: 2647.0, categoria: "vip",
        condicoes_pagamento: "12x de R$ 221",
        elegibilidade: { lote: 6, categoria: "vip", eduzz_product_id: "3061046" } },
      { nome: "Experiência Prime — Lote 6", codigo: "prime-lote-6", moeda: "BRL", valor: 6297.0, categoria: "prime",
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
      ofertas_vigentes: [{ codigo: "vip-lote-6", moeda: "BRL", valor: 2647.0 }],
    }],
  },
  precos_por_volume: {
    bloco: "precos_por_volume",
    precos_por_volume: TIERS.map(([a, pct, exp, cheio, unit, econ, parc]) => ({
      faixa: `${a} ingressos · ${pct}% off`,
      experiencia: `Experiência ${exp} — Lote 6`,
      desconto_percentual: pct,
      a_partir_de_ingressos: a,
      economia_por_ingresso: econ,
      valor_cheio_por_ingresso: cheio,
      valor_por_ingresso_com_desconto: unit,
      parcelamento_com_desconto: `12x de R$ ${parc}`,
    })),
  },
  regras_comerciais: {
    bloco: "regras_comerciais",
    regras: [{ chave: "desconto_por_volume", config: { tiers: [{ min: 20, off: 0.35 }, { min: 5, off: 0.1 }] } }],
  },
};

// O piso do caminho legado: `treble_agent_context`, evento + ofertas vigentes, sem
// categoria e sem faixas.
const LEGADO = {
  evento: { nome: "Mind Summit 2026", dias: ["2026-09-16", "2026-09-17"], local: "São Paulo Expo" },
  ofertas_vigentes: [
    { codigo: "mind-lote-6", nome: "Experiência Mind — Lote 6", valor: 1647.0, condicoes_pagamento: "12x de R$ 137" },
  ],
};

// A agenda NÃO alimenta a whitelist — está aqui só para provar que não alimenta.
const AGENDA = { sessions: [{ titulo: "Burnout e liderança", duracao_min: 45, sala: 3 }] };

const KIT_OF = precosOficiais(KIT);
const LEGADO_OF = precosOficiais(LEGADO);
const COM_AGENDA_OF = precosOficiais({ ...KIT, __agenda: AGENDA });

// ------------------------------------------------------------------ casos
const CASOS = [
  // ── 1. Falsos positivos da varredura global ────────────────────────────────
  ["rejeita R$ 90 (duração de gravação/masterclass)", "Sai por R$ 90 no lote atual.", KIT_OF, "rejeita"],
  ["rejeita R$ 35 (percentual do tier de +20)", "Fica R$ 35.", KIT_OF, "rejeita"],
  ["rejeita R$ 20 (quantidade e percentual)", "Custa R$ 20.", KIT_OF, "rejeita"],
  ["rejeita R$ 2026 (ano do evento)", "O ingresso custa R$ 2026.", KIT_OF, "rejeita"],
  ["rejeita R$ 6 (número do lote)", "Hoje está R$ 6.", KIT_OF, "rejeita"],
  ["rejeita R$ 4 (texto de comparativo, não dinheiro)", "Cada workshop sai R$ 4.", KIT_OF, "rejeita"],
  ["rejeita R$ 3.061.039 (id de produto da Eduzz)", "O valor é R$ 3.061.039.", KIT_OF, "rejeita"],

  // ── 2. PAPEL ERRADO — valor existe no payload, mas não é aquilo ────────────
  ["REJEITA 'O Mind custa R$ 165' (165 é economia)", "O Mind custa R$ 165.", KIT_OF, "rejeita"],
  ["REJEITA 'O Mind custa R$ 137' (137 é parcela)", "O Mind custa R$ 137.", KIT_OF, "rejeita"],
  ["rejeita 'O VIP sai por R$ 265' (265 é economia do VIP)", "O VIP sai por R$ 265.", KIT_OF, "rejeita"],
  ["rejeita 'o Prime está R$ 472' (472 é parcela do Prime)", "O Prime está R$ 472.", KIT_OF, "rejeita"],
  ["rejeita 'o ingresso custa R$ 1.482' sem quantidade (é unitário de faixa)", "O ingresso custa R$ 1.482.", KIT_OF, "rejeita"],
  ["aceita 'você economiza R$ 165 por ingresso' (papel certo)", "Você economiza R$ 165 por ingresso.", KIT_OF, "aceita"],
  ["aceita '12x de R$ 137' (parcela da oferta base)", "Dá para parcelar em 12x de R$ 137.", KIT_OF, "aceita"],
  ["aceita 'o Mind está R$ 1.647' (preço de oferta)", "O Mind está R$ 1.647.", KIT_OF, "aceita"],
  ["aceita 'o Prime está R$ 6.297'", "O Prime está R$ 6.297.", KIT_OF, "aceita"],

  // ── 3. EXPERIÊNCIA — valor de outra experiência não serve ──────────────────
  ["rejeita 'o Mind custa R$ 2.647' (preço do VIP)", "O Mind custa R$ 2.647.", KIT_OF, "rejeita"],
  ["rejeita 'o VIP está R$ 6.297' (preço do Prime)", "O VIP está R$ 6.297.", KIT_OF, "rejeita"],
  ["rejeita 'para 10 pessoas o Mind fica R$ 2.118 por pessoa' (unitário do VIP)", "Para 10 pessoas o Mind fica R$ 2.118 por pessoa.", KIT_OF, "rejeita"],
  ["aceita 'para 10 pessoas o VIP fica R$ 2.118 por pessoa'", "Para 10 pessoas o VIP fica R$ 2.118 por pessoa.", KIT_OF, "aceita"],

  // ── 4. FAIXA — unitário e total têm de ser os do tier da quantidade ────────
  ["REJEITA 'para 10 pessoas, R$ 1.482 por pessoa' (unitário de 5–9)", "Para 10 pessoas, fica R$ 1.482 por pessoa.", KIT_OF, "rejeita"],
  ["aceita 'para 10 pessoas, R$ 1.318 por pessoa'", "Para 10 pessoas, fica R$ 1.318 por pessoa.", KIT_OF, "aceita"],
  ["aceita 'para 5 pessoas, R$ 1.482 por pessoa'", "Para 5 pessoas, fica R$ 1.482 por pessoa.", KIT_OF, "aceita"],
  ["aceita 'a partir de 15 ingressos, R$ 1.153 cada'", "A partir de 15 ingressos, R$ 1.153 cada.", KIT_OF, "aceita"],
  ["rejeita 'a partir de 15 ingressos, R$ 1.318 cada' (unitário de +10)", "A partir de 15 ingressos, R$ 1.318 cada.", KIT_OF, "rejeita"],
  ["aceita 'para 20 pessoas, Prime a R$ 4.093 cada'", "Para 20 pessoas, o Prime sai a R$ 4.093 cada.", KIT_OF, "aceita"],

  // ── 5. TOTAL = quantidade × unitário do tier aplicável ─────────────────────
  ["aceita 5 pessoas = R$ 7.410 (5 × 1.482)", "Para 5 pessoas fica R$ 7.410.", KIT_OF, "aceita"],
  ["REJEITA 10 pessoas = R$ 14.820 (10 × 1.482, faixa errada)", "Para 10 pessoas fica R$ 14.820.", KIT_OF, "rejeita"],
  ["aceita 10 pessoas = R$ 13.180 (10 × 1.318)", "Para 10 pessoas fica R$ 13.180.", KIT_OF, "aceita"],
  ["aceita 20 ingressos Prime = R$ 81.860 (20 × 4.093)", "Para 20 ingressos, o Prime fecha em R$ 81.860.", KIT_OF, "aceita"],
  ["rejeita 15 pessoas = R$ 19.770 (15 × 1.318, faixa de +10)", "Para 15 pessoas fica R$ 19.770.", KIT_OF, "rejeita"],
  ["rejeita 3 pessoas = R$ 4.941 (nenhuma faixa cobre 3)", "Para 3 pessoas fica R$ 4.941.", KIT_OF, "rejeita"],
  ["rejeita R$ 330 (2 × economia 165), com quantidade", "Para 2 pessoas fica R$ 330.", KIT_OF, "rejeita"],
  ["rejeita R$ 1.650 (10 × economia 165) com 10 pessoas", "Para 10 pessoas fica R$ 1.650.", KIT_OF, "rejeita"],
  ["rejeita total que não é múltiplo de nada", "Para 5 pessoas fica R$ 7.500.", KIT_OF, "rejeita"],

  // ── 6. PERCENTUAL do tier ──────────────────────────────────────────────────
  ["REJEITA 'para 10 pessoas, o desconto é 10%' (o tier de 10 é 20%)", "Para 10 pessoas, o desconto é 10%.", KIT_OF, "rejeita"],
  ["aceita 'para 10 pessoas, o desconto é 20%'", "Para 10 pessoas, o desconto é 20%.", KIT_OF, "aceita"],
  ["aceita 'a partir de 20 ingressos são 35%'", "A partir de 20 ingressos são 35%.", KIT_OF, "aceita"],
  ["rejeita 'a partir de 20 ingressos são 50%'", "A partir de 20 ingressos são 50%.", KIT_OF, "rejeita"],
  ["aceita '30%' sem quantidade (existe como tier)", "Temos condições de até 30% para grupos.", KIT_OF, "aceita"],
  ["rejeita '45%' sem quantidade (não existe tier)", "Temos condições de até 45% para grupos.", KIT_OF, "rejeita"],
  ["legado rejeita qualquer percentual (payload sem tiers)", "Temos 10% de desconto.", LEGADO_OF, "rejeita"],

  // ── 7. Centavos não podem ser ignorados ────────────────────────────────────
  ["REJEITA R$ 1.318,99 (centavos inventados)", "Para 10 pessoas, R$ 1.318,99 por pessoa.", KIT_OF, "rejeita"],
  ["rejeita R$ 1.647,50", "O Mind está R$ 1.647,50.", KIT_OF, "rejeita"],
  ["aceita R$ 1.647,00", "O Mind está R$ 1.647,00.", KIT_OF, "aceita"],

  // ── 8. Caminho legado ──────────────────────────────────────────────────────
  ["legado aceita R$ 1.647", "A Experiência Mind está R$ 1.647.", LEGADO_OF, "aceita"],
  ["legado aceita 12x de R$ 137", "São 12x de R$ 137.", LEGADO_OF, "aceita"],
  ["legado rejeita R$ 1.500", "Consigo fazer por R$ 1.500.", LEGADO_OF, "rejeita"],
  ["legado rejeita total de grupo (não tem faixa)", "Para 5 pessoas fica R$ 8.235.", LEGADO_OF, "rejeita"],
  ["legado rejeita R$ 137 como preço", "O Mind custa R$ 137.", LEGADO_OF, "rejeita"],

  // ── 9. Agenda não autoriza preço ───────────────────────────────────────────
  ["agenda não autoriza R$ 45", "Sai R$ 45.", COM_AGENDA_OF, "rejeita"],
  ["agenda não autoriza R$ 3", "Sai R$ 3.", COM_AGENDA_OF, "rejeita"],

  // ── 10. Bordas ─────────────────────────────────────────────────────────────
  ["aceita resposta sem valor em R$", "O Summit é nos dias 16 e 17 de setembro, no São Paulo Expo.", KIT_OF, "aceita"],
  ["rejeita quando mistura oficial e inventado", "Mind por R$ 1.647 e VIP por R$ 2.000.", KIT_OF, "rejeita"],
  ["aceita unitário e total certos na mesma frase", "Para 10 pessoas, R$ 1.318 cada, total de R$ 13.180.", KIT_OF, "aceita"],
  ["'12x' não vira quantidade de ingresso", "São 12x de R$ 1.318.", KIT_OF, "rejeita"],
  ["contexto não vaza entre orações", "A Experiência Mind está R$ 1.647. O VIP está R$ 2.647.", KIT_OF, "aceita"],
];

// ------------------------------------------------------------------ run
let falhas = 0;
console.log("\nGuardrail de preço — contrato (papel + faixa + experiência)\n");
let grupo = "";
for (const [nome, answer, oficiais, esperado] of CASOS) {
  const achado = precoInventado(answer, oficiais);
  const obtido = achado ? "rejeita" : "aceita";
  const ok = obtido === esperado;
  if (!ok) falhas++;
  console.log(`  ${ok ? "✓" : "✗"} ${nome}` +
    (ok ? "" : `\n      esperado=${esperado} obtido=${obtido}${achado ? ` (barrou ${achado})` : ""}\n      resposta: ${answer}`));
}

// Prova direta do mecanismo, sem passar por texto de resposta.
console.log("\nFaixa aplicável por quantidade:");
for (const n of [3, 5, 9, 10, 14, 15, 19, 20, 50]) {
  const f = faixaDe(n, KIT_OF);
  const pct = KIT_OF.faixas.find((x) => x.aPartirDe === f)?.percentual ?? null;
  const units = KIT_OF.fatos.filter((x) => x.papel === "unitario" && x.aPartirDe === f);
  console.log(`  ${String(n).padStart(2)} → ${f === null ? "(nenhuma)" : `faixa ${f}+ · ${pct}% · ` +
    units.map((u) => `${u.experiencia}=${u.valor}`).join(" ")}`);
}

console.log("\nLeitura de uma resposta em afirmações:");
for (const a of afirmacoes("Para 10 pessoas o Mind fica R$ 1.318 por pessoa, total de R$ 13.180, em 12x de R$ 110. O desconto é 20%.")) {
  console.log(`  ${a.texto.padEnd(12)} papel=${String(a.papel).padEnd(11)} qtd=${a.quantidade} exp=[${a.experiencias}]`);
}

console.log(`\nFatos lidos do Kit: ${KIT_OF.fatos.length} · faixas: ${new Set(KIT_OF.faixas.map((f) => f.aPartirDe)).size}` +
  ` · linhas de volume na fixture: ${KIT.precos_por_volume.precos_por_volume.length}`);
console.log(`\n${CASOS.length - falhas}/${CASOS.length} casos passaram.`);
process.exit(falhas ? 1 : 0);
