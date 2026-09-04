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

test("múltiplos ingressos tornam a oportunidade B2B", () => {
  assert.equal(rotaComercialRapida("Quero 5 ingressos", []).rota, "summit_b2b");
});

test("intenção explícita de levar a equipe torna a oportunidade B2B", () => {
  assert.equal(rotaComercialRapida("Quero levar minha equipe", []).rota, "summit_b2b");
});

test("follow-up curto preserva intenção corporativa do histórico", () => {
  assert.equal(rotaComercialRapida("Quero", [
    { papel: "lead", conteudo: "Preciso de 10 ingressos para minha empresa" },
  ]).rota, "summit_b2b");
});

test("suporte explícito continua no Router universal", () => {
  assert.equal(rotaComercialRapida("Já comprei e meu ingresso não aparece", []).rota, null);
});
