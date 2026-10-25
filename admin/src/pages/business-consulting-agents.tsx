import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { ArrowRight, Bot, Braces, CheckCircle2, CircleDot, Code2 } from 'lucide-react';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { useSessao } from '@/hooks/use-sessao';
import { buscarAgentesIngestao, buscarRunIngestao, buscarRunsIngestao } from '@/services/business-ingestion';

const ORDEM = ['orchestrator','source_extractor','grounding_reviewer','semantic_normalizer','consulting_mapper','red_team'];

export function PaginaBusinessConsultingAgents() {
  const { simulada, obterToken, marcarSessaoExpirada } = useSessao();
  const [runId, setRunId] = useState<string | null>(null);
  const [aberto, setAberto] = useState<string | null>(null);

  const token = async () => {
    const t = await obterToken();
    if (!t) { marcarSessaoExpirada(); throw new Error('Sessão expirada. Entre novamente.'); }
    return t;
  };

  const agents = useQuery({
    queryKey:['business-ingestion','agents'],
    enabled:!simulada,
    queryFn:async()=>buscarAgentesIngestao({token:await token()}),
  });
  const runs = useQuery({
    queryKey:['business-ingestion','runs'],
    enabled:!simulada,
    queryFn:async()=>buscarRunsIngestao({token:await token()}),
  });
  const detalhe = useQuery({
    queryKey:['business-ingestion','run',runId],
    enabled:!simulada && Boolean(runId),
    queryFn:async()=>buscarRunIngestao(runId!,{token:await token()}),
  });

  const ordenados = useMemo(
    () => [...(agents.data ?? [])].sort((a,b)=>ORDEM.indexOf(a.agent_key)-ORDEM.indexOf(b.agent_key)),
    [agents.data],
  );

  function statusDoAgente(key:string) {
    const stages=detalhe.data?.stages.filter((s)=>s.agent_key===key) ?? [];
    if(!stages.length) return 'not_started';
    if(stages.some((s)=>s.status==='failed')) return 'failed';
    if(stages.some((s)=>s.status==='running')) return 'running';
    if(stages.every((s)=>s.status==='completed')) return 'completed';
    return stages.at(-1)?.status ?? 'pending';
  }

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Business Consulting · Agentes & Prompts"
        descricao="O desenho real do pipeline: quem faz o quê, com qual modelo, qual prompt e por quais runs já passou."
      />

      <Card>
        <CardHeader>
          <CardTitle>Run de referência</CardTitle>
          <CardDescription>Escolha uma ingestão para colorir o fluxo conforme o que já passou por cada agente.</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          {(runs.data ?? []).map((r)=>(
            <button key={r.id} type="button" onClick={()=>setRunId(r.id)}
              className={runId===r.id ? 'rounded-full bg-foreground px-3 py-1.5 text-xs font-semibold text-background' : 'rounded-full border px-3 py-1.5 text-xs font-semibold'}>
              {r.source?.title ?? String(r.metadata.source_title ?? r.source_id)}
            </button>
          ))}
          {(runs.data ?? []).length===0 ? <p className="text-sm text-muted-foreground">Ainda não existe run. O fluxo abaixo mostra a configuração atual.</p> : null}
        </CardContent>
      </Card>

      <section className="overflow-x-auto pb-2">
        <div className="flex min-w-max items-stretch gap-2">
          {ordenados.map((a,i)=>{
            const status=statusDoAgente(a.agent_key);
            return (
              <div key={a.agent_key} className="flex items-center gap-2">
                <button type="button" onClick={()=>setAberto(aberto===a.agent_key?null:a.agent_key)}
                  className="w-64 rounded-xl border bg-card p-4 text-left hover:bg-muted/40">
                  <div className="flex items-start justify-between gap-2">
                    <div className="rounded-lg bg-muted p-2">
                      {a.execution_kind==='code' ? <Code2 className="size-4"/> : <Bot className="size-4"/>}
                    </div>
                    <Status status={status}/>
                  </div>
                  <p className="mt-3 font-black">{a.role_name}</p>
                  <p className="mt-1 text-xs text-muted-foreground">{a.stage}</p>
                  <div className="mt-3 flex flex-wrap gap-1">
                    <Badge variant="outline">{a.execution_kind==='code'?'código':a.model}</Badge>
                    {a.reasoning_effort ? <Badge variant="secondary">reasoning {a.reasoning_effort}</Badge> : null}
                    <Badge variant="neutro">prompt v{a.prompt_version}</Badge>
                  </div>
                </button>
                {i<ordenados.length-1 ? <ArrowRight className="size-5 shrink-0 text-muted-foreground"/> : null}
              </div>
            );
          })}
        </div>
      </section>

      {aberto ? (() => {
        const a=ordenados.find((x)=>x.agent_key===aberto);
        if(!a) return null;
        const stages=detalhe.data?.stages.filter((s)=>s.agent_key===a.agent_key) ?? [];
        return (
          <Card>
            <CardHeader>
              <CardTitle>{a.role_name}</CardTitle>
              <CardDescription>{a.agent_key} · {a.stage}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-5">
              <div>
                <p className="mb-2 text-xs font-black uppercase tracking-widest text-muted-foreground">Prompt / instructions</p>
                <pre className="whitespace-pre-wrap rounded-lg border bg-muted/30 p-4 text-sm leading-6">{a.instructions}</pre>
              </div>
              <div className="grid gap-3 md:grid-cols-4">
                <Mini rotulo="Execução" valor={a.execution_kind}/>
                <Mini rotulo="Modelo" valor={a.model ?? '—'}/>
                <Mini rotulo="Reasoning" valor={a.reasoning_effort ?? '—'}/>
                <Mini rotulo="Prompt" valor={`v${a.prompt_version}`}/>
              </div>
              <div>
                <p className="mb-2 text-xs font-black uppercase tracking-widest text-muted-foreground">Execuções neste run</p>
                {stages.length===0 ? <p className="text-sm text-muted-foreground">Ainda não passou por este agente.</p> : (
                  <div className="space-y-2">
                    {stages.map((s)=>(
                      <div key={s.id} className="rounded-md border p-3 text-sm">
                        <div className="flex items-center justify-between gap-2">
                          <strong>{s.stage}</strong><Status status={s.status}/>
                        </div>
                        {s.output_summary ? <p className="mt-1 text-muted-foreground">{s.output_summary}</p> : null}
                        {s.error ? <p className="mt-1 text-destructive">{s.error}</p> : null}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </CardContent>
          </Card>
        );
      })() : (
        <Card>
          <CardContent className="flex items-center gap-3 p-5 text-sm text-muted-foreground">
            <Braces className="size-4"/>Clique em um agente para abrir o prompt real e seu histórico.
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function Status({status}:{status:string}) {
  if(status==='completed') return <Badge variant="sucesso"><CheckCircle2 className="mr-1 size-3"/>passou</Badge>;
  if(status==='failed') return <Badge variant="destructive">falhou</Badge>;
  if(status==='running') return <Badge variant="atencao"><CircleDot className="mr-1 size-3"/>rodando</Badge>;
  return <Badge variant="outline">ainda não</Badge>;
}

function Mini({rotulo,valor}:{rotulo:string;valor:string}) {
  return <div className="rounded-md border p-3"><p className="text-xs text-muted-foreground">{rotulo}</p><p className="mt-1 font-semibold">{valor}</p></div>;
}
