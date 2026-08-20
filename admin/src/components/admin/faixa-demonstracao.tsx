import { FlaskConical, SatelliteDish } from 'lucide-react';
import { useModoDados } from '@/services/provider-context';

/**
 * O painel precisa ser honesto sobre o próprio estado, e o modo
 * híbrido é o momento mais perigoso: número real e cadastro simulado
 * dividindo a mesma tela. Por isso o aviso fica no topo de toda página,
 * não em nota de rodapé onde ninguém lê antes de confiar num número.
 */
export function FaixaDemonstracao() {
  const modo = useModoDados();
  if (modo === 'http') return null;

  if (modo === 'hybrid') {
    return (
      <div
        className="flex items-center gap-2 border-b border-verde-200 bg-verde-50 px-4 py-1.5 text-xs text-verde-900"
        data-testid="faixa-modo"
      >
        <SatelliteDish className="size-3.5 shrink-0" />
        <p>
          <strong className="font-black">Dashboard real · Cadastros em demonstração.</strong> Os
          números da visão geral vêm da API administrativa. Todo o resto ainda é simulado e vive só
          na memória do navegador: editar, publicar, arquivar e reindexar não chegam ao backend.
        </p>
      </div>
    );
  }

  return (
    <div
      className="listra-demo flex items-center gap-2 border-b border-coral-200 bg-coral-50/70 px-4 py-1.5 text-xs text-coral-900"
      data-testid="faixa-modo"
    >
      <FlaskConical className="size-3.5 shrink-0" />
      <p>
        <strong className="font-black">Modo demonstração.</strong> Os dados são simulados e vivem só
        na memória do navegador: recarregar a página desfaz tudo. Nada é gravado no Supabase e
        nenhum documento é indexado de verdade.
      </p>
    </div>
  );
}
