import { useState } from 'react';
import { Archive, Send } from 'lucide-react';
import type { StatusEditorial } from '@/contracts';
import { useSessao } from '@/hooks/use-sessao';
import { Button } from '@/components/ui/button';
import { DialogoArquivamento } from './dialogos';

/* ============================================================
   AÇÕES DO FLUXO EDITORIAL
   ============================================================
   Regra visual desta fase:
   - editor salva rascunho e envia para revisão;
   - aprovador publica e arquiva;
   - conteúdo publicado mostra data e responsável.

   O botão some quando o papel não permite, mas quem recusa de verdade
   é o backend. Ver `src/lib/permissions.ts`. */
export function AcoesEditoriais({
  status,
  rotulo,
  salvando,
  aoPublicar,
  aoArquivar,
}: {
  status?: StatusEditorial;
  rotulo: string;
  salvando?: boolean;
  aoPublicar?: () => void;
  aoArquivar?: () => void;
}) {
  const sessao = useSessao();
  const [confirmandoArquivar, setConfirmandoArquivar] = useState(false);

  const podePublicar = sessao.pode('publicar');
  const podeArquivar = sessao.pode('arquivar');
  const jaPublicado = status === 'publicado';
  const jaArquivado = status === 'arquivado';

  return (
    <>
      {aoPublicar && podePublicar ? (
        <Button
          type="button"
          variant="secondary"
          onClick={aoPublicar}
          disabled={salvando || jaPublicado || jaArquivado}
          title={jaPublicado ? 'Já está publicado.' : undefined}
        >
          <Send /> Publicar
        </Button>
      ) : null}

      {aoArquivar && podeArquivar ? (
        <Button
          type="button"
          variant="outline"
          onClick={() => setConfirmandoArquivar(true)}
          disabled={salvando || jaArquivado}
        >
          <Archive /> Arquivar
        </Button>
      ) : null}

      <DialogoArquivamento
        aberto={confirmandoArquivar}
        rotulo={rotulo}
        carregando={salvando}
        aoConfirmar={() => {
          setConfirmandoArquivar(false);
          aoArquivar?.();
        }}
        aoCancelar={() => setConfirmandoArquivar(false)}
      />
    </>
  );
}

/** Linha "publicado em X por Y" que todo registro publicado exibe. */
export function InfoPublicacao({
  status,
  publicadoEm,
  publicadoPor,
  atualizadoEm,
  atualizadoPor,
}: {
  status?: StatusEditorial;
  publicadoEm?: string | null;
  publicadoPor?: string | null;
  atualizadoEm?: string;
  atualizadoPor?: string | null;
}) {
  return (
    <span>
      {status === 'publicado' && publicadoEm ? (
        <>
          Publicado em {new Date(publicadoEm).toLocaleString('pt-BR')} por {publicadoPor ?? '—'}.{' '}
        </>
      ) : null}
      {atualizadoEm ? (
        <>
          Última alteração {new Date(atualizadoEm).toLocaleString('pt-BR')}
          {atualizadoPor ? ` por ${atualizadoPor}` : ''}.
        </>
      ) : null}
    </span>
  );
}
