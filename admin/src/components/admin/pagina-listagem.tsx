import { useMemo, useState, type ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import type { ListFilters, MapaRecursos, NomeRecurso } from '@/contracts';
import { useLista } from '@/hooks/use-recurso';
import { useFiltrosUrl } from '@/hooks/use-filtros-url';
import { useSessao } from '@/hooks/use-sessao';
import { motivoDaRecusa, type Acao } from '@/lib/permissions';
import { CabecalhoPagina } from './cabecalho-pagina';
import { BarraDeFiltros, type DefinicaoFiltro } from './barra-filtros';
import { EstadoCarregando, EstadoErro, EstadoSemPermissao, EstadoVazio } from './estados';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { cn } from '@/lib/utils';

export interface Coluna<T> {
  chave: string;
  cabecalho: string;
  celula: (item: T) => ReactNode;
  className?: string;
}

/* ============================================================
   LISTAGEM PADRÃO
   ============================================================
   Quinze módulos, uma listagem. Cada página descreve as colunas e os
   filtros; carregamento, vazio, erro, sem permissão e busca vêm de
   graça — e iguais em todas.

   Trocar o mock por HTTP não toca aqui: o componente só conhece
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
  const sessao = useSessao();
  const { filtros, paraProvedor, definir, limpar } = useFiltrosUrl();
  const [busca, setBusca] = useState(filtros.busca ?? '');

  const filtrosConsulta = useMemo<ListFilters>(
    () => ({ ...filtrosFixos, ...paraProvedor, busca: busca || undefined, ordenar }),
    [filtrosFixos, paraProvedor, busca, ordenar],
  );

  const podeVer = sessao.pode(permissaoNecessaria);
  const consulta = useLista(recurso, filtrosConsulta, { enabled: podeVer });
  const itens = consulta.data?.itens ?? [];

  function abrir(item: MapaRecursos[K]) {
    if (aoClicarItem) return aoClicarItem(item);
    if (destinoItem) return navegar(destinoItem(item));
    return undefined;
  }

  const clicavel = Boolean(destinoItem || aoClicarItem);

  return (
    <div className="space-y-5">
      <CabecalhoPagina titulo={titulo} descricao={descricao} acoes={acoes} />

      {!podeVer ? (
        <EstadoSemPermissao motivo={motivoDaRecusa(sessao.papel, permissaoNecessaria)} />
      ) : (
        <>
          <BarraDeFiltros
            busca={busca}
            aoBuscar={setBusca}
            filtros={definicoesFiltro}
            valores={filtros}
            aoFiltrar={definir}
            aoLimpar={() => {
              setBusca('');
              limpar();
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
                      <TableHead key={coluna.chave} className={coluna.className}>
                        {coluna.cabecalho}
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
            <p className="text-xs text-muted-foreground">
              {consulta.data?.total ?? itens.length} registro(s).
            </p>
          ) : null}

          {rodape?.(itens)}
        </>
      )}
    </div>
  );
}
