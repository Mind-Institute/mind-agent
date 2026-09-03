#!/usr/bin/env node
// Contrato: FALHA DE RUNTIME NUNCA VIRA SILÊNCIO.
//
// Determinístico e offline: não sobe Edge Function, não chama modelo, não toca banco.
//
// O problema medido em 03/09/2026: o `catch` do fim do turno já devolvia 200 com uma
// fala de desculpa e `needs_human`, mas cinco `return` de falha aconteciam ANTES dele e
// saíam com HTTP puro, sem `user_session_keys`. Nesses casos, quem recebe alguma coisa
// depende inteiramente de o fluxo da Treble tratar não-2xx — e isso não é garantia
// deste lado da fronteira.
//
// O que este contrato trava:
//
//   1. todo caminho de falha de RUNTIME sai por `falhaComTransferencia`;
//   2. essa saída sempre carrega `resposta_ia` E `needs_human=true`, com status 200,
//      porque a Treble precisa ler o corpo para transferir;
//   3. a fala de desculpa mora numa constante só — duas cópias divergem com o tempo;
//   4. os únicos status não-2xx que sobram são os ALTOS de propósito: `unauthorized`
//      (token errado é erro de configuração da integração, não turno de gente) e
//      `method_not_allowed`.
//
//   node tests/vendedor_falha_sem_silencio.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const AQUI = dirname(fileURLToPath(import.meta.url));
const FONTE = join(AQUI, "..", "supabase", "functions", "treble-inbound-agent", "index.ts");
const src = readFileSync(FONTE, "utf8");

// Falhas de runtime: a pessoa está do outro lado esperando. Todas têm de transferir.
const FALHAS_DE_RUNTIME = [
  "ingestao_falhou",
  "config_indisponivel",
  "invalid_json",
  "faltam_campos",
  "ia_nao_configurada",
  "ia_indisponivel",
];

// Status não-2xx tolerados, e só estes. Nenhum deles é uma pessoa esperando resposta.
const ALTOS_DE_PROPOSITO = new Set(["401", "405"]);

const falhas = [];
const check = (nome, cond, detalhe = "") => {
  if (!cond) falhas.push(`${nome}${detalhe ? ` — ${detalhe}` : ""}`);
};

// ------------------------------------------------------------ 1. a saída existe
check("existe a saída única de transferência", /function falhaComTransferencia\s*\(/.test(src));

const corpo = src.slice(
  src.indexOf("function falhaComTransferencia"),
  src.indexOf("function falhaComTransferencia") + 700,
);
check("a transferência responde 200", /return json\(\s*200\s*,/.test(corpo), corpo.slice(0, 80));
check(
  "a transferência manda a copy já aprovada",
  /key:\s*"resposta_ia",\s*value:\s*RESPOSTA_HANDOFF/.test(corpo),
);
check("a transferência acende needs_human", /key:\s*"needs_human",\s*value:\s*"true"/.test(corpo));
check("a transferência preserva o código do erro", /error:\s*codigo/.test(corpo));
check("a transferência preserva o status de origem", /status_origem/.test(corpo));

// ------------------------------------------- 2. toda falha de runtime passa por ela
for (const codigo of FALHAS_DE_RUNTIME) {
  const viaTransferencia = new RegExp(`falhaComTransferencia\\(\\s*\\d+\\s*,\\s*"${codigo}"`).test(src);
  const viaJsonNu = new RegExp(`json\\(\\s*\\d+\\s*,\\s*\\{[^}]*error:\\s*"${codigo}"`).test(src);
  check(`\`${codigo}\` transfere em vez de calar`, viaTransferencia && !viaJsonNu);
}

// ------------------------------------------------- 3. a fala mora num lugar só
//
// Conta o texto da falha TÉCNICA, não o final "já vou te conectar…", que também
// aparece na copy de checkout indisponível — mensagem diferente, propósito diferente.
const ocorrenciasDaFala = src.split("Tive um probleminha técnico aqui").length - 1;
check("a fala de desculpa existe", ocorrenciasDaFala >= 1);
check(
  "a fala de desculpa mora só na constante",
  ocorrenciasDaFala === 1,
  `${ocorrenciasDaFala} cópias — deve existir só em RESPOSTA_HANDOFF`,
);

// ------------------------------------ 4. nenhum não-2xx novo escapa sem ser notado
const statusNao2xx = [...src.matchAll(/\breturn json\(\s*(\d{3})\s*,/g)]
  .map((m) => m[1])
  .filter((s) => !s.startsWith("2"));
const inesperados = [...new Set(statusNao2xx)].filter((s) => !ALTOS_DE_PROPOSITO.has(s));
check(
  "nenhum status não-2xx fora dos altos de propósito",
  inesperados.length === 0,
  inesperados.length ? `encontrados: ${inesperados.join(", ")}` : "",
);

// ------------------------------------------------------- 5. o catch continua coberto
check(
  "o catch final também transfere",
  /catch \(error\)[\s\S]{0,900}?return falhaComTransferencia\(/.test(src),
);

if (falhas.length) {
  console.error("Falhas no contrato de falha-sem-silêncio:");
  for (const f of falhas) console.error(" - " + f);
  process.exit(1);
}

const total = 6 + FALHAS_DE_RUNTIME.length + 2 + 1 + 1;
console.log(`✓ ${total}/${total} verificações passaram — nenhuma falha de runtime sai calada.`);
