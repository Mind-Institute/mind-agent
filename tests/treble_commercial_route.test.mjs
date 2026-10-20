import test from "node:test";
import assert from "node:assert/strict";
import { rotaComercialRapida } from "../supabase/functions/_shared/treble-commercial-route.ts";

/* ============================================================================
 * O QUE MUDOU EM 20/10/2026, E O QUE NÃO MUDOU
 *
 * NÃO mudou a discriminação B2B/B2C da v1.10.2: para ingresso, B2B exige destino
 * empresa/equipe E mais de uma pessoa; cargo, empresa e quantidade isolados não
 * bastam. Todos os casos que nomeiam ingresso continuam exatamente como estavam.
 *
 * MUDOU o alcance do atalho. Ele tinha um `return summit_b2c` incondicional no fim,
 * válido sob a premissa de 04/09 ("o canal é predominantemente comercial B2C"). Essa
 * premissa acabou em 24/09, quando o Summit saiu de venda e `institute`/`dash`
 * entraram no WhatsApp. Sem ingresso mencionado, o atalho deixa de opinar e o Router
 * decide — senão "quero levar minha equipe" continuaria sendo lido como compra de
 * ingresso de um evento que já aconteceu, em vez de poder ser Institute ou Dash.
 *
 * Os quatro casos abaixo foram ATUALIZADOS por causa disso, não removidos: eles
 * seguem travando o comportamento, agora o correto para o canal de hoje.
 * ==========================================================================*/

test("cargo sozinho não decide rota: vai ao Router", () => {
  // Antes: `summit_b2c` por padrão do canal. A regra de que CARGO NÃO É ATALHO DE
  // ROTA (v1.10.1) continua valendo — e é justamente por isso que "Sou gestora" não
  // pode virar venda de ingresso sozinha. Quem decide entre institute, dash e
  // cliente_suporte é o Router, com o contexto inteiro.
  assert.deepEqual(rotaComercialRapida("Sou gestora", []), {
    rota: null, motivo: "router_sem_sinal_de_ingresso",
  });
});

test("pergunta sobre ferramentas de trabalho NUNCA vira Summit", () => {
  // O caso que bloqueia lançamento. Enquanto o atalho tinha padrão comercial, esta
  // pergunta era classificada como compra de ingresso sem o Router ser consultado.
  for (
    const pergunta of [
      "Quais ferramentas vocês têm para trabalhar isso?",
      "Vocês têm alguma ferramenta para liderança?",
      "O que vocês oferecem para desenvolver meu time?",
      "Preciso de ajuda com clima organizacional, o que vocês têm?",
      "Quero desenvolver minhas competências de liderança",
      "Vocês têm formação para RH?",
    ]
  ) {
    assert.equal(
      rotaComercialRapida(pergunta, []).rota,
      null,
      `o atalho não pode decidir rota para: ${pergunta}`,
    );
  }
});

test("empresa conhecida não transforma compra individual em B2B", () => {
  assert.equal(rotaComercialRapida("Quero comprar um ingresso", [
    { papel: "lead", conteudo: "Trabalho na Natura como diretora" },
  ]).rota, "summit_b2c");
});

test("negação corporativa corrige histórico B2B quando o assunto é ingresso", () => {
  // O contrato original usava um histórico sem nenhuma menção a ingresso. A correção
  // de rota continua valendo — só precisa do assunto na conversa, que é o que o
  // atalho passou a exigir para opinar.
  assert.equal(rotaComercialRapida("Não é uma compra corporativa", [
    { papel: "lead", conteudo: "Quero um ingresso para o Summit" },
    { papel: "agente", conteudo: "Compra corporativa?" },
  ]).rota, "summit_b2c");
});

test("sem assunto de ingresso, a negação corporativa também vai ao Router", () => {
  assert.equal(rotaComercialRapida("Não é uma compra corporativa", [
    { papel: "lead", conteudo: "Sou gestora" },
  ]).rota, null);
});

test("empresa pagando um único ingresso continua B2C", () => {
  assert.equal(
    rotaComercialRapida("Minha empresa vai pagar meu ingresso", []).rota,
    "summit_b2c",
  );
});

test("dois ingressos para casal continuam B2C", () => {
  assert.equal(
    rotaComercialRapida("Quero dois ingressos para mim e meu marido", []).rota,
    "summit_b2c",
  );
});

test("quantidade sem destino corporativo continua B2C", () => {
  assert.equal(rotaComercialRapida("Quero 5 ingressos", []).rota, "summit_b2c");
});

test("empresa sem quantidade pede esclarecimento ao Router", () => {
  assert.deepEqual(
    rotaComercialRapida("Quero comprar ingressos para minha empresa", []),
    { rota: null, motivo: "router_quantidade_corporativa" },
  );
});

test("múltiplos ingressos para empresa tornam a oportunidade B2B", () => {
  assert.deepEqual(
    rotaComercialRapida("Quero 5 ingressos para minha empresa", []),
    { rota: "summit_b2b", motivo: "b2b_empresa_multiplos" },
  );
});

test("quantidade por extenso e destino corporativo tornam a oportunidade B2B", () => {
  assert.equal(
    rotaComercialRapida("Preciso de cinco ingressos para a empresa", []).rota,
    "summit_b2b",
  );
});

test("levar a equipe é B2B quando o assunto é ingresso", () => {
  assert.equal(
    rotaComercialRapida("Quero levar minha equipe ao Summit", []).rota,
    "summit_b2b",
  );
});

test("levar a equipe SEM dizer a quê não é mais compra de ingresso", () => {
  // Hoje "levar minha equipe" pode ser Institute (o FAQ do catálogo responde
  // "Minha empresa pode inscrever profissionais? Sim.") ou Dash. Decidir Summit
  // aqui seria responder sobre um evento encerrado.
  assert.equal(rotaComercialRapida("Quero levar minha equipe", []).rota, null);
});

test("equipe como destino já representa múltiplos participantes corporativos", () => {
  assert.equal(
    rotaComercialRapida("Quero comprar ingressos para minha equipe", []).rota,
    "summit_b2b",
  );
});

test("quantidade de gestores da empresa é B2B quando o assunto é ingresso", () => {
  assert.equal(
    rotaComercialRapida("Quero 5 ingressos para gestores da empresa", []).rota,
    "summit_b2b",
  );
});

test("quantidade de gestores sem dizer a quê vai ao Router", () => {
  assert.equal(
    rotaComercialRapida("Quero levar 5 gestores da empresa", []).rota,
    null,
  );
});

test("compra para si e para a equipe continua B2B quando há múltiplos corporativos", () => {
  assert.equal(
    rotaComercialRapida("Quero 5 ingressos para mim e minha equipe", []).rota,
    "summit_b2b",
  );
});

test("follow-up curto preserva intenção corporativa do histórico", () => {
  assert.equal(rotaComercialRapida("Quero", [
    { papel: "lead", conteudo: "Preciso de 10 ingressos para minha empresa" },
  ]).rota, "summit_b2b");
});

test("compra individual atual vence intenção B2B do histórico", () => {
  assert.equal(rotaComercialRapida("Agora quero somente um para mim", [
    { papel: "lead", conteudo: "Preciso de 10 ingressos para minha empresa" },
  ]).rota, "summit_b2c");
});

test("patrocínio segue como demanda B2B própria", () => {
  assert.equal(
    rotaComercialRapida("Quero conversar sobre patrocínio", []).rota,
    "summit_b2b",
  );
});

test("suporte explícito continua no Router universal", () => {
  assert.equal(
    rotaComercialRapida("Já comprei 5 ingressos para a empresa e não consigo acessar", []).rota,
    null,
  );
});
