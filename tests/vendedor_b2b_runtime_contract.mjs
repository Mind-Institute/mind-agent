#!/usr/bin/env node
// Contrato estático: a identidade B2B é progressiva e sensível à rota.
// Não chama modelo, não toca banco e não cria conversa.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const aqui = dirname(fileURLToPath(import.meta.url));
const fonte = join(aqui, "..", "supabase", "functions", "treble-inbound-agent", "index.ts");
const src = readFileSync(fonte, "utf8");

const checks = [
  ["runtime 1.6.1", src.includes('const VERSION = "1.6.1"')],
  ["regra sensível à rota B2B", src.includes('rotaAplicada === "summit_b2b"')],
  ["campos B2B progressivos", src.includes("nome, sobrenome, empresa, cargo e e-mail")],
  ["WhatsApp reaproveitado do canal", src.includes("O WhatsApp desta conversa já vem do canal")],
  ["uma informação por mensagem", src.includes("Peça no máximo um dado por mensagem")],
  ["compra antes do cadastro", src.includes("não atrase preço, proposta, checkout ou solução")],
  ["bloqueio antigo removido", !src.includes("Não colete cadastro.")],
  ["proibição antiga removida", !src.includes("Não peça e-mail, sobrenome, empresa ou cargo")],
];

const falhas = checks.filter(([, ok]) => !ok).map(([nome]) => nome);
if (falhas.length) {
  console.error("Falhas no contrato B2B:");
  for (const falha of falhas) console.error(" - " + falha);
  process.exit(1);
}
console.log(`✓ ${checks.length}/${checks.length} verificações do runtime B2B passaram`);
