/* ============================================================
   mindagent-acesso — a porta dos admins do sistema
   ============================================================
   FUNÇÃO NOVA, no molde da `mindagent-catalogo`. Nenhuma linha de
   `mindagent-admin` é tocada: ela continua respondendo `/admin/me`.

   Decisão da Adriana, 25/09/2026: o painel é dos admins deste sistema.
   Eles entram com o Google da Mind; a lista é por Mind ID; a pessoa tem
   que existir antes e estar marcada como equipe (migration 20260925232508).

   ROTAS

     POST /admin/vincular   liga a conta Google à pessoa da lista, no
                            primeiro login. Idempotente: conta já ligada
                            devolve o que está.
     GET  /health

   Quem decide é o banco (`mind_admin_vincular_login`, só service_role):
   conta Google, e-mail verificado @joinmind.com.br, uma pessoa só com
   esse e-mail, acesso ativo e marca de equipe. Aqui só se valida a
   sessão e se traduz a recusa na frase que a tela mostra.

   `verify_jwt = false` pelo mesmo motivo das outras funções do painel:
   o preflight do navegador chega sem token. A sessão é validada aqui
   dentro, antes de qualquer coisa.
*/

import { createClient } from "npm:@supabase/supabase-js@2.112.3";

/* O painel em desenvolvimento, na porta de sempre. */
const DEFAULT_ORIGINS = new Set(["http://localhost:5174", "http://127.0.0.1:5174"]);

/* O worker publicado E os previews de branch, que o Cloudflare publica num
   subdomínio com prefixo — o mesmo recorte das outras funções do painel. */
const WORKER = /^https:\/\/(?:[a-z0-9][a-z0-9-]*-)?mind-agent\.adriana-3eb\.workers\.dev$/;

/* O motivo que o banco devolve, na frase que a tela mostra. */
const MOTIVO: Record<string, string> = {
  conta_invalida: "Esta conta não pode entrar no painel.",
  email_nao_verificado: "O Google ainda não confirmou este e-mail.",
  dominio: "Entre com a sua conta Google da Mind (@joinmind.com.br).",
  so_google: "O painel só aceita entrar com o Google da Mind.",
  pessoa_nao_encontrada:
    "Este e-mail não está ligado a nenhuma pessoa do Mind. Peça a uma admin para cadastrar você.",
  email_em_mais_de_uma_pessoa:
    "Este e-mail aparece em mais de uma pessoa do Mind. Uma admin precisa resolver isso antes.",
  sem_acesso: "Você ainda não está na lista de admins do sistema.",
  pessoa_ja_ligada_a_outra_conta:
    "Sua pessoa já está ligada a outra conta de login. Fale com uma admin.",
  nao_e_equipe: "Sua pessoa não está marcada como equipe do Mind.",
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

function cabecalhosCors(req: Request) {
  const origem = req.headers.get("Origin");
  return {
    "Access-Control-Allow-Origin": origemPermitida(origem) && origem ? origem : "null",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Expose-Headers": "x-request-id",
    "Vary": "Origin",
  };
}

function json(req: Request, status: number, corpo: unknown, requestId: string) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: {
      ...cabecalhosCors(req),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "X-Request-Id": requestId,
    },
  });
}

Deno.serve(async (req) => {
  const requestId = crypto.randomUUID();
  const url = new URL(req.url);
  const partes = url.pathname.split("/").filter(Boolean);

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cabecalhosCors(req) });
  }
  if (req.method === "GET" && partes.at(-1) === "health") {
    return json(req, 200, { ok: true, service: "mindagent-acesso", version: "1.0.0" }, requestId);
  }

  const origem = req.headers.get("Origin");
  if (!origemPermitida(origem)) {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Origem não autorizada." }, requestId);
  }

  const ehVincular = partes.at(-2) === "admin" && partes.at(-1) === "vincular";
  if (!ehVincular) {
    return json(req, 404, { codigo: "nao_encontrado", mensagem: "Rota não encontrada." }, requestId);
  }
  if (req.method !== "POST") {
    return json(req, 405, { codigo: "validacao", mensagem: "Método não permitido." }, requestId);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const chavePublicavel = lerChave("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY");
  const chaveSecreta = lerChave("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !chavePublicavel || !chaveSecreta) {
    return json(req, 503, { codigo: "indisponivel", mensagem: "Serviço indisponível." }, requestId);
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

  const comSegredo = createClient(supabaseUrl, chaveSecreta, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await comSegredo.rpc("mind_admin_vincular_login", { p_user_id: usuario.user.id });
  if (error) {
    const motivo = (error.message ?? "").match(/admin_forbidden:([a-z_]+)/)?.[1];
    if (motivo || error.code === "42501") {
      return json(req, 403, {
        codigo: "sem_permissao",
        motivo: motivo ?? null,
        mensagem: (motivo && MOTIVO[motivo]) || "Esta conta não tem acesso ao painel.",
      }, requestId);
    }
    /* Sem e-mail nem token no log — só o que ajuda a achar o erro. */
    console.error(JSON.stringify({ request_id: requestId, error: "vincular_failed", code: error.code ?? null }));
    return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível confirmar o acesso." }, requestId);
  }

  const r = (data ?? {}) as { vinculado?: boolean; role?: string; display_name?: string | null; active?: boolean };
  if (!r.active) {
    return json(req, 403, { codigo: "sem_permissao", motivo: "sem_acesso", mensagem: MOTIVO.sem_acesso }, requestId);
  }
  return json(req, 200, { vinculado: Boolean(r.vinculado), papel: r.role ?? null, nome: r.display_name ?? null }, requestId);
});
