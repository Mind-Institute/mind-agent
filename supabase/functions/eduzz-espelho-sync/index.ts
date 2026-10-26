// ESPELHO — copia para este projeto o que outros dois projetos Supabase ja mantem.
//
// POR QUE ASSIM, E NAO PUXANDO DA FONTE ORIGINAL:
// a EDUZZ_API_KEY guardada aqui nao abre nada — nao existe app OAuth para a conta 14449348,
// o /oauth/token da Eduzz responde "App not found". Quem tem token valido da Eduzz e quem
// fala com a Yazo e o projeto mind-summit-vendas-dashboard; quem mantem o mapeamento de
// produtos e o mind-hubpost. Os dois ja sincronizam sozinhos. Uma terceira puxada aqui seria
// mais uma credencial e mais uma coisa pra quebrar, buscando o mesmo dado.
//
// DUAS ORIGENS, mesma porta dos dois lados: `espelho_para_mind` (SECURITY DEFINER, SO LEITURA,
// protegida por um segredo no Vault de cada projeto). Nada e escrito na origem.
//
//   vendas  (tkludhksqcnhhpgqyfqq)
//     blinket, vendas                      -> eduzz.*
//     cred_participantes, cred_yazo_*      -> credenciamento_summit_2026.*
//     receitas (diaria)                    -> vendasdiretas.espelho
//   hubpost (aelmxpsgjrqwujadeuop)
//     produtos, produto_catalogo,
//     hubspot_stage_config                 -> eduzz.*
//
// As tres do hubpost e o credenciamento sao VIVOS (crescem sozinhos), por isso sync periodico
// e nao carga unica.
//
// Fontes DIARIAS ficam fora da lista padrao (o cron de 30 min nao as roda); elas so rodam quando
// pedidas no body — `vendasdiretas_espelho_diario` manda {"fontes":["receitas"]}.
//
// A senha de credenciamento nao chega aqui, nem comissao/vendedor das receitas: o corte e feito
// na porta do projeto de origem.
//
// Auth: ?token=<intelligence.config.analise_token>.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";

const ORCAMENTO_MS = 220_000;   // margem sob o teto de execucao da edge
const PAGINA = 500;

// fonte -> de qual projeto ela vem
const ORIGEM: Record<string, "vendas" | "hubpost"> = {
  blinket:              "vendas",
  vendas:               "vendas",
  produtos:             "hubpost",
  produto_catalogo:     "hubpost",
  hubspot_stage_config: "hubpost",
  cred_participantes:   "vendas",
  cred_yazo_fila:       "vendas",
  cred_yazo_espelho:    "vendas",
  cred_yazo_sync_state: "vendas",
  receitas:             "vendas",
};

// so rodam quando pedidas explicitamente (cron proprio, uma vez por dia)
const DIARIAS = new Set(["receitas"]);

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

Deno.serve(async (req: Request) => {
  const inicio = Date.now();
  if (req.method !== "POST") return json(405, { ok: false, error: "method_not_allowed" });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: cfgAuth } = await supabase.rpc("analise_config");
  const esperado = cfgAuth?.analise_token as string | undefined;
  const url = new URL(req.url);
  if (!esperado || url.searchParams.get("token") !== esperado) {
    return json(401, { ok: false, error: "unauthorized" });
  }

  const { data: cfg, error: eCfg } = await supabase.rpc("espelho_config");
  if (eCfg) return json(500, { ok: false, error: `config: ${eCfg.message}` });

  const projeto = (nome: "vendas" | "hubpost") => ({
    url: cfg?.[`${nome}_espelho_url`] as string | undefined,
    key: cfg?.[`${nome}_espelho_apikey`] as string | undefined,
    segredo: cfg?.[`${nome}_espelho_segredo`] as string | undefined,
  });

  const body = await req.json().catch(() => ({})) as { fonte?: string; fontes?: string[] };
  const fontes = body.fontes ?? (body.fonte ? [body.fonte] : Object.keys(ORIGEM).filter((f) => !DIARIAS.has(f)));

  const resumo: Array<Record<string, unknown>> = [];

  for (const fonte of fontes) {
    const nomeOrigem = ORIGEM[fonte];
    if (!nomeOrigem) {
      resumo.push({ fonte, erro: "fonte desconhecida" });
      continue;
    }
    const origem = projeto(nomeOrigem);
    if (!origem.url || !origem.key || !origem.segredo) {
      resumo.push({ fonte, erro: `config do projeto ${nomeOrigem} incompleta` });
      continue;
    }

    await supabase.rpc("espelho_estado_set", { p_fonte: fonte, p_status: "rodando" });

    let offset = 0;
    let total = 0;
    let lidos = 0;
    let gravados = 0;
    let paginas = 0;
    let incompleto = false;

    try {
      for (;;) {
        if (Date.now() - inicio > ORCAMENTO_MS) { incompleto = true; break; }

        const res = await fetch(`${origem.url}/rest/v1/rpc/espelho_para_mind`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "apikey": origem.key,
            "Authorization": `Bearer ${origem.key}`,
          },
          body: JSON.stringify({
            p_segredo: origem.segredo,
            p_fonte: fonte,
            p_offset: offset,
            p_limite: PAGINA,
          }),
        });
        if (!res.ok) {
          throw new Error(`${nomeOrigem} ${res.status}: ${(await res.text()).slice(0, 300)}`);
        }

        const pagina = await res.json() as { total: number; linhas: unknown[] };
        total = pagina.total ?? 0;
        const linhas = pagina.linhas ?? [];
        paginas++;
        lidos += linhas.length;

        if (linhas.length > 0) {
          const { data: n, error: eGrav } = await supabase.rpc("espelho_gravar", {
            p_fonte: fonte,
            p_linhas: linhas,
          });
          if (eGrav) throw new Error(`gravar: ${eGrav.message}`);
          gravados += (n as number) ?? 0;
        }

        offset += PAGINA;
        if (linhas.length < PAGINA || offset >= total) break;
      }

      await supabase.rpc("espelho_estado_set", {
        p_fonte: fonte,
        p_status: incompleto ? "erro" : "ok",
        p_total_origem: total,
        p_lidos: lidos,
        p_gravados: gravados,
        p_erro: incompleto ? "orcamento de tempo estourou; rode de novo para completar" : null,
      });

      resumo.push({ fonte, origem: nomeOrigem, total_na_origem: total, lidos, gravados, paginas, incompleto });
    } catch (e) {
      const erro = e instanceof Error ? e.message : "erro";
      await supabase.rpc("espelho_estado_set", {
        p_fonte: fonte,
        p_status: "erro",
        p_total_origem: total,
        p_lidos: lidos,
        p_gravados: gravados,
        p_erro: erro,
      });
      resumo.push({ fonte, origem: nomeOrigem, erro, lidos, gravados, paginas });
    }
  }

  return json(200, {
    ok: resumo.every((r) => !r.erro && !r.incompleto),
    resumo,
    ms: Date.now() - inicio,
  });
});
