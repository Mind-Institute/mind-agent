// GUARDRAIL DE PREÇO — o que o agente pode afirmar sobre dinheiro.
//
// ============================================================================
// TRÊS GERAÇÕES, E POR QUE CADA UMA CAIU
//
// 1ª — `JSON.stringify(payload).match(/\d+/g)`: qualquer número do JSON virava preço.
//      Com o Kit, isso autorizava data (2026, 16, 17), percentual (10/20/30/35/40),
//      duração (90 dias, 2 horas), quantidade (4 workshops, 5/10/15/20 ingressos),
//      número de lote e id de produto da Eduzz. `R$ 90` passava.
//
// 2ª — whitelist por CAMPO MONETÁRIO + total como múltiplo de qualquer unitário. Matou
//      os falsos positivos, mas ainda aceitava total na FAIXA ERRADA
//      ("10 pessoas = R$ 14.820", que é 10 × 1.482, o unitário de 5–9) e total formado
//      a partir de `economia_por_ingresso`.
//
// 3ª — esta. As duas anteriores achatavam tudo num `Set<number>`: bastava o número
//      existir em ALGUM campo oficial. Isso deixava passar VALOR CERTO NO PAPEL ERRADO:
//
//        "O Mind custa R$ 165"    165 é economia por ingresso, não preço
//        "O Mind custa R$ 137"    137 é parcela, não preço
//        "Para 10 pessoas, R$ 1.482 por pessoa"    1.482 é o unitário de 5–9;
//                                                  para 10, Mind é 1.318
//        "Para 10 pessoas, o desconto é 10%"       o tier de 10 é 20%
//        "R$ 1.318,99"            passava porque a regex parava antes dos centavos
//
// ============================================================================
// O CONTRATO
//
// Cada valor em R$ da resposta vira uma AFIRMAÇÃO com três coordenadas, lidas do
// próprio texto, e é validada contra o payload nas três ao mesmo tempo:
//
//   PAPEL         preço de oferta · unitário do tier · total · parcela · economia
//   FAIXA         a quantidade que a resposta afirma decide qual tier vale
//   EXPERIÊNCIA   nomeou Mind/VIP/Prime? então o valor não pode vir de outra
//
// Regra de faixa, explícita: **quando a resposta afirma uma quantidade, o tier tem de
// bater; quando ela não afirma nenhuma, basta o papel bater.** Sem quantidade não existe
// tier aplicável para violar — e exigir uma faria o guardrail barrar "12x de R$ 137",
// que é a condição da oferta base.
//
// Uma assimetria deliberada entre citar e calcular: com quantidade abaixo da primeira
// faixa, um UNITÁRIO pode ser o preço cheio (não há desconto abaixo de 5, e o número é
// fato), mas um TOTAL é barrado — total é conta, e conta sem faixa aplicável não se
// confere. Errar para o lado de chamar gente é o lado certo aqui.
//
// PERCENTUAL também é validado: com quantidade, tem de ser o desconto do tier aplicável;
// sem quantidade, tem de ser o desconto de algum tier do payload. Payload sem tiers não
// autoriza percentual nenhum.
//
// A agenda (`mindagent_chat_search`) fica fora: não é fonte autoritativa de preço, e um
// número solto num texto de sessão ou FAQ não deve autorizar cotação.
//
// Este módulo não tem import: é função pura sobre o payload, testada sem subir a Edge
// Function (`tests/vendedor_guardrail_preco.mjs`).
// ============================================================================

/** O que um valor monetário É, dentro da Intelligence comercial do Summit. */
export type Papel = "oferta" | "cheio" | "unitario" | "economia" | "parcela";

/** Um valor do payload, com as coordenadas que lhe dão sentido. */
export type Fato = {
  papel: Papel;
  valor: number;
  /** `mind` · `vip` · `prime`, ou null quando o payload não diz. */
  experiencia: string | null;
  /** A faixa de volume a que pertence, ou null quando é da oferta base. */
  aPartirDe: number | null;
};

export type Oficiais = {
  fatos: Fato[];
  /** Desconto de cada faixa, para validar percentual. */
  faixas: { aPartirDe: number; percentual: number | null }[];
};

// ─────────────────────────────────────────────────────────────── leitura do texto

// Captura os centavos de propósito: `R$ 1.318,99` não pode passar por "1.318".
const MOEDA = /R\$\s?(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?|\d+(?:,\d{1,2})?)/g;
const PERCENTUAL = /(\d{1,3})\s*%/g;

// Quantidade de ingressos que a resposta afirma. Só conta número colado num substantivo
// de gente/ingresso, ou logo depois de "a partir de" — `12x` e `90 dias` não são compra.
const QUANTIDADE =
  /(?:a partir de\s+)?(\d{1,4})\s*(pessoas?|ingressos?|participantes?|colaboradores?|convites?|vagas?|lugares?)/gi;

const EXPERIENCIAS = ["mind", "vip", "prime"];

// Marcadores de papel, lidos na vizinhança imediata do valor. A ordem de teste importa:
// "economiza R$ 165 por ingresso" é economia, não unitário.
const MARCA_PARCELA_ANTES = /\d+\s*x\s*(?:de\s*)?$/i;
const MARCA_PARCELA_DEPOIS = /^\s*(?:por m[êe]s|mensais|ao m[êe]s)/i;
const MARCA_ECONOMIA = /(econom|poupa|abatimento|desconto de)\S*\s*(?:de\s*)?$/i;
const MARCA_UNITARIO = /^\s*[,)]?\s*(por pessoa|por ingresso|por participante|por convite|por cabe[çc]a|cada)/i;

/** "1.318,99" → 1318.99 · "1.647" → 1647 */
function numeroBR(bruto: string): number {
  return Number(bruto.replace(/\./g, "").replace(",", "."));
}

function experienciaDe(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = v.toLowerCase();
  return EXPERIENCIAS.find((e) => new RegExp(`\\b${e}\\b`).test(t)) ?? null;
}

function valoresEmReais(texto: string): number[] {
  return [...texto.matchAll(MOEDA)].map((m) => numeroBR(m[1])).filter((n) => Number.isFinite(n) && n > 0);
}

// ─────────────────────────────────────────────────────────── leitura do payload

/**
 * Percorre o payload enviado ao modelo e extrai os fatos monetários com papel, faixa e
 * experiência. Campo desconhecido não vira dinheiro; `inclusoes` reusa a chave `valor`
 * para texto de comparativo ("4 à sua escolha"), e texto nunca é dinheiro.
 *
 * A experiência é herdada do contexto: `inclusoes.experiencias[].ofertas_vigentes[]` não
 * repete a categoria, mas o pai tem `chave`.
 */
export function precosOficiais(dadosOficiais: unknown): Oficiais {
  const fatos: Fato[] = [];
  const faixas: { aPartirDe: number; percentual: number | null }[] = [];

  const anda = (no: unknown, expPai: string | null): void => {
    if (Array.isArray(no)) {
      no.forEach((n) => anda(n, expPai));
      return;
    }
    if (!no || typeof no !== "object") return;
    const obj = no as Record<string, unknown>;

    const eleg = obj["elegibilidade"] as Record<string, unknown> | undefined;
    const exp = experienciaDe(eleg?.["categoria"]) ??
      experienciaDe(obj["categoria"]) ??
      experienciaDe(obj["chave"]) ??
      experienciaDe(obj["experiencia"]) ??
      expPai;

    // Linha de faixa de volume, reconhecida pela FORMA — não pelo caminho no JSON.
    const aPartirDe = obj["a_partir_de_ingressos"];
    const unitario = obj["valor_por_ingresso_com_desconto"];
    if (typeof aPartirDe === "number" && aPartirDe > 0 && typeof unitario === "number" && unitario > 0) {
      const faixa = Math.round(aPartirDe);
      const pct = obj["desconto_percentual"];
      faixas.push({ aPartirDe: faixa, percentual: typeof pct === "number" ? Math.round(pct) : null });

      fatos.push({ papel: "unitario", valor: Math.round(unitario), experiencia: exp, aPartirDe: faixa });
      const cheio = obj["valor_cheio_por_ingresso"];
      if (typeof cheio === "number") fatos.push({ papel: "cheio", valor: Math.round(cheio), experiencia: exp, aPartirDe: faixa });
      const econ = obj["economia_por_ingresso"];
      if (typeof econ === "number") fatos.push({ papel: "economia", valor: Math.round(econ), experiencia: exp, aPartirDe: faixa });
      const parc = obj["parcelamento_com_desconto"];
      if (typeof parc === "string") {
        for (const v of valoresEmReais(parc)) fatos.push({ papel: "parcela", valor: v, experiencia: exp, aPartirDe: faixa });
      }
      return; // os campos desta linha já foram lidos com o papel certo
    }

    // Oferta: preço base e sua condição de pagamento, fora de qualquer faixa.
    if (typeof obj["valor"] === "number" && Number.isFinite(obj["valor"] as number)) {
      fatos.push({ papel: "oferta", valor: Math.round(obj["valor"] as number), experiencia: exp, aPartirDe: null });
    }
    if (typeof obj["condicoes_pagamento"] === "string") {
      for (const v of valoresEmReais(obj["condicoes_pagamento"] as string)) {
        fatos.push({ papel: "parcela", valor: v, experiencia: exp, aPartirDe: null });
      }
    }

    for (const [chave, valor] of Object.entries(obj)) {
      if (chave === "valor" || chave === "condicoes_pagamento") continue;
      anda(valor, exp);
    }
  };

  anda(dadosOficiais, null);
  return { fatos, faixas };
}

// ─────────────────────────────────────────────────────────── afirmações da resposta

/** A faixa que vale para uma quantidade: a de maior `aPartirDe` que ainda cabe. */
export function faixaDe(quantidade: number, oficiais: Oficiais): number | null {
  const cabem = oficiais.faixas.filter((f) => f.aPartirDe <= quantidade).map((f) => f.aPartirDe);
  return cabem.length ? Math.max(...cabem) : null;
}

export function quantidadesDitas(texto: string): number[] {
  const saida = new Set<number>();
  for (const m of texto.matchAll(QUANTIDADE)) {
    const n = Number(m[1]);
    if (Number.isFinite(n) && n > 0) saida.add(n);
  }
  return [...saida];
}

export function experienciasDitas(texto: string): string[] {
  const t = texto.toLowerCase();
  return EXPERIENCIAS.filter((e) => new RegExp(`\\b${e}\\b`).test(t));
}

/** O papel que a vizinhança do valor lhe atribui. */
function papelDaAfirmacao(antes: string, depois: string, temQuantidade: boolean): Papel | "total" {
  if (MARCA_PARCELA_ANTES.test(antes) || MARCA_PARCELA_DEPOIS.test(depois)) return "parcela";
  if (MARCA_ECONOMIA.test(antes)) return "economia";
  if (MARCA_UNITARIO.test(depois)) return "unitario";
  return temQuantidade ? "total" : "oferta";
}

export type Afirmacao = {
  texto: string;
  valor: number;
  papel: Papel | "total" | "percentual";
  quantidade: number | null;
  experiencias: string[];
};

/** Divide em orações para que o contexto de uma não vaze para a outra. */
function oracoes(answer: string): string[] {
  return answer.split(/(?<=[.!?;])\s+|\n+/).filter((s) => s.trim());
}

export function afirmacoes(answer: string): Afirmacao[] {
  const qtdGeral = quantidadesDitas(answer);
  const expGeral = experienciasDitas(answer);
  const saida: Afirmacao[] = [];

  for (const oracao of oracoes(answer)) {
    const qtdLocal = quantidadesDitas(oracao);
    const expLocal = experienciasDitas(oracao);
    const quantidades = qtdLocal.length ? qtdLocal : qtdGeral;
    const experiencias = expLocal.length ? expLocal : expGeral;
    const quantidade = quantidades.length ? Math.max(...quantidades) : null;

    for (const m of oracao.matchAll(MOEDA)) {
      const i = m.index ?? 0;
      saida.push({
        texto: m[0],
        valor: numeroBR(m[1]),
        papel: papelDaAfirmacao(oracao.slice(Math.max(0, i - 40), i), oracao.slice(i + m[0].length, i + m[0].length + 30), quantidade !== null),
        quantidade,
        experiencias,
      });
    }
    for (const m of oracao.matchAll(PERCENTUAL)) {
      saida.push({ texto: m[0], valor: Number(m[1]), papel: "percentual", quantidade, experiencias });
    }
  }
  return saida;
}

// ───────────────────────────────────────────────────────────────── validação

function combina(fato: Fato, experiencias: string[]): boolean {
  // Fato sem experiência serve a qualquer afirmação — é o caso do caminho legado, cujo
  // payload não carrega categoria. Fato COM experiência só serve se ela foi nomeada.
  return fato.experiencia === null || experiencias.length === 0 || experiencias.includes(fato.experiencia);
}

export function afirmacaoEhOficial(a: Afirmacao, oficiais: Oficiais): boolean {
  if (!Number.isFinite(a.valor)) return false;
  const faixa = a.quantidade !== null ? faixaDe(a.quantidade, oficiais) : null;

  if (a.papel === "percentual") {
    const candidatas = a.quantidade !== null
      ? oficiais.faixas.filter((f) => f.aPartirDe === faixa)
      : oficiais.faixas;
    return candidatas.some((f) => f.percentual === a.valor);
  }

  if (a.papel === "total") {
    // Conta: quantidade × unitário do tier aplicável, na experiência nomeada. Sem tier
    // aplicável não há total conferível.
    if (a.quantidade === null || faixa === null) return false;
    return oficiais.fatos.some((f) =>
      f.papel === "unitario" && f.aPartirDe === faixa && combina(f, a.experiencias) &&
      f.valor * (a.quantidade as number) === a.valor
    );
  }

  const papeis: Papel[] = a.papel === "unitario"
    // Unitário abaixo da primeira faixa é o preço cheio: não há desconto ali, e o número
    // é fato. Dentro de uma faixa, tem de ser o unitário daquela faixa.
    ? (faixa === null ? ["oferta", "cheio"] : ["unitario"])
    : a.papel === "oferta"
    ? ["oferta", "cheio"]
    : [a.papel];

  return oficiais.fatos.some((f) =>
    papeis.includes(f.papel) &&
    f.valor === a.valor &&
    combina(f, a.experiencias) &&
    // Com quantidade afirmada, o fato tem de ser da faixa aplicável (ou da oferta base,
    // quando nenhuma faixa cobre). Sem quantidade, qualquer faixa serve: o que se cobra
    // é o papel.
    (a.quantidade === null || f.aPartirDe === faixa || (faixa === null && f.aPartirDe === null))
  );
}

/**
 * A primeira afirmação monetária da resposta que o payload NÃO sustenta, como o agente
 * escreveu — ou `null` quando tudo o que ela afirma sobre dinheiro confere.
 */
export function precoInventado(answer: string, oficiais: Oficiais): string | null {
  for (const a of afirmacoes(answer)) {
    if (!afirmacaoEhOficial(a, oficiais)) return a.texto;
  }
  return null;
}
