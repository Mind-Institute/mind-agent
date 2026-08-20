import { describe, expect, it, vi } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AdminApiError } from '@/contracts';
import { HttpAdminDataProvider } from '@/services/http-admin-data-provider';
import { HybridAdminDataProvider } from '@/services/hybrid-admin-data-provider';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import {
  SESSAO_DE_TESTE,
  criarFetchFalso,
  criarPortaFalsa,
  renderizarPainel,
} from './utils';

const API = 'https://api.exemplo.invalido/mindagent-admin';

const PERFIL_OK = {
  id: 'usr-teste',
  email: 'ana.ribeiro@exemplo.com.br',
  nome: 'Ana Ribeiro',
  papel: 'administrador',
};

const RESUMO_VAZIO = { metricas: [], pendencias: [], alertas: [], geradoEm: '2026-08-20T12:00:00Z' };

/** Painel autenticado, com `/admin/me` respondendo o perfil dado. */
function renderizarAutenticado(
  opcoes: {
    perfil?: unknown;
    statusMe?: number;
    erroDeRedeNoMe?: boolean;
    rota?: string;
  } = {},
) {
  const porta = criarPortaFalsa({ sessaoInicial: SESSAO_DE_TESTE });
  const falso = criarFetchFalso({
    '/admin/me': {
      status: opcoes.statusMe ?? 200,
      corpo: opcoes.perfil ?? PERFIL_OK,
      erroDeRede: opcoes.erroDeRedeNoMe,
    },
    '/admin/dashboard': { corpo: RESUMO_VAZIO },
  });

  const tela = renderizarPainel({
    rota: opcoes.rota ?? '/',
    porta,
    baseUrlApi: API,
    fetchImpl: falso.fetch,
  });

  return { ...tela, porta, falso };
}

describe('restauração da sessão', () => {
  it('abre o painel sem pedir login quando já existe sessão guardada', async () => {
    const { falso } = renderizarAutenticado();

    /* Antes de resolver, a tela diz o que está fazendo. */
    expect(screen.getByText(/restaurando sua sessão/i)).toBeVisible();

    expect(await screen.findByRole('heading', { name: 'Visão geral', level: 1 })).toBeVisible();
    expect(screen.queryByLabelText(/^E-mail/)).not.toBeInTheDocument();
    expect(falso.ultima('/admin/me')).toBeDefined();
  });

  it('cai na tela de login quando não há sessão guardada', async () => {
    const porta = criarPortaFalsa({ sessaoInicial: null });
    const falso = criarFetchFalso({ '/admin/me': { corpo: PERFIL_OK } });

    renderizarPainel({ porta, baseUrlApi: API, fetchImpl: falso.fetch });

    expect(await screen.findByLabelText(/^E-mail/)).toBeVisible();
    expect(screen.getByRole('button', { name: /entrar/i })).toBeVisible();
    /* Sem sessão não se pergunta o papel a ninguém. */
    expect(falso.ultima('/admin/me')).toBeUndefined();
  });

  it('acompanha a sessão que chega depois, por onAuthStateChange', async () => {
    const porta = criarPortaFalsa({ sessaoInicial: null });
    const falso = criarFetchFalso({
      '/admin/me': { corpo: PERFIL_OK },
      '/admin/dashboard': { corpo: RESUMO_VAZIO },
    });

    renderizarPainel({ porta, baseUrlApi: API, fetchImpl: falso.fetch });
    await screen.findByLabelText(/^E-mail/);

    porta.emitir(SESSAO_DE_TESTE);

    expect(await screen.findByRole('heading', { name: 'Visão geral', level: 1 })).toBeVisible();
  });
});

describe('login', () => {
  it('entra com e-mail e senha e abre o painel', async () => {
    const usuario = userEvent.setup();
    const porta = criarPortaFalsa({ sessaoInicial: null });
    const falso = criarFetchFalso({
      '/admin/me': { corpo: PERFIL_OK },
      '/admin/dashboard': { corpo: RESUMO_VAZIO },
    });

    renderizarPainel({ porta, baseUrlApi: API, fetchImpl: falso.fetch });

    await usuario.type(await screen.findByLabelText(/^E-mail/), 'ana.ribeiro@exemplo.com.br');
    await usuario.type(screen.getByLabelText(/^Senha/), 'senha-de-teste');
    await usuario.click(screen.getByRole('button', { name: /entrar/i }));

    expect(await screen.findByRole('heading', { name: 'Visão geral', level: 1 })).toBeVisible();
    expect(porta.chamadas.entrar).toBe(1);
  });

  it('valida os campos antes de chamar o Supabase', async () => {
    const usuario = userEvent.setup();
    const porta = criarPortaFalsa({ sessaoInicial: null });

    renderizarPainel({ porta, baseUrlApi: API, fetchImpl: criarFetchFalso({}).fetch });

    await screen.findByLabelText(/^E-mail/);
    await usuario.click(screen.getByRole('button', { name: /entrar/i }));

    expect(await screen.findByText('Informe o e-mail.')).toBeVisible();
    expect(screen.getByText('Informe a senha.')).toBeVisible();
    expect(porta.chamadas.entrar).toBe(0);
  });

  it('mostra recado claro quando a senha está errada e limpa o campo', async () => {
    const usuario = userEvent.setup();
    const porta = criarPortaFalsa({
      sessaoInicial: null,
      aoEntrar: async () => {
        throw new AdminApiError('credenciais_invalidas', 'E-mail ou senha incorretos.');
      },
    });

    renderizarPainel({ porta, baseUrlApi: API, fetchImpl: criarFetchFalso({}).fetch });

    await usuario.type(await screen.findByLabelText(/^E-mail/), 'ana.ribeiro@exemplo.com.br');
    await usuario.type(screen.getByLabelText(/^Senha/), 'errada');
    await usuario.click(screen.getByRole('button', { name: /entrar/i }));

    const aviso = await screen.findByTestId('erro-login');
    expect(aviso).toHaveTextContent('Não foi possível entrar');
    expect(aviso).toHaveTextContent('E-mail ou senha incorretos.');

    expect(screen.getByLabelText(/^Senha/)).toHaveValue('');
    expect(screen.getByLabelText(/^E-mail/)).toHaveValue('ana.ribeiro@exemplo.com.br');
  });

  it('avisa quando o serviço de autenticação está fora do ar', async () => {
    const usuario = userEvent.setup();
    const porta = criarPortaFalsa({
      sessaoInicial: null,
      aoEntrar: async () => {
        throw new AdminApiError('rede', 'Não foi possível falar com o serviço de autenticação.');
      },
    });

    renderizarPainel({ porta, baseUrlApi: API, fetchImpl: criarFetchFalso({}).fetch });

    await usuario.type(await screen.findByLabelText(/^E-mail/), 'ana.ribeiro@exemplo.com.br');
    await usuario.type(screen.getByLabelText(/^Senha/), 'senha-de-teste');
    await usuario.click(screen.getByRole('button', { name: /entrar/i }));

    expect(await screen.findByText('Sem conexão com o serviço')).toBeVisible();
  });
});

describe('logout', () => {
  it('sai, volta para o login e avisa a porta de autenticação', async () => {
    const usuario = userEvent.setup();
    const { porta } = renderizarAutenticado();

    await screen.findByRole('heading', { name: 'Visão geral', level: 1 });
    await usuario.click(screen.getByRole('button', { name: /sair da conta/i }));

    expect(await screen.findByLabelText(/^E-mail/)).toBeVisible();
    expect(porta.chamadas.sair).toBe(1);
    /* Saiu de verdade: não é "sessão expirada", foi decisão da pessoa. */
    expect(screen.queryByText(/sua sessão expirou/i)).not.toBeInTheDocument();
  });
});

describe('respostas de erro de /admin/me', () => {
  it('401 devolve ao login dizendo que a sessão expirou', async () => {
    const { porta } = renderizarAutenticado({
      statusMe: 401,
      perfil: { codigo: 'sem_permissao', mensagem: 'Sessão inválida ou expirada.' },
    });

    expect(await screen.findByText(/sua sessão expirou/i)).toBeVisible();
    expect(screen.getByLabelText(/^E-mail/)).toBeVisible();
    /* A sessão morta é descartada, não fica pendurada no navegador. */
    await waitFor(() => expect(porta.chamadas.sair).toBe(1));
  });

  it('403 explica que a conta não tem papel administrativo', async () => {
    renderizarAutenticado({
      statusMe: 403,
      perfil: { codigo: 'sem_permissao', mensagem: 'Usuário sem papel administrativo.' },
    });

    expect(
      await screen.findByRole('heading', { name: /sua conta não tem acesso ao painel/i }),
    ).toBeVisible();
    expect(screen.getByText('Usuário sem papel administrativo.')).toBeVisible();
    /* Sem saída falsa: não existe "tentar novamente" para falta de papel. */
    expect(screen.queryByRole('button', { name: /tentar novamente/i })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /sair/i })).toBeVisible();
  });

  it('API fora do ar mostra erro com nova tentativa', async () => {
    const usuario = userEvent.setup();
    renderizarAutenticado({ erroDeRedeNoMe: true });

    expect(
      await screen.findByRole('heading', { name: /a api administrativa não respondeu/i }),
    ).toBeVisible();

    /* Só para provar que o botão refaz a busca; a rota falsa continua
       caindo, então a tela permanece a mesma. */
    await usuario.click(screen.getByRole('button', { name: /tentar novamente/i }));
    expect(
      await screen.findByRole('heading', { name: /a api administrativa não respondeu/i }),
    ).toBeVisible();
  });

  it('papel irreconhecível não abre o painel', async () => {
    renderizarAutenticado({ perfil: { papel: 'super-hacker' } });

    expect(
      await screen.findByRole('heading', { name: /sua conta não tem acesso ao painel/i }),
    ).toBeVisible();
  });
});

describe('papel e permissões vêm de /admin/me', () => {
  it('usa o papel da resposta, e não um padrão local', async () => {
    renderizarAutenticado({ perfil: { ...PERFIL_OK, papel: 'editor' } });

    await screen.findByRole('heading', { name: 'Visão geral', level: 1 });
    expect(screen.getByText('Editor')).toBeVisible();
    expect(screen.getByText('Ana Ribeiro')).toBeVisible();
  });

  it('sem o seletor "Ver como" — trocar de papel na tela seria mentira', async () => {
    renderizarAutenticado();

    await screen.findByRole('heading', { name: 'Visão geral', level: 1 });
    expect(screen.queryByLabelText('Papel simulado')).not.toBeInTheDocument();
  });

  it('o papel do backend governa o que a interface libera', async () => {
    renderizarAutenticado({ perfil: { ...PERFIL_OK, papel: 'editor' }, rota: '/usuarios' });

    expect(await screen.findByText('Sem permissão')).toBeVisible();
    expect(screen.getByText(/não pode gerir usuários e permissões/i)).toBeVisible();
  });

  it('a lista de permissões do backend tem precedência sobre o papel', async () => {
    /* Papel de editor, que na matriz local não publica — mas o backend
       mandou `publicar` na lista, e é a lista que vale. */
    renderizarAutenticado({
      perfil: { ...PERFIL_OK, papel: 'editor', permissoes: ['ver', 'editar', 'publicar'] },
      rota: '/conteudo/con_produtos',
    });

    await screen.findByDisplayValue('Plataformas e produtos');
    expect(screen.getByRole('button', { name: /publicar/i })).toBeVisible();
    /* E o que não está na lista continua fora, mesmo sendo de editor. */
    expect(screen.queryByRole('button', { name: /arquivar/i })).not.toBeInTheDocument();
  });
});

describe('o token no transporte', () => {
  it('vai no header Authorization, e nunca na URL', async () => {
    const porta = criarPortaFalsa({ sessaoInicial: SESSAO_DE_TESTE });
    const falso = criarFetchFalso({
      '/admin/me': { corpo: PERFIL_OK },
      '/admin/dashboard': { corpo: RESUMO_VAZIO },
    });

    renderizarPainel({
      porta,
      baseUrlApi: API,
      fetchImpl: falso.fetch,
      provedor: (opcoes) =>
        new HybridAdminDataProvider(
          new HttpAdminDataProvider({
            baseUrl: API,
            fetchImpl: falso.fetch,
            obterToken: opcoes.obterToken,
            aoNaoAutorizado: opcoes.aoNaoAutorizado,
          }),
          new MockAdminDataProvider({ latenciaMs: 0 }),
        ),
    });

    await screen.findByRole('heading', { name: 'Visão geral', level: 1 });
    await waitFor(() => expect(falso.ultima('/admin/dashboard')).toBeDefined());

    const chamadaMe = falso.ultima('/admin/me');
    const chamadaDashboard = falso.ultima('/admin/dashboard');

    expect(chamadaMe?.cabecalhos.Authorization).toBe(`Bearer ${SESSAO_DE_TESTE.accessToken}`);
    expect(chamadaDashboard?.cabecalhos.Authorization).toBe(
      `Bearer ${SESSAO_DE_TESTE.accessToken}`,
    );

    /* Nenhuma URL carrega o token — endereço vaza em histórico, log de
       proxy e print de tela. */
    for (const chamada of falso.chamadas) {
      expect(chamada.url).not.toContain(SESSAO_DE_TESTE.accessToken);
      expect(chamada.url.toLowerCase()).not.toContain('token');
      expect(chamada.url).not.toContain('@');
    }
  });

  it('não aparece em nenhuma saída de console', async () => {
    const escrito: string[] = [];
    const capturar = (...args: unknown[]) => escrito.push(args.map(String).join(' '));
    const espioes = (['log', 'info', 'warn', 'error', 'debug'] as const).map((nivel) =>
      vi.spyOn(console, nivel).mockImplementation(capturar),
    );

    try {
      const { falso } = renderizarAutenticado();
      await screen.findByRole('heading', { name: 'Visão geral', level: 1 });
      await waitFor(() => expect(falso.ultima('/admin/me')).toBeDefined());
    } finally {
      espioes.forEach((e) => e.mockRestore());
    }

    const tudo = escrito.join('\n');
    expect(tudo).not.toContain(SESSAO_DE_TESTE.accessToken);
    expect(tudo).not.toMatch(/bearer/i);
  });
});

describe('sessão expirada no meio do uso', () => {
  it('401 na API devolve ao login com o aviso', async () => {
    const porta = criarPortaFalsa({ sessaoInicial: SESSAO_DE_TESTE });
    const falso = criarFetchFalso({
      '/admin/me': { corpo: PERFIL_OK },
      '/admin/dashboard': {
        status: 401,
        corpo: { codigo: 'sem_permissao', mensagem: 'Sessão inválida ou expirada.' },
      },
    });

    renderizarPainel({
      porta,
      baseUrlApi: API,
      fetchImpl: falso.fetch,
      provedor: (opcoes) =>
        new HybridAdminDataProvider(
          new HttpAdminDataProvider({
            baseUrl: API,
            fetchImpl: falso.fetch,
            obterToken: opcoes.obterToken,
            aoNaoAutorizado: opcoes.aoNaoAutorizado,
          }),
          new MockAdminDataProvider({ latenciaMs: 0 }),
        ),
    });

    expect(await screen.findByText(/sua sessão expirou/i)).toBeVisible();
    expect(screen.getByLabelText(/^E-mail/)).toBeVisible();
    await waitFor(() => expect(porta.chamadas.sair).toBe(1));
  });
});
