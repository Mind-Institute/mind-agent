import type { ReactNode } from 'react';
import { Loader2, LogOut, RefreshCw, ShieldAlert } from 'lucide-react';
import { codigoDoErro, ehErroAdmin } from '@/contracts';
import { useSessao } from '@/hooks/use-sessao';
import { PaginaLogin } from '@/pages/login';
import { Button } from '@/components/ui/button';

/* ============================================================
   GUARDA DE AUTENTICAÇÃO
   ============================================================
   Fica FORA do roteador: enquanto não há sessão e perfil, não existe
   painel — nem barra lateral, nem rota. É mais honesto que renderizar
   a casca e ir escondendo pedaço.

   No modo simulado ela é transparente, e é isso que mantém o painel
   utilizável em demonstração sem backend. */

function Aguardando({ texto }: { texto: string }) {
  return (
    <div
      className="flex min-h-screen flex-col items-center justify-center gap-3 bg-background"
      role="status"
      aria-live="polite"
      aria-busy="true"
    >
      <Loader2 className="size-6 animate-spin text-primary" />
      <p className="text-sm text-muted-foreground">{texto}</p>
    </div>
  );
}

/** Autenticado no Supabase, mas `/admin/me` não deixou entrar. */
function PerfilRecusado() {
  const sessao = useSessao();
  const codigo = codigoDoErro(sessao.erro);
  const mensagem = ehErroAdmin(sessao.erro)
    ? sessao.erro.message
    : 'Não foi possível confirmar suas permissões.';

  const semPapel = codigo === 'sem_permissao';
  const indisponivel = codigo === 'rede' || codigo === 'indisponivel';

  return (
    <div className="flex min-h-screen items-center justify-center bg-background p-6">
      <div className="w-full max-w-md space-y-5 rounded-lg border bg-card p-6 text-center">
        <ShieldAlert
          className={`mx-auto size-8 ${semPapel ? 'text-coral-600' : 'text-amber-600'}`}
        />
        <div className="space-y-1">
          <h1 className="text-base font-black">
            {semPapel
              ? 'Sua conta não tem acesso ao painel'
              : indisponivel
                ? 'A API administrativa não respondeu'
                : 'Não foi possível confirmar seu papel'}
          </h1>
          <p className="text-sm text-muted-foreground">{mensagem}</p>
          {semPapel ? (
            <p className="text-sm text-muted-foreground">
              O login funcionou, mas o backend não encontrou papel administrativo para você. Quem
              concede isso é quem administra o Mind Agent — o painel não tem como se autorizar.
            </p>
          ) : null}
          {sessao.email ? (
            <p className="pt-1 text-xs text-muted-foreground">Conta: {sessao.email}</p>
          ) : null}
        </div>

        <div className="flex flex-col gap-2 sm:flex-row sm:justify-center">
          {!semPapel ? (
            <Button variant="outline" onClick={sessao.recarregarPerfil}>
              <RefreshCw /> Tentar novamente
            </Button>
          ) : null}
          <Button variant={semPapel ? 'default' : 'secondary'} onClick={() => void sessao.sair()}>
            <LogOut /> Sair
          </Button>
        </div>
      </div>
    </div>
  );
}

export function GuardaAutenticacao({ children }: { children: ReactNode }) {
  const sessao = useSessao();

  /* Demonstração sem backend: nada a guardar. */
  if (sessao.simulada) return <>{children}</>;

  switch (sessao.estado) {
    case 'carregando':
      return <Aguardando texto="Restaurando sua sessão…" />;
    case 'anonimo':
      return <PaginaLogin />;
    case 'carregando_perfil':
      return <Aguardando texto="Confirmando suas permissões…" />;
    case 'erro_perfil':
      return <PerfilRecusado />;
    case 'autenticado':
      return <>{children}</>;
    default:
      return <Aguardando texto="Carregando…" />;
  }
}
