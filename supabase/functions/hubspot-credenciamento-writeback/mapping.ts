// Decisão pura: dado o plano de uma pessoa (mind_credenciamento_hubspot_plano) e o que o
// HubSpot já tem no contato, o que escrever. Sem I/O, para o Node testar.
//
// A regra da Adriana (23/09/2026): NADA que já está no HubSpot é sobrescrito. Só se
// escreve o que está vazio. Nos campos de anos, acrescenta-se 2026 sem tirar nada.
// A única exceção é o reembolso confirmado, que troca o estágio de venda — e vai para
// `substituicoes`, para ela ver antes.

export const ANO = "2026";
export const STATUS_REEMBOLSO = "Reembolso da compra";

export const PROPRIEDADES_ANO = [
  "summit__participacao_anual",
  "summit__cortesia_anos",
  "summit__patrocinio_anos",
] as const;

export const PROPRIEDADES_TELEFONE = ["phone", "mobilephone", "hs_whatsapp_phone_number"] as const;

export const PROPRIEDADES_LIDAS = [
  "email", "firstname", "lastname",
  "phone", "mobilephone", "hs_whatsapp_phone_number", "cpf",
  "summit__categoria_2026", "summit__tipo_entrada_2026", "summit__instituicao_2026",
  "summit__lote_2026", "summit__papel_2026",
  "summit__participacao_anual", "summit__cortesia_anos", "summit__patrocinio_anos",
  "status_summit_2026",
];

// origem do ingresso no credenciamento -> opção de summit__tipo_entrada_2026.
// Imprensa, palestrante, parceiro, convidado e staff seguem o que o outro escritor
// (Mind Gerencial) já grava para eles no CRM: Cortesia.
export const TIPO_ENTRADA: Record<string, string> = {
  "Pago": "Pago",
  "Cortesia": "Cortesia",
  "Patrocínio": "Patrocínio",
  "Imprensa": "Cortesia",
  "Palestrante": "Cortesia",
  "Parceiro": "Cortesia",
  "Convidado institucional": "Cortesia",
  "Staff": "Cortesia",
};

// sponsor_company é texto livre; summit__instituicao_2026 é lista fechada.
export const INSTITUICAO_ALIAS: Record<string, string> = {
  "chillibeans": "Chilli Beans",
  "bp": "Beneficencia Portuguesa",
};

export type Linha = {
  email: string;
  primeiro_nome: string | null;
  sobrenome: string | null;
  telefone: string | null;
  cpf: string | null;
  categorias: string[];
  origens: string[];
  lotes: string[];
  instituicoes: string[];
  pagante: boolean;
  participante: boolean;
  cortesia: boolean;
  patrocinio: boolean;
  reembolsado: boolean;
  reembolso_nao_confirmado: boolean;
  so_por_terceiro: boolean;
  linhas_ativas: number;
  linhas_revogadas: number;
};

export type Definicao = {
  name: string;
  type: string;
  fieldType: string;
  options: Array<{ value: string; label?: string; hidden?: boolean }>;
};
export type Definicoes = Record<string, Definicao>;

export type ContatoAtual = {
  id: string;
  properties: Record<string, string | null | undefined>;
};

export type Conflito = { email: string; propriedade: string; atual: string; desejado: string };
export type Ignorado = { email: string; propriedade: string; valor: string; motivo: string };
export type Substituicao = { email: string; propriedade: string; atual: string; novo: string };

export type Decisao = {
  email: string;
  acao: "criar" | "atualizar" | "nada" | "pular";
  id?: string;
  motivo?: string;
  propriedades: Record<string, string>;
  conflitos: Conflito[];
  ignorados: Ignorado[];
  substituicoes: Substituicao[];
};

function vazio(valor: unknown): boolean {
  return valor === null || valor === undefined || String(valor).trim() === "";
}

function unicos(valores: string[]): string[] {
  return [...new Set(valores)];
}

function multi(def: Definicao | undefined): boolean {
  return def?.fieldType === "checkbox";
}

function partes(valor: string): string[] {
  return valor.split(";").map((v) => v.trim()).filter((v) => v !== "");
}

function digitos(valor: string): string {
  return valor.replace(/\D/g, "");
}

/** Mantém só os valores que a propriedade aceita; o resto vai para `ignorados`. */
function validar(
  email: string,
  propriedade: string,
  valores: string[],
  defs: Definicoes,
  ignorados: Ignorado[],
): string[] {
  const def = defs[propriedade];
  if (!def) {
    for (const v of valores) ignorados.push({ email, propriedade, valor: v, motivo: "propriedade_inexistente" });
    return [];
  }
  if (def.type !== "enumeration") return unicos(valores);
  const mapa = new Map(def.options.map((o) => [o.value.toLowerCase(), o.value]));
  const aceitos: string[] = [];
  for (const v of valores) {
    const opcao = mapa.get(v.toLowerCase());
    if (opcao) aceitos.push(opcao);
    else ignorados.push({ email, propriedade, valor: v, motivo: "valor_fora_da_lista" });
  }
  return unicos(aceitos);
}

function juntar(valores: string[], def: Definicao | undefined): string | null {
  if (valores.length === 0) return null;
  return multi(def) ? valores.join(";") : valores[0];
}

function instituicao(nome: string): string {
  return INSTITUICAO_ALIAS[nome.trim().toLowerCase()] ?? nome.trim();
}

/** O que o credenciamento diz sobre a pessoa, já no vocabulário do HubSpot. */
export function valoresDesejados(linha: Linha, defs: Definicoes, ignorados: Ignorado[]): Record<string, string> {
  const d: Record<string, string> = {};
  const email = linha.email;

  if (linha.participante) {
    if (linha.telefone) for (const p of PROPRIEDADES_TELEFONE) if (defs[p]) d[p] = linha.telefone;
    if (linha.cpf && defs.cpf) d.cpf = linha.cpf;

    const categoria = juntar(validar(email, "summit__categoria_2026", linha.categorias, defs, ignorados), defs.summit__categoria_2026);
    if (categoria) d.summit__categoria_2026 = categoria;

    const origens: string[] = [];
    for (const o of linha.origens) {
      const mapeada = TIPO_ENTRADA[o];
      if (mapeada) origens.push(mapeada);
      else ignorados.push({ email, propriedade: "summit__tipo_entrada_2026", valor: o, motivo: "origem_sem_mapeamento" });
    }
    const tipo = juntar(validar(email, "summit__tipo_entrada_2026", unicos(origens), defs, ignorados), defs.summit__tipo_entrada_2026);
    if (tipo) d.summit__tipo_entrada_2026 = tipo;

    const inst = juntar(validar(email, "summit__instituicao_2026", linha.instituicoes.map(instituicao), defs, ignorados), defs.summit__instituicao_2026);
    if (inst) d.summit__instituicao_2026 = inst;

    const lote = juntar(validar(email, "summit__lote_2026", linha.lotes, defs, ignorados), defs.summit__lote_2026);
    if (lote) d.summit__lote_2026 = lote;

    const papeis = [...(linha.pagante ? ["Pagante"] : []), "Participante"];
    const papel = juntar(validar(email, "summit__papel_2026", papeis, defs, ignorados), defs.summit__papel_2026);
    if (papel) d.summit__papel_2026 = papel;

    const anos: Array<[string, boolean]> = [
      ["summit__participacao_anual", true],
      ["summit__cortesia_anos", linha.cortesia],
      ["summit__patrocinio_anos", linha.patrocinio],
    ];
    for (const [prop, vale] of anos) {
      if (!vale) continue;
      const v = validar(email, prop, [ANO], defs, ignorados);
      if (v.length) d[prop] = v[0];
    }
  }

  if (linha.reembolsado) {
    const v = validar(email, "status_summit_2026", [STATUS_REEMBOLSO], defs, ignorados);
    if (v.length) d.status_summit_2026 = v[0];
  }

  return d;
}

function equivalentes(propriedade: string, atual: string, desejado: string, defs: Definicoes): boolean {
  if ((PROPRIEDADES_TELEFONE as readonly string[]).includes(propriedade)) return digitos(atual) === digitos(desejado);
  if (propriedade === "cpf") return digitos(atual) === digitos(desejado);
  if (multi(defs[propriedade])) {
    const a = new Set(partes(atual).map((v) => v.toLowerCase()));
    const b = new Set(partes(desejado).map((v) => v.toLowerCase()));
    return a.size === b.size && [...a].every((v) => b.has(v));
  }
  return atual.trim().toLowerCase() === desejado.trim().toLowerCase();
}

export function planejar(linha: Linha, atual: ContatoAtual | null, defs: Definicoes): Decisao {
  const ignorados: Ignorado[] = [];
  const conflitos: Conflito[] = [];
  const substituicoes: Substituicao[] = [];
  const desejado = valoresDesejados(linha, defs, ignorados);
  const base = { email: linha.email, conflitos, ignorados, substituicoes };

  if (!atual) {
    if (!linha.participante) {
      return { ...base, acao: "pular", motivo: "reembolso_sem_contato", propriedades: {} };
    }
    const propriedades: Record<string, string> = { email: linha.email, ...desejado };
    if (linha.primeiro_nome && defs.firstname) propriedades.firstname = linha.primeiro_nome;
    if (linha.sobrenome && defs.lastname) propriedades.lastname = linha.sobrenome;
    return { ...base, acao: "criar", propriedades };
  }

  const propriedades: Record<string, string> = {};
  for (const [prop, novo] of Object.entries(desejado)) {
    const cur = atual.properties[prop];
    if (vazio(cur)) {
      propriedades[prop] = novo;
      continue;
    }
    const atualTexto = String(cur);
    if ((PROPRIEDADES_ANO as readonly string[]).includes(prop)) {
      const anos = partes(atualTexto);
      if (!anos.includes(ANO)) propriedades[prop] = [...anos, ANO].join(";");
      continue;
    }
    if (prop === "status_summit_2026" && linha.reembolsado) {
      if (!equivalentes(prop, atualTexto, novo, defs)) {
        propriedades[prop] = novo;
        substituicoes.push({ email: linha.email, propriedade: prop, atual: atualTexto, novo });
      }
      continue;
    }
    if (!equivalentes(prop, atualTexto, novo, defs)) {
      conflitos.push({ email: linha.email, propriedade: prop, atual: atualTexto, desejado: novo });
    }
  }

  return {
    ...base,
    id: atual.id,
    acao: Object.keys(propriedades).length > 0 ? "atualizar" : "nada",
    propriedades,
  };
}
