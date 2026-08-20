import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import {
  AdminApiError,
  codigoDoErro,
  type EstadoSessao,
  type Papel,
  type PerfilAdmin,
  type SessaoAuth,
} from '@/contracts';
import type { PortaAutenticacao } from '@/services/auth';
import { buscarPerfilAdmin } from '@/services/perfil-admin';
import { pode as podePeloPapel, type Acao } from '@/lib/permissions';

/* ============================================================
   SESSÃO DO PAINEL
   ============================================================
   Dois modos, uma interface só — as páginas usam `useSessao()` sem
   saber qual está ativo:

   - `supabase`: sessão do Supabase Auth, papel e permissões de
     `GET /admin/me`. É o que roda quando o ambiente está configurado.
   - `simulado`: sem backend, papel escolhido no seletor do topo. É o
     modo de demonstração, e a tela diz isso.

   A REGRA QUE NÃO MUDA: no modo `supabase`, papel e permissões vêm
   EXCLUSIVAMENTE da resposta de `/admin/me`. Nada de `user_metadata`,
   nada de valor guardado no navegador, nada de padrão local. Se
   `/admin/me` recusar, o painel não abre. */

export interface ValorSessao {
  estado: EstadoSessao;
  nome: string;
  email: string | null;
  papel: Papel;
  /** Lista vinda de `/admin/me`. `null` = o backend só mandou o papel. */
  permissoes: string[] | null;
  /** `true` quando o papel vem do seletor, e não de `/admin/me`. */
  simulada: boolean;
  /** Erro do login (credenciais) ou da busca de perfil. */
  erro: unknown;
  /** Preenchido quando a sessão caiu sozinha, para a tela explicar. */
  expirou: boolean;
  carregandoLogin: boolean;

  pode: (acao: Acao) => boolean;
  entrar: (email: string, senha: string) => Promise<void>;
  sair: () => Promise<void>;
  recarregarPerfil: () => void;
  /** Só tem efeito no modo simulado. */
  definirPapel: (papel: Papel) => void;
  /** Usado pelo HttpAdminDataProvider. Identidade estável. */
  obterToken: () => Promise<string | null>;
  /** Chamado quando a API devolve 401 no meio do uso. */
  marcarSessaoExpirada: () => void;
}

const Contexto = createContext<ValorSessao | null>(null);

/** Margem antes do vencimento para pedir um token novo. */
const FOLGA_RENOVACAO_S = 60;

export function ProvedorDeSessao({
  children,
  porta,
  baseUrlApi,
  chavePublicavel,
  fetchImpl,
  papelInicial = 'administrador',
  nome = 'Você (demonstração)',
}: {
  children: ReactNode;
  /** Ausente = modo simulado. */
  porta?: PortaAutenticacao | null;
  baseUrlApi?: string;
  chavePublicavel?: string | null;
  fetchImpl?: typeof fetch;
  papelInicial?: Papel;
  nome?: string;
}) {
  const simulada = !porta;

  /* ---------------------------------------------------------------- */
  /* Modo simulado                                                     */
  /* ---------------------------------------------------------------- */
  const [papelSimulado, setPapelSimulado] = useState<Papel>(papelInicial);

  /* ---------------------------------------------------------------- */
  /* Modo Supabase                                                     */
  /* ---------------------------------------------------------------- */
  const [estado, setEstado] = useState<EstadoSessao>(simulada ? 'autenticado' : 'carregando');
  const [sessao, setSessao] = useState<SessaoAuth | null>(null);
  const [perfil, setPerfil] = useState<PerfilAdmin | null>(null);
  const [erro, setErro] = useState<unknown>(null);
  const [expirou, setExpirou] = useState(false);
  const [carregandoLogin, setCarregandoLogin] = useState(false);
  const [tentativaPerfil, setTentativaPerfil] = useState(0);

  /* O token vive numa ref para que `obterToken` tenha identidade
     estável — o provedor de dados é memoizado em cima dela. */
  const sessaoRef = useRef<SessaoAuth | null>(null);
  sessaoRef.current = sessao;
  const portaRef = useRef(porta);
  portaRef.current = porta;

  /* Restauração da sessão guardada + acompanhamento das mudanças. */
  useEffect(() => {
    if (!porta) return undefined;
    let vivo = true;

    void porta
      .obterSessao()
      .then((atual) => {
        if (!vivo) return;
        setSessao(atual);
        if (!atual) setEstado('anonimo');
      })
      .catch((e) => {
        if (!vivo) return;
        setErro(e);
        setEstado('anonimo');
      });

    const cancelar = porta.aoMudarSessao((nova) => {
      if (!vivo) return;
      setSessao(nova);
      if (!nova) {
        setPerfil(null);
        setEstado('anonimo');
      }
    });

    return () => {
      vivo = false;
      cancelar();
      porta.encerrar?.();
    };
  }, [porta]);

  /* Com sessão em mãos, o papel vem de /admin/me — e só de lá. */
  useEffect(() => {
    if (!porta) return undefined;
    const token = sessao?.accessToken;
    if (!token) return undefined;
    if (!baseUrlApi) {
      setErro(
        new AdminApiError(
          'indisponivel',
          'VITE_ADMIN_API_BASE_URL não está definida — sem ela não há de onde ler o papel.',
        ),
      );
      setEstado('erro_perfil');
      return undefined;
    }

    const controlador = new AbortController();
    setEstado('carregando_perfil');
    setErro(null);

    void buscarPerfilAdmin({
      baseUrl: baseUrlApi,
      token,
      chavePublicavel,
      fetchImpl,
      sinal: controlador.signal,
    })
      .then((encontrado) => {
        if (controlador.signal.aborted) return;
        setPerfil(encontrado);
        setExpirou(false);
        setEstado('autenticado');
      })
      .catch((e) => {
        if (controlador.signal.aborted) return;
        setPerfil(null);
        setErro(e);
        /* 401 aqui é sessão morta: volta para o login em vez de deixar
           a pessoa presa numa tela de erro sem saída. */
        if (codigoDoErro(e) === 'sessao_expirada') {
          setExpirou(true);
          setEstado('anonimo');
          void portaRef.current?.sair().catch(() => undefined);
        } else {
          setEstado('erro_perfil');
        }
      });

    return () => controlador.abort();
  }, [porta, sessao?.accessToken, baseUrlApi, chavePublicavel, fetchImpl, tentativaPerfil]);

  const entrar = useCallback(
    async (email: string, senha: string) => {
      if (!portaRef.current) return;
      setCarregandoLogin(true);
      setErro(null);
      setExpirou(false);
      try {
        const nova = await portaRef.current.entrar(email, senha);
        setSessao(nova);
      } catch (e) {
        setErro(e);
        setEstado('anonimo');
        throw e;
      } finally {
        setCarregandoLogin(false);
      }
    },
    [],
  );

  const sair = useCallback(async () => {
    if (!portaRef.current) return;
    try {
      await portaRef.current.sair();
    } finally {
      setSessao(null);
      setPerfil(null);
      setErro(null);
      setExpirou(false);
      setEstado('anonimo');
    }
  }, []);

  const marcarSessaoExpirada = useCallback(() => {
    if (!portaRef.current) return;
    setExpirou(true);
    setPerfil(null);
    setSessao(null);
    setEstado('anonimo');
    void portaRef.current.sair().catch(() => undefined);
  }, []);

  const recarregarPerfil = useCallback(() => setTentativaPerfil((n) => n + 1), []);

  /**
   * Token para o `Authorization`. Perto do vencimento, pede um novo ao
   * Supabase — que renova sozinho — em vez de mandar um token morto e
   * derrubar a sessão da pessoa no meio de uma edição.
   */
  const obterToken = useCallback(async () => {
    const atual = sessaoRef.current;
    if (!portaRef.current) return null;
    const agora = Math.floor(Date.now() / 1000);
    if (atual?.accessToken && (!atual.expiraEm || atual.expiraEm - agora > FOLGA_RENOVACAO_S)) {
      return atual.accessToken;
    }
    try {
      const renovada = await portaRef.current.obterSessao();
      if (renovada) setSessao(renovada);
      return renovada?.accessToken ?? null;
    } catch {
      return atual?.accessToken ?? null;
    }
  }, []);

  const papel: Papel = simulada ? papelSimulado : (perfil?.papel ?? 'analista');

  const pode = useCallback(
    (acao: Acao) => {
      if (simulada) return podePeloPapel(papelSimulado, acao);
      if (!perfil) return false;
      /* Lista explícita do backend manda. Sem ela, a leitura padrão do
         papel — que o servidor informou — governa só a interface. */
      if (perfil.permissoes) return perfil.permissoes.includes(acao);
      return podePeloPapel(perfil.papel, acao);
    },
    [simulada, papelSimulado, perfil],
  );

  const valor = useMemo<ValorSessao>(
    () => ({
      estado,
      nome: simulada ? nome : (perfil?.nome ?? sessao?.email ?? 'Usuário'),
      email: simulada ? null : (perfil?.email ?? sessao?.email ?? null),
      papel,
      permissoes: simulada ? null : (perfil?.permissoes ?? null),
      simulada,
      erro,
      expirou,
      carregandoLogin,
      pode,
      entrar,
      sair,
      recarregarPerfil,
      definirPapel: setPapelSimulado,
      obterToken,
      marcarSessaoExpirada,
    }),
    [
      estado,
      simulada,
      nome,
      perfil,
      sessao?.email,
      papel,
      erro,
      expirou,
      carregandoLogin,
      pode,
      entrar,
      sair,
      recarregarPerfil,
      obterToken,
      marcarSessaoExpirada,
    ],
  );

  return <Contexto.Provider value={valor}>{children}</Contexto.Provider>;
}

export function useSessao(): ValorSessao {
  const valor = useContext(Contexto);
  if (!valor) throw new Error('useSessao precisa estar dentro de <ProvedorDeSessao>.');
  return valor;
}

/** Versão tolerante, para quem pode ser montado fora do provedor. */
export function useSessaoOpcional(): ValorSessao | null {
  return useContext(Contexto);
}
