// Sincroniza diariamente a disponibilidade pública de VIP/Prime a partir do site oficial.
// A Edge apenas lê/valida o site e chama o RPC canônico no banco.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SITE_URL = "https://mindsummit.com.br/";
type Category = "vip" | "prime";

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function parseSoldPercent(html: string, category: Category): number | null {
  const article = new RegExp(
    `<article[^>]*data-tier-card=["']${category}["'][\\s\\S]*?<span[^>]*class=["'][^"']*progresso-label[^"']*["'][^>]*>\\s*(\\d{1,3})%\\s+dos\\s+lugares\\s+vendidos\\s*</span>`,
    "i",
  );
  const direct = html.match(article);
  if (direct) return Number(direct[1]);

  const categoryRegex = new RegExp(`>${category}<`, "i");
  const marker = categoryRegex.exec(html);
  if (!marker || marker.index === undefined) return null;
  const start = Math.max(0, marker.index - 3000);
  const end = Math.min(html.length, marker.index + 6000);
  const window = html.slice(start, end);
  const localMarker = marker.index - start;
  let best: { value: number; distance: number } | null = null;
  for (const m of window.matchAll(/(\d{1,3})%\s+dos\s+lugares\s+vendidos/gi)) {
    const value = Number(m[1]);
    const distance = Math.abs((m.index ?? 0) - localMarker);
    if (!best || distance < best.distance) best = { value, distance };
  }
  return best?.value ?? null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST" && req.method !== "GET") {
    return json(405, { ok: false, error: "method_not_allowed" });
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);
  try {
    const response = await fetch(SITE_URL, {
      signal: controller.signal,
      headers: { "User-Agent": "MindAgentAvailabilitySync/2.0" },
    });
    if (!response.ok) {
      return json(502, { ok: false, error: `site_http_${response.status}` });
    }

    const html = await response.text();
    const vip = parseSoldPercent(html, "vip");
    const prime = parseSoldPercent(html, "prime");
    if (vip === null || prime === null || ![vip, prime].every((v) => Number.isInteger(v) && v >= 0 && v <= 100)) {
      console.error(JSON.stringify({ fn: "sync-disponibilidade", erro: "percentual_invalido", vip, prime }));
      return json(422, { ok: false, error: "percentual_invalido", vip, prime });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const consultadoEm = new Date().toISOString();
    const { data, error } = await supabase.rpc("mindagent_sync_disponibilidade", {
      p_vip: vip,
      p_prime: prime,
      p_consultado_em: consultadoEm,
    });
    if (error) {
      console.error(JSON.stringify({ fn: "sync-disponibilidade", erro: "rpc", detalhe: error.message }));
      return json(500, { ok: false, error: "rpc_falhou" });
    }

    const result = { ok: true, fonte: SITE_URL, ...data };
    console.info(JSON.stringify({ fn: "sync-disponibilidade", ...result }));
    return json(200, result);
  } catch (e) {
    const isTimeout = e instanceof DOMException && e.name === "AbortError";
    console.error(JSON.stringify({ fn: "sync-disponibilidade", erro: isTimeout ? "timeout" : "inesperado", detalhe: String(e) }));
    return json(isTimeout ? 504 : 500, { ok: false, error: isTimeout ? "timeout" : "erro_inesperado" });
  } finally {
    clearTimeout(timeout);
  }
});
