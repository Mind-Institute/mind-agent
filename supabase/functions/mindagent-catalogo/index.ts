/* ============================================================
   mindagent-catalogo — a Edge Function do Catálogo no painel
   ============================================================
   FUNÇÃO NOVA, no molde da `mindagent-home`. Nenhuma linha de
   `mindagent-admin` é tocada.

   O catálogo (`catalogo.produtos`) é a origem de tudo: CRM, conhecimento
   e agentes referenciam os códigos dele. Pedido da Adriana, 25/09/2026:
   ler e editar pelo painel, e a edição ir para o banco quando ela salvar.

   ROTAS

     GET   /admin/products          lista, com busca, filtros, ordem e paginação
     GET   /admin/products/:id      um produto
     PATCH /admin/products/:id      edição de um produto que já existe
     GET   /health

   Não há criar nem arquivar: por enquanto o catálogo se edita, não se
   cria por aqui. `codigo` e `schema_dados` não se editam — ver a
   migration 20260925183716.

   Exige sessão de administrador — a mesma verificação da `mindagent-admin`
   e da `mindagent-home`, no mesmo lugar (`mind_admin_users`), com os
   mesmos papéis. O banco confere o papel de novo antes de escrever.

   O CONTRATO É O MESMO das outras funções do painel — `{itens,total,
   pagina,porPagina}` na lista, registro cru no resto, os mesmos códigos
   de erro e `If-Unmodified-Since-Version` na escrita —, porque o painel
   usa o mesmo cliente HTTP para todas.
*/

import { createClient } from "npm:@supabase/supabase-js@2.112.3";

type AdminRole = "administrador" | "editor" | "aprovador" | "atendimento" | "analista";
type AccessRecord = { display_name: string | null; role: AdminRole; active: boolean };

/* O painel em desenvolvimento, na porta de sempre. */
const DEFAULT_ORIGINS = new Set(["http://localhost:5174", "http://127.0.0.1:5174"]);

/* O worker publicado E os previews de branch, que o Cloudflare publica num
   subdomínio com prefixo — o mesmo recorte da `mindagent-home`. */
const WORKER = /^https:\/\/(?:[a-z0-9][a-z0-9-]*-)?mind-agent\.adriana-3eb\.workers\.dev$/;

const RECURSO = "products";

const ACOES_POR_PAPEL: Record<AdminRole, Set<string>> = {
  administrador: new Set(["view", "edit"]),
  editor: new Set(["view", "edit"]),
  aprovador: new Set(["view", "edit"]),
  atendimento: new Set(["view"]),
  analista: new Set(["view"]),
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/* O motivo que o banco devolve, na frase que a tela mostra. */
const MOTIVO_VALIDACAO: Record<string, string> = {
  versao_obrigatoria: "Recarregue o produto antes de salvar.",
  codigo_nao_editavel: "O código do produto não se edita pelo painel.",
  schema_dados_nao_editavel: "O schema de dados não se edita pelo painel.",
  nome_obrigatorio: "Informe o nome do produto.",
  janela_de_venda_invertida: "O fim da venda não pode ser antes do início.",
  datas_invertidas: "O fim não pode ser antes do começo.",
  pipelines_hubspot: "Os pipelines do HubSpot precisam vir como lista.",
  dados_invalidos: "Algum campo tem valor que o banco não aceita — tipo, vertical ou data.",
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
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, if-unmodified-since-version",
    "Access-Control-Allow-Methods": "GET, PATCH, OPTIONS",
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
      /* Quem acabou de salvar precisa ver o que salvou. */
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "X-Request-Id": requestId,
    },
  });
}

function erroDeRpc(req: Request, erro: { message?: string; code?: string }, requestId: string) {
  const m = erro.message ?? "";
  if (m.includes("admin_conflict") || erro.code === "40001") {
    return json(req, 409, { codigo: "conflito", mensagem: "O produto foi alterado por outra pessoa. Recarregue antes de salvar." }, requestId);
  }
  if (m.includes("admin_forbidden") || erro.code === "42501") {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Você não tem permissão para esta operação." }, requestId);
  }
  if (m.includes("admin_not_found") || erro.code === "P0002") {
    return json(req, 404, { codigo: "nao_encontrado", mensagem: "Produto não encontrado." }, requestId);
  }
  if (m.includes("admin_validation") || erro.code === "22023") {
    const motivo = m.split("admin_validation:")[1]?.trim() ?? "";
    return json(req, 422, {
      codigo: "validacao",
      mensagem: MOTIVO_VALIDACAO[motivo] ?? "Revise os campos enviados.",
    }, requestId);
  }
  console.error(JSON.stringify({ request_id: requestId, error: "catalogo_rpc_failed", code: erro.code ?? null }));
  return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível concluir a operação." }, requestId);
}

async function corpoDoPedido(req: Request) {
  const tamanho = Number(req.headers.get("content-length") ?? 0);
  if (tamanho > 1_000_000) throw new Error("body_too_large");
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

/* Busca e filtros do painel. O filtro chega como texto na query string:
   `vertical=institute`, `vertical=null` (sem vertical), `ativo=true`. */
function combina(item: Record<string, unknown>, url: URL) {
  const busca = semAcento(url.searchParams.get("busca"));
  if (busca && ![item.codigo, item.nome, item.descricaoCurta, item.descricao]
    .some((v) => semAcento(v).includes(busca))) return false;

  for (const chave of ["vertical", "tipo", "ativo", "vende"]) {
    const pedido = url.searchParams.get(chave);
    if (!pedido || pedido === "todos") continue;
    const valor = item[chave];
    if (pedido === "null" ? valor !== null && valor !== undefined : String(valor) !== pedido) return false;
  }
  return true;
}

/* As colunas da tela, uma a uma (pedido da Adriana, 26/09/2026: ordenar
   por qualquer coluna, crescente e decrescente). */
const CAMPOS_ORDEM = new Set([
  "codigo", "nome", "vertical", "tipo", "ativo", "vende",
  "vendeDe", "vendeAte", "comecaEm", "encerraEm", "atualizadoEm",
]);

function ordenar(itens: Record<string, unknown>[], pedido: string | null) {
  /* Sem pedido, fica a ordem do banco: por vertical, depois por nome. */
  const cru = pedido ?? "";
  const desc = cru.startsWith("-");
  const campo = desc ? cru.slice(1) : cru;
  if (!campo || !CAMPOS_ORDEM.has(campo)) return itens;
  const vazio = (v: unknown) => v === null || v === undefined || v === "";
  return [...itens].sort((a, b) => {
    const x = a[campo];
    const y = b[campo];
    /* Vazio vai para o fim nos dois sentidos: produto sem data não é o
       "mais antigo" nem o "mais novo". */
    if (vazio(x) || vazio(y)) return vazio(x) === vazio(y) ? 0 : vazio(x) ? 1 : -1;
    /* Datas ISO e booleanos comparam como texto (`false` antes de `true`);
       nome, vertical e tipo, no alfabeto do português. */
    return String(x).localeCompare(String(y), "pt-BR") * (desc ? -1 : 1);
  });
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const url = new URL(req.url);
  const partes = url.pathname.split("/").filter(Boolean);

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cabecalhosCors(req) });
  }
  if (req.method === "GET" && partes.at(-1) === "health") {
    return json(req, 200, { ok: true, service: "mindagent-catalogo", version: "1.1.0" }, requestId);
  }

  const origem = req.headers.get("Origin");
  if (!origemPermitida(origem)) {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Origem não autorizada." }, requestId);
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
  const sobra = iAdmin >= 0 ? partes[iAdmin + 3] : undefined;

  if (recurso !== RECURSO || sobra) {
    return json(req, 404, { codigo: "nao_encontrado", mensagem: "Rota não encontrada." }, requestId);
  }
  if (id && !UUID.test(id)) {
    return json(req, 404, { codigo: "nao_encontrado", mensagem: "Produto não encontrado." }, requestId);
  }

  /* ---------- Leitura ---------- */
  if (req.method === "GET") {
    const { data, error } = await comSegredo.rpc("mind_admin_read_catalogo", { p_id: id ?? null });
    if (error) return erroDeRpc(req, error, requestId);

    const itens = (Array.isArray(data) ? data : []) as Record<string, unknown>[];
    if (id) {
      return itens[0]
        ? json(req, 200, itens[0], requestId)
        : json(req, 404, { codigo: "nao_encontrado", mensagem: "Produto não encontrado." }, requestId);
    }
    const filtrados = ordenar(itens.filter((i) => combina(i, url)), url.searchParams.get("ordenar"));
    const pagina = Math.max(1, Number(url.searchParams.get("pagina") ?? 1) || 1);
    const porPagina = Math.min(500, Math.max(1, Number(url.searchParams.get("porPagina") ?? 100) || 100));
    const inicio = (pagina - 1) * porPagina;
    return json(req, 200, {
      itens: filtrados.slice(inicio, inicio + porPagina),
      total: filtrados.length, pagina, porPagina,
    }, requestId);
  }

  /* ---------- Edição ---------- */
  if (req.method !== "PATCH" || !id) {
    return json(req, 405, {
      codigo: "validacao",
      mensagem: "O catálogo aceita leitura e edição; criar e arquivar produto ainda não existem no painel.",
    }, requestId);
  }
  if (!ACOES_POR_PAPEL[acesso.role].has("edit")) {
    return json(req, 403, { codigo: "sem_permissao", mensagem: "Você não tem permissão para editar o catálogo." }, requestId);
  }

  let payload: Record<string, unknown>;
  try { payload = await corpoDoPedido(req); }
  catch { return json(req, 422, { codigo: "validacao", mensagem: "Corpo JSON inválido." }, requestId); }

  const esperado = req.headers.get("If-Unmodified-Since-Version")
    ?? (typeof payload.atualizadoEmEsperado === "string" ? payload.atualizadoEmEsperado : null);

  const { data, error } = await comSegredo.rpc("mind_admin_mutate_catalogo", {
    p_action: "atualizar", p_id: id, p_payload: payload,
    p_expected_updated_at: esperado, p_actor_id: usuario.user.id, p_request_id: requestId,
  });
  if (error) return erroDeRpc(req, error, requestId);
  return json(req, 200, data, requestId);
});
