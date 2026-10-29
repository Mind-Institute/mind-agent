/* ============================================================
   mia-liberacao — a MIA abre para quem já respondeu a pesquisa
   ============================================================
   A tela do LearnWorlds pergunta, a cada entrada: "esta pessoa já pode ver
   a MIA?". Esta função responde sim ou não, e mais nada.

   POR QUE UMA FUNÇÃO, e não uma consulta do navegador: as respostas de
   pesquisa são dado pessoal. O navegador não precisa delas — precisa de um
   booleano. Então a consulta mora aqui, com service_role, e o que atravessa
   é `{ liberada: true|false }`. Nem o nome, nem a data, nem a resposta.

   ROTA
     POST /            { email } → { ok, liberada, motivo }
     GET  /health

   ============================================================
   A COSTURA: `respondeuAPesquisa`
   ============================================================
   A pesquisa que decide isto AINDA NÃO EXISTE no banco (Vinícius,
   29/10/2026: "a pesquisa ainda não tenho ela no banco"). Tudo o mais está
   pronto e provado; falta uma função só.

   Enquanto ela não chega, `respondeuAPesquisa` devolve NÃO para todo mundo,
   com motivo `pesquisa_nao_configurada`. Isso é deliberado: um portão que
   ainda não sabe quem passa tem de ficar FECHADO, nunca aberto. A tela
   mostra a dobra da pesquisa, que é o estado correto enquanto ninguém pode
   ter respondido.

   QUANDO A PESQUISA CHEGAR, muda-se uma função — a de baixo — e nada mais.
   O formato que ela deve devolver está no tipo `Veredito`.

   O molde já existe: `engagement.pesquisa_summit_2026` guarda
   `email_informado` e `mind_id`, resolvido pela porta única de identidade
   (`mind_id_criterio`, `mind_id_resolvido_em`). Se a pesquisa nova seguir o
   mesmo formato, a troca é literalmente o nome da tabela.

   ============================================================
   O QUE ESTA FUNÇÃO NÃO É
   ============================================================
   Ela é uma CORTINA, não uma fechadura, e a diferença importa.

   O e-mail chega do LearnWorlds sem assinatura — a pessoa pode editá-lo no
   navegador. E a chave publishable do Supabase é pública por construção
   (está no bloco colado), então a `mindagent-chat` continua respondendo a
   quem a chamar direto, sem passar por esta tela.

   Isto está certo para o propósito de SEQUENCIAR a experiência: quem é
   honesto responde a pesquisa primeiro. Não serve para proteger segredo.
   Transformar a cortina em fechadura exige a `mindagent-chat` recusar o
   turno de quem não está liberado — e isso exige o servidor CONFIAR na
   identidade do LearnWorlds, que hoje ele descarta
   (`identitySource === "yazo_url"`). É mudança de auth, tem gate, e está
   na mesa da Adriana.

   UM EFEITO COLATERAL DECLARADO: esta rota diz se um e-mail respondeu a
   pesquisa. Quem souber o endereço pode perguntar por e-mails de terceiros
   e descobrir isso. É pouco, mas não é nada, e por isso a resposta é só um
   booleano e os motivos não distinguem "não existe" de "não respondeu".
*/

import { createClient } from "npm:@supabase/supabase-js@2.112.3";

const WORKER = /^https:\/\/(?:[a-z0-9][a-z0-9-]*-)?mind-agent\.adriana-3eb\.workers\.dev$/;

/* Mesma forma da `mindagent-chat`, e de propósito: a lista de origens vive
   numa variável só, e vale para as duas. Sem ela configurada, a origem é
   devolvida como veio — que é o comportamento de hoje do chat, e trocá-lo
   aqui sozinho só daria a falsa sensação de que o conjunto está fechado. */
function allowedOrigin(req: Request) {
  const origin = req.headers.get("Origin");
  const configured = (Deno.env.get("MINDAGENT_ALLOWED_ORIGINS") ?? "")
    .split(",").map((v) => v.trim()).filter(Boolean);
  if (!origin) return "*";
  if (configured.length === 0 || configured.includes(origin)) return origin;
  if (WORKER.test(origin)) return origin;
  return "null";
}

function corsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": allowedOrigin(req),
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
    "Vary": "Origin",
  };
}

function json(req: Request, status: number, corpo: unknown) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

/* O mesmo teste do bloco da MIA. Escrito aqui porque um bloco colado não
   compartilha arquivo com uma Edge Function, e porque o servidor nunca deve
   confiar na validação que o cliente diz ter feito. */
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

type Veredito = {
  /* A única coisa que a tela precisa saber. */
  liberada: boolean;
  /* Para o log e para a tela escolher a frase. Nunca distingue "não existe
     como pessoa" de "existe e não respondeu": a diferença não é da conta de
     quem está perguntando. */
  motivo:
    | "respondeu"
    | "nao_respondeu"
    | "pesquisa_nao_configurada";
};

/* ============================================================
   É AQUI QUE A PESQUISA ENTRA, E SÓ AQUI
   ============================================================
   Troque o corpo desta função quando a pesquisa existir. Exemplo do que ela
   vira, mantendo o formato da `pesquisa_summit_2026`:

       const { data, error } = await db
         .from("<tabela da pesquisa>")
         .select("mind_id")
         .eq("email_informado", email)
         .limit(1);
       if (error) throw error;
       return { liberada: data.length > 0,
                motivo: data.length > 0 ? "respondeu" : "nao_respondeu" };

   Nada fora desta função precisa mudar: nem a rota, nem o CORS, nem o
   bloco, nem os testes de contrato.

   `db` fica no parâmetro mesmo sem uso hoje: é ele que a versão de verdade
   usa, e tirá-lo faria a troca tocar a assinatura também. */
async function respondeuAPesquisa(
  _db: ReturnType<typeof createClient>,
  _email: string,
): Promise<Veredito> {
  return { liberada: false, motivo: "pesquisa_nao_configurada" };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });

  const url = new URL(req.url);
  if (req.method === "GET" && url.pathname.endsWith("/health")) {
    return json(req, 200, { ok: true, servico: "mia-liberacao" });
  }
  if (req.method !== "POST") {
    return json(req, 405, { ok: false, error: { code: "metodo_invalido" } });
  }

  let corpo: { email?: unknown };
  try {
    corpo = await req.json();
  } catch {
    return json(req, 400, { ok: false, error: { code: "corpo_invalido" } });
  }

  const email = typeof corpo.email === "string" ? corpo.email.trim().toLowerCase() : "";
  if (!EMAIL.test(email)) {
    /* Sem e-mail válido não há o que consultar. A tela trata isto como
       bloqueado, igual: é o mesmo resultado prático e evita que a ausência
       de identidade vire acesso por acidente. */
    return json(req, 200, { ok: true, liberada: false, motivo: "nao_respondeu" });
  }

  const db = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } },
  );

  try {
    const veredito = await respondeuAPesquisa(db, email);
    return json(req, 200, { ok: true, ...veredito });
  } catch (erro) {
    console.error("mia-liberacao falhou", erro);
    /* FALHA FECHA. Se o banco não respondeu, não sabemos se a pessoa pode
       entrar — e não saber nunca pode virar "pode". A tela mostra a dobra
       da pesquisa com um aviso de que não deu para conferir agora. */
    return json(req, 200, { ok: true, liberada: false, motivo: "nao_respondeu" });
  }
});
