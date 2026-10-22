// Extrator de inteligência (multi-analisador).
// 1) Classificador (analise_classificador) lê a conversa e devolve a LISTA de analisadores.
// 2) Para CADA analisador da lista, roda o prompt daquele analisador e grava o output integral
//    em intelligence.analise_conversa (1 linha por conversa×analisador, campo dados jsonb).
// A projeção de dados.customer_memory -> participante_memoria acontece dentro de analise_gravar.
// Sem classificador ativo -> assume ['analise_vendas_summit']; sem o prompt específico -> cai no
// fallback analise_contexto_geral. Sem nenhum prompt ativo -> só marca como pulada.
//
// Auth: ?token=<intelligence.config.analise_token>. LLM: OpenAI Responses API.
// Classificador = json_schema strict (lista fechada). Analisadores = json_object (forma no prompt).
//
// v17 (22/10/2026) — versionada no repositório (até a v16 só existia no ar) e com o
// conserto do BACKLOG §18.1: conversa cujos analisadores estão todos desligados
// ficava na fila e era reclassificada a cada 15 minutos. Agora ela recebe a marca
// `sem_analisador` em `intelligence.analise_conversa` (dados vazios, nada de memória
// nem continuidade) e sai da fila até chegar mensagem nova. O interruptor por agente
// (`agentes.rotas.analisa_conversas`, no painel) vale em `analise_pendentes`.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";

const ORCAMENTO_MS = 55_000;

const ANALISADORES = [
  "analise_vendas_summit",
  "analise_vendas_institute",
  "analise_vendas_dash",
  "analise_atendimento",
  "analise_concierge",
] as const;

const CLASSIFIER_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    analysis_prompts: { type: "array", items: { type: "string", enum: ANALISADORES } },
    reason: { type: "string" },
  },
  required: ["analysis_prompts", "reason"],
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function extractOutputText(payload: Record<string, unknown>): string {
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

// Deriva funcao + vertical do NOME do analisador.
function mapear(analisador: string): { funcao: string; vertical: string | null } {
  if (analisador.startsWith("analise_vendas_")) {
    return { funcao: "comercial", vertical: analisador.slice("analise_vendas_".length) };
  }
  if (analisador === "analise_atendimento") return { funcao: "atendimento", vertical: null };
  if (analisador === "analise_concierge") return { funcao: "concierge", vertical: null };
  return { funcao: "geral", vertical: null };
}

Deno.serve(async (req: Request) => {
  const inicio = Date.now();
  if (req.method !== "POST") return json(405, { ok: false, error: "method_not_allowed" });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: cfg } = await supabase.rpc("analise_config");
  const token = cfg?.analise_token as string | undefined;
  const model = (cfg?.openai_model as string | undefined) || "gpt-5.4-mini";
  const url = new URL(req.url);
  if (!token || url.searchParams.get("token") !== token) {
    return json(401, { ok: false, error: "unauthorized" });
  }

  const openAiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  if (!openAiKey) return json(503, { ok: false, error: "ia_nao_configurada" });

  const body = await req.json().catch(() => ({})) as { conversa_id?: string; limite?: number };

  let ids: string[] = [];
  if (body.conversa_id) {
    ids = [body.conversa_id];
  } else {
    const { data: pend, error } = await supabase.rpc("analise_pendentes", { p_limite: body.limite ?? 10 });
    if (error) return json(500, { ok: false, error: `pendentes: ${error.message}` });
    ids = (pend ?? []).map((r: { conversa_id: string }) => r.conversa_id);
  }

  // Cache de prompts (chave -> {conteudo, versao} ou null).
  const promptCache = new Map<string, { conteudo: string; versao: number } | null>();
  async function prompt(chave: string) {
    if (promptCache.has(chave)) return promptCache.get(chave)!;
    const { data } = await supabase.rpc("analise_prompt", { p_chave: chave });
    const meta = data && typeof data.conteudo === "string" && data.conteudo.trim()
      ? { conteudo: data.conteudo as string, versao: Number(data.versao ?? 1) }
      : null;
    promptCache.set(chave, meta);
    return meta;
  }

  async function chamarIA(instructions: string, input: unknown, opts: { strict?: unknown; maxTok: number }) {
    const format = opts.strict
      ? { type: "json_schema", name: "saida", strict: true, schema: opts.strict }
      : { type: "json_object" };
    const res = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { "Authorization": `Bearer ${openAiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        instructions,
        // A OpenAI exige a palavra "json" na entrada quando o formato é json_object.
        input: [{
          role: "user",
          content: "Analise a conversa abaixo e responda em JSON, conforme as instruções.\n"
            + JSON.stringify(input),
        }],
        reasoning: { effort: "none" },
        text: { format },
        max_output_tokens: opts.maxTok,
        store: false,
      }),
    });
    if (!res.ok) throw new Error(`openai ${res.status}: ${(await res.text()).slice(0, 200)}`);
    const payload = await res.json() as Record<string, unknown>;
    return JSON.parse(extractOutputText(payload));
  }

  let conversasProcessadas = 0, analisesGravadas = 0, pulados = 0;
  const erros: Array<{ conversa_id: string; erro: string }> = [];
  const classificacoes: Array<{ conversa_id: string; prompts: string[]; reason?: string; sem_prompt: string[] }> = [];

  for (const id of ids) {
    if (Date.now() - inicio > ORCAMENTO_MS) break;
    try {
      const { data: ctx } = await supabase.rpc("analise_montar_contexto", { p_conversa_id: id });
      const transcrito = Array.isArray(ctx?.transcrito) ? ctx.transcrito : [];
      if (!transcrito.some((m: { papel?: string }) => m?.papel === "lead")) { pulados++; continue; }

      // Estágio 1 — classificar (lista). Sem classificador ativo -> assume vendas_summit.
      let lista: string[] = ["analise_vendas_summit"];
      let motivo: string | undefined;
      const pClass = await prompt("analise_classificador");
      if (pClass) {
        const cls = await chamarIA(pClass.conteudo, ctx, { strict: CLASSIFIER_SCHEMA, maxTok: 300 });
        motivo = typeof cls.reason === "string" ? cls.reason : undefined;
        if (Array.isArray(cls.analysis_prompts) && cls.analysis_prompts.length) {
          lista = [...new Set(cls.analysis_prompts.filter((x: string) => ANALISADORES.includes(x as never)))];
        }
      }
      const semPrompt: string[] = [];
      classificacoes.push({ conversa_id: id, prompts: lista, reason: motivo, sem_prompt: semPrompt });

      // Estágio 2 — rodar cada analisador da lista.
      let algum = false;
      for (const analisador of lista) {
        const p = (await prompt(analisador)) ?? (await prompt("analise_contexto_geral"));
        if (!p) { semPrompt.push(analisador); continue; } // nem o específico nem o fallback ativos
        const { funcao, vertical } = mapear(analisador);
        const dados = await chamarIA(p.conteudo, ctx, { maxTok: 4000 });
        await supabase.rpc("analise_gravar", {
          p_conversa_id: id,
          p_analisador: analisador,
          p_funcao: funcao,
          p_vertical: vertical,
          p_dados: dados,
          p_modelo: model,
          p_prompt_versao: p.versao,
        });
        analisesGravadas++;
        algum = true;
      }
      if (algum) {
        conversasProcessadas++;
      } else {
        // Nenhum analisador ativo para esta conversa: marca para sair da fila.
        await supabase.rpc("analise_gravar", {
          p_conversa_id: id,
          p_analisador: "sem_analisador",
          p_funcao: "geral",
          p_vertical: null,
          p_dados: {},
          p_modelo: null,
          p_prompt_versao: 0,
        });
        pulados++;
      }
    } catch (e) {
      erros.push({ conversa_id: id, erro: e instanceof Error ? e.message : "erro" });
    }
  }

  return json(200, {
    ok: erros.length === 0,
    version: "17",
    total: ids.length,
    conversas_processadas: conversasProcessadas,
    analises_gravadas: analisesGravadas,
    pulados,
    classificacoes,
    erros,
    ms: Date.now() - inicio,
  });
});
