/* ============================================================
   mindagent-home — a Edge Function do módulo Home V3
   ============================================================
   FUNÇÃO NOVA. Nenhuma linha de `mindagent-admin` ou de
   `mindagent-bootstrap` é tocada — elas continuam exatamente como estão,
   inclusive com os problemas que já tinham.

   POR QUE UMA FUNÇÃO NOVA
   O painel precisava de três rotas que a `mindagent-admin` não conhece,
   e o app precisava ler avisos que o bootstrap não devolve. Os dois
   caminhos passariam por editar função viva de outra pessoa. Aqui não:
   é porta nova para conteúdo novo.

   ROTAS

     GET  /publico
          Avisos em circulação e composição da home. Sem sessão — é o
          que o participante lê. Responde `api.mindagent_home_publico`.

     POST /participante   { "email": "..." }  →  { "ingresso": "VIP" | null }
          O tipo de ingresso de quem abriu o app, para o cabeçalho. Sem
          sessão, como `/publico`, e com três cuidados que a diferenciam:

            · o e-mail vai no CORPO, nunca na URL — query string entra em
              log de borda, e o app inteiro trabalha para manter e-mail
              fora de barra de endereço;
            · a resposta NUNCA é cacheada;
            · devolve só o tipo. Ausente, `SEM MAPA`, revogado e tipo em
              desacordo respondem `null` igualzinho, então a porta não
              serve para descobrir quem tem ingresso — só confirma o tipo
              de quem tem um tipo mapeado.

          Responde `api.mindagent_participante_ingresso`, que só
          `service_role` executa.

     GET   /admin/:recurso
     GET   /admin/:recurso/:id
     POST  /admin/:recurso
     PATCH /admin/:recurso/:id
     POST  /admin/:recurso/:id/archive
          Os três recursos do módulo: `home_notices`, `home_state`,
          `home_schedule`. Exige sessão de administrador — a mesma
          verificação que a `mindagent-admin` faz, no mesmo lugar
          (`mind_admin_users`), com os mesmos papéis.

   DEPENDE de docs/sql/home-v3/ 01, 03, 04 e 06 aplicados. Publicar antes
   disso faz as rotas responderem 503.

   O CONTRATO É O MESMO da `mindagent-admin` — `{itens,total,pagina,
   porPagina}` na lista, registro cru no resto, e os mesmos códigos de
   erro — porque o painel usa o mesmo cliente HTTP para as duas.
*/

import { createClient } from "npm:@supabase/supabase-js@2.112.3";

type AdminRole = "administrador" | "editor" | "aprovador" | "atendimento" | "analista";
type AccessRecord = { display_name: string | null; role: AdminRole; active: boolean };

/* O painel em desenvolvimento e o app, nas portas de sempre. */
const DEFAULT_ORIGINS = new Set([
  "http://localhost:5174", "http://127.0.0.1:5174",
  "http://localhost:4321", "http://127.0.0.1:4321",
]);

/* O worker publicado E os previews. O Cloudflare publica cada branch num
   subdomínio com hash — `11967bf4-mind-agent.adriana-3eb.workers.dev` —,
   e uma lista fixa só com o domínio final recusaria todos eles. É o que
   acontece hoje com a `mindagent-admin`: preview nenhum consegue falar
   com ela, e a tela diz "a API não respondeu" como se fosse queda.
   Aqui o domínio do projeto vale com ou sem prefixo, e nada além dele. */
const WORKER = /^https:\/\/(?:[a-z0-9][a-z0-9-]*-)?mind-agent\.adriana-3eb\.workers\.dev$/;

const RECURSOS = new Set(["home_notices", "home_state", "home_schedule"]);
/* Estes dois vivem na mesma linha de `concierge.config`. */
const CONFIG = new Set(["home_state", "home_schedule"]);

const ACOES_POR_PAPEL: Record<AdminRole, Set<string>> = {
  administrador: new Set(["view", "edit", "create", "archive"]),
  editor: new Set(["view", "edit", "create"]),
  aprovador: new Set(["view", "edit", "archive"]),
  atendimento: new Set(["view"]),
  analista: new Set(["view"]),
};

function lerChave(nome: "SUPABASE_PUBLISHABLE_KEYS" | "SUPABASE_SECRET_KEYS", alternativa: string) {
  const cru = Deno.env.get(nome);
  if (cru) {
    try {
      const lido = JSON.parse(cru) as Record<string, unknown>;
      if (typeof lido.default === "string") return lido.default;
      const primeira = Object.values(lido).find((v) => typeof v === "string");
      if (typeof primeira === "string") return primeira;
    } catch { /* formato antigo, cai no fallback */ }
  }
  return Deno.env.get(alternativa) ?? "";
}

function origemPermitida(origem: string | null) {
  if (!origem) return true;
  if (WORKER.test(origem)) return true;
  if (DEFAULT_ORIGINS.has(origem)) return true;
  return (Deno.env.get("ADMIN_ALLOWED_ORIGINS") ?? "")
    .split(",").map((v) => v.trim()).filter(Boolean).includes(origem);
}

function cabecalhosCors(req: Request, publico: boolean) {
  const origem = req.headers.get("Origin");
  /* `/publico` é lido pelo app, que pode estar em qualquer origem — é
     conteúdo público, e restringir origem aqui só quebraria o app sem
     proteger nada. O caminho administrativo continua fechado. */
  const liberado = publico || origemPermitida(origem);
  return {
    "Access-Control-Allow-Origin": publico ? "*" : (liberado && origem ? origem : "null"),
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, if-unmodified-since-version",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
    "Access-Control-Expose-Headers": "x-request-id",
    "Vary": "Origin",
  };
}

function json(req: Request, status: number, corpo: unknown, requestId: string, publico = false, semCache = false) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: {
      ...cabecalhosCors(req, publico),
      "Content-Type": "application/json; charset=utf-8",
      /* O público pode ser cacheado por pouco tempo; o administrativo
         nunca — quem acabou de salvar precisa ver o que salvou. */
      "Cache-Control": publico && status === 200 && !semCache
        ? "public, max-age=30, stale-while-revalidate=120"
        : "no-store",
      "X-Content-Type-Options": "nosniff",
      "X-Request-Id": requestId,
    },
  });
}

function erroDeRpc(req: Request, erro: { message?: string; code?: string }, requestId: string) {
  const m = erro.message ?? "";
  if (m.includes("admin_conflict") || erro.code === "40001") {
    return json(req, 409, { codigo: "conflito", mensagem: "O registro foi alterado por outra pessoa. Recarregue antes de salvar." }, requestId);
  }
  if (m.includes("admin_forbidden") || erro.code === "42501") {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Você não tem permissão para esta operação." }, requestId);
  }
  if (m.includes("admin_not_found") || erro.code === "P0002") {
    return json(req, 404, { codigo: "nao_encontrado", mensagem: "Registro não encontrado." }, requestId);
  }
  if (m.includes("admin_validation") || erro.code === "22023") {
    return json(req, 422, { codigo: "validacao", mensagem: "Revise os campos enviados." }, requestId);
  }
  console.error(JSON.stringify({ request_id: requestId, error: "home_rpc_failed", code: erro.code ?? null }));
  return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível concluir a operação." }, requestId);
}

async function corpoDoPedido(req: Request) {
  const tamanho = Number(req.headers.get("content-length") ?? 0);
  if (tamanho > 1_000_000) throw new Error("body_too_large");
  const valor = await req.json();
  if (!valor || Array.isArray(valor) || typeof valor !== "object") throw new Error("invalid_body");
  return valor as Record<string, unknown>;
}

/* A busca do painel. `home_state` é registro único e não filtra. */
function combina(recurso: string, item: Record<string, unknown>, url: URL) {
  const busca = String(url.searchParams.get("busca") ?? "")
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  if (!busca) return true;
  const campos = recurso === "home_notices"
    ? [item.titulo, item.subtitulo, item.descricao]
    : recurso === "home_schedule"
    ? [item.nota, item.momento]
    : [item.momento, item.modo];
  return campos.some((v) => String(v ?? "")
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().includes(busca));
}

const CAMPOS_ORDEM: Record<string, Set<string>> = {
  home_notices: new Set(["disparoEm", "titulo", "situacao", "atualizadoEm"]),
  home_schedule: new Set(["quando", "momento", "atualizadoEm"]),
  home_state: new Set([]),
};

function ordenar(recurso: string, itens: Record<string, unknown>[], pedido: string | null) {
  /* Aviso: o mais recente em cima, como o participante vê.
     Agenda: para a frente, que é como se lê uma agenda. */
  const cru = pedido || (recurso === "home_notices" ? "-disparoEm"
    : recurso === "home_schedule" ? "quando" : "");
  const desc = cru.startsWith("-");
  const campo = desc ? cru.slice(1) : cru;
  if (!campo || !CAMPOS_ORDEM[recurso]?.has(campo)) return itens;
  return [...itens].sort((a, b) =>
    String(a[campo] ?? "").localeCompare(String(b[campo] ?? ""), "pt-BR") * (desc ? -1 : 1));
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const url = new URL(req.url);
  const partes = url.pathname.split("/").filter(Boolean);
  const ehPublico = partes.at(-1) === "publico";
  const ehParticipante = partes.at(-1) === "participante";
  /* As duas portas do app não pedem sessão e valem de qualquer origem. */
  const semSessao = ehPublico || ehParticipante;

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cabecalhosCors(req, semSessao) });
  }
  if (req.method === "GET" && partes.at(-1) === "health") {
    return json(req, 200, { ok: true, service: "mindagent-home", version: "1.0.0" }, requestId, true);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const chavePublicavel = lerChave("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY");
  const chaveSecreta = lerChave("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !chavePublicavel || !chaveSecreta) {
    return json(req, 503, { codigo: "indisponivel", mensagem: "Serviço indisponível." }, requestId, semSessao);
  }
  const comSegredo = createClient(supabaseUrl, chaveSecreta, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  /* ---------- A porta do app ---------- */
  if (ehPublico) {
    if (req.method !== "GET") {
      return json(req, 405, { codigo: "validacao", mensagem: "Método não permitido." }, requestId, true);
    }
    const slug = url.searchParams.get("event_slug") || "mind-summit-2026";
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug) || slug.length > 80) {
      return json(req, 400, { codigo: "validacao", mensagem: "Evento inválido." }, requestId, true);
    }
    const { data, error } = await comSegredo.rpc("mindagent_home_publico", { p_event_slug: slug });
    if (error) {
      console.error(JSON.stringify({ request_id: requestId, error: "home_publico_failed", code: error.code ?? null }));
      return json(req, 503, { codigo: "indisponivel", mensagem: "Serviço indisponível." }, requestId, true);
    }
    return json(req, 200, data, requestId, true);
  }

  /* ---------- O tipo de ingresso de quem abriu o app ---------- */
  if (ehParticipante) {
    if (req.method !== "POST") {
      return json(req, 405, { codigo: "validacao", mensagem: "Método não permitido." }, requestId, true, true);
    }
    const corpo = await req.json().catch(() => null) as { email?: unknown } | null;
    const email = typeof corpo?.email === "string" ? corpo.email.trim().toLowerCase() : "";

    /* E-mail torto responde como e-mail desconhecido, e não 400: a única
       reação possível do app é a mesma nos dois casos, e um código de
       status diferente seria mais um bit para quem estivesse sondando. */
    if (!email || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
      return json(req, 200, { ingresso: null }, requestId, true, true);
    }

    const { data, error } = await comSegredo.rpc("mindagent_participante_ingresso", { p_email: email });
    if (error) {
      /* Sem o e-mail no log — nem aqui, nem quando dá errado. */
      console.error(JSON.stringify({ request_id: requestId, error: "participante_ingresso_failed", code: error.code ?? null }));
      return json(req, 503, { codigo: "indisponivel", mensagem: "Serviço indisponível." }, requestId, true, true);
    }
    return json(req, 200, data, requestId, true, true);
  }

  /* ---------- A porta do painel ---------- */
  const origem = req.headers.get("Origin");
  if (!origemPermitida(origem)) {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Origem não autorizada." }, requestId);
  }

  const token = (req.headers.get("Authorization") ?? "").match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) return json(req, 401, { codigo: "sessao_expirada", mensagem: "Sessão ausente." }, requestId);

  const comChavePublica = createClient(supabaseUrl, chavePublicavel, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: usuario, error: erroUsuario } = await comChavePublica.auth.getUser(token);
  if (erroUsuario || !usuario.user) {
    return json(req, 401, { codigo: "sessao_expirada", mensagem: "Sessão inválida ou expirada." }, requestId);
  }

  const { data: acesso, error: erroAcesso } = await comSegredo
    .from("mind_admin_users").select("display_name,role,active")
    .eq("user_id", usuario.user.id).maybeSingle<AccessRecord>();
  if (erroAcesso) {
    return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível validar a permissão." }, requestId);
  }
  if (!acesso?.active || !ACOES_POR_PAPEL[acesso.role]) {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Usuário sem acesso ao painel." }, requestId);
  }

  const iAdmin = partes.lastIndexOf("admin");
  const recurso = iAdmin >= 0 ? partes[iAdmin + 1] : undefined;
  const id = iAdmin >= 0 ? partes[iAdmin + 2] : undefined;
  const acao = iAdmin >= 0 ? partes[iAdmin + 3] : undefined;

  if (!recurso || !RECURSOS.has(recurso)) {
    return json(req, 404, { codigo: "nao_encontrado", mensagem: "Rota não encontrada." }, requestId);
  }
  if (!ACOES_POR_PAPEL[acesso.role].has("view")) {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Sem permissão para visualizar." }, requestId);
  }

  if (req.method === "GET") {
    const { data, error } = CONFIG.has(recurso)
      ? await comSegredo.rpc("mind_admin_read_home_config", { p_resource: recurso, p_id: id ?? null })
      : await comSegredo.rpc("mind_admin_read_home_notices", { p_id: id ?? null });
    if (error) return erroDeRpc(req, error, requestId);

    const itens = (Array.isArray(data) ? data : []) as Record<string, unknown>[];
    if (id) {
      return itens[0]
        ? json(req, 200, itens[0], requestId)
        : json(req, 404, { codigo: "nao_encontrado", mensagem: "Registro não encontrado." }, requestId);
    }
    const filtrados = ordenar(recurso, itens.filter((i) => combina(recurso, i, url)),
      url.searchParams.get("ordenar"));
    const pagina = Math.max(1, Number(url.searchParams.get("pagina") ?? 1) || 1);
    const porPagina = Math.min(200, Math.max(1, Number(url.searchParams.get("porPagina") ?? 100) || 100));
    const inicio = (pagina - 1) * porPagina;
    return json(req, 200, {
      itens: filtrados.slice(inicio, inicio + porPagina),
      total: filtrados.length, pagina, porPagina,
    }, requestId);
  }

  let precisa: string;
  let acaoNoBanco: string;
  let payload: Record<string, unknown> = {};
  try { payload = await corpoDoPedido(req); }
  catch { return json(req, 422, { codigo: "validacao", mensagem: "Corpo JSON inválido." }, requestId); }

  if (req.method === "POST" && !id) { precisa = "create"; acaoNoBanco = "criar"; }
  else if (req.method === "PATCH" && id && !acao) { precisa = "edit"; acaoNoBanco = "atualizar"; }
  else if (req.method === "POST" && id && acao === "archive") { precisa = "archive"; acaoNoBanco = "arquivar"; }
  else return json(req, 405, { codigo: "validacao", mensagem: "Método não permitido para esta rota." }, requestId);

  if (!ACOES_POR_PAPEL[acesso.role].has(precisa)) {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Você não tem permissão para esta operação." }, requestId);
  }

  const esperado = req.headers.get("If-Unmodified-Since-Version")
    ?? (typeof payload.atualizadoEmEsperado === "string" ? payload.atualizadoEmEsperado : null);

  const { data, error } = CONFIG.has(recurso)
    ? await comSegredo.rpc("mind_admin_mutate_home_config", {
        p_action: acaoNoBanco, p_resource: recurso, p_id: id ?? null, p_payload: payload,
        p_expected_updated_at: esperado, p_actor_id: usuario.user.id, p_request_id: requestId,
      })
    : await comSegredo.rpc("mind_admin_mutate_home_notice", {
        p_action: acaoNoBanco, p_id: id ?? null, p_payload: payload,
        p_expected_updated_at: esperado, p_actor_id: usuario.user.id, p_request_id: requestId,
      });
  if (error) return erroDeRpc(req, error, requestId);
  return json(req, acaoNoBanco === "criar" ? 201 : 200, data, requestId);
});
