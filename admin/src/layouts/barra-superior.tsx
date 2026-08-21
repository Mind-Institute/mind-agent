import { LogOut, Menu } from 'lucide-react';
import { useLocation } from 'react-router-dom';
import { PAPEIS, ROTULO_PAPEL, type Papel } from '@/contracts';
import { useSessao } from '@/hooks/use-sessao';
import { useModoDados } from '@/services/provider-context';
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

/* Selo curto; a faixa logo abaixo nomeia módulo por módulo. */
const ROTULO_MODO: Record<string, { texto: string; variante: 'sucesso' | 'destructive' | 'atencao' }> = {
  mock: { texto: 'dados simulados', variante: 'destructive' },
  hybrid: { texto: 'núcleo real · apoio em demonstração', variante: 'atencao' },
  http: { texto: 'API administrativa', variante: 'sucesso' },
};

export function BarraSuperior({ aoAbrirMenu }: { aoAbrirMenu: () => void }) {
  const sessao = useSessao();
  const modo = useModoDados();
  const local = useLocation();
  const item = itemPorCaminho(local.pathname);
  const rotuloModo = ROTULO_MODO[modo] ?? ROTULO_MODO.mock;

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

      <Badge variant={rotuloModo.variante} className="hidden sm:inline-flex">
        {rotuloModo.texto}
      </Badge>

      {sessao.simulada ? (
        /* Seletor de papel: simulador de interface, não login.
           Ver o cabeçalho de src/lib/permissions.ts. */
        <div className="flex items-center gap-2">
          <span className="hidden text-xs text-muted-foreground md:inline">Ver como</span>
          <Select value={sessao.papel} onValueChange={(v) => sessao.definirPapel(v as Papel)}>
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
      ) : (
        /* Autenticado: o papel é o que /admin/me devolveu. Não há
           seletor — trocar de papel na tela seria mentira. */
        <div className="flex items-center gap-3">
          <div className="hidden text-right leading-tight sm:block">
            <p className="max-w-48 truncate text-xs font-bold">{sessao.nome}</p>
            <p className="text-[11px] text-muted-foreground">{ROTULO_PAPEL[sessao.papel]}</p>
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={() => void sessao.sair()}
            aria-label="Sair da conta"
          >
            <LogOut /> Sair
          </Button>
        </div>
      )}
    </header>
  );
}
