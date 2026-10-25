import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Database, Search, Table2, Layers3, AlertTriangle } from 'lucide-react';
import { useSessao } from '@/hooks/use-sessao';
import { buscarMapaSchemas, type MapaSchema } from '@/services/mapa-schemas';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';

const rotuloTipo = (tipo: string) => ({
  mind: 'Arquitetura Mind',
  infra_plataforma: 'Infraestrutura da plataforma',
  legado_pendente: 'Legado / pendência',
}[tipo] ?? tipo.replaceAll('_', ' '));

const normalizar = (valor: string) =>
  valor.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();

function casaCombina(item: MapaSchema, termo: string) {
  if (!termo) return true;
  const alvo = [
    item.schema_name,
    item.categoria,
    item.funcao,
    item.fronteira ?? '',
    item.observacoes ?? '',
    ...item.objetos.flatMap((objeto) => [objeto.nome, objeto.tipo, objeto.comentario ?? '']),
  ].join(' ');
  return normalizar(alvo).includes(normalizar(termo));
}

export function PaginaMapaSchemas() {
  const { simulada, obterToken, marcarSessaoExpirada } = useSessao();
  const [busca, setBusca] = useState('');
  const [tipo, setTipo] = useState('todos');

  const consulta = useQuery({
    queryKey: ['arquitetura-mapa-schemas', simulada],
    enabled: !simulada,
    queryFn: async ({ signal }) => {
      const token = await obterToken();
      if (!token) {
        marcarSessaoExpirada();
        throw new Error('Sessão expirada. Entre novamente.');
      }
      return buscarMapaSchemas({ token, sinal: signal });
    },
    refetchOnWindowFocus: true,
    refetchInterval: 60_000,
  });

  const itens = consulta.data ?? [];
  const tipos = useMemo(
    () => [...new Set(itens.map((item) => item.tipo))].sort(),
    [itens],
  );
  const filtrados = useMemo(
    () => itens.filter((item) => (tipo === 'todos' || item.tipo === tipo) && casaCombina(item, busca)),
    [itens, tipo, busca],
  );
  const totalObjetos = useMemo(
    () => itens.reduce((soma, item) => soma + item.objetos.length, 0),
    [itens],
  );

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Mapa de schemas"
        descricao="Leitura viva de arquitetura.mapa_schemas. O conteúdo desta tela vem do Supabase; o frontend só organiza e apresenta."
      />

      {simulada ? (
        <p role="status">Conecte o painel ao Supabase para consultar o mapa arquitetural.</p>
      ) : consulta.isPending ? (
        <p role="status">Carregando mapa de schemas…</p>
      ) : consulta.isError ? (
        <div role="alert" className="space-y-2">
          <p>Não foi possível consultar o mapa de schemas.</p>
          <button type="button" className="text-sm font-semibold underline" onClick={() => void consulta.refetch()}>
            Tentar novamente
          </button>
        </div>
      ) : null}

      {itens.length > 0 ? (
        <>
          <section className="grid gap-3 md:grid-cols-4" aria-label="Resumo do mapa">
            <ResumoCard icone={Database} rotulo="Schemas auditados" valor={itens.length} />
            <ResumoCard
              icone={Layers3}
              rotulo="Schemas Mind"
              valor={itens.filter((item) => item.tipo === 'mind').length}
            />
            <ResumoCard icone={Table2} rotulo="Tabelas e views" valor={totalObjetos} />
            <ResumoCard
              icone={AlertTriangle}
              rotulo="Pendências"
              valor={itens.filter((item) => item.tipo === 'legado_pendente').length}
            />
          </section>

          <section className="space-y-3" aria-label="Filtros">
            <div className="relative max-w-2xl">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                value={busca}
                onChange={(e) => setBusca(e.target.value)}
                placeholder="Buscar schema, função, fronteira, tabela ou view…"
                className="pl-9"
              />
            </div>
            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                onClick={() => setTipo('todos')}
                className={tipo === 'todos'
                  ? 'rounded-full bg-foreground px-3 py-1.5 text-xs font-semibold text-background'
                  : 'rounded-full border px-3 py-1.5 text-xs font-semibold hover:bg-muted'}
              >
                Todos ({itens.length})
              </button>
              {tipos.map((valor) => (
                <button
                  key={valor}
                  type="button"
                  onClick={() => setTipo(valor)}
                  className={tipo === valor
                    ? 'rounded-full bg-foreground px-3 py-1.5 text-xs font-semibold text-background'
                    : 'rounded-full border px-3 py-1.5 text-xs font-semibold hover:bg-muted'}
                >
                  {rotuloTipo(valor)} ({itens.filter((item) => item.tipo === valor).length})
                </button>
              ))}
            </div>
          </section>

          <section className="space-y-4" aria-label="Schemas">
            <p className="text-sm text-muted-foreground">
              {filtrados.length} de {itens.length} schemas exibidos.
            </p>
            <div className="grid gap-4 xl:grid-cols-2">
              {filtrados.map((item) => (
                <SchemaCard key={item.schema_name} item={item} />
              ))}
            </div>
          </section>
        </>
      ) : null}
    </div>
  );
}

function ResumoCard({
  icone: Icone,
  rotulo,
  valor,
}: {
  icone: typeof Database;
  rotulo: string;
  valor: number;
}) {
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

function SchemaCard({ item }: { item: MapaSchema }) {
  const tabelas = item.objetos.filter((objeto) =>
    objeto.tipo === 'table' || objeto.tipo === 'partitioned_table').length;
  const views = item.objetos.filter((objeto) =>
    objeto.tipo === 'view' || objeto.tipo === 'materialized_view').length;

  return (
    <Card className="overflow-hidden">
      <CardHeader className="space-y-3 border-b bg-muted/20">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle className="font-mono text-base">{item.schema_name}</CardTitle>
            <p className="mt-1 text-sm font-semibold">{item.categoria}</p>
          </div>
          <Badge variant="outline">{rotuloTipo(item.tipo)}</Badge>
        </div>
        <p className="text-sm leading-6 text-muted-foreground">{item.funcao}</p>
      </CardHeader>
      <CardContent className="space-y-4 p-4">
        {item.fronteira ? (
          <div>
            <p className="text-[11px] font-black uppercase tracking-widest text-muted-foreground">Fronteira</p>
            <p className="mt-1 text-sm leading-6">{item.fronteira}</p>
          </div>
        ) : null}

        {item.observacoes ? (
          <div>
            <p className="text-[11px] font-black uppercase tracking-widest text-muted-foreground">Observações</p>
            <p className="mt-1 text-sm leading-6">{item.observacoes}</p>
          </div>
        ) : null}

        <div className="flex flex-wrap gap-2">
          <Badge variant="neutro">{item.objetos.length} objetos</Badge>
          <Badge variant="neutro">{tabelas} tabelas</Badge>
          <Badge variant="neutro">{views} views</Badge>
          <Badge variant="outline">Auditado em {item.auditado_em.split('-').reverse().join('/')}</Badge>
        </div>

        <details className="rounded-lg border">
          <summary className="cursor-pointer select-none px-3 py-2 text-sm font-bold">
            Ver tabelas e views ({item.objetos.length})
          </summary>
          <div className="border-t">
            {item.objetos.length === 0 ? (
              <p className="px-3 py-4 text-sm text-muted-foreground">Nenhum objeto auditado neste schema.</p>
            ) : (
              <ul className="divide-y">
                {item.objetos.map((objeto) => (
                  <li key={`${objeto.tipo}:${objeto.nome}`} className="space-y-1 px-3 py-3">
                    <div className="flex flex-wrap items-center gap-2">
                      <code className="break-all text-xs font-bold">{objeto.nome}</code>
                      <Badge variant="outline">{objeto.tipo.replaceAll('_', ' ')}</Badge>
                    </div>
                    {objeto.comentario ? (
                      <p className="text-sm leading-5 text-muted-foreground">{objeto.comentario}</p>
                    ) : null}
                  </li>
                ))}
              </ul>
            )}
          </div>
        </details>
      </CardContent>
    </Card>
  );
}
