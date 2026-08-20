import { Link } from 'react-router-dom';
import { AlertTriangle, ArrowRight, CheckCircle2, Info, SatelliteDish } from 'lucide-react';
import type { AlertaPainel, GrupoPendencia, MetricaPainel } from '@/contracts';
import { useResumoPainel } from '@/hooks/use-recurso';
import { useModoDados } from '@/services/provider-context';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { EstadoCarregando, EstadoErro } from '@/components/admin/estados';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { formatarDataHora, formatarNumero } from '@/lib/format';
import { cn } from '@/lib/utils';

function CartaoMetrica({ metrica }: { metrica: MetricaPainel }) {
  const atencao = metrica.tom === 'atencao';
  return (
    <Link
      to={metrica.destino}
      className={cn(
        'group rounded-lg border bg-card p-4 transition-colors hover:border-verde-300 hover:bg-verde-50/40',
        atencao && 'border-coral-200 bg-coral-50/50 hover:border-coral-300 hover:bg-coral-50',
      )}
    >
      <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
        {metrica.rotulo}
      </p>
      <p
        className={cn(
          'tabular mt-1 text-3xl font-black tracking-tight',
          atencao ? 'text-coral-700' : 'text-foreground',
        )}
      >
        {formatarNumero(metrica.valor)}
      </p>
      {metrica.detalhe ? (
        <p className="mt-1 text-xs text-muted-foreground">{metrica.detalhe}</p>
      ) : null}
    </Link>
  );
}

function CartaoAlerta({ alerta }: { alerta: AlertaPainel }) {
  const Icone = alerta.nivel === 'info' ? Info : AlertTriangle;
  return (
    <div
      className={cn(
        'flex gap-3 rounded-lg border p-4',
        alerta.nivel === 'erro'
          ? 'border-coral-200 bg-coral-50'
          : alerta.nivel === 'atencao'
            ? 'border-amber-200 bg-amber-50'
            : 'border-verde-200 bg-verde-50',
      )}
    >
      <Icone className="mt-0.5 size-4 shrink-0" />
      <div className="space-y-1">
        <p className="text-sm font-bold">{alerta.titulo}</p>
        <p className="text-sm text-muted-foreground">{alerta.descricao}</p>
        {alerta.destino ? (
          <Link
            to={alerta.destino}
            className="inline-flex items-center gap-1 text-sm font-semibold text-primary hover:underline"
          >
            Revisar <ArrowRight className="size-3.5" />
          </Link>
        ) : null}
      </div>
    </div>
  );
}

function BlocoPendencia({ grupo }: { grupo: GrupoPendencia }) {
  const limpo = grupo.total === 0;
  return (
    <div className="rounded-lg border bg-card p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-bold">{grupo.titulo}</p>
          <p className="text-xs text-muted-foreground">{grupo.descricao}</p>
        </div>
        <Badge variant={limpo ? 'sucesso' : 'atencao'} className="shrink-0 tabular">
          {limpo ? <CheckCircle2 className="size-3" /> : null}
          {grupo.total}
        </Badge>
      </div>

      {limpo ? (
        <p className="mt-3 text-xs text-muted-foreground">Nada pendente aqui.</p>
      ) : (
        <>
          <ul className="mt-3 space-y-1">
            {grupo.itens.map((item) => (
              <li key={item.id}>
                <Link
                  to={item.destino}
                  className="line-clamp-1 text-sm text-slate-600 hover:text-primary hover:underline"
                  title={item.rotulo}
                >
                  {item.rotulo}
                </Link>
              </li>
            ))}
          </ul>
          {grupo.total > grupo.itens.length ? (
            <Link
              to={grupo.destino}
              className="mt-2 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
            >
              ver todos os {grupo.total} <ArrowRight className="size-3" />
            </Link>
          ) : null}
        </>
      )}
    </div>
  );
}

export function PaginaVisaoGeral() {
  const consulta = useResumoPainel();
  const modo = useModoDados();

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Visão geral"
        descricao="Os números do evento e, principalmente, o que ainda falta para o agente conseguir responder."
        acoes={
          modo === 'mock' ? (
            <Badge variant="destructive">números simulados</Badge>
          ) : (
            <Badge variant="sucesso" data-testid="selo-dashboard-real">
              <SatelliteDish className="size-3" /> números da API administrativa
            </Badge>
          )
        }
      />

      {consulta.isPending ? (
        <EstadoCarregando linhas={4} rotulo="Carregando visão geral…" />
      ) : consulta.error ? (
        <EstadoErro erro={consulta.error} aoTentarNovamente={() => void consulta.refetch()} />
      ) : consulta.data ? (
        <>
          <section aria-labelledby="metricas">
            <h2 id="metricas" className="sr-only">
              Métricas
            </h2>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5">
              {consulta.data.metricas.map((metrica) => (
                <CartaoMetrica key={metrica.chave} metrica={metrica} />
              ))}
            </div>
          </section>

          {consulta.data.alertas.length > 0 ? (
            <section aria-labelledby="alertas" className="space-y-2">
              <h2 id="alertas" className="text-sm font-black uppercase tracking-wide text-muted-foreground">
                Alertas
              </h2>
              <div className="grid gap-2 lg:grid-cols-2">
                {consulta.data.alertas.map((alerta) => (
                  <CartaoAlerta key={alerta.id} alerta={alerta} />
                ))}
              </div>
            </section>
          ) : null}

          <Card>
            <CardHeader>
              <CardTitle>Pendências importantes</CardTitle>
              <CardDescription>
                Cada bloco é um buraco na resposta do agente. Clicar leva direto ao registro que
                precisa de conserto.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
                {consulta.data.pendencias.map((grupo) => (
                  <BlocoPendencia key={grupo.categoria} grupo={grupo} />
                ))}
              </div>
            </CardContent>
          </Card>

          <p className="text-xs text-muted-foreground">
            Gerado em {formatarDataHora(consulta.data.geradoEm)}.
          </p>
        </>
      ) : null}
    </div>
  );
}
