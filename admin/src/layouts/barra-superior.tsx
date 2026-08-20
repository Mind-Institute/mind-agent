import { Menu } from 'lucide-react';
import { useLocation } from 'react-router-dom';
import { PAPEIS, ROTULO_PAPEL, type Papel } from '@/contracts';
import { useSessao } from '@/hooks/use-sessao';
import { useAdminData } from '@/services/provider-context';
import { itemPorCaminho } from '@/routes/navegacao';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

export function BarraSuperior({ aoAbrirMenu }: { aoAbrirMenu: () => void }) {
  const sessao = useSessao();
  const provedor = useAdminData();
  const local = useLocation();
  const item = itemPorCaminho(local.pathname);

  return (
    <header className="flex items-center gap-3 border-b bg-card px-4 py-2.5">
      <Button
        variant="ghost"
        size="icon"
        className="lg:hidden"
        onClick={aoAbrirMenu}
        aria-label="Abrir menu"
      >
        <Menu />
      </Button>

      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-bold">{item?.rotulo ?? 'Painel'}</p>
        <p className="truncate text-xs text-muted-foreground">{item?.descricao}</p>
      </div>

      <Badge variant={provedor.modo === 'mock' ? 'destructive' : 'sucesso'} className="hidden sm:inline-flex">
        {provedor.modo === 'mock' ? 'dados simulados' : 'API administrativa'}
      </Badge>

      {/* Seletor de papel: simulador de interface, não login.
          Ver o cabeçalho de src/lib/permissions.ts. */}
      <div className="flex items-center gap-2">
        <span className="hidden text-xs text-muted-foreground md:inline">Ver como</span>
        <Select
          value={sessao.papel}
          onValueChange={(valor) => sessao.definirPapel(valor as Papel)}
        >
          <SelectTrigger className="h-8 w-40" aria-label="Papel simulado">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {PAPEIS.map((papel) => (
              <SelectItem key={papel} value={papel}>
                {ROTULO_PAPEL[papel]}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
    </header>
  );
}
