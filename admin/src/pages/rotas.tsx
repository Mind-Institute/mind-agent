import { useMemo } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ArrowLeftRight, ArrowRight } from 'lucide-react';
import type { Rota } from '@/contracts';
import { useLista, TODAS_AS_OPCOES } from '@/hooks/use-recurso';
import { formatarDistancia, formatarDuracao } from '@/lib/format';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { SeloAtivo } from '@/components/admin/selos';
import { EstadoVazio } from '@/components/admin/estados';
import { MapaConexoes } from '@/features/rotas/mapa-conexoes';
import { DrawerRota } from '@/features/rotas/drawer-rota';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

export function PaginaRotas() {
  const { id } = useParams();
  const navegar = useNavigate();
  const espacos = useLista('spaces', { ordenar: 'nome', ...TODAS_AS_OPCOES });
  const rotas = useLista('routes', TODAS_AS_OPCOES);

  const nomeEspaco = useMemo(() => {
    const mapa = new Map((espacos.data?.itens ?? []).map((e) => [e.id, e.nome]));
    return (idEspaco: string) => mapa.get(idEspaco) ?? idEspaco;
  }, [espacos.data]);

  const colunas: Coluna<Rota>[] = [
    {
      chave: 'trajeto',
      cabecalho: 'Trajeto',
      celula: (r) => (
        <div className="flex min-w-56 items-center gap-2 font-semibold">
          <span>{nomeEspaco(r.origemId)}</span>
          {r.bidirecional ? (
            <ArrowLeftRight className="size-3.5 text-muted-foreground" />
          ) : (
            <ArrowRight className="size-3.5 text-muted-foreground" />
          )}
          <span>{nomeEspaco(r.destinoId)}</span>
        </div>
      ),
    },
    {
      chave: 'instrucoes',
      cabecalho: 'Instruções',
      celula: (r) => <p className="line-clamp-2 max-w-96 text-xs text-muted-foreground">{r.instrucoes}</p>,
    },
    {
      chave: 'distancia',
      cabecalho: 'Distância',
      className: 'tabular whitespace-nowrap',
      celula: (r) => formatarDistancia(r.distanciaMetros),
    },
    {
      chave: 'tempo',
      cabecalho: 'Tempo',
      className: 'tabular whitespace-nowrap',
      celula: (r) => formatarDuracao(r.tempoEstimadoMinutos),
    },
    {
      chave: 'acessivel',
      cabecalho: 'Acessível',
      celula: (r) =>
        r.acessivel ? (
          <Badge variant="sucesso">sim</Badge>
        ) : (
          <Badge variant="destructive">não</Badge>
        ),
    },
    { chave: 'ativo', cabecalho: 'Situação', celula: (r) => <SeloAtivo ativo={r.ativo} /> },
  ];

  return (
    <>
      <PaginaListagem
        recurso="routes"
        titulo="Rotas"
        descricao="Como se vai de um espaço a outro. É o que o agente responde quando alguém pergunta o caminho."
        colunas={colunas}
        placeholderBusca="Buscar nas instruções…"
        destinoItem={(r) => `/rotas/${r.id}`}
        definicoesFiltro={[
          {
            chave: 'origemId',
            rotulo: 'Origem',
            opcoes: (espacos.data?.itens ?? []).map((e) => ({ valor: e.id, rotulo: e.nome })),
          },
          {
            chave: 'acessivel',
            rotulo: 'Acessibilidade',
            opcoes: [
              { valor: 'true', rotulo: 'Acessível' },
              { valor: 'false', rotulo: 'Não acessível' },
            ],
          },
          {
            chave: 'ativo',
            rotulo: 'Situação',
            opcoes: [
              { valor: 'true', rotulo: 'Ativas' },
              { valor: 'false', rotulo: 'Inativas' },
            ],
          },
        ]}
        estadoVazio={
          <EstadoVazio
            titulo="Nenhuma rota cadastrada"
            descricao="Sem rota, o agente sabe onde o espaço fica mas não sabe explicar como chegar."
          />
        }
        rodape={() => (
          <Card>
            <CardHeader>
              <CardTitle>Conexões entre espaços</CardTitle>
              <CardDescription>
                Diagrama de conferência, não editor de mapas: serve para ver de relance quem ficou
                sem caminho. O editor visual completo fica para uma fase futura.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <MapaConexoes espacos={espacos.data?.itens ?? []} rotas={rotas.data?.itens ?? []} />
            </CardContent>
          </Card>
        )}
      />

      <DrawerRota id={id} aoFechar={() => navegar('/rotas')} />
    </>
  );
}
