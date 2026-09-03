import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";
import { checkoutRastreado, type CheckoutOficial } from "../_shared/checkout-attribution.ts";

function serviceKey() {
  try {
    const configured = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as { default?: unknown };
    if (typeof configured.default === "string") return configured.default;
  } catch { /* compatibilidade abaixo */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

function error(status: number, code: string) {
  return new Response(JSON.stringify({ ok: false, error: code }), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET" && req.method !== "HEAD") return error(405, "method_not_allowed");
  const eventId = new URL(req.url).pathname.split("/").filter(Boolean).at(-1) ?? "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(eventId)) {
    return error(404, "checkout_not_found");
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const key = serviceKey();
  if (!supabaseUrl || !key) return error(503, "configuration_missing");
  const admin = createClient(supabaseUrl, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error: rpcError } = await admin.rpc("mind_checkout_click_registrar", {
    p_event_id: eventId,
    p_request_id: crypto.randomUUID(),
  });
  if (rpcError || data?.ok !== true) return error(404, "checkout_not_found");

  const checkout: CheckoutOficial = {
    url: String(data.checkout_url),
    motivo: String(data.reason ?? "checkout"),
    ofertaCodigo: null,
    cupom: null,
    caminho: "ledger",
  };
  const channel = data.channel === "app" ? "app" : "whatsapp";
  const destination = checkoutRastreado(checkout, eventId, channel, String(data.agent_id ?? "ai_agent"));
  return new Response(null, {
    status: 302,
    headers: {
      Location: destination,
      "Cache-Control": "no-store, private",
      "Referrer-Policy": "no-referrer",
      "X-Robots-Tag": "noindex, nofollow",
      "X-Content-Type-Options": "nosniff",
    },
  });
});
