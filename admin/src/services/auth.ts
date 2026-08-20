import type { SessaoAuth } from '@/contracts';

/* ============================================================
   PORTA DE AUTENTICAÇÃO
   ============================================================
   O painel não conhece o Supabase — conhece esta interface. São quatro
   operações, e é tudo de que a tela precisa.

   Isso existe por dois motivos concretos:

   1. Os testes injetam uma porta falsa. Sem isso, o cliente real do
      Supabase entraria no processo de teste, abriria o timer de
      renovação de token e o `vitest run` deixaria de encerrar sozinho.
   2. Trocar de provedor de identidade um dia não vira reescrita de
      tela — vira outra implementação desta interface. */

export interface PortaAutenticacao {
  /** Sessão guardada, se houver. Chamado uma vez na abertura. */
  obterSessao(): Promise<SessaoAuth | null>;

  /**
   * Acompanha login, logout e renovação de token. Devolve a função de
   * cancelamento — que precisa ser chamada, ou o ouvinte sobrevive ao
   * componente.
   */
  aoMudarSessao(ouvinte: (sessao: SessaoAuth | null) => void): () => void;

  entrar(email: string, senha: string): Promise<SessaoAuth>;

  sair(): Promise<void>;

  /** Solta timers e conexões. Chamado quando o provedor desmonta. */
  encerrar?(): void;
}
