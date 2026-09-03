#!/usr/bin/env node
// Contrato estático: B2B usa credenciamento person-bound e o Core compartilhado,
// completa o contato no início e bloqueia checkout enquanto ele estiver incompleto.
// Não chama modelo, não toca banco e não cria conversa.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const aqui = dirname(fileURLToPath(import.meta.url));
const fonte = join(aqui, "..", "supabase", "functions", "treble-inbound-agent", "index.ts");
const src = readFileSync(fonte, "utf8");

const checks = [
  ["runtime 1.9.0", src.includes('const VERSION = "1.9.0"')],
  ["credenciamento entra no contexto", src.includes("credenciamento: conv.credenciamento ?? null")],
  ["e-mail e WhatsApp usam rótulos", src.includes("[email_1]") && src.includes("[whatsapp_1]")],
  ["formato validado pelo Core", src.includes("mind_identificador_validar") && src.includes("VALIDACAO_IDENTIFICADORES")],
  ["WhatsApp declarado usa writer próprio", src.includes("mind_identificador_declarado_registrar")],
  ["nome coletado hidrata identidade ancorada", src.includes("if (emailDito || nomeDito)")],
  ["dados de comprador não entram no runtime", !/buyer_(name|email|company|cpf|cnpj)/.test(src)],
  ["regra sensível à rota B2B", src.includes('rotaAplicada === "summit_b2b"')],
  ["cinco campos mínimos", src.includes("nome completo, e-mail, WhatsApp, empresa e cargo")],
  ["coleta sempre o próximo ausente", src.includes("SEMPRE colete o próximo")],
  ["uma pergunta curta por mensagem", src.includes("Faça uma pergunta curta por mensagem")],
  ["captura vale para B2B e B2C", src.includes('["summit_b2b", "summit_b2c"].includes')],
  ["checkout espera contato", src.includes("Não envie calculadora, proposta ou checkout antes de completar o contato mínimo")],
  ["WhatsApp ausente é pedido", src.includes("Caso contrário, peça o WhatsApp")],
  ["usa Kit único", src.includes('instructions = kit.playbook as string')],
  ["usa lupa compartilhada", src.includes('toolsDeIntelligence(toolsDoTurno)')],
  ["usa raciocínio adaptativo", src.includes('esforcoDeRaciocinio(message, toolsParaModelo.length)')],
];

const falhas = checks.filter(([, ok]) => !ok).map(([nome]) => nome);
if (falhas.length) {
  console.error("Falhas no contrato B2B:");
  for (const falha of falhas) console.error(" - " + falha);
  process.exit(1);
}
console.log(`✓ ${checks.length}/${checks.length} verificações do runtime B2B passaram`);
