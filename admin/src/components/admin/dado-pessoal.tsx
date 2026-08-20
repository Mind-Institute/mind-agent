import { EyeOff } from 'lucide-react';
import { mascararEmail, mascararIdentificador, mascararNome, mascararTelefone } from '@/lib/mask';
import { cn } from '@/lib/utils';

/* ============================================================
   EXIBIÇÃO DE DADO PESSOAL
   ============================================================
   Componente, e não chamada solta de função, porque assim é possível
   procurar no código quem mostra dado pessoal — e porque nenhuma tela
   consegue "esquecer" de mascarar sem que fique visível na revisão.

   Não existe botão de "revelar" nesta versão. Ver o dado inteiro é
   decisão de backend, com registro em auditoria. */

type Tipo = 'email' | 'telefone' | 'nome' | 'identificador';

const MASCARA: Record<Tipo, (v: string | null | undefined) => string> = {
  email: mascararEmail,
  telefone: mascararTelefone,
  nome: mascararNome,
  identificador: mascararIdentificador,
};

export function DadoPessoal({
  valor,
  tipo = 'identificador',
  className,
  comIcone = false,
}: {
  valor: string | null | undefined;
  tipo?: Tipo;
  className?: string;
  comIcone?: boolean;
}) {
  const mascarado = MASCARA[tipo](valor);
  return (
    <span
      className={cn('inline-flex items-center gap-1 tabular', className)}
      title="Dado pessoal mascarado"
      data-mascarado="true"
    >
      {comIcone ? <EyeOff className="size-3 text-muted-foreground" /> : null}
      {mascarado}
    </span>
  );
}

/** Contato de conversa: escolhe a máscara pelo formato do valor. */
export function ContatoMascarado({ valor }: { valor: string | null | undefined }) {
  if (!valor) return <span className="text-muted-foreground">—</span>;
  const tipo: Tipo = valor.includes('@') ? 'email' : 'telefone';
  return <DadoPessoal valor={valor} tipo={tipo} />;
}
