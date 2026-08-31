// ROUTER UNIVERSAL — Passo 10.
//
// Decide QUAL COMPETENCIA assume a NECESSIDADE ATUAL de uma conversa. Nada mais:
// nao responde, nao vende, nao escolhe estrategia, nao decide handoff e nao olha
// se existe playbook para a rota (Capability Gate e o Passo 11).
//
// v1.2.0 — O CANAL DEFINE O UNIVERSO DE ESCOLHA.
//
// Ate a v1.1.0 este servico era canal-agnostico por construcao: recebia so um
// `conversa_id` e escolhia entre as SEIS rotas globais. O Gate, depois, e que
// descobria que a escolhida nao era servida naquele canal — e ai nao havia para
// onde cair: o turno virava transferencia. Dois turnos reais morreram assim em
// 24h ("Quando sera o evento?", "quais palestrantes estarao no summit?" no
// WhatsApp), porque "programacao/horarios/agenda" e vocabulario de concierge e o
// concierge nao roda ali.
//
// Ninguem errou dentro da propria regra. A regra e que estava incompleta: faltava
// dizer ao Router qual e o universo LEGAL daquele canal.
//
// Agora o canal entra na requisicao, sem inferencia — quem chama sabe onde esta —
// e a politica vem de `agentes.canal_competencia`, via `public.mind_canal_rotas`.
//
// ORIGEM DO CANAL, em ordem: o corpo da requisicao, que e o runtime DECLARANDO onde
// esta; e, quando ele nao declara, `conversation.canal` do proprio AGENT_CONTEXT —
// o valor que a ingestao gravou, no mesmo vocabulario canonico
// (`whatsapp` / `mindagent-web`). A segunda origem nao e adivinhacao: e registro. Ela
// existe para que a politica valha para TODO chamador desde o primeiro minuto,
// inclusive os que ainda nao foram republicados. Sem nenhuma das duas, falha.
// A garantia NAO e de prompt: o enum do JSON Schema estrito e montado a partir das
// rotas permitidas, entao uma rota proibida no canal nao e sequer emitivel. O
// prompt so diz o conceito ("escolha entre as competencias deste turno"); os
// valores concretos vem do sistema.
//
// O que NAO muda: o Router continua ESCOLHENDO. A tabela nao diz qual rota — diz
// quais sao possiveis. Dentro delas, a decisao e do modelo, com o mesmo contrato
// de clarify de antes.
//
// NAO PERSISTE NADA. Nao escreve rota, nao toca engagement.conversas.
//
//   POST /router?token=<intelligence.config.analise_token>
//   { "conversa_id": "uuid", "canal": "whatsapp" | "mindagent-web" }

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";

const VERSION = "1.2.0";
const TIMEOUT_MS = 15_000;

// Taxonomia canonica. Fechada. `ja_comprou` e `desconhecido` NAO sao rotas.
// Continua sendo o vocabulario do servico; o que o canal faz e RECORTAR dela.
const ROTAS = [
  "summit_b2c",
  "summit_b2b",
  "institute",
  "dash",
  "cliente_suporte",
  "concierge_summit",
] as const;
type Rota = typeof ROTAS[number];

// O schema deixa de ser constante: o enum sai das rotas permitidas NESTE canal.
// E aqui que a politica vira garantia — o modelo nao tem como devolver uma rota
// que o canal nao serve, porque ela nao existe no contrato de saida.
function schemaDoCanal(permitidas: readonly string[]) {
  return {
    type: "object",
    additionalProperties: false,
    properties: {
      rota: {
        type: ["string", "null"],
        enum: [...permitidas, null],
        description: "A competencia que assume a necessidade atual, ou null quando ha ambiguidade real.",
      },
      precisa_esclarecer: { type: "boolean" },
      candidatas: {
        type: "array",
        items: { type: "string", enum: [...permitidas] },
        description: "So quando rota e null: as rotas que continuam plausiveis. Nunca vazia nesse caso.",
      },
    },
    required: ["rota", "precisa_esclarecer", "candidatas"],
  };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function extractOutputText(payload: Record<string, unknown>): string {
  if (typeof payload.output_text === "string") return payload.output_text;
  const output = Array.isArray(payload.output) ? payload.output : [];
  for (const item of output) {
    if (!item || typeof item !== "object") continue;
    const content = Array.isArray((item as Record<string, unknown>).content)
      ? (item as Record<string, unknown>).content as Array<Record<string, unknown>>
      : [];
    for (const part of content) {
      if (part.type === "output_text" && typeof part.text === "string") return part.text;
    }
  }
  return "";
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const startedAt = Date.now();
  const url = new URL(req.url);

  if (req.method === "GET" && url.pathname.endsWith("/health")) {
    return json(200, { ok: true, service: "router", version: VERSION });
  }
  if (req.method !== "POST") return json(405, { ok: false, error: "method_not_allowed" });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: cfg } = await supabase.rpc("analise_config");
  const token = cfg?.analise_token as string | undefined;
  const model = (cfg?.openai_model as string | undefined) || "gpt-5.4-mini";
  if (!token || url.searchParams.get("token") !== token) {
    return json(401, { ok: false, error: "unauthorized" });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { ok: false, error: "invalid_json" });
  }

  const bruto = typeof body.conversa_id === "string" ? body.conversa_id.trim() : "";
  if (bruto && !UUID_RE.test(bruto)) {
    return json(400, { ok: false, error: "conversa_id_invalido" });
  }
  const conversaId = bruto || null;

  // ---------------------------------------------------------------- CONTEXTO
  // O AGENT_CONTEXT ja resolve pessoa, entrada, CRM, comercial e historico, e ja
  // tem os tres contratos de erro. Aqui eles sao espelhados como estao.
  const { data: ctx, error: ctxError } = await supabase.rpc("mind_agent_context", {
    p_conversa_id: conversaId,
  });
  if (ctxError || !ctx) {
    console.error(JSON.stringify({ request_id: requestId, event: "contexto_falhou", detalhe: ctxError?.message }));
    return json(502, { ok: false, error: "contexto_indisponivel" });
  }
  if (ctx.ok !== true) {
    return json(200, ctx);
  }

  // ------------------------------------------------------- POLITICA DO CANAL
  // O universo legal de escolha deste turno. Vem do banco, nunca do prompt.
  const canalDeclarado = typeof body.canal === "string" ? body.canal.trim() : "";
  const canalRegistrado = typeof ctx.conversation?.canal === "string"
    ? String(ctx.conversation.canal).trim() : "";
  const canal = canalDeclarado || canalRegistrado;
  const canalOrigem = canalDeclarado ? "requisicao" : (canalRegistrado ? "conversa" : "ausente");
  if (!canal) {
    console.warn(JSON.stringify({ request_id: requestId, event: "canal_ausente", conversa: conversaId }));
    return json(400, { ok: false, error: "canal_ausente" });
  }

  const { data: politica, error: politicaError } = await supabase.rpc("mind_canal_rotas", {
    p_canal: canal,
  });
  if (politicaError || !politica) {
    console.error(JSON.stringify({
      request_id: requestId, event: "politica_indisponivel", detalhe: politicaError?.message,
    }));
    return json(502, { ok: false, error: "politica_indisponivel" });
  }
  // Canal desconhecido devolve a mesma palavra que o Gate ja usava.
  if (politica.ok !== true) {
    console.warn(JSON.stringify({ request_id: requestId, event: "canal_invalido", canal, canal_origem: canalOrigem }));
    return json(200, politica);
  }

  const permitidas: Rota[] = Array.isArray(politica.rotas)
    ? politica.rotas.filter((r: unknown): r is Rota => ROTAS.includes(r as Rota))
    : [];
  // Canal valido sem nenhuma competencia ativa nao tem o que rotear. Nao e erro
  // do turno — e a politica dizendo que este canal nao atende nada agora.
  if (permitidas.length === 0) {
    console.warn(JSON.stringify({ request_id: requestId, event: "canal_sem_competencia", canal }));
    return json(200, { ok: false, motivo: "canal_sem_competencia" });
  }

  // ------------------------------------------------------- NECESSIDADE ATUAL
  // A ultima fala da pessoa e a evidencia principal. Sem nenhuma fala dela, nao
  // ha necessidade a rotear — e tambem nao ha o que esclarecer. Nao chama modelo.
  const mensagens = Array.isArray(ctx.conversation?.mensagens) ? ctx.conversation.mensagens : [];
  const falasDoLead = mensagens.filter((m: Record<string, unknown>) =>
    m?.papel === "lead" && typeof m?.conteudo === "string" && String(m.conteudo).trim());
  if (falasDoLead.length === 0) {
    console.info(JSON.stringify({
      request_id: requestId, event: "sem_fala_do_lead",
      conversa: conversaId, duration_ms: Date.now() - startedAt,
    }));
    return json(200, {
      ok: true, conversa_id: conversaId,
      rota: null, precisa_esclarecer: false, candidatas: [],
    });
  }
  const necessidadeAtual = String(falasDoLead[falasDoLead.length - 1].conteudo).trim();

  // ------------------------------------------------------------------ PROMPT
  // Mesmo carregador dos analisadores: so devolve prompt ativo e nao-vazio.
  const { data: p } = await supabase.rpc("analise_prompt", { p_chave: "router_universal" });
  const instructions = typeof p?.conteudo === "string" ? p.conteudo : "";
  if (!instructions.trim()) {
    console.error(JSON.stringify({ request_id: requestId, event: "router_sem_prompt" }));
    return json(503, { ok: false, error: "router_sem_prompt" });
  }

  // --------------------------------------------------------------------- IA
  const openAiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!openAiKey) return json(503, { ok: false, error: "ia_nao_configurada" });

  const entrada = {
    // Explicito: a necessidade atual e a ultima fala da pessoa. O resto informa.
    necessidade_atual: necessidadeAtual,
    // O universo legal deste turno. Vem do banco, nunca do prompt.
    canal,
    competencias_disponiveis: permitidas,
    agent_context: ctx,
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
  let resposta: Response;
  try {
    resposta = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { "Authorization": `Bearer ${openAiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        instructions,
        input: [{ role: "user", content: JSON.stringify(entrada) }],
        reasoning: { effort: "none" },
        text: {
          format: {
            type: "json_schema", name: "rota", strict: true,
            schema: schemaDoCanal(permitidas),
          },
        },
        max_output_tokens: 300,
        store: false,
      }),
      signal: controller.signal,
    });
  } catch (e) {
    clearTimeout(timeout);
    const isTimeout = e instanceof DOMException && e.name === "AbortError";
    console.error(JSON.stringify({ request_id: requestId, event: isTimeout ? "ia_timeout" : "ia_erro" }));
    return json(isTimeout ? 504 : 502, { ok: false, error: "ia_indisponivel" });
  }
  clearTimeout(timeout);

  if (!resposta.ok) {
    console.error(JSON.stringify({ request_id: requestId, event: "openai_error", status: resposta.status }));
    return json(502, { ok: false, error: "ia_indisponivel" });
  }

  let saida: { rota?: unknown; precisa_esclarecer?: unknown; candidatas?: unknown };
  try {
    saida = JSON.parse(extractOutputText(await resposta.json() as Record<string, unknown>));
  } catch {
    console.error(JSON.stringify({ request_id: requestId, event: "saida_invalida", motivo: "json" }));
    return json(502, { ok: false, error: "saida_invalida" });
  }

  // ------------------------------------------------------------- INVARIANTES
  // O schema estrito ja fecha a taxonomia NO UNIVERSO DO CANAL; aqui a coerencia
  // do contrato e garantida deste lado, contra `permitidas` e nao contra ROTAS.
  // Cinto e suspensorio: se um dia o schema afrouxar, a rota proibida ainda cai.
  const rota: Rota | null = permitidas.includes(saida.rota as Rota) ? saida.rota as Rota : null;
  const candidatas = rota === null && Array.isArray(saida.candidatas)
    ? [...new Set(saida.candidatas.filter((c): c is Rota => permitidas.includes(c as Rota)))]
    : [];

  // CONTRATO DE CLARIFY. Pedir esclarecimento sem dizer entre o que e uma saida
  // vazia disfarcada de decisao: quem consome nao teria o que perguntar. Entao
  // rota=null com fala do lead so vale com pelo menos uma candidata canonica.
  //
  // Nao se inventa candidata deste lado. Escolher rota plausivel e competencia do
  // prompt, e o servidor forjar essa lista seria roteamento escondido no
  // encanamento. Sem candidata, a saida do modelo esta invalida e e rejeitada.
  if (rota === null && candidatas.length === 0) {
    console.error(JSON.stringify({
      request_id: requestId, event: "saida_invalida", motivo: "clarify_sem_candidatas",
      conversa: conversaId, canal, model, duration_ms: Date.now() - startedAt,
    }));
    return json(502, { ok: false, error: "saida_invalida" });
  }

  console.info(JSON.stringify({
    request_id: requestId, status: 200, conversa: conversaId,
    canal, canal_origem: canalOrigem, permitidas: permitidas.length,
    rota, precisa_esclarecer: rota === null, candidatas: candidatas.length,
    model, duration_ms: Date.now() - startedAt,
  }));

  return json(200, {
    ok: true,
    conversa_id: conversaId,
    rota,
    // Rota decidida nunca pede esclarecimento; rota nula com fala do lead sempre
    // pede — e, pela trava acima, sempre com candidatas para oferecer.
    precisa_esclarecer: rota === null,
    candidatas,
  });
});
