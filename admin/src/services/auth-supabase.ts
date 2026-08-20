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
}

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
      /* O painel não usa magic link nesta etapa; ler a URL atrás de
         token só criaria caminho para confusão. */
      detectSessionInUrl: false,
      storageKey: 'mindagent-admin-auth',
      ...(opcoes.storage ? { storage: opcoes.storage } : {}),
    },
  });

  return {
    async obterSessao() {
      const { data, error } = await cliente.auth.getSession();
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

/** Cria a porta a partir do ambiente. `null` quando não configurado. */
export function criarPortaSupabaseDoAmbiente(): PortaAutenticacao | null {
  const url = import.meta.env.VITE_SUPABASE_URL?.trim();
  const chave = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!url || !chave) return null;
  return criarPortaSupabase({ url, chavePublicavel: chave });
}
