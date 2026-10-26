// lead-aviso — avisa o time por e-mail quando o agente atende um lead de Institute ou Dash.
//
// Pedido da Adriana (24/09/2026): e-mail para thiago@, diego@ e adriana@joinmind.com.br (o mesmo
// e-mail para os três), pelo Resend. Quem chama é o gatilho `intelligence.lead_aviso_detectar`,
// pela porta interna (pg_net + analise_token), com o id do sinal em `intelligence.sinais_comerciais`.
//
//   entrada   { token, sinal_id }
//   secrets   RESEND_API_KEY (obrigatório)
//   config    intelligence.config: lead_aviso_destinatarios (JSON array), lead_aviso_remetente
//   saída     sinal `avisado` com o id do Resend em `observacao`; falha → `erro_envio` (reenviável
//             com `select public.mind_lead_aviso_disparar(<sinal_id>)`).
//
// Só envia sinal `novo` ou `erro_envio`: repetir a chamada não repete o e-mail.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";
import { type Dados, montarEmail } from "./mensagem.ts";

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { ok: false, erro: "method_not_allowed" });
  const url = Deno.env.get("SUPABASE_URL");
  const chave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !chave) return json(500, { ok: false, erro: "ambiente do supabase incompleto" });
  const db = createClient(url, chave, { auth: { persistSession: false, autoRefreshToken: false } });

  const corpo = await req.json().catch(() => ({})) as { token?: string; sinal_id?: string };
  const { data: cfg } = await db.rpc("analise_config");
  const esperado = (cfg as { analise_token?: string } | null)?.analise_token;
  if (!esperado || !corpo.token || corpo.token !== esperado) return json(401, { ok: false, erro: "unauthorized" });
  if (!corpo.sinal_id) return json(400, { ok: false, erro: "sinal_id obrigatório" });

  const { data, error } = await db.rpc("mind_lead_aviso_dados", { p_sinal_id: corpo.sinal_id });
  if (error || !data) return json(404, { ok: false, erro: "sinal_nao_encontrado" });
  const d = data as Dados;
  if (!["novo", "erro_envio"].includes(d.sinal.status)) return json(200, { ok: true, ignorado: d.sinal.status });

  const resendKey = Deno.env.get("RESEND_API_KEY");
  const para = Array.isArray(d.destinatarios) ? d.destinatarios.filter((e) => typeof e === "string" && e.includes("@")) : [];
  if (!resendKey || para.length === 0 || !d.remetente) {
    const motivo = !resendKey ? "RESEND_API_KEY ausente nos secrets" : "destinatários/remetente ausentes";
    await db.rpc("mind_lead_aviso_marcar", { p_sinal_id: d.sinal.id, p_status: "erro_envio", p_observacao: motivo });
    return json(500, { ok: false, erro: motivo });
  }

  const email = montarEmail(d);
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Authorization": `Bearer ${resendKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: d.remetente, to: para, subject: email.assunto, html: email.html, text: email.texto }),
  });
  const resposta = await r.json().catch(() => ({})) as { id?: string; message?: string };
  if (!r.ok) {
    const motivo = `resend ${r.status}: ${resposta.message ?? "erro"}`;
    await db.rpc("mind_lead_aviso_marcar", { p_sinal_id: d.sinal.id, p_status: "erro_envio", p_observacao: motivo });
    return json(502, { ok: false, erro: motivo });
  }
  await db.rpc("mind_lead_aviso_marcar", { p_sinal_id: d.sinal.id, p_status: "avisado", p_observacao: `resend ${resposta.id ?? ""}` });
  return json(200, { ok: true, resend_id: resposta.id ?? null, para });
});
