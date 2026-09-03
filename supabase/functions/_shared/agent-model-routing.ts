// Seleção conservadora de modelo para o Agent.
// O rápido só atende fatos inequívocos do evento. Todo o restante permanece no
// modelo completo; o runtime ainda promove para o completo diante de tool,
// abstinência, erro de contrato ou indisponibilidade do rápido.

export type ModelDecision = { model: string; reason: string };

export function bucketDeRollout(chave: string) {
  let hash = 2166136261;
  for (const char of chave) {
    hash ^= char.codePointAt(0) ?? 0;
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0) % 100;
}

export function modeloInicialDoTurno(
  mensagem: string,
  rota: string | null,
  historico: number,
  modeloRapido: string,
  modeloCompleto: string,
  participaDoRollout = true,
): ModelDecision {
  if (modeloRapido === modeloCompleto) return { model: modeloCompleto, reason: "config_unica" };
  if (!participaDoRollout) return { model: modeloCompleto, reason: "fora_do_rollout" };
  if (rota !== "concierge_summit") return { model: modeloCompleto, reason: "rota_complexa" };

  const texto = mensagem.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();
  const seguimentoAnaforico = historico > 0 &&
    /^(e|mas|isso|essa|esse|esta|este|ela|ele|aquela|aquele|tambem|nesse caso)\b/.test(texto);
  const exigeCompleto = mensagem.length > 180 || historico >= 4 || seguimentoAnaforico ||
    /\b(compar\w*|recomend\w*|melhor|vale a pena|por que|porque|explic\w*|estrateg\w*|empresa\w*|equipe\w*|lideran\w*|desafio\w*|objetiv\w*|vender|comprar|upgrade|preco|valor|desconto|ingresso|palestra\w*|sessao|sessoes|palestrante\w*|programacao)\b/.test(texto);
  const factualSimples =
    /\b(onde fica|qual (?:e |a )?sala|que horas|qual (?:e |o )?horario|quando (?:comeca|termina)|endereco|mapa|wifi|wi-fi|banheiro|estacionamento|credenciamento|guarda.?volumes|almoco)\b/.test(texto);

  return factualSimples && !exigeCompleto
    ? { model: modeloRapido, reason: "factual_simples" }
    : { model: modeloCompleto, reason: exigeCompleto ? "complexidade_detectada" : "ambiguidade_conservadora" };
}

export function podeTentarModelo(tentativas: number, maximo: number) {
  return tentativas < maximo;
}

export function podeExecutarTool(rodadas: number, maximo: number) {
  return rodadas < maximo;
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
