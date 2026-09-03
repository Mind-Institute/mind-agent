#!/usr/bin/env node
// Contrato estático: B2B recebe credenciamento e completa os seis campos validados.
// Não chama modelo, não toca banco e não cria conversa.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const aqui = dirname(fileURLToPath(import.meta.url));
const fonte = join(aqui, "..", "supabase", "functions", "treble-inbound-agent", "index.ts");
const src = readFileSync(fonte, "utf8");

const checks = [
  ["runtime 1.7.0", src.includes('const VERSION = "1.7.0"')],
  ["credenciamento entra no contexto", src.includes("credenciamento: conv.credenciamento ?? null")],
  ["regra restrita ao B2B", src.includes('rotaAplicada === "summit_b2b"')],
  ["seis campos mínimos", src.includes("primeiro nome, sobrenome, e-mail, WhatsApp, empresa e cargo")],
  ["coleta sempre o que falta", src.includes("SEMPRE colete o próximo")],
  ["uma pergunta por mensagem", src.includes("Faça uma pergunta curta por mensagem")],
  ["ação antes da coleta", src.includes("Responda e execute primeiro o que a pessoa pediu")],
  ["WhatsApp ausente é pedido", src.includes("Caso contrário, peça o WhatsApp")],
  ["e-mail e WhatsApp usam rótulos", src.includes("[email_1]") && src.includes("[whatsapp_1]")],
  ["formato validado pelo Core", src.includes("mind_identificador_validar") && src.includes("VALIDACAO_IDENTIFICADORES")],
  ["WhatsApp declarado usa writer próprio", src.includes("mind_identificador_declarado_registrar")],
  ["nome coletado hidrata identidade ancorada", src.includes("if (emailDito || nomeDito)")],
  ["proibição invertida não voltou", !src.includes("Não colete cadastro.")],
  ["dados de comprador não entram no runtime", !/buyer_(name|email|company|cpf|cnpj)/.test(src)],
];

const falhas = checks.filter(([, ok]) => !ok).map(([nome]) => nome);
if (falhas.length) {
  console.error("Falhas no contrato B2B:");
  for (const falha of falhas) console.error(" - " + falha);
  process.exit(1);
}
console.log(`✓ ${checks.length}/${checks.length} verificações do runtime B2B passaram`);
