import { createClient } from "npm:@supabase/supabase-js@2.112.3";

type ChatRequest = {
  message?: string;
  event_slug?: string;
  device_id?: string;
  client_message_id?: string;
  session?: { id?: string; conversation_id?: string; token?: string };
  identity?: { email?: string; name?: string; source?: string };
  // Porta de entrada da conversa. NÃO é identidade: diz de onde a pessoa veio, não
  // quem ela é. Persistido em `engagement.conversas.origem_codigo`, a mesma casa que
  // o WhatsApp já usa (`summit_info_evento`, `summit_garantir_ingresso`, …).
  origem_codigo?: string;
  // Modo ação do Play. Mesmo endpoint, mesma sessão, mesma identidade — o que
  // muda é que não há pergunta e não há modelo: é a execução de uma ferramenta
  // já registrada. O contrato do cliente é o de `play-service.js`.
  ferramenta?: string;
  argumentos?: Record<string, unknown>;
  client_action_id?: string;
};

type Interest = {
  key: string;
  label: string;
  confidence: number;
  confirmed: boolean;
  sensitivity: string;
};

const VERSION = "1.8.0";
const DEFAULT_EVENT_SLUG = "mind-summit-2026";
const DEFAULT_MODEL = "gpt-5.4-mini";

// O CANAL DESTE RUNTIME. Constante, nunca inferida da conversa: quem chama sabe
// onde está. É ele que o Router usa para recortar, em `agentes.canal_competencia`,
// quais competências podem ser escolhidas neste turno.
const CANAL = "mindagent-web";

// ORIGENS COM ROTA AUTORITATIVA. Quem entra pelo app oficial do Summit já disse, pela
// própria porta, qual competência quer: o concierge. O Router existe para DECIDIR — e
// não há o que decidir aqui.
//
// Isto é orquestração, não política de canal: `agentes.canal_competencia` continua
// dizendo o que o canal PODE servir, e o Gate continua confirmando se executa. Esta
// tabela responde outra pergunta — "esta entrada já vem com a competência definida?".
// Uma entrada só; se um dia houver outra, ela nasce aqui.
const ROTA_POR_ORIGEM: Record<string, string> = {
  mind_summit_app: "concierge_summit",
};

// Código de origem é identificador, não texto livre — mesmo formato que o banco valida.
const ORIGEM_CODIGO_RE = /^[a-z][a-z0-9_]{1,59}$/;

// Duas rodadas de ferramenta por turno, e não mais. Uma rodada busca; a segunda
// lê o que a busca achou. Além disso vira ruminação: o modelo continua procurando
// em vez de responder com o que já tem — e quem espera é uma pessoa.
const MAX_RODADAS_TOOL = 2;

// Orçamento do TURNO INTEIRO, não de uma chamada. Com tool loop existem até três
// gerações e duas idas ao banco; medir cada uma isolada deixaria o pior caso sem teto.
const ORCAMENTO_TURNO_MS = 30_000;
const ROUTER_TIMEOUT_MS = 12_000;

// FERRAMENTAS DE INTELLIGENCE — mesmo princípio de `FERRAMENTAS_PLAY`: o nome que
// chega de fora NUNCA vira nome de RPC. QUAIS ferramentas estão ligadas é decisão do
// Kit (`agentes.kit_blocos`, seção `tools`), no banco; COMO cada uma executa está
// aqui, estático e auditável. Ferramenta que o Kit exponha e este mapa não conheça é
// descartada — o runtime nunca inventa executor.
//
// As duas são de LEITURA. `mind_intelligence_buscar` e `mind_intelligence_ler` já
// existem desde 20260831070000 e leem as casas canônicas (palestrantes, sessões,
// knowledge_documents). Nenhuma fonte da verdade nova, nenhum índice paralelo.
const FERRAMENTAS_INTELLIGENCE: Record<
  string,
  { rpc: string; args: (bruto: Record<string, unknown>) => Record<string, unknown> }
> = {
  buscar_intelligence: {
    rpc: "mind_intelligence_buscar",
    args: (a) => {
      const limite = Number(a.limite);
      return {
        p_necessidade: String(a.necessidade ?? "").trim().slice(0, 400),
        p_limite: Number.isFinite(limite) ? Math.max(1, Math.min(10, Math.trunc(limite))) : 6,
      };
    },
  },
  ler_intelligence: {
    rpc: "mind_intelligence_ler",
    args: (a) => ({
      p_tipo: String(a.tipo ?? "").trim().slice(0, 40),
      p_id: String(a.id ?? "").trim().slice(0, 80),
      p_corte: 1200,
    }),
  },
};

// SENSIBILIDADE DO INTERESSE — espelha as chaves ATIVAS de
// `intelligence.memoria_bloqueios` em 31/08/2026, mais `none`.
//
// Está literal aqui porque o `json_schema` strict da OpenAI exige enum
// literal, e porque errar para o lado fechado é o comportamento certo: se a
// tabela ganhar uma chave nova que este enum não conhece, o modelo não
// consegue emiti-la, o campo vem com outro valor e o gate da Lane D — que é a
// autoridade — bloqueia. Ausente ou desconhecido = bloqueado, nunca liberado.
const SENSIBILIDADES = [
  "none",
  "afastamento_titular",
  "diagnostico_titular",
  "filiacao_sindical",
  "medicacao_titular",
  "opiniao_politica",
  "orientacao_sexual",
  "origem_racial",
  "religiao",
  "saude_de_pessoa_citada",
  "saude_do_titular",
] as const;

// FERRAMENTAS DO PLAY — allowlist explícita, estática e auditável.
//
// O nome que chega do cliente NUNCA vira nome de RPC: ele é chave de consulta
// neste mapa, e só o que está aqui executa. `mind_play_*` são SECURITY DEFINER
// com EXECUTE apenas para `service_role`, e é por isso que o navegador não as
// chama direto — quem chama é este runtime, que também é quem sabe quem é a
// pessoa. Os nomes e as assinaturas são os de `concierge.ferramentas` e das
// funções da Lane E.
const FERRAMENTAS_PLAY: Record<string, { rpc: string; vinculo: "conversa" | "mensagem" | "nenhum" }> = {
  registrar_feedback_sessao: { rpc: "mind_play_feedback_sessao", vinculo: "conversa" },
  registrar_nps:             { rpc: "mind_play_nps",             vinculo: "conversa" },
  registrar_feedback_evento: { rpc: "mind_play_feedback_evento", vinculo: "mensagem" },
  registrar_feedback:        { rpc: "mind_play_feedback",        vinculo: "nenhum" },
};

// RECUSA DO WRITER — o `motivo` das `mind_play_*` É o código de domínio, e o
// `play-service.js` já sabe lê-lo em `error.code`. Só passa o que tem forma de
// código; qualquer outra coisa vira `acao_recusada`, para nunca vazar texto
// interno do banco na resposta. Nada é traduzido: inventar enum aqui criaria
// uma segunda taxonomia para a mesma recusa.
function codigoDeRecusa(saida: Record<string, unknown> | null) {
  const motivo = typeof saida?.motivo === "string" ? saida.motivo.trim() : "";
  return /^[a-z][a-z0-9_]{1,39}$/.test(motivo) ? motivo : "acao_recusada";
}

function readKey(name: "SUPABASE_PUBLISHABLE_KEYS" | "SUPABASE_SECRET_KEYS", fallback: string) {
  const raw = Deno.env.get(name);
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      if (typeof parsed.default === "string") return parsed.default;
      const first = Object.values(parsed).find((value) => typeof value === "string");
      if (typeof first === "string") return first;
    } catch {
      // Legacy fallback below.
    }
  }
  return Deno.env.get(fallback) ?? "";
}

function allowedOrigin(req: Request) {
  const origin = req.headers.get("Origin");
  const configured = (Deno.env.get("MINDAGENT_ALLOWED_ORIGINS") ?? "")
    .split(",").map((value) => value.trim()).filter(Boolean);
  if (!origin) return "*";
  if (configured.length === 0 || configured.includes(origin)) return origin;
  return "null";
}

function corsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": allowedOrigin(req),
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Expose-Headers": "x-request-id",
    "Vary": "Origin",
  };
}

function json(req: Request, status: number, body: unknown, requestId: string) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(req),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "X-Request-Id": requestId,
    },
  });
}

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");
}

async function sha256(value: string) {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(hash), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function validUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function validSlug(value: string) {
  return /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value) && value.length <= 80;
}

function validEmail(value: unknown): value is string {
  return typeof value === "string" && value.length <= 320 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value.trim().toLowerCase());
}

function normalizeInterestKey(value: string) {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    .replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 80);
}

function redactForAi(value: string) {
  return value
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "[e-mail omitido]")
    .replace(/(?:\+?\d[\d\s().-]{7,}\d)/g, "[telefone omitido]");
}

function normalizeAnswerLayout(value: string) {
  // ESCRITA ESTRANHA AO PORTUGUÊS. O filtro cobria só CJK e um turno real chegou à
  // pessoa com "Ela ficou հայտնի por pesquisar…" — armênio no meio da frase. Em vez de
  // listar alfabeto por alfabeto, a regra vira positiva: some o que NÃO é letra latina,
  // número, pontuação ou símbolo. Emoji e acento continuam passando.
  // Limitação conhecida: apagar a palavra deixa a frase com um buraco. É menos ruim que
  // entregar o caractere, e a causa (geração corrompida) é do modelo, não daqui.
  const withoutUnexpectedScripts = value
    .replace(/\p{L}/gu, (c) => /\p{Script=Latin}/u.test(c) ? c : "")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/\s+([,.;:!?])/g, "$1");

  return withoutUnexpectedScripts
    .replace(/\s*[•●]\s*/g, "\n• ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function buildPersonalizationProfile(value: unknown) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const source = value as Record<string, unknown>;
  const cleanText = (field: unknown, max: number) =>
    typeof field === "string" ? field.trim().slice(0, max) : "";
  const rawInterests = Array.isArray(source.interests) ? source.interests : [];
  const interests = rawInterests
    .map((interest) => {
      if (typeof interest === "string") return interest.trim();
      if (!interest || typeof interest !== "object") return "";
      return cleanText((interest as Record<string, unknown>).label, 120);
    })
    .filter(Boolean)
    .filter((interest, index, all) => all.indexOf(interest) === index)
    .slice(0, 8);
  const profile = {
    nome: cleanText(source.name, 120),
    cargo: cleanText(source.role, 120),
    empresa: cleanText(source.company, 160),
    interesses: interests,
  };
  return profile.nome || profile.cargo || profile.empresa || profile.interesses.length > 0 ? profile : null;
}

// CHAMADAS DE FERRAMENTA de uma geração da Responses API. Só o que tem forma de
// chamada entra; qualquer outro item do output é ignorado sem virar erro.
function extractFunctionCalls(payload: Record<string, unknown>) {
  const output = Array.isArray(payload.output) ? payload.output : [];
  const calls: Array<{ call_id: string; name: string; arguments: string }> = [];
  for (const raw of output) {
    if (!raw || typeof raw !== "object") continue;
    const item = raw as Record<string, unknown>;
    if (item.type !== "function_call") continue;
    if (typeof item.name !== "string" || typeof item.call_id !== "string") continue;
    calls.push({
      call_id: item.call_id,
      name: item.name,
      arguments: typeof item.arguments === "string" ? item.arguments : "{}",
    });
  }
  return calls;
}

// ROTA — quem decide é a Edge Function `router` (Passo 10), e só ela. Este runtime
// não tem heurística, lista de palavra-chave nem rota preferida: o canal vai
// EXPLÍCITO e o Router escolhe dentro do que `agentes.canal_competencia` permite
// para ele. A lista de rotas do App não é repetida aqui de propósito — duplicá-la
// criaria uma segunda autoridade sobre a política que acabamos de centralizar.
async function decidirRota(
  baseUrl: string,
  serviceKey: string,
  token: string,
  conversaId: string,
  timeoutMs: number,
): Promise<{ rota: string | null; candidatas: string[]; falha: string | null }> {
  const VAZIO = (falha: string) => ({ rota: null, candidatas: [], falha });
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const r = await fetch(`${baseUrl}/functions/v1/router?token=${encodeURIComponent(token)}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": serviceKey,
        "Authorization": `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({ conversa_id: conversaId, canal: CANAL }),
      signal: controller.signal,
    });
    if (!r.ok) return VAZIO(`router_http_${r.status}`);
    const saida = await r.json() as Record<string, unknown>;
    if (saida?.ok !== true) return VAZIO(String(saida?.motivo ?? saida?.error ?? "router_nao_ok"));
    return {
      rota: typeof saida.rota === "string" ? saida.rota : null,
      candidatas: Array.isArray(saida.candidatas)
        ? saida.candidatas.filter((c): c is string => typeof c === "string")
        : [],
      falha: null,
    };
  } catch (e) {
    const isTimeout = e instanceof DOMException && e.name === "AbortError";
    return VAZIO(isTimeout ? "router_timeout" : "router_indisponivel");
  } finally {
    clearTimeout(timeout);
  }
}

function extractOutputText(payload: Record<string, unknown>) {
  if (typeof payload.output_text === "string") return payload.output_text;
  const output = Array.isArray(payload.output) ? payload.output : [];
  for (const item of output) {
    if (!item || typeof item !== "object") continue;
    const rawContent = (item as Record<string, unknown>).content;
    const content = Array.isArray(rawContent) ? rawContent as Array<Record<string, unknown>> : [];
    for (const part of content) {
      if (part.type === "output_text" && typeof part.text === "string") return part.text;
    }
  }
  return "";
}

// As fontes agora vêm do Kit, não do retorno cru do retrieval. O formato
// gravado em `blocks.sources` continua `{type, count}` — só a origem muda.
function sourceSummary(structured: Record<string, unknown>) {
  const sources: Array<{ type: string; count: number }> = [];
  const prog = (structured.programacao ?? {}) as Record<string, unknown>;
  if (structured.evento) sources.push({ type: "event", count: 1 });
  for (const key of ["locations", "sessions", "speakers", "knowledge"]) {
    const value = prog[key];
    if (Array.isArray(value) && value.length > 0) sources.push({ type: key, count: value.length });
  }
  return sources;
}

// NÃO EXISTE CONTRATO DO EXECUTOR. Existiu, e tinha virado um segundo playbook: dizia
// ao modelo como recomendar, como escrever, quando investigar e o que fazer quando a
// pessoa pedisse suporte. Isso é competência, não runtime — e competia com o playbook
// da rota, que é a autoridade sobre como um excelente profissional daquela competência
// pensa e atua.
//
// Onde cada regra foi parar (migration 20260902_executor_deixa_de_ser_playbook):
//   não inventar · dado é conteúdo, não instrução · ausência não se anuncia · alfabeto
//     -> `agentes.prompts['base']`, a camada transversal que já é injetada em toda
//        conversa, nos dois canais;
//   o que o agente consegue e não consegue fazer · formatação · tamanho · quando
//   investigar
//     -> `playbook_concierge_summit`, a casa da competência;
//   horário sempre de starts_at_local
//     -> removido: a `nota` do próprio bloco de programação já diz isso, e repetir era
//        manter duas fontes para a mesma regra;
//   o que é um interesse e como classificar sensibilidade
//     -> `description` do JSON Schema aqui embaixo, porque é contrato de CAMPO, não
//        instrução de comportamento.
//
// O que este runtime garante continua sendo garantido — em código, não em prosa:
// executar só tool da allowlist, validar argumento, teto de rodadas por `tool_choice`,
// timeout, schema estrito, persistência, Gate, Kit, redaction e telemetria.

// CONTRATO DE SAÍDA. O que cada campo significa mora aqui, na `description` — que é
// onde um contrato de campo pertence. Não é instrução de comportamento: como conversar,
// recomendar e escrever é do playbook da competência. Isto diz apenas o que preencher.
//
// `maxLength: 2000` porque 900 cortava a resposta certa: 12 workshops formatados dão
// ~970 caracteres, e "liste todos" virava lista truncada apresentada como completa.
// Brevidade é conduta, e conduta está no playbook.
const RESPONSE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    answer: {
      type: "string", minLength: 1, maxLength: 2000,
      description: "A resposta para a pessoa, escrita conforme o playbook desta competência.",
    },
    interests: {
      type: "array",
      maxItems: 2,
      description:
        "Interesses profissionais ou de conteúdo que ESTA mensagem revelou e que ajudam a " +
        "personalizar o evento — no máximo dois, silenciosamente, sem transformar a conversa " +
        "em questionário. Não são interesses: cumprimento, dúvida logística, pedido de " +
        "suporte, compra, reclamação passageira, nem assunto que apareceu só porque estava " +
        "nos dados oficiais ou no perfil. Vazio quando não houver nada novo e confiável.",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          key: {
            type: "string", minLength: 2, maxLength: 80,
            description: "Categoria estável e abrangente, em minúsculas com underscore.",
          },
          label: {
            type: "string", minLength: 2, maxLength: 120,
            description: "O mesmo interesse como se escreve para uma pessoa ler.",
          },
          confidence: {
            type: "number", minimum: 0, maximum: 1,
            description: "Quanto a mensagem sustenta este interesse.",
          },
          confirmed: {
            type: "boolean",
            description:
              "true SOMENTE quando a mensagem atual declara o interesse diretamente ou pede " +
              "para guardá-lo. Nunca true para algo vindo dos dados oficiais ou do perfil.",
          },
          sensitivity: {
            type: "string", enum: [...SENSIBILIDADES],
            description:
              "De quem a mensagem fala, não de que tema. Empresa, equipe, mercado ou cenário " +
              "é contexto profissional: \"none\". A própria pessoa falando da saúde dela, ou " +
              "alguém que ela identifique, escolhe a chave correspondente. Na dúvida sobre de " +
              "quem se fala, não use \"none\".",
          },
        },
        required: ["key", "label", "confidence", "confirmed", "sensitivity"],
      },
    },
  },
  required: ["answer", "interests"],
};

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const startedAt = Date.now();

  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });

  const url = new URL(req.url);
  if (req.method === "GET" && url.pathname.endsWith("/health")) {
    return json(req, 200, {
      ok: true,
      service: "mindagent-chat",
      version: VERSION,
      model: Deno.env.get("OPENAI_MODEL") ?? DEFAULT_MODEL,
      openai_configured: Boolean(Deno.env.get("OPENAI_API_KEY")),
    }, requestId);
  }

  if (req.method !== "POST") {
    return json(req, 405, { ok: false, error: { code: "method_not_allowed", message: "Use POST." } }, requestId);
  }

  if (Number(req.headers.get("content-length") ?? 0) > 20_000) {
    return json(req, 413, { ok: false, error: { code: "payload_too_large", message: "Solicitação muito grande." } }, requestId);
  }

  let payload: ChatRequest;
  try {
    payload = await req.json();
  } catch {
    return json(req, 400, { ok: false, error: { code: "invalid_json", message: "Envie um JSON válido." } }, requestId);
  }

  const message = String(payload.message ?? "").trim();
  const eventSlug = String(payload.event_slug ?? DEFAULT_EVENT_SLUG).trim();
  // MODO AÇÃO. Mesmo endpoint, mesma sessão, mesma identidade: o que distingue
  // é a ferramenta pedida. Sem pergunta e sem modelo.
  const ferramenta = typeof payload.ferramenta === "string" ? payload.ferramenta.trim() : "";
  const modoAcao = ferramenta.length > 0;
  const identitySource = payload.identity?.source === "yazo_url" ? "yazo_url" : null;
  const identityEmailReceived = identitySource === "yazo_url" && validEmail(payload.identity?.email);
  const identityNameReceived = identitySource === "yazo_url" &&
    typeof payload.identity?.name === "string" && payload.identity.name.trim().length > 0;
  // Só na ABERTURA da conversa isto tem efeito: o banco grava com `where origem_codigo
  // is null`. Um turno posterior não reescreve a porta de entrada, e é isso que a torna
  // autoritativa em vez de um parâmetro que o cliente redefine quando quiser.
  const origemInformada = typeof payload.origem_codigo === "string"
    && ORIGEM_CODIGO_RE.test(payload.origem_codigo.trim())
    ? payload.origem_codigo.trim()
    : null;
  if (!validSlug(eventSlug) || (!modoAcao && (message.length < 1 || message.length > 1200))) {
    return json(req, 422, {
      ok: false,
      error: { code: "invalid_request", message: "Informe uma mensagem de até 1.200 caracteres e um evento válido." },
    }, requestId);
  }
  if (modoAcao && !Object.prototype.hasOwnProperty.call(FERRAMENTAS_PLAY, ferramenta)) {
    return json(req, 400, {
      ok: false,
      error: { code: "ferramenta_desconhecida", message: "Esta ação não está disponível." },
    }, requestId);
  }
  const argumentos = payload.argumentos;
  if (modoAcao && (typeof argumentos !== "object" || argumentos === null || Array.isArray(argumentos))) {
    return json(req, 400, {
      ok: false,
      error: { code: "argumentos_invalidos", message: "Os dados da ação são inválidos." },
    }, requestId);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const publishableKey = readKey("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY");
  const secretKey = readKey("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
  const openAiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  const model = Deno.env.get("OPENAI_MODEL") ?? DEFAULT_MODEL;
  if (!supabaseUrl || !publishableKey || !secretKey) {
    return json(req, 503, { ok: false, error: { code: "database_unavailable", message: "Serviço temporariamente indisponível." } }, requestId);
  }
  // A ação do Play não chama modelo nenhum: exigir a chave da OpenAI aqui
  // derrubaria uma coleta que não depende dela.
  if (!openAiKey && !modoAcao) {
    return json(req, 503, { ok: false, error: { code: "ai_not_configured", message: "A IA ainda não foi configurada." } }, requestId);
  }

  const authorization = req.headers.get("Authorization") ?? "";
  const userToken = authorization.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!userToken) {
    return json(req, 401, { ok: false, error: { code: "unauthorized", message: "Sessão de acesso ausente." } }, requestId);
  }

  const authClient = createClient(supabaseUrl, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await authClient.auth.getUser(userToken);
  if (userError || !userData.user) {
    return json(req, 401, { ok: false, error: { code: "unauthorized", message: "Sessão de acesso inválida." } }, requestId);
  }
  const authUserId = userData.user.id;
  const admin = createClient(supabaseUrl, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let sessionId: string;
  let conversationId: string;
  let sessionToken: string;
  const deviceId = validUuid(payload.device_id) ? payload.device_id : crypto.randomUUID();
  let expiresAt: string | null = null;
  let newSession = false;
  let profileLoaded = false;

  const startNewSession = async () => {
    const token = randomToken();
    const tokenHash = await sha256(token);
    const { data, error } = await admin.rpc("mindagent_chat_start", {
      p_auth_user_id: authUserId,
      p_device_key: deviceId,
      p_user_agent: req.headers.get("User-Agent") ?? "",
      p_token_hash: tokenHash,
      p_origem_codigo: origemInformada,
    });
    if (error || !data) throw new Error("session_start_failed");
    return {
      sessionId: String(data.session_id),
      conversationId: String(data.conversation_id),
      sessionToken: token,
      expiresAt: typeof data.expires_at === "string" ? data.expires_at : null,
    };
  };

  try {
    const supplied = payload.session;
    if (
      supplied && validUuid(supplied.id) && validUuid(supplied.conversation_id) &&
      typeof supplied.token === "string" && /^[a-f0-9]{64}$/i.test(supplied.token)
    ) {
      sessionId = supplied.id;
      conversationId = supplied.conversation_id;
      sessionToken = supplied.token;
    } else {
      newSession = true;
      ({ sessionId, conversationId, sessionToken, expiresAt } = await startNewSession());
    }

    let tokenHash = await sha256(sessionToken);

    if (identityEmailReceived) {
      const bindIdentity = async () => {
        const { data, error } = await admin.rpc("mindagent_chat_bind_identity", {
          p_auth_user_id: authUserId,
          p_session_id: sessionId,
          p_conversation_id: conversationId,
          p_token_hash: tokenHash,
          p_email: String(payload.identity?.email ?? "").trim().toLowerCase(),
          // O NOME ATRAVESSA. Chegava até aqui e era descartado por falta de
          // parâmetro: o e-mail virava identidade e `pessoas.pessoas` ficava sem
          // nome. Quem decide o que fazer com ele continua sendo
          // `mind_identidade_resolver` — que preenche quando falta e nunca
          // sobrescreve nome canônico existente. Aqui é só encanamento.
          p_nome: identityNameReceived
            ? String(payload.identity?.name ?? "").trim().slice(0, 160)
            : null,
        });
        if (error) {
          console.warn(JSON.stringify({ request_id: requestId, event: "identity_bind_failed" }));
          return null;
        }
        return data as Record<string, unknown>;
      };

      let binding = await bindIdentity();
      if (binding?.conflict === true) {
        newSession = true;
        ({ sessionId, conversationId, sessionToken, expiresAt } = await startNewSession());
        tokenHash = await sha256(sessionToken);
        binding = await bindIdentity();
      }
      profileLoaded = binding?.found === true;
    }

    const { data: sessionContext, error: contextError } = await admin.rpc("mindagent_chat_get_context", {
      p_auth_user_id: authUserId,
      p_session_id: sessionId,
      p_conversation_id: conversationId,
      p_token_hash: tokenHash,
    });
    if (contextError || !sessionContext) {
      return json(req, 401, { ok: false, error: { code: "session_expired", message: "A conversa expirou. Inicie uma nova sessão." } }, requestId);
    }
    profileLoaded = profileLoaded || Boolean(sessionContext.participant_profile);
    const personalizationProfile = buildPersonalizationProfile(sessionContext.participant_profile);

    // HISTÓRICO DA CONVERSA. `mindagent_chat_get_context` sempre devolveu `history`, e
    // este runtime sempre descartou — então toda pergunta de seguimento morria. Medido:
    // "Por quê?", logo depois de uma recomendação, respondia "não entendi o suficiente".
    // Ele é lido AQUI, antes de a fala atual ser persistida, então não contém a pergunta
    // deste turno e não duplica nada.
    const historico = (Array.isArray(sessionContext.history) ? sessionContext.history : [])
      .filter((h: unknown): h is { role: string; content: string } =>
        Boolean(h) && typeof h === "object" &&
        typeof (h as Record<string, unknown>).content === "string" &&
        String((h as Record<string, unknown>).content).trim().length > 0)
      // Janela curta de propósito: o histórico é reenviado a cada rodada de ferramenta,
      // então cada turno guardado custa três vezes. Oito mensagens cobrem o seguimento
      // ("por quê?", "e o segundo?") sem inflar o turno.
      .slice(-8)
      .map((h) => ({
        role: h.role === "user" ? "user" : "assistant",
        content: h.content.slice(0, 1000),
      }));
    expiresAt = expiresAt ?? (typeof sessionContext.expires_at === "string" ? sessionContext.expires_at : null);

    const pessoaId = typeof sessionContext.participant_profile?.participant_id === "string"
      ? sessionContext.participant_profile.participant_id
      : null;

    // ==================================================== MODO AÇÃO (Play)
    // Sessão, identidade e conversa já foram resolvidas acima, exatamente
    // como no chat — inclusive para quem chega da Yazo sem nunca ter falado
    // com o Concierge: `startNewSession` criou a sessão canônica e
    // `bind_identity` ligou a pessoa. Daqui em diante é só executar.
    if (modoAcao) {
      // v1 é person-bound: sem pessoa não há coleta. Não é erro de servidor —
      // é a regra do produto, e a tela precisa poder dizer isso.
      if (!pessoaId) {
        console.warn(JSON.stringify({ request_id: requestId, event: "play_sem_pessoa", ferramenta }));
        return json(req, 200, {
          ok: false,
          error: { code: "sem_pessoa", message: "Precisamos identificar você para registrar isso." },
        }, requestId);
      }

      const alvo = FERRAMENTAS_PLAY[ferramenta];
      const sessaoDaAcao = {
        id: sessionId, conversation_id: conversationId, token: sessionToken, expires_at: expiresAt,
      };
      const acaoOk = (resultado: unknown) => json(req, 200, {
        ok: true,
        resultado,
        session: sessaoDaAcao,
        device_id: deviceId,
        request_id: requestId,
      }, requestId);
      const acaoRecusada = (code: string, message: string, status = 200) =>
        json(req, status, { ok: false, error: { code, message } }, requestId);

      // ------------------------------------------- IDEMPOTÊNCIA DE TRANSPORTE
      // `client_action_id` chega com um contrato explícito do cliente: "rede
      // repete; a pessoa não". Os writers já são idempotentes por chave
      // natural — menos `registrar_feedback_evento` sem mensagem, que é
      // exatamente como este runtime o chama: ali, um retry vira dois relatos.
      //
      // A casa é `concierge.ferramenta_chamadas`, que já existe com
      // `idempotency_key` e índice UNIQUE parcial. Reservar ANTES de executar
      // é o que fecha a corrida: quem insere executa, quem colide recebe o que
      // a primeira tentativa registrou.
      const chaveAcao = typeof payload.client_action_id === "string" && payload.client_action_id.trim()
        ? payload.client_action_id.trim().slice(0, 200)
        : null;

      let chamadaId: string | null = null;
      if (chaveAcao) {
        const { data: reserva, error: reservaError } = await admin.rpc("mind_play_chamada_iniciar", {
          p_ferramenta: ferramenta,
          p_pessoa_id: pessoaId,
          p_idempotency_key: chaveAcao,
          p_entrada: argumentos ?? {},
        });
        // Fail closed: o cliente foi prometido deduplicação. Sem o ledger não
        // dá para cumprir, e executar assim mesmo é o defeito, não o contorno.
        if (reservaError || reserva?.ok !== true) {
          const motivo = typeof reserva?.motivo === "string" ? reserva.motivo : null;
          console.error(JSON.stringify({
            request_id: requestId, event: "play_reserva_falhou", ferramenta, motivo,
            detalhe: reservaError?.message ?? null,
          }));
          return motivo === "chave_conflitante"
            ? acaoRecusada("chave_conflitante", "Esta identificação de ação já foi usada em outro registro.", 409)
            : acaoRecusada("acao_falhou", "Não consegui registrar agora.", 502);
        }
        if (reserva.estado === "repetida") {
          // A MESMA tentativa. Devolve o desfecho gravado; o writer não roda de novo.
          const saida = (reserva.saida ?? null) as Record<string, unknown> | null;
          console.info(JSON.stringify({
            request_id: requestId, event: "play_repetido", ferramenta,
            status_original: reserva.status ?? null, duration_ms: Date.now() - startedAt,
          }));
          if (reserva.status === "concluida") return acaoOk(saida);
          if (reserva.status === "recusada") {
            return acaoRecusada(codigoDeRecusa(saida), "Não consegui registrar isso.");
          }
          return acaoRecusada("acao_falhou", "Não consegui registrar agora.", 502);
        }
        if (reserva.estado === "em_andamento") {
          // A primeira tentativa ainda não respondeu. Executar agora duplicaria.
          return acaoRecusada("acao_em_andamento", "Esta ação ainda está sendo registrada.", 409);
        }
        chamadaId = typeof reserva.chamada_id === "string" ? reserva.chamada_id : null;
      }

      const args: Record<string, unknown> = {
        p_pessoa_id: pessoaId,
        p_payload: argumentos ?? {},
      };
      if (alvo.vinculo === "conversa") args.p_conversa_id = conversationId;
      if (alvo.vinculo === "mensagem") args.p_mensagem_id = null;

      const { data: resultado, error: acaoError } = await admin.rpc(alvo.rpc, args);

      const fecharChamada = async (
        status: "concluida" | "recusada" | "falhou",
        saida: unknown,
        httpStatus: number,
        erro: string | null,
      ) => {
        if (!chamadaId) return;
        const { error } = await admin.rpc("mind_play_chamada_concluir", {
          p_chamada_id: chamadaId,
          p_status: status,
          p_saida: saida ?? null,
          p_http_status: httpStatus,
          p_latencia_ms: Date.now() - startedAt,
          p_erro: erro,
        });
        // O writer já rodou: não dá para desfazer, e reexecutar é o que não se
        // quer. A reserva fica em andamento e o retry recebe `acao_em_andamento`
        // — pessimista, nunca duplicado.
        if (error) {
          console.warn(JSON.stringify({
            request_id: requestId, event: "play_ledger_nao_fechou", ferramenta, chamada_id: chamadaId,
          }));
        }
      };

      if (acaoError) {
        await fecharChamada("falhou", null, 502, acaoError.message);
        console.error(JSON.stringify({
          request_id: requestId, event: "play_falhou", ferramenta, rpc: alvo.rpc,
          detalhe: acaoError.message,
        }));
        return acaoRecusada("acao_falhou", "Não consegui registrar agora.", 502);
      }

      // RECUSA DO WRITER É RECUSA, NÃO SUCESSO.
      // As `mind_play_*` devolvem erro de domínio como DADO —
      // `{ok:false, motivo:"sem_nota"}` — e não como exception. Olhar só o
      // `acaoError` fazia a Edge responder top-level `ok:true` carregando uma
      // recusa dentro, e o `play-service.js` lê o top-level: a tela diria que
      // registrou o que o banco recusou. Sucesso agora exige as duas coisas.
      const escrita = (resultado ?? null) as Record<string, unknown> | null;
      if (escrita?.ok !== true) {
        const recusa = escrita?.ok === false;
        await fecharChamada(
          recusa ? "recusada" : "falhou",
          escrita,
          recusa ? 200 : 502,
          recusa ? null : "writer sem contrato ok",
        );
        console.warn(JSON.stringify({
          request_id: requestId, event: recusa ? "play_recusado" : "play_sem_contrato",
          ferramenta, rpc: alvo.rpc, motivo: escrita?.motivo ?? null,
          duration_ms: Date.now() - startedAt,
        }));
        // Recusa de negócio não é erro de servidor; contrato quebrado é.
        return recusa
          ? acaoRecusada(codigoDeRecusa(escrita), "Não consegui registrar isso.")
          : acaoRecusada("acao_falhou", "Não consegui registrar agora.", 502);
      }

      await fecharChamada("concluida", escrita, 200, null);

      console.info(JSON.stringify({
        request_id: requestId, status: 200, event: "play_executado",
        ferramenta, rpc: alvo.rpc, session_id: sessionId, new_session: newSession,
        client_action_id: chaveAcao,
        duration_ms: Date.now() - startedAt,
      }));

      return acaoOk(escrita);
    }

    // ==================================================== MODO CHAT
    const clientMessageId = typeof payload.client_message_id === "string" &&
        payload.client_message_id.length > 0 && payload.client_message_id.length <= 120
      ? payload.client_message_id
      : crypto.randomUUID();

    // A FALA DA PESSOA É PERSISTIDA ANTES DE QUALQUER COISA QUE POSSA RECUSAR
    // O TURNO. Gate fechado, Kit indisponível ou OpenAI fora do ar custam a
    // resposta — nunca o registro do que a pessoa disse. A idempotência por
    // `client_message_id` mantém o retry sem linha duplicada.
    const { data: userMessage, error: userMessageError } = await admin.rpc("mindagent_chat_save_message", {
      p_auth_user_id: authUserId,
      p_session_id: sessionId,
      p_conversation_id: conversationId,
      p_token_hash: tokenHash,
      p_role: "user",
      p_content: message,
      p_client_message_id: clientMessageId,
      p_blocks: null,
    });
    if (userMessageError || !userMessage) throw new Error("user_message_save_failed");

    // ----------------------------------------------------------- ROUTER
    // ATÉ A v1.5.0 ISTO NÃO EXISTIA. A rota era constante: "mindagent-web é
    // concierge por construção". A frase era verdadeira quando o App só tinha uma
    // competência — e virou errada no dia em que passou a ter duas. Medido em
    // runtime: "Meu ingresso não apareceu no app e eu preciso de ajuda" continuava
    // em `concierge_summit`, porque ninguém perguntava.
    //
    // Agora o canal define o universo e o Router escolhe dentro dele. As rotas do
    // App NÃO estão escritas aqui: quem sabe é `agentes.canal_competencia`, lida
    // pelo Router via `mind_canal_rotas`. Repetir a lista nesta Edge recriaria a
    // segunda autoridade que a política acabou de eliminar.
    // ORIGEM AUTORITATIVA VEM ANTES DO ROUTER. Quem entrou pelo app oficial já disse,
    // pela porta, qual competência quer. O Router existe para decidir; aqui não há o que
    // decidir, e perguntar é gasto e chance de errar — medido: "Oi" no App caía em
    // `cliente_suporte` porque o Router não sabia de onde a pessoa veio.
    //
    // A origem lida é a PERSISTIDA na conversa, não a que veio no corpo deste turno: o
    // banco grava uma vez, na abertura. Um cliente não muda a rota de uma conversa
    // mandando outro código depois.
    const origemDaConversa = typeof sessionContext.origem_codigo === "string"
      ? sessionContext.origem_codigo.trim()
      : "";
    const rotaAutoritativa = ROTA_POR_ORIGEM[origemDaConversa] ?? null;

    let rotaOrigem = "router";
    let rotaFalha: string | null = null;
    let rotaDecidida = "concierge_summit";
    let routerToken = "";
    const antesDoRouter = Date.now();

    if (rotaAutoritativa) {
      // O Gate continua obrigatório logo abaixo: a origem diz QUAL competência foi
      // acionada, nunca se ela executa.
      rotaDecidida = rotaAutoritativa;
      rotaOrigem = "origem_autoritativa";
    } else {
      const { data: cfgCore } = await admin.rpc("analise_config");
      routerToken = typeof cfgCore?.analise_token === "string" ? cfgCore.analise_token : "";

      if (routerToken) {
        const r = await decidirRota(
          supabaseUrl, secretKey, routerToken, conversationId, ROUTER_TIMEOUT_MS,
        );
        rotaFalha = r.falha;
        if (r.rota) {
          rotaDecidida = r.rota;
        } else if (r.candidatas.length > 0) {
          // CLARIFY. O Router disse "não dá para saber ENTRE ESTAS" e devolveu a lista,
          // já filtrada pela política do canal. O desempate era `candidatas[0]` — a ordem
          // em que o modelo listou, ou seja, arbitrária. Medido em produção: "Oi", "Olá" e
          // "teste" caíam em `cliente_suporte`, e a porta de entrada do App se apresentava
          // como atendimento. O App é o concierge; suporte é para onde se roteia quando há
          // sinal de suporte, não o padrão de quem só disse oi.
          //
          // Então o empate resolve igual ao piso de indisponibilidade logo abaixo: se o
          // concierge está entre as candidatas do próprio Router, é ele. Não é rota nova
          // nem lista de rotas do canal duplicada aqui — é escolher dentro do que o Router
          // devolveu, de forma determinística em vez de arbitrária.
          rotaDecidida = r.candidatas.includes("concierge_summit")
            ? "concierge_summit"
            : r.candidatas[0];
          rotaOrigem = "clarify_concierge_padrao";
        } else {
          rotaOrigem = "fallback_router_indisponivel";
        }
      } else {
        rotaFalha = "router_sem_token";
        rotaOrigem = "fallback_router_indisponivel";
      }
    }
    const routerMs = Date.now() - antesDoRouter;

    // O FALLBACK NÃO ESCAPA DA POLÍTICA. Seja qual for a origem da rota, ela passa
    // pelo Gate abaixo com este canal — inclusive o fallback. Se a política não
    // servir a rota aqui, o turno não acontece. `concierge_summit` é piso de
    // INDISPONIBILIDADE do Router, não decisão de roteamento: por isso sai no log
    // como `rota_origem`, e é medível.

    // ------------------------------------------------------------- GATE
    // O Gate responde se este runtime consegue executar a rota escolhida agora,
    // neste canal.
    const { data: gate, error: gateError } = await admin.rpc("mind_rota_capacidade", {
      p_rota: rotaDecidida,
      p_canal: CANAL,
    });
    if (gateError || gate?.ok !== true || gate?.pode_executar !== true) {
      console.error(JSON.stringify({
        request_id: requestId, event: "gate_fechado",
        rota: rotaDecidida, rota_origem: rotaOrigem, router_falha: rotaFalha,
        reason: gate?.reason ?? gate?.motivo ?? null,
      }));
      return json(req, 503, {
        ok: false,
        error: { code: "rota_indisponivel", message: "Não consegui consultar os dados oficiais agora." },
      }, requestId);
    }

    // -------------------------------------------------------------- KIT
    // NECESSIDADE ATUAL e MEMÓRIA entram por campos separados: `pergunta` é a
    // única coisa que seleciona, `interesses` só reordena o que já foi
    // selecionado. Concatenar os dois — como a v1.4.0 fazia — apagava a
    // listagem de agenda e fazia pergunta sem lastro receber conteúdo de
    // interesse. `event_slug` preserva o contrato que o payload já tinha.
    const { data: kit, error: kitError } = await admin.rpc("mind_agent_kit", {
      p_rota: rotaDecidida,
      p_conversa_id: conversationId,
      p_necessidade: {
        event_slug: eventSlug,
        pergunta: message,
        // 8 cortava listas legítimas: são 12 workshops e 6 por dia. `sessions_total`
        // continua dizendo quantos existem quando ainda assim faltar.
        limite: 12,
        interesses: personalizationProfile?.interesses?.slice(0, 3) ?? [],
      },
    });

    // FAIL-CLOSED. Sem Kit disponível, sem playbook ou sem nenhum bloco, o modelo
    // não é chamado: responder sem a verdade mínima é como a invenção começa.
    //
    // A CONFERÊNCIA DEIXOU DE CITAR BLOCO POR NOME. Antes exigia `evento` e
    // `programacao` — os blocos do concierge —, o que só funcionava enquanto havia
    // uma rota só. Quem declara o que é obrigatório é `agentes.kit_blocos`, e quem
    // confere é `mind_kit_meta`: `kit_disponivel` já é essa resposta.
    const structuredDoKit = (kit?.structured ?? {}) as Record<string, unknown>;
    const kitOk = !kitError && kit && kit.ok !== false &&
      kit.meta?.kit_disponivel === true &&
      typeof kit.playbook === "string" && kit.playbook.trim().length > 0 &&
      Object.keys(structuredDoKit).length > 0;
    if (!kitOk) {
      console.error(JSON.stringify({
        request_id: requestId, event: "kit_indisponivel",
        rota: rotaDecidida, rota_origem: rotaOrigem,
        motivo: kit?.motivo ?? null,
        kit_disponivel: kit?.meta?.kit_disponivel ?? null,
        blocos: Object.keys(structuredDoKit),
        detalhe: kitError?.message ?? null,
      }));
      return json(req, 503, {
        ok: false,
        error: { code: "official_data_unavailable", message: "Não consegui consultar os dados oficiais agora." },
      }, requestId);
    }
    const officialContext = kit.structured;

    // ------------------------------------------------------------ TOOLS
    // QUAIS ferramentas existem neste turno é decisão do Kit, no banco. COMO cada
    // uma executa está em `FERRAMENTAS_INTELLIGENCE`. O que o Kit expõe e este
    // runtime não sabe executar é descartado — com registro, porque é divergência
    // entre política e executor, não erro do turno.
    const toolsDoKit = Array.isArray(kit.tools) ? kit.tools as Array<Record<string, unknown>> : [];
    const ferramentasAtivas = toolsDoKit.filter((t) =>
      typeof t?.nome === "string" &&
      Object.prototype.hasOwnProperty.call(FERRAMENTAS_INTELLIGENCE, t.nome as string) &&
      t?.parametros && typeof t.parametros === "object");
    const semExecutor = toolsDoKit.length - ferramentasAtivas.length;
    if (semExecutor > 0) {
      console.warn(JSON.stringify({
        request_id: requestId, event: "tool_sem_executor",
        rota: rotaDecidida, quantidade: semExecutor,
      }));
    }
    const toolsParaModelo = ferramentasAtivas.map((t) => ({
      type: "function",
      name: String(t.nome),
      description: typeof t.descricao === "string" ? t.descricao : "",
      parameters: t.parametros,
      strict: true,
    }));
    const nomesDasFerramentas = toolsParaModelo.map((t) => t.name);

    const aiContext = {
      official_context: officialContext,
      ...(personalizationProfile ? { personalization_profile: personalizationProfile } : {}),
      user_question: redactForAi(message),
    };
    // ------------------------------------------------------- TOOL LOOP
    // O turno deixa de ser uma geração só. O modelo pode pedir ferramenta, ler o
    // resultado e pedir de novo — no máximo `MAX_RODADAS_TOOL` vezes. Na última
    // rodada `tool_choice` vira "none": as ferramentas continuam declaradas (o
    // histórico da conversa referencia as chamadas já feitas), mas o modelo não
    // tem escolha senão responder. É assim que "no máximo 2 rodadas" vira garantia
    // do runtime em vez de pedido no prompt.
    //
    // MÚLTIPLAS CHAMADAS NUMA RODADA SÃO EXECUTADAS JUNTAS. Se o modelo pedir três
    // leituras de uma vez, forçar uma por vez gastaria três rodadas para fazer o
    // trabalho de uma — e o orçamento do turno é de quem está esperando resposta.
    const entradaDoModelo: Array<Record<string, unknown>> = [
      ...historico,
      { role: "user", content: `Responda usando este JSON:\n${JSON.stringify(aiContext)}` },
    ];
    const fimDoOrcamento = startedAt + ORCAMENTO_TURNO_MS;
    // As instruções do turno são as da COMPETÊNCIA, e só. O Kit já entrega o playbook
    // da rota com a camada transversal `base` na frente.
    const instrucoes = kit.playbook as string;

    let openAiResponse!: Response;
    let openAiPayload: Record<string, unknown> = {};
    let outputText = "";
    let rodadasTool = 0;
    const chamadasFeitas: Array<{ nome: string; ok: boolean }> = [];

    for (let volta = 0; volta <= MAX_RODADAS_TOOL; volta++) {
      const restante = fimDoOrcamento - Date.now();
      if (restante <= 0) throw new DOMException("orcamento_do_turno", "AbortError");

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), restante);
      try {
        openAiResponse = await fetch("https://api.openai.com/v1/responses", {
          method: "POST",
          headers: { "Authorization": `Bearer ${openAiKey}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            model,
            instructions: instrucoes,
            input: entradaDoModelo,
            // SEM FERRAMENTA, `none` — é o comportamento que já estava em produção e
            // que não deve mudar por causa desta entrega. COM ferramenta, `low`:
            // decidir se busca, o que buscar e se o resultado responde é raciocínio,
            // e com `none` o modelo tende a responder direto sem investigar.
            reasoning: { effort: toolsParaModelo.length > 0 ? "low" : "none" },
            text: {
              format: {
                type: "json_schema", name: "mindagent_response", strict: true, schema: RESPONSE_SCHEMA,
              },
            },
            ...(toolsParaModelo.length > 0
              ? { tools: toolsParaModelo, tool_choice: volta >= MAX_RODADAS_TOOL ? "none" : "auto" }
              : {}),
            // Com ferramenta o teto sobe: `max_output_tokens` inclui os tokens de
            // raciocínio, e estourar o teto devolve resposta `incomplete` — texto
            // vazio, turno perdido. A resposta em si continua limitada pelo schema
            // (`maxLength`); a folga aqui é para o modelo pensar.
            max_output_tokens: toolsParaModelo.length > 0 ? 3000 : 1500,
            safety_identifier: authUserId,
            store: false,
          }),
          signal: controller.signal,
        });
      } finally {
        clearTimeout(timeout);
      }

      if (!openAiResponse.ok) break;

      openAiPayload = await openAiResponse.json() as Record<string, unknown>;
      const chamadas = extractFunctionCalls(openAiPayload);
      if (chamadas.length === 0) {
        outputText = extractOutputText(openAiPayload);
        break;
      }

      // A chamada volta para a entrada ANTES do resultado: a Responses API precisa
      // do par completo para continuar a conversa na próxima geração.
      for (const c of chamadas) {
        entradaDoModelo.push({
          type: "function_call", call_id: c.call_id, name: c.name, arguments: c.arguments,
        });
      }

      const resultados = await Promise.all(chamadas.map(async (c) => {
        const alvo = FERRAMENTAS_INTELLIGENCE[c.name];
        // Ferramenta fora da allowlist não executa e não derruba o turno: volta como
        // recusa nomeada, e o modelo segue com o que tem.
        if (!alvo) return { call_id: c.call_id, output: JSON.stringify({ erro: "ferramenta_desconhecida" }), nome: c.name, ok: false };
        let bruto: Record<string, unknown>;
        try {
          const parsed = JSON.parse(c.arguments || "{}");
          bruto = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
        } catch {
          return { call_id: c.call_id, output: JSON.stringify({ erro: "argumentos_invalidos" }), nome: c.name, ok: false };
        }
        const { data, error } = await admin.rpc(alvo.rpc, alvo.args(bruto));
        if (error) {
          console.warn(JSON.stringify({
            request_id: requestId, event: "tool_falhou", tool: c.name, detalhe: error.message,
          }));
          return { call_id: c.call_id, output: JSON.stringify({ erro: "consulta_indisponivel" }), nome: c.name, ok: false };
        }
        // `null` é resposta legítima: o objeto não existe ou não está visível. Vira
        // "nao_encontrado" para o modelo não confundir ausência com falha — e para
        // ele dizer que não achou em vez de completar de cabeça.
        return {
          call_id: c.call_id,
          output: JSON.stringify(data ?? { resultado: "nao_encontrado" }).slice(0, 24_000),
          nome: c.name,
          ok: true,
        };
      }));

      for (const r of resultados) {
        entradaDoModelo.push({ type: "function_call_output", call_id: r.call_id, output: r.output });
        chamadasFeitas.push({ nome: r.nome, ok: r.ok });
      }
      rodadasTool++;
    }
    // O ERRO DA OPENAI CONTINUA SENDO TRADUZIDO COMO ANTES. O loop pode sair por
    // resposta não-ok em qualquer rodada — inclusive depois de uma ferramenta já ter
    // executado —, e a tela precisa da mesma taxonomia de sempre.
    if (!openAiResponse.ok) {
      const status = openAiResponse.status;
      const upstreamPayload = await openAiResponse.json().catch(() => ({})) as Record<string, unknown>;
      const upstreamError = upstreamPayload.error && typeof upstreamPayload.error === "object"
        ? upstreamPayload.error as Record<string, unknown>
        : {};
      const upstreamCode = typeof upstreamError.code === "string" ? upstreamError.code : null;
      const upstreamType = typeof upstreamError.type === "string" ? upstreamError.type : null;
      const publicCode = status === 401
        ? "ai_authentication_failed"
        : status === 403
        ? "ai_access_denied"
        : status === 404
        ? "ai_model_unavailable"
        : status === 429
        ? "ai_busy"
        : status === 400
        ? "ai_request_invalid"
        : "ai_unavailable";
      console.error(JSON.stringify({
        request_id: requestId,
        event: "openai_error",
        status,
        upstream_code: upstreamCode,
        upstream_type: upstreamType,
        model,
        rota: rotaDecidida,
        rodadas_tool: rodadasTool,
        duration_ms: Date.now() - startedAt,
      }));
      return json(req, status === 429 ? 429 : 502, {
        ok: false,
        error: {
          code: publicCode,
          message: status === 429 ? "Muitas solicitações agora. Tente novamente em instantes." : "Não consegui gerar a resposta agora.",
          diagnostic: { upstream_status: status, upstream_code: upstreamCode, upstream_type: upstreamType },
        },
      }, requestId);
    }

    let structured: { answer: string; interests: Interest[] };
    try {
      structured = JSON.parse(outputText);
    } catch {
      throw new Error("invalid_ai_output");
    }

    const answer = normalizeAnswerLayout(String(structured.answer ?? "")).slice(0, 2000).trim();
    if (!answer) throw new Error("empty_ai_answer");
    const interests = (Array.isArray(structured.interests) ? structured.interests : [])
      .slice(0, 2)
      .map((interest) => ({
        key: normalizeInterestKey(String(interest.key ?? interest.label ?? "")),
        label: String(interest.label ?? "").trim().slice(0, 120),
        confidence: Math.max(0, Math.min(1, Number(interest.confidence ?? 0))),
        confirmed: interest.confirmed === true,
        // Repassado INTACTO para `mindagent_chat_save_interests`. A política é
        // do gate da Lane D, no banco; aqui não se decide nem se corrige. Um
        // valor fora do enum vira string desconhecida — e desconhecido é
        // bloqueado do outro lado, que é o lado certo para errar.
        sensitivity: typeof interest.sensitivity === "string" && interest.sensitivity.trim()
          ? interest.sensitivity.trim().slice(0, 60)
          : "desconhecido",
      }))
      .filter((interest) => interest.key.length >= 2 && interest.label.length >= 2 && interest.confidence >= 0.65);

    const sources = sourceSummary(officialContext);
    const { data: assistantMessage, error: assistantMessageError } = await admin.rpc("mindagent_chat_save_message", {
      p_auth_user_id: authUserId,
      p_session_id: sessionId,
      p_conversation_id: conversationId,
      p_token_hash: tokenHash,
      p_role: "assistant",
      p_content: answer,
      p_client_message_id: `${clientMessageId}:assistant`,
      p_blocks: {
        sources,
        model,
        identity_received: {
          email: identityEmailReceived,
          name: identityNameReceived,
          source: identitySource,
        },
        profile_loaded: profileLoaded,
        // A ROTA VIRA REGISTRO. Sem isto não dá para responder depois "por que este
        // turno foi para suporte?" nem medir com que frequência o Router não decide.
        rota: rotaDecidida,
        rota_origem: rotaOrigem,
        origem_codigo: origemDaConversa || null,
        rodadas_tool: rodadasTool,
        ferramentas: chamadasFeitas,
      },
    });
    if (assistantMessageError || !assistantMessage) throw new Error("assistant_message_save_failed");

    if (interests.length > 0) {
      const { error: interestError } = await admin.rpc("mindagent_chat_save_interests", {
        p_auth_user_id: authUserId,
        p_session_id: sessionId,
        p_token_hash: tokenHash,
        p_interests: interests,
        p_evidence_message_id: userMessage.id,
      });
      if (interestError) console.warn(JSON.stringify({ request_id: requestId, event: "interest_save_failed", session_id: sessionId }));
    }

    console.info(JSON.stringify({
      request_id: requestId, status: 200, event_slug: eventSlug, session_id: sessionId,
      new_session: newSession, model, interests: interests.length, duration_ms: Date.now() - startedAt,
      rota: rotaDecidida, rota_origem: rotaOrigem, router_falha: rotaFalha, router_ms: routerMs,
      origem_codigo: origemDaConversa || null,
      tools_expostas: nomesDasFerramentas.length, rodadas_tool: rodadasTool,
      historico: historico.length,
      chamadas_tool: chamadasFeitas.length,
      identity_email_received: identityEmailReceived,
      identity_name_received: identityNameReceived,
      identity_source: identitySource,
      profile_loaded: profileLoaded,
    }));

    return json(req, 200, {
      ok: true,
      answer,
      session: { id: sessionId, conversation_id: conversationId, token: sessionToken, expires_at: expiresAt },
      device_id: deviceId,
      identity_verified: false,
      identity_received: {
        email: identityEmailReceived,
        name: identityNameReceived,
        source: identitySource,
      },
      profile_loaded: profileLoaded,
      rota: rotaDecidida,
      interests,
      sources,
      request_id: requestId,
    }, requestId);
  } catch (error) {
    const isTimeout = error instanceof DOMException && error.name === "AbortError";
    console.error(JSON.stringify({
      request_id: requestId, status: isTimeout ? 504 : 500,
      event: isTimeout ? "ai_timeout" : "unexpected_error",
      reason: error instanceof Error ? error.message : "unknown",
      duration_ms: Date.now() - startedAt,
    }));
    return json(req, isTimeout ? 504 : 500, {
      ok: false,
      error: {
        code: isTimeout ? "ai_timeout" : "internal_error",
        message: isTimeout ? "A resposta demorou demais. Tente novamente." : "Não consegui concluir a conversa agora.",
      },
    }, requestId);
  }
});
