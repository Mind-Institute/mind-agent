import { describe, expect, it } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { codigoDoErro, darAcessoFormSchema, ehErroAdmin, type AdminSistema } from '@/contracts';
import { payloadDaEdicaoAdmin, paraFormularioAdmin, rotuloDoPapel } from '@/lib/admins';
import { validarRegistro } from '@/services/validacao-api';
import { HybridAdminDataProvider } from '@/services/hybrid-admin-data-provider';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { ACESSO_FALSO, PERFIL_HTTP, lista, renderizarHibrido, renderizarPainel } from './utils';

/* ============================================================
   ADMINS DO SISTEMA — quem entra no Mind Intelligence Admin
   ============================================================
   Pedido da Adriana (26/09/2026): ver e cadastrar quem entra. Quem decide
   é o banco (contrato em `tests/admins_no_painel_contract.sql`) e a porta
   é a `mindagent-acesso` (`tests/mindagent_acesso_comportamento.test.mjs`).
   Aqui se confere a tela: de onde a lista vem, o que cada escrita manda e
   que cada recusa do banco chega em quem está usando. */

/* Como a `mindagent-acesso` devolve. Nomes inventados: o repositório é público. */
const ADMIN: AdminSistema = {
  id: '33333333-3333-4333-8333-333333333333',
  criadoEm: '2026-09-25T23:25:08.123456+00:00',
  atualizadoEm: '2026-09-26T14:37:00.654321+00:00',
  atualizadoPor: null,
  mindId: '9f0e1d2c-3b4a-4596-8778-695a4b3c2d1e',
  nome: 'Helena Vinda da API',
  email: 'helena.api@joinmind.com.br',
  papel: 'editor',
  ativo: true,
  loginLigado: true,
  ultimoLoginEm: '2026-09-26T14:37:00+00:00',
};

/* A conta antiga, de senha: anterior ao Mind ID, sem pessoa. */
const CONTA_SEM_MIND_ID: AdminSistema = {
  ...ADMIN,
  id: '44444444-4444-4444-8444-444444444444',
  mindId: null,
  nome: 'Conta de senha',
  email: null,
  papel: 'administrador',
  loginLigado: true,
};

const CONVIDADA: AdminSistema = {
  ...ADMIN,
  id: '55555555-5555-4555-8555-555555555555',
  nome: 'Nina Convidada',
  email: 'nina.convidada@joinmind.com.br',
  papel: 'analista',
  loginLigado: false,
  ultimoLoginEm: null,
};

function rotasDaLista(extra = {}) {
  return {
    'GET /admin/admins': { corpo: lista([ADMIN, CONTA_SEM_MIND_ID]) },
    [`GET /admin/admins/${ADMIN.id}`]: { corpo: ADMIN },
    ...extra,
  };
}

describe('admins — regras da tela', () => {
  it('salvar manda só o que mudou: papel, situação, ou nada', () => {
    const base = paraFormularioAdmin(ADMIN);
    expect(payloadDaEdicaoAdmin({ ...base, papel: 'analista' }, ADMIN)).toEqual({ papel: 'analista' });
    expect(payloadDaEdicaoAdmin({ ...base, ativo: false }, ADMIN)).toEqual({ ativo: false });
    expect(payloadDaEdicaoAdmin(base, ADMIN)).toEqual({});
  });

  it('papel que o painel não conhece aparece com o próprio código', () => {
    expect(rotuloDoPapel('editor')).toEqual({ texto: 'Editor', conhecido: true });
    expect(rotuloDoPapel('curador')).toEqual({ texto: 'curador', conhecido: false });
  });

  it('dar acesso exige o e-mail da Mind e um papel escolhido', () => {
    expect(darAcessoFormSchema.parse({ email: '  Nina.Convidada@JoinMind.com.br ', papel: 'analista' }))
      .toEqual({ email: 'nina.convidada@joinmind.com.br', papel: 'analista' });

    const deFora = darAcessoFormSchema.safeParse({ email: 'nina@gmail.com', papel: 'analista' });
    expect(deFora.success).toBe(false);
    expect(deFora.error?.issues[0].message).toMatch(/@joinmind\.com\.br/);

    const semPapel = darAcessoFormSchema.safeParse({ email: 'nina@joinmind.com.br' });
    expect(semPapel.error?.issues.map((i) => i.message)).toEqual(['Escolha o papel.']);
  });

  it('linha sem versão é quebra de contrato; sem Mind ID é estado legítimo', () => {
    const { atualizadoEm: _versao, ...semVersao } = ADMIN;
    expect(() => validarRegistro('admins', semVersao)).toThrow(/Contrato incompatível/);
    expect(validarRegistro('admins', CONTA_SEM_MIND_ID).mindId).toBeNull();
  });

  it('arquivar e publicar admin não existem: tirar o acesso é desligar a situação', async () => {
    const hibrido = new HybridAdminDataProvider(
      new MockAdminDataProvider({ latenciaMs: 0 }),
      undefined,
      new MockAdminDataProvider({ latenciaMs: 0 }),
    );
    await expect(hibrido.archive('admins', ADMIN.id)).rejects.toSatisfy(
      (e: unknown) => ehErroAdmin(e) && codigoDoErro(e) === 'validacao' && /arquivar admin não existe/.test(e.message),
    );
    await expect(hibrido.publish('admins', ADMIN.id)).rejects.toSatisfy(
      (e: unknown) => ehErroAdmin(e) && /publicar admin não existe/.test(e.message),
    );
  });
});

describe('admins — a lista real', () => {
  it('vem da mindagent-acesso, com o token, e mostra quem entra', async () => {
    const { falso } = renderizarHibrido({ rota: '/admins', rotas: rotasDaLista() });

    const linha = await screen.findByTestId(`linha-${ADMIN.id}`);
    expect(within(linha).getByText('Helena Vinda da API')).toBeVisible();
    expect(within(linha).getByText('helena.api@joinmind.com.br')).toBeVisible();
    expect(within(linha).getByText('Editor')).toBeVisible();
    expect(screen.getByTestId('selo-origem-real')).toHaveTextContent('dados reais');

    const chamada = falso.ultima('/admin/admins');
    expect(chamada?.url.startsWith(`${ACESSO_FALSO}/admin/admins`)).toBe(true);
    expect(chamada?.cabecalhos.Authorization).toMatch(/^Bearer /);
  });

  it('a conta anterior ao Mind ID aparece marcada', async () => {
    renderizarHibrido({ rota: '/admins', rotas: rotasDaLista() });

    const linha = await screen.findByTestId(`linha-${CONTA_SEM_MIND_ID.id}`);
    expect(within(linha).getByText('sem Mind ID')).toBeVisible();
    expect(within(screen.getByTestId(`linha-${ADMIN.id}`)).queryByText('sem Mind ID')).toBeNull();
  });

  it('quem não é administrador vê "sem permissão" e a lista nem é pedida', async () => {
    const { falso } = renderizarHibrido({
      rota: '/admins',
      rotas: rotasDaLista(),
      perfil: { ...PERFIL_HTTP, papel: 'editor' },
    });

    expect(await screen.findByText('Sem permissão')).toBeVisible();
    expect(screen.queryByRole('button', { name: /dar acesso/i })).toBeNull();
    expect(falso.ultima('/admin/admins')).toBeUndefined();
  });
});

describe('admins — dar acesso', () => {
  async function abrirEPreencher(email: string, papel?: string) {
    const usuario = userEvent.setup();
    await usuario.click(await screen.findByRole('button', { name: /dar acesso/i }));
    const dialogo = await screen.findByRole('dialog', { name: /dar acesso ao painel/i });
    await usuario.type(within(dialogo).getByLabelText(/e-mail da mind/i), email);
    if (papel) {
      await usuario.click(within(dialogo).getByRole('combobox', { name: /papel/i }));
      await usuario.click(await screen.findByRole('option', { name: papel }));
    }
    return { usuario, dialogo };
  }

  it('manda só e-mail e papel, e a lista volta com a pessoa', async () => {
    const { falso } = renderizarHibrido({
      rota: '/admins',
      rotas: rotasDaLista({
        'POST /admin/admins': { status: 201, corpo: CONVIDADA },
        'GET /admin/admins': {
          sequencia: [{ corpo: lista([ADMIN, CONTA_SEM_MIND_ID]) }, { corpo: lista([ADMIN, CONTA_SEM_MIND_ID, CONVIDADA]) }],
        },
      }),
    });
    await screen.findByTestId(`linha-${ADMIN.id}`);

    const { usuario, dialogo } = await abrirEPreencher(' Nina.Convidada@joinmind.com.br', 'Analista');
    await usuario.click(within(dialogo).getByRole('button', { name: /dar acesso/i }));

    await waitFor(() => expect(falso.ultima('/admin/admins')?.metodo).toBe('GET'));
    const post = falso.chamadas.find((c) => c.metodo === 'POST');
    expect(post?.url).toBe(`${ACESSO_FALSO}/admin/admins`);
    expect(post?.corpo).toEqual({ email: 'nina.convidada@joinmind.com.br', papel: 'analista' });

    expect(await screen.findByTestId(`linha-${CONVIDADA.id}`)).toBeVisible();
    expect(screen.getByTestId('acesso-concedido')).toHaveTextContent(
      'Nina Convidada já pode entrar: é só usar "Entrar com Google" com nina.convidada@joinmind.com.br.',
    );
    expect(screen.queryByRole('dialog', { name: /dar acesso ao painel/i })).toBeNull();
  });

  it('a recusa do banco aparece no diálogo, que guarda o que foi digitado', async () => {
    const { falso } = renderizarHibrido({
      rota: '/admins',
      rotas: rotasDaLista({
        'POST /admin/admins': {
          status: 422,
          corpo: { codigo: 'validacao', mensagem: 'Essa pessoa não está marcada como equipe no Mind ID.' },
        },
      }),
    });
    await screen.findByTestId(`linha-${ADMIN.id}`);

    const { usuario, dialogo } = await abrirEPreencher('nina.convidada@joinmind.com.br', 'Editor');
    await usuario.click(within(dialogo).getByRole('button', { name: /dar acesso/i }));

    expect(await within(dialogo).findByText('Essa pessoa não está marcada como equipe no Mind ID.')).toBeVisible();
    expect(within(dialogo).getByLabelText(/e-mail da mind/i)).toHaveValue('nina.convidada@joinmind.com.br');
    expect(falso.chamadas.filter((c) => c.metodo === 'POST')).toHaveLength(1);
    expect(screen.queryByTestId('acesso-concedido')).toBeNull();
  });

  it('e-mail de fora da Mind nem sai da tela', async () => {
    const { falso } = renderizarHibrido({ rota: '/admins', rotas: rotasDaLista() });
    await screen.findByTestId(`linha-${ADMIN.id}`);

    const { usuario, dialogo } = await abrirEPreencher('nina@gmail.com', 'Editor');
    await usuario.click(within(dialogo).getByRole('button', { name: /dar acesso/i }));

    expect(await within(dialogo).findByText(/Use o e-mail da Mind/)).toBeVisible();
    expect(falso.chamadas.some((c) => c.metodo === 'POST')).toBe(false);
  });

  it('sem papel escolhido, pede o papel', async () => {
    const { falso } = renderizarHibrido({ rota: '/admins', rotas: rotasDaLista() });
    await screen.findByTestId(`linha-${ADMIN.id}`);

    const { usuario, dialogo } = await abrirEPreencher('nina.convidada@joinmind.com.br');
    await usuario.click(within(dialogo).getByRole('button', { name: /dar acesso/i }));

    expect(await within(dialogo).findByText('Escolha o papel.')).toBeVisible();
    expect(falso.chamadas.some((c) => c.metodo === 'POST')).toBe(false);
  });
});

describe('admins — mudar papel e situação', () => {
  it('trocar o papel manda só o papel, com a versão que a tela viu', async () => {
    const usuario = userEvent.setup();
    const { falso } = renderizarHibrido({
      rota: `/admins/${ADMIN.id}`,
      rotas: rotasDaLista({
        [`PATCH /admin/admins/${ADMIN.id}`]: {
          corpo: { ...ADMIN, papel: 'aprovador', atualizadoEm: '2026-09-26T15:00:00+00:00' },
        },
      }),
    });

    const drawer = await screen.findByRole('dialog', { name: 'Helena Vinda da API' });
    await usuario.click(await within(drawer).findByRole('combobox', { name: /papel/i }));
    await usuario.click(await screen.findByRole('option', { name: 'Aprovador' }));
    await usuario.click(within(drawer).getByRole('button', { name: /salvar/i }));

    expect(await within(drawer).findByText(/Está no banco e já vale/)).toBeVisible();
    const patch = falso.chamadas.find((c) => c.metodo === 'PATCH');
    expect(patch?.url).toBe(`${ACESSO_FALSO}/admin/admins/${ADMIN.id}`);
    expect(patch?.corpo).toEqual({ papel: 'aprovador' });
    expect(patch?.cabecalhos['If-Unmodified-Since-Version']).toBe(ADMIN.atualizadoEm);
  });

  it('tirar o acesso é desligar a situação — e só ela vai', async () => {
    const usuario = userEvent.setup();
    const { falso } = renderizarHibrido({
      rota: `/admins/${ADMIN.id}`,
      rotas: rotasDaLista({
        [`PATCH /admin/admins/${ADMIN.id}`]: { corpo: { ...ADMIN, ativo: false } },
      }),
    });

    const drawer = await screen.findByRole('dialog', { name: 'Helena Vinda da API' });
    await usuario.click(await within(drawer).findByRole('switch', { name: /pode entrar no painel/i }));
    await usuario.click(within(drawer).getByRole('button', { name: /salvar/i }));

    await waitFor(() => expect(falso.chamadas.some((c) => c.metodo === 'PATCH')).toBe(true));
    expect(falso.chamadas.find((c) => c.metodo === 'PATCH')?.corpo).toEqual({ ativo: false });
  });

  it('a trava do banco contra tirar o próprio acesso chega na tela', async () => {
    const usuario = userEvent.setup();
    renderizarHibrido({
      rota: `/admins/${ADMIN.id}`,
      rotas: rotasDaLista({
        [`PATCH /admin/admins/${ADMIN.id}`]: {
          status: 422,
          corpo: {
            codigo: 'validacao',
            mensagem: 'Ninguém tira o próprio acesso nem o próprio papel de administrador por aqui.',
          },
        },
      }),
    });

    const drawer = await screen.findByRole('dialog', { name: 'Helena Vinda da API' });
    await usuario.click(await within(drawer).findByRole('switch', { name: /pode entrar no painel/i }));
    await usuario.click(within(drawer).getByRole('button', { name: /salvar/i }));

    expect(await within(drawer).findByTestId('erro-escrita')).toHaveTextContent(
      'Ninguém tira o próprio acesso nem o próprio papel de administrador por aqui.',
    );
  });

  it('conflito de versão pede para recarregar, sem sobrescrever', async () => {
    const usuario = userEvent.setup();
    renderizarHibrido({
      rota: `/admins/${ADMIN.id}`,
      rotas: rotasDaLista({
        [`PATCH /admin/admins/${ADMIN.id}`]: {
          status: 409,
          corpo: { codigo: 'conflito', mensagem: 'Esse acesso foi alterado por outra pessoa. Recarregue antes de salvar.' },
        },
      }),
    });

    const drawer = await screen.findByRole('dialog', { name: 'Helena Vinda da API' });
    await usuario.click(await within(drawer).findByRole('switch', { name: /pode entrar no painel/i }));
    await usuario.click(within(drawer).getByRole('button', { name: /salvar/i }));

    expect(await screen.findByRole('dialog', { name: /conflito de atualização/i })).toBeVisible();
  });
});

describe('admins — demonstração', () => {
  it('sem a função, a lista é a semente inventada e a tela diz que é demonstração', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/admins' });

    expect(await screen.findByText('Ana Exemplo')).toBeVisible();
    expect(screen.getByTestId('selo-origem-mock')).toHaveTextContent('demonstração');

    await usuario.click(screen.getByRole('button', { name: /dar acesso/i }));
    const dialogo = await screen.findByRole('dialog', { name: /dar acesso ao painel/i });
    await usuario.type(within(dialogo).getByLabelText(/e-mail da mind/i), 'nova.pessoa@joinmind.com.br');
    await usuario.click(within(dialogo).getByRole('combobox', { name: /papel/i }));
    await usuario.click(await screen.findByRole('option', { name: 'Editor' }));
    await usuario.click(within(dialogo).getByRole('button', { name: /dar acesso/i }));

    expect(await screen.findByTestId('acesso-concedido')).toHaveTextContent(/Modo demonstração/);
    expect(await screen.findByText('nova.pessoa@joinmind.com.br')).toBeVisible();
  });
});
