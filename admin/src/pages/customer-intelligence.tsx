import { useMemo, useState } from 'react';
import { Database, ShieldAlert, UsersRound } from 'lucide-react';
import type { CustomerKnowledgeGovernance } from '@/contracts';
import { useLista } from '@/hooks/use-recurso';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

function agrupar(itens: CustomerKnowledgeGovernance[]) {
  const mapa = new Map<string, CustomerKnowledgeGovernance[]>();
  for (const item of itens) {
    const atual = mapa.get(item.collectionKey) ?? [];
    atual.push(item);
    mapa.set(item.collectionKey, atual);
  }
  return Array.from(mapa.entries()).sort((a, b) =>
    a[1][0].collectionName.localeCompare(b[1][0].collectionName, 'pt-BR'),
  );
}

function sensibilidade(v: CustomerKnowledgeGovernance['sensitivity']) {
  if (v === 'sensitive') return <Badge variant="destructive">sensitive</Badge>;
  if (v === 'personal') return <Badge variant="atencao">personal</Badge>;
  return <Badge variant="secondary">internal</Badge>;
}

export function PaginaCustomerIntelligence() {
  const query = useLista('customer_intelligence', { porPagina: 500 });
  const grupos = useMemo(() => agrupar(query.data?.itens ?? []), [query.data?.itens]);
  const [aberta, setAberta] = useState<string | null>(null);

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Customer Intelligence"
        descricao="Mapa de governança do que o Mind sabe sobre pessoas, empresas, conversas, intenção, sinais comerciais e comportamento. Esta camada não autoriza acesso indiscriminado: cada fonte mantém seu escopo de pessoa/conta."
      />

      <Card>
        <CardContent className="flex gap-3 py-4 text-sm text-muted-foreground">
          <ShieldAlert className="mt-0.5 size-4 shrink-0" />
          O switch de Agent Intelligence autoriza o tipo de conhecimento. A autorização de qual pessoa ou empresa pode ser consultada continua sendo aplicada no dado de origem.
        </CardContent>
      </Card>

      {query.isLoading ? <div className="text-sm text-muted-foreground">Carregando Customer Intelligence…</div> : null}
      {query.error ? (
        <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          {query.error instanceof Error ? query.error.message : 'Erro ao carregar Customer Intelligence.'}
        </div>
      ) : null}

      {!query.isLoading && !query.error ? (
        <div className="space-y-3">
          {grupos.map(([chave, fontes]) => {
            const primeira = fontes[0];
            const expandida = aberta === chave;
            const maiorSensibilidade: CustomerKnowledgeGovernance['sensitivity'] = fontes.some((f) => f.sensitivity === 'sensitive')
              ? 'sensitive'
              : fontes.some((f) => f.sensitivity === 'personal')
                ? 'personal'
                : 'internal';
            return (
              <Card key={chave}>
                <button type="button" className="w-full text-left" onClick={() => setAberta(expandida ? null : chave)}>
                  <CardHeader>
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div>
                        <CardTitle className="flex items-center gap-2">
                          <UsersRound className="size-4" />
                          {primeira.collectionName}
                        </CardTitle>
                        <CardDescription className="mt-1">{primeira.description}</CardDescription>
                      </div>
                      <div className="flex flex-wrap gap-2">
                        {sensibilidade(maiorSensibilidade)}
                        <Badge variant="outline">{fontes.length} source{fontes.length === 1 ? '' : 's'}</Badge>
                      </div>
                    </div>
                  </CardHeader>
                </button>

                {expandida ? (
                  <CardContent>
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead>Source</TableHead>
                          <TableHead>Intelligence</TableHead>
                          <TableHead>Granularidade</TableHead>
                          <TableHead>Sensibilidade</TableHead>
                          <TableHead>Row scope</TableHead>
                          <TableHead>Usos</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {fontes.map((fonte) => (
                          <TableRow key={fonte.id}>
                            <TableCell>
                              <div className="flex items-center gap-2 font-mono text-xs">
                                <Database className="size-3.5 text-muted-foreground" />
                                {fonte.sourceSchema}.{fonte.sourceTable}
                              </div>
                              {fonte.description ? <div className="mt-1 max-w-xl text-xs text-muted-foreground">{fonte.description}</div> : null}
                            </TableCell>
                            <TableCell><Badge variant="outline">{fonte.intelligenceType}</Badge></TableCell>
                            <TableCell>{fonte.granularity}</TableCell>
                            <TableCell>{sensibilidade(fonte.sensitivity)}</TableCell>
                            <TableCell className="font-mono text-xs">{fonte.rowScopePolicy}</TableCell>
                            <TableCell>
                              <div className="flex max-w-sm flex-wrap gap-1">
                                {fonte.purposes.map((p) => <Badge key={p} variant="secondary">{p}</Badge>)}
                              </div>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </CardContent>
                ) : null}
              </Card>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}
