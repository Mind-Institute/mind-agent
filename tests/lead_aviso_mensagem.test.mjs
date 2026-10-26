import assert from "node:assert/strict";
import test from "node:test";
import { montarEmail } from "../supabase/functions/lead-aviso/mensagem.ts";

const base = {
  sinal: { id: "s1", vertical: "institute", status: "novo", criado_em: "2026-09-24T20:00:00Z" },
  pessoa: {
    nome: "Clarice Lima", email: "clarice@exemplo.com", whatsapp: "+55 (21) 99793-5363",
    cargo: "Gerente de SMS", empresa: "Petrobras", icp: "Gestor(a) / Middle Management (não RH)",
    ingresso_summit_2026: ["Mind"],
  },
  conversa: [
    { papel: "lead", texto: "Meu desafio é engajar as equipes <e> cuidar dos líderes" },
    { papel: "agente", texto: "Recomendo a Certificação Avançada em Liderança Positiva." },
  ],
  destinatarios: ["a@x.com"],
  remetente: "Mind Agent <agente@joinmind.com.br>",
};

test("assunto nomeia produto, pessoa, cargo e empresa", () => {
  const e = montarEmail(base);
  assert.equal(e.assunto, "Lead Mind Institute: Clarice Lima — Gerente de SMS · Petrobras");
  assert.equal(montarEmail({ ...base, sinal: { ...base.sinal, vertical: "dash" } }).assunto.startsWith("Lead Mind Dash:"), true);
});

test("html traz contato, link de WhatsApp só com dígitos e a conversa escapada", () => {
  const e = montarEmail(base);
  assert.match(e.html, /https:\/\/wa\.me\/5521997935363/);
  assert.match(e.html, /clarice@exemplo\.com/);
  assert.match(e.html, /engajar as equipes &lt;e&gt; cuidar/);
  assert.doesNotMatch(e.html, /<e>/);
  assert.match(e.texto, /Pessoa: Meu desafio/);
});

test("sem nome nem WhatsApp não quebra e não gera link", () => {
  const e = montarEmail({ ...base, pessoa: { email: "x@y.com" }, conversa: [] });
  assert.equal(e.assunto, "Lead Mind Institute: sem nome");
  assert.doesNotMatch(e.html, /wa\.me/);
  assert.match(e.html, /\(sem mensagens\)/);
});
