import { useMemo, useState } from 'react';
import {
  BookOpen,
  BrainCircuit,
  BriefcaseBusiness,
  Database,
  GitBranch,
  Layers3,
  Network,
  CircleGauge,
} from 'lucide-react';
import type { BusinessKnowledgeGovernance } from '@/contracts';
import { useLista } from '@/hooks/use-recurso';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
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

function IntegracaoPendente({
  titulo,
  descricao,
  caminho,
}: {
  titulo: string;
  descricao: string;
  caminho: string;
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Network className="size-4" />
          {titulo}
        </CardTitle>
        <CardDescription>{descricao}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
          A estrutura já existe em <code className="font-mono">business_strategy</code>, mas a API administrativa
          ainda não expõe este recurso para o navegador. A tela não simula nem copia o conteúdo para o front.
        </div>
        <div className="text-sm text-muted-foreground">
          Fluxo esperado quando a leitura estiver exposta: <span className="font-medium text-foreground">{caminho}</span>
        </div>
      </CardContent>
    </Card>
  );
}

function VisaoComoLer() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Como ler a inteligência</CardTitle>
        <CardDescription>
          Livro é fonte. Knowledge object é a unidade central. Problema/job é a porta de acesso e composição.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <div className="grid gap-3 md:grid-cols-4">
          <div className="rounded-lg border p-4">
            <div className="mb-2 flex items-center gap-2 font-semibold"><BriefcaseBusiness className="size-4" />Problema</div>
            <p className="text-sm text-muted-foreground">O que o consultor precisa ajudar a resolver.</p>
          </div>
          <div className="rounded-lg border p-4">
            <div className="mb-2 flex items-center gap-2 font-semibold"><BrainCircuit className="size-4" />Conhecimentos</div>
            <p className="text-sm text-muted-foreground">Objetos relevantes, vindos de uma ou várias fontes.</p>
          </div>
          <div className="rounded-lg border p-4">
            <div className="mb-2 flex items-center gap-2 font-semibold"><GitBranch className="size-4" />Relações</div>
            <p className="text-sm text-muted-foreground">Como modelos, métodos, regras e evidências se conectam.</p>
          </div>
          <div className="rounded-lg border p-4">
            <div className="mb-2 flex items-center gap-2 font-semibold"><BookOpen className="size-4" />Grounding</div>
            <p className="text-sm text-muted-foreground">De onde veio e onde voltar ao material original.</p>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

function VisaoCobertura() {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <CircleGauge className="size-4" />
          Cobertura e lacunas
        </CardTitle>
        <CardDescription>
          Cada problema deve mostrar não só quais conhecimentos existem, mas também o quanto a base atual sustenta uma resposta robusta e o que ainda falta aprender.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <div className="grid gap-3 md:grid-cols-3">
          <div className="rounded-lg border p-4">
            <div className="font-semibold">Cobertura forte</div>
            <p className="mt-1 text-sm text-muted-foreground">Há modelos, métodos e relações suficientes para orientar diagnóstico e decisão.</p>
          </div>
          <div className="rounded-lg border p-4">
            <div className="font-semibold">Cobertura parcial</div>
            <p className="mt-1 text-sm text-muted-foreground">A IA consegue ajudar, mas deve explicitar limites e conhecimentos complementares necessários.</p>
          </div>
          <div className="rounded-lg border p-4">
            <div className="font-semibold">Lacuna</div>
            <p className="mt-1 text-sm text-muted-foreground">O problema está mapeado, mas ainda não há base suficiente para recomendar com confiança.</p>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

function GovernancaTecnica({ fontes }: { fontes: BusinessKnowledgeGovernance[] }) {
  const grupos = useMemo(() => agrupado(fontes), [fontes]);
  const [aberta, setAberta] = useState<string | null>(null);

  return (
    <div className="space-y-3">
      <Card>
        <CardHeader>
          <CardTitle>Governança técnica</CardTitle>
          <CardDescription>
            Visão legada preservada para auditoria: mostra onde dados e coleções vivem. Não é mais a visão principal da inteligência.
          </CardDescription>
        </CardHeader>
      </Card>

      {grupos.map(([chave, itens]) => {
        const primeira = itens[0];
        const expandida = aberta === chave;
        const verticais = Array.from(new Set(itens.map((f) => f.vertical)));
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
                      <Database className="size-4" />
                      {primeira.collectionName}
                    </CardTitle>
                    <CardDescription className="mt-1">{primeira.description}</CardDescription>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {verticais.map((v) => <Badge key={v} variant="secondary">{v}</Badge>)}
                    <Badge variant="outline">{itens.length} source{itens.length === 1 ? '' : 's'}</Badge>
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
                    {itens.map((fonte) => (
                      <TableRow key={fonte.id}>
                        <TableCell>
                          <div className="flex items-center gap-2 font-mono text-xs">
                            <Database className="size-3.5 text-muted-foreground" />
                            {fonte.sourceSchema}.{fonte.sourceTable}
                          </div>
                          {fonte.description ? (
                            <div className="mt-1 max-w-2xl text-xs text-muted-foreground">{fonte.description}</div>
                          ) : null}
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
                  Clique para ver as tabelas de origem desta collection.
                </div>
              </CardContent>
            )}
          </Card>
        );
      })}
    </div>
  );
}

export function PaginaBusinessIntelligence() {
  const query = useLista('business_intelligence', { porPagina: 500 });

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Business Intelligence"
        descricao="Raio-X da inteligência consultiva: problemas que ela sabe resolver, conhecimentos que usa, relações entre eles e origem de cada ideia."
      />

      <VisaoComoLer />
      <VisaoCobertura />

      {query.isLoading ? <div className="text-sm text-muted-foreground">Carregando Business Intelligence…</div> : null}
      {query.error ? (
        <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          {query.error instanceof Error ? query.error.message : 'Erro ao carregar Business Intelligence.'}
        </div>
      ) : null}

      {!query.isLoading && !query.error ? (
        <Tabs defaultValue="problems">
          <TabsList className="flex h-auto flex-wrap">
            <TabsTrigger value="problems"><BriefcaseBusiness className="mr-1 size-4" />Problemas</TabsTrigger>
            <TabsTrigger value="knowledge"><BrainCircuit className="mr-1 size-4" />Conhecimento</TabsTrigger>
            <TabsTrigger value="sources"><BookOpen className="mr-1 size-4" />Fontes</TabsTrigger>
            <TabsTrigger value="governance"><Database className="mr-1 size-4" />Governança técnica</TabsTrigger>
          </TabsList>

          <TabsContent value="problems" className="mt-4">
            <IntegracaoPendente
              titulo="Problemas e jobs consultivos"
              descricao="A visão principal começa pelo problema. Cada job deve mostrar conhecimentos relevantes, dependências, fontes, nível de cobertura e lacunas da base."
              caminho="área de problema → job consultivo → cobertura/lacunas → conhecimentos relevantes → dependências entre jobs → groundings"
            />
          </TabsContent>

          <TabsContent value="knowledge" className="mt-4">
            <IntegracaoPendente
              titulo="Mapa de conhecimento"
              descricao="Exploração do grafo de knowledge objects, permitindo abrir relações sucessivamente sem impor uma árvore fixa."
              caminho="knowledge object → objetos relacionados → papel da relação → groundings"
            />
          </TabsContent>

          <TabsContent value="sources" className="mt-4">
            <IntegracaoPendente
              titulo="Fontes e material original"
              descricao="A fonte entra como provenance e auditoria. O usuário deve conseguir voltar do conceito ao livro, seção e grounding original."
              caminho="knowledge object → grounding → seção/página → fonte original"
            />
          </TabsContent>

          <TabsContent value="governance" className="mt-4">
            <GovernancaTecnica fontes={query.data?.itens ?? []} />
          </TabsContent>
        </Tabs>
      ) : null}
    </div>
  );
}
