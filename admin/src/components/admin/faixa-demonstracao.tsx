import { FlaskConical } from 'lucide-react';
import { useModoDemonstracao } from '@/services/provider-context';

/**
 * O painel precisa ser honesto sobre o próprio estado. Enquanto roda em
 * mock, isso aparece no topo de toda página — não em nota de rodapé,
 * onde ninguém lê antes de confiar num número.
 */
export function FaixaDemonstracao() {
  const demonstracao = useModoDemonstracao();
  if (!demonstracao) return null;

  return (
    <div className="listra-demo flex items-center gap-2 border-b border-coral-200 bg-coral-50/70 px-4 py-1.5 text-xs text-coral-900">
      <FlaskConical className="size-3.5 shrink-0" />
      <p>
        <strong className="font-black">Modo demonstração.</strong> Os dados são simulados e vivem só
        na memória do navegador: recarregar a página desfaz tudo. Nada é gravado no Supabase e
        nenhum documento é indexado de verdade.
      </p>
    </div>
  );
}
