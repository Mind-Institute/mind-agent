import type { ReactNode } from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { Info } from 'lucide-react';
import {
  SITUACOES_OFERTA,
  TIPOS_OFERTA,
  type OfertaCatalogo,
  type PrecoOferta,
} from '@/contracts';
import { useItem } from '@/hooks/use-recurso';
import { formatarDataHora, formatarReais } from '@/lib/format';
import { PaginaListagem, type Coluna } from '@/components/admin/pagina-listagem';
import { EstadoCarregando, EstadoErro, EstadoVazio } from '@/components/admin/estados';
import { Alert, AlertDescription } from '@/components/ui/alert';
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
   OFERTAS — o schema `catalogo`, como está no banco
   ============================================================
   Decisão da Adriana (26/09/2026): preço, oferta, order bump e cupom
   moram no schema `catalogo`, e "o painel é o controle deste schema".
   Esta tela mostra cada oferta com os preços (um por produto, com o
   código vendável), o bônus e o que ela exige — order bump (no
   carrinho) e upgrade (já comprado) —, e a situação calculada pelo banco
   com as mesmas pontas de janela do site.

   SÓ LEITURA por enquanto (Passo 2 de docs/PLANO_OFERTAS_PASSO_A_PASSO.md);
   a edição é o Passo 4. As ofertas do Institute entram aqui na virada
   (Passo 5): até lá, o site do Institute ainda lê a casa antiga. */

const RECURSO = 'offers' as const;
const CAMINHO = '/ofertas';

const VERTICAIS = [
  { valor: 'institute', rotulo: 'Institute' },
  { valor: 'summit', rotulo: 'Summit' },
  { valor: 'dash', rotulo: 'Dash' },
  { valor: 'eventos', rotulo: 'Eventos' },
  { valor: 'outro', rotulo: 'Outro' },
];

const COR_SITUACAO: Record<string, BadgeProps['variant']> = {
  no_ar: 'sucesso',
  so_link: 'roxo',
  agendada: 'atencao',
  encerrada: 'neutro',
  desligada: 'neutro',
  historico: 'outline',
};

export function SeloSituacaoOferta({ situacao }: { situacao: string }) {
  const def = SITUACOES_OFERTA.find((s) => s.valor === situacao);
  return (
    <Badge variant={COR_SITUACAO[situacao] ?? 'outline'} title={def?.dica}>
      {def?.rotulo ?? situacao}
    </Badge>
  );
}

function rotuloTipo(tipo: string): string {
  return TIPOS_OFERTA.find((t) => t.valor === tipo)?.rotulo ?? tipo;
}

/** "R$ 1.200,00 · 12× de R$ 100,00", como o preço aparece para quem compra. */
function precoPorExtenso(p: PrecoOferta): string {
  const avista = formatarReais(p.valor, p.moeda);
  if (p.parcelas && p.valorParcela !== null) {
    return `${avista} · ${p.parcelas}× de ${formatarReais(p.valorParcela, p.moeda)}`;
  }
  return avista;
}

function prazo(o: Pick<OfertaCatalogo, 'iniciaEm' | 'encerraEm'>): string {
  if (!o.iniciaEm && !o.encerraEm) return 'sem prazo';
  if (!o.iniciaEm) return `até ${formatarDataHora(o.encerraEm)}`;
  if (!o.encerraEm) return `a partir de ${formatarDataHora(o.iniciaEm)}`;
  return `${formatarDataHora(o.iniciaEm)} → ${formatarDataHora(o.encerraEm)}`;
}

/** Valor de coluna como texto legível, sem esconder o que o banco guarda. */
function valorDaColuna(valor: unknown): string {
  if (valor === null || valor === undefined || valor === '') return '—';
  if (typeof valor === 'boolean') return valor ? 'sim' : 'não';
  if (Array.isArray(valor)) {
    if (valor.length === 0) return '—';
    return valor.every((v) => typeof v !== 'object') ? valor.join(', ') : JSON.stringify(valor, null, 2);
  }
  if (typeof valor === 'object') return JSON.stringify(valor, null, 2);
  return String(valor);
}

function Campo({ rotulo, children }: { rotulo: string; children: ReactNode }) {
  return (
    <div className="space-y-0.5">
      <dt className="text-xs font-semibold text-muted-foreground">{rotulo}</dt>
      <dd>{children}</dd>
    </div>
  );
}

function Secao({ titulo, children, testId }: { titulo: string; children: ReactNode; testId?: string }) {
  return (
    <section className="space-y-2" data-testid={testId}>
      <h3 className="text-xs font-black uppercase tracking-wide text-muted-foreground">{titulo}</h3>
      {children}
    </section>
  );
}

function DetalheOferta({ id, aoFechar }: { id: string | undefined; aoFechar: () => void }) {
  const consulta = useItem(RECURSO, id);
  const oferta = consulta.data;

  return (
    <Sheet open={Boolean(id)} onOpenChange={(aberto) => (!aberto ? aoFechar() : undefined)}>
      <SheetContent side="right" className="w-full p-0 sm:max-w-3xl">
        <SheetHeader>
          <SheetTitle>{oferta?.nome ?? 'Oferta'}</SheetTitle>
          <SheetDescription>
            {oferta ? (
              <span className="font-mono text-xs">{oferta.codigo}</span>
            ) : (
              'Carregando…'
            )}
          </SheetDescription>
        </SheetHeader>

        <div className="flex-1 space-y-6 overflow-y-auto p-5">
          {consulta.isPending ? (
            <EstadoCarregando linhas={8} />
          ) : consulta.error ? (
            <EstadoErro erro={consulta.error} aoTentarNovamente={() => void consulta.refetch()} />
          ) : oferta ? (
            <>
              <dl className="grid gap-3 rounded-lg border bg-muted/30 p-4 text-sm sm:grid-cols-3">
                <Campo rotulo="Situação">
                  <SeloSituacaoOferta situacao={oferta.situacao} />
                  <p className="mt-1 text-xs text-muted-foreground">
                    {SITUACOES_OFERTA.find((s) => s.valor === oferta.situacao)?.dica}
                  </p>
                </Campo>
                <Campo rotulo="Tipo">{rotuloTipo(oferta.tipo)}</Campo>
                <Campo rotulo="Prazo (horário de Brasília)">{prazo(oferta)}</Campo>
                <Campo rotulo="No site">
                  {oferta.noSite ? 'Sim — o site lê esta oferta agora' : 'Não'}
                </Campo>
                <Campo rotulo="Aparece no site">{oferta.publico ? 'Sim' : 'Não (só por link)'}</Campo>
                <Campo rotulo="Meios de pagamento">
                  {oferta.meiosPagamento.length ? oferta.meiosPagamento.join(', ') : '—'}
                </Campo>
              </dl>

              <Secao titulo={`Preços (${oferta.precos.length})`} testId="precos-da-oferta">
                {oferta.precos.length === 0 ? (
                  <p className="text-sm text-muted-foreground">Nenhum preço cadastrado.</p>
                ) : (
                  <ul className="divide-y rounded-lg border text-sm">
                    {oferta.precos.map((p) => (
                      <li key={p.codigo} className="space-y-1 px-3 py-2">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="font-semibold">{p.nome ?? p.produtoNome ?? p.produtoCodigo}</span>
                          {p.noSite ? <Badge variant="sucesso">no site</Badge> : null}
                        </div>
                        <p className="tabular">{precoPorExtenso(p)}</p>
                        {p.valorRiscado !== null ? (
                          <p className="text-xs text-muted-foreground">de {formatarReais(p.valorRiscado, p.moeda)} (riscado)</p>
                        ) : null}
                        <p className="text-xs text-muted-foreground">
                          Produto <span className="font-mono">{p.produtoCodigo}</span> · código vendável{' '}
                          <span className="font-mono">{p.codigo}</span>
                        </p>
                        {p.checkoutUrl ? (
                          <p className="break-all text-xs text-muted-foreground">Link de compra: {p.checkoutUrl}</p>
                        ) : null}
                        {p.eduzz ? (
                          <p className="text-xs text-muted-foreground" data-testid={`eduzz-${p.codigo}`}>
                            Eduzz ({p.skuExterno}): preço de lista atual {formatarReais(p.eduzz.preco)}
                            {p.eduzz.lidoEm ? ` · lido em ${formatarDataHora(p.eduzz.lidoEm)}` : ''}
                            {p.eduzz.arquivado ? ' · arquivado lá' : ''}
                          </p>
                        ) : null}
                      </li>
                    ))}
                  </ul>
                )}
              </Secao>

              {oferta.bonus.length ? (
                <Secao titulo={`Bônus (${oferta.bonus.length})`} testId="bonus-da-oferta">
                  <ul className="divide-y rounded-lg border text-sm">
                    {oferta.bonus.map((b) => (
                      <li key={`${b.produtoCodigo}-${b.inclusoCodigo}`} className="space-y-1 px-3 py-2">
                        <p className="font-semibold">{b.nome ?? b.inclusoNome ?? b.inclusoCodigo}</p>
                        {b.descricao ? <p className="text-xs">{b.descricao}</p> : null}
                        <p className="text-xs text-muted-foreground">
                          Entrega <span className="font-mono">{b.inclusoCodigo}</span>
                          {b.valorReferencia !== null ? ` · vale ${formatarReais(b.valorReferencia)}` : ''}
                          {b.encerraEm ? ` · até ${formatarDataHora(b.encerraEm)}` : ''}
                        </p>
                      </li>
                    ))}
                  </ul>
                </Secao>
              ) : null}

              {oferta.requer.length ? (
                <Secao titulo="Exige (order bump / upgrade)" testId="exigencias-da-oferta">
                  <ul className="divide-y rounded-lg border text-sm">
                    {oferta.requer.map((r) => (
                      <li key={r.produtoCodigo} className="px-3 py-2">
                        <p>
                          {r.modo === 'posse' ? 'Só para quem já comprou ' : 'Aparece no checkout de '}
                          <span className="font-semibold">{r.produtoNome ?? r.produtoCodigo}</span>
                        </p>
                        <p className="text-xs text-muted-foreground">
                          {r.modo === 'posse' ? 'upgrade' : 'order bump'}
                          {r.grupoExclusivo ? ` · grupo ${r.grupoExclusivo}` : ''}
                          {r.prioridade !== null ? ` · prioridade ${r.prioridade}` : ''}
                          {r.ativo ? '' : ' · desligada'}
                        </p>
                      </li>
                    ))}
                  </ul>
                </Secao>
              ) : null}

              {oferta.origem ? (
                <Secao titulo="De onde veio" testId="origem-da-oferta">
                  <pre className="max-h-64 overflow-auto whitespace-pre-wrap rounded-lg border bg-muted/30 p-3 font-mono text-xs">
                    {JSON.stringify(oferta.origem, null, 2)}
                  </pre>
                </Secao>
              ) : null}

              <Secao titulo="Como está no banco" testId="colunas-da-oferta">
                <dl className="divide-y rounded-lg border text-sm">
                  {Object.entries(oferta)
                    .filter(([coluna]) => !['precos', 'bonus', 'requer', 'origem'].includes(coluna))
                    .map(([coluna, valor]) => {
                      const texto = valorDaColuna(valor);
                      return (
                        <div key={coluna} className="grid gap-1 px-3 py-2 sm:grid-cols-[12rem_1fr]">
                          <dt className="font-mono text-xs text-muted-foreground">{coluna}</dt>
                          <dd className="min-w-0 break-words">
                            {texto.includes('\n') ? (
                              <pre className="whitespace-pre-wrap font-mono text-xs">{texto}</pre>
                            ) : (
                              texto
                            )}
                          </dd>
                        </div>
                      );
                    })}
                </dl>
              </Secao>
            </>
          ) : null}
        </div>

        <SheetFooter>
          <p className="mr-auto text-xs text-muted-foreground">
            {oferta?.historico
              ? 'Histórico: só consulta.'
              : 'Só leitura por enquanto: a edição de ofertas chega no próximo passo.'}
          </p>
          <Button variant="outline" type="button" onClick={aoFechar}>
            Fechar
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}

export function PaginaOfertas() {
  const { id } = useParams();
  const navegar = useNavigate();
  /* Fechar a oferta volta à lista como estava: busca, filtros, página e ordem. */
  const { search } = useLocation();

  const colunas: Coluna<OfertaCatalogo>[] = [
    {
      chave: 'oferta',
      cabecalho: 'Oferta',
      ordenarPor: 'nome',
      celula: (o) => (
        <div className="min-w-56">
          <p className="font-semibold">{o.nome}</p>
          <p className="font-mono text-xs text-muted-foreground">{o.codigo}</p>
        </div>
      ),
    },
    {
      chave: 'tipo',
      cabecalho: 'Tipo',
      ordenarPor: 'tipo',
      className: 'whitespace-nowrap',
      celula: (o) => <span className="text-xs">{rotuloTipo(o.tipo)}</span>,
    },
    {
      chave: 'precos',
      cabecalho: 'Produtos e preços',
      celula: (o) =>
        o.precos.length ? (
          <ul className="space-y-1 text-xs">
            {o.precos.map((p) => (
              <li key={p.codigo}>
                <span className="font-medium">{p.produtoNome ?? p.produtoCodigo}</span>{' '}
                <span className="tabular text-muted-foreground">{precoPorExtenso(p)}</span>
                {p.noSite ? (
                  <Badge variant="sucesso" className="ml-1">
                    no site
                  </Badge>
                ) : null}
              </li>
            ))}
          </ul>
        ) : (
          <span className="text-muted-foreground">—</span>
        ),
    },
    {
      chave: 'situacao',
      cabecalho: 'Situação',
      ordenarPor: 'situacaoOrdem',
      className: 'whitespace-nowrap',
      celula: (o) => <SeloSituacaoOferta situacao={o.situacao} />,
    },
    {
      chave: 'prazo',
      cabecalho: 'Prazo',
      ordenarPor: 'iniciaEm',
      className: 'whitespace-nowrap text-xs tabular',
      celula: (o) => prazo(o),
    },
    {
      chave: 'verticais',
      cabecalho: 'Vertical',
      celula: (o) =>
        o.verticais.length ? (
          <span className="text-xs">{o.verticais.join(', ')}</span>
        ) : (
          <span className="text-muted-foreground">—</span>
        ),
    },
  ];

  return (
    <>
      <PaginaListagem
        recurso={RECURSO}
        titulo="Ofertas"
        descricao="O schema catalogo como está no banco: cada oferta com os preços, o bônus e o que ela exige (order bump e upgrade). Só leitura por enquanto."
        colunas={colunas}
        placeholderBusca="Buscar por nome, código, código vendável ou produto…"
        destinoItem={(o) => `${CAMINHO}/${o.id}`}
        antesDaTabela={() => (
          <Alert variant="info" data-testid="aviso-virada">
            <Info />
            <AlertDescription>
              As ofertas do Institute entram aqui na virada. Até lá, o site do Institute ainda lê a
              casa antiga (<code className="font-mono">institute.ofertas</code>); aqui está o que já mora
              no <code className="font-mono">catalogo</code>. O selo <strong>no site</strong> marca o
              preço que o site lê agora.
            </AlertDescription>
          </Alert>
        )}
        definicoesFiltro={[
          { chave: 'situacao', rotulo: 'Situação', opcoes: SITUACOES_OFERTA.map((s) => ({ valor: s.valor, rotulo: s.rotulo })) },
          { chave: 'tipo', rotulo: 'Tipo', opcoes: TIPOS_OFERTA },
          { chave: 'verticais', rotulo: 'Vertical', opcoes: VERTICAIS },
          {
            chave: 'noSite',
            rotulo: 'No site',
            opcoes: [
              { valor: 'true', rotulo: 'O site lê agora' },
              { valor: 'false', rotulo: 'Fora do site' },
            ],
          },
        ]}
        estadoVazio={
          <EstadoVazio titulo="Nenhuma oferta no recorte" descricao="Nenhuma oferta bate com a busca e os filtros atuais." />
        }
      />

      <DetalheOferta id={id} aoFechar={() => navegar({ pathname: CAMINHO, search })} />
    </>
  );
}
