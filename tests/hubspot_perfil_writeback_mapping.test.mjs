import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  chave,
  chaveEmpresa,
  montarOpcoes,
  planejar,
  PROPRIEDADES_LIDAS,
  PROPRIEDADES_PERFIL,
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
  mind_resumo_inteligencia: { name: "mind_resumo_inteligencia", type: "string", fieldType: "textarea", options: [] },
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
test("propriedades lidas são exatamente as do perfil, mais o resumo da inteligência", () => {
  assert.deepEqual(PROPRIEDADES_LIDAS, ["email", "jobtitle", "company", "icp", "icp_confianca", "jtbd", "mind_resumo_inteligencia"]);
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
  assert.match(index, /rpc\("mind_hubspot_perfil_plano", \{ p_desde: desde \?\? null \}\)/);
  assert.match(index, /rpc\("mind_hubspot_perfil_definicoes"\)/);
  assert.match(index, /rpc\("mind_hubspot_perfil_registrar", \{ p_itens: fatia, p_rotulo: rotulo \}\)/);
  assert.match(index, /REGISTRO_LOTE = 200/);
  assert.match(index, /hubspot-perfil-writeback \$\{executar \? "execucao" : "ensaio"\}/);
  assert.match(index, /if \(executar\) \{[\s\S]*registrador\(/); // só registra quando executa
  assert.match(index, /fieldType: "textarea"/);
  assert.match(index, /label: "Resumo da inteligência \(Mind\)"/);
  assert.match(index, /preservados: \{ total: preservados\.length, por_motivo: preservadosPorMotivo, lista: preservados\.slice\(0, 80\) \}/);
  assert.match(index, /registrados: registro/);
  assert.match(index, /desde_invalido/);
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
  assert.equal(d.equivalentes.find((q) => q.propriedade === "jobtitle").motivo, "novo_menos_especifico"); // "CEO" no lugar de "CEO / Fundador" empobrece
  const d2 = planejar({ ...linha, jobtitle: "Empreendedor", company: "Dna Treinamentos" }, { id: "1", properties: { email: "a@b.c", jobtitle: "Board Member", company: "Kilson e Albuquerque Treinamentos ltda" } }, defs);
  assert.equal(d2.acao, "atualizar");
  assert.deepEqual(d2.propriedades, { jobtitle: "Empreendedor", company: "Dna Treinamentos" });
  assert.equal(d2.substituicoes.length, 2);
});

// ---- guarda de "última escrita" (BACKLOG §21.1): o cron nunca desfaz uma edição humana feita no HubSpot depois da nossa
const RESUMO_A = "Cargo: Gerente de RH na Vale.\nICP: Gestor de RH (7/10).\nJobs: cumprir a NR-1 com dados.";
const RESUMO_B = "Cargo: Diretora de RH na Vale.\nICP: CHRO / Diretor de RH (7/10).\nJobs: engajar líderes no cuidado.";

test("cargo: valor atual é o que o Mind escreveu por último e o desejado mudou → escreve e vai para substituicoes", () => {
  const d = planejar(
    linha({ jobtitle: "Diretora de RH", ultimo_escrito: { jobtitle: "Gerente de RH" } }),
    contato({ jobtitle: "Gerente de RH" }),
    defs,
  );
  assert.equal(d.acao, "atualizar");
  assert.deepEqual(d.propriedades, { jobtitle: "Diretora de RH" });
  assert.deepEqual(d.substituicoes, [{ email: "ada@example.com", propriedade: "jobtitle", atual: "Gerente de RH", novo: "Diretora de RH" }]);
  assert.deepEqual(d.preservados, []);

  // a comparação é por chave: grafia/caixa diferente do que escrevemos ainda é "nosso"
  const caixa = planejar(
    linha({ jobtitle: "Diretora de RH", ultimo_escrito: { jobtitle: "Gerente de RH" } }),
    contato({ jobtitle: "gerente de rh" }),
    defs,
  );
  assert.deepEqual(caixa.propriedades, { jobtitle: "Diretora de RH" });

  // empresa usa a chave de empresa: "Vale" que virou "VALE SA" na tela continua sendo o que escrevemos
  const empresa = planejar(
    linha({ company: "Beiersdorf", ultimo_escrito: { company: "Vale" } }),
    contato({ company: "VALE SA" }),
    defs,
  );
  assert.deepEqual(empresa.propriedades, { company: "Beiersdorf" });
  assert.equal(empresa.substituicoes.length, 1);
  assert.deepEqual(empresa.preservados, []);
});

test("cargo: valor atual diferente do que o Mind escreveu por último foi editado no HubSpot → preservado, sem escrever", () => {
  const d = planejar(
    linha({ jobtitle: "Diretora de RH", ultimo_escrito: { jobtitle: "Gerente de RH" } }),
    contato({ jobtitle: "Head de Pessoas" }),
    defs,
  );
  assert.equal(d.acao, "nada");
  assert.deepEqual(d.propriedades, {});
  assert.deepEqual(d.substituicoes, []);
  assert.deepEqual(d.preservados, [{
    email: "ada@example.com", propriedade: "jobtitle", atual: "Head de Pessoas", desejado: "Diretora de RH", motivo: "editado_no_hubspot",
  }]);

  // o que já existe continua valendo antes da guarda: vazio escreve; equivalente ao desejado não escreve
  const vazio = planejar(linha({ jobtitle: "Diretora de RH", ultimo_escrito: { jobtitle: "Gerente de RH" } }), contato({ jobtitle: "" }), defs);
  assert.deepEqual(vazio.propriedades, { jobtitle: "Diretora de RH" });
  const equivalente = planejar(linha({ jobtitle: "Diretora de RH", ultimo_escrito: { jobtitle: "Gerente de RH" } }), contato({ jobtitle: "diretora de rh" }), defs);
  assert.equal(equivalente.acao, "nada");
  assert.deepEqual(equivalente.preservados, []);

  // a guarda é por propriedade: empresa nunca escrita segue a regra de sempre no mesmo contato
  const misto = planejar(
    linha({ jobtitle: "Diretora de RH", company: "Beiersdorf", ultimo_escrito: { jobtitle: "Gerente de RH" } }),
    contato({ jobtitle: "Head de Pessoas", company: "BDF NIVEA" }),
    defs,
  );
  assert.deepEqual(misto.propriedades, { company: "Beiersdorf" });
  assert.equal(misto.preservados.length, 1);
  assert.equal(misto.substituicoes.length, 1);
});

test("cargo: sem registro de última escrita, troca real escreve como antes", () => {
  for (const ultimo_escrito of [undefined, null, {}, { company: "Vale" }]) {
    const d = planejar(linha({ jobtitle: "Gerente de RH", ultimo_escrito }), contato({ jobtitle: "Analista de RH" }), defs);
    assert.equal(d.acao, "atualizar");
    assert.deepEqual(d.propriedades, { jobtitle: "Gerente de RH" });
    assert.equal(d.substituicoes.length, 1);
    assert.deepEqual(d.preservados, []);
  }
});

test("ICP: valor atual igual ao último escrito pelo Mind e classificação nova → escreve icp + icp_confianca e registra substituição; ICP manual continua conflito", () => {
  const nosso = planejar(
    linha({ icp: "analista_bp_rh", icp_confianca: 7, ultimo_escrito: { icp: "gestor_rh", icp_confianca: "7" } }),
    contato({ icp: "gestor_rh", icp_confianca: "7" }),
    defs,
  );
  assert.equal(nosso.acao, "atualizar");
  assert.deepEqual(nosso.propriedades, { icp: "analista_bp_rh", icp_confianca: "7" });
  assert.deepEqual(nosso.substituicoes, [{ email: "ada@example.com", propriedade: "icp", atual: "gestor_rh", novo: "analista_bp_rh" }]);
  assert.deepEqual(nosso.conflitos, []);

  // caixa não separa: o valor gravado pode voltar com outra grafia
  const caixa = planejar(linha({ icp: "analista_bp_rh", ultimo_escrito: { icp: "GESTOR_RH" } }), contato({ icp: "gestor_rh" }), defs);
  assert.deepEqual(caixa.propriedades, { icp: "analista_bp_rh" });

  // alguém trocou o ICP no HubSpot depois de nós: manual, não sobrescreve
  const manual = planejar(
    linha({ icp: "analista_bp_rh", icp_confianca: 7, ultimo_escrito: { icp: "gestor_rh" } }),
    contato({ icp: "CEO / C-Suite" }),
    defs,
  );
  assert.equal(manual.acao, "nada");
  assert.deepEqual(manual.propriedades, {});
  assert.deepEqual(manual.conflitos, [{ email: "ada@example.com", propriedade: "icp", atual: "CEO / C-Suite", desejado: "analista_bp_rh" }]);
  assert.deepEqual(manual.substituicoes, []);

  // sem registro: continua como hoje (conflito)
  const semRegistro = planejar(linha({ icp: "analista_bp_rh" }), contato({ icp: "gestor_rh" }), defs);
  assert.equal(semRegistro.conflitos.length, 1);
  assert.deepEqual(semRegistro.propriedades, {});

  // igual ao desejado: nada, com ou sem registro
  const igual = planejar(linha({ icp: "gestor_rh", ultimo_escrito: { icp: "gestor_rh" } }), contato({ icp: "gestor_rh" }), defs);
  assert.equal(igual.acao, "nada");
});

test("resumo: sem a propriedade no HubSpot vai para ignorados (propriedade_inexistente) uma vez por contato, sem escrever", () => {
  const { mind_resumo_inteligencia: _, ...semResumo } = defs;
  const d = planejar(linha({ resumo: RESUMO_A, jobtitle: "CHRO" }), contato({}), semResumo);
  assert.equal(d.acao, "atualizar");
  assert.deepEqual(d.propriedades, { jobtitle: "CHRO" });
  assert.deepEqual(d.ignorados, [{
    email: "ada@example.com", propriedade: "mind_resumo_inteligencia", valor: "resumo", motivo: "propriedade_inexistente",
  }]);

  const semResumoNoPlano = planejar(linha({ resumo: "   ", jobtitle: "CHRO" }), contato({}), semResumo);
  assert.deepEqual(semResumoNoPlano.ignorados, []);
});

test("resumo: vazio escreve; igual não escreve; editado por humano preserva; último escrito pelo Mind e mudou escreve", () => {
  const vazio = planejar(linha({ resumo: RESUMO_A }), contato({}), defs);
  assert.equal(vazio.acao, "atualizar");
  assert.deepEqual(vazio.propriedades, { mind_resumo_inteligencia: RESUMO_A });

  const igual = planejar(linha({ resumo: RESUMO_A, ultimo_escrito: { mind_resumo_inteligencia: RESUMO_A } }), contato({ mind_resumo_inteligencia: `${RESUMO_A}\n` }), defs);
  assert.equal(igual.acao, "nada");
  assert.deepEqual(igual.propriedades, {});
  assert.deepEqual(igual.preservados, []);

  const humano = planejar(
    linha({ resumo: RESUMO_B, ultimo_escrito: { mind_resumo_inteligencia: RESUMO_A } }),
    contato({ mind_resumo_inteligencia: "Cliente estratégica — falar com a Adriana antes de qualquer abordagem." }),
    defs,
  );
  assert.equal(humano.acao, "nada");
  assert.deepEqual(humano.propriedades, {});
  assert.deepEqual(humano.preservados, [{
    email: "ada@example.com",
    propriedade: "mind_resumo_inteligencia",
    atual: "Cliente estratégica — falar com a Adriana antes de qualquer abordagem.",
    desejado: RESUMO_B,
    motivo: "editado_no_hubspot",
  }]);

  const nosso = planejar(
    linha({ resumo: RESUMO_B, ultimo_escrito: { mind_resumo_inteligencia: RESUMO_A } }),
    contato({ mind_resumo_inteligencia: RESUMO_A }),
    defs,
  );
  assert.equal(nosso.acao, "atualizar");
  assert.deepEqual(nosso.propriedades, { mind_resumo_inteligencia: RESUMO_B });
  assert.deepEqual(nosso.preservados, []);

  // nunca escrevemos o resumo neste contato, mas há texto lá: escreve (regra de sempre)
  const semRegistro = planejar(linha({ resumo: RESUMO_B, ultimo_escrito: { jobtitle: "CHRO" } }), contato({ mind_resumo_inteligencia: "texto antigo" }), defs);
  assert.deepEqual(semRegistro.propriedades, { mind_resumo_inteligencia: RESUMO_B });
});

test("decisão completa com a guarda: ICP nosso muda, cargo editado no HubSpot fica, resumo entra", () => {
  const d = planejar(
    linha({
      jobtitle: "Diretora de RH", company: "Vale S.A.", icp: "analista_bp_rh", icp_confianca: 7, jtbd: ["nr1_mensuracao"], resumo: RESUMO_B,
      ultimo_escrito: { jobtitle: "Gerente de RH", company: "Vale", icp: "gestor_rh", icp_confianca: "7", jtbd: "engajar_lideres" },
    }),
    contato({ jobtitle: "Head de Pessoas", company: "VALE SA", icp: "gestor_rh", icp_confianca: "7", jtbd: "engajar_lideres", mind_resumo_inteligencia: "" }),
    defs,
  );
  assert.equal(d.acao, "atualizar");
  // jtbd: o HubSpot tinha exatamente o que o Mind escreveu ("engajar_lideres") → nosso e intacto → o
  // conjunto do banco substitui (o job rebaixado sai) e a troca aparece em substituicoes
  assert.deepEqual(d.propriedades, {
    icp: "analista_bp_rh",
    icp_confianca: "7",
    jtbd: "nr1_mensuracao",
    mind_resumo_inteligencia: RESUMO_B,
  });
  assert.deepEqual(d.preservados.map((p) => p.propriedade), ["jobtitle"]);
  assert.deepEqual(d.substituicoes.map((s) => s.propriedade), ["icp", "jtbd"]);
  assert.deepEqual(d.conflitos, []);
  assert.deepEqual(d.equivalentes, []); // "Vale S.A." ≡ "VALE SA" é mesma_chave, que não se lista
});

// ------------------------------------------------------- jtbd: conjunto × união (revisão 23/09)
test("jtbd: HubSpot tem exatamente o que o Mind escreveu por último → o conjunto do banco substitui e pode remover job", () => {
  const d = planejar(
    linha({ jtbd: ["nr1_mensuracao"], ultimo_escrito: { jtbd: "engajar_lideres;reduzir_afastamentos" } }),
    contato({ jtbd: "reduzir_afastamentos;engajar_lideres" }),
    defs,
  );
  assert.equal(d.propriedades.jtbd, "nr1_mensuracao");
  assert.deepEqual(d.substituicoes, [{ email: "ada@example.com", propriedade: "jtbd", atual: "reduzir_afastamentos;engajar_lideres", novo: "nr1_mensuracao" }]);
});

test("jtbd: alguém marcou um job a mais no HubSpot → união, nunca se apaga escolha humana", () => {
  const d = planejar(
    linha({ jtbd: ["nr1_mensuracao"], ultimo_escrito: { jtbd: "engajar_lideres" } }),
    contato({ jtbd: "engajar_lideres;reduzir_afastamentos" }),
    defs,
  );
  assert.equal(d.propriedades.jtbd, "engajar_lideres;nr1_mensuracao;reduzir_afastamentos");
  assert.deepEqual(d.substituicoes, []);
});

test("jtbd: sem registro de última escrita → união, como antes", () => {
  const d = planejar(linha({ jtbd: ["nr1_mensuracao"] }), contato({ jtbd: "engajar_lideres" }), defs);
  assert.equal(d.propriedades.jtbd, "engajar_lideres;nr1_mensuracao");
  assert.deepEqual(d.substituicoes, []);
});

test("jtbd: plano sem job e HubSpot com o que o Mind escreveu → limpa a propriedade (substituição visível); com edição humana, fica", () => {
  const limpa = planejar(linha({ jtbd: [], ultimo_escrito: { jtbd: "engajar_lideres" } }), contato({ jtbd: "engajar_lideres" }), defs);
  assert.equal(limpa.acao, "atualizar");
  assert.equal(limpa.propriedades.jtbd, "");
  assert.deepEqual(limpa.substituicoes.map((s) => s.propriedade), ["jtbd"]);
  const fica = planejar(linha({ jtbd: [], ultimo_escrito: { jtbd: "engajar_lideres" } }), contato({ jtbd: "engajar_lideres;reduzir_afastamentos" }), defs);
  assert.equal(fica.acao, "nada");
  const nunca = planejar(linha({ jtbd: [] }), contato({ jtbd: "engajar_lideres" }), defs);
  assert.equal(nunca.acao, "nada");
});

test("jtbd: conjunto igual ao atual (em outra ordem) não escreve", () => {
  const d = planejar(
    linha({ jtbd: ["nr1_mensuracao", "engajar_lideres"], ultimo_escrito: { jtbd: "nr1_mensuracao;engajar_lideres" } }),
    contato({ jtbd: "engajar_lideres;nr1_mensuracao" }),
    defs,
  );
  assert.equal(d.acao, "nada");
});

// ------------------------------------------------------- qualidade do valor novo (revisão 23/09)
test("cargo: headline do LinkedIn, URL ou e-mail colados não substituem o que está lá nem entram em campo vazio", () => {
  const cheio = planejar(linha({ jobtitle: "CEO | Palestrante | Idealizadora do Sistema DIBE | dibe.com.br" }), contato({ jobtitle: "CEO" }), defs);
  assert.equal(cheio.acao, "nada");
  assert.deepEqual(cheio.equivalentes.map((e) => e.motivo), ["novo_parece_headline_ou_url"]);
  const vazio = planejar(linha({ company: "https://www.minhaempresa.com.br" }), contato({ company: "" }), defs);
  assert.equal(vazio.acao, "nada");
  assert.deepEqual(vazio.ignorados.map((i) => i.motivo), ["novo_parece_headline_ou_url"]);
});

test("cargo: nível solto (\"Gerente\") não substitui cargo com área (\"Gerente de Comunicação\"); o inverso substitui", () => {
  const pobre = planejar(linha({ jobtitle: "Gerente", ultimo_escrito: { jobtitle: "Gerente de Comunicação" } }), contato({ jobtitle: "Gerente de Comunicação" }), defs);
  assert.equal(pobre.acao, "nada");
  assert.deepEqual(pobre.equivalentes.map((e) => e.motivo), ["novo_menos_especifico"]);
  const rico = planejar(linha({ jobtitle: "Gerente de Comunicação Interna", ultimo_escrito: { jobtitle: "Gerente" } }), contato({ jobtitle: "Gerente" }), defs);
  assert.equal(rico.acao, "atualizar");
  assert.equal(rico.propriedades.jobtitle, "Gerente de Comunicação Interna");
  const outraArea = planejar(linha({ jobtitle: "Diretora", ultimo_escrito: { jobtitle: "Gerente de Marketing" } }), contato({ jobtitle: "Gerente de Marketing" }), defs);
  assert.equal(outraArea.acao, "nada");
  assert.deepEqual(outraArea.equivalentes.map((e) => e.motivo), ["novo_menos_especifico"]);
});

// ------------------------------------------- quem não é lead não tem ICP nem JTBD (Adriana, 23/09)
test("não-lead: ICP, confiança, JTBD e resumo que estão no HubSpot são limpos, manuais ou nossos; cargo e empresa seguem", () => {
  const d = planejar(
    linha({ nao_lead: true, jobtitle: "Diretora de Pessoas", company: "Vale", icp: null, jtbd: [], resumo: null,
            ultimo_escrito: { jtbd: "engajar_lideres" } }),
    contato({ jobtitle: "", company: "Vale S.A.", icp: "CHRO / VP de Pessoas", icp_confianca: "7",
              jtbd: "engajar_lideres;nr1_mensuracao", mind_resumo_inteligencia: "ICP: CHRO\nJTBD: engajar líderes" }),
    defs,
  );
  assert.equal(d.acao, "atualizar");
  assert.deepEqual(d.propriedades, { jobtitle: "Diretora de Pessoas", icp: "", icp_confianca: "", jtbd: "", mind_resumo_inteligencia: "" });
  assert.deepEqual(d.limpezas.map((x) => [x.propriedade, x.motivo]), [
    ["icp", "nao_e_lead"], ["icp_confianca", "nao_e_lead"], ["jtbd", "nao_e_lead"], ["mind_resumo_inteligencia", "nao_e_lead"],
  ]);
  assert.equal(d.limpezas[0].atual, "CHRO / VP de Pessoas");
  assert.equal(d.limpezas[2].atual, "engajar_lideres;nr1_mensuracao");
  assert.equal(d.limpezas[3].atual, "resumo", "o texto do resumo não vai para o relatório");
  assert.deepEqual(d.conflitos, [], "ICP manual de não-lead não é conflito: é limpo");
  assert.deepEqual(d.preservados, []);
  assert.equal(d.propriedades.company, undefined, "\"Vale\" ≡ \"Vale S.A.\": empresa segue a regra de sempre");
});

test("não-lead: nada de perfil no HubSpot → nada a limpar; o plano não escreve ICP/JTBD mesmo se vier", () => {
  const limpo = planejar(linha({ nao_lead: true }), contato({ icp: "", jtbd: "", icp_confianca: null }), defs);
  assert.equal(limpo.acao, "nada");
  assert.deepEqual(limpo.limpezas, []);
  // defesa em profundidade: o plano já manda nulo, mas mesmo que viesse, quem não é lead não recebe perfil
  const vazou = planejar(linha({ nao_lead: true, icp: "gestor_rh", icp_confianca: 6, jtbd: ["nr1_mensuracao"], resumo: "x" }), contato({}), defs);
  assert.equal(vazou.acao, "nada");
  assert.deepEqual(vazou.propriedades, {});
});

test("não-lead: nao_lead false/ausente segue a regra de sempre (ICP vazio é preenchido)", () => {
  for (const extra of [{ nao_lead: false }, {}]) {
    const d = planejar(linha({ ...extra, icp: "gestor_rh", icp_confianca: 7 }), contato({ icp: "" }), defs);
    assert.equal(d.propriedades.icp, "gestor_rh");
    assert.deepEqual(d.limpezas, []);
  }
  assert.deepEqual(PROPRIEDADES_PERFIL, ["icp", "icp_confianca", "jtbd", "mind_resumo_inteligencia"]);
  for (const p of PROPRIEDADES_PERFIL) assert.ok(PROPRIEDADES_LIDAS.includes(p), `${p} precisa ser lida para ser limpa`);
});

test("pular (sem contato) também traz limpezas vazio, para o relatório somar sem quebrar", () => {
  const d = planejar(linha({ nao_lead: true }), null, defs);
  assert.equal(d.acao, "pular");
  assert.deepEqual(d.limpezas, []);
});
