import { useState, type ReactNode } from 'react';
import { Save } from 'lucide-react';
import { Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle } from '@/components/ui/sheet';
import { Button } from '@/components/ui/button';
import { DialogoConfirmacao } from './dialogos';
import { Salvando } from './estados';

/* ============================================================
   DRAWER DE EDIÇÃO
   ============================================================
   Editar sem perder a listagem de vista. O fechamento passa pela
   mesma checagem de alterações não salvas que a troca de rota — sair
   por aqui não pode ser a brecha por onde o trabalho some. */
export function DrawerEdicao({
  aberto,
  titulo,
  descricao,
  sujo,
  salvando,
  podeSalvar = true,
  idFormulario,
  acoes,
  informacao,
  aoFechar,
  children,
}: {
  aberto: boolean;
  titulo: string;
  descricao?: ReactNode;
  sujo: boolean;
  salvando?: boolean;
  podeSalvar?: boolean;
  idFormulario: string;
  acoes?: ReactNode;
  informacao?: ReactNode;
  aoFechar: () => void;
  children: ReactNode;
}) {
  const [confirmandoSaida, setConfirmandoSaida] = useState(false);

  function tentarFechar() {
    if (sujo) setConfirmandoSaida(true);
    else aoFechar();
  }

  return (
    <>
      <Sheet open={aberto} onOpenChange={(estado) => (!estado ? tentarFechar() : undefined)}>
        <SheetContent side="right" className="w-full p-0 sm:max-w-2xl">
          <SheetHeader>
            <SheetTitle>{titulo}</SheetTitle>
            {descricao ? <SheetDescription asChild><div>{descricao}</div></SheetDescription> : null}
          </SheetHeader>

          <div className="flex-1 overflow-y-auto p-5">{children}</div>

          <SheetFooter className="flex-col items-stretch gap-2 sm:flex-row sm:items-center sm:justify-between">
            <div className="text-xs text-muted-foreground">{informacao}</div>
            <div className="flex flex-wrap items-center justify-end gap-2">
              {acoes}
              <Button variant="outline" onClick={tentarFechar} type="button">
                Fechar
              </Button>
              <Button type="submit" form={idFormulario} disabled={!podeSalvar || !sujo || salvando}>
                {salvando ? <Salvando /> : <Save />}
                Salvar
              </Button>
            </div>
          </SheetFooter>
        </SheetContent>
      </Sheet>

      <DialogoConfirmacao
        aberto={confirmandoSaida}
        titulo="Você tem alterações não salvas"
        descricao="Fechar agora descarta o que foi editado neste formulário."
        rotuloConfirmar="Descartar e fechar"
        rotuloCancelar="Continuar editando"
        destrutivo
        aoConfirmar={() => {
          setConfirmandoSaida(false);
          aoFechar();
        }}
        aoCancelar={() => setConfirmandoSaida(false)}
      />
    </>
  );
}
