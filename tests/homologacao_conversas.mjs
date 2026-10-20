#!/usr/bin/env node
/* ============================================================================
 * BATERIA DE HOMOLOGAÇÃO — conversas com o MODELO REAL.
 *
 * O que esta bateria é, e o que ela não é:
 *
 *   O harness `vendedor_institute_dash_e2e.mjs` prova o CÓDIGO: que o Gate é
 *   consultado, que o Kit certo é carregado, que o guardrail barra preço fora do
 *   catálogo, que o reenvio não duplica. Ele usa resposta de modelo SIMULADA — o
 *   dublê devolve um JSON escrito por nós. Ele não sabe nada sobre a qualidade da
 *   resposta, porque a resposta nunca foi gerada.
 *
 *   ESTA bateria prova o ENTENDIMENTO: ela chama o modelo de verdade, com o
 *   playbook real, o catálogo real e o mesmo payload que o runtime monta, e guarda
 *   a resposta inteira para leitura humana.
 *
 * O QUE ELA NÃO TOCA: não chama a Edge Function, não escreve no banco, não cria
 * conversa, não manda mensagem para ninguém. O único serviço externo é a OpenAI.
 * O catálogo e os playbooks vêm de `tests/fixtures/kit-homologacao.json`, uma cópia
 * congelada do Kit vivo — regenerável por `npm run homologacao:snapshot`.
 *
 * O QUE ELA NÃO DECIDE: aprovação. Os sinais automáticos abaixo pegam erro grosseiro
 * (preço fora do catálogo, link que o Kit não mandou, oferta de Summit onde não
 * cabe). Correção, pertinência e tom são leitura de gente — por isso o relatório sai
 * com a conversa inteira, não só com um placar.
 *
 *   OPENAI_API_KEY=...  node tests/homologacao_conversas.mjs
 *   OPENAI_API_KEY=...  node tests/homologacao_conversas.mjs --caso ferramentas
 *
 * Saídas (em `audit/homologacao/`, não versionadas):
 *   conversas-<carimbo>.md    para ler e revisar
 *   conversas-<carimbo>.json  bruto, com payload e resposta de cada turno
 * ==========================================================================*/

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
import vm from "node:vm";

import {
  precoInventado,
  precosOficiais,
} from "../supabase/functions/treble-inbound-agent/guardrail-preco.ts";
import {
  escolherLinkOficial,
  listarLinksOficiais,
} from "../supabase/functions/_shared/checkout-attribution.ts";

/* ------------------------------------------------------------------ entrada */

const CHAVE = process.env.OPENAI_API_KEY ?? "";
const MODELO = process.env.OPENAI_MODEL ?? "gpt-5.4";
const filtro = (() => {
  const i = process.argv.indexOf("--caso");
  return i > -1 ? process.argv[i + 1] : null;
})();

// ENSAIO: monta tudo — fixture, schema tirado do runtime, payload de cada turno — e
// NÃO chama a OpenAI. Serve para conferir o que vai ser enviado antes de gastar
// chamada, e para este arquivo ser verificável sem credencial nenhuma.
const ensaio = process.argv.includes("--ensaio");

if (!CHAVE && !ensaio) {
  console.error(`
Falta OPENAI_API_KEY.

Esta bateria chama o modelo de verdade — é esse o ponto dela. Sem a chave não há
o que rodar, e inventar resposta aqui seria exatamente o contrário do que ela
existe para medir.

  OPENAI_API_KEY=...  node tests/homologacao_conversas.mjs

A chave é a mesma que a Edge Function usa. Ela não é lida de nenhum arquivo do
repositório e não fica gravada em lugar nenhum por este script.

Para conferir o que seria enviado, sem chave e sem chamada:

  node tests/homologacao_conversas.mjs --ensaio
`);
  process.exit(2);
}

/* -------------------------------------------------- kit e playbooks reais */

const FIXTURE = new URL("./fixtures/kit-homologacao.json", import.meta.url);
const kit = JSON.parse(readFileSync(FIXTURE, "utf8"));

/* ---------------------------------- o schema de saída, lido do runtime vivo */
/* Não se reescreve o schema aqui: ele é extraído do fonte que vai ao ar, para a
 * bateria não validar um contrato que o runtime não usa. */

function semImports(src) {
  const saida = [];
  let dentro = false;
  for (const linha of src.split("\n")) {
    if (dentro) { if (/;\s*$/.test(linha)) dentro = false; continue; }
    if (/^import\b/.test(linha)) { if (!/;\s*$/.test(linha)) dentro = true; continue; }
    saida.push(linha);
  }
  return saida.join("\n");
}

const fonteRuntime = readFileSync(
  new URL("../supabase/functions/treble-inbound-agent/index.ts", import.meta.url),
  "utf8",
);
const ctx = { Deno: { serve() {}, env: { get: () => "" } }, console: { log() {}, info() {}, warn() {}, error() {} } };
vm.runInNewContext(stripTypeScriptTypes(semImports(fonteRuntime)), ctx);
const montarResponseSchema = ctx.montarResponseSchema;
if (typeof montarResponseSchema !== "function") {
  console.error("não consegui extrair montarResponseSchema do runtime");
  process.exit(1);
}
const ROTAS_DO_CANAL = kit.canal_rotas.rotas;
const SCHEMA = montarResponseSchema(ROTAS_DO_CANAL);

/* ------------------------------------------------------------- os cenários */
/* Cada cenário é uma CONVERSA: uma ou mais falas da pessoa, na ordem. A rota é
 * declarada porque esta bateria mede a RESPOSTA, não a classificação — a escolha de
 * rota é medida no harness determinístico e pelo Router, que não é chamado aqui. */

const CENARIOS = [
  {
    id: "ferramentas",
    titulo: "Pergunta sobre ferramentas, sem produto definido",
    porque: "O caso que bloqueia lançamento. A resposta não pode presumir Institute nem Dash, e não pode oferecer Summit.",
    rota: "institute",
    falas: ["Oi! Quais ferramentas vocês têm para trabalhar isso?"],
    esperado: [
      "Pede contexto ou devolve uma leitura útil antes de recomendar",
      "NÃO empurra um programa específico já na primeira fala",
      "NÃO menciona o Mind Summit como oferta",
    ],
  },
  {
    id: "ferramentas-dash",
    titulo: "A mesma pergunta, na competência Dash",
    porque: "A pergunta ambígua não pode virar venda nem no caminho consultivo.",
    rota: "dash",
    falas: ["Oi! Quais ferramentas vocês têm para trabalhar isso?"],
    esperado: [
      "Pergunta o que a pessoa precisa transformar",
      "NÃO cita preço, proposta ou contrato",
    ],
  },
  {
    id: "pergunta-direta",
    titulo: "Pergunta específica que merece resposta direta",
    porque: "Pertinência: pergunta objetiva não vira entrevista nem catálogo inteiro.",
    rota: "institute",
    falas: ["Quando começa a Certificação Avançada e quanto custa?"],
    esperado: [
      "Responde a data e o preço do catálogo, sem rodeio",
      "Preço exatamente como está no catálogo",
      "No máximo uma pergunta de volta",
    ],
  },
  {
    id: "esclarecimento",
    titulo: "Dúvida que exige esclarecimento",
    porque: "O pedido não discrimina entre formação avulsa e percurso completo.",
    rota: "institute",
    falas: ["Queria me desenvolver melhor, o que vocês indicam?"],
    esperado: [
      "Faz UMA pergunta discriminante",
      "NÃO despeja os seis programas",
    ],
  },
  {
    id: "comparacao",
    titulo: "Comparação entre soluções",
    porque: "Comparar sem transformar em hierarquia nem empurrar o mais caro.",
    rota: "institute",
    falas: ["Qual a diferença entre a Certificação Avançada e o Mind Journey?"],
    esperado: [
      "Diferencia os dois com fatos do catálogo",
      "Não apresenta como hierarquia",
      "Preços, se citados, batem com o catálogo",
    ],
  },
  {
    id: "mudanca-de-assunto",
    titulo: "Mudança de assunto e correção do cliente",
    porque: "Continuidade: a correção da pessoa vence o que o agente inferiu antes.",
    rota: "institute",
    falas: [
      "Quero me desenvolver em liderança",
      "Na verdade não é para mim — minha empresa precisa diagnosticar o clima e medir resultado",
    ],
    esperado: [
      "Reconhece a correção sem repetir a recomendação anterior",
      "Pede `next_route=dash` no segundo turno",
      "NÃO insiste em formação depois da correção",
    ],
  },
  {
    id: "fora-do-catalogo",
    titulo: "Pergunta fora do catálogo",
    porque: "O playbook manda passar o WhatsApp do time, não inventar condição.",
    rota: "institute",
    falas: ["Vocês fazem nota fiscal para empresa e dão desconto para 8 pessoas?"],
    esperado: [
      "NÃO inventa preço corporativo, desconto nem política de NF",
      "Oferece o WhatsApp do time do Institute",
    ],
  },
  {
    id: "suporte-e-humano",
    titulo: "Suporte e pedido explícito de humano",
    porque: "Atendimento não é desta competência; a pessoa pediu gente.",
    rota: "institute",
    falas: ["Meu pagamento de uma formação deu erro e eu quero falar com uma pessoa"],
    esperado: [
      "Aciona needs_human ou pede next_route=cliente_suporte",
      "NÃO tenta resolver pagamento por conta própria",
      "NÃO vende nada neste turno",
    ],
  },
  {
    id: "compra-institute",
    titulo: "Intenção explícita de compra do Institute",
    porque: "O caminho feliz: recomendar, dizer o preço e mandar a página com a âncora.",
    rota: "institute",
    falas: [
      "Quero fazer a formação de Segurança Psicológica",
      "Perfeito, como faço para me inscrever?",
    ],
    esperado: [
      "Manda a pagina_oficial exata do catálogo, com o #",
      "checkout_url preenchido com um link do Kit",
      "Preço, se citado, bate com o catálogo",
    ],
  },
  {
    id: "summit-encerrado",
    titulo: "Summit encerrado",
    porque: "O evento acabou em 17/09 e saiu de venda. Não pode virar oferta nem promessa.",
    rota: "institute",
    falas: ["Ainda dá para comprar ingresso do Mind Summit?"],
    esperado: [
      "Diz que o Summit não está à venda, ou encaminha a gente",
      "NÃO oferece ingresso, lote, preço ou link do Summit",
      "NÃO inventa a próxima edição",
    ],
  },
];

/* --------------------------------------------------- o payload do runtime */

function montarPayload(cenario, historico, fala) {
  const k = kit[cenario.rota];
  return {
    DADOS_OFICIAIS: k.structured,
    // Em institute/dash a agenda do Summit NÃO entra — é a regra da v1.11.0.
    AGENDA_E_PALESTRANTES: {},
    VALIDACAO_IDENTIFICADORES: {},
    estado_da_conversa: {
      rota: cenario.rota,
      audience: null,
      stage: historico.length ? "em_conversa" : null,
      nome_contato: "Renata",
      origem_codigo: null,
      utm_de_origem: null,
      produto: null,
    },
    quem_esta_falando: {
      ja_identificada: true,
      perfil: { nome: "Renata" },
      credenciamento: null,
      como_agir: [
        "USE O QUE JÁ SABEMOS ANTES DE PERGUNTAR: confira perfil e credenciamento e nunca repita um dado conhecido.",
        "Só pergunte um dado se ele for necessário para resolver o que a pessoa quer AGORA.",
        "Se a pessoa contar algo sobre si espontaneamente, aproveite — mas não puxe.",
      ].join(" "),
    },
    historico,
    mensagem_do_lead: fala,
  };
}

async function chamarModelo(instructions, payload) {
  const r = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${CHAVE}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: MODELO,
      instructions,
      input: [{ role: "user", content: JSON.stringify(payload) }],
      text: { format: { type: "json_schema", name: "treble_agent_turn", strict: true, schema: SCHEMA } },
      max_output_tokens: 1500,
      store: false,
    }),
  });
  if (!r.ok) throw new Error(`openai_${r.status}: ${(await r.text()).slice(0, 300)}`);
  const corpo = await r.json();
  const texto = typeof corpo.output_text === "string" && corpo.output_text
    ? corpo.output_text
    : (corpo.output ?? [])
        .flatMap((i) => i?.content ?? [])
        .find((p) => p?.type === "output_text")?.text ?? "";
  return JSON.parse(texto);
}

/* ------------------------------------------------------- sinais automáticos */
/* Erro grosseiro, não julgamento de qualidade. */

const SUMMIT_COMO_OFERTA =
  /\b(ingresso|lote \d|experi[êe]ncia (mind|vip|prime)\b|garanta (seu|sua)|[úu]ltimas vagas)\b/i;

function sinais(cenario, turno) {
  const k = kit[cenario.rota];
  const oficiais = precosOficiais(k.structured);
  const linksDoKit = listarLinksOficiais(k.structured);
  const texto = String(turno.answer ?? "");
  const achados = [];

  const preco = precoInventado(texto, oficiais);
  if (preco) achados.push(`PREÇO FORA DO CATÁLOGO: ${preco}`);

  for (const url of texto.match(/https?:\/\/\S+/g) ?? []) {
    const limpa = url.replace(/[).,;]+$/, "");
    if (!linksDoKit.includes(limpa) && !limpa.includes("wa.me")) {
      achados.push(`LINK QUE O KIT NÃO MANDOU: ${limpa}`);
    }
  }

  if (turno.checkout_url && !escolherLinkOficial(k.structured, turno.checkout_url, texto)) {
    achados.push(`checkout_url não confere com o Kit: ${turno.checkout_url}`);
  }

  if (cenario.id !== "summit-encerrado" && SUMMIT_COMO_OFERTA.test(texto)) {
    achados.push("OFERTA INDEVIDA: fala de ingresso/lote/experiência do Summit");
  }
  if (cenario.id === "summit-encerrado" && /https?:\/\/\S*summit/i.test(texto)) {
    achados.push("OFERTA INDEVIDA: link de Summit num turno sobre evento encerrado");
  }

  if (turno.next_route && !ROTAS_DO_CANAL.includes(turno.next_route)) {
    achados.push(`next_route fora da política do canal: ${turno.next_route}`);
  }
  return achados;
}

/* ------------------------------------------------------------------ execução */

const carimbo = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
mkdirSync(new URL("../audit/homologacao/", import.meta.url), { recursive: true });

const resultados = [];
let turnosComSinal = 0;

for (const cenario of CENARIOS) {
  if (filtro && cenario.id !== filtro) continue;
  console.log(`\n━━ ${cenario.id} · ${cenario.titulo}`);
  const historico = [];
  const turnos = [];

  for (const fala of cenario.falas) {
    const payload = montarPayload(cenario, [...historico], fala);

    if (ensaio) {
      const bytes = JSON.stringify(payload).length;
      console.log(`   lead: ${fala}`);
      console.log(`         playbook ${kit[cenario.rota].playbook.length} chars · payload ${bytes} bytes` +
        ` · blocos ${Object.keys(payload.DADOS_OFICIAIS).join(",")}` +
        ` · agenda ${Object.keys(payload.AGENDA_E_PALESTRANTES).length}` +
        ` · histórico ${payload.historico.length}`);
      turnos.push({ fala, turno: null, erro: null, sinais: [], payload });
      historico.push({ papel: "lead", conteudo: fala });
      historico.push({ papel: "agente", conteudo: "(ensaio: sem resposta do modelo)" });
      continue;
    }

    let turno, erro = null;
    try {
      turno = await chamarModelo(kit[cenario.rota].playbook, payload);
    } catch (e) {
      erro = e.message;
      turno = null;
      console.log(`   ✗ ${erro}`);
    }
    const achados = turno ? sinais(cenario, turno) : [];
    if (achados.length) turnosComSinal++;

    console.log(`   lead: ${fala}`);
    if (turno) {
      console.log(`   mia:  ${String(turno.answer).replace(/\n/g, "\n         ")}`);
      console.log(`         [needs_human=${turno.needs_human} · checkout_sent=${turno.checkout_sent} · next_route=${turno.next_route ?? "null"}]`);
      for (const a of achados) console.log(`   ⚠ ${a}`);
    }

    turnos.push({ fala, turno, erro, sinais: achados, payload });
    if (turno) {
      historico.push({ papel: "lead", conteudo: fala });
      historico.push({ papel: "agente", conteudo: turno.answer });
    }
  }
  resultados.push({ ...cenario, turnos });
}

/* -------------------------------------------------------------- relatórios */

const base = new URL(`../audit/homologacao/conversas-${carimbo}`, import.meta.url);
writeFileSync(new URL(`${base.pathname}.json`, "file:"), JSON.stringify({
  gerado_em: new Date().toISOString(),
  modelo: MODELO,
  kit_gerado_em: kit.gerado_em,
  rotas_do_canal: ROTAS_DO_CANAL,
  resultados,
}, null, 2));

const md = [];
md.push(`# Homologação do vendedor no WhatsApp — conversas com o modelo real\n`);
md.push(`Rodado em ${new Date().toISOString()} · modelo \`${MODELO}\``);
md.push(`Kit e playbooks: cópia de ${kit.gerado_em}`);
md.push(`Rotas do canal: ${ROTAS_DO_CANAL.join(", ")}\n`);
md.push(`> Os sinais automáticos pegam erro grosseiro — preço fora do catálogo, link que o Kit`);
md.push(`> não mandou, oferta de Summit onde não cabe. **Correção, pertinência e tom são leitura`);
md.push(`> sua.** Cada cenário traz o que se espera dele, para a leitura ter critério.\n`);
md.push(`---\n`);

for (const r of resultados) {
  md.push(`## ${r.titulo}\n`);
  md.push(`**Por que está na bateria:** ${r.porque}\n`);
  md.push(`**Competência:** \`${r.rota}\`\n`);
  md.push(`**O que se espera:**\n`);
  for (const e of r.esperado) md.push(`- ${e}`);
  md.push(``);
  for (const t of r.turnos) {
    md.push(`> **Pessoa:** ${t.fala}\n`);
    if (t.erro) { md.push(`**ERRO:** ${t.erro}\n`); continue; }
    if (!t.turno) { md.push(`_(ensaio: o modelo não foi chamado)_\n`); continue; }
    md.push(`**MIA:**\n`);
    md.push(t.turno.answer.split("\n").map((l) => `> ${l}`).join("\n"));
    md.push(``);
    md.push(`\`needs_human=${t.turno.needs_human}\` · \`checkout_sent=${t.turno.checkout_sent}\` · ` +
      `\`checkout_url=${t.turno.checkout_url ?? "null"}\` · \`next_route=${t.turno.next_route ?? "null"}\` · ` +
      `\`intent=${t.turno.intent}\` · \`stage=${t.turno.stage}\``);
    md.push(``);
    if (t.sinais.length) {
      md.push(`**⚠ Sinais automáticos:**`);
      for (const s of t.sinais) md.push(`- ${s}`);
      md.push(``);
    }
  }
  md.push(`**Aprovado?** ( ) sim ( ) não — observações:\n`);
  md.push(`---\n`);
}

writeFileSync(new URL(`${base.pathname}.md`, "file:"), md.join("\n"));

const totalTurnos = resultados.reduce((n, r) => n + r.turnos.length, 0);
console.log(`\n${totalTurnos} turnos em ${resultados.length} cenários.`);
console.log(`${turnosComSinal} turno(s) com sinal automático.`);
console.log(`\nPara revisar:  audit/homologacao/conversas-${carimbo}.md`);
console.log(`Bruto:         audit/homologacao/conversas-${carimbo}.json`);
console.log(`\nSinal automático limpo NÃO é aprovação. A homologação é a sua leitura.`);
