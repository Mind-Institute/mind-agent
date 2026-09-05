import test from "node:test";
import assert from "node:assert/strict";
import {
  mensagemComercialDiretaSemLupa,
  pedidoCondicaoSemCategoria,
  rotaComercialRapida,
} from "../supabase/functions/_shared/treble-commercial-route.ts";

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

test("equipe como destino já representa múltiplos participantes corporativos", () => {
  assert.equal(
    rotaComercialRapida("Quero comprar ingressos para minha equipe", []).rota,
    "summit_b2b",
  );
});

test("quantidade de gestores da empresa é B2B", () => {
  assert.equal(
    rotaComercialRapida("Quero levar 5 gestores da empresa", []).rota,
    "summit_b2b",
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

test("follow-up reutiliza rota B2C ativa sem chamar Router", () => {
  assert.deepEqual(
    rotaComercialRapida("E o Prime?", [], "summit_b2c"),
    { rota: "summit_b2c", motivo: "rota_ativa" },
  );
});

test("follow-up reutiliza rota B2B ativa sem chamar Router", () => {
  assert.deepEqual(
    rotaComercialRapida("Qual é o valor?", [], "summit_b2b"),
    { rota: "summit_b2b", motivo: "rota_ativa" },
  );
});

test("intenção corporativa múltipla troca rota ativa de B2C para B2B", () => {
  assert.deepEqual(
    rotaComercialRapida("Agora quero 5 ingressos para minha empresa", [], "summit_b2c"),
    { rota: "summit_b2b", motivo: "b2b_empresa_multiplos" },
  );
});

test("compra individual explícita troca rota ativa de B2B para B2C", () => {
  assert.deepEqual(
    rotaComercialRapida("Agora quero somente um para mim", [], "summit_b2b"),
    { rota: "summit_b2c", motivo: "b2c_explicito" },
  );
});

test("cargo ou empresa isolados não tiram a conversa da rota B2C ativa", () => {
  assert.deepEqual(
    rotaComercialRapida("Sou diretora da Natura", [], "summit_b2c"),
    { rota: "summit_b2c", motivo: "rota_ativa" },
  );
});

test("suporte explícito vence rota comercial ativa", () => {
  assert.deepEqual(
    rotaComercialRapida("Meu pagamento não foi aprovado", [], "summit_b2c"),
    { rota: null, motivo: "router_necessario" },
  );
});

test("condição especial sem categoria pede somente a escolha do ingresso", () => {
  assert.equal(pedidoCondicaoSemCategoria("Quero saber da condição especial", []), true);
  assert.equal(pedidoCondicaoSemCategoria("Condição especial por favor", []), true);
  assert.equal(pedidoCondicaoSemCategoria("Tem condição especial para o VIP?", []), false);
  assert.equal(pedidoCondicaoSemCategoria("Qual a oferta?", [
    { papel: "lead", conteudo: "Quero o Prime" },
  ]), false);
});

test("turno comercial direto usa o Kit sem abrir lupa de Intelligence", () => {
  assert.equal(mensagemComercialDiretaSemLupa("Quero saber da condição especial"), true);
  assert.equal(mensagemComercialDiretaSemLupa("Quanto custa o VIP?"), true);
  assert.equal(mensagemComercialDiretaSemLupa("Quero o checkout do Prime"), true);
  assert.equal(mensagemComercialDiretaSemLupa("Qual a programação de palestrantes?"), false);
});
