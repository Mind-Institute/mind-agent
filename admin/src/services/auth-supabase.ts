import { createClient, type Session, type SupabaseClient } from '@supabase/supabase-js';
import { AdminApiError, type SessaoAuth } from '@/contracts';
import type { PortaAutenticacao } from './auth';

/* ============================================================
   Supabase Auth
   ============================================================
   O cliente é criado com a chave PUBLICÁVEL (anon) — a única que pode
   estar no navegador. `service_role` e secret key não aparecem aqui,
   e não devem aparecer: elas ignoram RLS e valem como senha mestra.

   Deste cliente o painel usa exatamente uma coisa: a sessão. Consulta
   administrativa a tabela nenhuma passa por aqui — quem fala com o
   banco é a Edge Function. */

export interface OpcoesSupabase {
  url: string;
  chavePublicavel: string;
  /** Trocável nos testes; em produção é o `localStorage`. */
  storage?: Storage;
  /** Para onde o Google devolve a pessoa. Precisa estar nas Redirect URLs do Supabase. */
  redirecionarPara?: string;
}

/* Só contas do Workspace da Mind. O `hd` faz o Google mostrar só elas;
   quem garante é o app de login "Interno" do Workspace e, de novo, o
   banco (`mind_admin_vincular_login`). */
const DOMINIO_GOOGLE = 'joinmind.com.br';

/** `Session` do Supabase → o mínimo que o painel usa. */
function paraSessaoAuth(sessao: Session | null): SessaoAuth | null {
  if (!sessao?.access_token) return null;
  return {
    accessToken: sessao.access_token,
    usuarioId: sessao.user?.id ?? '',
    email: sessao.user?.email ?? null,
    expiraEm: sessao.expires_at ?? null,
  };
}

/**
 * Erros do Supabase → o vocabulário do painel.
 *
 * A mensagem crua (`Invalid login credentials`) não vai para a tela:
 * ela é em inglês e não diz o que fazer.
 */
function traduzirErro(erro: { message?: string; code?: string; status?: number }): AdminApiError {
  const codigo = erro.code ?? '';
  const mensagem = erro.message ?? 'Falha ao autenticar.';

  if (codigo === 'invalid_credentials' || /invalid login credentials/i.test(mensagem)) {
    return new AdminApiError('credenciais_invalidas', 'E-mail ou senha incorretos.');
  }
  if (codigo === 'email_not_confirmed' || /email not confirmed/i.test(mensagem)) {
    return new AdminApiError(
      'credenciais_invalidas',
      'Este e-mail ainda não foi confirmado. Confira a caixa de entrada.',
    );
  }
  if (codigo === 'over_request_rate_limit' || erro.status === 429) {
    return new AdminApiError(
      'indisponivel',
      'Muitas tentativas seguidas. Espere um minuto antes de tentar de novo.',
    );
  }
  if (/fetch|network|failed to fetch/i.test(mensagem)) {
    return new AdminApiError('rede', 'Não foi possível falar com o serviço de autenticação.');
  }
  return new AdminApiError('desconhecido', mensagem);
}

export function criarPortaSupabase(opcoes: OpcoesSupabase): PortaAutenticacao {
  const cliente: SupabaseClient = createClient(opcoes.url, opcoes.chavePublicavel, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      /* A volta do Google traz um `?code=` que só vira sessão com o
         verificador guardado neste navegador na ida (PKCE). Um código
         colado de fora não abre nada. Magic link o painel não usa. */
      flowType: 'pkce',
      detectSessionInUrl: true,
      storageKey: 'mindagent-admin-auth',
      ...(opcoes.storage ? { storage: opcoes.storage } : {}),
    },
  });

  return {
    async obterSessao() {
      const { data, error } = await cliente.auth.getSession();
      /* A volta do Google já foi trocada por sessão aqui (`getSession`
         espera a inicialização). O `code` sai do endereço para não ficar
         no histórico nem ir junto num print. */
      limparCodigoDaUrl();
      if (error) throw traduzirErro(error);
      return paraSessaoAuth(data.session);
    },

    aoMudarSessao(ouvinte) {
      const { data } = cliente.auth.onAuthStateChange((_evento, sessao) => {
        ouvinte(paraSessaoAuth(sessao));
      });
      return () => data.subscription.unsubscribe();
    },

    async entrar(email, senha) {
      const { data, error } = await cliente.auth.signInWithPassword({ email, password: senha });
      if (error) throw traduzirErro(error);
      const sessao = paraSessaoAuth(data.session);
      if (!sessao) {
        throw new AdminApiError('desconhecido', 'O login não devolveu sessão.');
      }
      return sessao;
    },

    async entrarComGoogle() {
      const { error } = await cliente.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: opcoes.redirecionarPara,
          queryParams: { hd: DOMINIO_GOOGLE, prompt: 'select_account' },
        },
      });
      if (error) throw traduzirErro(error);
    },

    async sair() {
      const { error } = await cliente.auth.signOut();
      /* Sessão que já não existe no servidor não é falha de logout:
         o objetivo — sair — foi atingido de qualquer jeito. */
      if (error && error.status !== 401 && error.status !== 403) throw traduzirErro(error);
    },

    encerrar() {
      void cliente.auth.stopAutoRefresh();
    },
  };
}

/** Tira `code`, `error` e `error_description` da barra de endereço, sem recarregar. */
function limparCodigoDaUrl() {
  if (typeof window === 'undefined') return;
  const endereco = new URL(window.location.href);
  let mudou = false;
  for (const chave of ['code', 'error', 'error_code', 'error_description']) {
    if (endereco.searchParams.has(chave)) {
      endereco.searchParams.delete(chave);
      mudou = true;
    }
  }
  if (mudou) window.history.replaceState(window.history.state, '', endereco.toString());
}

/** Cria a porta a partir do ambiente. `null` quando não configurado. */
export function criarPortaSupabaseDoAmbiente(): PortaAutenticacao | null {
  const url = import.meta.env.VITE_SUPABASE_URL?.trim();
  const chave = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!url || !chave) return null;
  /* O Google devolve para a raiz do painel (`/admin/`), no mesmo
     endereço em que a pessoa está — produção ou preview. */
  const redirecionarPara =
    typeof window === 'undefined' ? undefined : `${window.location.origin}${import.meta.env.BASE_URL}`;
  return criarPortaSupabase({ url, chavePublicavel: chave, redirecionarPara });
}
