import { useQuery } from '@tanstack/react-query';
import { useSessao } from '@/hooks/use-sessao';
import { buscarDecisoes } from '@/services/decisoes';
import { useSearchParams } from 'react-router-dom';
import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge, type BadgeProps } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import {
  CAMADAS,
  ROTULO_SITUACAO,
  type Decisao,
  type Situacao,
} from '@/lib/arquitetura';

/* Espelho somente leitura de arquitetura.decisoes no Supabase.
   Sem lista local ou fallback que possa apresentar uma decisão antiga. */

const COR_SITUACAO: Record<Situacao, BadgeProps['variant']> = {
  aplicada: 'sucesso',
  parcial: 'atencao',
  'so-documento': 'neutro',
};

export function PaginaArquitetura() {
  const [parametros, setParametros] = useSearchParams();
  const { simulada, obterToken, marcarSessaoExpirada } = useSessao();
  const consulta = useQuery({
    queryKey: ['arquitetura-decisoes', simulada],
    enabled: !simulada,
    queryFn: async ({ signal }) => {
      const token = await obterToken();
      if (!token) { marcarSessaoExpirada(); throw new Error('Sessão expirada. Entre novamente.'); }
      return buscarDecisoes({ token, sinal: signal });
    },
    refetchOnWindowFocus: true,
    refetchInterval: 60_000,
  });
  const decisoes = consulta.data ?? [];
  const escolhida = decisoes.find((d) => d.id === parametros.get('d')) ?? decisoes[0];
  const escolher = (id: string) => setParametros({ d: id }, { replace: true });

  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Decisões do sistema"
        descricao="Decisões aprovadas no Supabase, em arquitetura.decisoes. Esta tela apenas consulta e mostra."
      />

      {simulada ? <p role="status">Conecte o painel ao Supabase para consultar as decisões oficiais.</p>
        : consulta.isPending ? <p role="status">Carregando decisões…</p>
        : consulta.isError ? <div role="alert"><p>Não foi possível consultar as decisões oficiais.</p>
          <button type="button" onClick={() => void consulta.refetch()}>Tentar novamente</button></div>
        : decisoes.length === 0 ? <p role="status">Nenhuma decisão registrada.</p> : null}
      {escolhida ? <>
      <section aria-labelledby="titulo-mapa" className="space-y-3">
        <h2 id="titulo-mapa" className="text-base font-black">Mapa</h2>
        <div className="overflow-x-auto rounded-lg border">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left">
              <tr>
                <th scope="col" className="px-3 py-2 font-semibold">Decisão</th>
                <th scope="col" className="px-3 py-2 font-semibold">Situação</th>
                {CAMADAS.map((camada) => (
                  <th key={camada.id} scope="col" className="px-3 py-2 text-center font-semibold">
                    {camada.rotulo}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {decisoes.map((decisao) => (
                <tr
                  key={decisao.id}
                  onClick={() => escolher(decisao.id)}
                  aria-selected={decisao.id === escolhida.id}
                  className={
                    decisao.id === escolhida.id
                      ? 'cursor-pointer border-t bg-verde-100'
                      : 'cursor-pointer border-t hover:bg-muted/50'
                  }
                >
                  <th scope="row" className="px-3 py-2 text-left font-black">
                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation();
                        escolher(decisao.id);
                      }}
                      aria-pressed={decisao.id === escolhida.id}
                      className="hover:underline"
                    >
                      {decisao.id}
                    </button>
                  </th>
                  <td className="px-3 py-2">
                    <BadgeSituacao decisao={decisao} />
                  </td>
                  {CAMADAS.map((camada) => {
                    const n = decisao.lugares.filter((l) => l.camada === camada.id).length;
                    return (
                      <td
                        key={camada.id}
                        className="px-3 py-2 text-center tabular-nums"
                        aria-label={`${decisao.id} · ${camada.rotulo}: ${n}`}
                      >
                        {n > 0 ? n : <span className="text-muted-foreground">—</span>}
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="text-xs text-muted-foreground">
          Cada número é quantos lugares daquela camada aplicam a decisão. Clique numa linha para ver a decisão aqui embaixo.
        </p>
      </section>

      <section aria-label="Decisão escolhida">
        <CartaoDecisao decisao={escolhida} />
      </section>
      </> : null}
    </div>
  );
}

function BadgeSituacao({ decisao }: { decisao: Decisao }) {
  return <Badge variant={decisao.situacao ? COR_SITUACAO[decisao.situacao] : 'neutro'}>
    {decisao.situacao ? ROTULO_SITUACAO[decisao.situacao] : 'Não aferida'}
  </Badge>;
}

function CartaoDecisao({ decisao }: { decisao: Decisao }) {
  return (
    <Card>
      <CardHeader className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="outline" className="font-black">{decisao.id}</Badge>
          <BadgeSituacao decisao={decisao} />
          <span className="text-xs text-muted-foreground">{decisao.data} · Aprovada por {decisao.aprovadaPor} · {decisao.vigencia}</span>
        </div>
        <CardTitle className="text-base">{decisao.titulo}</CardTitle>
        <CardDescription>{decisao.texto}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <p className="text-sm">{decisao.significado}</p>
        {decisao.substituidaPor ? <p className="text-sm">Substituída por {decisao.substituidaPor}.</p> : null}
        <p className="text-sm">{decisao.leitura}</p>
        {decisao.medidoEm ? <p className="text-xs text-muted-foreground">Mapa de implementação aferido em {decisao.medidoEm}; pode não refletir alterações posteriores.</p> : null}
        <div className="space-y-3">
          {CAMADAS.map((camada) => {
            const lugares = decisao.lugares.filter((l) => l.camada === camada.id);
            if (lugares.length === 0) return null;
            return (
              <div key={camada.id}>
                <p className="text-[11px] font-black uppercase tracking-widest text-muted-foreground">
                  {camada.rotulo}
                </p>
                <ul className="mt-1 space-y-1">
                  {lugares.map((lugar) => (
                    <li key={lugar.onde} className="text-sm">
                      <code className="break-all rounded bg-muted px-1 py-0.5 text-xs">{lugar.onde}</code>
                      <span className="text-muted-foreground"> — {lugar.oQueFaz}</span>
                    </li>
                  ))}
                </ul>
              </div>
            );
          })}
        </div>
      </CardContent>
    </Card>
  );
}
