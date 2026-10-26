import { useMemo, useState } from 'react';
import { BriefcaseBusiness, Database, Layers3 } from 'lucide-react';
import type { BusinessKnowledgeGovernance } from '@/contracts';
import { useLista } from '@/hooks/use-recurso';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

function agrupado(itens: BusinessKnowledgeGovernance[]) {
  const mapa = new Map<string, BusinessKnowledgeGovernance[]>();
  for (const item of itens) {
    const atual = mapa.get(item.collectionKey) ?? [];
    atual.push(item);
    mapa.set(item.collectionKey, atual);
  }
  return Array.from(mapa.entries()).sort((a, b) =>
    a[1][0].collectionName.localeCompare(b[1][0].collectionName, 'pt-BR'),
  );
}

export function PaginaBusinessIntelligence() {
  const query = useLista('business_intelligence', { porPagina: 500 });
  const grupos = useMemo(() => agrupado(query.data?.itens ?? []), [query.data?.itens]);
  const [aberta, setAberta] = useState<string | null>(null);

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Business Intelligence"
        descricao="Mapa de governança do conhecimento de produto, oferta, comercial e operação. O conteúdo continua nas tabelas de origem; esta camada apenas diz onde ele vive e como deve ser usado."
      />

      {query.isLoading ? <div className="text-sm text-muted-foreground">Carregando Business Intelligence…</div> : null}
      {query.error ? (
        <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          {query.error instanceof Error ? query.error.message : 'Erro ao carregar Business Intelligence.'}
        </div>
      ) : null}

      {!query.isLoading && !query.error ? (
        <div className="space-y-3">
          {grupos.map(([chave, fontes]) => {
            const primeira = fontes[0];
            const expandida = aberta === chave;
            const verticais = Array.from(new Set(fontes.map((f) => f.vertical)));
            return (
              <Card key={chave}>
                <button
                  type="button"
                  className="w-full text-left"
                  onClick={() => setAberta(expandida ? null : chave)}
                >
                  <CardHeader>
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div>
                        <CardTitle className="flex items-center gap-2">
                          <BriefcaseBusiness className="size-4" />
                          {primeira.collectionName}
                        </CardTitle>
                        <CardDescription className="mt-1">{primeira.description}</CardDescription>
                      </div>
                      <div className="flex flex-wrap gap-2">
                        {verticais.map((v) => <Badge key={v} variant="secondary">{v}</Badge>)}
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
                          <TableHead>Tipo</TableHead>
                          <TableHead>Filtro</TableHead>
                          <TableHead>Retrieval</TableHead>
                          <TableHead>Prioridade</TableHead>
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
                              {fonte.description ? <div className="mt-1 max-w-2xl text-xs text-muted-foreground">{fonte.description}</div> : null}
                            </TableCell>
                            <TableCell><Badge variant="outline">{fonte.knowledgeType}</Badge></TableCell>
                            <TableCell className="max-w-md font-mono text-xs text-muted-foreground">
                              {Object.keys(fonte.sourceFilter).length ? JSON.stringify(fonte.sourceFilter) : '—'}
                            </TableCell>
                            <TableCell>{fonte.retrievable ? <Badge variant="sucesso">ON</Badge> : <Badge variant="secondary">OFF</Badge>}</TableCell>
                            <TableCell className="tabular">{fonte.priority}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </CardContent>
                ) : (
                  <CardContent className="pt-0">
                    <div className="flex items-center gap-2 text-xs text-muted-foreground">
                      <Layers3 className="size-3.5" />
                      Clique para ver exatamente quais tabelas alimentam esta knowledge.
                    </div>
                  </CardContent>
                )}
              </Card>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}
