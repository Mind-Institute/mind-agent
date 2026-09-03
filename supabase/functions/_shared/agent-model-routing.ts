// Seleção conservadora de modelo para o Agent.
// O rápido só atende fatos inequívocos do evento. Todo o restante permanece no
// modelo completo; o runtime ainda promove para o completo diante de tool,
// abstinência, erro de contrato ou indisponibilidade do rápido.

export type ModelDecision = { model: string; reason: string };

export function modeloInicialDoTurno(
  mensagem: string,
  rota: string | null,
  historico: number,
  modeloRapido: string,
  modeloCompleto: string,
): ModelDecision {
  if (modeloRapido === modeloCompleto) return { model: modeloCompleto, reason: "config_unica" };
  if (rota !== "concierge_summit") return { model: modeloCompleto, reason: "rota_complexa" };

  const texto = mensagem.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  const exigeCompleto = mensagem.length > 180 || historico > 8 ||
    /\b(compar\w*|recomend\w*|melhor|vale a pena|por que|porque|explic\w*|estrateg\w*|empresa\w*|equipe\w*|lideran\w*|desafio\w*|objetiv\w*|vender|comprar|upgrade|preco|valor|desconto|ingresso)\b/.test(texto);
  const factualSimples =
    /\b(onde fica|qual (?:e |a )?sala|que horas|qual (?:e |o )?horario|quando (?:comeca|termina)|endereco|mapa|wifi|wi-fi|banheiro|estacionamento|credenciamento|guarda.?volumes|almoco)\b/.test(texto);

  return factualSimples && !exigeCompleto
    ? { model: modeloRapido, reason: "factual_simples" }
    : { model: modeloCompleto, reason: exigeCompleto ? "complexidade_detectada" : "ambiguidade_conservadora" };
}

export function saidaEstruturadaMinimaValida(outputText: string) {
  try {
    const value = JSON.parse(outputText) as Record<string, unknown>;
    return Boolean(value) && typeof value === "object" && !Array.isArray(value) &&
      typeof value.answer === "string" && value.answer.trim().length > 0;
  } catch {
    return false;
  }
}
