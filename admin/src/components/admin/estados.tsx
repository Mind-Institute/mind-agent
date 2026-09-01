import type { ReactNode } from 'react';
import { AlertTriangle, Inbox, Loader2, Lock, RefreshCw } from 'lucide-react';
import { codigoDoErro, ehErroAdmin } from '@/contracts';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';

/* ============================================================
   OS ESTADOS OBRIGATÓRIOS
   ============================================================
   Toda listagem e todo formulário do painel passa por aqui. São
   componentes, e não trechos copiados, para que "vazio" e "erro"
   tenham a mesma cara em quinze módulos — e para que nenhum deles
   esqueça de tratar um caso. */

export function EstadoCarregando({
  linhas = 5,
  rotulo = 'Carregando…',
}: {
  linhas?: number;
  rotulo?: string;
}) {
  return (
    <div className="space-y-2 p-1" role="status" aria-live="polite" aria-busy="true">
      <span className="sr-only">{rotulo}</span>
      {Array.from({ length: linhas }).map((_, i) => (
        <Skeleton key={i} className="h-11 w-full" />
      ))}
    </div>
  );
}

export function EstadoVazio({
  titulo = 'Nada por aqui ainda',
  descricao,
  acao,
  icone,
}: {
  titulo?: string;
  descricao?: string;
  acao?: ReactNode;
  icone?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 rounded-lg border border-dashed px-6 py-14 text-center">
      <div className="text-muted-foreground">{icone ?? <Inbox className="size-7" />}</div>
      <div className="space-y-1">
        <p className="text-sm font-bold">{titulo}</p>
        {descricao ? (
          <p className="max-w-md text-sm text-muted-foreground">{descricao}</p>
        ) : null}
      </div>
      {acao}
    </div>
  );
}

export function EstadoSemPermissao({ motivo }: { motivo: string }) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 rounded-lg border border-dashed px-6 py-14 text-center">
      <Lock className="size-7 text-muted-foreground" />
      <div className="space-y-1">
        <p className="text-sm font-bold">Sem permissão</p>
        <p className="max-w-lg text-sm text-muted-foreground">{motivo}</p>
        <p className="max-w-lg text-xs text-muted-foreground">
          Este bloqueio é da interface. A recusa definitiva é do backend, contra o papel gravado no
          banco.
        </p>
      </div>
    </div>
  );
}

export function EstadoErro({
  erro,
  aoTentarNovamente,
}: {
  erro: unknown;
  aoTentarNovamente?: () => void;
}) {
  const codigo = codigoDoErro(erro);

  if (codigo === 'sem_permissao') {
    return (
      <EstadoSemPermissao
        motivo={
          ehErroAdmin(erro) ? erro.message : 'A API recusou o acesso a estes dados para o seu papel.'
        }
      />
    );
  }

  const titulos: Record<string, string> = {
    rede: 'Não foi possível carregar',
    indisponivel: 'Serviço indisponível',
    nao_encontrado: 'Registro não encontrado',
    conflito: 'Conflito de atualização',
    validacao: 'Dados recusados',
    sessao_expirada: 'Sessão expirada',
    credenciais_invalidas: 'Credenciais inválidas',
    desconhecido: 'Algo deu errado',
  };

  const mensagem =
    erro instanceof Error ? erro.message : 'Erro inesperado ao falar com a API administrativa.';
  const requestId = ehErroAdmin(erro) ? erro.requestId : undefined;

  return (
    <div className="flex flex-col items-center justify-center gap-3 rounded-lg border border-coral-200 bg-coral-50 px-6 py-12 text-center">
      <AlertTriangle className="size-7 text-coral-600" />
      <div className="space-y-1">
        <p className="text-sm font-bold text-coral-900">{titulos[codigo] ?? titulos.desconhecido}</p>
        <p className="max-w-lg text-sm text-coral-900/80">{mensagem}</p>
        {requestId ? (
          <p className="font-mono text-xs text-coral-900/60">requisição {requestId}</p>
        ) : null}
      </div>
      {aoTentarNovamente ? (
        <Button variant="outline" size="sm" onClick={aoTentarNovamente}>
          <RefreshCw /> Tentar novamente
        </Button>
      ) : null}
    </div>
  );
}


export function Salvando({ className }: { className?: string }) {
  return <Loader2 className={cn('size-4 animate-spin', className)} />;
}
