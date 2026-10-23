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
// - JTBD é multi-seleção: quando o HubSpot tem exatamente o que o Mind escreveu por último, o
//   conjunto do banco substitui (pode remover job rebaixado); quando alguém mexeu lá, ou nunca
//   escrevemos, união (atual ∪ desejado) na ordem do catálogo — nunca se apaga escolha humana.
// - Cargo/empresa novos que parecem headline/URL/e-mail, longos demais ou um nível solto no lugar
//   de um cargo com área não substituem o que está lá (`pior`).
// - Esta função não cria contatos (isso é da irmã de credenciamento): sem contato, pula.
// - Guarda de "última escrita" (BACKLOG §21.1, condição para o cron horário): `linha.ultimo_escrito`
//   é o que o Mind escreveu por último nesse contato (registrado por mind_hubspot_perfil_registrar).
//   Quando o valor que está no HubSpot não é o que o Mind escreveu, alguém editou lá depois de nós:
//   fica como está e vai para `preservados` (`editado_no_hubspot`). Quando é o nosso, a mudança do
//   banco passa — inclusive no ICP, que de outro jeito é manual e nunca se sobrescreve. Sem registro
//   (nunca escrevemos aquela propriedade), vale a regra de sempre.
// - Resumo da inteligência (`mind_resumo_inteligencia`, texto multi-linha) vem em `linha.resumo`:
//   vazio no HubSpot → escreve; igual → nada; diferente → segue a guarda acima. Sem a propriedade
//   no HubSpot → `ignorados` (`propriedade_inexistente`), uma vez por contato.
// - Quem não é lead (staff, palestrante, professor, parceiro de venda — `pessoas.relacionamento_mind`,
//   que o plano traz como `nao_lead`) não tem ICP nem JTBD (regra da Adriana, 23/09/2026): cargo e
//   empresa seguem como para todo mundo; `icp`, `icp_confianca`, `jtbd` e o resumo que está no HubSpot
//   são limpos, seja de quem for o valor, e vão para `limpezas` (motivo `nao_e_lead`).
//
// - Credenciamento manda (Adriana, 24/09/2026): quando o plano traz `forcar = true` (o cargo veio do que a
//   pessoa escreveu no credenciamento do Summit), cargo, empresa e ICP sobrescrevem o que estiver no
//   HubSpot, inclusive valor editado lá ou ICP manual — a troca vai para `substituicoes`. Continuam
//   valendo `pior` (headline/URL/e-mail) e `equivalentes` (mesma coisa escrita de outro jeito).
//
// Também mora aqui `montarOpcoes`, que decide as opções finais de uma propriedade de
// enumeração a partir do catálogo do banco sem apagar valor que já existe no HubSpot.

/** Propriedade de texto multi-linha do HubSpot que recebe o resumo da inteligência. */
export const PROPRIEDADE_RESUMO = "mind_resumo_inteligencia";

export const PROPRIEDADES_LIDAS = ["email", "jobtitle", "company", "icp", "icp_confianca", "jtbd", PROPRIEDADE_RESUMO];

/** Propriedades de perfil comercial: quem não é lead não as tem — o que houver lá é limpo. */
export const PROPRIEDADES_PERFIL = ["icp", "icp_confianca", "jtbd", PROPRIEDADE_RESUMO];

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
  /** Texto multi-linha para `mind_resumo_inteligencia`; vazio/nulo = não escreve. */
  resumo?: string | null;
  /**
   * O que o Mind escreveu por último neste contato, por propriedade (mind_hubspot_perfil_registrar),
   * ex.: {"jobtitle":"Gerente de RH","icp":"gestor_rh","jtbd":"a;b"}. Chave ausente = nunca escrevemos
   * aquela propriedade. Nulo/ausente = nunca escrevemos nada neste contato.
   */
  ultimo_escrito?: Record<string, unknown> | null;
  /**
   * true quando a pessoa não é lead (staff, palestrante, professor, parceiro de venda —
   * pessoas.relacionamento_mind): ICP, JTBD e resumo não vão, e o que estiver no HubSpot é limpo.
   */
  nao_lead?: boolean | null;
  /**
   * true quando o cargo veio do credenciamento (o que a pessoa escreveu): cargo, empresa e ICP
   * sobrescrevem o que estiver no HubSpot, mesmo editado lá (Adriana, 24/09/2026).
   */
  forcar?: boolean | null;
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
/** Valor que ficou como está porque alguém o editou no HubSpot depois da última escrita do Mind. */
export type Preservado = { email: string; propriedade: string; atual: string; desejado: string; motivo: string };
/** Valor de perfil comercial apagado no HubSpot porque a pessoa não é lead (`nao_e_lead`). */
export type Limpeza = { email: string; propriedade: string; atual: string; motivo: string };

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
  preservados: Preservado[];
  limpezas: Limpeza[];
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

// Valor novo que não merece substituir o que está lá: headline do LinkedIn / URL / e-mail colados no
// cargo ("CEO | Palestrante | dibe.com.br"), texto longo demais, ou um nível solto ("Gerente") no lugar
// de um cargo com área ("Gerente de Comunicação").
const RE_LIXO = /\||https?:\/\/|www\.|@/i;
const NIVEL_SOLTO = new Set([
  "gerente", "diretor", "diretora", "coordenador", "coordenadora", "analista", "assistente", "gestor", "gestora",
  "supervisor", "supervisora", "head", "lider", "ceo", "socio", "socia", "consultor", "consultora", "coach",
  "estagiario", "estagiaria", "executivo", "executiva", "assessor", "assessora", "especialista",
]);
export function pior(prop: string, atualTexto: string, novo: string): string | null {
  if (RE_LIXO.test(novo) || novo.length > 80) return "novo_parece_headline_ou_url";
  if (prop === "jobtitle" && atualTexto !== "" && NIVEL_SOLTO.has(chave(novo)) && chave(atualTexto).split(" ").length >= 2) {
    return "novo_menos_especifico";
  }
  return null;
}

function emailDe(linha: Linha, atual: ContatoAtual | null): string {
  return (texto(linha.email) || texto(atual?.properties.email)).toLowerCase();
}

/**
 * O que o Mind escreveu por último nessa propriedade, ou null quando nunca escreveu (chave ausente
 * em `ultimo_escrito`). Chave presente com valor nulo conta como "escrevemos vazio" ("").
 */
function ultimoEscrito(linha: Linha, prop: string): string | null {
  const ue = linha.ultimo_escrito;
  if (!ue || typeof ue !== "object" || !Object.prototype.hasOwnProperty.call(ue, prop)) return null;
  const v = ue[prop];
  return v === null || v === undefined ? "" : String(v).trim();
}

export function planejar(linha: Linha, atual: ContatoAtual | null, defs: Definicoes): Decisao {
  const email = emailDe(linha, atual);
  const ignorados: Ignorado[] = [];
  const conflitos: Conflito[] = [];
  const substituicoes: Substituicao[] = [];
  const equivalentes: Equivalente[] = [];
  const preservados: Preservado[] = [];
  const limpezas: Limpeza[] = [];
  const base = { mind_id: linha.mind_id, email, conflitos, ignorados, substituicoes, equivalentes, preservados, limpezas };

  if (!atual) {
    const motivo = texto(linha.hubspot_id) || texto(linha.email) ? "sem_contato" : "sem_identificador";
    return { ...base, acao: "pular", motivo, propriedades: {} };
  }

  const propriedades: Record<string, string> = {};
  const forcar = linha.forcar === true;
  const preservar = (prop: string, atualTexto: string, desejado: string) =>
    preservados.push({ email, propriedade: prop, atual: atualTexto, desejado, motivo: "editado_no_hubspot" });

  // Texto livre (cargo, empresa): atualiza, mas sem duplicar grafia; troca real vai para
  // `substituicoes`, para a Adriana rever — a menos que o valor de lá não seja o que o Mind
  // escreveu por último: aí foi editado no HubSpot e fica (`preservados`).
  const textoLivre = (prop: string, desejado: string | null, chaveDe: (v: unknown) => string) => {
    const novo = texto(desejado);
    if (!novo) return;
    if (chaveDe(novo) === "") {
      ignorados.push({ email, propriedade: prop, valor: novo, motivo: "sem_conteudo" });
      return;
    }
    const cur = atual.properties[prop];
    if (vazio(cur)) {
      const p = pior(prop, "", novo);
      if (p) {
        ignorados.push({ email, propriedade: prop, valor: novo, motivo: p });
        return;
      }
      propriedades[prop] = novo;
      return;
    }
    const atualTexto = String(cur).trim();
    const kAtual = chaveDe(atualTexto);
    const kNovo = chaveDe(novo);
    if (kAtual === kNovo) return;
    const p = pior(prop, atualTexto, novo);
    if (p) {
      equivalentes.push({ email, propriedade: prop, atual: atualTexto, novo, motivo: p });
      return;
    }
    // "Gerente" → "Gerente de Comunicação Interna" enriquece: a contenção não segura o valor mais rico
    const enriquece = prop === "jobtitle" && NIVEL_SOLTO.has(kAtual) && kNovo.split(" ").length >= 2 && kNovo.includes(kAtual);
    const motivo = equivalente(kAtual, kNovo);
    if (motivo && !enriquece) {
      equivalentes.push({ email, propriedade: prop, atual: atualTexto, novo, motivo });
      return;
    }
    const ultimo = ultimoEscrito(linha, prop);
    if (!forcar && ultimo !== null && chaveDe(ultimo) !== kAtual) {
      preservar(prop, atualTexto, novo);
      return;
    }
    propriedades[prop] = novo;
    substituicoes.push({ email, propriedade: prop, atual: atualTexto, novo });
  };
  textoLivre("jobtitle", linha.jobtitle, chave);
  textoLivre("company", linha.company, chaveEmpresa);

  // Quem não é lead não tem ICP nem JTBD (regra da Adriana, 23/09/2026): o que estiver lá é limpo,
  // manual ou nosso, junto com o resumo que os cita. O "antes" fica no registro da escrita.
  if (linha.nao_lead === true) {
    for (const prop of PROPRIEDADES_PERFIL) {
      const cur = atual.properties[prop];
      if (vazio(cur)) continue;
      propriedades[prop] = "";
      // o resumo tem até ~1.200 caracteres: no relatório vai só o nome; o texto fica no registro
      limpezas.push({ email, propriedade: prop, atual: prop === PROPRIEDADE_RESUMO ? "resumo" : String(cur).trim(), motivo: "nao_e_lead" });
    }
    return { ...base, id: atual.id, acao: Object.keys(propriedades).length > 0 ? "atualizar" : "nada", propriedades };
  }

  // ICP: preenche vazio. Valor já presente só é trocado quando é o que o próprio Mind escreveu
  // por último (a classificação mudou no banco); valor manual nunca é sobrescrito — vira conflito.
  const icpDesejado = texto(linha.icp);
  if (icpDesejado) {
    const aceitos = validar(email, "icp", [icpDesejado], defs, ignorados);
    if (aceitos.length > 0) {
      const novo = aceitos[0];
      const escreverIcp = () => {
        propriedades.icp = novo;
        const confianca = linha.icp_confianca;
        if (typeof confianca === "number" && Number.isFinite(confianca)) {
          if (defs.icp_confianca) propriedades.icp_confianca = String(confianca);
          else ignorados.push({ email, propriedade: "icp_confianca", valor: String(confianca), motivo: "propriedade_inexistente" });
        }
      };
      const cur = atual.properties.icp;
      if (vazio(cur)) {
        escreverIcp();
      } else {
        const atualTexto = String(cur).trim();
        if (atualTexto.toLowerCase() !== novo.toLowerCase()) {
          const ultimo = ultimoEscrito(linha, "icp");
          if (forcar || (ultimo !== null && ultimo.toLowerCase() === atualTexto.toLowerCase())) {
            escreverIcp();
            substituicoes.push({ email, propriedade: "icp", atual: atualTexto, novo });
          } else {
            conflitos.push({ email, propriedade: "icp", atual: atualTexto, desejado: novo });
          }
        }
      }
    }
  }

  // JTBD (multi-seleção). Quando o que está no HubSpot é exatamente o que o Mind escreveu por último
  // ("nosso e intacto"), o banco manda: o conjunto atual substitui o anterior — inclusive removendo job
  // que a regra rebaixou. Quando alguém marcou algo lá (ou nunca escrevemos), união: nunca se apaga o
  // que a pessoa já tem. Plano sem job + nosso intacto = limpa a propriedade (vai para `substituicoes`).
  const jtbdDesejado = unicos((Array.isArray(linha.jtbd) ? linha.jtbd : []).map(texto).filter((v) => v !== ""));
  const defJtbd = defs.jtbd;
  if (defJtbd) {
    const atuais = partes(String(atual.properties.jtbd ?? ""));
    const ultimoJtbd = ultimoEscrito(linha, "jtbd");
    const nossoIntacto = ultimoJtbd !== null && mesmoConjunto(partes(ultimoJtbd), atuais);
    const aceitos = jtbdDesejado.length > 0 ? validar(email, "jtbd", jtbdDesejado, defs, ignorados) : [];
    if (aceitos.length > 0) {
      const alvo = nossoIntacto ? unirJtbd([], aceitos, defJtbd) : unirJtbd(atuais, aceitos, defJtbd);
      if (!mesmoConjunto(atuais, alvo)) {
        propriedades.jtbd = alvo.join(";");
        if (nossoIntacto && atuais.some((v) => !alvo.some((a) => a.toLowerCase() === v.toLowerCase()))) {
          substituicoes.push({ email, propriedade: "jtbd", atual: atuais.join(";"), novo: propriedades.jtbd });
        }
      }
    } else if (jtbdDesejado.length === 0 && nossoIntacto && atuais.length > 0) {
      propriedades.jtbd = "";
      substituicoes.push({ email, propriedade: "jtbd", atual: atuais.join(";"), novo: "" });
    }
  } else if (jtbdDesejado.length > 0) {
    validar(email, "jtbd", jtbdDesejado, defs, ignorados);
  }

  // Resumo da inteligência (texto multi-linha): vazio → escreve; igual → nada; diferente → só
  // quando o que está lá é o que o Mind escreveu por último (ou nunca escrevemos).
  const resumoDesejado = texto(linha.resumo);
  if (resumoDesejado) {
    if (!defs[PROPRIEDADE_RESUMO]) {
      // `valor` fixo de propósito: o texto tem até ~1.200 caracteres e o relatório agrega por valor.
      ignorados.push({ email, propriedade: PROPRIEDADE_RESUMO, valor: "resumo", motivo: "propriedade_inexistente" });
    } else {
      const cur = texto(atual.properties[PROPRIEDADE_RESUMO]);
      if (cur === "") {
        propriedades[PROPRIEDADE_RESUMO] = resumoDesejado;
      } else if (cur !== resumoDesejado) {
        const ultimo = ultimoEscrito(linha, PROPRIEDADE_RESUMO);
        if (ultimo !== null && ultimo !== cur) preservar(PROPRIEDADE_RESUMO, cur, resumoDesejado);
        else propriedades[PROPRIEDADE_RESUMO] = resumoDesejado;
      }
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
