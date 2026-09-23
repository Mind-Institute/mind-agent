// Decisão pura: dado o plano de perfil de uma pessoa (mind_hubspot_perfil_plano) e o que o
// HubSpot já tem no contato, o que escrever. Sem I/O, para o Node testar.
//
// Regras da Adriana (23/09/2026):
// - cargo (jobtitle) e empresa (company) são o que a pessoa escreveu no credenciamento:
//   atualizam o HubSpot, mas sem duplicar por typo/grafia — se o que está lá é a mesma
//   coisa escrita de outro jeito ("Vale S.A." / "VALE SA", "CEO / Fundador" / "CEO",
//   "Beiersdorf" / "Beiwrsdorf"), não se escreve (`equivalentes`, com o motivo). Quando é
//   outra coisa de verdade, escreve-se e a troca vai para `substituicoes`, para ela rever.
// - ICP só preenche o que está vazio; valor já presente no HubSpot (manual) nunca é
//   sobrescrito — a diferença vai para `conflitos`. Junto com o ICP vai `icp_confianca`.
// - JTBD é multi-seleção: escreve-se a união (atual ∪ desejado), na ordem do catálogo, e
//   só quando a união acrescenta algo ao que já está lá.
// - Esta função não cria contatos (isso é da irmã de credenciamento): sem contato, pula.
//
// Também mora aqui `montarOpcoes`, que decide as opções finais de uma propriedade de
// enumeração a partir do catálogo do banco sem apagar valor que já existe no HubSpot.

export const PROPRIEDADES_LIDAS = ["email", "jobtitle", "company", "icp", "icp_confianca", "jtbd"];

// Sufixos jurídicos/geográficos que não distinguem uma empresa da outra grafia dela.
// Removidos como palavra inteira depois da normalização (`chave`).
export const SUFIXOS_EMPRESA = [
  "ltda", "limitada", "sa", "s a", "me", "eireli", "epp", "ss", "cia", "company", "co", "inc",
  "llc", "corp", "corporation", "group", "holding", "participacoes", "brasil", "brazil",
  "do brasil", "latam", "latin america", "international", "internacional",
];

// Artigo ou "grupo" no início do nome ("Grupo Boticário" é "O Boticário").
export const PREFIXOS_EMPRESA = ["o", "a", "os", "as", "the", "grupo", "group"];

export type Linha = {
  mind_id: string;
  hubspot_id: string | null;
  email: string | null;
  jobtitle: string | null;
  company: string | null;
  icp: string | null;
  icp_confianca: number | null;
  jtbd: string[] | null;
  fontes?: Record<string, unknown> | null;
};

export type OpcaoHubSpot = {
  value: string;
  label?: string;
  displayOrder?: number;
  hidden?: boolean;
  description?: string;
};

export type Definicao = {
  name: string;
  type: string;
  fieldType: string;
  options: OpcaoHubSpot[];
};
export type Definicoes = Record<string, Definicao>;

export type ItemCatalogo = {
  codigo: string;
  rotulo: string;
  hubspot_valor?: string | null;
  ordem?: number | null;
  descricao?: string | null;
};
export type Catalogos = { icp?: ItemCatalogo[] | null; jtbd?: ItemCatalogo[] | null };

export type ContatoAtual = {
  id: string;
  properties: Record<string, string | null | undefined>;
};

export type Conflito = { email: string; propriedade: string; atual: string; desejado: string };
export type Ignorado = { email: string; propriedade: string; valor: string; motivo: string };
export type Substituicao = { email: string; propriedade: string; atual: string; novo: string };
export type Equivalente = { email: string; propriedade: string; atual: string; novo: string; motivo: string };

export type Decisao = {
  mind_id: string;
  email: string;
  acao: "atualizar" | "nada" | "pular";
  id?: string;
  motivo?: string;
  propriedades: Record<string, string>;
  conflitos: Conflito[];
  ignorados: Ignorado[];
  substituicoes: Substituicao[];
  equivalentes: Equivalente[];
};

export type DiffOpcoes = {
  renomeadas: Array<{ value: string; de: string; para: string }>;
  acrescentadas: Array<{ value: string; label: string }>;
  reordenadas: Array<{ value: string; de: number | null; para: number }>;
  reexibidas: string[];
  mantidas: string[];
};

function vazio(valor: unknown): boolean {
  return valor === null || valor === undefined || String(valor).trim() === "";
}

function texto(valor: unknown): string {
  return typeof valor === "string" ? valor.trim() : "";
}

function unicos(valores: string[]): string[] {
  return [...new Set(valores)];
}

function partes(valor: string): string[] {
  return valor.split(";").map((v) => v.trim()).filter((v) => v !== "");
}

/**
 * Chave de comparação de texto livre: minúsculas, sem acentos (NFD e remoção das marcas),
 * "&" vira " e ", só [a-z0-9] e espaço, espaços colapsados. "Gerente de RH" ≡ "gerente de rh";
 * "Gerente RH" continua diferente de "Gerente de RH" — aqui não se adivinha.
 */
export function chave(valor: unknown): string {
  return String(valor ?? "")
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/&/g, " e ")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const RE_SUFIXOS_EMPRESA = new RegExp(
  `\\b(?:${[...SUFIXOS_EMPRESA].sort((a, b) => b.length - a.length).join("|")})\\b`,
  "g",
);

/**
 * Chave de empresa: a `chave` sem sufixos jurídicos (palavra inteira) e sem o artigo ou
 * "grupo" inicial. "Vale S.A." ≡ "VALE SA" ≡ "vale"; "BDF NIVEA" ≠ "Beiersdorf".
 * Se sobrar nada (o nome era só sufixo), vale a chave inteira — nunca "" contra "".
 */
export function chaveEmpresa(valor: unknown): string {
  const base = chave(valor);
  const palavras = base.replace(RE_SUFIXOS_EMPRESA, " ").split(" ").filter((p) => p !== "");
  while (palavras.length > 0 && PREFIXOS_EMPRESA.includes(palavras[0])) palavras.shift();
  const reduzida = palavras.join(" ");
  return reduzida === "" ? base : reduzida;
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

function mesmoConjunto(a: string[], b: string[]): boolean {
  const x = new Set(a.map((v) => v.toLowerCase()));
  const y = new Set(b.map((v) => v.toLowerCase()));
  return x.size === y.size && [...x].every((v) => y.has(v));
}

/** Posição de cada opção na ordem do catálogo (displayOrder; sem ele, a ordem da lista). */
function ordemDasOpcoes(def: Definicao): Map<string, number> {
  const ordenadas = def.options
    .map((o, i) => ({ value: o.value.toLowerCase(), ordem: typeof o.displayOrder === "number" && o.displayOrder >= 0 ? o.displayOrder : Number.MAX_SAFE_INTEGER, i }))
    .sort((a, b) => a.ordem - b.ordem || a.i - b.i);
  return new Map(ordenadas.map((o, posicao) => [o.value, posicao]));
}

/**
 * União dos valores atuais com os desejados, na ordem do catálogo. Valor que já está no
 * contato mas não está mais na lista de opções é mantido no fim, como está — nunca se
 * apaga o que a pessoa já tem.
 */
export function unirJtbd(atuais: string[], desejados: string[], def: Definicao): string[] {
  const canonico = new Map(def.options.map((o) => [o.value.toLowerCase(), o.value]));
  const posicao = ordemDasOpcoes(def);
  const vistos = new Set<string>();
  const lista: string[] = [];
  for (const v of [...atuais, ...desejados]) {
    const k = v.toLowerCase();
    if (vistos.has(k)) continue;
    vistos.add(k);
    lista.push(canonico.get(k) ?? v);
  }
  const rank = (v: string) => posicao.get(v.toLowerCase()) ?? Number.MAX_SAFE_INTEGER;
  return lista.sort((a, b) => rank(a) - rank(b));
}

/** Distância de Levenshtein entre duas chaves (para pegar typo: "beiersdorf" / "beiwrsdorf"). */
export function distancia(a: string, b: string): number {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;
  let anterior = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i += 1) {
    const atual = [i];
    for (let j = 1; j <= b.length; j += 1) {
      const custo = a[i - 1] === b[j - 1] ? 0 : 1;
      atual[j] = Math.min(anterior[j] + 1, atual[j - 1] + 1, anterior[j - 1] + custo);
    }
    anterior = atual;
  }
  return anterior[b.length];
}

/**
 * "É a mesma coisa escrita de outro jeito?" — a guarda da Adriana contra typo e duplicata.
 * Mesma chave; ou uma chave contém a outra ("CEO / Fundador" ⊇ "CEO", "Localiza & CO" ⊇ "Localiza");
 * ou distância de edição pequena para o tamanho ("beiersdorf" / "beiwrsdorf"). Nesses casos o que
 * já está no HubSpot fica. Devolve o motivo, ou null quando é outra coisa de verdade.
 */
export function equivalente(chaveAtual: string, chaveNova: string): string | null {
  if (chaveAtual === chaveNova) return "mesma_chave";
  const menor = Math.min(chaveAtual.length, chaveNova.length);
  if (menor >= 3 && (chaveAtual.includes(chaveNova) || chaveNova.includes(chaveAtual))) return "uma_contem_a_outra";
  const d = distancia(chaveAtual, chaveNova);
  const tolerancia = menor >= 12 ? 3 : menor >= 6 ? 2 : menor >= 4 ? 1 : 0;
  if (d <= tolerancia) return "typo_provavel";
  return null;
}

function emailDe(linha: Linha, atual: ContatoAtual | null): string {
  return (texto(linha.email) || texto(atual?.properties.email)).toLowerCase();
}

export function planejar(linha: Linha, atual: ContatoAtual | null, defs: Definicoes): Decisao {
  const email = emailDe(linha, atual);
  const ignorados: Ignorado[] = [];
  const conflitos: Conflito[] = [];
  const substituicoes: Substituicao[] = [];
  const equivalentes: Equivalente[] = [];
  const base = { mind_id: linha.mind_id, email, conflitos, ignorados, substituicoes, equivalentes };

  if (!atual) {
    const motivo = texto(linha.hubspot_id) || texto(linha.email) ? "sem_contato" : "sem_identificador";
    return { ...base, acao: "pular", motivo, propriedades: {} };
  }

  const propriedades: Record<string, string> = {};

  // Texto livre (cargo, empresa): atualiza, mas sem duplicar grafia; troca real vai para
  // `substituicoes`, para a Adriana rever.
  const textoLivre = (prop: string, desejado: string | null, chaveDe: (v: unknown) => string) => {
    const novo = texto(desejado);
    if (!novo) return;
    if (chaveDe(novo) === "") {
      ignorados.push({ email, propriedade: prop, valor: novo, motivo: "sem_conteudo" });
      return;
    }
    const cur = atual.properties[prop];
    if (vazio(cur)) {
      propriedades[prop] = novo;
      return;
    }
    const atualTexto = String(cur).trim();
    const motivo = equivalente(chaveDe(atualTexto), chaveDe(novo));
    if (motivo) {
      if (motivo !== "mesma_chave") equivalentes.push({ email, propriedade: prop, atual: atualTexto, novo, motivo });
      return;
    }
    propriedades[prop] = novo;
    substituicoes.push({ email, propriedade: prop, atual: atualTexto, novo });
  };
  textoLivre("jobtitle", linha.jobtitle, chave);
  textoLivre("company", linha.company, chaveEmpresa);

  // ICP: só preenche vazio. Valor já presente (manual) nunca é sobrescrito; diferença vira conflito.
  const icpDesejado = texto(linha.icp);
  if (icpDesejado) {
    const aceitos = validar(email, "icp", [icpDesejado], defs, ignorados);
    if (aceitos.length > 0) {
      const novo = aceitos[0];
      const cur = atual.properties.icp;
      if (vazio(cur)) {
        propriedades.icp = novo;
        const confianca = linha.icp_confianca;
        if (typeof confianca === "number" && Number.isFinite(confianca)) {
          if (defs.icp_confianca) propriedades.icp_confianca = String(confianca);
          else ignorados.push({ email, propriedade: "icp_confianca", valor: String(confianca), motivo: "propriedade_inexistente" });
        }
      } else if (String(cur).trim().toLowerCase() !== novo.toLowerCase()) {
        conflitos.push({ email, propriedade: "icp", atual: String(cur).trim(), desejado: novo });
      }
    }
  }

  // JTBD (multi-seleção): união do que já está lá com o que o Mind vê, na ordem do catálogo.
  const jtbdDesejado = unicos((Array.isArray(linha.jtbd) ? linha.jtbd : []).map(texto).filter((v) => v !== ""));
  if (jtbdDesejado.length > 0) {
    const aceitos = validar(email, "jtbd", jtbdDesejado, defs, ignorados);
    const def = defs.jtbd;
    if (def && aceitos.length > 0) {
      const atuais = partes(String(atual.properties.jtbd ?? ""));
      const uniao = unirJtbd(atuais, aceitos, def);
      if (!mesmoConjunto(atuais, uniao)) propriedades.jtbd = uniao.join(";");
    }
  }

  return {
    ...base,
    id: atual.id,
    acao: Object.keys(propriedades).length > 0 ? "atualizar" : "nada",
    propriedades,
  };
}

function ordemDe(opcao: OpcaoHubSpot | undefined): number | null {
  return typeof opcao?.displayOrder === "number" && opcao.displayOrder >= 0 ? opcao.displayOrder : null;
}

/**
 * Opções finais de uma propriedade de enumeração a partir do catálogo do banco.
 * Para cada item do catálogo: { value: hubspot_valor, label: rotulo, displayOrder: ordem,
 * hidden: false }. Opção que existe no HubSpot e não está no catálogo fica como está —
 * nunca se apaga valor, contatos podem usá-lo. Devolve o diff para o relatório e `mudou`,
 * que diz se vale um PATCH.
 */
export function montarOpcoes(
  atuais: OpcaoHubSpot[],
  catalogo: ItemCatalogo[],
): { opcoes: OpcaoHubSpot[]; diff: DiffOpcoes; mudou: boolean } {
  const diff: DiffOpcoes = { renomeadas: [], acrescentadas: [], reordenadas: [], reexibidas: [], mantidas: [] };
  const existentes = new Map(atuais.map((o) => [o.value, o]));
  const doCatalogo = new Set<string>();
  const finais: OpcaoHubSpot[] = [];

  for (const item of catalogo) {
    const value = texto(item.hubspot_valor) || texto(item.codigo);
    if (!value || doCatalogo.has(value)) continue;
    doCatalogo.add(value);
    const atual = existentes.get(value);
    const label = texto(item.rotulo) || value;
    const displayOrder = typeof item.ordem === "number" ? item.ordem : (ordemDe(atual) ?? -1);
    const opcao: OpcaoHubSpot = { value, label, displayOrder, hidden: false };
    if (atual?.description) opcao.description = atual.description;
    finais.push(opcao);

    if (!atual) {
      diff.acrescentadas.push({ value, label });
      continue;
    }
    let mudou = false;
    const labelAtual = texto(atual.label);
    if (labelAtual !== label) {
      diff.renomeadas.push({ value, de: labelAtual, para: label });
      mudou = true;
    }
    if (ordemDe(atual) !== displayOrder) {
      diff.reordenadas.push({ value, de: ordemDe(atual), para: displayOrder });
      mudou = true;
    }
    if (atual.hidden === true) {
      diff.reexibidas.push(value);
      mudou = true;
    }
    if (!mudou) diff.mantidas.push(value);
  }

  for (const o of atuais) {
    if (doCatalogo.has(o.value)) continue;
    finais.push({ ...o });
    diff.mantidas.push(o.value);
  }

  const semOrdem = Number.MAX_SAFE_INTEGER;
  finais.sort((a, b) => (ordemDe(a) ?? semOrdem) - (ordemDe(b) ?? semOrdem));

  const mudou = diff.renomeadas.length > 0 || diff.acrescentadas.length > 0 ||
    diff.reordenadas.length > 0 || diff.reexibidas.length > 0;
  return { opcoes: finais, diff, mudou };
}
