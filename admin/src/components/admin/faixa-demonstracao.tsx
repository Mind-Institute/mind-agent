import { FlaskConical, SatelliteDish } from 'lucide-react';
import { useModoDados } from '@/services/provider-context';

/**
 * O painel precisa ser honesto sobre o próprio estado, e o modo
 * híbrido é o momento mais perigoso: módulo real e módulo simulado
 * dividindo a mesma barra lateral. Por isso a faixa nomeia quais são
 * quais, no topo de toda página — não em nota de rodapé, onde ninguém
 * lê antes de confiar num número.
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
          <strong className="font-black">
            Evento, programação, palestrantes e espaços reais · Demais módulos em demonstração.
          </strong>{' '}
          A visão geral e esses quatro módulos leem e gravam na API administrativa. Rotas, estandes,
          ofertas, conteúdo, documentos, conversas, perguntas, usuários e auditoria vivem só na
          memória do navegador.
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
