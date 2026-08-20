import type { ReactNode } from 'react';
import { AlertTriangle, Archive } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';

/* ============================================================
   CONFIRMAÇÕES
   ============================================================
   Duas, e só duas, porque são os dois pontos onde alguém perde
   trabalho: arquivar um registro e sair de um formulário sujo. */

export function DialogoConfirmacao({
  aberto,
  titulo,
  descricao,
  rotuloConfirmar = 'Confirmar',
  rotuloCancelar = 'Cancelar',
  destrutivo = false,
  carregando = false,
  icone,
  aoConfirmar,
  aoCancelar,
}: {
  aberto: boolean;
  titulo: string;
  descricao: ReactNode;
  rotuloConfirmar?: string;
  rotuloCancelar?: string;
  destrutivo?: boolean;
  carregando?: boolean;
  icone?: ReactNode;
  aoConfirmar: () => void;
  aoCancelar: () => void;
}) {
  return (
    <Dialog open={aberto} onOpenChange={(estado) => (!estado ? aoCancelar() : undefined)}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            {icone ?? <AlertTriangle className="size-5 text-amber-600" />}
            {titulo}
          </DialogTitle>
          <DialogDescription asChild>
            <div className="pt-1 text-sm text-muted-foreground">{descricao}</div>
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={aoCancelar} disabled={carregando}>
            {rotuloCancelar}
          </Button>
          <Button
            variant={destrutivo ? 'destructive' : 'default'}
            onClick={aoConfirmar}
            disabled={carregando}
          >
            {rotuloConfirmar}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function DialogoArquivamento({
  aberto,
  rotulo,
  carregando,
  aoConfirmar,
  aoCancelar,
}: {
  aberto: boolean;
  rotulo: string;
  carregando?: boolean;
  aoConfirmar: () => void;
  aoCancelar: () => void;
}) {
  return (
    <DialogoConfirmacao
      aberto={aberto}
      icone={<Archive className="size-5 text-amber-600" />}
      titulo="Arquivar registro"
      descricao={
        <div className="space-y-2">
          <p>
            <strong className="text-foreground">{rotulo}</strong> sai das listagens ativas e deixa de
            alimentar o agente.
          </p>
          <p>
            O registro <strong className="text-foreground">não é apagado</strong>: continua no banco
            e na auditoria, e pode ser reativado. O painel prefere arquivar a excluir de vez.
          </p>
        </div>
      }
      rotuloConfirmar="Arquivar"
      carregando={carregando}
      aoConfirmar={aoConfirmar}
      aoCancelar={aoCancelar}
    />
  );
}

export function DialogoAlteracoesNaoSalvas({
  aberto,
  aoDescartar,
  aoFicar,
}: {
  aberto: boolean;
  aoDescartar: () => void;
  aoFicar: () => void;
}) {
  return (
    <DialogoConfirmacao
      aberto={aberto}
      titulo="Você tem alterações não salvas"
      descricao="Se sair agora, o que foi editado nesta tela é perdido."
      rotuloConfirmar="Sair sem salvar"
      rotuloCancelar="Continuar editando"
      destrutivo
      aoConfirmar={aoDescartar}
      aoCancelar={aoFicar}
    />
  );
}

/** Conflito de atualização: alguém salvou o mesmo registro antes. */
export function DialogoConflito({
  aberto,
  aoRecarregar,
  aoFechar,
}: {
  aberto: boolean;
  aoRecarregar: () => void;
  aoFechar: () => void;
}) {
  return (
    <DialogoConfirmacao
      aberto={aberto}
      titulo="Conflito de atualização"
      descricao={
        <div className="space-y-2">
          <p>
            Este registro mudou depois que você abriu a tela. Salvar agora apagaria a alteração da
            outra pessoa.
          </p>
          <p>Recarregue a versão atual e reaplique o que você mudou.</p>
        </div>
      }
      rotuloConfirmar="Recarregar versão atual"
      rotuloCancelar="Manter minha tela"
      aoConfirmar={aoRecarregar}
      aoCancelar={aoFechar}
    />
  );
}
