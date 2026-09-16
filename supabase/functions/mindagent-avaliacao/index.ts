/* ============================================================
   mindagent-avaliacao — a Edge Function da Avaliação do dia
   ============================================================
   FUNÇÃO NOVA. Nenhuma linha de `mindagent-chat`, `mindagent-home`,
   `mindagent-admin` ou `mindagent-bootstrap` é tocada. A pesquisa é
   coleta estruturada e não passa pelo processamento da IA — ela não tem
   nada que fazer no turno do agente.

   ROTAS

     GET  /health

     GET  /estado?event_slug=&dia=
          O que a tela precisa para abrir: se a pesquisa está ligada, o
          dia avaliado, se a pessoa já enviou, a experiência sugerida e a
          programação oficial daquele dia. Exige a sessão do app
          (`Authorization: Bearer`), a mesma do chat.

     POST /enviar
          Envio definitivo. Mesma sessão. O corpo traz as respostas; NÃO
          traz quem responde — isso o servidor resolve.

     GET  /admin/relatorio?event_slug=&dia=&experiencia=
     GET  /admin/respostas?event_slug=&dia=&experiencia=&sessao_id=&pagina=&porPagina=
          Exige sessão de administrador, com a mesma verificação da
          `mindagent-admin` e da `mindagent-home` (`mind_admin_users`).

   IDENTIDADE
   O cliente manda um token de sessão e, quando a Yazo informou, um
   e-mail. NENHUM DOS DOIS É `participante_id`, e a função não aceita
   um: quem diz de quem é a resposta é o vínculo canônico
   (`engagement.identidades`, canal `auth_user`), lido dentro do banco a
   partir do dono do token.

   Quem nunca conversou ainda não tem esse vínculo. Para esse caso — e só
   para ele — a função chama `mind_identidade_resolver`, a mesma porta
   canônica que o chat usa na primeira mensagem, com os mesmos
   argumentos. Não existe segunda identidade, segundo cadastro de pessoas
   nem sessão paralela.

   DEPENDE de `supabase/migrations/20260916210000_avaliacao_do_dia.sql`
   aplicada. Sem ela, as rotas respondem 503.

   PRIVACIDADE
   Nenhuma resposta aberta, e-mail ou nome vai para log — nem no caminho
   feliz, nem no erro. O que se registra é o código do erro.
*/

import { createClient } from "npm:@supabase/supabase-js@2.112.3";

type AdminRole = "administrador" | "editor" | "aprovador" | "atendimento" | "analista";
type AccessRecord = { display_name: string | null; role: AdminRole; active: boolean };

const VERSAO = "1.0.0";
const EVENTO_PADRAO = "mind-summit-2026";

/* O painel em desenvolvimento e o app, nas portas de sempre. */
const DEFAULT_ORIGINS = new Set([
  "http://localhost:5174", "http://127.0.0.1:5174",
  "http://localhost:4321", "http://127.0.0.1:4321",
  "http://localhost:3000", "http://127.0.0.1:3000",
]);

/* O worker publicado E os previews de branch, que a Cloudflare serve num
   subdomínio com prefixo. Mesma regra da `mindagent-home`. */
const WORKER = /^https:\/\/(?:[a-z0-9][a-z0-9-]*-)?mind-agent\.adriana-3eb\.workers\.dev$/;

/* Todos os papéis do painel leem o relatório; nenhum escreve nele. A
   pesquisa não tem operação de escrita administrativa — resposta
   enviada não se edita, e isso vale para o admin também. */
const PAPEIS_QUE_LEEM: Set<AdminRole> = new Set([
  "administrador", "editor", "aprovador", "atendimento", "analista",
]);

const FORMATO_EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const FORMATO_SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const FORMATO_DIA = /^\d{4}-\d{2}-\d{2}$/;
const FORMATO_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/* Os mesmos limites que a migration aplica. Repetidos aqui para a
   resposta de erro ser específica em vez de "erro no banco". */
const LIMITES = { profissao: 120, expectativas: 1000, aberta: 1000 };

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

function cabecalhosCors(req: Request, doApp: boolean) {
  const origem = req.headers.get("Origin");
  /* As rotas do participante valem de qualquer origem: o app vive no
     worker, nos previews e em localhost, e a autorização delas é o token,
     não o endereço. O caminho administrativo continua fechado. */
  const liberado = doApp || origemPermitida(origem);
  return {
    "Access-Control-Allow-Origin": doApp ? "*" : (liberado && origem ? origem : "null"),
    /* `x-identidade-*` carrega o que a Yazo informou. Vai por cabeçalho e
       nunca por query string: endereço entra em histórico e em log de
       borda, e o app inteiro trabalha para manter e-mail fora dos dois. */
    "Access-Control-Allow-Headers":
      "authorization, apikey, content-type, x-client-info, x-identidade-email, x-identidade-nome",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Expose-Headers": "x-request-id",
    "Vary": "Origin",
  };
}

function json(req: Request, status: number, corpo: unknown, requestId: string, doApp = false) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: {
      ...cabecalhosCors(req, doApp),
      "Content-Type": "application/json; charset=utf-8",
      /* Nunca cacheado: tudo aqui é de uma pessoa ou é relatório vivo. */
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "X-Request-Id": requestId,
    },
  });
}

/* Os erros que as funções do banco levantam, traduzidos. O `message` do
   Postgres tem a forma `avaliacao_validacao:<motivo>`. */
function erroDeRpc(req: Request, erro: { message?: string; code?: string }, requestId: string, doApp: boolean) {
  const m = String(erro.message ?? "");

  if (m.includes("avaliacao_ja_enviada") || erro.code === "23505") {
    return json(req, 409, {
      codigo: "ja_enviada",
      mensagem: "Sua avaliação de hoje já foi enviada e não pode ser alterada.",
    }, requestId, doApp);
  }
  if (m.includes("avaliacao_sem_identidade") || erro.code === "28000") {
    return json(req, 401, {
      codigo: "sem_identidade",
      mensagem: "Não reconhecemos quem você é. Abra a avaliação pelo app do evento para continuar.",
    }, requestId, doApp);
  }
  if (m.includes("avaliacao_validacao:pesquisa_desligada")) {
    return json(req, 409, { codigo: "desligada", mensagem: "A avaliação não está disponível agora." }, requestId, doApp);
  }
  if (m.includes("avaliacao_validacao:") || erro.code === "22023") {
    const motivo = m.split("avaliacao_validacao:")[1]?.split(/\s/)[0] ?? "invalido";
    return json(req, 422, {
      codigo: "validacao", campo: motivo,
      mensagem: "Revise as respostas antes de enviar.",
    }, requestId, doApp);
  }

  /* Sem `message` no log: ele pode carregar valor de campo. */
  console.error(JSON.stringify({ request_id: requestId, error: "avaliacao_rpc_failed", code: erro.code ?? null }));
  return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível concluir agora. Tente de novo." }, requestId, doApp);
}

/* NOTA AUSENTE NÃO É NOTA ZERO, e `Number()` não sabe disso: `Number(null)`,
   `Number("")`, `Number(false)` e `Number([])` são todos `0`. Usar `Number`
   direto transformaria "não respondi" na pior nota possível — e a pesquisa
   inteira mediria errado justamente onde dói. Só número de verdade passa. */
function notaInteira(valor: unknown): number | null {
  return typeof valor === "number" && Number.isInteger(valor) ? valor : null;
}

function textoLimitado(valor: unknown, limite: number): string | null {
  if (typeof valor !== "string") return null;
  const limpo = valor.trim();
  if (!limpo) return null;
  return limpo.slice(0, limite);
}

function eventoDaUrl(url: URL) {
  const slug = url.searchParams.get("event_slug") || EVENTO_PADRAO;
  return FORMATO_SLUG.test(slug) && slug.length <= 80 ? slug : null;
}

function diaDaUrl(url: URL) {
  const dia = url.searchParams.get("dia");
  if (!dia) return null;
  return FORMATO_DIA.test(dia) ? dia : "invalido";
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const url = new URL(req.url);
  const partes = url.pathname.split("/").filter(Boolean);
  const iAdmin = partes.lastIndexOf("admin");
  const ehAdmin = iAdmin >= 0;
  const rota = partes.at(-1) ?? "";
  const doApp = !ehAdmin;

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cabecalhosCors(req, doApp) });
  }
  if (req.method === "GET" && rota === "health") {
    return json(req, 200, { ok: true, service: "mindagent-avaliacao", version: VERSAO }, requestId, true);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const chavePublicavel = lerChave("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY");
  const chaveSecreta = lerChave("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !chavePublicavel || !chaveSecreta) {
    return json(req, 503, { codigo: "indisponivel", mensagem: "Serviço indisponível." }, requestId, doApp);
  }
  const comSegredo = createClient(supabaseUrl, chaveSecreta, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const comChavePublica = createClient(supabaseUrl, chavePublicavel, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  /* Todas as rotas exigem um token — o do participante ou o do admin. */
  const token = (req.headers.get("Authorization") ?? "").match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) {
    return json(req, 401, {
      codigo: "sem_sessao",
      mensagem: "Abra a avaliação pelo app do evento para continuar.",
    }, requestId, doApp);
  }
  const { data: usuario, error: erroUsuario } = await comChavePublica.auth.getUser(token);
  if (erroUsuario || !usuario.user) {
    return json(req, 401, { codigo: "sessao_invalida", mensagem: "Sessão inválida ou expirada." }, requestId, doApp);
  }
  const authUserId = usuario.user.id;

  /* ============================================================
     O PAINEL
     ============================================================ */
  if (ehAdmin) {
    if (!origemPermitida(req.headers.get("Origin"))) {
      return json(req, 403, { codigo: "sem_permissao", mensagem: "Origem não autorizada." }, requestId);
    }
    if (req.method !== "GET") {
      return json(req, 405, { codigo: "validacao", mensagem: "Método não permitido." }, requestId);
    }

    const { data: acesso, error: erroAcesso } = await comSegredo
      .from("mind_admin_users").select("display_name,role,active")
      .eq("user_id", authUserId).maybeSingle<AccessRecord>();
    if (erroAcesso) {
      return json(req, 503, { codigo: "indisponivel", mensagem: "Não foi possível validar a permissão." }, requestId);
    }
    if (!acesso?.active || !PAPEIS_QUE_LEEM.has(acesso.role)) {
      return json(req, 403, { codigo: "sem_permissao", mensagem: "Usuário sem acesso ao painel." }, requestId);
    }

    const slug = eventoDaUrl(url);
    if (!slug) return json(req, 400, { codigo: "validacao", mensagem: "Evento inválido." }, requestId);
    const dia = diaDaUrl(url);
    if (dia === "invalido") return json(req, 400, { codigo: "validacao", mensagem: "Dia inválido." }, requestId);
    const experiencia = url.searchParams.get("experiencia");

    const alvo = partes[iAdmin + 1];

    if (alvo === "relatorio") {
      const { data, error } = await comSegredo.rpc("mind_avaliacao_do_dia_relatorio", {
        p_event_slug: slug, p_dia: dia, p_experiencia: experiencia,
      });
      if (error) return erroDeRpc(req, error, requestId, false);
      return json(req, 200, data, requestId);
    }

    if (alvo === "respostas") {
      const sessao = url.searchParams.get("sessao_id");
      if (sessao && !FORMATO_UUID.test(sessao)) {
        return json(req, 400, { codigo: "validacao", mensagem: "Atividade inválida." }, requestId);
      }
      const { data, error } = await comSegredo.rpc("mind_avaliacao_do_dia_respostas", {
        p_event_slug: slug, p_dia: dia, p_experiencia: experiencia,
        p_sessao_id: sessao, p_pagina: Number(url.searchParams.get("pagina") ?? 1) || 1,
        p_por_pagina: Number(url.searchParams.get("porPagina") ?? 50) || 50,
      });
      if (error) return erroDeRpc(req, error, requestId, false);
      return json(req, 200, data, requestId);
    }

    return json(req, 404, { codigo: "nao_encontrado", mensagem: "Rota não encontrada." }, requestId);
  }

  /* ============================================================
     O PARTICIPANTE
     ============================================================ */

  /* Liga o dono deste token à pessoa canônica quando ainda não há
     vínculo — o caso de quem abriu o app e nunca conversou. É a mesma
     chamada, com os mesmos argumentos, que a `mindagent-chat` faz na
     primeira mensagem. Falhar aqui não é erro fatal: a resposta segue
     com `identificado: false` e a tela orienta. */
  const ligarIdentidade = async (email: string | null, nome: string | null) => {
    if (!email || !FORMATO_EMAIL.test(email) || email.length > 254) return;
    const { error } = await comSegredo.rpc("mind_identidade_resolver", {
      p_identificadores: { email, auth_user_id: authUserId },
      p_nome: nome,
      p_canal: "mindagent-web",
      p_pessoa_ancora: null,
    });
    if (error) {
      console.warn(JSON.stringify({ request_id: requestId, event: "identidade_nao_ligou", code: error.code ?? null }));
    }
  };

  const lerEstado = async (slug: string, dia: string | null) => {
    return await comSegredo.rpc("mind_avaliacao_do_dia_estado", {
      p_auth_user_id: authUserId, p_event_slug: slug, p_dia: dia,
    });
  };

  if (req.method === "GET" && rota === "estado") {
    const slug = eventoDaUrl(url);
    if (!slug) return json(req, 400, { codigo: "validacao", mensagem: "Evento inválido." }, requestId, true);
    const dia = diaDaUrl(url);
    if (dia === "invalido") return json(req, 400, { codigo: "validacao", mensagem: "Dia inválido." }, requestId, true);

    let { data, error } = await lerEstado(slug, dia);
    if (error) return erroDeRpc(req, error, requestId, true);

    /* Sem vínculo e com e-mail da Yazo na mão: liga e lê de novo, uma
       vez só. O e-mail vem por cabeçalho e não por query string — barra
       de endereço e log de borda não são lugar de e-mail. */
    if (data && (data as Record<string, unknown>).identificado === false) {
      const email = textoLimitado(req.headers.get("X-Identidade-Email"), 254)?.toLowerCase() ?? null;
      if (email) {
        await ligarIdentidade(email, textoLimitado(req.headers.get("X-Identidade-Nome"), 160));
        ({ data, error } = await lerEstado(slug, dia));
        if (error) return erroDeRpc(req, error, requestId, true);
      }
    }

    return json(req, 200, data, requestId, true);
  }

  if (req.method === "POST" && rota === "enviar") {
    if (Number(req.headers.get("content-length") ?? 0) > 100_000) {
      return json(req, 413, { codigo: "validacao", mensagem: "Resposta grande demais." }, requestId, true);
    }
    let corpo: Record<string, unknown>;
    try {
      const lido = await req.json();
      if (!lido || Array.isArray(lido) || typeof lido !== "object") throw new Error("corpo");
      corpo = lido as Record<string, unknown>;
    } catch {
      return json(req, 422, { codigo: "validacao", mensagem: "Corpo inválido." }, requestId, true);
    }

    const slug = typeof corpo.eventSlug === "string" && FORMATO_SLUG.test(corpo.eventSlug)
      ? corpo.eventSlug : EVENTO_PADRAO;
    const dia = typeof corpo.dia === "string" && FORMATO_DIA.test(corpo.dia) ? corpo.dia : null;
    if (!dia) return json(req, 422, { codigo: "validacao", campo: "dia", mensagem: "Dia inválido." }, requestId, true);

    /* Quem nunca conversou também precisa poder responder. Mesma ligação
       do `/estado`, antes de gravar. */
    const email = textoLimitado(req.headers.get("X-Identidade-Email"), 254)?.toLowerCase() ?? null;
    if (email) await ligarIdentidade(email, textoLimitado(req.headers.get("X-Identidade-Nome"), 160));

    /* Só os campos que a pesquisa conhece atravessam. O que o cliente
       mandar além disso — inclusive `participanteId` — é descartado aqui
       e nunca chega ao banco. */
    const atividades = Array.isArray(corpo.atividades)
      ? (corpo.atividades as unknown[]).slice(0, 200).map((item) => {
          const a = (item ?? {}) as Record<string, unknown>;
          return { sessaoId: String(a.sessaoId ?? ""), nota: notaInteira(a.nota) };
        }).filter((a): a is { sessaoId: string; nota: number } =>
          FORMATO_UUID.test(a.sessaoId) && a.nota !== null)
      : [];

    const notaExpectativas = notaInteira(corpo.notaExpectativas);
    const notaProgramacao = notaInteira(corpo.notaProgramacao);

    const payload = {
      experiencia: typeof corpo.experiencia === "string" ? corpo.experiencia.trim().toLowerCase() : "",
      profissao: textoLimitado(corpo.profissao, LIMITES.profissao) ?? "",
      expectativas: textoLimitado(corpo.expectativas, LIMITES.expectativas) ?? "",
      notaExpectativas,
      notaProgramacao,
      maisGostou: textoLimitado(corpo.maisGostou, LIMITES.aberta),
      melhorar: textoLimitado(corpo.melhorar, LIMITES.aberta),
      comentario: textoLimitado(corpo.comentario, LIMITES.aberta),
      atividades,
    };

    if (notaExpectativas === null || notaProgramacao === null) {
      return json(req, 422, {
        codigo: "validacao", campo: "nota_obrigatoria",
        mensagem: "Responda as duas notas de 0 a 5 antes de enviar.",
      }, requestId, true);
    }

    const { data, error } = await comSegredo.rpc("mind_avaliacao_do_dia_registrar", {
      p_auth_user_id: authUserId, p_event_slug: slug, p_dia: dia, p_payload: payload,
    });
    if (error) return erroDeRpc(req, error, requestId, true);
    return json(req, 201, data, requestId, true);
  }

  return json(req, 404, { codigo: "nao_encontrado", mensagem: "Rota não encontrada." }, requestId, true);
});
