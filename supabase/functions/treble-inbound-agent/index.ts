// Cérebro do agente inbound de vendas do Mind no WhatsApp.
//
// v1.10.1 — VENDA B2C SEM ATRITO. O canal comercial parte de B2C, preserva B2B
// apenas quando existe intenção corporativa explícita e não usa cargo/empresa como
// atalho de rota. A rota comercial rápida evita uma chamada ao Router na maioria dos
// turnos. Cadastro pode enriquecer o CRM, mas nunca bloqueia resposta, condição ou
// checkout.
//
// v1.8.0 — CORE AGÊNTICO COMPARTILHADO + CREDENCIAMENTO. O Treble recebe dados
// person-bound de participante e ingresso pelo Core e consome o mesmo bundle do Kit,
// as mesmas ferramentas de Intelligence e a mesma política de raciocínio do App.
// B2B e B2C ampliam a lupa sob demanda sem receber o catálogo inteiro. Nas duas rotas
// de venda, o contato mínimo é completado no início e antes de calculadora ou checkout.
//
// v1.6.2 — CHECKOUT OFICIAL SOBREVIVE AO GUARDRAIL DE PREÇO. Se o modelo
// selecionou um carrinho que veio do Kit, mas escreveu um preço inconsistente,
// o runtime remove toda a copy livre, envia apenas uma frase sem preço + o link
// oficial rastreado e registra o checkout. Sem checkout oficial, o fail-closed e
// o handoff continuam intactos.
//
// v1.6.1 — IDENTIDADE COMERCIAL PROGRESSIVA. As rotas summit_b2b e summit_b2c
// completam somente os dados ausentes de nome, empresa, cargo, e-mail e WhatsApp.
//
// v1.6.0 — CHECKOUT ATRIBUIDO AO ENVIO. O modelo aponta o checkout_url exato
// recebido no Kit; o runtime valida que ele é oficial, gera um evento opaco e
// devolve a URL com canal, motivo e token. A venda pode então voltar da Eduzz
// para a conversa e para este Agent sem PII na URL.
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
import { decidirGuardrailPreco, precosOficiais } from "./guardrail-preco.ts";
import {
  checkoutCurto,
  checkoutRastreado,
  escolherCheckoutOficial,
  idEventoCheckout,
  inserirCheckoutNaResposta,
} from "../_shared/checkout-attribution.ts";
import { rotaComercialRapida } from "../_shared/treble-commercial-route.ts";
import {
  executarChamadas,
  esforcoDeRaciocinio,
  extrairChamadas,
  MAX_RODADAS_TOOL,
  ORCAMENTO_TURNO_MS,
  produtoDoContexto,
  toolsDeIntelligence,
} from "../_shared/agent-intelligence.ts";

const VERSION = "1.10.1";
const DEFAULT_MODEL = "gpt-5.4";

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
    checkout_url: {
      type: ["string", "null"],
      maxLength: 1200,
      description: "Quando enviar checkout, copie EXATAMENTE um checkout_url recebido nos dados oficiais. null quando não enviar. Nunca construa, corrija ou complete uma URL.",
    },
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
    whatsapp_informado: {
      type: ["string", "null"], maxLength: 40,
      description: "Os números de WhatsApp da mensagem chegam MASCARADOS como [whatsapp_1], [whatsapp_2]... Devolva EXATAMENTE o rótulo do WhatsApp que o lead disse ser DELE PRÓPRIO. WhatsApp de colega, chefe ou terceiro retorna null. null também se não houver WhatsApp próprio no turno.",
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
    "needs_human", "checkout_sent", "checkout_url", "stage", "desfecho",
    "nome_informado", "email_informado", "whatsapp_informado",
    "empresa_informada", "cargo_informado",
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

// FALHA DE RUNTIME NÃO PODE VIRAR SILÊNCIO.
//
// O `catch` do fim do turno já resolvia isto: devolve 200 com uma fala de desculpa e
// `needs_human`, e a Treble transfere. Mas os `return` de falha que acontecem ANTES
// dele saíam com HTTP puro e sem `user_session_keys` — quem estava do outro lado só
// recebia alguma coisa se o fluxo tratasse não-2xx, e isso não é garantia deste lado.
//
// Esta função é A MESMA SAÍDA DO `catch`, num lugar só: mesma fala, mesmo
// `needs_human`, mesmo status 200. Não há rota nova, estado novo nem decisão nova —
// é a saída que já existia aplicada aos caminhos que escapavam dela.
//
// O diagnóstico não se perde: `error` continua com o código de sempre e
// `status_origem` guarda o HTTP que aquele caminho devolvia, para log e monitoramento
// distinguirem `ia_indisponivel` de `config_indisponivel` como antes.
//
// `unauthorized` de propósito NÃO passa por aqui: token errado é erro de configuração
// da integração, não turno de uma pessoa esperando resposta, e deve continuar alto.
//
// A fala é a `RESPOSTA_HANDOFF` que este runtime já usava — copy aprovada, não se
// inventa mensagem para o lead aqui.
function falhaComTransferencia(
  statusOrigem: number,
  codigo: string,
  extra: Record<string, unknown> = {},
) {
  return json(200, {
    ok: false,
    error: codigo,
    status_origem: statusOrigem,
    ...extra,
    user_session_keys: [
      { key: "resposta_ia", value: RESPOSTA_HANDOFF },
      { key: "needs_human", value: "true" },
    ],
  });
}

// O e-mail nunca sai daqui em texto claro para a OpenAI, mas o modelo precisa
// conseguir DIZER QUAL deles é o do próprio lead. Então cada e-mail vira um
// rótulo estável ([email_1], [email_2]...) e a lista fica só do lado de cá:
// o modelo estabelece a semântica, e nós resolvemos o valor.
function mascarar(value: string): { texto: string; emails: string[]; whatsapps: string[] } {
  const emails: string[] = [];
  const whatsapps: string[] = [];
  const texto = value
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, (m) => {
      emails.push(m);
      return `[email_${emails.length}]`;
    })
    .replace(/(?:\+?\d[\d\s().-]{9,}\d)/g, (m) => {
      whatsapps.push(m);
      return `[whatsapp_${whatsapps.length}]`;
    });
  return { texto, emails, whatsapps };
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
  if (cfgError || !cfg?.webhook_token) return falhaComTransferencia(503, "config_indisponivel");
  if (url.searchParams.get("token") !== cfg.webhook_token) {
    console.warn(JSON.stringify({ request_id: requestId, status: 401 }));
    return json(401, { ok: false, error: "unauthorized" });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return falhaComTransferencia(400, "invalid_json");
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
    return falhaComTransferencia(422, "faltam_campos", {
      detalhe: "esperado identificador de sessão e mensagem do lead",
    });
  }

  const openAiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!openAiKey) return falhaComTransferencia(503, "ia_nao_configurada");
  const model = (typeof cfg.openai_model === "string" && cfg.openai_model) ||
    Deno.env.get("OPENAI_MODEL") || DEFAULT_MODEL;
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
    return falhaComTransferencia(500, "ingestao_falhou");
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
    let toolsDoTurno: unknown = [];
    let produtoDoTurno: string | null = null;

    // Quanto o Router custa neste caminho é a pergunta em aberto do Passo 6B (§8/§10 do
    // Core): dois turnos observados mostram que a Treble entregou um de ~4,43 s e não
    // emitiu um de ~5,96 s. Medir aqui é o que transforma isso em número em vez de
    // suposição — por isso `router_ms` sai no log de todo turno.
    let routerMs: number | null = null;
    let rotaOrigem = "router";
    const rotaRapida = rotaComercialRapida(message, conv.historico);
    if (rotaRapida.rota) {
      rotaDecidida = rotaRapida.rota;
      routerMs = 0;
      rotaOrigem = rotaRapida.motivo;
    } else if (routerToken) {
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
      const [{ data: gate }, kitR] = await Promise.all([
        supabase.rpc("mind_rota_capacidade", { p_rota: rotaDecidida, p_canal: CANAL }),
        ehDoVendedor
          ? supabase.rpc("mind_agent_kit", {
            p_rota: rotaDecidida,
            p_conversa_id: conv.conversation_id,
            p_necessidade: { texto: message, pergunta: message, rota: rotaDecidida, canal: CANAL },
          })
          : vazio,
      ]);
      const kit = kitR.data;

      gateReason = typeof gate?.reason === "string" ? gate.reason : null;
      needsHumanDoGate = gate?.needs_human === true;

      const kitServe = ehDoVendedor &&
        gate?.pode_executar === true &&
        kit && kit.ok !== false &&
        kit.meta?.kit_disponivel === true &&
        kit.structured && Object.keys(kit.structured as Record<string, unknown>).length > 0 &&
        typeof kit.playbook === "string" && kit.playbook.trim().length > 0;

      if (kitServe) {
        rotaAplicada = rotaDecidida;
        dadosOficiais = kit.structured;
        instructions = kit.playbook as string;
        toolsDoTurno = kit.tools;
        produtoDoTurno = produtoDoContexto(kit.structured);
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
          rota_origem: rotaOrigem,
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
      rota_origem: rotaOrigem,
    }));

    const historico = Array.isArray(conv.historico) ? conv.historico : [];
    const agendaSegura = agenda && typeof agenda === "object"
      ? Object.fromEntries(Object.entries(agenda as Record<string, unknown>)
          .filter(([k]) => ["sessions", "speakers", "locations", "exhibitors", "mind"].includes(k)))
      : {};

    const mascarado = mascarar(message);

    // Formato é validado pelo mesmo Core que normaliza a identidade. A IA recebe
    // apenas o rótulo e o resultado; o valor real continua deste lado do runtime.
    const candidatosIdentificador = [
      ...mascarado.emails.map((valor, i) => ({ chave: `email_${i + 1}`, canal: "email", valor })),
      ...mascarado.whatsapps.map((valor, i) => ({ chave: `whatsapp_${i + 1}`, canal: "whatsapp", valor })),
    ];
    const paresValidacao = await Promise.all(candidatosIdentificador.map(async (candidato) => {
      const { data, error } = await supabase.rpc("mind_identificador_validar", {
        p_canal: candidato.canal,
        p_valor: candidato.valor,
      });
      if (error || !data) {
        return [candidato.chave, { valido: false, motivo: "validacao_indisponivel" }] as const;
      }
      return [candidato.chave, {
        valido: data.valido === true,
        motivo: typeof data.motivo === "string" ? data.motivo : null,
      }] as const;
    }));
    const validacaoIdentificadores: Record<string, { valido: boolean; motivo: string | null }> =
      Object.fromEntries(paresValidacao);

    const aiInput = {
      DADOS_OFICIAIS: dadosOficiais,
      AGENDA_E_PALESTRANTES: agendaSegura,
      VALIDACAO_IDENTIFICADORES: validacaoIdentificadores,
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
        // coleta_cadastro foi criado pela regra removida e não representa estágio
        // comercial. Não deixe esse estado legado mandar o Agent voltar ao formulário.
        stage: conv.stage === "coleta_cadastro" ? "escolha_aberta" : conv.stage,
        nome_contato: conv.nome_contato ?? contactName ?? null,
        origem_codigo: conv.origem_codigo ?? origem ?? null,
        utm_de_origem: conv.utm ?? null,
        produto: conv.produto_codigo ?? null,
      },
      // Identidade e credenciamento chegam resolvidos pelo Core. Dados espontâneos
      // podem enriquecer o perfil, mas nunca viram pedágio para vender.
      quem_esta_falando: {
        ja_identificada: idConhecida,
        perfil: idPerfil,
        credenciamento: conv.credenciamento ?? null,
        como_agir: [
          "USE O QUE JÁ SABEMOS ANTES DE PERGUNTAR: confira perfil e credenciamento e nunca repita um dado conhecido.",
          ...(["summit_b2b", "summit_b2c"].includes(rotaAplicada ?? "")
            ? [
              "Venda primeiro. Nunca condicione resposta, recomendação, preço, calculadora, proposta ou checkout ao preenchimento de cadastro.",
              "Não peça nome completo, e-mail, empresa ou cargo apenas para enriquecer CRM. O WhatsApp do canal já ancora a conversa.",
              "Se a pessoa oferecer um dado espontaneamente, aproveite sem interromper o movimento comercial.",
              "Cargo e empresa descrevem a pessoa; não transformam uma compra individual em B2B.",
            ]
            : [
              "Só pergunte um dado se ele for necessário para resolver o que a pessoa quer AGORA.",
              "Se a pessoa contar algo sobre si espontaneamente, aproveite — mas não puxe.",
            ]),
          "E-mails e WhatsApps aparecem mascarados como [email_1] e [whatsapp_1]. Consulte VALIDACAO_IDENTIFICADORES: se valido=false, peça confirmação ou correção e não trate o campo como preenchido. valido=true confirma apenas formato, não propriedade ou entregabilidade. Nunca repita o rótulo na resposta.",
        ].join(" "),
      },
      historico,
      mensagem_do_lead: mascarado.texto,
    };

    const { tools: toolsParaModelo, semExecutor } = toolsDeIntelligence(toolsDoTurno);
    if (semExecutor > 0) {
      console.warn(JSON.stringify({
        request_id: requestId, event: "tool_sem_executor",
        rota: rotaAplicada, quantidade: semExecutor,
      }));
    }

    const entradaDoModelo: Array<Record<string, unknown>> = [
      { role: "user", content: JSON.stringify(aiInput) },
    ];
    const fimDoOrcamento = startedAt + ORCAMENTO_TURNO_MS;
    let aiResponse!: Response;
    let aiPayload: Record<string, unknown> = {};
    let outputText = "";
    let rodadasTool = 0;
    const chamadasFeitas: Array<{ nome: string; ok: boolean }> = [];

    for (let volta = 0; volta <= MAX_RODADAS_TOOL; volta++) {
      const restante = fimDoOrcamento - Date.now();
      if (restante <= 0) throw new DOMException("orcamento_do_turno", "AbortError");

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), restante);
      try {
        aiResponse = await fetch("https://api.openai.com/v1/responses", {
          method: "POST",
          headers: { "Authorization": `Bearer ${openAiKey}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            model,
            instructions,
            input: entradaDoModelo,
            reasoning: { effort: esforcoDeRaciocinio(message, toolsParaModelo.length) },
            text: { format: { type: "json_schema", name: "treble_agent_turn", strict: true, schema: RESPONSE_SCHEMA } },
            ...(toolsParaModelo.length > 0
              ? { tools: toolsParaModelo, tool_choice: volta >= MAX_RODADAS_TOOL ? "none" : "auto" }
              : {}),
            max_output_tokens: toolsParaModelo.length > 0 ? 3000 : 1500,
            store: false,
          }),
          signal: controller.signal,
        });
      } finally {
        clearTimeout(timeout);
      }

      if (!aiResponse.ok) break;

      aiPayload = await aiResponse.json() as Record<string, unknown>;
      const chamadas = extrairChamadas(aiPayload);
      if (chamadas.length === 0) {
        outputText = extractOutputText(aiPayload);
        break;
      }

      for (const chamada of chamadas) {
        entradaDoModelo.push({
          type: "function_call",
          call_id: chamada.call_id,
          name: chamada.name,
          arguments: chamada.arguments,
        });
      }

      const resultados = await executarChamadas(supabase, chamadas, {
        rota: rotaAplicada ?? rotaDecidida ?? "desconhecido",
        canal: CANAL,
        produtoCodigo: produtoDoTurno,
        openAiKey,
      });
      for (const resultado of resultados) {
        entradaDoModelo.push({
          type: "function_call_output",
          call_id: resultado.call_id,
          output: resultado.output,
        });
        chamadasFeitas.push({ nome: resultado.nome, ok: resultado.ok });
        if (!resultado.ok && "detalhe" in resultado && resultado.detalhe) {
          console.warn(JSON.stringify({
            request_id: requestId, event: "tool_falhou",
            tool: resultado.nome, detalhe: resultado.detalhe,
          }));
        }
      }
      rodadasTool++;
    }

    if (!aiResponse.ok) {
      console.error(JSON.stringify({ request_id: requestId, event: "openai_error", status: aiResponse.status }));
      return falhaComTransferencia(502, "ia_indisponivel", { upstream_status: aiResponse.status });
    }

    const turn = JSON.parse(outputText || extractOutputText(aiPayload)) as {
      answer: string; audience: string; intent: string; ticket_interest: string | null;
      objection: string | null; needs_human: boolean; checkout_sent: boolean;
      checkout_url: string | null;
      stage: string; desfecho: string | null;
      nome_informado: string | null; email_informado: string | null;
      whatsapp_informado: string | null;
      empresa_informada: string | null; cargo_informado: string | null;
    };
    // NUNCA cortar por caractere. Ate a v1.5.0 esta linha terminava em
    // `.slice(0, 700)`, e um turno real chegou ao WhatsApp com exatamente 700
    // caracteres, partido no meio de "Mind". Mensagem completa vale mais que
    // frase mutilada: a brevidade e comportamento do prompt, nao tesoura aqui.
    let answer = String(turn.answer ?? "").trim();
    if (!answer) throw new Error("resposta_vazia");

    // O que o lead contou sobre si NESTE turno é extraído antes das ações. Assim,
    // o último campo informado já pode liberar o checkout no próprio turno.
    const nomeDito = (turn.nome_informado ?? "").trim() || null;
    const rotuloEmail = (turn.email_informado ?? "").trim().match(/^\[?email_(\d+)\]?$/i);
    const emailDito = rotuloEmail &&
        validacaoIdentificadores[`email_${Number(rotuloEmail[1])}`]?.valido === true
      ? (mascarado.emails[Number(rotuloEmail[1]) - 1] ?? "").match(EMAIL_RE)?.[0] ?? null
      : null;
    const rotuloWhatsapp = (turn.whatsapp_informado ?? "").trim().match(/^\[?whatsapp_(\d+)\]?$/i);
    const whatsappDito = rotuloWhatsapp &&
        validacaoIdentificadores[`whatsapp_${Number(rotuloWhatsapp[1])}`]?.valido === true
      ? mascarado.whatsapps[Number(rotuloWhatsapp[1]) - 1] ?? null
      : null;
    const empresaDita = (turn.empresa_informada ?? "").trim() || null;
    const cargoDito = (turn.cargo_informado ?? "").trim() || null;

    const rotaDeVenda = ["summit_b2b", "summit_b2c"].includes(rotaAplicada ?? "");

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

    // CHECKOUT É AÇÃO DO RUNTIME, NÃO TEXTO LIVRE DO MODELO. O modelo pode escolher
    // somente uma URL que veio no Kit; o runtime confere, assina e registra. Como
    // compatibilidade, uma URL oficial já escrita em `answer` também é reconhecida.
    const checkoutCandidato = typeof turn.checkout_url === "string" && turn.checkout_url.trim()
      ? turn.checkout_url.trim()
      : null;
    let checkoutOficial = escolherCheckoutOficial(dadosOficiais, checkoutCandidato, answer);
    const checkoutSolicitado = turn.checkout_sent === true || checkoutCandidato !== null || checkoutOficial !== null;
    if (checkoutSolicitado && !checkoutOficial) {
      console.error(JSON.stringify({ request_id: requestId, event: "checkout_nao_oficial" }));
      return json(200, {
        ok: true, guarded: true,
        user_session_keys: [
          { key: "resposta_ia", value: "Não consegui abrir um checkout oficial agora. Já vou te conectar com alguém do nosso time!" },
          { key: "needs_human", value: "true" },
          { key: "checkout_sent", value: "false" },
        ],
      });
    }

    // O checkout oficial é resolvido ANTES do guardrail porque ele muda a ação segura:
    // se a copy livre contiver um preço inválido, descartamos a copy inteira e ainda
    // entregamos o carrinho validado. Sem carrinho oficial, o guardrail segue
    // fail-closed e transfere exatamente como antes.
    const decisaoPreco = decidirGuardrailPreco(
      answer,
      precosOficiais(dadosOficiais),
      checkoutOficial !== null,
    );
    if (decisaoPreco.valorRejeitado) {
      console.error(JSON.stringify({
        request_id: requestId,
        event: decisaoPreco.bloqueia ? "preco_inventado" : "preco_inventado_removido_checkout",
        preco: decisaoPreco.valorRejeitado,
      }));
    }
    if (decisaoPreco.bloqueia) {
      return json(200, {
        ok: true, guarded: true,
        user_session_keys: [
          { key: "resposta_ia", value: "Deixa eu confirmar esse valor com o time para não te passar nada errado — já te chamo um consultor! 🙌" },
          { key: "needs_human", value: "true" },
        ],
      });
    }

    let respostaFinal = decisaoPreco.resposta;
    let checkoutEventoId: string | null = null;
    if (checkoutOficial) {
      checkoutEventoId = await idEventoCheckout(
        String(conv.conversation_id), idExterno || requestId, checkoutOficial.url,
      );
      const urlRastreada = checkoutRastreado(
        checkoutOficial, checkoutEventoId, "whatsapp", "treble-inbound-agent",
      );
      const redirectBase = Deno.env.get("CHECKOUT_REDIRECT_BASE") ??
        `${supabaseUrl.replace(/\/+$/, "")}/functions/v1/mindagent-checkout`;
      const urlEntregue = checkoutCurto(checkoutEventoId, redirectBase) ?? urlRastreada;
      respostaFinal = inserirCheckoutNaResposta(answer, checkoutOficial, urlEntregue, checkoutCandidato);
    }
    const checkoutSentFinal = checkoutEventoId !== null;

    // PORTA ÚNICA DE IDENTIDADE. O e-mail que o lead disse ser dele passa pelo
    // resolvedor universal, ancorado na conversa: se for compatível, anexa à
    // mesma pessoa; se apontar para outra, vira conflito pendente. Nenhum
    // identificador é movido, e a conversa nunca troca de pessoa.
    if (emailDito || nomeDito) {
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

    // WhatsApp declarado é normalizado e gravado como declaração não verificada.
    // O número do próprio canal continua sendo a evidência forte; conflito nunca
    // move identidade nem sobrescreve um WhatsApp já conhecido.
    if (idPessoa && whatsappDito) {
      const { data: whatsappIdent, error: whatsappError } = await supabase.rpc(
        "mind_identificador_declarado_registrar",
        { p_pessoa_id: idPessoa, p_canal: "whatsapp", p_valor: whatsappDito },
      );
      if (whatsappError || whatsappIdent?.ok !== true) {
        console.warn(JSON.stringify({
          request_id: requestId,
          event: "whatsapp_identificar_falhou",
          motivo: whatsappIdent?.motivo ?? whatsappError?.message ?? "desconhecido",
        }));
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
      checkout_sent: checkoutSentFinal,
      stage: turn.stage,
      desfecho: checkoutSentFinal ? "checkout_enviado" : turn.desfecho,
    };
    // Só a resposta do agente: a fala do lead já foi persistida na ingestão.
    const { error: saveError } = await supabase.rpc("mind_turno_registrar", {
      p_conversa_id: conv.conversation_id,
      p_resposta: respostaFinal,
      p_estado: state,
      // A rota do turno fica registrada em `blocos` da mensagem do agente — nenhuma
      // coluna nova, nenhuma segunda casa. `request_id` continua sendo a chave de
      // idempotência que mind_turno_registrar lê daqui.
      p_meta: {
        model, request_id: requestId, version: VERSION,
        rota: rotaDecidida, rota_aplicada: rotaAplicada,
        precisa_esclarecer: precisaEsclarecer, candidatas,
        gate_reason: gateReason, rota_falha: falhaDaRota, router_ms: routerMs,
        rota_origem: rotaOrigem,
        tools_expostas: toolsParaModelo.length,
        rodadas_tool: rodadasTool,
        ferramentas: chamadasFeitas,
        reasoning_effort: esforcoDeRaciocinio(message, toolsParaModelo.length),
        checkout_event_id: checkoutEventoId,
        checkout_reason: checkoutOficial?.motivo ?? null,
      },
    });
    if (saveError) {
      console.error(JSON.stringify({ request_id: requestId, event: "save_falhou", detalhe: saveError.message }));
      if (checkoutEventoId) throw new Error("checkout_message_save_failed");
    }

    if (checkoutEventoId && checkoutOficial) {
      const { error: eventoError } = await supabase.rpc("mind_checkout_envio_registrar", {
        p_evento_id: checkoutEventoId,
        p_conversa_id: conv.conversation_id,
        p_checkout_url: checkoutOficial.url,
        p_canal: "whatsapp",
        p_agente: "treble-inbound-agent",
        p_rota: rotaAplicada ?? rotaDecidida,
        p_motivo: checkoutOficial.motivo,
        p_request_id: idExterno || requestId,
      });
      if (eventoError) {
        console.error(JSON.stringify({ request_id: requestId, event: "checkout_evento_falhou", detalhe: eventoError.message }));
        throw new Error("checkout_event_save_failed");
      }
    }

    console.info(JSON.stringify({
      request_id: requestId, status: 200, session: sessionId.slice(0, 8),
      rota: rotaAplicada, audience: audienceFinal, intent: turn.intent,
      needs_human: needsHumanFinal, gate_reason: gateReason,
      desfecho: turn.desfecho, identificada: idConhecida,
      email_proprio: emailDito != null,
      tools_expostas: toolsParaModelo.length,
      rodadas_tool: rodadasTool,
      chamadas_tool: chamadasFeitas.length,
      checkout_event_id: checkoutEventoId,
      chars_resposta: respostaFinal.length,
      duration_ms: Date.now() - startedAt,
    }));

    return json(200, {
      ok: true,
      user_session_keys: [
        { key: "resposta_ia", value: respostaFinal },
        { key: "needs_human", value: String(needsHumanFinal) },
        { key: "intent", value: turn.intent },
        { key: "audience", value: audienceFinal },
        { key: "checkout_sent", value: String(checkoutSentFinal) },
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
    return falhaComTransferencia(isTimeout ? 504 : 500, isTimeout ? "timeout" : "erro_interno");
  }
});
