import { Search, X } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

export interface OpcaoFiltro {
  valor: string;
  rotulo: string;
}

export interface DefinicaoFiltro {
  chave: string;
  rotulo: string;
  opcoes: OpcaoFiltro[];
}

/**
 * Busca + selects, com o estado inteiro na URL. Um filtro escolhido é
 * um link compartilhável — e é assim que a visão geral aponta para a
 * lista que explica cada número.
 */
export function BarraDeFiltros({
  busca,
  aoBuscar,
  filtros,
  valores,
  aoFiltrar,
  aoLimpar,
  placeholderBusca = 'Buscar…',
}: {
  busca: string;
  aoBuscar: (valor: string) => void;
  filtros: DefinicaoFiltro[];
  valores: Record<string, string>;
  aoFiltrar: (chave: string, valor: string) => void;
  aoLimpar: () => void;
  placeholderBusca?: string;
}) {
  const temAlgumFiltro =
    Boolean(busca) || filtros.some((f) => valores[f.chave] && valores[f.chave] !== 'todos');

  return (
    <div className="flex flex-wrap items-center gap-2">
      <div className="relative min-w-56 flex-1">
        <Search className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={busca}
          onChange={(e) => aoBuscar(e.target.value)}
          placeholder={placeholderBusca}
          className="pl-8"
          aria-label="Buscar"
          type="search"
        />
      </div>

      {filtros.map((filtro) => (
        <Select
          key={filtro.chave}
          value={valores[filtro.chave] || 'todos'}
          onValueChange={(valor) => aoFiltrar(filtro.chave, valor)}
        >
          <SelectTrigger className="w-auto min-w-40" aria-label={filtro.rotulo}>
            <SelectValue placeholder={filtro.rotulo} />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="todos">{filtro.rotulo}: todos</SelectItem>
            {filtro.opcoes.map((opcao) => (
              <SelectItem key={opcao.valor} value={opcao.valor}>
                {opcao.rotulo}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      ))}

      {temAlgumFiltro ? (
        <Button variant="ghost" size="sm" onClick={aoLimpar}>
          <X /> Limpar
        </Button>
      ) : null}
    </div>
  );
}
