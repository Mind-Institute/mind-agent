#!/usr/bin/env node
// Contrato estático: B2B usa credenciamento person-bound e o Core compartilhado,
// enriquece dados sem bloquear a venda e roteia B2B só por intenção corporativa.
// Não chama modelo, não toca banco e não cria conversa.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const aqui = dirname(fileURLToPath(import.meta.url));
const fonte = join(aqui, "..", "supabase", "functions", "treble-inbound-agent", "index.ts");
const src = readFileSync(fonte, "utf8");

const checks = [
  ["runtime 1.10.1", src.includes('const VERSION = "1.10.1"')],
  ["credenciamento entra no contexto", src.includes("credenciamento: conv.credenciamento ?? null")],
  ["e-mail e WhatsApp usam rótulos", src.includes("[email_1]") && src.includes("[whatsapp_1]")],
  ["formato validado pelo Core", src.includes("mind_identificador_validar") && src.includes("VALIDACAO_IDENTIFICADORES")],
  ["WhatsApp declarado usa writer próprio", src.includes("mind_identificador_declarado_registrar")],
  ["nome coletado hidrata identidade ancorada", src.includes("if (emailDito || nomeDito)")],
  ["dados de comprador não entram no runtime", !/buyer_(name|email|company|cpf|cnpj)/.test(src)],
  ["rota comercial rápida", src.includes("rotaComercialRapida(message, conv.historico)")],
  ["cadastro não bloqueia checkout", src.includes("Nunca condicione resposta, recomendação, preço, calculadora, proposta ou checkout")],
  ["cargo não define B2B", src.includes("Cargo e empresa descrevem a pessoa")],
  ["bloqueio cadastral removido", !src.includes("ativo_comercial_aguarda_contato")],
  ["estado cadastral legado neutralizado", src.includes('conv.stage === "coleta_cadastro" ? "escolha_aberta"')],
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
