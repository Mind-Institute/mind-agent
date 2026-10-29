import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import MiaVitrine from '@/components/mia-vitrine';
import './index.css';

/* Monta SÓ a demo. Nada de `Provedores`, de roteador ou de porta do Supabase:
   a peça é controlada e não fala com servidor nenhum, então tudo isso seria
   andaime para olhar um componente.

   O `index.css` entra porque é ele que declara os tokens do shadcn
   (`--muted-foreground`, `--foreground`, `--card`…). Sem ele o componente
   monta e aparece sem cor nenhuma — e o degradê do "pensando", que é o
   detalhe que esta vitrine existe para conferir, não teria como ser julgado. */
const raiz = document.getElementById('raiz');
if (raiz) {
  createRoot(raiz).render(
    <StrictMode>
      <MiaVitrine />
    </StrictMode>,
  );
}
