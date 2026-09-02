#!/usr/bin/env node
// Contrato: RESPOSTA PRONTA NUNCA É CORTADA POR CARACTERE.
//
// Determinístico e offline: não sobe Edge Function, não chama modelo, não toca banco.
//
// O bug (v1.5.0 e anteriores): três tetos empilhados em 700 caracteres —
//
//   1. `answer.maxLength: 700`   no JSON Schema mandado à OpenAI;
//   2. `max_output_tokens: 700`  no orçamento da chamada (token ≠ caractere);
//   3. `.slice(0, 700)`          na leitura de `turn.answer` no runtime.
//
// Um turno real chegou ao WhatsApp com exatamente 700 caracteres, partido no meio
// de "Mind". O gatilho foi o playbook pedir as três experiências com preço, 12x e
// proposta de valor: não cabia, e o teto ganhava do prompt.
//
// Brevidade virou CONDUTA (está na `description` do campo), não tesoura. Este teste
// lê os BYTES VIVOS de `index.ts` — não uma cópia — e roda a cadeia real da resposta.
//
//   node tests/vendedor_resposta_nao_truncada.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { precoInventado, precosOficiais } from "../supabase/functions/treble-inbound-agent/guardrail-preco.ts";

const AQUI = dirname(fileURLToPath(import.meta.url));
const FONTE = join(AQUI, "..", "supabase", "functions", "treble-inbound-agent", "index.ts");
const src = readFileSync(FONTE, "utf8");

let ok = 0;
const falhas = [];
const check = (nome, cond, detalhe = "") => {
  if (cond) { ok++; return; }
  falhas.push(`${nome}${detalhe ? ` — ${detalhe}` : ""}`);
};

// ------------------------------------------------ 1. os três tetos, nos bytes vivos
// Sem regex frouxa: cada teto é procurado onde ele de fato morava.

// 1.1 — a leitura de `turn.answer` não pode terminar em corte.
const linhaAnswer = src.split("\n").find((l) => /const answer\s*=/.test(l));
check("existe a linha que lê turn.answer", Boolean(linhaAnswer));
check(
  "turn.answer é lido sem .slice()",
  Boolean(linhaAnswer) && !/\.slice\s*\(/.test(linhaAnswer),
  linhaAnswer?.trim(),
);
check(
  "turn.answer é lido sem substring/substr",
  Boolean(linhaAnswer) && !/\.subst(r|ring)\s*\(/.test(linhaAnswer),
  linhaAnswer?.trim(),
);

// 1.2 — o schema não pode voltar a apertar `answer`.
const bloco = src.slice(src.indexOf("answer:"), src.indexOf("answer:") + 1200);
const maxLen = Number(bloco.match(/maxLength:\s*(\d+)/)?.[1] ?? 0);
check("answer.maxLength >= 2000 no schema", maxLen >= 2000, `maxLength=${maxLen}`);

// 1.3 — o orçamento de tokens tem de caber numa resposta longa.
const maxTok = Number(src.match(/max_output_tokens:\s*(\d+)/)?.[1] ?? 0);
check("max_output_tokens >= 1500", maxTok >= 1500, `max_output_tokens=${maxTok}`);

// 1.4 — nenhum 700 sobrou como teto em lugar nenhum do arquivo (comentário não conta).
const setecentos = src
  .split("\n")
  .map((l, i) => [i + 1, l])
  .filter(([, l]) => !/^\s*(\/\/|\*|\/\*)/.test(l))
  .filter(([, l]) => /\b700\b/.test(l));
check("nenhum literal 700 em código executável", setecentos.length === 0,
  setecentos.map(([n, l]) => `L${n}: ${l.trim()}`).join(" | "));

// 1.5 — a brevidade continua sendo pedida ao modelo, como conduta.
check("a description de answer ainda pede resposta curta de WhatsApp",
  /description:\s*"[^"]*WhatsApp[^"]*curta/i.test(bloco), "sumiu a orientação de brevidade");
check("a description manda terminar a mensagem, nunca cortar no meio",
  /nunca interrompa no meio/i.test(bloco), "sumiu a instrução de frase inteira");

// ------------------------------- 2. a cadeia real, com uma resposta acima de 700
// A forma exata que estourava o teto: as três experiências com preço, 12x e
// proposta de valor. Os valores são os do Kit vivo (Lote 6), conferidos em 30/08/2026.
const DADOS_OFICIAIS = {
  ofertas: {
    bloco: "ofertas",
    ofertas: [
      { nome: "Experiência Mind — Lote 6", codigo: "mind-lote-6", moeda: "BRL", valor: 1647.0,
        condicoes_pagamento: "12x de R$ 137" },
      { nome: "Experiência VIP — Lote 6", codigo: "vip-lote-6", moeda: "BRL", valor: 2647.0,
        condicoes_pagamento: "12x de R$ 221" },
      { nome: "Experiência Prime — Lote 6", codigo: "prime-lote-6", moeda: "BRL", valor: 6297.0,
        condicoes_pagamento: "12x de R$ 525" },
    ],
  },
};

const RESPOSTA_LONGA =
  "Claro! São três experiências, e a diferença entre elas é o quanto você quer " +
  "estar perto do conteúdo e das pessoas.\n\n" +
  "A Experiência Mind sai por R$ 1.647, ou 12x de R$ 137. É o acesso completo aos " +
  "dois dias de conteúdo no São Paulo Expo, com todos os palestrantes do palco principal.\n\n" +
  "A Experiência VIP é R$ 2.647, ou 12x de R$ 221. Além de tudo da Mind, você fica " +
  "nas primeiras fileiras e participa das sessões fechadas com os pesquisadores.\n\n" +
  "A Experiência Prime é R$ 6.297, ou 12x de R$ 525. É a mais restrita: jantar com " +
  "os palestrantes, mesa de trabalho reservada e acesso ao material aprofundado depois do evento.\n\n" +
  "Os dois dias são 16 e 17 de setembro, e o ingresso vale para os dois.\n\n" +
  "Me conta o que te trouxe até o Summit que eu te ajudo a escolher a certa.";

// 2.1 — a resposta de teste precisa de fato estourar o teto antigo.
check("a resposta de teste passa de 700 caracteres", RESPOSTA_LONGA.length > 700,
  `${RESPOSTA_LONGA.length} chars`);

// 2.2 — a cadeia do runtime, na ordem em que ela roda.
const answer = String(RESPOSTA_LONGA ?? "").trim();          // index.ts: const answer = ...
const inventado = precoInventado(answer, precosOficiais(DADOS_OFICIAIS));
const respostaIa = inventado ? "<guardrail derrubou o turno>" : answer;

check("o guardrail de preço aprova a resposta longa", !inventado, `bloqueou em ${inventado}`);
check("resposta_ia sai com o mesmo tamanho que entrou",
  respostaIa.length === RESPOSTA_LONGA.length,
  `entrou ${RESPOSTA_LONGA.length}, saiu ${respostaIa.length}`);
check("resposta_ia é byte a byte a resposta do modelo", respostaIa === RESPOSTA_LONGA);
check("resposta_ia termina em frase inteira", /[.!?…🙌😊]$/u.test(respostaIa.trim()),
  `termina em ${JSON.stringify(respostaIa.slice(-24))}`);
check("resposta_ia não termina no meio de uma palavra",
  !/[A-Za-zÀ-ÿ]$/u.test(respostaIa.trim()),
  `termina em ${JSON.stringify(respostaIa.slice(-24))}`);

// 2.3 — o teto antigo, para deixar o contraste no registro. O corte cego perde
// caracteres e para onde calhar: no meio de uma palavra, de um item ou de uma frase.
// O turno real que expôs o bug parou dentro de "Mind"; o que importa aqui é a
// propriedade, não o ponto exato: 700 chars entregues no lugar da mensagem inteira.
const comoEra = RESPOSTA_LONGA.slice(0, 700);
check("o teto antigo cortava esta resposta", comoEra.length === 700 && comoEra !== RESPOSTA_LONGA,
  `${RESPOSTA_LONGA.length} chars viravam ${comoEra.length}`);
check("o teto antigo não parava em frase inteira", !/[.!?…]\s*$/u.test(comoEra),
  `a v1.5.0 entregaria ${JSON.stringify("…" + comoEra.slice(-30))}`);

// ------------------------------------------------------------------- relatório
console.log(`\nresposta de teste: ${RESPOSTA_LONGA.length} caracteres`);
console.log(`  v1.5.0 entregaria: …${JSON.stringify(comoEra.slice(-32))} (cortado em 700)`);
console.log(`  v1.5.1 entrega:    …${JSON.stringify(respostaIa.slice(-32))} (${respostaIa.length} chars, inteira)`);
console.log(`\nschema answer.maxLength=${maxLen} · max_output_tokens=${maxTok} · .slice no answer: ausente`);

if (falhas.length) {
  console.error(`\n✗ ${falhas.length} falha(s):`);
  for (const f of falhas) console.error(`   - ${f}`);
  console.error(`\n${ok}/${ok + falhas.length} casos passaram.`);
  process.exit(1);
}
console.log(`\n${ok}/${ok} casos passaram.`);
