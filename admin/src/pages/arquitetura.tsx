import { CabecalhoPagina } from '@/components/admin/cabecalho-pagina';
import { Badge, type BadgeProps } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import {
  CAMADAS,
  DECISOES,
  MEDIDO_EM,
  ROTULO_SITUACAO,
  TABELAS_NA_PORTA,
  type Decisao,
  type Situacao,
} from '@/lib/arquitetura';

/* ============================================================
   ARQUITETURA DO SISTEMA — DECISÕES E MAPA
   ============================================================
   Pedido da Adriana (07/10/2026): o espelho das decisões D1–D6 e onde
   cada uma está aplicada. Só leitura; o conteúdo mora em
   `lib/arquitetura.ts`, tirado dos documentos e do banco. */

const COR_SITUACAO: Record<Situacao, BadgeProps['variant']> = {
  aplicada: 'sucesso',
  parcial: 'atencao',
  'so-documento': 'neutro',
};

export function PaginaArquitetura() {
  return (
    <div className="space-y-6">
      <CabecalhoPagina
        titulo="Decisões do sistema"
        descricao={`As decisões congeladas no PROJECT_STATE.md e onde cada uma está aplicada. Números medidos no banco em ${MEDIDO_EM}.`}
      />

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
              {DECISOES.map((decisao) => (
                <tr key={decisao.id} className="border-t">
                  <th scope="row" className="px-3 py-2 text-left font-black">
                    <a href={`#${decisao.id}`} className="hover:underline">{decisao.id}</a>
                  </th>
                  <td className="px-3 py-2">
                    <Badge variant={COR_SITUACAO[decisao.situacao]}>{ROTULO_SITUACAO[decisao.situacao]}</Badge>
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
          Cada número é quantos lugares daquela camada aplicam a decisão. Clique na decisão para ver quais.
        </p>
      </section>

      <section aria-label="Decisões" className="space-y-4">
        {DECISOES.map((decisao) => (
          <CartaoDecisao key={decisao.id} decisao={decisao} />
        ))}
      </section>
    </div>
  );
}

function CartaoDecisao({ decisao }: { decisao: Decisao }) {
  return (
    <Card id={decisao.id} className="scroll-mt-20">
      <CardHeader className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="outline" className="font-black">{decisao.id}</Badge>
          <Badge variant={COR_SITUACAO[decisao.situacao]}>{ROTULO_SITUACAO[decisao.situacao]}</Badge>
          <span className="text-xs text-muted-foreground">{decisao.data}</span>
        </div>
        <CardTitle className="text-base">{decisao.titulo}</CardTitle>
        <CardDescription>{decisao.resumo}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <p className="text-sm">{decisao.leitura}</p>
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
        {decisao.id === 'D5' ? (
          <details className="text-sm">
            <summary className="cursor-pointer font-semibold">
              As {TABELAS_NA_PORTA.length} tabelas em que a porta roda antes de escrever
            </summary>
            <ul className="mt-2 grid gap-1 sm:grid-cols-2">
              {TABELAS_NA_PORTA.map((tabela) => (
                <li key={tabela}>
                  <code className="break-all text-xs">{tabela}</code>
                </li>
              ))}
            </ul>
          </details>
        ) : null}
      </CardContent>
    </Card>
  );
}
