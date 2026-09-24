#!/usr/bin/env node
// Contrato: TURNO BLOQUEADO TAMBÉM É TURNO REGISTRADO.
//
// Determinístico e offline: não sobe Edge Function, não chama modelo, não toca banco.
//
// O problema medido em produção (07/09/2026): os dois desvios de `guarded` —
// checkout sem oficial e preço inventado sem carrinho — respondiam à Treble com
// `needs_human=true` e retornavam ANTES de `mind_turno_registrar`. A pessoa recebia
// a fala de handoff, mas engagement.conversas nunca sabia: audience/stage/needs_human
// continuavam null e a fila de pós-turno nunca via a conversa. A promessa de "já
// chamo alguém do time" não deixava rastro nenhum no banco.
//
// O que este contrato trava:
//
//   1. existe uma única função de persistência para os dois desvios de guard;
//   2. ela chama `mind_turno_registrar` e força `needs_human: true`;
//   3. o desvio de checkout não-oficial persiste antes de responder;
//   4. o desvio de preço inventado (bloqueio) persiste antes de responder;
//   5. o motivo do bloqueio viaja em `p_meta.guard_motivo`, para distinguir os dois
//      casos depois, sem tabela nova.
//
//   node tests/vendedor_guard_persiste_turno.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const AQUI = dirname(fileURLToPath(import.meta.url));
const FONTE = join(AQUI, "..", "supabase", "functions", "treble-inbound-agent", "index.ts");
const src = readFileSync(FONTE, "utf8");

const falhas = [];
const check = (nome, cond, detalhe = "") => {
  if (!cond) falhas.push(`${nome}${detalhe ? ` — ${detalhe}` : ""}`);
};

// ------------------------------------------------ 1. a função de persistência existe
check(
  "existe registrarTurnoGuardado",
  /const registrarTurnoGuardado = async \(motivo: string, resposta: string\)/.test(src),
);

const inicioHelper = src.indexOf("const registrarTurnoGuardado");
const fimHelper = src.indexOf("checkoutCandidato", inicioHelper);
const helper = inicioHelper >= 0 && fimHelper > inicioHelper ? src.slice(inicioHelper, fimHelper) : "";

// --------------------------------------- 2. ela persiste via mind_turno_registrar
check("o helper chama mind_turno_registrar", /supabase\.rpc\(\s*"mind_turno_registrar"/.test(helper));
check("o helper força needs_human true", /needs_human:\s*true/.test(helper));
check("o helper carrega o motivo do bloqueio", /guard_motivo:\s*motivo/.test(helper));

// --------------------------------- 3. checkout sem oficial persiste antes de sair
const blocoCheckout = src.slice(
  src.indexOf("if (checkoutSolicitado && !checkoutOficial)"),
  src.indexOf("if (checkoutSolicitado && !checkoutOficial)") + 700,
);
check(
  "checkout_nao_oficial chama o helper antes do return",
  /await registrarTurnoGuardado\(\s*"checkout_nao_oficial"/.test(blocoCheckout) &&
    blocoCheckout.indexOf("registrarTurnoGuardado") < blocoCheckout.indexOf("return json"),
);

// ------------------------------------------- 4. preço inventado persiste antes de sair
const blocoPreco = src.slice(
  src.indexOf("if (decisaoPreco.bloqueia)"),
  src.indexOf("if (decisaoPreco.bloqueia)") + 700,
);
check(
  "preco_inventado chama o helper antes do return",
  /await registrarTurnoGuardado\(\s*"preco_inventado"/.test(blocoPreco) &&
    blocoPreco.indexOf("registrarTurnoGuardado") < blocoPreco.indexOf("return json"),
);

if (falhas.length) {
  console.error("Falhas no contrato de persistência do turno guardado:");
  for (const f of falhas) console.error(" - " + f);
  process.exit(1);
}

console.log("✓ 6/6 verificações passaram — turno bloqueado sempre fica registrado.");
