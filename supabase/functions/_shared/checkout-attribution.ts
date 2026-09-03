export type CheckoutOficial = {
  url: string;
  motivo: string;
  ofertaCodigo: string | null;
  cupom: string | null;
  caminho: string;
};

const PARAMETROS_ATRIBUICAO = new Set([
  "gclid",
  "fbclid",
  "mind_canal",
  "mind_conversa",
  "mind_evento",
]);

function urlEduzz(valor: unknown): URL | null {
  if (typeof valor !== "string") return null;
  try {
    const url = new URL(valor);
    if (url.protocol !== "https:" || !/(^|\.)eduzz\.com$/i.test(url.hostname)) return null;
    return url;
  } catch {
    return null;
  }
}

function codigo(valor: unknown, fallback = "checkout") {
  const normalizado = String(valor ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, 120);
  return normalizado || fallback;
}

function assinatura(valor: string): string | null {
  const url = urlEduzz(valor);
  if (!url) return null;

  const parametros = [...url.searchParams.entries()]
    .filter(([chave]) => !chave.toLowerCase().startsWith("utm_") &&
      !chave.toLowerCase().startsWith("mind_") &&
      !PARAMETROS_ATRIBUICAO.has(chave.toLowerCase()))
    .sort(([a, av], [b, bv]) => a.localeCompare(b) || av.localeCompare(bv));
  const query = new URLSearchParams(parametros).toString();
  return `${url.origin.toLowerCase()}${url.pathname}${query ? `?${query}` : ""}`;
}

function descreverCheckout(
  objeto: Record<string, unknown>,
  caminho: Array<string | number>,
): Omit<CheckoutOficial, "url"> {
  const ofertaCodigo = typeof objeto.codigo === "string" ? objeto.codigo : null;
  const cupomDaUrl = urlEduzz(objeto.checkout_url)?.searchParams.get("cupom") ?? null;
  const cupom = typeof objeto.cupom === "string" && objeto.cupom ? objeto.cupom : cupomDaUrl;
  const categoria = typeof caminho.at(-2) === "string" ? String(caminho.at(-2)) : "";

  let motivo: string;
  if (ofertaCodigo && /^(mind|vip|prime)-lote-\d+$/i.test(ofertaCodigo)) {
    motivo = `checkout_${codigo(ofertaCodigo.split("-")[0])}_preco_regular`;
  } else if (ofertaCodigo) {
    motivo = `checkout_${codigo(ofertaCodigo)}`;
  } else if (cupom) {
    const percentual = cupom.match(/(\d{1,3})/)?.[1] ?? codigo(cupom);
    motivo = `checkout_${codigo(categoria, "oferta")}_desconto_${percentual}`;
  } else {
    motivo = `checkout_${codigo(categoria, "oferta")}`;
  }

  return {
    motivo,
    ofertaCodigo,
    cupom,
    caminho: caminho.map(String).join("."),
  };
}

export function listarCheckoutsOficiais(raiz: unknown): CheckoutOficial[] {
  const encontrados = new Map<string, CheckoutOficial>();

  const visitar = (valor: unknown, caminho: Array<string | number>) => {
    if (Array.isArray(valor)) {
      valor.forEach((item, indice) => visitar(item, [...caminho, indice]));
      return;
    }
    if (!valor || typeof valor !== "object") return;

    const objeto = valor as Record<string, unknown>;
    if (typeof objeto.checkout_url === "string" && urlEduzz(objeto.checkout_url)) {
      const item = {
        url: objeto.checkout_url,
        ...descreverCheckout(objeto, [...caminho, "checkout_url"]),
      };
      encontrados.set(assinatura(item.url)!, item);
    }
    for (const [chave, filho] of Object.entries(objeto)) {
      if (chave !== "checkout_url") visitar(filho, [...caminho, chave]);
    }
  };

  visitar(raiz, []);
  return [...encontrados.values()];
}

export function escolherCheckoutOficial(
  raiz: unknown,
  candidato: unknown,
  resposta = "",
): CheckoutOficial | null {
  const oficiais = listarCheckoutsOficiais(raiz);
  const assinaturaCandidata = typeof candidato === "string" ? assinatura(candidato) : null;
  if (assinaturaCandidata) {
    const encontrado = oficiais.find((item) => assinatura(item.url) === assinaturaCandidata);
    if (encontrado) return encontrado;
  }

  for (const item of oficiais) {
    if (resposta.includes(item.url)) return item;
    const base = assinatura(item.url);
    if (base && resposta.includes(base)) return item;
  }
  return null;
}

export async function idEventoCheckout(
  conversaId: string,
  chaveIdempotencia: string,
  checkoutUrl: string,
): Promise<string> {
  const entrada = new TextEncoder().encode(`${conversaId}\n${chaveIdempotencia}\n${checkoutUrl}`);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", entrada));
  digest[6] = (digest[6] & 0x0f) | 0x50;
  digest[8] = (digest[8] & 0x3f) | 0x80;
  const hex = [...digest.slice(0, 16)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function checkoutRastreado(
  checkout: CheckoutOficial,
  eventoId: string,
  canal: "whatsapp" | "app",
  agente: string,
): string {
  const url = new URL(checkout.url);
  const token = `ae_${eventoId.replaceAll("-", "")}`;
  const campanha = codigo(url.searchParams.get("utm_campaign"), "mind_summit_2026");
  const campanhaId = campanha === "mind_summit_2026" || campanha === "summit_2026"
    ? "ms26_ai_sales"
    : `${campanha}_ai_sales`;

  // Este link mede o envio comercial, portanto a origem é sempre o canal onde a
  // conversa aconteceu. A aquisição anterior continua registrada na conversa.
  url.searchParams.set("utm_source", canal);
  url.searchParams.set("utm_medium", "ai_agent");
  url.searchParams.set("utm_campaign", campanha);
  url.searchParams.set("utm_id", campanhaId);

  url.searchParams.set("utm_content", `${codigo(checkout.motivo)}__${token}`);
  // Redundância intencional: o espelho atual já preserva utm_content. Quando a
  // origem passar a trazer utm_term, o mesmo token também estará disponível lá.
  url.searchParams.set("utm_term", token);
  url.searchParams.set("agent_id", agente);
  // É o identificador público opaco que resolve a conversa no ledger. Não é o
  // UUID interno da conversa e não contém nome, telefone, e-mail ou documento.
  url.searchParams.set("conversation_id", eventoId);
  url.searchParams.set("mind_canal", canal);
  url.searchParams.set("mind_evento", eventoId);
  return url.toString();
}

export function checkoutCurto(eventoId: string, redirectBase: string): string | null {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(eventoId)) {
    return null;
  }
  try {
    const base = new URL(redirectBase);
    if (base.protocol !== "https:") return null;
    base.search = "";
    base.hash = "";
    base.pathname = `${base.pathname.replace(/\/+$/, "")}/${eventoId}`;
    return base.toString();
  } catch {
    return null;
  }
}

export function inserirCheckoutNaResposta(
  resposta: string,
  checkout: CheckoutOficial,
  rastreado: string,
  candidato: unknown,
): string {
  const opcoes = [typeof candidato === "string" ? candidato : "", checkout.url]
    .filter(Boolean)
    .sort((a, b) => b.length - a.length);
  for (const opcao of opcoes) {
    if (resposta.includes(opcao)) return resposta.replaceAll(opcao, rastreado);
  }
  return `${resposta.trim()}\n\n${rastreado}`.trim();
}
