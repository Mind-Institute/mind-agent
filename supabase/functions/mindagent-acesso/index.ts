/* ============================================================
   mindagent-acesso — a porta dos admins do sistema
   ============================================================
   FUNÇÃO NOVA, no molde da `mindagent-catalogo`. Nenhuma linha de
   `mindagent-admin` é tocada: ela continua respondendo `/admin/me`.

   Decisão da Adriana, 25/09/2026: o painel é dos admins deste sistema.
   Eles entram com o Google da Mind; a lista é por Mind ID; a pessoa tem
   que existir antes e estar marcada como equipe (migration 20260925232508).

   ROTAS

     POST  /admin/vincular     liga a conta Google à pessoa da lista, no
                               primeiro login. Idempotente: conta já ligada
                               devolve o que está.
     GET   /admin/admins       quem pode entrar no painel (busca, ativo, papel)
     GET   /admin/admins/:id
     POST  /admin/admins       dá acesso: { email, papel }
     PATCH /admin/admins/:id   muda papel e ativo, com If-Unmodified-Since-Version
     GET   /health

   A tela de admins do sistema é pedido da Adriana (26/09/2026): "a visão
   do quadro do backend onde eu cadastro as pessoas que podem entrar no
   sistema", para ver e cadastrar.

   Quem decide é o banco (só service_role): `mind_admin_vincular_login`
   no primeiro login; `mind_admin_read_admins` e `mind_admin_mutate_admins`
   na lista — só administrador ativo lê e escreve, a pessoa tem que existir
   no Mind ID e ser equipe, ninguém tira o próprio acesso. Aqui só se
   valida a sessão e se traduz a recusa na frase que a tela mostra.

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

/* O motivo da recusa na lista de admins, na frase que a tela mostra. */
const MOTIVO_ADMINS: Record<string, string> = {
  so_administrador: "Só administrador vê e cadastra quem entra no painel.",
  email_obrigatorio: "Informe o e-mail da pessoa.",
  dominio: "Use o e-mail da Mind (@joinmind.com.br): é com ele que a pessoa entra, pelo Google.",
  pessoa_nao_encontrada: "Esse e-mail não é de ninguém no Mind ID. A pessoa precisa existir lá antes.",
  email_em_mais_de_uma_pessoa: "Esse e-mail aparece em mais de uma pessoa do Mind ID. Resolva a duplicidade antes.",
  nao_e_equipe: "Essa pessoa não está marcada como equipe no Mind ID.",
  pessoa_fundida: "Essa pessoa foi fundida com outra no Mind ID. Use a que ficou.",
  ja_tem_acesso: "Essa pessoa já tem acesso. Para mudar o papel, abra a linha dela.",
  papel_invalido: "Papel inválido.",
  proprio_acesso: "Ninguém tira o próprio acesso nem o próprio papel de administrador por aqui.",
  ultimo_administrador: "O painel precisa de pelo menos um administrador ativo.",
  versao_obrigatoria: "Recarregue a lista antes de salvar.",
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, if-unmodified-since-version",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
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

function erroDaLista(req: Request, erro: { message?: string; code?: string }, requestId: string) {
  const m = erro.message ?? "";
  if (m.includes("admin_conflict") || erro.code === "40001") {
    return json(req, 409, { codigo: "conflito", mensagem: "Esse acesso foi alterado por outra pessoa. Recarregue antes de salvar." }, requestId);
  }
  if (m.includes("admin_forbidden") || erro.code === "42501") {
    return json(req, 403, { codigo: "sem_permissao", mensagem: MOTIVO_ADMINS.so_administrador }, requestId);
  }
  if (m.includes("admin_not_found") || erro.code === "P0002") {
    return json(req, 404, { codigo: "nao_encontrado", mensagem: "Acesso não encontrado." }, requestId);
  }
  if (m.includes("admin_validation") || erro.code === "22023") {
    const motivo = m.split("admin_validation:")[1]?.trim() ?? "";
    return json(req, 422, {
      codigo: "validacao",
      mensagem: MOTIVO_ADMINS[motivo] ?? "Revise os campos enviados.",
    }, requestId);
  }
  console.error(JSON.stringify({ request_id: requestId, error: "admins_rpc_failed", code: erro.code ?? null }));
  return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível concluir a operação." }, requestId);
}

async function corpoDoPedido(req: Request) {
  const tamanho = Number(req.headers.get("content-length") ?? 0);
  if (tamanho > 100_000) throw new Error("body_too_large");
  const valor = await req.json();
  if (!valor || Array.isArray(valor) || typeof valor !== "object") throw new Error("invalid_body");
  return valor as Record<string, unknown>;
}

/* Tira os acentos sem escape unicode no código: o caminho de publicação
   converte o escape no caractere invisível, e a versão no ar deixaria de
   bater com a do repositório. */
function semAcento(v: unknown) {
  return [...String(v ?? "").normalize("NFD")]
    .filter((c) => { const p = c.codePointAt(0) ?? 0; return p < 0x300 || p > 0x36f; })
    .join("").toLowerCase();
}

/* Busca e filtros da tela: `busca` em nome e e-mail, `ativo=true`, `papel=editor`. */
function combina(item: Record<string, unknown>, url: URL) {
  const busca = semAcento(url.searchParams.get("busca"));
  if (busca && ![item.nome, item.email].some((v) => semAcento(v).includes(busca))) return false;
  for (const chave of ["ativo", "papel"]) {
    const pedido = url.searchParams.get(chave);
    if (!pedido || pedido === "todos") continue;
    if (String(item[chave]) !== pedido) return false;
  }
  return true;
}

Deno.serve(async (req) => {
  const requestId = crypto.randomUUID();
  const url = new URL(req.url);
  const partes = url.pathname.split("/").filter(Boolean);

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cabecalhosCors(req) });
  }
  if (req.method === "GET" && partes.at(-1) === "health") {
    return json(req, 200, { ok: true, service: "mindagent-acesso", version: "2.0.0" }, requestId);
  }

  const origem = req.headers.get("Origin");
  if (!origemPermitida(origem)) {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Origem não autorizada." }, requestId);
  }

  const iAdmin = partes.lastIndexOf("admin");
  const recurso = iAdmin >= 0 ? partes[iAdmin + 1] : undefined;
  const id = iAdmin >= 0 ? partes[iAdmin + 2] : undefined;
  const sobra = iAdmin >= 0 ? partes[iAdmin + 3] : undefined;
  const ehVincular = recurso === "vincular" && !id;
  const ehLista = recurso === "admins" && !sobra;
  if (!ehVincular && !ehLista) {
    return json(req, 404, { codigo: "nao_encontrado", mensagem: "Rota não encontrada." }, requestId);
  }
  if (ehVincular && req.method !== "POST") {
    return json(req, 405, { codigo: "validacao", mensagem: "Método não permitido." }, requestId);
  }
  if (ehLista && id && !UUID.test(id)) {
    return json(req, 404, { codigo: "nao_encontrado", mensagem: "Acesso não encontrado." }, requestId);
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

  /* ---------- A lista de quem pode entrar ---------- */
  if (ehLista) {
    const ator = usuario.user.id;

    if (req.method === "GET") {
      const { data, error } = await comSegredo.rpc("mind_admin_read_admins", { p_actor_id: ator, p_id: id ?? null });
      if (error) return erroDaLista(req, error, requestId);
      const itens = (Array.isArray(data) ? data : []) as Record<string, unknown>[];
      if (id) {
        return itens[0]
          ? json(req, 200, itens[0], requestId)
          : json(req, 404, { codigo: "nao_encontrado", mensagem: "Acesso não encontrado." }, requestId);
      }
      const filtrados = itens.filter((i) => combina(i, url));
      const pagina = Math.max(1, Number(url.searchParams.get("pagina") ?? 1) || 1);
      const porPagina = Math.min(500, Math.max(1, Number(url.searchParams.get("porPagina") ?? 100) || 100));
      const inicio = (pagina - 1) * porPagina;
      return json(req, 200, {
        itens: filtrados.slice(inicio, inicio + porPagina),
        total: filtrados.length, pagina, porPagina,
      }, requestId);
    }

    let corpo: Record<string, unknown>;
    try {
      corpo = await corpoDoPedido(req);
    } catch {
      return json(req, 422, { codigo: "validacao", mensagem: "Corpo da requisição inválido." }, requestId);
    }

    if (req.method === "POST" && !id) {
      const payload: Record<string, unknown> = { email: corpo.email ?? null };
      if (corpo.papel !== undefined) payload.papel = corpo.papel;
      const { data, error } = await comSegredo.rpc("mind_admin_mutate_admins", {
        p_action: "conceder", p_id: null, p_payload: payload, p_expected_updated_at: null,
        p_actor_id: ator, p_request_id: requestId,
      });
      if (error) return erroDaLista(req, error, requestId);
      return json(req, 201, data, requestId);
    }

    if (req.method === "PATCH" && id) {
      /* Só papel e ativo mudam por aqui; o resto do corpo é ignorado. */
      const payload: Record<string, unknown> = {};
      if (corpo.papel !== undefined) payload.papel = corpo.papel;
      if (corpo.ativo !== undefined) payload.ativo = corpo.ativo;
      const { data, error } = await comSegredo.rpc("mind_admin_mutate_admins", {
        p_action: "atualizar", p_id: id, p_payload: payload,
        p_expected_updated_at: req.headers.get("If-Unmodified-Since-Version"),
        p_actor_id: ator, p_request_id: requestId,
      });
      if (error) return erroDaLista(req, error, requestId);
      return json(req, 200, data, requestId);
    }

    return json(req, 405, { codigo: "validacao", mensagem: "Método não permitido." }, requestId);
  }

  /* ---------- Primeiro login ---------- */
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
