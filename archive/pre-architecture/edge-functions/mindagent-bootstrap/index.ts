import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const PROJECT_PUBLISHABLE_KEY = "sb_publishable__wYRbYyBgK_MBfqmLpiZNg_Z8iJNxvc";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function json(body: unknown, status = 200, requestId?: string) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": status === 200
        ? "public, max-age=60, stale-while-revalidate=300"
        : "no-store",
      ...(requestId ? { "X-Request-Id": requestId } : {}),
    },
  });
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET") {
    return json({ ok: false, error: "METHOD_NOT_ALLOWED" }, 405, requestId);
  }

  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const eventosIndex = parts.lastIndexOf("eventos");
  const pathSlug = eventosIndex >= 0 ? parts[eventosIndex + 1] : null;
  const eventSlug = pathSlug || url.searchParams.get("event_slug") || "mind-summit-2026";

  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(eventSlug) || eventSlug.length > 80) {
    return json({ ok: false, error: "INVALID_EVENT_SLUG" }, 400, requestId);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  if (!supabaseUrl) {
    return json({ ok: false, error: "SERVICE_UNAVAILABLE" }, 503, requestId);
  }

  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8000);
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/mindagent_bootstrap`, {
      method: "POST",
      headers: {
        "apikey": PROJECT_PUBLISHABLE_KEY,
        "Authorization": `Bearer ${PROJECT_PUBLISHABLE_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_event_slug: eventSlug }),
      signal: controller.signal,
    });
    clearTimeout(timeout);

    if (!response.ok) {
      console.error(JSON.stringify({ requestId, error: "DATABASE_REQUEST_FAILED", status: response.status }));
      return json({ ok: false, error: "SERVICE_UNAVAILABLE" }, 503, requestId);
    }

    const payload = await response.json();
    if (!payload?.evento) {
      return json({ ok: false, error: "EVENT_NOT_FOUND" }, 404, requestId);
    }
    return json(payload, 200, requestId);
  } catch (error) {
    console.error(JSON.stringify({
      requestId,
      error: error instanceof DOMException && error.name === "AbortError"
        ? "DATABASE_TIMEOUT"
        : "UNEXPECTED_ERROR",
    }));
    return json({ ok: false, error: "SERVICE_UNAVAILABLE" }, 503, requestId);
  }
});
