import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import {
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  ChevronLeft,
  ChevronRight,
  FlaskConical,
  SatelliteDish,
} from 'lucide-react';
import type { ListFilters, MapaRecursos, NomeRecurso } from '@/contracts';
import { useLista } from '@/hooks/use-recurso';
import { useFiltrosUrl } from '@/hooks/use-filtros-url';
import { useSessao } from '@/hooks/use-sessao';
import { useOrigemRecurso } from '@/services/provider-context';
import { motivoDaRecusa, type Acao } from '@/lib/permissions';
import { formatarNumero } from '@/lib/format';
import { CabecalhoPagina } from './cabecalho-pagina';
import { BarraDeFiltros, type DefinicaoFiltro } from './barra-filtros';
import { EstadoCarregando, EstadoErro, EstadoSemPermissao, EstadoVazio } from './estados';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { cn } from '@/lib/utils';

export interface Coluna<T> {
  chave: string;
  cabecalho: string;
  celula: (item: T) => ReactNode;
  className?: string;
  /** Campo do registro por onde a coluna ordena. Ausente, o cabeçalho não ordena. */
  ordenarPor?: string;
}

/** A ordem pedida na URL: `nome` é crescente, `-nome` decrescente. */
function lerOrdem(valor: string | undefined): { campo: string; desc: boolean } | null {
  if (!valor) return null;
  const desc = valor.startsWith('-');
  const campo = desc ? valor.slice(1) : valor;
  return campo ? { campo, desc } : null;
}

/**
 * Cabeçalho que ordena. Um clique ordena crescente, o segundo
 * decrescente, o terceiro volta à ordem do banco.
 */
function CabecalhoOrdenavel({
  rotulo,
  campo,
  ordem,
  escolhida,
  aoOrdenar,
}: {
  rotulo: string;
  campo: string;
  ordem: { campo: string; desc: boolean } | null;
  /** `false` quando a ordem vigente é a padrão da página, não um clique. */
  escolhida: boolean;
  aoOrdenar: (proxima: string | null) => void;
}) {
  const ativa = ordem?.campo === campo ? ordem : null;
  const Icone = !ativa ? ArrowUpDown : ativa.desc ? ArrowDown : ArrowUp;
  /* Crescente → decrescente → padrão. Se a coluna já está ordenada pelo
     padrão da página, o clique inverte — "voltar ao padrão" ali não
     mudaria nada. */
  const proxima = !ativa
    ? campo
    : !escolhida
      ? ativa.desc
        ? campo
        : `-${campo}`
      : !ativa.desc
        ? `-${campo}`
        : null;
  const dica =
    proxima === null
      ? 'Voltar à ordem padrão'
      : `Ordenar por ${rotulo}, ${proxima.startsWith('-') ? 'decrescente' : 'crescente'}`;
  return (
    <button
      type="button"
      onClick={() => aoOrdenar(proxima)}
      title={dica}
      className={cn(
        '-mx-1 inline-flex items-center gap-1 rounded px-1 py-0.5 hover:bg-muted hover:text-foreground',
        ativa && 'text-foreground',
      )}
    >
      {rotulo}
      <Icone className={cn('size-3.5 shrink-0', !ativa && 'opacity-40')} aria-hidden />
    </button>
  );
}

/** Quantos registros por página. A API já devolve `total` e `pagina`. */
const POR_PAGINA = 50;

/** Diz de onde a listagem vem — real ou demonstração. */
function SeloOrigem({ origem }: { origem: 'http' | 'mock' }) {
  return origem === 'http' ? (
    <Badge variant="sucesso" data-testid="selo-origem-real">
      <SatelliteDish className="size-3" /> dados reais
    </Badge>
  ) : (
    <Badge variant="destructive" data-testid="selo-origem-mock">
      <FlaskConical className="size-3" /> demonstração
    </Badge>
  );
}

/* ============================================================
   LISTAGEM PADRÃO
   ============================================================
   Quinze módulos, uma listagem. Cada página descreve as colunas e os
   filtros; carregamento, vazio, erro, sem permissão, busca, paginação
   e o selo de origem vêm de graça — e iguais em todas.

   Trocar mock por HTTP não toca aqui: o componente só conhece
   `useLista`, que só conhece o `AdminDataProvider`. */
export function PaginaListagem<K extends NomeRecurso>({
  recurso,
  titulo,
  descricao,
  colunas,
  definicoesFiltro = [],
  placeholderBusca,
  acoes,
  destinoItem,
  aoClicarItem,
  estadoVazio,
  permissaoNecessaria = 'ver',
  filtrosFixos,
  ordenar,
  rodape,
  antesDaTabela,
}: {
  recurso: K;
  titulo: string;
  descricao?: string;
  colunas: Coluna<MapaRecursos[K]>[];
  definicoesFiltro?: DefinicaoFiltro[];
  placeholderBusca?: string;
  acoes?: ReactNode;
  destinoItem?: (item: MapaRecursos[K]) => string;
  aoClicarItem?: (item: MapaRecursos[K]) => void;
  estadoVazio?: ReactNode;
  permissaoNecessaria?: Acao;
  filtrosFixos?: ListFilters;
  ordenar?: string;
  rodape?: (itens: MapaRecursos[K][]) => ReactNode;
  antesDaTabela?: (itens: MapaRecursos[K][]) => ReactNode;
}) {
  const navegar = useNavigate();
  const { search } = useLocation();
  const sessao = useSessao();
  const origem = useOrigemRecurso(recurso);
  const { filtros, paraProvedor, definir, definirVarios, limpar } = useFiltrosUrl();
  const [busca, setBusca] = useState(filtros.busca ?? '');

  const pagina = Math.max(1, Number(filtros.pagina ?? 1) || 1);

  /* A ordem escolhida no cabeçalho mora na URL, como os filtros; sem ela,
     vale a da página (ou a do banco). */
  const ordemPedida = filtros.ordenar || ordenar;
  const ordem = lerOrdem(ordemPedida);

  /* Busca nova recomeça na primeira página: continuar na página 3 de um
     recorte que agora tem 4 registros mostraria vazio.
     A primeira renderização não conta — ali a busca veio da URL, junto
     com a página, e as duas devem ser respeitadas. */
  const buscaAnterior = useRef(busca);
  useEffect(() => {
    if (buscaAnterior.current === busca) return;
    buscaAnterior.current = busca;
    if (pagina > 1) definir('pagina', null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [busca]);

  const filtrosConsulta = useMemo<ListFilters>(
    () => ({
      ...filtrosFixos,
      ...paraProvedor,
      busca: busca || undefined,
      ordenar: ordemPedida || undefined,
      pagina,
      porPagina: POR_PAGINA,
    }),
    [filtrosFixos, paraProvedor, busca, ordemPedida, pagina],
  );

  const podeVer = sessao.pode(permissaoNecessaria);
  const consulta = useLista(recurso, filtrosConsulta, { enabled: podeVer });
  const itens = consulta.data?.itens ?? [];
  const total = consulta.data?.total ?? itens.length;
  const porPagina = consulta.data?.porPagina || POR_PAGINA;
  const totalPaginas = Math.max(1, Math.ceil(total / porPagina));

  function abrir(item: MapaRecursos[K]) {
    if (aoClicarItem) return aoClicarItem(item);
    /* A busca, os filtros, a página e a ordem ficam na URL: abrir um
       registro leva a query junto, para a lista atrás do drawer não mudar. */
    if (destinoItem) return navegar({ pathname: destinoItem(item), search });
    return undefined;
  }

  const clicavel = Boolean(destinoItem || aoClicarItem);

  return (
    <div className="space-y-5">
      <CabecalhoPagina
        titulo={titulo}
        descricao={descricao}
        acoes={
          <>
            <SeloOrigem origem={origem} />
            {acoes}
          </>
        }
      />

      {!podeVer ? (
        <EstadoSemPermissao motivo={motivoDaRecusa(sessao.papel, permissaoNecessaria)} />
      ) : (
        <>
          <BarraDeFiltros
            busca={busca}
            aoBuscar={setBusca}
            filtros={definicoesFiltro}
            valores={filtros}
            aoFiltrar={(chave, valor) => definirVarios({ pagina: null, [chave]: valor })}
            aoLimpar={() => {
              setBusca('');
              limpar(['ordenar']);
            }}
            placeholderBusca={placeholderBusca}
          />

          {antesDaTabela?.(itens)}

          {consulta.isPending ? (
            <EstadoCarregando />
          ) : consulta.error ? (
            <EstadoErro erro={consulta.error} aoTentarNovamente={() => void consulta.refetch()} />
          ) : itens.length === 0 ? (
            (estadoVazio ?? (
              <EstadoVazio
                titulo="Nenhum registro encontrado"
                descricao="Ajuste a busca ou os filtros — ou cadastre o primeiro registro deste módulo."
              />
            ))
          ) : (
            <div className="overflow-hidden rounded-lg border bg-card">
              <Table>
                <TableHeader>
                  <TableRow>
                    {colunas.map((coluna) => (
                      <TableHead
                        key={coluna.chave}
                        className={coluna.className}
                        aria-sort={
                          !coluna.ordenarPor
                            ? undefined
                            : ordem?.campo !== coluna.ordenarPor
                              ? 'none'
                              : ordem.desc
                                ? 'descending'
                                : 'ascending'
                        }
                      >
                        {coluna.ordenarPor ? (
                          <CabecalhoOrdenavel
                            rotulo={coluna.cabecalho}
                            campo={coluna.ordenarPor}
                            ordem={ordem}
                            escolhida={Boolean(filtros.ordenar)}
                            aoOrdenar={(proxima) => definirVarios({ ordenar: proxima, pagina: null })}
                          />
                        ) : (
                          coluna.cabecalho
                        )}
                      </TableHead>
                    ))}
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {itens.map((item) => {
                    const id = (item as { id: string }).id;
                    return (
                      <TableRow
                        key={id}
                        data-testid={`linha-${id}`}
                        className={cn(clicavel && 'cursor-pointer')}
                        onClick={clicavel ? () => abrir(item) : undefined}
                      >
                        {colunas.map((coluna) => (
                          <TableCell key={coluna.chave} className={coluna.className}>
                            {coluna.celula(item)}
                          </TableCell>
                        ))}
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </div>
          )}

          {itens.length > 0 ? (
            <div className="flex flex-wrap items-center justify-between gap-3">
              <p className="text-xs text-muted-foreground" data-testid="contagem-registros">
                {formatarNumero(total)} registro(s)
                {totalPaginas > 1 ? ` · página ${pagina} de ${totalPaginas}` : ''}
              </p>

              {totalPaginas > 1 ? (
                <div className="flex items-center gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={pagina <= 1}
                    onClick={() => definir('pagina', pagina <= 2 ? null : String(pagina - 1))}
                  >
                    <ChevronLeft /> Anterior
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={pagina >= totalPaginas}
                    onClick={() => definir('pagina', String(pagina + 1))}
                  >
                    Próxima <ChevronRight />
                  </Button>
                </div>
              ) : null}
            </div>
          ) : null}

          {rodape?.(itens)}
        </>
      )}
    </div>
  );
}
