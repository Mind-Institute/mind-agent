import test from "node:test";
import assert from "node:assert/strict";
import { rotaComercialRapida } from "../supabase/functions/_shared/treble-commercial-route.ts";

test("cargo de gestora continua B2C", () => {
  assert.deepEqual(rotaComercialRapida("Sou gestora", []), {
    rota: "summit_b2c", motivo: "b2c_padrao_comercial",
  });
});

test("empresa conhecida não transforma compra individual em B2B", () => {
  assert.equal(rotaComercialRapida("Quero comprar um ingresso", [
    { papel: "lead", conteudo: "Trabalho na Natura como diretora" },
  ]).rota, "summit_b2c");
});

test("negação corporativa corrige histórico B2B", () => {
  assert.equal(rotaComercialRapida("Não é uma compra corporativa", [
    { papel: "lead", conteudo: "Sou gestora" },
    { papel: "agente", conteudo: "Compra corporativa?" },
  ]).rota, "summit_b2c");
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

test("intenção explícita de levar a equipe torna a oportunidade B2B", () => {
  assert.equal(rotaComercialRapida("Quero levar minha equipe", []).rota, "summit_b2b");
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
