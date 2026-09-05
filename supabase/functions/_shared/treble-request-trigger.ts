// Transporte do Request Trigger da Treble.
//
// O webhook de entrada confirma o recebimento imediatamente. Quando o turno termina,
// estas funcoes atualizam as mesmas user_session_keys que o fluxo sincrono devolveria
// e fazem a conversa pausada na Treble continuar.

export type TrebleSessionKey = {
  key: string;
  value: string;
};

function primeiraString(payload: Record<string, unknown>, keys: string[]): string {
  for (const key of keys) {
    const value = payload[key];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return "";
}

// `actual_response` e o campo oficial do webhook de resposta da Treble. O texto de
// `question` e a pergunta feita pelo fluxo, nao a fala do lead, e nunca pode ocupar
// esse lugar. Os aliases seguintes preservam os payloads customizados ja em producao.
export function respostaDoLeadTreble(payload: Record<string, unknown>): string {
  const direta = primeiraString(payload, [
    "actual_response",
    "mensagem", "message", "text", "resposta", "answer", "user_message",
    "user_response", "response", "user_answer", "respuesta",
  ]);
  if (direta) return direta;

  const classificada = payload.classified_answer;
  if (!classificada || typeof classificada !== "object" || Array.isArray(classificada)) return "";
  return primeiraString(classificada as Record<string, unknown>, ["text"]);
}

export function requestTriggerHabilitado(url: URL): boolean {
  const valor = url.searchParams.get("request_trigger")?.trim().toLowerCase();
  return valor === "1" || valor === "true";
}

export function chavesSessaoDaResposta(payload: unknown): TrebleSessionKey[] {
  if (!payload || typeof payload !== "object") return [];
  const raw = (payload as Record<string, unknown>).user_session_keys;
  if (!Array.isArray(raw)) return [];

  return raw.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const key = (item as Record<string, unknown>).key;
    const value = (item as Record<string, unknown>).value;
    if (typeof key !== "string" || !key.trim() || typeof value !== "string") return [];
    return [{ key: key.trim(), value }];
  });
}

export async function atualizarSessaoTreble(params: {
  sessionExternalId: string;
  userSessionKeys: TrebleSessionKey[];
  apiKey: string;
  baseUrl?: string;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
}): Promise<void> {
  const sessionExternalId = params.sessionExternalId.trim();
  if (!sessionExternalId) throw new Error("treble_session_id_missing");
  if (!params.apiKey.trim()) throw new Error("treble_api_key_missing");
  if (params.userSessionKeys.length === 0) throw new Error("treble_session_keys_missing");

  const base = (params.baseUrl ?? "https://main.treble.ai").replace(/\/+$/, "");
  const endpoint = new URL(`${base}/session/${encodeURIComponent(sessionExternalId)}/update`);
  if (endpoint.protocol !== "https:") throw new Error("treble_api_base_must_be_https");

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), params.timeoutMs ?? 8_000);
  try {
    const response = await (params.fetchImpl ?? fetch)(endpoint, {
      method: "POST",
      headers: {
        "Authorization": params.apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ user_session_keys: params.userSessionKeys }),
      signal: controller.signal,
    });
    if (!response.ok) {
      const detalhe = (await response.text().catch(() => "")).slice(0, 160);
      throw new Error(`treble_update_failed_${response.status}${detalhe ? `:${detalhe}` : ""}`);
    }
  } finally {
    clearTimeout(timeout);
  }
}
