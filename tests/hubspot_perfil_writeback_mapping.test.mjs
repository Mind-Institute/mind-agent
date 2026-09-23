import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  chave,
  chaveEmpresa,
  montarOpcoes,
  planejar,
  PROPRIEDADES_LIDAS,
  unirJtbd,
} from "../supabase/functions/hubspot-perfil-writeback/mapping.ts";

// ------------------------------------------------------------------ fixtures
const ICP_ANTIGOS = [
  "CHRO / VP de Pessoas",
  "CEO / C-Suite",
  "Gestor / Middle Manager",
  "People Leader / Business Partner",
  "Executivo Sênior / Alto Performer",
  "Consultor / Coach / Psicólogo",
];

const defs = {
  email: { name: "email", type: "string", fieldType: "text", options: [] },
  jobtitle: { name: "jobtitle", type: "string", fieldType: "text", options: [] },
  company: { name: "company", type: "string", fieldType: "text", options: [] },
  icp: {
    name: "icp", type: "enumeration", fieldType: "select",
    options: [
      ...ICP_ANTIGOS.map((v, i) => ({ value: v, label: v, displayOrder: i + 1 })),
      { value: "gestor_rh", label: "Gestor de RH", displayOrder: 7 },
      { value: "analista_bp_rh", label: "Analista / BP de RH", displayOrder: 8 },
    ],
  },
  icp_confianca: { name: "icp_confianca", type: "number", fieldType: "number", options: [] },
  jtbd: {
    name: "jtbd", type: "enumeration", fieldType: "checkbox",
    options: [
      { value: "engajar_lideres", label: "Engajar líderes no cuidado", displayOrder: 3 },
      { value: "nr1_mensuracao", label: "Cumprir a NR-1 com mensuração e dados", displayOrder: 9 },
      { value: "reduzir_afastamentos", label: "Reduzir afastamentos", displayOrder: 12 },
    ],
  },
};

const MIND_ID = "11111111-2222-4333-8444-555555555555";

function linha(extra = {}) {
  return {
    mind_id: MIND_ID,
    hubspot_id: "501",
    email: "ada@example.com",
    jobtitle: null,
    company: null,
    icp: null,
    icp_confianca: null,
    jtbd: [],
    fontes: { cargo: "credenciamento" },
    ...extra,
  };
}

function contato(properties = {}) {
  return { id: "501", properties: { email: "ada@example.com", ...properties } };
}

// --------------------------------------------------------------------- chave
test("chave de empresa ignora sufixo jurídico, país e artigo/grupo inicial", () => {
  assert.equal(chaveEmpresa("Vale S.A."), chaveEmpresa("VALE SA"));
  assert.equal(chaveEmpresa("VALE SA"), chaveEmpresa("vale"));
  assert.equal(chaveEmpresa("Vale S.A."), "vale");
  assert.equal(chaveEmpresa("Heineken Brasil"), chaveEmpresa("heineken"));
  assert.equal(chaveEmpresa("Grupo Boticário"), chaveEmpresa("O Boticario"));
  assert.equal(chaveEmpresa("Banco do Brasil S/A"), "banco");
  assert.equal(chaveEmpresa("Natura &Co"), chaveEmpresa("Natura & Co Holding"));
});

test("chave de empresa não iguala empresas diferentes nem some com nome que é só sufixo", () => {
  assert.notEqual(chaveEmpresa("BDF NIVEA"), chaveEmpresa("Beiersdorf"));
  assert.notEqual(chaveEmpresa("Vale"), chaveEmpresa("Valeo"));
  assert.equal(chaveEmpresa("Brasil"), "brasil");
  assert.equal(chaveEmpresa("SA"), "sa");
  assert.equal(chaveEmpresa(""), "");
  assert.equal(chaveEmpresa(null), "");
});

test("chave de cargo normaliza acento, caixa e pontuação sem adivinhar palavras", () => {
  assert.equal(chave("Gerente de RH"), chave("gerente de rh"));
  assert.equal(chave("Gerente de RH"), "gerente de rh");
  assert.notEqual(chave("Gerente RH"), chave("Gerente de RH"));
  assert.equal(chave("Coordenação de P&D"), "coordenacao de p e d");
  assert.equal(chave("  CHRO / VP  de Pessoas "), "chro vp de pessoas");
  assert.equal(chave("Gerente de RH"), chaveEmpresa("Gerente de RH"));
});

// ------------------------------------------------------------------ planejar
test("propriedades lidas são exatamente as do perfil", () => {
  assert.deepEqual(PROPRIEDADES_LIDAS, ["email", "jobtitle", "company", "icp", "icp_confianca", "jtbd"]);
});

test("contato ausente é pulado: esta função não cria contatos", () => {
  const d = planejar(linha({ jobtitle: "Gerente de RH" }), null, defs);
  assert.equal(d.acao, "pular");
  assert.equal(d.motivo, "sem_contato");
  assert.deepEqual(d.propriedades, {});
  assert.equal(d.mind_id, MIND_ID);
  assert.equal(d.email, "ada@example.com");

  const semId = planejar(linha({ hubspot_id: null, email: null }), null, defs);
  assert.equal(semId.acao, "pular");
  assert.equal(semId.motivo, "sem_identificador");
});

test("cargo vazio no HubSpot recebe o desejado, sem substituição", () => {
  const d = planejar(linha({ jobtitle: "Gerente de RH" }), contato({ jobtitle: "" }), defs);
  assert.equal(d.acao, "atualizar");
  assert.equal(d.id, "501");
  assert.deepEqual(d.propriedades, { jobtitle: "Gerente de RH" });
  assert.deepEqual(d.substituicoes, []);
  assert.deepEqual(d.conflitos, []);
});

test("cargo equivalente (mesma coisa escrita de outro jeito) não é reescrito", () => {
  const d = planejar(linha({ jobtitle: "Gerente de RH" }), contato({ jobtitle: "gerente de rh" }), defs);
  assert.equal(d.acao, "nada");
  assert.deepEqual(d.propriedades, {});
  assert.deepEqual(d.substituicoes, []);
});

test("cargo diferente é atualizado e registrado em substituicoes para a Adriana rever", () => {
  const d = planejar(linha({ jobtitle: "Gerente de RH" }), contato({ jobtitle: "Analista de RH" }), defs);
  assert.equal(d.acao, "atualizar");
  assert.deepEqual(d.propriedades, { jobtitle: "Gerente de RH" });
  assert.deepEqual(d.substituicoes, [{
    email: "ada@example.com", propriedade: "jobtitle", atual: "Analista de RH", novo: "Gerente de RH",
  }]);
  assert.deepEqual(d.conflitos, []);
});

test("empresa usa a chave de empresa: grafia jurídica não duplica, empresa diferente substitui", () => {
  const igual = planejar(linha({ company: "Vale S.A." }), contato({ company: "VALE SA" }), defs);
  assert.equal(igual.acao, "nada");
  assert.deepEqual(igual.substituicoes, []);

  const grupo = planejar(linha({ company: "O Boticario" }), contato({ company: "Grupo Boticário" }), defs);
  assert.equal(grupo.acao, "nada");

  const troca = planejar(linha({ company: "Beiersdorf" }), contato({ company: "BDF NIVEA" }), defs);
  assert.equal(troca.acao, "atualizar");
  assert.deepEqual(troca.propriedades, { company: "Beiersdorf" });
  assert.deepEqual(troca.substituicoes, [{
    email: "ada@example.com", propriedade: "company", atual: "BDF NIVEA", novo: "Beiersdorf",
  }]);

  const vazio = planejar(linha({ company: "Heineken" }), contato({}), defs);
  assert.deepEqual(vazio.propriedades, { company: "Heineken" });
});

test("cargo e empresa nulos no plano não escrevem nada", () => {
  const d = planejar(linha(), contato({ jobtitle: "CHRO", company: "Mind" }), defs);
  assert.equal(d.acao, "nada");
  assert.deepEqual(d.propriedades, {});
});

test("ICP preenche só o vazio e leva icp_confianca junto", () => {
  const d = planejar(linha({ icp: "gestor_rh", icp_confianca: 8 }), contato({ icp: "" }), defs);
  assert.equal(d.acao, "atualizar");
  assert.deepEqual(d.propriedades, { icp: "gestor_rh", icp_confianca: "8" });
  assert.deepEqual(d.conflitos, []);

  const semConfianca = planejar(linha({ icp: "gestor_rh", icp_confianca: null }), contato({}), defs);
  assert.deepEqual(semConfianca.propriedades, { icp: "gestor_rh" });
});

test("ICP já preenchido no HubSpot nunca é sobrescrito: diferença vira conflito", () => {
  const d = planejar(linha({ icp: "gestor_rh", icp_confianca: 9 }), contato({ icp: "CEO / C-Suite" }), defs);
  assert.equal(d.acao, "nada");
  assert.deepEqual(d.propriedades, {});
  assert.deepEqual(d.conflitos, [{
    email: "ada@example.com", propriedade: "icp", atual: "CEO / C-Suite", desejado: "gestor_rh",
  }]);

  const igual = planejar(linha({ icp: "gestor_rh", icp_confianca: 9 }), contato({ icp: "gestor_rh" }), defs);
  assert.equal(igual.acao, "nada");
  assert.deepEqual(igual.conflitos, []);
  assert.deepEqual(igual.propriedades, {});
});

test("ICP fora da lista de opções vai para ignorados e não é escrito", () => {
  const d = planejar(linha({ icp: "marciano", icp_confianca: 10 }), contato({}), defs);
  assert.equal(d.acao, "nada");
  assert.deepEqual(d.propriedades, {});
  assert.deepEqual(d.ignorados, [{
    email: "ada@example.com", propriedade: "icp", valor: "marciano", motivo: "valor_fora_da_lista",
  }]);
});

test("ICP aceita a opção com a grafia do HubSpot (caixa) e sem icp_confianca no HubSpot só ignora a confiança", () => {
  const caixa = planejar(linha({ icp: "GESTOR_RH" }), contato({}), defs);
  assert.deepEqual(caixa.propriedades, { icp: "gestor_rh" });

  const { icp_confianca: _, ...semConfianca } = defs;
  const d = planejar(linha({ icp: "gestor_rh", icp_confianca: 7 }), contato({}), semConfianca);
  assert.deepEqual(d.propriedades, { icp: "gestor_rh" });
  assert.deepEqual(d.ignorados, [{
    email: "ada@example.com", propriedade: "icp_confianca", valor: "7", motivo: "propriedade_inexistente",
  }]);
});

test("JTBD escreve a união na ordem do catálogo", () => {
  const d = planejar(linha({ jtbd: ["nr1_mensuracao"] }), contato({ jtbd: "reduzir_afastamentos;engajar_lideres" }), defs);
  assert.equal(d.acao, "atualizar");
  assert.deepEqual(d.propriedades, { jtbd: "engajar_lideres;nr1_mensuracao;reduzir_afastamentos" });

  const vazio = planejar(linha({ jtbd: ["reduzir_afastamentos", "engajar_lideres"] }), contato({}), defs);
  assert.deepEqual(vazio.propriedades, { jtbd: "engajar_lideres;reduzir_afastamentos" });
});

test("JTBD não reescreve quando o conjunto já é o mesmo", () => {
  const d = planejar(
    linha({ jtbd: ["engajar_lideres", "nr1_mensuracao"] }),
    contato({ jtbd: "nr1_mensuracao;engajar_lideres" }),
    defs,
  );
  assert.equal(d.acao, "nada");
  assert.deepEqual(d.propriedades, {});

  const subconjunto = planejar(linha({ jtbd: ["engajar_lideres"] }), contato({ jtbd: "nr1_mensuracao;engajar_lideres" }), defs);
  assert.equal(subconjunto.acao, "nada");
});

test("JTBD preserva valor que o contato já tem mesmo fora da lista atual", () => {
  assert.deepEqual(
    unirJtbd(["legado_x", "engajar_lideres"], ["nr1_mensuracao"], defs.jtbd),
    ["engajar_lideres", "nr1_mensuracao", "legado_x"],
  );
  const d = planejar(linha({ jtbd: ["nr1_mensuracao"] }), contato({ jtbd: "legado_x" }), defs);
  assert.deepEqual(d.propriedades, { jtbd: "nr1_mensuracao;legado_x" });
});

test("valor de JTBD fora da lista vai para ignorados; os válidos seguem", () => {
  const d = planejar(linha({ jtbd: ["inexistente", "nr1_mensuracao"] }), contato({}), defs);
  assert.deepEqual(d.propriedades, { jtbd: "nr1_mensuracao" });
  assert.deepEqual(d.ignorados, [{
    email: "ada@example.com", propriedade: "jtbd", valor: "inexistente", motivo: "valor_fora_da_lista",
  }]);

  const soInvalido = planejar(linha({ jtbd: ["inexistente"] }), contato({}), defs);
  assert.equal(soInvalido.acao, "nada");
  assert.deepEqual(soInvalido.propriedades, {});
});

test("sem a propriedade jtbd no HubSpot nada de JTBD é escrito", () => {
  const { jtbd: _, ...semJtbd } = defs;
  const d = planejar(linha({ jtbd: ["nr1_mensuracao"], jobtitle: "CHRO" }), contato({}), semJtbd);
  assert.equal(d.acao, "atualizar");
  assert.deepEqual(d.propriedades, { jobtitle: "CHRO" });
  assert.equal(d.propriedades.jtbd, undefined);
  assert.deepEqual(d.ignorados, [{
    email: "ada@example.com", propriedade: "jtbd", valor: "nr1_mensuracao", motivo: "propriedade_inexistente",
  }]);
});

test("decisão completa combina as quatro propriedades numa só escrita", () => {
  const d = planejar(
    linha({ jobtitle: "Gerente de RH", company: "Vale S.A.", icp: "gestor_rh", icp_confianca: 8, jtbd: ["nr1_mensuracao"] }),
    contato({ jobtitle: "Analista de RH", company: "VALE SA", icp: "", jtbd: "engajar_lideres" }),
    defs,
  );
  assert.equal(d.acao, "atualizar");
  assert.deepEqual(d.propriedades, {
    jobtitle: "Gerente de RH",
    icp: "gestor_rh",
    icp_confianca: "8",
    jtbd: "engajar_lideres;nr1_mensuracao",
  });
  assert.equal(d.substituicoes.length, 1);
  assert.equal(d.substituicoes[0].propriedade, "jobtitle");
});

// -------------------------------------------------------------- montarOpcoes
const OPCOES_ATUAIS = ICP_ANTIGOS.map((v, i) => ({ value: v, label: v, displayOrder: i, hidden: false }));

const CATALOGO_ICP = [
  { codigo: "chro_vp_diretor_rh", rotulo: "CHRO / VP / Diretor de RH", hubspot_valor: "CHRO / VP de Pessoas", ordem: 1, descricao: "..." },
  { codigo: "gestor_rh", rotulo: "Gestor de RH", hubspot_valor: "gestor_rh", ordem: 2, descricao: "..." },
  { codigo: "ceo_fundador_csuite", rotulo: "CEO / C-Suite", hubspot_valor: "CEO / C-Suite", ordem: 3, descricao: "..." },
];

test("montarOpcoes mantém opções desconhecidas, renomeia as conhecidas e acrescenta as novas", () => {
  const { opcoes, diff, mudou } = montarOpcoes(OPCOES_ATUAIS, CATALOGO_ICP);
  assert.equal(mudou, true);

  const valores = opcoes.map((o) => o.value);
  for (const antigo of ICP_ANTIGOS) assert.ok(valores.includes(antigo), `${antigo} foi apagada`);
  assert.ok(valores.includes("gestor_rh"));
  assert.equal(opcoes.length, ICP_ANTIGOS.length + 1);

  assert.deepEqual(diff.renomeadas, [{ value: "CHRO / VP de Pessoas", de: "CHRO / VP de Pessoas", para: "CHRO / VP / Diretor de RH" }]);
  assert.deepEqual(diff.acrescentadas, [{ value: "gestor_rh", label: "Gestor de RH" }]);
  assert.deepEqual(
    [...diff.mantidas].sort(),
    ICP_ANTIGOS.filter((v) => v !== "CHRO / VP de Pessoas" && v !== "CEO / C-Suite").sort(),
  );
  assert.deepEqual(diff.reordenadas.map((r) => r.value).sort(), ["CEO / C-Suite", "CHRO / VP de Pessoas"].sort());

  const chro = opcoes.find((o) => o.value === "CHRO / VP de Pessoas");
  assert.deepEqual(chro, { value: "CHRO / VP de Pessoas", label: "CHRO / VP / Diretor de RH", displayOrder: 1, hidden: false });
  const gestor = opcoes.find((o) => o.value === "gestor_rh");
  assert.deepEqual(gestor, { value: "gestor_rh", label: "Gestor de RH", displayOrder: 2, hidden: false });
  const desconhecida = opcoes.find((o) => o.value === "Gestor / Middle Manager");
  assert.deepEqual(desconhecida, { value: "Gestor / Middle Manager", label: "Gestor / Middle Manager", displayOrder: 2, hidden: false });
});

test("montarOpcoes ordena por ordem do catálogo e deixa sem-ordem no fim", () => {
  const atuais = [
    { value: "z_sem_ordem", label: "Z", displayOrder: -1 },
    { value: "b", label: "B", displayOrder: 5 },
  ];
  const catalogo = [
    { codigo: "c", rotulo: "C", hubspot_valor: "c", ordem: 3 },
    { codigo: "a", rotulo: "A", hubspot_valor: "a", ordem: 1 },
  ];
  const { opcoes } = montarOpcoes(atuais, catalogo);
  assert.deepEqual(opcoes.map((o) => o.value), ["a", "c", "b", "z_sem_ordem"]);
});

test("montarOpcoes sem diferença não pede PATCH", () => {
  const atuais = CATALOGO_ICP.map((i) => ({ value: i.hubspot_valor, label: i.rotulo, displayOrder: i.ordem, hidden: false }));
  const { diff, mudou } = montarOpcoes(atuais, CATALOGO_ICP);
  assert.equal(mudou, false);
  assert.deepEqual(diff.renomeadas, []);
  assert.deepEqual(diff.acrescentadas, []);
  assert.deepEqual(diff.reordenadas, []);
  assert.deepEqual([...diff.mantidas].sort(), CATALOGO_ICP.map((i) => i.hubspot_valor).sort());
});

test("montarOpcoes usa o codigo quando falta hubspot_valor e parte do zero para propriedade nova", () => {
  const { opcoes, diff, mudou } = montarOpcoes([], [
    { codigo: "nr1_mensuracao", rotulo: "Cumprir a NR-1 com mensuração e dados", ordem: 9 },
    { codigo: "engajar_lideres", rotulo: "Engajar líderes", hubspot_valor: "engajar_lideres", ordem: 3 },
  ]);
  assert.equal(mudou, true);
  assert.deepEqual(opcoes, [
    { value: "engajar_lideres", label: "Engajar líderes", displayOrder: 3, hidden: false },
    { value: "nr1_mensuracao", label: "Cumprir a NR-1 com mensuração e dados", displayOrder: 9, hidden: false },
  ]);
  assert.equal(diff.acrescentadas.length, 2);
  assert.deepEqual(diff.mantidas, []);
});

// --------------------------------------------------------------- runtime (index.ts)
test("runtime segue a irmã: token da analise_config, ensaio por padrão, não cria contato, nomeia escopo faltando", () => {
  const index = readFileSync(
    new URL("../supabase/functions/hubspot-perfil-writeback/index.ts", import.meta.url),
    "utf8",
  );
  assert.match(index, /db\.rpc\("analise_config"\)/);
  assert.match(index, /corpo\.executar === true/);
  assert.match(index, /ORCAMENTO_MS = 110_000/);
  assert.match(index, /rpc\("mind_hubspot_perfil_plano"\)/);
  assert.match(index, /rpc\("mind_hubspot_perfil_definicoes"\)/);
  assert.match(index, /crm\.schemas\.contacts\.write/);
  assert.match(index, /escopo_faltando/);
  assert.match(index, /sem_contato|planejar/);
  assert.match(index, /batch\/update/);
  assert.doesNotMatch(index, /batch\/create/);
  assert.doesNotMatch(index, /"\/crm\/v3\/objects\/contacts",\s*\{\s*method:\s*"POST"/);
  assert.match(index, /fieldType: "checkbox"/);
  assert.match(index, /idProperty: "email"/);
});


// ---- guarda de typo / duplicata (Adriana, 23/09): mesma coisa escrita de outro jeito não é reescrita
import { equivalente, distancia } from "../supabase/functions/hubspot-perfil-writeback/mapping.ts";

test("equivalente: typo provável, contenção e coisa diferente", () => {
  assert.equal(distancia("beiersdorf", "beiwrsdorf"), 1);
  assert.equal(equivalente("beiersdorf", "beiwrsdorf"), "typo_provavel");
  assert.equal(equivalente("ceo fundador", "ceo"), "uma_contem_a_outra");
  assert.equal(equivalente("localiza e co", "localiza"), "uma_contem_a_outra");
  assert.equal(equivalente("gerente de rh", "gerente de rh"), "mesma_chave");
  assert.equal(equivalente("board member", "empreendedor"), null);
  assert.equal(equivalente("hr business partner", "gerente de saude e bem estar mental"), null);
  assert.equal(equivalente("sa", "me"), null); // chaves curtas nunca são "typo"
});

test("planejar: typo e contenção ficam em equivalentes, sem escrever; troca real escreve", () => {
  const defs = { jobtitle: { name: "jobtitle", type: "string", fieldType: "text", options: [] }, company: { name: "company", type: "string", fieldType: "text", options: [] } };
  const linha = { mind_id: "m", hubspot_id: "1", email: "a@b.c", jobtitle: "CEO", company: "Beiwrsdorf", icp: null, icp_confianca: null, jtbd: [] };
  const atual = { id: "1", properties: { email: "a@b.c", jobtitle: "CEO / Fundador", company: "Beiersdorf" } };
  const d = planejar(linha, atual, defs);
  assert.equal(d.acao, "nada");
  assert.deepEqual(d.propriedades, {});
  assert.equal(d.equivalentes.length, 2);
  assert.equal(d.equivalentes.find((q) => q.propriedade === "company").motivo, "typo_provavel");
  assert.equal(d.equivalentes.find((q) => q.propriedade === "jobtitle").motivo, "uma_contem_a_outra");
  const d2 = planejar({ ...linha, jobtitle: "Empreendedor", company: "Dna Treinamentos" }, { id: "1", properties: { email: "a@b.c", jobtitle: "Board Member", company: "Kilson e Albuquerque Treinamentos ltda" } }, defs);
  assert.equal(d2.acao, "atualizar");
  assert.deepEqual(d2.propriedades, { jobtitle: "Empreendedor", company: "Dna Treinamentos" });
  assert.equal(d2.substituicoes.length, 2);
});
