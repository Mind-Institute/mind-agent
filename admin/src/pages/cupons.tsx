import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { SITUACOES_CUPOM, type CupomCatalogo } from '@/contracts';
import { useItem } from '@/hooks/use-recurso';
import { formatarDataHora, formatarReais } from '@/lib/format';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { EstadoCarregando, EstadoErro, EstadoVazio } from '@/components/admin/estados';
import { Badge, type BadgeProps } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetFooter,
  SheetHeader,
  SheetTitle,
} from '@/components/ui/sheet';

/* ============================================================
   CUPONS — `catalogo.cupons`, como está no banco
   ============================================================
   Decisão da Adriana (26/09/2026): cupom mora no schema `catalogo`, e o
   painel é o controle dele. Até 26/09 a tabela era `checkout.cupons`
   (vazia); os cupons do Summit 2026 entraram como histórico. SÓ LEITURA
   por enquanto — a edição é o Passo 4 do plano de ofertas. */

const RECURSO = 'coupons' as const;
const CAMINHO = '/cupons';

const COR_SITUACAO: Record<string, BadgeProps['variant']> = {
  valendo: 'sucesso',
  agendado: 'atencao',
  esgotado: 'neutro',
  encerrado: 'neutro',
  desligado: 'neutro',
  historico: 'outline',
};

function SeloSituacaoCupom({ situacao }: { situacao: string }) {
  const def = SITUACOES_CUPOM.find((s) => s.valor === situacao);
  return (
    <Badge variant={COR_SITUACAO[situacao] ?? 'outline'} title={def?.dica}>
      {def?.rotulo ?? situacao}
    </Badge>
  );
}

/** "10%" ou "R$ 200,00", como o desconto aparece para quem compra. */
function desconto(c: Pick<CupomCatalogo, 'tipo' | 'valor'>): string {
  if (c.tipo === 'percentual') return `${new Intl.NumberFormat('pt-BR').format(c.valor)}%`;
  if (c.tipo === 'valor') return formatarReais(c.valor);
  return `${c.valor} (${c.tipo})`;
}

const SISTEMA: Record<string, string> = {
  checkout_proprio: 'Checkout próprio',
  eduzz: 'Eduzz',
};

function prazo(c: Pick<CupomCatalogo, 'iniciaEm' | 'encerraEm'>): string {
  if (!c.iniciaEm && !c.encerraEm) return 'sem prazo';
  if (!c.iniciaEm) return `até ${formatarDataHora(c.encerraEm)}`;
  if (!c.encerraEm) return `a partir de ${formatarDataHora(c.iniciaEm)}`;
  return `${formatarDataHora(c.iniciaEm)} → ${formatarDataHora(c.encerraEm)}`;
}

function DetalheCupom({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const consulta = useItem(RECURSO, id);
  const cupom = consulta.data;

  return (
    <Sheet open={Boolean(id)} onOpenChange={(aberto) => (!aberto ? aoFechar() : undefined)}>
      <SheetContent side="right" className="w-full p-0 sm:max-w-2xl">
        <SheetHeader>
          <SheetTitle>{cupom?.codigo ?? 'Cupom'}</SheetTitle>
          <SheetDescription>{cupom ? (cupom.descricao ?? 'Sem descrição') : 'Carregando…'}</SheetDescription>
        </SheetHeader>

        <div className="flex-1 space-y-5 overflow-y-auto p-5">
          {consulta.isPending ? (
            <EstadoCarregando linhas={6} />
          ) : consulta.error ? (
            <EstadoErro erro={consulta.error} aoTentarNovamente={() => void consulta.refetch()} />
          ) : cupom ? (
            <dl className="grid gap-3 rounded-lg border bg-muted/30 p-4 text-sm sm:grid-cols-2" data-testid="dados-do-cupom">
              <div className="space-y-0.5">
                <dt className="text-xs font-semibold text-muted-foreground">Situação</dt>
                <dd>
                  <SeloSituacaoCupom situacao={cupom.situacao} />
                </dd>
              </div>
              <div className="space-y-0.5">
                <dt className="text-xs font-semibold text-muted-foreground">Desconto</dt>
                <dd>{desconto(cupom)}</dd>
              </div>
              <div className="space-y-0.5">
                <dt className="text-xs font-semibold text-muted-foreground">Onde se aplica</dt>
                <dd>{SISTEMA[cupom.sistema] ?? cupom.sistema}</dd>
              </div>
              <div className="space-y-0.5">
                <dt className="text-xs font-semibold text-muted-foreground">Prazo (horário de Brasília)</dt>
                <dd>{prazo(cupom)}</dd>
              </div>
              <div className="space-y-0.5">
                <dt className="text-xs font-semibold text-muted-foreground">Usos</dt>
                <dd className="tabular">
                  {cupom.usos}
                  {cupom.usosMaximos !== null ? ` de ${cupom.usosMaximos}` : ''}
                  {cupom.usosPorEmail !== null ? ` · até ${cupom.usosPorEmail} por e-mail` : ''}
                </dd>
              </div>
              <div className="space-y-0.5">
                <dt className="text-xs font-semibold text-muted-foreground">Vale para</dt>
                <dd className="break-words">
                  {[...cupom.ofertas, ...cupom.programas, ...cupom.produtos].length
                    ? [...cupom.ofertas, ...cupom.programas, ...cupom.produtos].join(', ')
                    : 'qualquer oferta'}
                </dd>
              </div>
              <div className="space-y-0.5">
                <dt className="text-xs font-semibold text-muted-foreground">Compra mínima</dt>
                <dd>{formatarReais(cupom.valorMinimo)}</dd>
              </div>
              <div className="space-y-0.5">
                <dt className="text-xs font-semibold text-muted-foreground">Teto do desconto</dt>
                <dd>{formatarReais(cupom.tetoDesconto)}</dd>
              </div>
              {cupom.origem ? (
                <div className="space-y-0.5 sm:col-span-2">
                  <dt className="text-xs font-semibold text-muted-foreground">De onde veio</dt>
                  <dd>
                    <pre className="max-h-48 overflow-auto whitespace-pre-wrap rounded border bg-background p-2 font-mono text-xs">
                      {JSON.stringify(cupom.origem, null, 2)}
                    </pre>
                  </dd>
                </div>
              ) : null}
            </dl>
          ) : null}
        </div>

        <SheetFooter>
          <p className="mr-auto text-xs text-muted-foreground">
            {cupom?.historico ? 'Histórico: só consulta.' : 'Só leitura por enquanto: a edição de cupons chega no próximo passo.'}
          </p>
          <Button variant="outline" type="button" onClick={aoFechar}>
            Fechar
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}

export function PaginaCupons() {
  const { id } = useParams();
  const navegar = useNavigate();
  const { search } = useLocation();

  const colunas: Coluna<CupomCatalogo>[] = [
    {
      chave: 'codigo',
      cabecalho: 'Cupom',
      ordenarPor: 'codigo',
      celula: (c) => (
        <div className="min-w-40">
          <p className="font-mono font-semibold">{c.codigo}</p>
          {c.descricao ? <p className="text-xs text-muted-foreground">{c.descricao}</p> : null}
        </div>
      ),
    },
    {
      chave: 'desconto',
      cabecalho: 'Desconto',
      ordenarPor: 'valor',
      className: 'whitespace-nowrap tabular',
      celula: (c) => desconto(c),
    },
    {
      chave: 'situacao',
      cabecalho: 'Situação',
      ordenarPor: 'situacaoOrdem',
      className: 'whitespace-nowrap',
      celula: (c) => <SeloSituacaoCupom situacao={c.situacao} />,
    },
    {
      chave: 'sistema',
      cabecalho: 'Onde se aplica',
      className: 'whitespace-nowrap text-xs',
      celula: (c) => SISTEMA[c.sistema] ?? c.sistema,
    },
    {
      chave: 'usos',
      cabecalho: 'Usos',
      ordenarPor: 'usos',
      className: 'whitespace-nowrap tabular text-xs',
      celula: (c) => `${c.usos}${c.usosMaximos !== null ? ` de ${c.usosMaximos}` : ''}`,
    },
    {
      chave: 'prazo',
      cabecalho: 'Prazo',
      ordenarPor: 'encerraEm',
      className: 'whitespace-nowrap text-xs tabular',
      celula: (c) => prazo(c),
    },
  ];

  return (
    <>
      <PaginaListagem
        recurso={RECURSO}
        titulo="Cupons"
        descricao="A tabela catalogo.cupons como está no banco. Só leitura por enquanto."
        colunas={colunas}
        placeholderBusca="Buscar por código ou descrição…"
        destinoItem={(c) => `${CAMINHO}/${c.id}`}
        definicoesFiltro={[
          { chave: 'situacao', rotulo: 'Situação', opcoes: SITUACOES_CUPOM.map((s) => ({ valor: s.valor, rotulo: s.rotulo })) },
          {
            chave: 'sistema',
            rotulo: 'Onde se aplica',
            opcoes: Object.entries(SISTEMA).map(([valor, rotulo]) => ({ valor, rotulo })),
          },
        ]}
        estadoVazio={
          <EstadoVazio titulo="Nenhum cupom no recorte" descricao="Nenhum cupom bate com a busca e os filtros atuais." />
        }
      />

      <DetalheCupom id={id} aoFechar={() => navegar({ pathname: CAMINHO, search })} />
    </>
  );
}
