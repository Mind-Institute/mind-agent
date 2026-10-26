import type { JobConsulting } from '@/services/business-consulting';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

export function ConsultingJobsPanel({
  jobs,
  abrirObjeto,
}: {
  jobs: JobConsulting[];
  abrirObjeto: (id: string) => void;
}) {
  const areas = [...new Map(jobs.map((job) => [job.area.id, job.area])).values()]
    .sort((a,b) => a.sortOrder - b.sortOrder);

  if (jobs.length === 0) {
    return <p className="text-sm text-muted-foreground">Nenhum job consultivo registrado.</p>;
  }

  return (
    <section className="space-y-4" aria-label="Problemas consultivos">
      <div>
        <h2 className="text-lg font-black">Problemas que o consultor sabe resolver</h2>
        <p className="text-sm text-muted-foreground">
          Esta é a navegação principal. Livros são fontes; jobs combinam conhecimentos de múltiplas fontes.
        </p>
      </div>
      {areas.map((area) => {
        const daArea = jobs.filter((job) => job.area.id === area.id);
        return (
          <Card key={area.id}>
            <CardHeader>
              <CardTitle>{area.name}</CardTitle>
              <CardDescription>{area.description}</CardDescription>
            </CardHeader>
            <CardContent className="grid gap-3 xl:grid-cols-2">
              {daArea.map((job) => (
                <details key={job.id} className="rounded-lg border bg-card">
                  <summary className="cursor-pointer select-none p-4">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className="font-bold">{job.name}</span>
                      <span className="flex gap-2">
                        <Badge variant="secondary">{job.coverage.knowledgeCount} conhecimentos</Badge>
                        <Badge variant="outline">{job.coverage.sourceCount} fontes</Badge>
                      </span>
                    </div>
                    <p className="mt-2 text-sm leading-5 text-muted-foreground">{job.description}</p>
                  </summary>
                  <div className="space-y-4 border-t p-4">
                    {job.userQuestions.length > 0 ? (
                      <div>
                        <p className="text-[11px] font-black uppercase tracking-widest text-muted-foreground">Perguntas que responde</p>
                        <ul className="mt-1 list-disc space-y-1 pl-5 text-sm">
                          {job.userQuestions.map((q) => <li key={q}>{q}</li>)}
                        </ul>
                      </div>
                    ) : null}
                    {job.expectedOutput ? (
                      <div>
                        <p className="text-[11px] font-black uppercase tracking-widest text-muted-foreground">Saída esperada</p>
                        <p className="mt-1 text-sm">{job.expectedOutput}</p>
                      </div>
                    ) : null}
                    {job.relatedJobs.length > 0 ? (
                      <div>
                        <p className="text-[11px] font-black uppercase tracking-widest text-muted-foreground">Jobs relacionados</p>
                        <div className="mt-2 flex flex-wrap gap-1">
                          {job.relatedJobs.map((r) => <Badge key={`${r.direction}:${r.jobId}:${r.relationshipType}`} variant="neutro">{r.jobName}</Badge>)}
                        </div>
                      </div>
                    ) : null}
                    <div>
                      <p className="text-[11px] font-black uppercase tracking-widest text-muted-foreground">Conhecimentos usados</p>
                      <div className="mt-2 space-y-2">
                        {job.knowledge.map((k) => (
                          <button
                            key={k.id}
                            type="button"
                            onClick={() => abrirObjeto(k.id)}
                            className="w-full rounded-md border p-3 text-left hover:bg-muted/40"
                          >
                            <div className="flex flex-wrap items-center gap-2">
                              <span className="font-semibold">{k.name}</span>
                              <Badge variant="outline">{k.objectType.replaceAll('_',' ')}</Badge>
                              <Badge variant="secondary">{k.source.title}</Badge>
                            </div>
                            {k.summary ? <p className="mt-1 text-sm text-muted-foreground">{k.summary}</p> : null}
                            <p className="mt-2 text-xs text-muted-foreground">{k.rationale}</p>
                          </button>
                        ))}
                      </div>
                    </div>
                  </div>
                </details>
              ))}
            </CardContent>
          </Card>
        );
      })}
    </section>
  );
}
