export type RotaVenda = "summit_b2c" | "summit_b2b";

function normalizar(texto: string): string {
  return texto.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

export function rotaComercialRapida(
  mensagem: string,
  historicoValue: unknown,
): { rota: RotaVenda | null; motivo: string } {
  const atual = normalizar(mensagem);
  const historico = Array.isArray(historicoValue)
    ? historicoValue
      .filter((m: Record<string, unknown>) => m?.papel === "lead" && typeof m?.conteudo === "string")
      .slice(-8)
      .map((m: Record<string, unknown>) => String(m.conteudo))
      .join(" ")
    : "";
  const contexto = normalizar(`${historico} ${mensagem}`);

  if (/\b(nao (e|seria) (uma )?compra corporativa|compra individual|ingresso individual|so (um|1) ingresso|para mim|pra mim|para eu ir|pra eu ir)\b/.test(atual)) {
    return { rota: "summit_b2c", motivo: "b2c_explicito" };
  }

  if (
    /\b(compra corporativa|delegacao|grupo de|para (a|minha|nossa) empresa|empresa (vai|ira) pagar|levar (a|minha|nossa) equipe|levar (o|meu|nosso) time|varios ingressos|multiplos ingressos|patrocinio)\b/.test(contexto) ||
    /\b([2-9]|[1-9][0-9]+)\s*(ingressos?|pessoas?|participantes?|vagas?)\b/.test(contexto)
  ) {
    return { rota: "summit_b2b", motivo: "b2b_explicito" };
  }

  if (/\b(mind institute|mind dash|ja comprei|meu ingresso nao|reembolso|cancelamento|erro (no|de) pagamento|pagamento (nao|duplicado)|nao consigo acessar)\b/.test(atual)) {
    return { rota: null, motivo: "router_necessario" };
  }

  return { rota: "summit_b2c", motivo: "b2c_padrao_comercial" };
}
