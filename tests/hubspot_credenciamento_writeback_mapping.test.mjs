import assert from "node:assert/strict";
import test from "node:test";
import {
  ANO,
  planejar,
  STATUS_REEMBOLSO,
  valoresDesejados,
} from "../supabase/functions/hubspot-credenciamento-writeback/mapping.ts";

// Definições como o HubSpot devolve: enumerações com opções; checkbox = várias.
const opcoes = (...v) => v.map((value) => ({ value, label: value }));
const DEFS = {
  email: { name: "email", type: "string", fieldType: "text", options: [] },
  firstname: { name: "firstname", type: "string", fieldType: "text", options: [] },
  lastname: { name: "lastname", type: "string", fieldType: "text", options: [] },
  phone: { name: "phone", type: "string", fieldType: "phonenumber", options: [] },
  mobilephone: { name: "mobilephone", type: "string", fieldType: "phonenumber", options: [] },
  hs_whatsapp_phone_number: { name: "hs_whatsapp_phone_number", type: "string", fieldType: "text", options: [] },
  cpf: { name: "cpf", type: "string", fieldType: "text", options: [] },
  summit__categoria_2026: { name: "summit__categoria_2026", type: "enumeration", fieldType: "checkbox", options: opcoes("Prime", "VIP", "Mind", "Camarote") },
  summit__tipo_entrada_2026: { name: "summit__tipo_entrada_2026", type: "enumeration", fieldType: "checkbox", options: opcoes("Pago", "Cortesia", "Bonus | Ingresso incluido em oferta", "Patrocínio") },
  summit__instituicao_2026: { name: "summit__instituicao_2026", type: "enumeration", fieldType: "select", options: opcoes("Mind", "Heineken", "Chilli Beans", "Beneficencia Portuguesa", "Outra") },
  summit__lote_2026: { name: "summit__lote_2026", type: "enumeration", fieldType: "select", options: opcoes("Lote 1", "Lote 2", "Lote 6") },
  summit__papel_2026: { name: "summit__papel_2026", type: "enumeration", fieldType: "checkbox", options: opcoes("Pagante", "Participante") },
  summit__participacao_anual: { name: "summit__participacao_anual", type: "enumeration", fieldType: "checkbox", options: opcoes("2024", "2025", "2026") },
  summit__cortesia_anos: { name: "summit__cortesia_anos", type: "enumeration", fieldType: "checkbox", options: opcoes("2025", "2026") },
  summit__patrocinio_anos: { name: "summit__patrocinio_anos", type: "enumeration", fieldType: "checkbox", options: opcoes("2025", "2026") },
  status_summit_2026: { name: "status_summit_2026", type: "enumeration", fieldType: "select", options: opcoes("Comprou", "Cortesia", STATUS_REEMBOLSO) },
};

const linha = (extra = {}) => ({
  email: "ada@example.com",
  primeiro_nome: "Ada",
  sobrenome: "Lovelace",
  telefone: "+5511999990000",
  cpf: "12345678901",
  categorias: ["VIP"],
  origens: ["Pago"],
  lotes: ["Lote 1"],
  instituicoes: [],
  pagante: true,
  participante: true,
  cortesia: false,
  patrocinio: false,
  reembolsado: false,
  reembolso_nao_confirmado: false,
  so_por_terceiro: false,
  linhas_ativas: 1,
  linhas_revogadas: 0,
  ...extra,
});

test("contato novo nasce com e-mail, nome e tudo que o credenciamento sabe", () => {
  const d = planejar(linha(), null, DEFS);
  assert.equal(d.acao, "criar");
  assert.deepEqual(d.propriedades, {
    email: "ada@example.com",
    firstname: "Ada",
    lastname: "Lovelace",
    phone: "+5511999990000",
    mobilephone: "+5511999990000",
    hs_whatsapp_phone_number: "+5511999990000",
    cpf: "12345678901",
    summit__categoria_2026: "VIP",
    summit__tipo_entrada_2026: "Pago",
    summit__lote_2026: "Lote 1",
    summit__papel_2026: "Pagante;Participante",
    summit__participacao_anual: ANO,
  });
  assert.deepEqual(d.conflitos, []);
});

test("contato existente: só o que está vazio é escrito; nome nunca é tocado", () => {
  const atual = {
    id: "77",
    properties: {
      email: "ADA@example.com",
      firstname: "Adah",
      lastname: null,
      phone: "+55 (11) 99999-0000",
      mobilephone: "",
      hs_whatsapp_phone_number: null,
      summit__categoria_2026: "VIP",
      summit__tipo_entrada_2026: "Pago",
      summit__papel_2026: "Pagante;Participante",
      summit__participacao_anual: "2025",
    },
  };
  const d = planejar(linha(), atual, DEFS);
  assert.equal(d.acao, "atualizar");
  assert.equal(d.id, "77");
  assert.deepEqual(d.propriedades, {
    mobilephone: "+5511999990000",
    hs_whatsapp_phone_number: "+5511999990000",
    cpf: "12345678901",
    summit__lote_2026: "Lote 1",
    summit__participacao_anual: "2025;2026",
  });
  assert.equal("firstname" in d.propriedades, false, "nome só em contato novo");
  assert.equal("lastname" in d.propriedades, false, "sobrenome vazio no HubSpot não é preenchido em contato existente");
  assert.deepEqual(d.conflitos, [], "telefone igual com formatação diferente não é conflito");
});

test("valor diferente já gravado vira conflito, nunca escrita", () => {
  const atual = {
    id: "1",
    properties: {
      phone: "+5511888880000",
      summit__categoria_2026: "Mind",
      summit__papel_2026: "Participante",
      summit__lote_2026: "Lote 6",
      summit__participacao_anual: "2026",
    },
  };
  const d = planejar(linha(), atual, DEFS);
  assert.deepEqual(d.propriedades, {
    mobilephone: "+5511999990000",
    hs_whatsapp_phone_number: "+5511999990000",
    cpf: "12345678901",
    summit__tipo_entrada_2026: "Pago",
  });
  const props = d.conflitos.map((c) => c.propriedade).sort();
  assert.deepEqual(props, ["phone", "summit__categoria_2026", "summit__lote_2026", "summit__papel_2026"]);
  assert.equal(d.conflitos.find((c) => c.propriedade === "summit__papel_2026").atual, "Participante");
});

test("anos acumulam: 2026 entra sem tirar 2025; se já tem 2026, nada", () => {
  const l = linha({ origens: ["Cortesia"], cortesia: true, pagante: false });
  const d = planejar(l, { id: "1", properties: { summit__cortesia_anos: "2025", summit__participacao_anual: "2024;2026" } }, DEFS);
  assert.equal(d.propriedades.summit__cortesia_anos, "2025;2026");
  assert.equal("summit__participacao_anual" in d.propriedades, false);
});

test("origens fora do vocabulário do HubSpot seguem o precedente do CRM: Cortesia", () => {
  const d = valoresDesejados(linha({ origens: ["Imprensa", "Palestrante"], pagante: false }), DEFS, []);
  assert.equal(d.summit__tipo_entrada_2026, "Cortesia");
  assert.equal(d.summit__papel_2026, "Participante");
});

test("instituição: apelido casa com a lista; desconhecida é ignorada com motivo", () => {
  const ignorados = [];
  const d = valoresDesejados(linha({ instituicoes: ["Chillibeans"], origens: ["Patrocínio"], patrocinio: true, pagante: false }), DEFS, ignorados);
  assert.equal(d.summit__instituicao_2026, "Chilli Beans");
  assert.equal(d.summit__patrocinio_anos, ANO);
  assert.deepEqual(ignorados, []);

  const ignorados2 = [];
  const d2 = valoresDesejados(linha({ instituicoes: ["Bluma"] }), DEFS, ignorados2);
  assert.equal("summit__instituicao_2026" in d2, false);
  assert.deepEqual(ignorados2, [{ email: "ada@example.com", propriedade: "summit__instituicao_2026", valor: "Bluma", motivo: "valor_fora_da_lista" }]);
});

test("checkbox junta várias; select fica com a primeira (a mais recente)", () => {
  const d = valoresDesejados(linha({ categorias: ["Mind", "VIP"], lotes: ["Lote 6", "Lote 1"] }), DEFS, []);
  assert.equal(d.summit__categoria_2026, "Mind;VIP");
  assert.equal(d.summit__lote_2026, "Lote 6");
});

test("inscrito por terceiro chega sem telefone e CPF, e nada disso é escrito", () => {
  const d = planejar(linha({ telefone: null, cpf: null, so_por_terceiro: true, pagante: false }), null, DEFS);
  assert.equal("phone" in d.propriedades, false);
  assert.equal("cpf" in d.propriedades, false);
  assert.equal(d.propriedades.summit__papel_2026, "Participante");
});

test("reembolso confirmado: só o estágio muda, e a troca é declarada", () => {
  const l = linha({ participante: false, reembolsado: true, categorias: [], origens: [], lotes: [], pagante: false });
  const d = planejar(l, { id: "9", properties: { status_summit_2026: "Comprou", summit__participacao_anual: "2025" } }, DEFS);
  assert.deepEqual(d.propriedades, { status_summit_2026: STATUS_REEMBOLSO });
  assert.deepEqual(d.substituicoes, [{ email: "ada@example.com", propriedade: "status_summit_2026", atual: "Comprou", novo: STATUS_REEMBOLSO }]);
  assert.equal("summit__participacao_anual" in d.propriedades, false, "quem só tem ingresso reembolsado não participou");

  const semContato = planejar(l, null, DEFS);
  assert.equal(semContato.acao, "pular");
  assert.equal(semContato.motivo, "reembolso_sem_contato");
});

test("nada a fazer quando o HubSpot já tem tudo", () => {
  const atual = {
    id: "3",
    properties: {
      phone: "5511999990000", mobilephone: "+5511999990000", hs_whatsapp_phone_number: "+5511999990000", cpf: "123.456.789-01",
      summit__categoria_2026: "VIP", summit__tipo_entrada_2026: "Pago", summit__lote_2026: "Lote 1",
      summit__papel_2026: "Participante;Pagante", summit__participacao_anual: "2025;2026",
    },
  };
  const d = planejar(linha(), atual, DEFS);
  assert.equal(d.acao, "nada");
  assert.deepEqual(d.conflitos, []);
});

test("propriedade que não existe no portal nunca é enviada", () => {
  const defs = { ...DEFS };
  delete defs.summit__lote_2026;
  const ignorados = [];
  const d = valoresDesejados(linha(), defs, ignorados);
  assert.equal("summit__lote_2026" in d, false);
  assert.equal(ignorados[0].motivo, "propriedade_inexistente");
});
