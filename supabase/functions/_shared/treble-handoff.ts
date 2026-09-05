export const HANDOFF_REASONS = [
  "pedido_humano",
  "erro_pagamento",
  "reclamacao_seria",
  "condicao_fora_regra",
  "contrato_faturamento_procurement",
  "negociacao_personalizada",
  "duvida_factual_bloqueante",
  "b2b_5_9_alta_intencao",
  "volume_10_mais",
] as const;

export type HandoffReason = typeof HANDOFF_REASONS[number];

export function decidirHandoff(
  pedidoDoModelo: unknown,
  motivoDoModelo: unknown,
  necessidadeDoGate: boolean,
): {
  needsHuman: boolean;
  reason: HandoffReason | null;
  suppressed: boolean;
} {
  const reason = typeof motivoDoModelo === "string" &&
      (HANDOFF_REASONS as readonly string[]).includes(motivoDoModelo)
    ? motivoDoModelo as HandoffReason
    : null;
  const pedidoValido = pedidoDoModelo === true && reason !== null;
  return {
    needsHuman: necessidadeDoGate || pedidoValido,
    reason: pedidoValido ? reason : null,
    suppressed: pedidoDoModelo === true && !pedidoValido && !necessidadeDoGate,
  };
}
