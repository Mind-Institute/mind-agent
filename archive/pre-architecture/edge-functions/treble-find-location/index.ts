const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

function json(status: number, body: unknown, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...JSON_HEADERS, ...extra },
  });
}

function safeEqual(left: string, right: string) {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

function getPublishableKey() {
  const raw = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      if (typeof parsed?.default === "string") return parsed.default;
      const first = Object.values(parsed).find((value) => typeof value === "string");
      if (typeof first === "string") return first;
    } catch {
      // Fallback below.
    }
  }
  return Deno.env.get("SUPABASE_ANON_KEY") ?? "";
}

function buildAnswer(matches: Array<Record<string, unknown>>) {
  if (matches.length === 0) {
    return "Não encontrei esse local nas informações oficiais do evento. Posso tentar pelo nome do palco, sala, estande ou ativação.";
  }

  const match = matches[0];
  const name = String(match.name ?? "Local encontrado");
  const directions = typeof match.how_to_get_there === "string"
    ? match.how_to_get_there.trim()
    : "";

  if (directions) {
    return directions;
  }

  const details = [
    match.venue ? `no espaço ${match.venue}` : "",
    match.parent ? `próximo de ${match.parent}` : "",
    match.floor ? `no ${match.floor}` : "",
  ].filter(Boolean);

  if (details.length > 0) {
    return `${name} fica ${details.join(", ")}.`;
  }

  return `Encontrei ${name} na base oficial, mas a posição exata no mapa ainda não foi cadastrada.`;
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const startedAt = Date.now();

  if (req.method !== "GET") {
    return json(405, {
      ok: false,
      error: { code: "method_not_allowed", message: "Use GET." },
      request_id: requestId,
    }, { "Allow": "GET" });
  }

  const expectedToken = Deno.env.get("TREBLE_READ_TOKEN");
  if (!expectedToken) {
    console.error(JSON.stringify({ request_id: requestId, status: 503, reason: "missing_secret" }));
    return json(503, {
      ok: false,
      error: { code: "service_unavailable", message: "Integração temporariamente indisponível." },
      request_id: requestId,
    });
  }

  const authorization = req.headers.get("Authorization") ?? "";
  const suppliedToken = authorization.startsWith("Bearer ")
    ? authorization.slice(7).trim()
    : (req.headers.get("Bearer") ?? "").trim();

  if (!suppliedToken || !safeEqual(suppliedToken, expectedToken)) {
    console.warn(JSON.stringify({ request_id: requestId, status: 401, reason: "unauthorized" }));
    return json(401, {
      ok: false,
      error: { code: "unauthorized", message: "Credencial inválida." },
      request_id: requestId,
    });
  }

  const url = new URL(req.url);
  const eventSlug = (
    url.searchParams.get("event_slug") ??
    url.searchParams.get("eventSlug") ??
    ""
  ).trim();
  const query = (url.searchParams.get("query") ?? "").trim();

  if (!/^[a-z0-9-]{2,80}$/.test(eventSlug) || query.length < 2 || query.length > 120) {
    return json(400, {
      ok: false,
      error: {
        code: "invalid_request",
        message: "Informe event_slug válido e query entre 2 e 120 caracteres.",
      },
      request_id: requestId,
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const publishableKey = getPublishableKey();
  if (!supabaseUrl || !publishableKey) {
    console.error(JSON.stringify({ request_id: requestId, status: 503, reason: "missing_supabase_config" }));
    return json(503, {
      ok: false,
      error: { code: "service_unavailable", message: "Integração temporariamente indisponível." },
      request_id: requestId,
    });
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);

  try {
    const rpcResponse = await fetch(`${supabaseUrl}/rest/v1/rpc/treble_find_location`, {
      method: "POST",
      headers: {
        "apikey": publishableKey,
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: JSON.stringify({ p_event_slug: eventSlug, p_query: query }),
      signal: controller.signal,
    });

    if (!rpcResponse.ok) {
      console.error(JSON.stringify({
        request_id: requestId,
        status: 502,
        rpc_status: rpcResponse.status,
        duration_ms: Date.now() - startedAt,
        event_slug: eventSlug,
      }));
      return json(502, {
        ok: false,
        error: { code: "upstream_error", message: "Não foi possível consultar os locais agora." },
        request_id: requestId,
      });
    }

    const raw = await rpcResponse.json();
    const matches = Array.isArray(raw) ? raw : [];
    const needsContentUpdate = matches.length > 0 &&
      !matches[0]?.venue && !matches[0]?.parent && !matches[0]?.floor;

    console.info(JSON.stringify({
      request_id: requestId,
      status: 200,
      duration_ms: Date.now() - startedAt,
      event_slug: eventSlug,
      matches: matches.length,
    }));

    return json(200, {
      answer: buildAnswer(matches),
    });
  } catch (error) {
    const isTimeout = error instanceof DOMException && error.name === "AbortError";
    console.error(JSON.stringify({
      request_id: requestId,
      status: isTimeout ? 504 : 502,
      reason: isTimeout ? "timeout" : "upstream_failure",
      duration_ms: Date.now() - startedAt,
      event_slug: eventSlug,
    }));
    return json(isTimeout ? 504 : 502, {
      ok: false,
      error: {
        code: isTimeout ? "timeout" : "upstream_error",
        message: "Não foi possível consultar os locais agora.",
      },
      request_id: requestId,
    });
  } finally {
    clearTimeout(timeout);
  }
});
