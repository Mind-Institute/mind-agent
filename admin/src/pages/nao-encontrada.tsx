import { Link } from 'react-router-dom';
import { Compass } from 'lucide-react';
import { Button } from '@/components/ui/button';

export function PaginaNaoEncontrada() {
  return (
    <div className="flex flex-col items-center justify-center gap-4 py-24 text-center">
      <Compass className="size-8 text-muted-foreground" />
      <div className="space-y-1">
        <h1 className="text-xl font-black">Esta página não existe no painel</h1>
        <p className="text-sm text-muted-foreground">
          Confira o endereço ou volte para a visão geral.
        </p>
      </div>
      <Button asChild>
        <Link to="/">Ir para a visão geral</Link>
      </Button>
    </div>
  );
}
