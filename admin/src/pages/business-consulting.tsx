import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { BookOpen, Boxes, Link2, Quote, Search } from 'lucide-react';
import { useSessao } from '@/hooks/use-sessao';
import {
  buscarBusinessConsulting,
  buscarObjetoConsulting,
  type LivroConsulting,
  type ObjetoConsulting,
} from '@/services/business-consulting';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ArvoreConhecimento } from '@/components/admin/arvore-conhecimento';
import { ConsultingJobsPanel } from '@/components/admin/consulting-jobs-panel';
import { BusinessIngestionPanel } from '@/components/admin/business-ingestion-panel';

/* BUSINESS CONSULTING KNOWLEDGE (pedido da Adriana, 24/10/2026). O conhecimento que o agente
   consultor interno — que só fala com ela e com o time — usa para aconselhar: livros de business
   ingeridos pelo ChatGPT em `business_strategy`, quebrados em objetos (modelos, princípios,
   métodos, métricas) com a página de onde vieram e as relações entre eles. Diferente do Global
   Knowledge, que é conteúdo para os agentes que falam com o público. Somente leitura. */

const normalizar = (valor: string) =>
  valor.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

const legivel = (valor: string) => valor.replaceAll('_', ' ');

function paginas(inicio: number | null, fim: number | null) {
  if (inicio == null) return null;
  return fim != null && fim !== inicio ? `p. ${inicio}–${fim}` : `p. ${inicio}`;
}

function objetoCombina(objeto: ObjetoConsulting, termo: string) {
  if (!termo) return true;
  const alvo = [objeto.nome, objeto.tipo, objeto.resumo ?? '', objeto.escopo ?? '', objeto.capitulo ?? '',
    ...(objeto.topicos ?? [])].join(' ');
  return normalizar(alvo).includes(normalizar(termo));
}

export function PaginaBusinessConsulting() {
  const { simulada, obterToken, marcarSessaoExpirada } = useSessao();
  const [busca, setBusca] = useState('');
  const [familia, setFamilia] = useState('todas');
  const [livro, setLivro] = useState('todos');
  const [aberto, setAberto] = useState<string | null>(null);

  const token = async () => {
    const t = await obterToken();
    if (!t) {
      marcarSessaoExpirada();
      throw new Error('Sessão expirada. Entre novamente.');
    }
    return t;
  };

  const consulta = useQuery({
    queryKey: ['business-consulting', simulada],
    enabled: !simulada,
    queryFn: async ({ signal }) => buscarBusinessConsulting({ token: await token(), sinal: signal }),
    refetchOnWindowFocus: true,
    // A ingestão está em curso: a tela acompanha os livros entrando.
    refetchInterval: 60_000,
  });

  const livros = consulta.data?.livros ?? [];
  const objetos = consulta.data?.objetos ?? [];
  const familias = useMemo(() => [...new Set(objetos.map((o) => o.familia))].sort(), [objetos]);
  const filtrados = useMemo(
    () => objetos.filter((o) =>
      (familia === 'todas' || o.familia === familia) &&
      (livro === 'todos' || o.livro_id === livro) &&
      objetoCombina(o, busca)),
    [objetos, familia, livro, busca],
  );
  const tituloDoLivro = useMemo(() => new Map(livros.map((l) => [l.id, l.titulo])), [livros]);

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Business Consulting Knowledge"
        descricao="Inteligência consultiva organizada por problemas e jobs. Knowledge objects são a unidade central; livros permanecem como provenance e auditoria."
      />

      {simulada ? (
        <p role="status">Conecte o painel ao Supabase para consultar o Business Consulting Knowledge.</p>
      ) : consulta.isPending ? (
        <p role="status">Carregando Business Consulting Knowledge…</p>
      ) : consulta.isError ? (
        <div role="alert" className="space-y-2">
          <p>Não foi possível consultar o Business Consulting Knowledge.</p>
          <button type="button" className="text-sm font-semibold underline" onClick={() => void consulta.refetch()}>
            Tentar novamente
          </button>
        </div>
      ) : null}

      {consulta.data ? (
        <>
          <section className="grid gap-3 md:grid-cols-4" aria-label="Resumo do conhecimento">
            <ResumoCard icone={BookOpen} rotulo="Livros" valor={consulta.data.totais.livros} />
            <ResumoCard icone={Boxes} rotulo="Objetos de conhecimento" valor={consulta.data.totais.objetos} />
            <ResumoCard icone={Quote} rotulo="Citações com página" valor={consulta.data.totais.citacoes} />
            <ResumoCard icone={Link2} rotulo="Relações entre objetos" valor={consulta.data.totais.relacoes} />
          </section>

          <ConsultingJobsPanel jobs={consulta.data.jobs} abrirObjeto={setAberto} />

          <Card>
            <CardHeader>
              <CardTitle>Fontes</CardTitle>
              <CardDescription>Provenance e auditoria: o que já foi ingerido e quanto de cada fonte está processado.</CardDescription>
            </CardHeader>
            <CardContent>
              {livros.length === 0 ? (
                <p className="text-sm text-muted-foreground">Nenhum livro ingerido ainda.</p>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Livro</TableHead>
                      <TableHead>Seções processadas</TableHead>
                      <TableHead>Objetos</TableHead>
                      <TableHead>Status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {livros.map((l) => <LinhaLivro key={l.id} livro={l} />)}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>

          <Tabs defaultValue="arvore" className="space-y-4">
            <TabsList>
              <TabsTrigger value="arvore">Árvore</TabsTrigger>
              <TabsTrigger value="lista">Lista</TabsTrigger>
            </TabsList>

            <TabsContent value="arvore" className="space-y-3">
              <p className="text-sm text-muted-foreground">
                Abra o livro, depois um capítulo, depois um objeto: cada objeto abre o que está ligado a ele.
                Clique no nome para ver a ficha completa, com a página de onde veio.
              </p>
              <ArvoreConhecimento dados={consulta.data} aoAbrirFicha={setAberto} />
            </TabsContent>

            <TabsContent value="lista" className="space-y-6">
          <section className="space-y-3" aria-label="Filtros">
            <div className="relative max-w-2xl">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                value={busca}
                onChange={(e) => setBusca(e.target.value)}
                placeholder="Buscar modelo, princípio, método, tópico ou capítulo…"
                className="pl-9"
              />
            </div>
            <div className="flex flex-wrap gap-2">
              <Filtro ativo={familia === 'todas'} onClick={() => setFamilia('todas')}>
                Todas as famílias ({objetos.length})
              </Filtro>
              {familias.map((f) => (
                <Filtro key={f} ativo={familia === f} onClick={() => setFamilia(f)}>
                  {f} ({objetos.filter((o) => o.familia === f).length})
                </Filtro>
              ))}
            </div>
            {livros.length > 1 ? (
              <div className="flex flex-wrap gap-2">
                <Filtro ativo={livro === 'todos'} onClick={() => setLivro('todos')}>Todos os livros</Filtro>
                {livros.map((l) => (
                  <Filtro key={l.id} ativo={livro === l.id} onClick={() => setLivro(l.id)}>{l.titulo}</Filtro>
                ))}
              </div>
            ) : null}
          </section>

          <section className="space-y-3" aria-label="Objetos de conhecimento">
            <p className="text-sm text-muted-foreground">
              {filtrados.length} de {objetos.length} objetos exibidos. Clique em um para ver de onde veio e com o que se relaciona.
            </p>
            <div className="grid gap-3 xl:grid-cols-2">
              {filtrados.map((o) => (
                <button
                  key={o.id}
                  type="button"
                  onClick={() => setAberto(o.id)}
                  className="rounded-lg border bg-card p-4 text-left transition-colors hover:bg-muted/40"
                >
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-bold">{o.nome}</span>
                    <Badge variant="outline">{o.familia}</Badge>
                    <Badge variant="neutro">{legivel(o.tipo)}</Badge>
                  </div>
                  {o.resumo ? <p className="mt-2 text-sm leading-6 text-muted-foreground">{o.resumo}</p> : null}
                  <p className="mt-2 text-xs text-muted-foreground">
                    {tituloDoLivro.get(o.livro_id) ?? ''}{o.capitulo ? ` · ${o.capitulo}` : ''}
                  </p>
                </button>
              ))}
            </div>
          </section>
            </TabsContent>
          </Tabs>

          <BusinessIngestionPanel />
        </>
      ) : null}

      <DetalheObjeto id={aberto} aoFechar={() => setAberto(null)} aoAbrir={setAberto} token={token} />
    </div>
  );
}

function LinhaLivro({ livro }: { livro: LivroConsulting }) {
  return (
    <TableRow>
      <TableCell>
        <p className="font-semibold">{livro.titulo}</p>
        <p className="text-xs text-muted-foreground">
          {(livro.autores ?? []).join(', ')}{livro.paginas ? ` · ${livro.paginas} páginas` : ''}
        </p>
      </TableCell>
      <TableCell className="tabular-nums">{livro.secoes_processadas} de {livro.secoes}</TableCell>
      <TableCell className="tabular-nums">{livro.objetos}</TableCell>
      <TableCell>{livro.status ? <Badge variant="neutro">{legivel(livro.status)}</Badge> : null}</TableCell>
    </TableRow>
  );
}

function DetalheObjeto({
  id,
  aoFechar,
  aoAbrir,
  token,
}: {
  id: string | null;
  aoFechar: () => void;
  aoAbrir: (id: string) => void;
  token: () => Promise<string>;
}) {
  const detalhe = useQuery({
    queryKey: ['business-consulting', 'objeto', id],
    enabled: id !== null,
    queryFn: async ({ signal }) => buscarObjetoConsulting(id!, { token: await token(), sinal: signal }),
  });
  const d = detalhe.data;

  return (
    <Sheet open={id !== null} onOpenChange={(abrir) => { if (!abrir) aoFechar(); }}>
      <SheetContent className="overflow-y-auto">
        <SheetHeader>
          <SheetTitle>{d?.objeto.nome ?? 'Carregando…'}</SheetTitle>
          <SheetDescription>
            {d ? `${d.objeto.livro}${d.objeto.capitulo ? ` · ${d.objeto.capitulo}` : ''}` : ' '}
          </SheetDescription>
        </SheetHeader>
        {detalhe.isError ? (
          <p role="alert" className="p-5 text-sm">Não foi possível abrir este objeto.</p>
        ) : d ? (
          <div className="space-y-5 p-5 text-sm">
            <div className="flex flex-wrap gap-2">
              <Badge variant="outline">{d.objeto.familia}</Badge>
              <Badge variant="neutro">{legivel(d.objeto.tipo)}</Badge>
              {d.objeto.status_epistemico ? <Badge variant="neutro">{legivel(d.objeto.status_epistemico)}</Badge> : null}
              {d.objeto.confianca != null ? <Badge variant="neutro">confiança {d.objeto.confianca}</Badge> : null}
            </div>
            {d.objeto.resumo ? <p className="leading-6">{d.objeto.resumo}</p> : null}
            {d.objeto.escopo ? <Campo rotulo="Escopo">{d.objeto.escopo}</Campo> : null}
            <ListaJson rotulo="Condições" valor={d.objeto.condicoes} />
            <ListaJson rotulo="Limitações" valor={d.objeto.limitacoes} />
            <ListaJson rotulo="Detalhes" valor={d.objeto.detalhes} />
            {(d.objeto.topicos ?? []).length > 0 ? (
              <Campo rotulo="Tópicos">{(d.objeto.topicos ?? []).map(legivel).join(' · ')}</Campo>
            ) : null}

            <div>
              <p className="text-[11px] font-black uppercase tracking-widest text-muted-foreground">De onde veio</p>
              <ul className="mt-2 space-y-2">
                {d.citacoes.map((c, i) => (
                  <li key={i} className="rounded-md border p-3">
                    <p className="font-semibold">
                      {[c.capitulo ?? c.localizador, paginas(c.pagina_inicio, c.pagina_fim)].filter(Boolean).join(' · ')}
                    </p>
                    {c.papel ? <p className="text-xs text-muted-foreground">{legivel(c.papel)}</p> : null}
                    {c.resumo ? <p className="mt-1 leading-5 text-muted-foreground">{c.resumo}</p> : null}
                  </li>
                ))}
              </ul>
            </div>

            <div>
              <p className="text-[11px] font-black uppercase tracking-widest text-muted-foreground">Relações</p>
              {d.relacoes.length === 0 ? (
                <p className="mt-2 text-muted-foreground">Sem relações registradas.</p>
              ) : (
                <ul className="mt-2 space-y-2">
                  {d.relacoes.map((r, i) => (
                    <li key={i} className="rounded-md border p-3">
                      <p>
                        {r.direcao === 'saida' ? 'Este objeto ' : ''}
                        <span className="font-semibold">{legivel(r.tipo)}</span>{' '}
                        {r.direcao === 'entrada' ? '← ' : '→ '}
                        <button type="button" className="font-semibold underline" onClick={() => aoAbrir(r.outro_id)}>
                          {r.outro_nome}
                        </button>
                      </p>
                      {r.resumo ? <p className="mt-1 leading-5 text-muted-foreground">{r.resumo}</p> : null}
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        ) : (
          <p role="status" className="p-5 text-sm">Carregando…</p>
        )}
      </SheetContent>
    </Sheet>
  );
}

function Campo({ rotulo, children }: { rotulo: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-[11px] font-black uppercase tracking-widest text-muted-foreground">{rotulo}</p>
      <p className="mt-1 leading-6">{children}</p>
    </div>
  );
}

/* Condições, limitações e detalhes chegam como JSON livre da ingestão: lista de textos, objeto
   ou vazio. Mostra o que houver, sem inventar estrutura. */
function ListaJson({ rotulo, valor }: { rotulo: string; valor: unknown }) {
  if (valor == null) return null;
  if (Array.isArray(valor)) {
    if (valor.length === 0) return null;
    return (
      <Campo rotulo={rotulo}>
        {valor.map((v) => (typeof v === 'string' ? v : JSON.stringify(v))).join(' · ')}
      </Campo>
    );
  }
  if (typeof valor === 'object') {
    const entradas = Object.entries(valor as Record<string, unknown>);
    if (entradas.length === 0) return null;
    return (
      <div>
        <p className="text-[11px] font-black uppercase tracking-widest text-muted-foreground">{rotulo}</p>
        <dl className="mt-1 space-y-1">
          {entradas.map(([k, v]) => (
            <div key={k}>
              <dt className="inline font-semibold">{legivel(k)}: </dt>
              <dd className="inline">{Array.isArray(v) ? v.map((x) => (typeof x === 'string' ? legivel(x) : JSON.stringify(x))).join(' · ') : typeof v === 'string' ? v : JSON.stringify(v)}</dd>
            </div>
          ))}
        </dl>
      </div>
    );
  }
  return <Campo rotulo={rotulo}>{String(valor)}</Campo>;
}

function Filtro({ ativo, onClick, children }: { ativo: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={ativo
        ? 'rounded-full bg-foreground px-3 py-1.5 text-xs font-semibold text-background'
        : 'rounded-full border px-3 py-1.5 text-xs font-semibold hover:bg-muted'}
    >
      {children}
    </button>
  );
}

function ResumoCard({ icone: Icone, rotulo, valor }: { icone: typeof BookOpen; rotulo: string; valor: number }) {
  return (
    <Card>
      <CardContent className="flex items-center gap-3 p-4">
        <div className="rounded-lg bg-muted p-2">
          <Icone className="h-4 w-4" />
        </div>
        <div>
          <p className="text-2xl font-black tabular-nums">{valor}</p>
          <p className="text-xs text-muted-foreground">{rotulo}</p>
        </div>
      </CardContent>
    </Card>
  );
}
