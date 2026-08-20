import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { AlertTriangle, LogIn } from 'lucide-react';
import simboloMind from '@marca/simbolo-mind-verde.png';
import { codigoDoErro } from '@/contracts';
import { useSessao } from '@/hooks/use-sessao';
import { Campo } from '@/components/admin/campo';
import { Salvando } from '@/components/admin/estados';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';

const loginSchema = z.object({
  email: z.string().min(1, 'Informe o e-mail.').email('Informe um e-mail válido.'),
  senha: z.string().min(1, 'Informe a senha.'),
});

type LoginForm = z.infer<typeof loginSchema>;

/** Mensagens por código — a tela diz o que fazer, não o que quebrou. */
function mensagemDoErro(erro: unknown): { titulo: string; descricao: string } | null {
  if (!erro) return null;
  const codigo = codigoDoErro(erro);
  const mensagem = erro instanceof Error ? erro.message : 'Não foi possível entrar.';

  switch (codigo) {
    case 'credenciais_invalidas':
      return { titulo: 'Não foi possível entrar', descricao: mensagem };
    case 'sem_permissao':
      return {
        titulo: 'Sem acesso ao painel',
        descricao:
          'Esta conta existe, mas não tem papel administrativo cadastrado. Fale com quem administra o Mind Agent.',
      };
    case 'rede':
      return {
        titulo: 'Sem conexão com o serviço',
        descricao: 'Não foi possível falar com o Supabase. Confira a rede e tente de novo.',
      };
    case 'indisponivel':
      return { titulo: 'Serviço indisponível', descricao: mensagem };
    default:
      return { titulo: 'Algo deu errado', descricao: mensagem };
  }
}

export function PaginaLogin() {
  const sessao = useSessao();
  const aviso = mensagemDoErro(sessao.erro);

  const formulario = useForm<LoginForm>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: '', senha: '' },
  });

  async function enviar(valores: LoginForm) {
    try {
      await sessao.entrar(valores.email.trim(), valores.senha);
    } catch {
      /* O erro já está no contexto e aparece no aviso acima do formulário. */
      formulario.setValue('senha', '');
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-background p-6">
      <div className="w-full max-w-sm space-y-6">
        <header className="space-y-2 text-center">
          <img src={simboloMind} alt="" className="mx-auto size-10" />
          <div>
            <h1 className="text-lg font-black tracking-tight">Mind Agent</h1>
            <p className="text-[11px] font-semibold uppercase tracking-widest text-muted-foreground">
              Administração
            </p>
          </div>
        </header>

        {sessao.expirou ? (
          <Alert variant="atencao">
            <AlertTriangle />
            <AlertTitle>Sua sessão expirou</AlertTitle>
            <AlertDescription>Entre novamente para continuar de onde parou.</AlertDescription>
          </Alert>
        ) : null}

        {aviso ? (
          <Alert variant="erro" data-testid="erro-login">
            <AlertTriangle />
            <AlertTitle>{aviso.titulo}</AlertTitle>
            <AlertDescription>{aviso.descricao}</AlertDescription>
          </Alert>
        ) : null}

        <form
          onSubmit={formulario.handleSubmit(enviar)}
          className="space-y-4 rounded-lg border bg-card p-5"
          noValidate
        >
          <Campo rotulo="E-mail" obrigatorio erro={formulario.formState.errors.email?.message}>
            {(p) => (
              <Input
                type="email"
                autoComplete="username"
                autoFocus
                {...p}
                {...formulario.register('email')}
              />
            )}
          </Campo>

          <Campo rotulo="Senha" obrigatorio erro={formulario.formState.errors.senha?.message}>
            {(p) => (
              <Input
                type="password"
                autoComplete="current-password"
                {...p}
                {...formulario.register('senha')}
              />
            )}
          </Campo>

          <Button type="submit" className="w-full" disabled={sessao.carregandoLogin}>
            {sessao.carregandoLogin ? <Salvando /> : <LogIn />}
            Entrar
          </Button>
        </form>

        <p className="text-center text-xs leading-relaxed text-muted-foreground">
          O acesso é validado pelo Supabase Auth. O papel e as permissões vêm de{' '}
          <code className="font-mono">/admin/me</code>, conferidos no backend contra o banco.
        </p>
      </div>
    </div>
  );
}
