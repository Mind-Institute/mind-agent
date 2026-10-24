import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Bot, CheckCircle2, CircleAlert, Loader2 } from 'lucide-react';
import { useSessao } from '@/hooks/use-sessao';
import { buscarAgentesIngestao, buscarRunIngestao, buscarRunsIngestao } from '@/services/business-ingestion';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

export function BusinessIngestionPanel() {
  const { simulada, obterToken, marcarSessaoExpirada } = useSessao();
  const [runId, setRunId] = useState<string | null>(null);

  const token = async () => {
    const t = await obterToken();
    if (!t) { marcarSessaoExpirada(); throw new Error('Sessão expirada. Entre novamente.'); }
    return t;
  };

  const agents = useQuery({
    queryKey:['business-ingestion','agents'],
    enabled:!simulada,
    queryFn:async ({signal}) => buscarAgentesIngestao({token:await token(),sinal:signal}),
  });
  const runs = useQuery({
    queryKey:['business-ingestion','runs'],
    enabled:!simulada,
    queryFn:async ({signal}) => buscarRunsIngestao({token:await token(),sinal:signal}),
    refetchInterval:30_000,
  });
  const detail = useQuery({
    queryKey:['business-ingestion','run',runId],
    enabled:!simulada && Boolean(runId),
    queryFn:async ({signal}) => buscarRunIngestao(runId!,{token:await token(),sinal:signal}),
    refetchInterval:20_000,
  });

  if (simulada) return <p className="text-sm text-muted-foreground">Conecte o painel ao Supabase para acompanhar a ingestão.</p>;

  return (
    <section className="space-y-5" aria-label="Ingestion Engine">
      <div>
        <h2 className="text-lg font-black">Ingestion Engine</h2>
        <p className="text-sm text-muted-foreground">Pipeline auditável: candidatos temporários só viram conhecimento canônico depois do QA.</p>
      </div>

      <div className="grid gap-3 md:grid-cols-3 xl:grid-cols-6">
        {(agents.data ?? []).map((a) => (
          <Card key={a.agent_key}>
            <CardContent className="p-4">
              <Bot className="mb-2 h-4 w-4" />
              <p className="text-sm font-bold">{a.role_name}</p>
              <p className="mt-1 text-xs text-muted-foreground">{a.execution_kind === 'code' ? 'código' : a.model}</p>
              <Badge className="mt-2" variant={a.active ? 'sucesso' : 'secondary'}>{a.active ? 'ativo' : 'inativo'}</Badge>
            </CardContent>
          </Card>
        ))}
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Execuções</CardTitle>
          <CardDescription>Cada run acompanha uma fonte do início até publicação.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          {runs.isPending ? <p className="text-sm">Carregando runs…</p> : null}
          {(runs.data ?? []).length === 0 && !runs.isPending ? <p className="text-sm text-muted-foreground">Nenhuma ingestão nova iniciada ainda.</p> : null}
          {(runs.data ?? []).map((r) => (
            <button key={r.id} type="button" onClick={() => setRunId(r.id)}
              className="flex w-full items-center justify-between rounded-md border p-3 text-left hover:bg-muted/40">
              <div>
                <p className="font-semibold">{r.source?.title ?? String(r.metadata.source_title ?? r.source_id)}</p>
                <p className="text-xs text-muted-foreground">{r.current_stage ?? r.status} · protocolo {r.protocol_version}</p>
              </div>
              <Badge variant={r.status === 'published' ? 'sucesso' : r.status === 'failed' ? 'destrutivo' : 'neutro'}>{r.status.replaceAll('_',' ')}</Badge>
            </button>
          ))}
        </CardContent>
      </Card>

      {runId ? (
        <Card>
          <CardHeader>
            <CardTitle>Run selecionado</CardTitle>
            <CardDescription>{detail.data?.run.id ?? runId}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-5">
            {detail.isPending ? <div className="flex items-center gap-2 text-sm"><Loader2 className="h-4 w-4 animate-spin" />Carregando…</div> : null}
            {detail.data ? (
              <>
                <div className="grid gap-3 md:grid-cols-3">
                  <Resumo rotulo="Candidatos" valor={detail.data.candidates.length} />
                  <Resumo rotulo="Etapas" valor={detail.data.stages.length} />
                  <Resumo rotulo="Findings abertos" valor={detail.data.findings.filter((f) => f.status === 'open').length} />
                </div>
                <div>
                  <p className="text-[11px] font-black uppercase tracking-widest text-muted-foreground">Etapas</p>
                  <div className="mt-2 space-y-2">
                    {detail.data.stages.map((s) => (
                      <div key={s.id} className="flex items-start gap-2 rounded-md border p-3 text-sm">
                        {s.status === 'completed' ? <CheckCircle2 className="mt-0.5 h-4 w-4" /> : s.status === 'failed' ? <CircleAlert className="mt-0.5 h-4 w-4" /> : <Loader2 className="mt-0.5 h-4 w-4" />}
                        <div><p className="font-semibold">{s.stage} · {s.agent_key}</p>{s.output_summary ? <p className="text-muted-foreground">{s.output_summary}</p> : null}</div>
                      </div>
                    ))}
                  </div>
                </div>
                {detail.data.findings.length > 0 ? (
                  <div>
                    <p className="text-[11px] font-black uppercase tracking-widest text-muted-foreground">QA findings</p>
                    <div className="mt-2 space-y-2">
                      {detail.data.findings.map((f) => (
                        <div key={f.id} className="rounded-md border p-3 text-sm">
                          <div className="flex items-center gap-2"><Badge variant={f.severity === 'critical' ? 'destrutivo' : f.severity === 'warning' ? 'atencao' : 'neutro'}>{f.severity}</Badge><strong>{f.finding_type}</strong></div>
                          <p className="mt-1 text-muted-foreground">{f.description}</p>
                        </div>
                      ))}
                    </div>
                  </div>
                ) : null}
              </>
            ) : null}
          </CardContent>
        </Card>
      ) : null}
    </section>
  );
}

function Resumo({rotulo,valor}:{rotulo:string;valor:number}) {
  return <div className="rounded-md border p-3"><p className="text-2xl font-black">{valor}</p><p className="text-xs text-muted-foreground">{rotulo}</p></div>;
}
