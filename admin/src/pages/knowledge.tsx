import { useMemo, useState } from 'react';
import { AlertTriangle, BookOpen, Boxes, Bot, Database, ShieldCheck } from 'lucide-react';
import type { AgentKnowledgeAccess, KnowledgeAsset, KnowledgeCollection } from '@/contracts';
import { useAtualizar, useLista } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Switch } from '@/components/ui/switch';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

const AGENTES_PREFERIDOS = [
  'concierge_summit',
  'summit_b2c',
  'summit_b2b',
  'institute',
  'dash',
  'cliente_suporte',
];

function rotuloAgente(chave: string) {
  const mapa: Record<string, string> = {
    concierge_summit: 'Concierge Summit',
    summit_b2c: 'Summit B2C',
    summit_b2b: 'Summit B2B',
    institute: 'Institute',
    dash: 'Dash',
    cliente_suporte: 'Suporte',
  };
  return mapa[chave] ?? chave;
}

function acessoLabel(v: 'mind_only' | 'mind_public') {
  return v === 'mind_only' ? 'Mind only' : 'Mind + public';
}

function Resumo({
  collections,
  assets,
  accesses,
}: {
  collections: KnowledgeCollection[];
  assets: KnowledgeAsset[];
  accesses: AgentKnowledgeAccess[];
}) {
  const pendencias = assets.filter((a) => a.pendenciaDecisao).length + accesses.filter((a) => a.pendenciaDecisao).length;
  const agentes = new Set(accesses.map((a) => a.agentKey)).size;
  const mindOnly = assets.filter((a) => a.acesso === 'mind_only').length;

  const cards = [
    { titulo: 'Collections', valor: collections.length, detalhe: 'taxonomia viva de routing', icone: Boxes },
    { titulo: 'Knowledge assets', valor: assets.length, detalhe: 'fontes, sessões e materiais', icone: Database },
    { titulo: 'Agentes', valor: agentes, detalhe: 'com matriz de conhecimento', icone: Bot },
    { titulo: 'Mind only', valor: mindOnly, detalhe: 'assets protegidos por padrão', icone: ShieldCheck },
    { titulo: 'Pendências', valor: pendencias, detalhe: 'decisões reservadas à Adriana', icone: AlertTriangle },
  ];

  return (
    <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-5">
      {cards.map(({ titulo, valor, detalhe, icone: Icone }) => (
        <Card key={titulo}>
          <CardHeader className="pb-2">
            <div className="flex items-center justify-between">
              <CardDescription>{titulo}</CardDescription>
              <Icone className="size-4 text-muted-foreground" />
            </div>
            <CardTitle className="text-2xl">{valor}</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-xs text-muted-foreground">{detalhe}</p>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

function TabelaCollections({ itens }: { itens: KnowledgeCollection[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Collections</CardTitle>
        <CardDescription>
          Domínios de governança e routing. Uma fonte ou asset pode pertencer a várias collections.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Collection</TableHead>
              <TableHead>Acesso padrão</TableHead>
              <TableHead className="text-right">Sources</TableHead>
              <TableHead className="text-right">Assets</TableHead>
              <TableHead className="text-right">Agentes ON</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {itens.map((c) => (
              <TableRow key={c.id}>
                <TableCell>
                  <div className="font-semibold">{c.nome}</div>
                  <div className="font-mono text-xs text-muted-foreground">{c.chave}</div>
                  {c.descricao ? <div className="mt-1 max-w-2xl text-xs text-muted-foreground">{c.descricao}</div> : null}
                </TableCell>
                <TableCell>
                  <Badge variant={c.acessoPadrao === 'mind_only' ? 'atencao' : 'sucesso'}>
                    {acessoLabel(c.acessoPadrao)}
                  </Badge>
                </TableCell>
                <TableCell className="text-right tabular">{c.sources}</TableCell>
                <TableCell className="text-right tabular">{c.assets}</TableCell>
                <TableCell className="text-right tabular">{c.agents}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

function TabelaAssets({ itens }: { itens: KnowledgeAsset[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Knowledge assets</CardTitle>
        <CardDescription>
          O control plane aponta para conteúdo que continua morando em seu schema de origem.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Asset</TableHead>
              <TableHead>Origem</TableHead>
              <TableHead>Collections</TableHead>
              <TableHead>Acesso</TableHead>
              <TableHead>Pendência</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {itens.map((a) => (
              <TableRow key={a.id}>
                <TableCell>
                  <div className="font-semibold">{a.titulo}</div>
                  <div className="text-xs text-muted-foreground">{a.assetType}</div>
                </TableCell>
                <TableCell className="font-mono text-xs">
                  {a.originSchema}.{a.originTable}
                </TableCell>
                <TableCell>
                  <div className="flex max-w-xl flex-wrap gap-1">
                    {a.collections.map((c) => (
                      <Badge key={c.chave} variant={c.principal ? 'default' : 'secondary'}>
                        {c.nome}
                      </Badge>
                    ))}
                  </div>
                </TableCell>
                <TableCell>
                  <Badge variant={a.acesso === 'mind_only' ? 'atencao' : 'sucesso'}>
                    {acessoLabel(a.acesso)}
                  </Badge>
                </TableCell>
                <TableCell className="max-w-sm text-xs text-muted-foreground">
                  {a.pendenciaDecisao ?? '—'}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

function MatrizAgentes({
  collections,
  accesses,
}: {
  collections: KnowledgeCollection[];
  accesses: AgentKnowledgeAccess[];
}) {
  const sessao = useSessao();
  const atualizar = useAtualizar('agent_knowledge_access');
  const [erro, setErro] = useState<string | null>(null);

  const agentes = useMemo(() => {
    const presentes = Array.from(new Set(accesses.map((a) => a.agentKey)));
    return [...AGENTES_PREFERIDOS.filter((a) => presentes.includes(a)), ...presentes.filter((a) => !AGENTES_PREFERIDOS.includes(a))];
  }, [accesses]);

  const mapa = useMemo(
    () => new Map(accesses.map((a) => [`${a.agentKey}::${a.collectionKey}`, a])),
    [accesses],
  );

  async function alternar(acesso: AgentKnowledgeAccess, ligado: boolean) {
    setErro(null);
    try {
      await atualizar.mutateAsync({
        id: acesso.id,
        payload: {
          enabled: ligado,
          prioridade: acesso.prioridade,
          acessoMaximo: acesso.acessoMaximo,
        },
        opcoes: { atualizadoEmEsperado: acesso.atualizadoEm },
      });
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível salvar.');
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Agente × Knowledge</CardTitle>
        <CardDescription>
          O switch controla eligibility de retrieval por collection. A autorização é aplicada antes da busca.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {erro ? <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">{erro}</div> : null}
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="min-w-56">Collection</TableHead>
              {agentes.map((a) => <TableHead key={a} className="text-center">{rotuloAgente(a)}</TableHead>)}
            </TableRow>
          </TableHeader>
          <TableBody>
            {collections.map((collection) => (
              <TableRow key={collection.chave}>
                <TableCell>
                  <div className="font-semibold">{collection.nome}</div>
                  <div className="font-mono text-xs text-muted-foreground">{collection.chave}</div>
                </TableCell>
                {agentes.map((agent) => {
                  const acesso = mapa.get(`${agent}::${collection.chave}`);
                  return (
                    <TableCell key={agent} className="text-center">
                      {acesso ? (
                        <div className="flex flex-col items-center gap-1">
                          <Switch
                            checked={acesso.enabled}
                            disabled={!sessao.pode('editar') || atualizar.isPending}
                            onCheckedChange={(v) => void alternar(acesso, v)}
                            aria-label={`${rotuloAgente(agent)}: ${collection.nome}`}
                          />
                          <span className="text-[10px] text-muted-foreground">
                            {acesso.acessoMaximo === 'mind_only' ? 'Mind' : 'Public'}
                          </span>
                          {acesso.pendenciaDecisao ? <AlertTriangle className="size-3 text-amber-600" aria-label="Há decisão pendente" /> : null}
                        </div>
                      ) : (
                        <span className="text-xs text-muted-foreground">—</span>
                      )}
                    </TableCell>
                  );
                })}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}

export function PaginaKnowledge() {
  const collections = useLista('knowledge_collections', { porPagina: 500, ordenar: 'nome' });
  const assets = useLista('knowledge_assets', { porPagina: 500, ordenar: '-atualizadoEm' });
  const accesses = useLista('agent_knowledge_access', { porPagina: 500 });

  const carregando = collections.isLoading || assets.isLoading || accesses.isLoading;
  const erro = collections.error || assets.error || accesses.error;

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Knowledge"
        descricao="Control plane do conhecimento do Mind: sources, assets, collections, acesso por agente e decisões pendentes sem mover o conteúdo de seus schemas de origem."
      />

      {carregando ? <div className="text-sm text-muted-foreground">Carregando Knowledge…</div> : null}
      {erro ? <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">{erro instanceof Error ? erro.message : 'Erro ao carregar Knowledge.'}</div> : null}

      {!carregando && !erro ? (
        <>
          <Resumo
            collections={collections.data?.itens ?? []}
            assets={assets.data?.itens ?? []}
            accesses={accesses.data?.itens ?? []}
          />

          <Tabs defaultValue="collections">
            <TabsList>
              <TabsTrigger value="collections"><Boxes className="mr-1 size-4" />Collections</TabsTrigger>
              <TabsTrigger value="assets"><BookOpen className="mr-1 size-4" />Assets</TabsTrigger>
              <TabsTrigger value="agents"><Bot className="mr-1 size-4" />Agents</TabsTrigger>
            </TabsList>
            <TabsContent value="collections" className="mt-4">
              <TabelaCollections itens={collections.data?.itens ?? []} />
            </TabsContent>
            <TabsContent value="assets" className="mt-4">
              <TabelaAssets itens={assets.data?.itens ?? []} />
            </TabsContent>
            <TabsContent value="agents" className="mt-4">
              <MatrizAgentes
                collections={collections.data?.itens ?? []}
                accesses={accesses.data?.itens ?? []}
              />
            </TabsContent>
          </Tabs>
        </>
      ) : null}
    </div>
  );
}
