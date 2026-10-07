import { ExternalLink } from 'lucide-react';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { DECISOES, REGRAS_POSTERIORES, REPOSITORIO } from '@/lib/arquitetura';

/* Só leitura: o conteúdo é o resumo de `src/lib/arquitetura.ts`, que
   espelha `PROJECT_STATE.md` e `CLAUDE.md`. Não há banco por trás. */
export function PaginaArquitetura() {
  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Arquitetura do sistema"
        descricao="As decisões congeladas que orientam o banco, os agentes e este painel. O texto oficial está no PROJECT_STATE.md; aqui fica o resumo, com as palavras da Adriana quando registradas."
        acoes={
          <a
            href={`${REPOSITORIO}/PROJECT_STATE.md`}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1 text-sm font-medium underline-offset-4 hover:underline"
          >
            Abrir PROJECT_STATE.md <ExternalLink className="h-3.5 w-3.5" aria-hidden />
          </a>
        }
      />

      <section aria-labelledby="decisoes-numeradas" className="space-y-3">
        <h2 id="decisoes-numeradas" className="text-base font-bold">Decisões numeradas</h2>
        <div className="grid gap-4 lg:grid-cols-2">
          {DECISOES.map((decisao) => (
            <Card key={decisao.codigo} role="article" aria-label={`${decisao.codigo} — ${decisao.titulo}`}>
              <CardHeader className="space-y-2">
                <div className="flex items-center gap-2">
                  <Badge>{decisao.codigo}</Badge>
                  <span className="text-xs text-muted-foreground">{decisao.data}</span>
                </div>
                <CardTitle className="text-base">{decisao.titulo}</CardTitle>
                <CardDescription>{decisao.resumo}</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3 text-sm">
                {decisao.palavras ? (
                  <blockquote className="border-l-2 pl-3 italic text-muted-foreground">
                    “{decisao.palavras}”
                  </blockquote>
                ) : null}
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Onde vive</p>
                  <ul className="mt-1 list-disc space-y-0.5 pl-5">
                    {decisao.ondeVive.map((onde) => (
                      <li key={onde}>{onde}</li>
                    ))}
                  </ul>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      </section>

      <section aria-labelledby="regras-posteriores" className="space-y-3">
        <div className="space-y-1">
          <h2 id="regras-posteriores" className="text-base font-bold">Regras posteriores</h2>
          <p className="text-sm text-muted-foreground">
            Decididas pela Adriana depois da v10 e registradas no CLAUDE.md; ainda sem número no PROJECT_STATE.md.
          </p>
        </div>
        <Card>
          <CardContent className="divide-y p-0">
            {REGRAS_POSTERIORES.map((regra) => (
              <div key={regra.titulo} className="space-y-1 p-4">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-semibold">{regra.titulo}</span>
                  <span className="text-xs text-muted-foreground">{regra.data}</span>
                </div>
                <p className="text-sm text-muted-foreground">{regra.resumo}</p>
              </div>
            ))}
          </CardContent>
        </Card>
      </section>
    </div>
  );
}
