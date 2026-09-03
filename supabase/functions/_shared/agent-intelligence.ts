// Runtime compartilhado de Intelligence para todos os Agents.
//
// O Kit decide QUAIS ferramentas uma rota pode usar. Este módulo decide COMO as
// ferramentas de leitura são executadas, com escopo de rota/produto/canal, orçamento
// explícito e fallback lexical quando embedding estiver indisponível.

export const MAX_RODADAS_TOOL = 2;
export const ORCAMENTO_TURNO_MS = 30_000;

export type IntelligenceContext = {
  rota: string;
  canal: string;
  produtoCodigo?: string | null;
  openAiKey?: string;
};

export type FunctionCall = {
  call_id: string;
  name: string;
  arguments: string;
};

type RpcResult = { data: unknown; error: { message?: string } | null };
export type RpcClient = {
  rpc: (name: string, args: Record<string, unknown>) => Promise<RpcResult>;
};

const EXECUTORES = new Set(["buscar_intelligence", "ler_intelligence"]);

export function produtoDoContexto(structured: unknown) {
  if (!structured || typeof structured !== "object" || Array.isArray(structured)) return null;
  const pi = (structured as Record<string, unknown>).product_intelligence;
  if (!pi || typeof pi !== "object" || Array.isArray(pi)) return null;
  const status = (pi as Record<string, unknown>).produto_da_rota;
  if (status && typeof status === "object" && !Array.isArray(status)) {
    const codigo = (status as Record<string, unknown>).produto_codigo;
    if (typeof codigo === "string" && codigo) return codigo;
  }
  const produtos = (pi as Record<string, unknown>).produtos;
  if (!Array.isArray(produtos) || produtos.length !== 1) return null;
  const codigo = produtos[0] && typeof produtos[0] === "object"
    ? (produtos[0] as Record<string, unknown>).codigo
    : null;
  return typeof codigo === "string" && codigo ? codigo : null;
}

export function toolsDeIntelligence(kitTools: unknown) {
  const declaradas = Array.isArray(kitTools)
    ? kitTools.filter((item): item is Record<string, unknown> =>
      Boolean(item) && typeof item === "object" && !Array.isArray(item))
    : [];

  const ativas = declaradas.filter((tool) =>
    typeof tool.nome === "string" &&
    EXECUTORES.has(tool.nome) &&
    Boolean(tool.parametros) &&
    typeof tool.parametros === "object"
  );

  return {
    semExecutor: declaradas.length - ativas.length,
    tools: ativas.map((tool) => ({
      type: "function",
      name: String(tool.nome),
      description: typeof tool.descricao === "string" ? tool.descricao : "",
      parameters: tool.parametros,
      strict: true,
    })),
  };
}

export function extrairChamadas(payload: Record<string, unknown>) {
  const output = Array.isArray(payload.output) ? payload.output : [];
  const calls: FunctionCall[] = [];
  for (const raw of output) {
    if (!raw || typeof raw !== "object") continue;
    const item = raw as Record<string, unknown>;
    if (item.type !== "function_call") continue;
    if (typeof item.name !== "string" || typeof item.call_id !== "string") continue;
    calls.push({
      call_id: item.call_id,
      name: item.name,
      arguments: typeof item.arguments === "string" ? item.arguments : "{}",
    });
  }
  return calls;
}

export function esforcoDeRaciocinio(mensagem: string, ferramentas: number) {
  if (ferramentas === 0) return "none" as const;

  const texto = mensagem.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  const complexa = mensagem.length > 220 ||
    /\b(compar\w*|por que|porque|justific\w*|aprov\w*|proposta\w*|delegac\w*|equipe\w*|empresa\w*|objec\w*|estrateg\w*|recomend\w*|qual.*melhor|vale a pena|nr.?1|pgr)\b/.test(texto);

  return complexa ? "medium" as const : "low" as const;
}

export function respostaExigeBuscaAntesDeDesistir(outputText: string) {
  let resposta = outputText;
  try {
    const parsed = JSON.parse(outputText) as Record<string, unknown>;
    if (typeof parsed.answer === "string") resposta = parsed.answer;
  } catch {
    // Se a saída não for JSON, a validação normal do runtime ainda cuidará dela.
  }

  const texto = resposta
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();

  /* Uma resposta de abstinência sem nenhuma tentativa de lupa reproduz o
     defeito medido em produção: o Agent vê um recorte vazio, conclui que o
     dado não existe e expõe detalhes como `sessions: []`. O runtime dá uma
     segunda chance somente nesses casos; uma resposta factual normal não paga
     busca nem latência extra. */
  return /\b(?:nao consigo|nao consegui|nao encontrei|nao achei|nao tenho como|nao tenho (?:essa|esta) informacao)\b/.test(texto) ||
    /\b(?:dados?|fontes?|informacoes?|lista|campo|sessoes?)\b.{0,50}\b(?:vazi[oa]s?|nao (?:veio|vieram|esta|estao|tem|ha)|insuficiente|indisponivel|nao consta|nao foi informad[oa])\b/.test(texto) ||
    /\b(?:isso )?nao consta (?:nos?|em) dados\b/.test(texto) ||
    /\ba informacao nao (?:esta disponivel|foi informada)\b/.test(texto) ||
    /\bcom (?:este|esse) json\b/.test(texto);
}

function argumentos(raw: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(raw || "{}");
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : null;
  } catch {
    return null;
  }
}

async function embeddingDaConsulta(texto: string, openAiKey?: string) {
  if (!openAiKey || !texto) return null;
  try {
    const response = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openAiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ model: "text-embedding-3-small", input: texto }),
    });
    if (!response.ok) return null;
    const body = await response.json() as { data?: Array<{ embedding?: number[] }> };
    const embedding = body.data?.[0]?.embedding;
    return Array.isArray(embedding) && embedding.length === 1536
      ? `[${embedding.join(",")}]`
      : null;
  } catch {
    return null;
  }
}

export async function executarChamadas(
  client: RpcClient,
  calls: FunctionCall[],
  contexto: IntelligenceContext,
) {
  return await Promise.all(calls.map(async (call) => {
    if (!EXECUTORES.has(call.name)) {
      return {
        call_id: call.call_id,
        output: JSON.stringify({ erro: "ferramenta_desconhecida" }),
        nome: call.name,
        ok: false,
      };
    }

    const bruto = argumentos(call.arguments);
    if (!bruto) {
      return {
        call_id: call.call_id,
        output: JSON.stringify({ erro: "argumentos_invalidos" }),
        nome: call.name,
        ok: false,
      };
    }

    let rpc: string;
    let args: Record<string, unknown>;
    if (call.name === "buscar_intelligence") {
      const necessidade = String(bruto.necessidade ?? "").trim().slice(0, 400);
      const limiteBruto = Number(bruto.limite);
      const limite = Number.isFinite(limiteBruto)
        ? Math.max(1, Math.min(10, Math.trunc(limiteBruto)))
        : 6;
      rpc = "mind_intelligence_buscar_contextual";
      args = {
        p_necessidade: necessidade,
        p_limite: limite,
        p_rota: contexto.rota,
        p_canal: contexto.canal,
        p_produto_codigo: contexto.produtoCodigo ?? null,
        p_embedding: await embeddingDaConsulta(necessidade, contexto.openAiKey),
      };
    } else {
      rpc = "mind_intelligence_ler_contextual";
      args = {
        p_tipo: String(bruto.tipo ?? "").trim().slice(0, 40),
        p_id: String(bruto.id ?? "").trim().slice(0, 80),
        p_rota: contexto.rota,
        p_canal: contexto.canal,
        p_produto_codigo: contexto.produtoCodigo ?? null,
        p_corte: 1200,
      };
    }

    const { data, error } = await client.rpc(rpc, args);
    if (error) {
      return {
        call_id: call.call_id,
        output: JSON.stringify({ erro: "consulta_indisponivel" }),
        nome: call.name,
        ok: false,
        detalhe: error.message ?? null,
      };
    }

    return {
      call_id: call.call_id,
      output: JSON.stringify(data ?? { resultado: "nao_encontrado" }).slice(0, 24_000),
      nome: call.name,
      ok: true,
    };
  }));
}
