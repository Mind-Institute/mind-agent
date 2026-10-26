import { useMemo, useState } from 'react';
import { BookOpen, Boxes, Database, Search, Sparkles } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import type { AgentKnowledgeAccess } from '@/contracts';
import { useLista } from '@/hooks/use-recurso';
import { useSessao } from '@/hooks/use-sessao';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { enderecoDoKnowledge } from '@/services/provider-context';

type ResultadoBusca = {
  id: string;
  texto: string;
  insightType: string;
  baseNaFonte: string;
  evidenceStatus: string;
  causalStatus: string;
  localizadorFonte?: string | null;
  collections?: string[];
  source?: {
    title?: string;
    authors?: string[];
    year?: number;
    studyDesign?: string | null;
    methodologicalQuality?: string | null;
  };
  section?: { title?: string | null };
  retrieval?: { hybridScore?: number | null };
};

function rotuloAgente(chave: string) {
  const mapa: Record<string, string> = {
    knowledge_admin: 'Knowledge Admin',
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

function RagPlayground({ accesses }: { accesses: AgentKnowledgeAccess[] }) {
  const sessao = useSessao();
  const [query, setQuery] = useState('segurança psicológica aprendizagem performance');
  const [agentKey, setAgentKey] = useState('knowledge_admin');
  const [resultados, setResultados] = useState<ResultadoBusca[]>([]);
  const [mode, setMode] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [buscando, setBuscando] = useState(false);
  const [indexando, setIndexando] = useState(false);
  const [statusIndexacao, setStatusIndexacao] = useState<string | null>(null);

  const agentes = useMemo(() => {
    const existentes = Array.from(new Set(accesses.map((a) => a.agentKey))).filter((a) => a !== 'knowledge_admin');
    return ['knowledge_admin', ...existentes];
  }, [accesses]);

  async function headers() {
    const token = await sessao.obterToken();
    if (!token) throw new Error('Sessão ausente.');
    const chave = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();
    return {
      Authorization: `Bearer ${token}`,
      ...(chave ? { apikey: chave } : {}),
      'Content-Type': 'application/json',
    };
  }

  async function buscar() {
    if (query.trim().length < 2) return;
    setBuscando(true);
    setErro(null);
    try {
      const base = enderecoDoKnowledge();
      if (!base) throw new Error('Knowledge API não configurada.');
      const resposta = await fetch(`${base}/admin/knowledge_search`, {
        method: 'POST',
        headers: await headers(),
        body: JSON.stringify({ query: query.trim(), agentKey, limit: 12 }),
      });
      const payload = await resposta.json().catch(() => ({})) as { itens?: ResultadoBusca[]; mode?: string; mensagem?: string };
      if (!resposta.ok) throw new Error(payload.mensagem ?? 'Não foi possível buscar.');
      setResultados(payload.itens ?? []);
      setMode(payload.mode ?? null);
    } catch (e) {
      setResultados([]);
      setErro(e instanceof Error ? e.message : 'Não foi possível buscar.');
    } finally {
      setBuscando(false);
    }
  }

  async function indexar() {
    setIndexando(true);
    setErro(null);
    setStatusIndexacao(null);
    try {
      const supabaseUrl = import.meta.env.VITE_SUPABASE_URL?.trim().replace(/\/+$/, '');
      if (!supabaseUrl) throw new Error('Supabase não configurado.');
      const resposta = await fetch(`${supabaseUrl}/functions/v1/mindagent-index-global-knowledge`, {
        method: 'POST',
        headers: await headers(),
        body: JSON.stringify({ limit: 200 }),
      });
      const payload = await resposta.json().catch(() => ({})) as { processados?: number; restantes?: string | number; model?: string; mensagem?: string };
      if (!resposta.ok) throw new Error(payload.mensagem ?? 'Não foi possível indexar.');
      setStatusIndexacao(`${payload.processados ?? 0} embeddings processados · ${payload.model ?? 'modelo não informado'} · restantes: ${payload.restantes ?? 'não informado'}`);
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível indexar.');
    } finally {
      setIndexando(false);
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>RAG Playground</CardTitle>
          <CardDescription>Testa o corpus científico e metodológico global do Mind com provenance e filtros de acesso.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-3 lg:grid-cols-[minmax(0,1fr)_260px_auto]">
            <Input value={query} onChange={(e) => setQuery(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') void buscar(); }} />
            <Select value={agentKey} onValueChange={setAgentKey}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {agentes.map((a) => <SelectItem key={a} value={a}>{rotuloAgente(a)}</SelectItem>)}
              </SelectContent>
            </Select>
            <Button onClick={() => void buscar()} disabled={buscando || query.trim().length < 2}>
              <Search className="mr-2 size-4" />{buscando ? 'Buscando…' : 'Buscar'}
            </Button>
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <Button variant="outline" onClick={() => void indexar()} disabled={indexando || !sessao.pode('editar')}>
              <Sparkles className="mr-2 size-4" />{indexando ? 'Indexando…' : 'Gerar embeddings pendentes'}
            </Button>
            {mode ? <Badge variant="secondary">retrieval: {mode}</Badge> : null}
            {statusIndexacao ? <span className="text-xs text-muted-foreground">{statusIndexacao}</span> : null}
          </div>
          {erro ? <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">{erro}</div> : null}
        </CardContent>
      </Card>

      {resultados.map((r, indice) => (
        <Card key={r.id}>
          <CardHeader className="pb-3">
            <div className="flex flex-wrap gap-2">
              <Badge>#{indice + 1}</Badge><Badge variant="secondary">{r.insightType}</Badge>
              <Badge variant="outline">{r.evidenceStatus}</Badge><Badge variant="outline">{r.causalStatus}</Badge>
            </div>
            <CardTitle className="text-base leading-6">{r.texto}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <div><span className="font-medium">{r.source?.title ?? 'Fonte sem título'}</span>{r.source?.year ? <span className="text-muted-foreground"> · {r.source.year}</span> : null}</div>
            <div className="text-xs text-muted-foreground">{r.section?.title ? `${r.section.title} · ` : ''}{r.localizadorFonte ?? 'sem localizador'}</div>
            <div className="flex flex-wrap gap-1">{(r.collections ?? []).map((x) => <Badge key={x} variant="secondary">{x}</Badge>)}</div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

export function PaginaKnowledge() {
  const navigate = useNavigate();
  const collections = useLista('knowledge_collections', { porPagina: 500, ordenar: 'nome' });
  const sources = useLista('knowledge_sources', { porPagina: 500, ordenar: '-atualizadoEm' });
  const assets = useLista('knowledge_assets', { porPagina: 500, ordenar: '-atualizadoEm' });
  const accesses = useLista('agent_knowledge_access', { porPagina: 500 });
  const [tab, setTab] = useState('collections');
  const [collection, setCollection] = useState<string | null>(null);

  const fontes = useMemo(() => {
    const itens = sources.data?.itens ?? [];
    return collection ? itens.filter((s) => s.collections.some((c) => c.chave === collection)) : itens;
  }, [sources.data?.itens, collection]);

  const assetsFiltrados = useMemo(() => {
    const itens = assets.data?.itens ?? [];
    return collection ? itens.filter((a) => a.collections.some((c) => c.chave === collection)) : itens;
  }, [assets.data?.itens, collection]);

  const carregando = collections.isLoading || sources.isLoading || assets.isLoading || accesses.isLoading;
  const erro = collections.error || sources.error || assets.error || accesses.error;

  function abrirSources(chave: string) {
    setCollection(chave);
    setTab('sources');
  }

  function abrirAssets(chave: string) {
    setCollection(chave);
    setTab('assets');
  }

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Global Knowledge"
        descricao="Conhecimento científico, evidência, metodologia e frameworks transversais do Mind. Conhecimento específico de produto e cliente vive nas áreas próprias."
      />

      {carregando ? <div className="text-sm text-muted-foreground">Carregando Global Knowledge…</div> : null}
      {erro ? <div className="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-800">{erro instanceof Error ? erro.message : 'Erro ao carregar Global Knowledge.'}</div> : null}

      {!carregando && !erro ? (
        <Tabs value={tab} onValueChange={setTab}>
          <TabsList>
            <TabsTrigger value="collections"><Boxes className="mr-1 size-4" />Collections</TabsTrigger>
            <TabsTrigger value="sources"><BookOpen className="mr-1 size-4" />Sources</TabsTrigger>
            <TabsTrigger value="assets"><Database className="mr-1 size-4" />Assets</TabsTrigger>
            <TabsTrigger value="playground"><Search className="mr-1 size-4" />Playground</TabsTrigger>
          </TabsList>

          <TabsContent value="collections" className="mt-4">
            <Card>
              <CardHeader>
                <CardTitle>Collections</CardTitle>
                <CardDescription>Clique em uma collection ou em seus números para entender o que existe por trás dela.</CardDescription>
              </CardHeader>
              <CardContent>
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Collection</TableHead>
                      <TableHead>Acesso padrão</TableHead>
                      <TableHead className="text-right">Sources</TableHead>
                      <TableHead className="text-right">Assets</TableHead>
                      <TableHead className="text-right">Agents on</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {(collections.data?.itens ?? []).map((c) => (
                      <TableRow key={c.id}>
                        <TableCell>
                          <button type="button" className="text-left" onClick={() => abrirSources(c.chave)}>
                            <div className="font-semibold underline-offset-4 hover:underline">{c.nome}</div>
                            <div className="font-mono text-xs text-muted-foreground">{c.chave}</div>
                            {c.descricao ? <div className="mt-1 max-w-2xl text-xs text-muted-foreground">{c.descricao}</div> : null}
                          </button>
                        </TableCell>
                        <TableCell><Badge variant={c.acessoPadrao === 'mind_only' ? 'atencao' : 'sucesso'}>{acessoLabel(c.acessoPadrao)}</Badge></TableCell>
                        <TableCell className="text-right"><Button variant="ghost" size="sm" onClick={() => abrirSources(c.chave)}>{c.sources}</Button></TableCell>
                        <TableCell className="text-right"><Button variant="ghost" size="sm" onClick={() => abrirAssets(c.chave)}>{c.assets}</Button></TableCell>
                        <TableCell className="text-right"><Button variant="ghost" size="sm" onClick={() => navigate(`/agent-intelligence?namespace=global&knowledge=${encodeURIComponent(c.chave)}`)}>{c.agents}</Button></TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="sources" className="mt-4">
            <Card>
              <CardHeader>
                <CardTitle>{collection ? `Sources · ${collections.data?.itens.find((x) => x.chave === collection)?.nome ?? collection}` : 'Sources'}</CardTitle>
                <CardDescription>Fontes registradas no Global Knowledge. O conteúdo de produto não aparece mais aqui.</CardDescription>
              </CardHeader>
              <CardContent>
                <Table>
                  <TableHeader>
                    <TableRow><TableHead>Source</TableHead><TableHead>Origem</TableHead><TableHead>Collections</TableHead><TableHead>Acesso</TableHead></TableRow>
                  </TableHeader>
                  <TableBody>
                    {fontes.map((s) => (
                      <TableRow key={s.id}>
                        <TableCell>
                          <div className="font-semibold">{s.titulo}</div>
                          <div className="text-xs text-muted-foreground">
                            {[s.tipoFonte, s.autores.join(', '), s.ano].filter(Boolean).join(' · ') || 'fonte canônica'}
                          </div>
                        </TableCell>
                        <TableCell>
                          <div className="text-xs">{s.evidenceRole ?? '—'}</div>
                          <div className="font-mono text-xs text-muted-foreground">{s.doi ?? s.isbn ?? s.drivePath ?? '—'}</div>
                        </TableCell>
                        <TableCell><div className="flex flex-wrap gap-1">{s.collections.map((c) => <Badge key={c.chave} variant="secondary">{c.nome}</Badge>)}</div></TableCell>
                        <TableCell><Badge variant={s.acesso === 'mind_only' ? 'atencao' : 'sucesso'}>{acessoLabel(s.acesso)}</Badge></TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="assets" className="mt-4">
            <Card>
              <CardHeader>
                <CardTitle>{collection ? `Assets · ${collections.data?.itens.find((x) => x.chave === collection)?.nome ?? collection}` : 'Assets'}</CardTitle>
                <CardDescription>
                  Assets são os ponteiros do control plane para unidades recuperáveis de conhecimento. Uma Source é a obra/documento canônico; um Asset pode representar essa fonte ou, futuramente, uma unidade derivada/estrutural sem duplicar o conteúdo.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <Table>
                  <TableHeader>
                    <TableRow><TableHead>Asset</TableHead><TableHead>Origem física</TableHead><TableHead>Tipo</TableHead><TableHead>Collections</TableHead></TableRow>
                  </TableHeader>
                  <TableBody>
                    {assetsFiltrados.map((a) => (
                      <TableRow key={a.id}>
                        <TableCell><div className="font-semibold">{a.titulo}</div></TableCell>
                        <TableCell className="font-mono text-xs">{a.originSchema}.{a.originTable} · {a.originId}</TableCell>
                        <TableCell><Badge variant="outline">{a.assetType}</Badge></TableCell>
                        <TableCell><div className="flex flex-wrap gap-1">{a.collections.map((x) => <Badge key={x.chave} variant={x.principal ? 'default' : 'secondary'}>{x.nome}</Badge>)}</div></TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="playground" className="mt-4">
            <RagPlayground accesses={accesses.data?.itens ?? []} />
          </TabsContent>
        </Tabs>
      ) : null}
    </div>
  );
}
