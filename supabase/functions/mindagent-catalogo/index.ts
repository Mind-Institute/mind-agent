/* ============================================================
   mindagent-catalogo — a Edge Function do Catálogo no painel
   ============================================================
   FUNÇÃO NOVA, no molde da `mindagent-home`. Nenhuma linha de
   `mindagent-admin` é tocada.

   O catálogo (`catalogo.produtos`) é a origem de tudo: CRM, conhecimento
   e agentes referenciam os códigos dele. Pedido da Adriana, 25/09/2026:
   ler e editar pelo painel, e a edição ir para o banco quando ela salvar.
   Desde 26/09 (`1.3.0`), o mesmo schema guarda ofertas e cupons — "o
   painel é o controle deste schema" —, e esta função os serve também.

   ROTAS

     GET   /admin/products          lista, com busca, filtros, ordem e paginação
     GET   /admin/products/:id      um produto
     PATCH /admin/products/:id      edição de um produto que já existe
     GET   /admin/offers            ofertas (catalogo.ofertas + preços, bônus, bump/upgrade)
     GET   /admin/offers/:id        uma oferta
     GET   /admin/coupons           cupons (catalogo.cupons)
     GET   /admin/coupons/:id       um cupom
     GET   /health

   Produto: não há criar nem arquivar; `codigo` e `schema_dados` não se
   editam — ver a migration 20260925183716. Oferta e cupom: só leitura por
   enquanto (migration 20260926202049); a edição é o Passo 4 de
   docs/PLANO_OFERTAS_PASSO_A_PASSO.md.

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

/* Cada recurso do catálogo: a porta de leitura (e de edição, quando
   existe), como a tela o chama, onde a busca olha, os filtros e as colunas
   que ordenam. Recurso novo do schema `catalogo` entra aqui. */
type Recurso = {
  ler: string;
  editar?: string;
  naoEncontrado: string;
  busca: (item: Record<string, unknown>) => unknown[];
  filtros: string[];
  ordem: Set<string>;
};

const RECURSOS: Record<string, Recurso> = {
  products: {
    ler: "mind_admin_read_catalogo",
    editar: "mind_admin_mutate_catalogo",
    naoEncontrado: "Produto não encontrado.",
    busca: (i) => [i.codigo, i.nome, i.descricaoCurta, i.descricao],
    filtros: ["vertical", "tipo", "ativo", "vende"],
    /* As colunas da tela, uma a uma (pedido da Adriana, 26/09/2026: ordenar
       por qualquer coluna, crescente e decrescente). */
    ordem: new Set([
      "codigo", "nome", "vertical", "tipo", "ativo", "vende",
      "vendeDe", "vendeAte", "comecaEm", "encerraEm", "atualizadoEm",
    ]),
  },
  offers: {
    ler: "mind_admin_read_ofertas",
    naoEncontrado: "Oferta não encontrada.",
    busca: (i) => {
      const precos = Array.isArray(i.precos) ? i.precos as Record<string, unknown>[] : [];
      return [i.codigo, i.nome, i.descricao, ...precos.flatMap((p) => [p.codigo, p.nome, p.produtoCodigo, p.produtoNome])];
    },
    filtros: ["situacao", "tipo", "verticais", "produtos", "historico", "noSite"],
    ordem: new Set(["situacaoOrdem", "codigo", "nome", "tipo", "iniciaEm", "encerraEm", "atualizadoEm"]),
  },
  coupons: {
    ler: "mind_admin_read_cupons",
    naoEncontrado: "Cupom não encontrado.",
    busca: (i) => [i.codigo, i.descricao],
    filtros: ["situacao", "tipo", "sistema", "ativo", "historico"],
    ordem: new Set(["situacaoOrdem", "codigo", "tipo", "valor", "usos", "iniciaEm", "encerraEm", "atualizadoEm"]),
  },
};

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
  datas_da_turma: "No Institute, as datas vêm da turma (institute.programas). Mude na turma, não no catálogo.",
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
   `vertical=institute`, `vertical=null` (sem vertical), `ativo=true`.
   Campo que é lista (as verticais e os produtos de uma oferta) combina
   quando contém o valor pedido. */
function combina(item: Record<string, unknown>, url: URL, recurso: Recurso) {
  const busca = semAcento(url.searchParams.get("busca"));
  if (busca && !recurso.busca(item).some((v) => semAcento(v).includes(busca))) return false;

  for (const chave of recurso.filtros) {
    const pedido = url.searchParams.get(chave);
    if (!pedido || pedido === "todos") continue;
    const valor = item[chave];
    if (Array.isArray(valor)) {
      if (!valor.map(String).includes(pedido)) return false;
      continue;
    }
    if (pedido === "null" ? valor !== null && valor !== undefined : String(valor) !== pedido) return false;
  }
  return true;
}

function ordenar(itens: Record<string, unknown>[], pedido: string | null, campos: Set<string>) {
  /* Sem pedido, fica a ordem do banco: por vertical, depois por nome. */
  const cru = pedido ?? "";
  const desc = cru.startsWith("-");
  const campo = desc ? cru.slice(1) : cru;
  if (!campo || !campos.has(campo)) return itens;
  const vazio = (v: unknown) => v === null || v === undefined || v === "";
  return [...itens].sort((a, b) => {
    const x = a[campo];
    const y = b[campo];
    /* Vazio vai para o fim nos dois sentidos: produto sem data não é o
       "mais antigo" nem o "mais novo". */
    if (vazio(x) || vazio(y)) return vazio(x) === vazio(y) ? 0 : vazio(x) ? 1 : -1;
    return comparar(x, y) * (desc ? -1 : 1);
  });
}

/* Instante compara como instante, mesmo com fusos diferentes; número como
   número (preço, usos, a ordem da situação); o resto — datas sem hora,
   `false` antes de `true`, nome, vertical e tipo — como texto, no alfabeto
   do português. O mock do painel compara igual. */
const INSTANTE = /^\d{4}-\d{2}-\d{2}T/;

function comparar(a: unknown, b: unknown) {
  if (typeof a === "number" && typeof b === "number") return a === b ? 0 : a < b ? -1 : 1;
  if (typeof a === "string" && typeof b === "string" && INSTANTE.test(a) && INSTANTE.test(b)) {
    const ta = Date.parse(a);
    const tb = Date.parse(b);
    if (!Number.isNaN(ta) && !Number.isNaN(tb)) return ta === tb ? 0 : ta < tb ? -1 : 1;
  }
  return String(a).localeCompare(String(b), "pt-BR");
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const url = new URL(req.url);
  const partes = url.pathname.split("/").filter(Boolean);

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cabecalhosCors(req) });
  }
  if (req.method === "GET" && partes.at(-1) === "health") {
    return json(req, 200, { ok: true, service: "mindagent-catalogo", version: "1.3.0" }, requestId);
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
  const nomeRecurso = iAdmin >= 0 ? partes[iAdmin + 1] : undefined;
  const id = iAdmin >= 0 ? partes[iAdmin + 2] : undefined;
  const sobra = iAdmin >= 0 ? partes[iAdmin + 3] : undefined;
  /* Só as chaves do próprio mapa: "/admin/constructor" não é recurso. */
  const recurso = nomeRecurso && Object.hasOwn(RECURSOS, nomeRecurso) ? RECURSOS[nomeRecurso] : undefined;

  if (!recurso || sobra) {
    return json(req, 404, { codigo: "nao_encontrado", mensagem: "Rota não encontrada." }, requestId);
  }
  if (id && !UUID.test(id)) {
    return json(req, 404, { codigo: "nao_encontrado", mensagem: recurso.naoEncontrado }, requestId);
  }

  /* ---------- Leitura ---------- */
  if (req.method === "GET") {
    const { data, error } = await comSegredo.rpc(recurso.ler, { p_id: id ?? null });
    if (error) return erroDeRpc(req, error, requestId);

    const itens = (Array.isArray(data) ? data : []) as Record<string, unknown>[];
    if (id) {
      return itens[0]
        ? json(req, 200, itens[0], requestId)
        : json(req, 404, { codigo: "nao_encontrado", mensagem: recurso.naoEncontrado }, requestId);
    }
    const filtrados = ordenar(
      itens.filter((i) => combina(i, url, recurso)), url.searchParams.get("ordenar"), recurso.ordem,
    );
    const pagina = Math.max(1, Number(url.searchParams.get("pagina") ?? 1) || 1);
    const porPagina = Math.min(500, Math.max(1, Number(url.searchParams.get("porPagina") ?? 100) || 100));
    const inicio = (pagina - 1) * porPagina;
    return json(req, 200, {
      itens: filtrados.slice(inicio, inicio + porPagina),
      total: filtrados.length, pagina, porPagina,
    }, requestId);
  }

  /* ---------- Edição ---------- */
  if (!recurso.editar) {
    return json(req, 405, {
      codigo: "validacao",
      mensagem: "Ofertas e cupons ainda são só leitura no painel; a edição é o próximo passo.",
    }, requestId);
  }
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

  const { data, error } = await comSegredo.rpc(recurso.editar, {
    p_action: "atualizar", p_id: id, p_payload: payload,
    p_expected_updated_at: esperado, p_actor_id: usuario.user.id, p_request_id: requestId,
  });
  if (error) return erroDeRpc(req, error, requestId);
  return json(req, 200, data, requestId);
});
