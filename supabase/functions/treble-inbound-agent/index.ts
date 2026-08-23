// Cérebro do agente inbound de vendas do Mind no WhatsApp.
// O Treble entrega cada mensagem via webhook (?token=... valida a origem);
// o agente consulta a fonte da verdade (RPC treble_agent_context), chama a
// OpenAI com saída estruturada e devolve user_session_keys para o fluxo.
//
// Guardrails: preço, checkout e lote vêm SOMENTE do contexto oficial;
// sem regra comercial liberando, desconto não existe; a conta de grupo sai
// pronta do banco (D-16); a atribuição viaja do site até o checkout (D-20);
// e o calendario do produto decide se e hora de vender ou de atender (D-25).
//
// v0.8.2 — a conversa vira pessoa. Duas buscas antes de criar: pela chave que
// veio (WhatsApp) e, depois de pedir o que falta, pela chave nova (e-mail).
// O nome nunca decide identidade — apelido pontua menos que pessoa diferente —
// então quando ele destoa o agente PERGUNTA, sem revelar dado de terceiro.
// A segunda busca roda em TODO turno em que o lead diz algo sobre si, mesmo
// com a conversa já ligada: é assim que o sobrenome entra e é assim que duas
// fichas da mesma pessoa aparecem (precisa_fundir) em vez de conviverem.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";

const VERSION = "0.8.2";
const DEFAULT_MODEL = "gpt-5.4-mini";

// O prompt vive no banco (treble.prompts), composto por turno:
// base + tom_de_voz + playbook_<audiencia> [+ objecoes]. Este texto é só
// a rede de segurança se o banco não devolver nada.
const PROMPT_FALLBACK = `Você atende o WhatsApp oficial do Mind Summit 2026.
Use somente os dados oficiais recebidos no JSON; nunca invente preço, palestrante ou política.
Se faltar informação, diga que vai confirmar com o time e acione needs_human=true.
Responda em português do Brasil, curto e caloroso, uma pergunta por mensagem.`;

const RESPONSE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    answer: { type: "string", minLength: 1, maxLength: 700 },
    audience: { type: "string", enum: ["b2c", "b2b", "cliente_suporte", "ja_comprou", "desconhecido"] },
    intent: { type: "string", minLength: 2, maxLength: 40 },
    ticket_interest: { type: ["string", "null"], enum: ["mind", "vip", "prime", null] },
    objection: { type: ["string", "null"] },
    needs_human: { type: "boolean" },
    checkout_sent: { type: "boolean" },
    stage: { type: "string", minLength: 2, maxLength: 40 },
    desfecho: {
      type: ["string", "null"],
      enum: ["compra_concluida", "checkout_enviado", "lead_qualificado", "handoff_humano", "ja_comprou", "descadastrado", "abandono", null],
    },
    // Identidade: o que o lead informou SOBRE SI NESTE TURNO. Só o que ele
    // disse com todas as letras — nada de deduzir nome a partir do contexto.
    // As descriptions vão para o modelo; os comentários, não. O nome precisa
    // vir INTEIRO porque nome+sobrenome+chave é o que deduplica a pessoa.
    nome_informado: {
      type: ["string", "null"], maxLength: 120,
      description: "O nome que o lead disse sobre si mesmo NESTE turno, transcrito INTEIRO e exatamente como ele escreveu — nome e sobrenome juntos quando ele deu os dois (\"Sou a Renata Vasconcelos\" => \"Renata Vasconcelos\"; \"me chamo Bia\" => \"Bia\"). Nunca encurte, nunca corrija a grafia, nunca complete com o nome que veio do WhatsApp. Nome de outra pessoa (chefe, colega, quem vai usar o ingresso) não entra aqui. null se ele não disse o nome dele neste turno.",
    },
    email_informado: {
      type: ["string", "null"], maxLength: 200,
      description: "O e-mail que o lead deu NESTE turno, exatamente como escrito. null se não deu nenhum neste turno.",
    },
    // Resposta a "esse cadastro é seu?": true = é ela, false = é de outra
    // pessoa, null = não foi perguntado ou não respondeu.
    confirmou_ser_titular: {
      type: ["boolean", "null"],
      description: "Só preencha se você perguntou se o cadastro encontrado é dele. true = ele confirmou que é ele mesmo. false = ele disse que não é ele (usou o e-mail/dado de outra pessoa). null = não foi perguntado ou ele não respondeu.",
    },
  },
  required: [
    "answer", "audience", "intent", "ticket_interest", "objection",
    "needs_human", "checkout_sent", "stage", "desfecho",
    "nome_informado", "email_informado", "confirmou_ser_titular",
  ],
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function redact(value: string) {
  return value
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "[e-mail omitido]")
    .replace(/(?:\+?\d[\d\s().-]{9,}\d)/g, "[telefone omitido]");
}

function pick(body: Record<string, unknown>, keys: string[]): string {
  for (const k of keys) {
    const v = body?.[k];
    if (typeof v === "string" && v.trim()) return v.trim();
  }
  const keysArr = Array.isArray(body?.user_session_keys) ? body.user_session_keys as Array<Record<string, unknown>> : [];
  for (const k of keys) {
    const hit = keysArr.find((e) => e?.key === k && typeof e?.value === "string" && String(e.value).trim());
    if (hit) return String(hit.value).trim();
  }
  return "";
}

function extractOutputText(payload: Record<string, unknown>) {
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

async function sha256(value: string) {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(hash), (b) => b.toString(16).padStart(2, "0")).join("");
}

const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/;

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const startedAt = Date.now();
  const url = new URL(req.url);

  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

  if (req.method === "GET" && url.pathname.endsWith("/health")) {
    return json(200, { ok: true, service: "treble-inbound-agent", version: VERSION });
  }
  if (req.method !== "POST") return json(405, { ok: false, error: "method_not_allowed" });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Config vem do banco (treble.config): token, modelo, timeout.
  const { data: cfg, error: cfgError } = await supabase.rpc("treble_agent_config");
  if (cfgError || !cfg?.webhook_token) return json(503, { ok: false, error: "config_indisponivel" });
  if (url.searchParams.get("token") !== cfg.webhook_token) {
    console.warn(JSON.stringify({ request_id: requestId, status: 401 }));
    return json(401, { ok: false, error: "unauthorized" });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { ok: false, error: "invalid_json" });
  }

  const sessionId = pick(body, ["session_external_id", "sessionExternalId", "session_id", "sessionId", "conversation_id", "cellphone", "celular"]);
  let message = pick(body, [
    "mensagem", "message", "text", "resposta", "answer", "user_message",
    "user_response", "response", "user_answer", "respuesta",
  ]).slice(0, 1200);
  const contactName = pick(body, ["name", "nome", "user_name", "first_name", "hubspot_firstname"]);
  const whatsapp = pick(body, ["cellphone", "celular", "phone", "whatsapp"]);
  // Origem = o botão pelo qual a pessoa entrou. Decide o utm_source (site),
  // o campo oculto do HubSpot e a mensagem de abertura.
  const origem = pick(body, ["origem", "origem_codigo", "origin", "botao", "utm_content", "entry_point"])
    .slice(0, 60);
  // O WhatsApp não tem query string: a UTM que trouxe a pessoa ao site viaja
  // como token curto dentro do texto pré-preenchido do wa.me ("[ref ab12cd34]").
  let utmToken = pick(body, ["utm_token", "ref", "token_utm"]).slice(0, 8);

  const CONTROLE = new Set([
    "needs_human", "intent", "audience", "checkout_sent", "resposta_ia",
    "country_code", "cellphone", "session_id", "conversation_id", "hubspot_firstname",
    "origem", "origem_codigo", "utm_content", "utm_token", "ref",
  ]);
  const pareceIdentificador = (v: string) =>
    /^[A-Z]{2,6}[_-]?\d{6,}$/i.test(v) || /^\+?\d[\d\s()-]{6,}$/.test(v) ||
    /^[0-9a-f]{16,}$/i.test(v);

  if (!message && Array.isArray(body.user_session_keys)) {
    const candidatos = (body.user_session_keys as Array<Record<string, unknown>>)
      .filter((e) => typeof e?.value === "string" && String(e.value).trim().length > 1 &&
                     !CONTROLE.has(String(e?.key ?? "")) &&
                     !pareceIdentificador(String(e.value).trim()));
    if (candidatos.length > 0) message = String(candidatos[candidatos.length - 1].value).slice(0, 1200);
  }
  const REF = /\[?\s*ref[:\s]\s*([a-z0-9]{8})\s*\]?/i;
  const achouRef = message.match(REF);
  if (achouRef) {
    if (!utmToken) utmToken = achouRef[1].toLowerCase();
    message = message.replace(REF, "").trim();
  }

  if (message && pareceIdentificador(message)) {
    console.warn(JSON.stringify({ request_id: requestId, event: "mensagem_descartada_identificador" }));
    message = "";
  }

  if (!sessionId || !message) {
    console.warn(JSON.stringify({
      request_id: requestId, event: "payload_nao_reconhecido",
      campos: Object.keys(body ?? {}),
      session_keys: Array.isArray(body.user_session_keys)
        ? (body.user_session_keys as Array<Record<string, unknown>>).map((e) => String(e?.key ?? ""))
        : null,
      tem_session: Boolean(sessionId), tem_mensagem: Boolean(message),
    }));
    return json(422, { ok: false, error: "faltam_campos", detalhe: "esperado identificador de sessão e mensagem do lead" });
  }

  console.info(JSON.stringify({
    request_id: requestId, event: "webhook_recebido",
    campos: Object.keys(body ?? {}),
  }));

  const openAiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!openAiKey) return json(503, { ok: false, error: "ia_nao_configurada" });
  const model = (typeof cfg.openai_model === "string" && cfg.openai_model) ||
    Deno.env.get("OPENAI_MODEL") || DEFAULT_MODEL;
  const timeoutMs = Number(cfg.timeout_ms) > 0 ? Number(cfg.timeout_ms) : 8500;

  try {
    const telefoneHash = whatsapp ? await sha256(whatsapp) : null;
    // start vem primeiro porque o contexto monta o checkout com a UTM da
    // conversa: sem isso o link sai sem atribuição. E é aqui que acontece a
    // PRIMEIRA busca da pessoa, pela chave que veio.
    const { data: conv, error: convError } = await supabase.rpc("treble_agent_start", {
      p_session_external_id: sessionId,
      p_contact: { nome: contactName || null, whatsapp: whatsapp || null, telefone_hash: telefoneHash },
      p_origem: origem || null,
      p_utm_token: utmToken || null,
    });
    if (convError || !conv) throw new Error("conversa_falhou");

    // Estado da identidade neste turno.
    let idConhecida = conv.pessoa_encontrada === true;
    let idPerfil = (conv.perfil ?? null) as Record<string, unknown> | null;
    let idFalta: string[] = Array.isArray(conv.falta) ? conv.falta as string[] : [];
    let idPergunta: Record<string, unknown> | null = null;

    // SEGUNDA BUSCA: só quando o lead entrega uma chave nova. O e-mail é
    // detectado por regex — determinístico, o modelo não pode alucinar um.
    const emailNaMensagem = message.match(EMAIL_RE)?.[0] ?? null;
    if (!idConhecida && emailNaMensagem) {
      const { data: ident, error: identError } = await supabase.rpc("treble_agent_identificar", {
        p_session_external_id: sessionId,
        p_email: emailNaMensagem,
        p_nome: contactName || conv.nome_contato || null,
        p_sobrenome: null,
        p_mesma_pessoa: null,
      });
      if (identError) {
        console.error(JSON.stringify({ request_id: requestId, event: "identificar_falhou", detalhe: identError.message }));
      } else if (ident?.precisa_perguntar) {
        idPergunta = ident.pergunta ?? null;
      } else if (ident?.pessoa_encontrada) {
        idConhecida = true;
        idPerfil = ident.perfil ?? null;
        idFalta = Array.isArray(ident.falta) ? ident.falta : [];
        console.info(JSON.stringify({
          request_id: requestId, event: "pessoa_identificada", criou: ident.criou === true,
        }));
      }
    }

    const [{ data: contexto, error: ctxError }, promptPre, { data: agenda }] = await Promise.all([
      supabase.rpc("treble_agent_context", {
        p_audience: null,
        p_origem: conv.origem_codigo ?? origem ?? null,
        p_utm: conv.utm ?? null,
        p_conversa: conv.conversation_id ?? null,
        p_produto: conv.produto_codigo ?? null,
      }),
      supabase.rpc("treble_agent_prompt", { p_audience: null }),
      cfg.bloco_agenda_busca === "true"
        ? supabase.rpc("mindagent_chat_search", {
            p_event_slug: "mind-summit-2026",
            p_query: message.slice(0, 300),
            p_limit: 8,
          })
        : Promise.resolve({ data: null, error: null }),
    ]);
    if (ctxError || !contexto) throw new Error("contexto_falhou");

    // Webhook duplicado do Treble: mesma fala em segundos → devolve a
    // resposta anterior em vez de gerar (e cobrar) outra.
    const { data: jaRespondida } = await supabase.rpc("treble_agent_resposta_repetida", {
      p_conversation_id: conv.conversation_id,
      p_mensagem: message,
      p_janela_segundos: 90,
    });
    if (typeof jaRespondida === "string" && jaRespondida.trim()) {
      console.info(JSON.stringify({ request_id: requestId, event: "turno_duplicado_ignorado" }));
      return json(200, {
        ok: true, duplicado: true,
        user_session_keys: [
          { key: "resposta_ia", value: jaRespondida },
          { key: "needs_human", value: String(conv.needs_human === true) },
        ],
      });
    }

    const audienciaAtual = typeof conv.audience === "string" && conv.audience ? conv.audience : "desconhecido";
    const { data: promptComposto } = audienciaAtual === "desconhecido"
      ? promptPre
      : await supabase.rpc("treble_agent_prompt", { p_audience: audienciaAtual });
    const instructions = typeof promptComposto === "string" && promptComposto.trim()
      ? promptComposto
      : PROMPT_FALLBACK;

    const historico = Array.isArray(conv.historico) ? conv.historico : [];
    const agendaSegura = agenda && typeof agenda === "object"
      ? Object.fromEntries(Object.entries(agenda as Record<string, unknown>)
          .filter(([k]) => ["sessions", "speakers", "locations", "exhibitors", "mind"].includes(k)))
      : {};

    const aiInput = {
      DADOS_OFICIAIS: contexto,
      AGENDA_E_PALESTRANTES: agendaSegura,
      estado_da_conversa: {
        audience: conv.audience,
        stage: conv.stage,
        nome_contato: conv.nome_contato ?? contactName ?? null,
        origem_codigo: conv.origem_codigo ?? origem ?? null,
        utm_de_origem: conv.utm ?? null,
        produto: conv.produto_codigo ?? null,
      },
      // Identidade. O agente pede o que falta com naturalidade, uma coisa por
      // vez, e NUNCA pergunta o que já está preenchido aqui.
      quem_esta_falando: {
        ja_identificada: idConhecida,
        perfil: idPerfil,
        ainda_falta: idFalta,
        pergunta_de_identidade: idPergunta,
        como_agir: idPergunta
          ? "Faça a pergunta_de_identidade com suas palavras, no seu tom, antes de seguir. Não cite nome, e-mail ou empresa de nenhum outro cadastro."
          : idFalta.length > 0
            ? "Peça UM item de ainda_falta quando a conversa permitir, sem parecer formulário. Nunca peça o que já está em perfil."
            : "Você já sabe quem é. Não peça dado nenhum de cadastro.",
      },
      historico,
      mensagem_do_lead: redact(message),
    };

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    let aiResponse: Response;
    try {
      aiResponse = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: { "Authorization": `Bearer ${openAiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          model,
          instructions,
          input: [{ role: "user", content: JSON.stringify(aiInput) }],
          reasoning: { effort: "none" },
          text: { format: { type: "json_schema", name: "treble_agent_turn", strict: true, schema: RESPONSE_SCHEMA } },
          max_output_tokens: 700,
          store: false,
        }),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeout);
    }

    if (!aiResponse.ok) {
      console.error(JSON.stringify({ request_id: requestId, event: "openai_error", status: aiResponse.status }));
      return json(502, { ok: false, error: "ia_indisponivel" });
    }

    const aiPayload = await aiResponse.json() as Record<string, unknown>;
    const turn = JSON.parse(extractOutputText(aiPayload)) as {
      answer: string; audience: string; intent: string; ticket_interest: string | null;
      objection: string | null; needs_human: boolean; checkout_sent: boolean;
      stage: string; desfecho: string | null;
      nome_informado: string | null; email_informado: string | null;
      confirmou_ser_titular: boolean | null;
    };
    const answer = String(turn.answer ?? "").trim().slice(0, 700);
    if (!answer) throw new Error("resposta_vazia");

    // Guardrail de preço: valor em R$ fora dos dados oficiais derruba o turno.
    const precosOficiais = new Set<string>(
      JSON.stringify({ contexto, agendaSegura }).match(/\d+(?:\.\d+)?/g) ?? [],
    );
    const camposDePreco = (obj: unknown, chaves: string[]): number[] => {
      const saida: number[] = [];
      const anda = (n: unknown) => {
        if (Array.isArray(n)) return n.forEach(anda);
        if (n && typeof n === "object") {
          for (const [k, v] of Object.entries(n as Record<string, unknown>)) {
            if (chaves.includes(k) && Number.isFinite(Number(v))) saida.push(Math.round(Number(v)));
            else anda(v);
          }
        }
      };
      anda(obj);
      return saida;
    };
    const unitarios = camposDePreco(contexto, ["valor", "valor_por_ingresso_com_desconto", "valor_cheio_por_ingresso"])
      .filter((v) => v >= 100 && v <= 100000);
    const ehMultiploDeOficial = (valor: number) =>
      unitarios.some((u) => valor % u === 0 && valor / u >= 2 && valor / u <= 60);
    const precosNaResposta = answer.match(/R\$\s?([\d.]+)/g) ?? [];
    for (const p of precosNaResposta) {
      const bruto = p.replace(/R\$\s?/, "").replace(/\./g, "");
      if (!precosOficiais.has(bruto) && !precosOficiais.has(bruto + ".00") &&
          !ehMultiploDeOficial(Number(bruto))) {
        console.error(JSON.stringify({ request_id: requestId, event: "preco_inventado", preco: p }));
        return json(200, {
          ok: true, guarded: true,
          user_session_keys: [
            { key: "resposta_ia", value: "Deixa eu confirmar esse valor com o time para não te passar nada errado — já te chamo um consultor! 🙌" },
            { key: "needs_human", value: "true" },
          ],
        });
      }
    }

    // Depois de responder: o que o lead informou sobre si neste turno vira
    // identificação. Roda fora do caminho crítico da resposta — se falhar,
    // a resposta já foi dada e a próxima mensagem tenta de novo.
    const nomeDito = (turn.nome_informado ?? "").trim() || null;
    const emailDito = (turn.email_informado ?? "").trim().match(EMAIL_RE)?.[0] ?? null;
    // So CRIA com E-MAIL em maos: sem ele a segunda busca nao aconteceu, e
    // criar a pessoa agora significaria duplicar a cliente antiga que so
    // seria encontrada pelo e-mail. Nome sozinho nunca cria — quem garante
    // isso e o banco, em treble_agent_identificar.
    //
    // Mas a chamada acontece mesmo com a pessoa ja ligada: e assim que o
    // sobrenome entra. A busca de cima roda antes do modelo ler a mensagem,
    // com o primeiro nome que veio do WhatsApp; so aqui existe "Renata
    // Vasconcelos" inteiro. A funcao so preenche o que esta vazio (coalesce),
    // nunca sobrescreve, e devolve precisa_fundir se o e-mail for de outra
    // ficha — que e a segunda busca que a Adriana pediu, acontecendo sempre.
    const chaveNova = emailDito ?? emailNaMensagem;
    if (chaveNova || nomeDito || turn.confirmou_ser_titular !== null) {
      const { data: ident2, error: err2 } = await supabase.rpc("treble_agent_identificar", {
        p_session_external_id: sessionId,
        p_email: chaveNova,
        p_nome: nomeDito ?? contactName ?? conv.nome_contato ?? null,
        p_sobrenome: null,
        p_mesma_pessoa: turn.confirmou_ser_titular,
      });
      if (err2) {
        console.error(JSON.stringify({ request_id: requestId, event: "identificar_pos_turno_falhou", detalhe: err2.message }));
      } else if (ident2?.precisa_fundir) {
        // Duas fichas para a mesma pessoa. Ninguem funde sozinho: fica
        // registrado para uma pessoa decidir.
        console.warn(JSON.stringify({
          request_id: requestId, event: "identidade_precisa_fundir",
          participante_id: ident2.participante_id, outro: ident2.outro_cadastro_id,
        }));
      } else if (ident2?.pessoa_encontrada) {
        idConhecida = true;
        console.info(JSON.stringify({
          request_id: requestId, event: "pessoa_identificada_pos_turno", criou: ident2.criou === true,
        }));
      }
    }

    const state = {
      audience: turn.audience,
      intent: turn.intent,
      ticket_interest: turn.ticket_interest,
      objection: turn.objection,
      needs_human: turn.needs_human,
      checkout_sent: turn.checkout_sent,
      stage: turn.stage,
      desfecho: turn.desfecho,
    };
    const { error: saveError } = await supabase.rpc("treble_agent_save_turn", {
      p_conversation_id: conv.conversation_id,
      p_user_msg: message,
      p_answer: answer,
      p_state: state,
      p_tool_calls: { model, request_id: requestId, version: VERSION },
    });
    if (saveError) console.error(JSON.stringify({ request_id: requestId, event: "save_falhou", detalhe: saveError.message }));

    console.info(JSON.stringify({
      request_id: requestId, status: 200, session: sessionId.slice(0, 8),
      audience: turn.audience, intent: turn.intent, needs_human: turn.needs_human,
      desfecho: turn.desfecho, identificada: idConhecida,
      duration_ms: Date.now() - startedAt,
    }));

    return json(200, {
      ok: true,
      user_session_keys: [
        { key: "resposta_ia", value: answer },
        { key: "needs_human", value: String(turn.needs_human) },
        { key: "intent", value: turn.intent },
        { key: "audience", value: turn.audience },
        { key: "checkout_sent", value: String(turn.checkout_sent) },
      ],
      state,
      request_id: requestId,
    });
  } catch (error) {
    const isTimeout = error instanceof DOMException && error.name === "AbortError";
    console.error(JSON.stringify({
      request_id: requestId, status: isTimeout ? 504 : 500,
      reason: error instanceof Error ? error.message : "unknown",
      duration_ms: Date.now() - startedAt,
    }));
    return json(200, {
      ok: false,
      user_session_keys: [
        { key: "resposta_ia", value: "Tive um probleminha técnico aqui 😅 Já vou te conectar com alguém do nosso time!" },
        { key: "needs_human", value: "true" },
      ],
    });
  }
});
