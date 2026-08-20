import { useId, type ReactNode } from 'react';
import { Label } from '@/components/ui/label';
import { cn } from '@/lib/utils';

/* Envólucro de campo: rótulo, dica, erro e o `aria-invalid` que o
   leitor de tela precisa. Um lugar só, para nenhum formulário do painel
   mostrar erro de um jeito diferente. */
export function Campo({
  rotulo,
  dica,
  erro,
  obrigatorio,
  children,
  className,
}: {
  rotulo: string;
  dica?: ReactNode;
  erro?: string;
  obrigatorio?: boolean;
  children: (props: { id: string; 'aria-invalid': boolean; 'aria-describedby'?: string }) => ReactNode;
  className?: string;
}) {
  const id = useId();
  const idErro = `${id}-erro`;
  const idDica = `${id}-dica`;
  const descrito = [erro ? idErro : null, dica ? idDica : null].filter(Boolean).join(' ');

  return (
    <div className={cn('space-y-1.5', className)}>
      <Label htmlFor={id}>
        {rotulo}
        {obrigatorio ? <span className="ml-0.5 text-coral-600">*</span> : null}
      </Label>
      {children({
        id,
        'aria-invalid': Boolean(erro),
        'aria-describedby': descrito || undefined,
      })}
      {dica ? (
        <p id={idDica} className="text-xs text-muted-foreground">
          {dica}
        </p>
      ) : null}
      {erro ? (
        <p id={idErro} role="alert" className="text-xs font-semibold text-coral-700">
          {erro}
        </p>
      ) : null}
    </div>
  );
}

export function SecaoFormulario({
  titulo,
  descricao,
  children,
}: {
  titulo: string;
  descricao?: string;
  children: ReactNode;
}) {
  return (
    <section className="space-y-4 rounded-lg border bg-card p-5">
      <div className="space-y-0.5">
        <h2 className="text-sm font-black uppercase tracking-wide text-muted-foreground">
          {titulo}
        </h2>
        {descricao ? <p className="text-xs text-muted-foreground">{descricao}</p> : null}
      </div>
      <div className="grid gap-4 md:grid-cols-2">{children}</div>
    </section>
  );
}
