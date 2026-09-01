import { useState } from 'react';
import { Outlet } from 'react-router-dom';
import { BarraLateral } from './barra-lateral';
import { BarraSuperior } from './barra-superior';
import { Sheet, SheetContent, SheetTitle } from '@/components/ui/sheet';

export function AdminLayout() {
  const [menuAberto, setMenuAberto] = useState(false);

  return (
    <div className="flex min-h-screen bg-background">
      <aside className="hidden w-64 shrink-0 border-r bg-card lg:block">
        <div className="sticky top-0 h-screen">
          <BarraLateral />
        </div>
      </aside>

      <Sheet open={menuAberto} onOpenChange={setMenuAberto}>
        <SheetContent side="left" className="w-72 p-0">
          <SheetTitle className="sr-only">Navegação principal</SheetTitle>
          <BarraLateral aoNavegar={() => setMenuAberto(false)} />
        </SheetContent>
      </Sheet>

      <div className="flex min-w-0 flex-1 flex-col">
        <BarraSuperior aoAbrirMenu={() => setMenuAberto(true)} />
        <main className="flex-1 p-4 md:p-6">
          <div className="mx-auto max-w-7xl">
            <Outlet />
          </div>
        </main>
      </div>
    </div>
  );
}
