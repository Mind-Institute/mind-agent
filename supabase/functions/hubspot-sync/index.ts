import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Cada invocacao e curta e retomavel. O cursor incremental e salvo a cada pagina; assim o
// runtime nao bate o limite de compute tentando resolver um backlog inteiro de uma vez.
// O cron chama uma fonte por vez e cada fonte recebe seu proprio processo.
const ORCAMENTO_MS = 45_000;
const PAGINA = 100;

type Fonte =
  | "hubspot_contatos"
  | "hubspot_negocios"
  | "hubspot_negocios_historicos"
  | "hubspot_leads_inbound"
  | "hubspot_negocios_empenho_2026";

// `chavePipeline` e a chave dentro de platform.integracoes.config('hubspot').
// Pipeline novo = uma linha aqui + uma linha na config + uma linha em crm.sync_estado
// (que ja carrega tabela_destino e chave_destino). Nada mais.
const FONTES: Record<Fonte, {
  objeto: "contacts" | "deals" | "leads";
  modificado: string;
  chavePipeline?: string;
  varreArquivados?: boolean;
}> = {
  hubspot_contatos:              { objeto: "contacts", modificado: "lastmodifieddate", varreArquivados: true },
  hubspot_negocios:              { objeto: "deals", modificado: "hs_lastmodifieddate", chavePipeline: "pipeline_leads", varreArquivados: true },
  hubspot_negocios_historicos:   { objeto: "deals", modificado: "hs_lastmodifieddate", chavePipeline: "pipeline_historico" },
  hubspot_leads_inbound:         { objeto: "leads", modificado: "hs_lastmodifieddate", chavePipeline: "pipeline_leads_inbound", varreArquivados: true },
  hubspot_negocios_empenho_2026: { objeto: "deals", modificado: "hs_lastmodifieddate", chavePipeline: "pipeline_empenho_2026" },
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function limpar(valor: unknown, tipo: string): unknown {
  if (valor === null || valor === undefined) return null;
  const s = String(valor).trim();
  if (s === "") return null;
  if (tipo === "number") return Number.isFinite(Number(s)) ? s : null;
  if (tipo === "bool") return s === "true" || s === "false" ? s : null;
  if (tipo === "date" || tipo === "datetime") return s;
  return s;
}

async function hubspot(caminho: string, token: string, init?: RequestInit) {
  const res = await fetch(`https://api.hubapi.com${caminho}`, {
    ...init,
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
  if (!res.ok) {
    const corpo = await res.text().catch(() => "");
    throw new Error(`hubspot ${res.status} em ${caminho}: ${corpo.slice(0, 300)}`);
  }
  return res.json();
}

async function propriedadesDe(objeto: string, token: string) {
  const r = await hubspot(`/crm/v3/properties/${objeto}`, token);
  const tipos = new Map<string, string>();
  for (const p of r.results ?? []) tipos.set(p.name, p.type);
  return tipos;
}

async function listar(objeto: string, token: string, nomes: string[], depois?: string) {
  const q = new URLSearchParams({ limit: "100", properties: nomes.join(",") });
  if (depois) q.set("after", depois);
  const r = await hubspot(`/crm/v3/objects/${objeto}?${q.toString()}`, token);
  return { linhas: r.results ?? [], depois: r.paging?.next?.after as string | undefined };
}

async function listarArquivados(objeto: string, token: string, depois?: string) {
  const q = new URLSearchParams({ limit: String(PAGINA), archived: "true" });
  if (depois) q.set("after", depois);
  const r = await hubspot(`/crm/v3/objects/${objeto}?${q.toString()}`, token);
  return {
    ids: (r.results ?? []).map((linha: { id: string | number }) => String(linha.id)),
    depois: r.paging?.next?.after as string | undefined,
  };
}

async function contatosDosNegocios(ids: string[], token: string) {
  const mapa = new Map<string, string[]>();
  if (ids.length === 0) return mapa;
  const r = await hubspot("/crm/v4/associations/deals/contacts/batch/read", token, {
    method: "POST",
    body: JSON.stringify({ inputs: ids.map((id) => ({ id })) }),
  });
  for (const linha of r.results ?? []) {
    const de = String(linha.from?.id ?? "");
    const para = (linha.to ?? []).map((t: { toObjectId?: string | number }) => String(t.toObjectId));
    if (de) mapa.set(de, para);
  }
  return mapa;
}

Deno.serve(async (req: Request) => {
  const inicio = Date.now();
  const token = Deno.env.get("HUBSPOT_TOKEN");
  const url = Deno.env.get("SUPABASE_URL");
  const chave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!token) return json(500, { ok: false, erro: "HUBSPOT_TOKEN ausente nos secrets" });
  if (!url || !chave) return json(500, { ok: false, erro: "ambiente do supabase incompleto" });

  const db = createClient(url, chave, { auth: { persistSession: false } });

  let pedido: { fonte?: Fonte; paginas?: number; diag?: boolean; reconciliar?: boolean } = {};
  if (req.method === "POST") pedido = await req.json().catch(() => ({}));

  if (pedido.diag) {
    const r = await fetch(`https://api.hubapi.com/oauth/v1/access-tokens/${token}`);
    const info = await r.json().catch(() => ({}));
    const scopes = (info as { scopes?: string[] }).scopes;
    return json(200, {
      diag: true,
      hubspot_status: r.status,
      app_id: (info as Record<string, unknown>).app_id ?? (info as Record<string, unknown>).appId ?? null,
      hub_id: (info as Record<string, unknown>).hub_id ?? (info as Record<string, unknown>).hubId ?? null,
      user: (info as Record<string, unknown>).user ?? null,
      tem_leads_read: Array.isArray(scopes) ? scopes.includes("crm.objects.leads.read") : null,
      scopes: scopes ?? null,
    });
  }

  const alvos: Fonte[] = pedido.fonte ? [pedido.fonte] : (Object.keys(FONTES) as Fonte[]);
  const tetoPaginas = Number.isInteger(pedido.paginas) ? Number(pedido.paginas) : 10;
  const fatiaPorFonte = Math.floor(ORCAMENTO_MS / Math.max(alvos.length, 1));

  const relatorio: Record<string, unknown> = {};
  let concluidoTudo = true;

  for (const fonte of alvos) {
    const inicioFonte = Date.now();
    const definicao = FONTES[fonte];
    if (!definicao) {
      relatorio[fonte] = { erro: "fonte desconhecida" };
      concluidoTudo = false;
      continue;
    }
    const { objeto, modificado, chavePipeline } = definicao;
    const propPipeline = objeto === "leads" ? "hs_pipeline" : "pipeline";

    const { data: abertura, error: erroAbrir } = await db.rpc("mind_sync_abrir", { p_fonte: fonte });
    if (erroAbrir) {
      relatorio[fonte] = { erro: `abrir: ${erroAbrir.message}` };
      concluidoTudo = false;
      continue;
    }
    const cfg = ((abertura as { config?: Record<string, string> })?.config ?? {});
    const pipeline = chavePipeline ? cfg[chavePipeline] : null;

    if (chavePipeline && !pipeline) {
      relatorio[fonte] = { erro: `pipeline nao configurado em platform.integracoes: ${chavePipeline}` };
      concluidoTudo = false;
      continue;
    }

    if (pedido.reconciliar) {
      let cursor = (abertura as { reconciliacao_cursor?: string })?.reconciliacao_cursor ?? null;
      let lidos = 0;
      let removidos = 0;
      let concluido = false;
      let erro: string | null = null;

      try {
        for (let pagina = 0; pagina < tetoPaginas; pagina += 1) {
          const { data: lote, error: erroLote } = await db.rpc("mind_espelho_ids", {
            p_fonte: fonte,
            p_depois: cursor,
            p_limite: PAGINA,
          });
          if (erroLote) throw new Error(`listar IDs do espelho: ${erroLote.message}`);

          const ids = ((lote as { ids?: string[] })?.ids ?? []).map(String);
          const proximo = (lote as { depois?: string | null })?.depois ?? null;
          if (ids.length === 0) {
            const { error: erroMarcar } = await db.rpc("mind_sync_reconciliacao_marcar", {
              p_fonte: fonte, p_cursor: null, p_completou: true,
            });
            if (erroMarcar) throw new Error(`concluir reconciliacao: ${erroMarcar.message}`);
            concluido = true;
            break;
          }

          const loteHubSpot = await hubspot(
            `/crm/v3/objects/${objeto}/batch/read?archived=false`, token,
            {
              method: "POST",
              body: JSON.stringify({
                inputs: ids.map((id) => ({ id })),
                properties: pipeline ? [propPipeline] : [],
              }),
            },
          );
          const ativos = new Map<string, Record<string, unknown>>();
          for (const linha of loteHubSpot.results ?? []) {
            ativos.set(String(linha.id), linha.properties ?? {});
          }
          const excluir = ids.filter((id) => {
            const props = ativos.get(id);
            if (!props) return true;
            return pipeline ? String(props[propPipeline] ?? "") !== pipeline : false;
          });
          if (excluir.length > 0) {
            const { data: res, error } = await db.rpc("mind_espelho_remover", {
              p_fonte: fonte, p_ids: excluir,
            });
            if (error) throw new Error(`remover na reconciliacao: ${error.message}`);
            removidos += Number((res as { removidos?: number })?.removidos ?? 0);
          }
          lidos += ids.length;
          cursor = proximo;

          const { error: erroMarcar } = await db.rpc("mind_sync_reconciliacao_marcar", {
            p_fonte: fonte,
            p_cursor: cursor,
            p_completou: !cursor,
          });
          if (erroMarcar) throw new Error(`marcar reconciliacao: ${erroMarcar.message}`);
          if (!cursor) {
            concluido = true;
            break;
          }
        }
      } catch (e) {
        erro = e instanceof Error ? e.message : String(e);
      }

      const { error: erroStatus } = await db.rpc("mind_sync_marcar", {
        p_fonte: fonte,
        p_status: erro ? "erro" : concluido ? "ocioso" : "parcial",
        p_erro: erro,
        p_cursor: null,
      });
      relatorio[fonte] = {
        reconciliacao: true, lidos, removidos, concluido, erro,
        ...(erroStatus ? { erro_ao_marcar: erroStatus.message } : {}),
      };
      if (!concluido || erro || erroStatus) concluidoTudo = false;
      continue;
    }

    const marcaSalva = (abertura as { marca_dagua?: string })?.marca_dagua;
    const marcaBase = marcaSalva ? new Date(marcaSalva).getTime() : 0;
    let marcaMax = (abertura as { incremental_marca_max?: string })?.incremental_marca_max
      ? new Date((abertura as { incremental_marca_max: string }).incremental_marca_max).getTime()
      : marcaBase;
    const completa = Boolean((abertura as { carga_completa_em?: string })?.carga_completa_em);
    let depois: string | undefined = completa
      ? ((abertura as { incremental_cursor?: string })?.incremental_cursor ?? undefined)
      : ((abertura as { cursor?: string })?.cursor ?? undefined);

    // A busca incremental nao devolve arquivados. Varremos o endpoint oficial
    // archived=true e apagamos essas chaves do espelho descartavel.
    let cursorArquivados = (abertura as { arquivados_cursor?: string })?.arquivados_cursor ?? undefined;
    let arquivadosLidos = 0;
    let removidos = 0;
    let arquivadosConcluidos = false;
    const orcamentoArquivados = Math.min(15_000, Math.floor(fatiaPorFonte / 4));

    try {
      if (!definicao.varreArquivados) {
        arquivadosConcluidos = true;
      }
      const inicioArquivados = Date.now();
      while (definicao.varreArquivados && Date.now() - inicioArquivados < orcamentoArquivados) {
        const pg = await listarArquivados(objeto, token, cursorArquivados);
        arquivadosLidos += pg.ids.length;
        if (pg.ids.length > 0) {
          const { data: res, error } = await db.rpc("mind_espelho_remover_objeto", {
            p_objeto: objeto,
            p_ids: pg.ids,
          });
          if (error) throw new Error(`remover arquivados: ${error.message}`);
          removidos += Number((res as { removidos?: number })?.removidos ?? 0);
        }
        cursorArquivados = pg.depois;
        const { error: erroCursor } = await db.rpc("mind_sync_arquivados_marcar", {
          p_fonte: fonte,
          p_cursor: cursorArquivados ?? null,
          p_completou: !cursorArquivados,
        });
        if (erroCursor) throw new Error(`marcar arquivados: ${erroCursor.message}`);
        if (!cursorArquivados) {
          arquivadosConcluidos = true;
          break;
        }
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      await db.rpc("mind_sync_marcar", {
        p_fonte: fonte, p_status: "erro", p_erro: msg, p_cursor: null,
      });
      relatorio[fonte] = { erro: msg, arquivados_lidos: arquivadosLidos, removidos };
      concluidoTudo = false;
      continue;
    }

    let tipos: Map<string, string>;
    try {
      tipos = await propriedadesDe(objeto, token);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      await db.rpc("mind_sync_marcar", {
        p_fonte: fonte, p_status: "erro", p_erro: msg, p_cursor: null,
      });
      relatorio[fonte] = { erro: msg };
      concluidoTudo = false;
      continue;
    }
    const nomes = [...tipos.keys()];

    let lidos = 0;
    let gravados = 0;
    let paginas = 0;
    let concluido = true;
    let erro: string | null = null;

    try {
      while (paginas < tetoPaginas) {
        // a fonte para quando estoura a fatia dela OU o teto global da invocacao
        if (Date.now() - inicioFonte > fatiaPorFonte || Date.now() - inicio > ORCAMENTO_MS) {
          concluido = false;
          break;
        }

        // Lemos todas as alteracoes do tipo de objeto. Filtrar pelo pipeline no
        // HubSpot esconderia quem saiu dele e deixaria um fantasma no espelho antigo.
        const filtros: Record<string, unknown>[] = [
          { propertyName: modificado, operator: "GT", value: String(marcaBase) },
        ];

        let linhas: Array<{ id: string; properties: Record<string, unknown> }>;
        let proximo: string | undefined;

        if (!completa) {
          const pg = await listar(objeto, token, nomes, depois);
          linhas = pg.linhas;
          proximo = pg.depois;
          lidos += pg.linhas.length;
          if (pg.linhas.length === 0) break;
        } else {
          const busca = await hubspot(`/crm/v3/objects/${objeto}/search`, token, {
            method: "POST",
            body: JSON.stringify({
              filterGroups: [{ filters: filtros }],
              sorts: [{ propertyName: modificado, direction: "ASCENDING" }],
              properties: nomes,
              limit: PAGINA,
              after: depois,
            }),
          });
          linhas = busca.results ?? [];
          proximo = busca.paging?.next?.after;
          lidos += linhas.length;
          if (linhas.length === 0) {
            const { error: erroCursor } = await db.rpc("mind_sync_incremental_marcar", {
              p_fonte: fonte,
              p_cursor: null,
              p_marca_max: marcaMax > 0 ? new Date(marcaMax).toISOString() : null,
              p_completou: true,
            });
            if (erroCursor) throw new Error(`concluir incremental: ${erroCursor.message}`);
            break;
          }
        }
        paginas += 1;
        if (linhas.length === 0) { depois = proximo; if (!depois) break; continue; }

        const linhasDaFonte = pipeline
          ? linhas.filter((l) => String(l.properties?.[propPipeline] ?? "") === pipeline)
          : linhas;
        const idsForaDaFonte = pipeline
          ? linhas.filter((l) => String(l.properties?.[propPipeline] ?? "") !== pipeline)
            .map((l) => String(l.id))
          : [];

        if (idsForaDaFonte.length > 0) {
          const { data: res, error } = await db.rpc("mind_espelho_remover", {
            p_fonte: fonte,
            p_ids: idsForaDaFonte,
          });
          if (error) throw new Error(`remover fora do pipeline: ${error.message}`);
          removidos += Number((res as { removidos?: number })?.removidos ?? 0);
        }

        const ids = linhasDaFonte.map((l: { id: string }) => String(l.id));
        const assoc = objeto === "deals" ? await contatosDosNegocios(ids, token) : new Map();

        const registros = linhasDaFonte.map((l: { id: string; properties: Record<string, unknown> }) => {
          const props = l.properties ?? {};
          const limpo: Record<string, unknown> = {};
          for (const [k, v] of Object.entries(props)) {
            limpo[k] = limpar(v, tipos.get(k) ?? "string");
          }
          const inteiro: Record<string, unknown> = { ...limpo };
          if (objeto === "deals") inteiro._contatos = assoc.get(String(l.id)) ?? [];

          return {
            ...limpo,
            [objeto === "contacts" ? "hubspot_id" : objeto === "deals" ? "hubspot_deal_id" : "hubspot_lead_id"]: String(l.id),
            propriedades: inteiro,
          };
        });

        if (registros.length > 0) {
          const { data: res, error } = await db.rpc("mind_espelho_gravar", {
            p_fonte: fonte,
            p_registros: registros,
          });
          if (error) throw new Error(`gravar: ${error.message}`);
          gravados += Number((res as { gravados?: number })?.gravados ?? 0);
        }

        const ultimo = linhas[linhas.length - 1]?.properties?.[modificado];
        if (ultimo) marcaMax = Math.max(marcaMax, new Date(ultimo).getTime());

        depois = proximo;
        const { error: erroProgresso } = await db.rpc("mind_sync_marcar", {
          p_fonte: fonte,
          p_lidos: lidos,
          p_gravados: gravados,
          p_cursor: null,
        });
        if (erroProgresso) throw new Error(`marcar progresso: ${erroProgresso.message}`);

        if (completa) {
          const { error: erroCursor } = await db.rpc("mind_sync_incremental_marcar", {
            p_fonte: fonte,
            p_cursor: depois ?? null,
            p_marca_max: marcaMax > 0 ? new Date(marcaMax).toISOString() : null,
            p_completou: !depois,
          });
          if (erroCursor) throw new Error(`marcar incremental: ${erroCursor.message}`);
        } else {
          const { error: erroCursor } = await db.rpc("mind_sync_marcar", {
            p_fonte: fonte,
            p_cursor: depois ?? null,
          });
          if (erroCursor) throw new Error(`marcar carga inicial: ${erroCursor.message}`);
        }

        if (completa && !depois) break;
        if (!completa && !depois) break;
      }
      if (depois) concluido = false;
    } catch (e) {
      erro = e instanceof Error ? e.message : String(e);
      concluido = false;
    }

    if (!concluido || !arquivadosConcluidos) concluidoTudo = false;

    const varreuTudo = !completa && !erro && concluido && !depois;
    const { error: erroMarcar } = await db.rpc("mind_sync_marcar", {
      p_fonte: fonte,
      p_status: erro ? "erro" : concluido && arquivadosConcluidos ? "ocioso" : "parcial",
      p_erro: erro,
      p_marca: varreuTudo ? new Date().toISOString() : null,
      p_completou: varreuTudo,
    });
    // se a marcacao final falhar, o status fica preso em 'rodando' e a saude do espelho
    // vira mentira. Ja aconteceu (o CHECK nao aceitava 'parcial'): agora aparece no relatorio.
    if (erroMarcar) concluidoTudo = false;

    relatorio[fonte] = {
      lidos, gravados, removidos, paginas,
      arquivados_lidos: arquivadosLidos,
      arquivados_concluidos: arquivadosConcluidos,
      concluido: concluido && arquivadosConcluidos,
      erro,
      ...(erroMarcar ? { erro_ao_marcar: erroMarcar.message } : {}),
    };
    console.info(JSON.stringify({
      fn: "hubspot-sync", fonte, lidos, gravados, removidos, paginas,
      arquivados_lidos: arquivadosLidos,
      concluido: concluido && arquivadosConcluidos,
      erro,
    }));
  }

  return json(200, {
    ok: true,
    concluido: concluidoTudo,
    fontes: relatorio,
    ligacoes: { agendada_separadamente: true },
    ms: Date.now() - inicio,
  });
});
