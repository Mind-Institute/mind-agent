// Monta o e-mail de aviso de lead. Separado do handler para ser testado em Node.

export function esc(v: unknown) {
  return String(v ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

export type Dados = {
  sinal: { id: string; vertical: string; status: string; criado_em: string };
  pessoa: { nome?: string; email?: string; whatsapp?: string; cargo?: string; empresa?: string; icp?: string; ingresso_summit_2026?: string[] };
  conversa: Array<{ papel: string; texto: string }>;
  destinatarios: string[] | null;
  remetente: string | null;
};

export function montarEmail(d: Dados) {
  const produto = d.sinal.vertical === "dash" ? "Mind Dash" : "Mind Institute";
  const p = d.pessoa;
  const quem = [p.cargo, p.empresa].filter(Boolean).join(" · ");
  const wa = p.whatsapp ? p.whatsapp.replace(/\D/g, "") : "";
  const assunto = `Lead ${produto}: ${p.nome ?? "sem nome"}${quem ? ` — ${quem}` : ""}`;
  const linhas: Array<[string, string]> = [
    ["Nome", p.nome ?? "—"],
    ["WhatsApp", p.whatsapp ?? "—"],
    ["E-mail", p.email ?? "—"],
    ["Cargo / empresa", quem || "—"],
    ["Perfil (ICP)", p.icp ?? "—"],
    ["Ingresso Summit 2026", (p.ingresso_summit_2026 ?? []).join(", ") || "—"],
  ];
  const conversa = d.conversa
    .map((m) => `<p><b>${m.papel === "lead" ? "Pessoa" : "Agente"}:</b> ${esc(m.texto).replace(/\n/g, "<br>")}</p>`)
    .join("");
  const html = `<h2>${esc(assunto)}</h2>
<p>O agente do app atendeu uma pessoa com interesse em <b>${produto}</b>.</p>
<table cellpadding="4">${linhas.map(([k, v]) => `<tr><td><b>${esc(k)}</b></td><td>${esc(v)}</td></tr>`).join("")}</table>
${wa ? `<p><a href="https://wa.me/${wa}">Abrir conversa no WhatsApp</a></p>` : ""}
<h3>Conversa</h3>${conversa || "<p>(sem mensagens)</p>"}`;
  const texto = `${assunto}\n\n${linhas.map(([k, v]) => `${k}: ${v}`).join("\n")}\n\nConversa:\n` +
    d.conversa.map((m) => `${m.papel === "lead" ? "Pessoa" : "Agente"}: ${m.texto}`).join("\n\n");
  return { assunto, html, texto };
}
