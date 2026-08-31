// Cérebro do agente inbound de vendas do Mind no WhatsApp.
//
// v1.5.2 — O CANAL VAI AO ROUTER. Ate aqui a chamada mandava so `conversa_id`, e o
// Router escolhia entre as seis rotas globais sem saber onde estava. Duas perguntas
// banais de lead ("Quando sera o evento?", "quais palestrantes estarao no summit?")
// foram para `concierge_summit`, que este canal nao serve, e viraram transferencia.
// Agora o canal segue junto e o Router monta o enum da resposta a partir da politica
// em `agentes.canal_competencia`: rota proibida deixa de ser possivel no schema, nao
// apenas desaconselhada no prompt. O Gate continua validando depois.
//
// v1.5.1 — RESPOSTA PRONTA NAO SE CORTA POR CARACTERE. Ate a v1.5.0 havia tres tetos
// empilhados em 700: `answer.maxLength` no schema, `max_output_tokens` e um
// `.slice(0, 700)` no runtime. Um turno real chegou ao WhatsApp com exatamente 700
// caracteres, partido no meio de "Mind". O gatilho foi o playbook pedir as tres
// experiencias com preco, 12x e proposta de valor: nao cabia, e o teto ganhava do
// prompt. Agora o limite de tamanho e CONDUTA (esta na `description` do campo), nao
// tesoura: mensagem completa vale mais que frase mutilada.
//
// v1.5.0 — O CORE CANÔNICO É O ÚNICO CAMINHO. O legado saiu do runtime: não há mais
// fallback para o comportamento v1.3.0, `treble_agent_context` não é mais chamado, e a
// flag `core_rota_kit` deixou de existir aqui — ela decidia entre duas inteligências, e
// agora só existe uma.
//
// A decisão que isso implementa: quando o Core não serve o turno, este runtime NÃO
// improvisa. Ele encerra de forma controlada, com `needs_human`, e a fala da pessoa
// continua persistida desde a ingestão. Responder com dado antigo era pior que não
// responder — o piso factual do legado nunca soube diferenciar Mind/VIP/Prime nem
// entregar preço por volume, então "degradar" para ele era degradar a venda.
//
// UMA EXCEÇÃO, E ELA NÃO É QUEDA: o CLARIFY. `rota = null` com candidatas é o Router
// dizendo "ainda não dá para saber ENTRE ESTAS", e a resposta certa é uma pergunta. Esse
// turno segue sem Kit e sem DADOS_OFICIAIS — e, portanto, sem poder falar de preço, o
// que o guardrail garante sozinho quando o payload oficial vem vazio.
//
// O QUE ISSO CUSTA, dito com todas as letras: sem legado, uma falha técnica do Router
// vira transferência para humano em vez de resposta degradada. É penhasco, não rampa.
// Medido antes da mudança: o caminho legado havia atendido 7 conversas na história do
// canal, todas de teste — não havia tráfego real caindo nele.
//
// v1.4.0 — O TURNO PASSA A ATRAVESSAR O CORE: Router → Capability Gate → Kit Loader.
// Até a v1.3.0 este runtime decidia sozinho: a competência saía do próprio prompt
// (`playbook_router` classificava `audience` dentro da resposta) e os DADOS_OFICIAIS
// vinham do `treble_agent_context`, que ignora os cinco parâmetros que recebe e devolve
// sempre evento + ofertas. Agora:
//
//   1. ROUTER — a competência é decidida pela Edge Function `router` (Passo 10), dona
//      única da taxonomia das seis rotas. Nenhum segundo Router nasce aqui.
//   2. CAPABILITY GATE — `public.mind_rota_capacidade(rota, 'whatsapp')` responde se
//      ESTE runtime consegue executar a rota. Ele não muda rota e não é reimplementado.
//   3. KIT — `public.mind_agent_kit(rota, conversa, necessidade)` (Passo 12B) devolve
//      playbook + structured. O `structured` VIRA os DADOS_OFICIAIS: evento, ofertas
//      vigentes com checkout assinado, inclusões, regras comerciais e — em summit_b2b —
//      preços por volume, que o `treble_agent_context` nunca entregou.
//
// `audience` DEIXA DE SER DECISÃO DO MODELO no caminho canônico: ela vira derivação da
// rota. A chave continua no payload do Treble e em engagement.conversas porque é
// contrato público e estado persistido — mas quem manda é a rota, não o modelo.
//
// QUANDO O GATE FECHA, `needs_human` é forçado pelo runtime: o Gate é a autoridade
// sobre "esta necessidade não se conclui sozinha", e essa resposta é determinística —
// não fica a cargo da leitura do modelo.
//
// ESCOPO DE EXECUÇÃO: só `summit_b2c` e `summit_b2b` — as rotas deste vendedor.
// Carregar Kit ou playbook de `cliente_suporte`/`concierge_summit` aqui seria decidir
// por lane alheia; desde a v1.5.0, uma rota de outra lane encerra o turno com
// transferência em vez de ser respondida por um vendedor que não é dono dela. O Gate,
// porém, é consultado para TODAS (ver abaixo): capacidade não é execução.
//
// O GUARDRAIL DE PREÇO SAIU DAQUI para `guardrail-preco.ts`, e ficou mais estreito no
// caminho: a lista de valores permitidos passou a sair de CAMPOS MONETÁRIOS do payload
// em vez de uma varredura de todos os números do JSON. Com o Kit, aquela varredura
// autorizava data, percentual de desconto, duração e quantidade como se fossem preço.
//
// O CONTRATO DE CLARIFY DO ROUTER É PRESERVADO. `rota = null` com `precisa_esclarecer`
// vem acompanhado das `candidatas`, e elas chegam ao Agent para que ele faça UMA
// pergunta que as separe. `rota_aplicada` continua null, nenhum Kit é carregado e
// NENHUMA audiência nova é gravada: o classificador do prompt legado não é promovido a
// rota canônica nem a estado novo.
//
// O GATE RODA PARA TODA ROTA CANÔNICA, não só para as desta lane. Perguntar capacidade
// e executar são coisas diferentes: `mind_rota_capacidade` é consultado sempre que o
// Router decide, para que `needs_human` venha do contrato; Kit e playbook comercial só
// são carregados em `summit_b2c`/`summit_b2b`.
//
// v1.3.0 — ÁUDIO É MENSAGEM, NÃO ANEXO À PARTE. A Treble transcreve o áudio dentro de
// uma sessão em andamento e entrega o texto em `mensagem`, com o arquivo em
// `mensagem_file_url`. Até a v1.2.0 só o texto era lido: o arquivo era descartado aqui e
// reaparecia depois pelo session.close como uma SEGUNDA linha. Agora o turno é UMA
// mensagem — `conteudo` é a transcrição e `blocos` guarda o original.
//
// E O FALLBACK VIROU RISCO. Quando `mensagem` vinha vazia, o código varria
// user_session_keys e adotava a última chave qualquer como fala do lead — uma URL de
// mídia passava, e um texto de um turno anterior também. Agora, havendo arquivo, o
// fallback genérico não roda: sem transcrição confiável, o arquivo é preservado e o turno
// para. A URL nunca vira fala do lead e a IA nunca é chamada fingindo ter entendido.
//
// E-MAIL CITADO NÃO É IDENTIDADE. Até a v1.0.0 qualquer e-mail achado por regex
// na mensagem virava candidato a identificador — "manda também pra minha colega
// ana@empresa.com" ligava a colega à conversa. Agora só `email_informado` ("o
// lead disse que este e-mail é dele") vira candidato, e ele passa pela porta
// única (mind_identidade_resolver, ancorado na conversa).
//
// Como o e-mail nunca sai daqui em texto claro para a OpenAI, ele viaja
// MASCARADO com um rótulo estável ([email_1], [email_2]...): o modelo diz QUAL
// rótulo é o do próprio lead e nós resolvemos o valor deste lado. A semântica
// é do modelo; a regex só extrai e valida.
//
// ORDEM QUE IMPORTA: a fala do lead é persistida na PRIMEIRA chamada, antes de
// contexto, IA, guardrail ou resposta. Se qualquer etapa adiante falhar — e a
// mais provável é a OpenAI — o que a pessoa disse continua registrado.
//
// Identidade deixou de ser formulário. Regra: USE O QUE JÁ SABEMOS ANTES DE
// PERGUNTAR. Guardrails de venda seguem intactos.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";
import { precoInventado, precosOficiais } from "./guardrail-preco.ts";

const VERSION = "1.5.2";
const DEFAULT_MODEL = "gpt-5.4-mini";

// O canal deste runtime no vocabulário do Capability Gate. `whatsapp` é o
// treble-inbound-agent; não há alias.
const CANAL = "whatsapp";

// As rotas canônicas que ESTE runtime executa. Fora delas o turno encerra com
// transferência — a rota decidida ainda é registrada, para quem vier depois.
const ROTAS_DO_VENDEDOR = new Set(["summit_b2c", "summit_b2b"]);

// `audience` é chave pública do payload do Treble e estado persistido em
// engagement.conversas. No caminho canônico ela não é uma segunda decisão: é o nome
// legado da rota que o Router já escolheu.
const AUDIENCE_DA_ROTA: Record<string, string> = {
  summit_b2c: "b2c",
  summit_b2b: "b2b",
};

// Orçamento do Router. Estourar não tem mais para onde cair: o turno encerra com
// transferência, e o motivo sai como `router_timeout`. Ajustável por
// `treble.config.router_timeout_ms`.
const ROUTER_TIMEOUT_MS = 6000;

// Transferência. É a MESMA copy já aprovada no caminho de erro deste runtime: não se
// inventa mensagem para o lead aqui. Quando a rota decidida não é atendida por este
// canal, a frase certa é de produto e cabe à Adriana escrevê-la.
const RESPOSTA_HANDOFF =
  "Tive um probleminha técnico aqui 😅 Já vou te conectar com alguém do nosso time!";

const PROMPT_FALLBACK = `Você atende o WhatsApp oficial do Mind Summit 2026.
Use somente os dados oficiais recebidos no JSON; nunca invente preço, palestrante ou política.
Se faltar informação, diga que vai confirmar com o time e acione needs_human=true.
Responda em português do Brasil, curto e caloroso, uma pergunta por mensagem.`;

const RESPONSE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    answer: {
      type: "string", minLength: 1, maxLength: 2000,
      // O teto existe so como sanidade — o WhatsApp aceita ~4.000 e o limite de
      // verdade e de conduta, nao de contagem. Com 700 o proprio schema cortava a
      // frase quando o playbook pedia as tres experiencias com preco, parcela e
      // proposta de valor: nao cabia, e a mensagem chegava partida.
      description: "A mensagem para o lead, em portugues do Brasil. WhatsApp: curta, direta, sem enrolacao — diga o necessario e pare. Escreva sempre frases inteiras e termine a mensagem; nunca interrompa no meio de uma palavra ou de um item de lista. Se o assunto nao couber de forma breve, corte o escopo do que voce diz, nao a frase.",
    },
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
    // O que o lead informou SOBRE SI NESTE TURNO. Só o que ele disse com todas
    // as letras. Nome NUNCA identifica sozinho: quem decide identidade é o core.
    nome_informado: {
      type: ["string", "null"], maxLength: 120,
      description: "O nome que o lead disse sobre si mesmo NESTE turno, transcrito INTEIRO e exatamente como ele escreveu — nome e sobrenome juntos quando ele deu os dois (\"Sou a Renata Vasconcelos\" => \"Renata Vasconcelos\"; \"me chamo Bia\" => \"Bia\"). Nunca encurte, nunca corrija a grafia, nunca complete com o nome que veio do WhatsApp. Nome de outra pessoa (chefe, colega, quem vai usar o ingresso) não entra aqui. null se ele não disse o nome dele neste turno.",
    },
    email_informado: {
      type: ["string", "null"], maxLength: 200,
      description: "Os e-mails da mensagem chegam MASCARADOS como [email_1], [email_2]... Devolva EXATAMENTE o rótulo (ex.: \"[email_2]\") daquele que o lead disse ser O E-MAIL DELE PRÓPRIO. Se ele pedir para enviar para a colega, o chefe, o financeiro ou qualquer terceiro, esse e-mail NÃO é dele: devolva null. null também se não houver e-mail no turno. Nunca escreva um e-mail por extenso aqui.",
    },
    empresa_informada: {
      type: ["string", "null"], maxLength: 160,
      description: "A empresa onde o lead trabalha, se ele disse NESTE turno. Só o nome da empresa dele — não a empresa de um terceiro, nem o nome de um evento ou produto. null se não disse.",
    },
    cargo_informado: {
      type: ["string", "null"], maxLength: 120,
      description: "O cargo do lead, se ele disse NESTE turno (\"sou head de RH\", \"trabalho como gerente\"). null se não disse.",
    },
  },
  required: [
    "answer", "audience", "intent", "ticket_interest", "objection",
    "needs_human", "checkout_sent", "stage", "desfecho",
    "nome_informado", "email_informado", "empresa_informada", "cargo_informado",
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

// O e-mail nunca sai daqui em texto claro para a OpenAI, mas o modelo precisa
// conseguir DIZER QUAL deles é o do próprio lead. Então cada e-mail vira um
// rótulo estável ([email_1], [email_2]...) e a lista fica só do lado de cá:
// o modelo estabelece a semântica, e nós resolvemos o valor.
function mascarar(value: string): { texto: string; emails: string[] } {
  const emails: string[] = [];
  const texto = value
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, (m) => {
      emails.push(m);
      return `[email_${emails.length}]`;
    })
    .replace(/(?:\+?\d[\d\s().-]{9,}\d)/g, "[telefone omitido]");
  return { texto, emails };
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

// O arquivo que veio junto com a mensagem. A Treble entrega em `mensagem_file_url`,
// ao lado da transcrição em `mensagem` — mesma família, mesmo turno.
const MIDIA_KEYS = ["mensagem_file_url", "file_url", "media_url"];
const CHAVE_MIDIA_RE = /(file|url|link|midia|media|audio|imagem|image|foto|document|video)/i;
const AUDIO_EXT_RE = /\.(ogg|opus|mp3|m4a|aac|amr|wav)$/i;

function ehUrl(v: string) {
  return /:\/\//.test(v);
}
function ehAudioUrl(v: string) {
  if (!ehUrl(v)) return false;
  try {
    return AUDIO_EXT_RE.test(new URL(v).pathname);
  } catch {
    return false;
  }
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

// Só valida/extrai o valor DEPOIS que a semântica "é o meu e-mail" já foi
// estabelecida pelo modelo. Nunca para varrer a mensagem atrás de identidade.
const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/;

// ROTA — quem decide é a Edge Function `router` (Passo 10), e só ela. Aqui não há
// heurística, lista de palavra-chave nem fallback que escolha rota: ou o Router
// responde, ou não há rota — e sem rota o turno encerra com transferência.
//
// `rota = null` é resposta legítima do Router (ambiguidade real, ou conversa sem fala
// do lead). Não é erro e não vira rota inventada deste lado.
//
// O CONTRATO DE CLARIFY VEM JUNTO. Quando o Router devolve `rota = null` com
// `precisa_esclarecer = true`, ele também devolve as `candidatas` — e essa lista é a
// resposta dele, não ruído. Descartá-la aqui empurraria o turno para o classificador
// legado do prompt exatamente quando o Router disse "ainda não decidi", criando uma
// segunda autoridade de roteamento no único momento em que ela é mais perigosa.
async function decidirRota(
  baseUrl: string,
  serviceKey: string,
  token: string,
  conversaId: string,
  timeoutMs: number,
): Promise<{ rota: string | null; precisaEsclarecer: boolean; candidatas: string[]; falha: string | null }> {
  const VAZIO = (falha: string) => ({ rota: null, precisaEsclarecer: false, candidatas: [], falha });
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
      // O canal vai EXPLICITO. O Router filtra as competencias possiveis por ele
      // antes de decidir, entao ele nao pode devolver uma rota que este canal nao
      // serve. `CANAL` e a constante deste runtime — nunca inferida da conversa.
      body: JSON.stringify({ conversa_id: conversaId, canal: CANAL }),
      signal: controller.signal,
    });
    if (!r.ok) return VAZIO(`router_http_${r.status}`);
    const saida = await r.json() as Record<string, unknown>;
    if (saida?.ok !== true) return VAZIO(String(saida?.motivo ?? saida?.error ?? "router_nao_ok"));
    return {
      rota: typeof saida.rota === "string" ? saida.rota : null,
      precisaEsclarecer: saida.precisa_esclarecer === true,
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

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const startedAt = Date.now();
  const url = new URL(req.url);

  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

  if (req.method === "GET" && url.pathname.endsWith("/health")) {
    return json(200, { ok: true, service: "treble-inbound-agent", version: VERSION });
  }
  if (req.method !== "POST") return json(405, { ok: false, error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(
    supabaseUrl,
    serviceKey,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Duas configs, uma ida: a do canal e a do Core. O token do Router mora em
  // `intelligence.config` e é lido pelo mesmo carregador que a própria Edge do Router
  // usa — não se duplica segredo em `treble.config`.
  const [{ data: cfg, error: cfgError }, { data: cfgCore }] = await Promise.all([
    supabase.rpc("treble_agent_config"),
    supabase.rpc("analise_config"),
  ]);
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
  const fileUrl = pick(body, MIDIA_KEYS).slice(0, 500);
  const idExterno = pick(body, ["message_id", "messageId", "external_message_id", "client_message_id"]).slice(0, 160);
  const contactName = pick(body, ["name", "nome", "user_name", "first_name", "hubspot_firstname"]);
  const whatsapp = pick(body, ["cellphone", "celular", "phone", "whatsapp"]);
  const origem = pick(body, ["origem", "origem_codigo", "origin", "botao", "utm_content", "entry_point"]).slice(0, 60);
  let utmToken = pick(body, ["utm_token", "ref", "token_utm"]).slice(0, 8);

  const CONTROLE = new Set([
    "needs_human", "intent", "audience", "checkout_sent", "resposta_ia",
    "country_code", "cellphone", "session_id", "conversation_id", "hubspot_firstname",
    "origem", "origem_codigo", "utm_content", "utm_token", "ref",
    ...MIDIA_KEYS,
  ]);
  const pareceIdentificador = (v: string) =>
    /^[A-Z]{2,6}[_-]?\d{6,}$/i.test(v) || /^\+?\d[\d\s()-]{6,}$/.test(v) ||
    /^[0-9a-f]{16,}$/i.test(v);

  // Fallback para fluxos que entregam a fala do lead numa chave que não conhecemos.
  // Duas travas: nunca aceita uma URL nem uma chave de mídia como fala; e não roda
  // quando veio arquivo — aí uma chave solta é quase sempre sobra do turno anterior,
  // e adotá-la significa responder a mensagem errada.
  if (!message && !fileUrl && Array.isArray(body.user_session_keys)) {
    const candidatos = (body.user_session_keys as Array<Record<string, unknown>>)
      .filter((e) => typeof e?.value === "string" && String(e.value).trim().length > 1 &&
                     !CONTROLE.has(String(e?.key ?? "")) &&
                     !CHAVE_MIDIA_RE.test(String(e?.key ?? "")) &&
                     !ehUrl(String(e.value).trim()) &&
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
  // Uma URL nunca é a fala da pessoa, venha de onde vier.
  if (message && ehUrl(message)) {
    console.warn(JSON.stringify({ request_id: requestId, event: "mensagem_descartada_url" }));
    message = "";
  }

  const audioUrl = fileUrl && ehAudioUrl(fileUrl) ? fileUrl : "";

  // ÁUDIO SEM TRANSCRIÇÃO. A Treble transcreve o áudio dentro de uma sessão em andamento;
  // quando ela não entrega texto, nós não sabemos o que a pessoa disse. O arquivo é
  // preservado e o turno para aqui: a IA não é chamada e nenhuma resposta é devolvida —
  // não há `resposta_ia`, então o fluxo não tem nada novo para enviar.
  if (!message && audioUrl && sessionId) {
    const telHashA = whatsapp ? await sha256(whatsapp) : null;
    const { data: convA, error: errA } = await supabase.rpc("treble_agent_start", {
      p_session_external_id: sessionId,
      p_contact: { nome: contactName || null, whatsapp: whatsapp || null, telefone_hash: telHashA },
      p_origem: origem || null,
      p_utm_token: utmToken || null,
      p_mensagem: {
        papel: "lead", conteudo: null,
        blocos: { tipo: "audio", url: audioUrl },
        id_externo: idExterno || null,
      },
    });
    console.warn(JSON.stringify({
      request_id: requestId, event: "audio_sem_transcricao",
      conversa: convA?.conversation_id ?? null,
      persistido: Boolean(convA) && !errA,
      detalhe: errA?.message,
    }));
    return json(200, {
      ok: false, error: "audio_sem_transcricao",
      persistido: Boolean(convA) && !errA, request_id: requestId,
    });
  }

  if (!sessionId || !message) {
    console.warn(JSON.stringify({
      request_id: requestId, event: "payload_nao_reconhecido",
      campos: Object.keys(body ?? {}),
      session_keys: Array.isArray(body.user_session_keys)
        ? (body.user_session_keys as Array<Record<string, unknown>>).map((e) => String(e?.key ?? ""))
        : null,
      tem_session: Boolean(sessionId), tem_mensagem: Boolean(message),
      tem_arquivo: Boolean(fileUrl), arquivo_e_audio: Boolean(audioUrl),
    }));
    return json(422, { ok: false, error: "faltam_campos", detalhe: "esperado identificador de sessão e mensagem do lead" });
  }

  const openAiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!openAiKey) return json(503, { ok: false, error: "ia_nao_configurada" });
  const model = (typeof cfg.openai_model === "string" && cfg.openai_model) ||
    Deno.env.get("OPENAI_MODEL") || DEFAULT_MODEL;
  const timeoutMs = Number(cfg.timeout_ms) > 0 ? Number(cfg.timeout_ms) : 8500;
  const routerTimeoutMs = Number(cfg.router_timeout_ms) > 0 ? Number(cfg.router_timeout_ms) : ROUTER_TIMEOUT_MS;

  // O token do Router. Sem ele o Core não decide rota — e não existe mais um segundo
  // caminho para onde cair: o turno encerra de forma controlada.
  const routerToken = typeof cfgCore?.analise_token === "string" ? cfgCore.analise_token : "";

  // ============================================================ INGESTÃO
  const telefoneHash = whatsapp ? await sha256(whatsapp) : null;
  const { data: conv, error: convError } = await supabase.rpc("treble_agent_start", {
    p_session_external_id: sessionId,
    p_contact: { nome: contactName || null, whatsapp: whatsapp || null, telefone_hash: telefoneHash },
    p_origem: origem || null,
    p_utm_token: utmToken || null,
    // UMA mensagem por turno: a transcrição é o conteúdo, o arquivo vive em blocos.
    // Sem áudio, a chave `blocos` nem existe — mensagem de texto continua como antes.
    p_mensagem: {
      papel: "lead", conteudo: message, id_externo: idExterno || null,
      ...(audioUrl ? { blocos: { tipo: "audio", url: audioUrl } } : {}),
    },
  });
  if (convError || !conv) {
    console.error(JSON.stringify({ request_id: requestId, event: "ingestao_falhou", detalhe: convError?.message }));
    return json(200, {
      ok: false,
      user_session_keys: [
        { key: "resposta_ia", value: "Tive um probleminha técnico aqui 😅 Já vou te conectar com alguém do nosso time!" },
        { key: "needs_human", value: "true" },
      ],
    });
  }

  console.info(JSON.stringify({
    request_id: requestId, event: "mensagem_persistida",
    conversa: conv.conversation_id, mensagem: conv.mensagem_id,
    duplicada: conv.mensagem_duplicada === true,
    pessoa_criada: conv.pessoa_criada === true,
    conflito: conv.conflito_identidade != null,
    audio: Boolean(audioUrl),
  }));

  try {
    let idConhecida = conv.pessoa_encontrada === true;
    let idPessoa: string | null = (conv.participante_id ?? null) as string | null;
    let idPerfil = (conv.perfil ?? null) as Record<string, unknown> | null;

    // NÃO existe mais busca de identidade por regex antes do turno.

    // Baratas, independentes da rota e capazes de encerrar o turno: a deduplicação vem
    // antes de qualquer ida ao modelo — inclusive a do Router.
    const [{ data: jaRespondida }, { data: agenda }] = await Promise.all([
      supabase.rpc("treble_agent_resposta_repetida", {
        p_conversation_id: conv.conversation_id,
        p_mensagem: message,
        p_janela_segundos: 90,
      }),
      cfg.bloco_agenda_busca === "true"
        ? supabase.rpc("mindagent_chat_search", {
            p_event_slug: "mind-summit-2026",
            p_query: message.slice(0, 300),
            p_limit: 8,
          })
        : Promise.resolve({ data: null, error: null }),
    ]);
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

    // ====================================================== ROUTER → GATE → KIT
    // A necessidade atual é a fala deste turno; ela já está persistida, e é dela que o
    // Router parte. `rotaDecidida` é o que o Core disse; `rotaAplicada` é o que este
    // runtime conseguiu executar — as duas podem divergir, e a diferença é registrada.
    let rotaDecidida: string | null = null;
    let rotaAplicada: string | null = null;
    let precisaEsclarecer = false;
    let candidatas: string[] = [];
    let falhaDaRota: string | null = null;
    let gateReason: string | null = null;
    let needsHumanDoGate = false;
    let dadosOficiais: unknown = null;
    let instructions = PROMPT_FALLBACK;

    // Quanto o Router custa neste caminho é a pergunta em aberto do Passo 6B (§8/§10 do
    // Core): dois turnos observados mostram que a Treble entregou um de ~4,43 s e não
    // emitiu um de ~5,96 s. Medir aqui é o que transforma isso em número em vez de
    // suposição — por isso `router_ms` sai no log de todo turno.
    let routerMs: number | null = null;
    if (routerToken) {
      const antes = Date.now();
      const decisao = await decidirRota(
        supabaseUrl, serviceKey, routerToken, String(conv.conversation_id), routerTimeoutMs,
      );
      routerMs = Date.now() - antes;
      rotaDecidida = decisao.rota;
      precisaEsclarecer = decisao.precisaEsclarecer;
      candidatas = decisao.candidatas;
      falhaDaRota = decisao.falha;
    }

    if (rotaDecidida) {
      // O GATE RODA PARA QUALQUER ROTA CANÔNICA que o Router decidir, não só para as
      // desta lane. O caminho declarado é Router → Gate: se o Router disser
      // `cliente_suporte` e o Gate não for consultado, `needs_human` volta a depender
      // da leitura do modelo, e o handoff passa a ser sorte em vez de contrato.
      //
      // O que é exclusivo da lane é EXECUTAR: Kit e playbook comercial só são
      // carregados para `summit_b2c`/`summit_b2b`. Capacidade se pergunta sempre;
      // execução só onde este runtime é dono.
      const ehDoVendedor = ROTAS_DO_VENDEDOR.has(rotaDecidida);
      const vazio = Promise.resolve({ data: null, error: null });
      const [{ data: gate }, kitR, playbookR] = await Promise.all([
        supabase.rpc("mind_rota_capacidade", { p_rota: rotaDecidida, p_canal: CANAL }),
        ehDoVendedor
          ? supabase.rpc("mind_agent_kit", {
            p_rota: rotaDecidida,
            p_conversa_id: conv.conversation_id,
            p_necessidade: { texto: message },
          })
          : vazio,
        ehDoVendedor
          ? supabase.rpc("treble_agent_prompt", { p_audience: rotaDecidida })
          : vazio,
      ]);
      const kit = kitR.data;
      const playbookDaRota = playbookR.data;

      gateReason = typeof gate?.reason === "string" ? gate.reason : null;
      needsHumanDoGate = gate?.needs_human === true;

      const kitServe = ehDoVendedor &&
        gate?.pode_executar === true &&
        kit && kit.ok !== false &&
        kit.meta?.kit_disponivel === true &&
        kit.structured && Object.keys(kit.structured as Record<string, unknown>).length > 0 &&
        typeof playbookDaRota === "string" && playbookDaRota.trim().length > 0;

      if (kitServe) {
        rotaAplicada = rotaDecidida;
        dadosOficiais = kit.structured;
        instructions = playbookDaRota as string;
      } else {
        // O Core não serve este turno. Desde a v1.5.0 não há piso para onde cair: o
        // turno encerra com transferência logo abaixo. Quem decide `needs_human` é o
        // Gate, e só ele — `needsHumanDoGate` já carrega a resposta, para qualquer rota.
        //
        // Três motivos distintos caem aqui, e o registro os separa em `rota_falha`:
        //   rota_de_outra_lane  a rota é canônica e o Gate já respondeu, mas executá-la
        //                       não é desta lane;
        //   gate fechado        condição estável (missing_playbook, missing_kit,
        //                       canal_incompativel): a rota não executa aqui, e isso é
        //                       necessidade humana de fato;
        //   kit_indisponivel    Gate aberto e Kit que não veio — falha passageira de
        //                       leitura. Antes isto caía no piso factual do legado sem
        //                       acender handoff; agora transfere, porque responder com
        //                       dado velho deixou de ser uma opção deste runtime.
        falhaDaRota = falhaDaRota ??
          (!ehDoVendedor ? "rota_de_outra_lane" : gateReason ?? "kit_indisponivel");
      }
    }

    // NÃO EXISTE SEGUNDA INTELIGÊNCIA. Quando o Core não serve o turno, este runtime
    // não improvisa com dado antigo nem com prompt genérico: encerra de forma
    // controlada. A fala da pessoa já está persistida desde a ingestão — o que se
    // perde é a resposta, nunca o registro.
    //
    // O CLARIFY NÃO É QUEDA. `rota = null` com candidatas é o Router dizendo "ainda não
    // dá para saber ENTRE ESTAS", e a resposta certa é uma pergunta. O turno segue sem
    // Kit e sem DADOS_OFICIAIS — e, por isso, sem poder falar de preço: o guardrail
    // barra qualquer valor quando o payload oficial está vazio.
    const ehClarify = precisaEsclarecer && candidatas.length > 0;
    if (!rotaAplicada && !ehClarify) {
      const motivo = falhaDaRota ?? (routerToken ? "rota_indefinida" : "router_sem_token");
      const audienceSem = rotaDecidida
        ? (AUDIENCE_DA_ROTA[rotaDecidida] ?? (conv.audience ?? "desconhecido"))
        : (conv.audience ?? "desconhecido");
      console.warn(JSON.stringify({
        request_id: requestId, event: "turno_sem_execucao",
        rota: rotaDecidida, gate_reason: gateReason, motivo, router_ms: routerMs,
      }));
      const { error: errSem } = await supabase.rpc("mind_turno_registrar", {
        p_conversa_id: conv.conversation_id,
        p_resposta: RESPOSTA_HANDOFF,
        p_estado: { audience: audienceSem, needs_human: true, stage: conv.stage ?? null },
        p_meta: {
          request_id: requestId, version: VERSION,
          rota: rotaDecidida, rota_aplicada: null,
          precisa_esclarecer: precisaEsclarecer, candidatas,
          gate_reason: gateReason, rota_falha: motivo, router_ms: routerMs,
        },
      });
      if (errSem) {
        console.error(JSON.stringify({ request_id: requestId, event: "save_falhou", detalhe: errSem.message }));
      }
      return json(200, {
        ok: true, sem_execucao: true, motivo,
        user_session_keys: [
          { key: "resposta_ia", value: RESPOSTA_HANDOFF },
          { key: "needs_human", value: "true" },
        ],
        request_id: requestId,
      });
    }

    console.info(JSON.stringify({
      request_id: requestId, event: "rota_do_turno",
      rota: rotaDecidida, rota_aplicada: rotaAplicada,
      precisa_esclarecer: precisaEsclarecer, candidatas: candidatas.length,
      gate_reason: gateReason, falha: falhaDaRota, router_ms: routerMs,
    }));

    const historico = Array.isArray(conv.historico) ? conv.historico : [];
    const agendaSegura = agenda && typeof agenda === "object"
      ? Object.fromEntries(Object.entries(agenda as Record<string, unknown>)
          .filter(([k]) => ["sessions", "speakers", "locations", "exhibitors", "mind"].includes(k)))
      : {};

    const mascarado = mascarar(message);

    const aiInput = {
      DADOS_OFICIAIS: dadosOficiais,
      AGENDA_E_PALESTRANTES: agendaSegura,
      // CLARIFY DO ROUTER. Quando ele devolve `rota = null` com candidatas, a resposta
      // dele é "ainda não dá para saber ENTRE ESTAS" — e é isso que o turno faz: uma
      // pergunta que separe as candidatas. O classificador do prompt legado não vira
      // rota canônica por causa disso; `rota_aplicada` continua null e nada de Kit é
      // carregado. Fora desse caso a chave nem aparece.
      ...((!rotaAplicada && precisaEsclarecer && candidatas.length > 0)
        ? {
          esclarecimento: {
            situacao: "O Core ainda não decidiu qual competência assume esta necessidade.",
            candidatas,
            como_agir: [
              "Faça UMA pergunta curta que separe essas possibilidades, na linguagem da pessoa.",
              "Não escolha por ela e não siga como se já soubesse.",
              "Nunca diga ao lead o nome técnico de uma rota.",
            ].join(" "),
          },
        }
        : {}),
      estado_da_conversa: {
        // A rota é a competência que este turno está executando. Quando ela vem, o
        // playbook dela já está nas instruções — não é para reclassificar.
        rota: rotaAplicada,
        audience: conv.audience,
        stage: conv.stage,
        nome_contato: conv.nome_contato ?? contactName ?? null,
        origem_codigo: conv.origem_codigo ?? origem ?? null,
        utm_de_origem: conv.utm ?? null,
        produto: conv.produto_codigo ?? null,
      },
      // Identidade NÃO é formulário. Nada aqui manda coletar cadastro.
      quem_esta_falando: {
        ja_identificada: idConhecida,
        perfil: idPerfil,
        como_agir: [
          "USE O QUE JÁ SABEMOS ANTES DE PERGUNTAR: nunca peça o que já está em perfil.",
          "Não colete cadastro. Não peça e-mail, sobrenome, empresa ou cargo para 'completar' nada.",
          "Só pergunte um dado se ele for necessário para resolver o que a pessoa quer AGORA.",
          "Se a pessoa contar algo sobre si espontaneamente, aproveite — mas não puxe.",
          "Os e-mails aparecem mascarados como [email_1], [email_2]. Nunca repita o rótulo na resposta ao lead: fale do e-mail em linguagem natural ('o e-mail que você passou').",
        ].join(" "),
      },
      historico,
      mensagem_do_lead: mascarado.texto,
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
          // Orcamento de TOKENS, nao de caracteres: precisa caber a `answer` (ate
          // 2.000 chars ~ 700 tokens em portugues) mais os outros doze campos do
          // JSON estruturado. Com 700 no total, uma resposta longa esgotava o
          // orcamento antes de fechar o objeto.
          max_output_tokens: 1500,
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
      empresa_informada: string | null; cargo_informado: string | null;
    };
    // NUNCA cortar por caractere. Ate a v1.5.0 esta linha terminava em
    // `.slice(0, 700)`, e um turno real chegou ao WhatsApp com exatamente 700
    // caracteres, partido no meio de "Mind". Mensagem completa vale mais que
    // frase mutilada: a brevidade e comportamento do prompt, nao tesoura aqui.
    const answer = String(turn.answer ?? "").trim();
    if (!answer) throw new Error("resposta_vazia");

    // A rota manda no `audience`.
    //
    //   rota executada  → derivado dela;
    //   CLARIFY         → NÃO se grava classificação nova. O Router disse "não decidi";
    //                     deixar o classificador legado escrever `b2c`/`b2b` aqui
    //                     criaria estado que um fallback futuro trataria como decisão.
    //                     Preserva-se o que a conversa já tinha, ou `desconhecido`;
    //   demais casos    → a leitura do modelo, que só chega aqui com Kit aplicado.
    //
    // A chave em si nunca some do payload do Treble.
    const audienceDaConversa = typeof conv.audience === "string" && conv.audience
      ? conv.audience
      : "desconhecido";
    const audienceFinal = rotaAplicada
      ? (AUDIENCE_DA_ROTA[rotaAplicada] ?? turn.audience)
      : precisaEsclarecer
      ? audienceDaConversa
      : turn.audience;

    // `needs_human` é NECESSIDADE, e o Gate é quem sabe que a rota decidida não se
    // conclui sozinha neste runtime — qualquer rota, não só as de venda. Ele soma à
    // leitura do modelo; nunca a subtrai.
    const needsHumanFinal = turn.needs_human === true || needsHumanDoGate;

    // Guardrail de preço: valor em R$ que não veio de um campo monetário dos dados
    // oficiais derruba o turno. A lista de permitidos sai de CAMPOS, nunca de uma
    // varredura do JSON — ver `guardrail-preco.ts` para o porquê.
    const inventado = precoInventado(answer, precosOficiais(dadosOficiais));
    if (inventado) {
      console.error(JSON.stringify({ request_id: requestId, event: "preco_inventado", preco: inventado }));
      return json(200, {
        ok: true, guarded: true,
        user_session_keys: [
          { key: "resposta_ia", value: "Deixa eu confirmar esse valor com o time para não te passar nada errado — já te chamo um consultor! 🙌" },
          { key: "needs_human", value: "true" },
        ],
      });
    }

    // O que o lead contou sobre si — o que ele DISSE, não o que pedimos.
    const nomeDito = (turn.nome_informado ?? "").trim() || null;
    // O modelo devolve o RÓTULO ([email_2]) do e-mail que o lead disse ser dele.
    // Aqui o rótulo vira valor de novo — a regex só valida o que já tem a
    // semântica de "é o meu e-mail" estabelecida pelo modelo.
    const rotuloEmail = (turn.email_informado ?? "").trim().match(/^\[?email_(\d+)\]?$/i);
    const emailDito = rotuloEmail
      ? (mascarado.emails[Number(rotuloEmail[1]) - 1] ?? "").match(EMAIL_RE)?.[0] ?? null
      : null;
    const empresaDita = (turn.empresa_informada ?? "").trim() || null;
    const cargoDito = (turn.cargo_informado ?? "").trim() || null;

    // PORTA ÚNICA DE IDENTIDADE. O e-mail que o lead disse ser dele passa pelo
    // resolvedor universal, ancorado na conversa: se for compatível, anexa à
    // mesma pessoa; se apontar para outra, vira conflito pendente. Nenhum
    // identificador é movido, e a conversa nunca troca de pessoa.
    if (emailDito) {
      const { data: ident, error: identError } = await supabase.rpc("treble_agent_identificar", {
        p_session_external_id: sessionId,
        p_email: emailDito,
        p_nome: nomeDito ?? contactName ?? conv.nome_contato ?? null,
        p_sobrenome: null,
        p_mesma_pessoa: null,
      });
      if (identError) {
        console.error(JSON.stringify({ request_id: requestId, event: "identificar_falhou", detalhe: identError.message }));
      } else if (ident?.precisa_fundir) {
        console.warn(JSON.stringify({ request_id: requestId, event: "identidade_em_conflito" }));
      } else if (ident?.pessoa_encontrada) {
        idConhecida = true;
        idPessoa = (ident.pessoa_id ?? idPessoa) as string | null;
        idPerfil = (ident.perfil ?? idPerfil) as Record<string, unknown> | null;
      }
    }

    // Perfil, não identidade: sobrenome, empresa e cargo. Preenche só o que
    // está vazio e nunca sobrescreve. E-mail não passa por aqui.
    if (idPessoa && (empresaDita || cargoDito || nomeDito)) {
      const sobrenomeDito = nomeDito && nomeDito.includes(" ")
        ? nomeDito.slice(nomeDito.indexOf(" ") + 1).trim() || null
        : null;
      const { error: errC } = await supabase.rpc("mind_pessoa_completar", {
        p_pessoa_id: idPessoa,
        p_sobrenome: sobrenomeDito,
        p_empresa: empresaDita,
        p_cargo: cargoDito,
      });
      if (errC) console.error(JSON.stringify({ request_id: requestId, event: "completar_falhou", detalhe: errC.message }));
    }

    // A CHAMADA A `mind_lead_capturar` FOI REMOVIDA AQUI (30/08/2026).
    //
    // Ela nunca funcionou: a função não existe em nenhum schema do banco, e o erro era
    // engolido com `console.error({event:"lead_capturar_falhou"})` a cada turno com
    // pessoa. A investigação da #42 (Lane D, dona do write-back) fechou que se trata de
    // chamada morta, não de função faltante — todo o payload que ela carregava já tem
    // casa canônica NO MESMO TURNO:
    //
    //   pessoa · referência · agente   →  engagement.conversas (participante_id,
    //                                     session_external_id, agente)
    //   origem · utm · produto         →  engagement.conversas
    //   audience · stage               →  engagement.conversas, por mind_turno_registrar
    //   intent · ticket_interest ·     →  engagement.conversas.variables, idem
    //   objection · desfecho ·
    //   needs_human
    //   rota                           →  engagement.mensagens.blocos, no meta do turno
    //
    // Criar a RPC duplicaria estado, e `crm.registrar_lead` não é substituto compatível
    // (outra assinatura, outro schema, e quebrada). Por isso a chamada sai sem nenhum
    // writer no lugar. Quando o Passo 15B construir o write-back de verdade, ele nasce
    // da casa canônica — não daqui.

    const state = {
      audience: audienceFinal,
      intent: turn.intent,
      ticket_interest: turn.ticket_interest,
      objection: turn.objection,
      needs_human: needsHumanFinal,
      checkout_sent: turn.checkout_sent,
      stage: turn.stage,
      desfecho: turn.desfecho,
    };
    // Só a resposta do agente: a fala do lead já foi persistida na ingestão.
    const { error: saveError } = await supabase.rpc("mind_turno_registrar", {
      p_conversa_id: conv.conversation_id,
      p_resposta: answer,
      p_estado: state,
      // A rota do turno fica registrada em `blocos` da mensagem do agente — nenhuma
      // coluna nova, nenhuma segunda casa. `request_id` continua sendo a chave de
      // idempotência que mind_turno_registrar lê daqui.
      p_meta: {
        model, request_id: requestId, version: VERSION,
        rota: rotaDecidida, rota_aplicada: rotaAplicada,
        precisa_esclarecer: precisaEsclarecer, candidatas,
        gate_reason: gateReason, rota_falha: falhaDaRota, router_ms: routerMs,
      },
    });
    if (saveError) console.error(JSON.stringify({ request_id: requestId, event: "save_falhou", detalhe: saveError.message }));

    console.info(JSON.stringify({
      request_id: requestId, status: 200, session: sessionId.slice(0, 8),
      rota: rotaAplicada, audience: audienceFinal, intent: turn.intent,
      needs_human: needsHumanFinal, gate_reason: gateReason,
      desfecho: turn.desfecho, identificada: idConhecida,
      email_proprio: emailDito != null,
      chars_resposta: answer.length,
      duration_ms: Date.now() - startedAt,
    }));

    return json(200, {
      ok: true,
      user_session_keys: [
        { key: "resposta_ia", value: answer },
        { key: "needs_human", value: String(needsHumanFinal) },
        { key: "intent", value: turn.intent },
        { key: "audience", value: audienceFinal },
        { key: "checkout_sent", value: String(turn.checkout_sent) },
      ],
      state,
      request_id: requestId,
    });
  } catch (error) {
    // A mensagem do lead JÁ ESTÁ GRAVADA neste ponto — a ingestão aconteceu
    // antes deste try. Falha aqui custa a resposta, não o registro.
    const isTimeout = error instanceof DOMException && error.name === "AbortError";
    console.error(JSON.stringify({
      request_id: requestId, status: isTimeout ? 504 : 500,
      conversa: conv?.conversation_id ?? null,
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
