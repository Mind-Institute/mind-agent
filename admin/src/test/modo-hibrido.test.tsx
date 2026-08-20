import { describe, expect, it } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { ResumoPainel } from '@/contracts';
import { ehErroAdmin } from '@/contracts';
import { HttpAdminDataProvider } from '@/services/http-admin-data-provider';
import { HybridAdminDataProvider } from '@/services/hybrid-admin-data-provider';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { SESSAO_DE_TESTE, criarFetchFalso, criarPortaFalsa, renderizarPainel } from './utils';

const API = 'https://api.exemplo.invalido/mindagent-admin';

const PERFIL_OK = {
  id: 'usr-teste',
  email: 'ana.ribeiro@exemplo.com.br',
  nome: 'Ana Ribeiro',
  papel: 'administrador',
};

/* Números propositalmente diferentes dos do mock (53 sessões, 39
   palestrantes): se a tela mostrar 777, veio da API. */
const RESUMO_DA_API: ResumoPainel = {
  geradoEm: '2026-08-20T15:00:00.000Z',
  metricas: [
    { chave: 'sessoes', rotulo: 'Sessões', valor: 777, destino: '/programacao' },
    { chave: 'palestrantes', rotulo: 'Palestrantes', valor: 888, destino: '/palestrantes' },
  ],
  pendencias: [
    {
      categoria: 'sessoes_sem_espaco',
      titulo: 'Sessões sem espaço',
      descricao: 'Vindo da API administrativa.',
      total: 3,
      itens: [{ id: 's1', rotulo: 'Sessão da API', destino: '/programacao/s1' }],
      destino: '/programacao',
    },
  ],
  alertas: [
    {
      id: 'alerta_api',
      nivel: 'atencao',
      titulo: 'Alerta vindo do backend',
      descricao: 'Este texto não existe no mock.',
    },
  ],
};

/** Painel autenticado em modo híbrido, com fetch falso. */
function renderizarHibrido(
  opcoes: { rota?: string; dashboard?: { status?: number; corpo?: unknown } } = {},
) {
  const porta = criarPortaFalsa({ sessaoInicial: SESSAO_DE_TESTE });
  const falso = criarFetchFalso({
    '/admin/me': { corpo: PERFIL_OK },
    '/admin/dashboard': opcoes.dashboard ?? { corpo: RESUMO_DA_API },
  });

  const tela = renderizarPainel({
    rota: opcoes.rota ?? '/',
    porta,
    baseUrlApi: API,
    fetchImpl: falso.fetch,
    provedor: (o) =>
      new HybridAdminDataProvider(
        new HttpAdminDataProvider({
          baseUrl: API,
          fetchImpl: falso.fetch,
          obterToken: o.obterToken,
          aoNaoAutorizado: o.aoNaoAutorizado,
        }),
        new MockAdminDataProvider({ latenciaMs: 0 }),
      ),
  });

  return { ...tela, falso, porta };
}

describe('dashboard real', () => {
  it('a visão geral mostra os números que vieram da API', async () => {
    renderizarHibrido();

    expect(await screen.findByText('777')).toBeVisible();
    expect(screen.getByText('888')).toBeVisible();
    expect(screen.getByText('Alerta vindo do backend')).toBeVisible();
    expect(screen.getByText('Sessão da API')).toBeVisible();

    /* 53 é o total do mock: se aparecesse, o dashboard não seria real. */
    expect(screen.queryByText('53')).not.toBeInTheDocument();
  });

  it('marca na própria tela que os números são da API', async () => {
    renderizarHibrido();

    await screen.findByText('777');
    expect(screen.getByTestId('selo-dashboard-real')).toHaveTextContent(
      /números da api administrativa/i,
    );
  });

  it('a faixa do topo diz exatamente o que é real e o que é demonstração', async () => {
    renderizarHibrido();

    const faixa = await screen.findByTestId('faixa-modo');
    expect(faixa).toHaveTextContent('Dashboard real · Cadastros em demonstração.');
    expect(faixa).toHaveTextContent(/não chegam ao backend/i);
  });

  it('formato inesperado vira erro, não número inventado', async () => {
    renderizarHibrido({ dashboard: { corpo: { qualquer: 'coisa' } } });

    expect(await screen.findByText('Algo deu errado')).toBeVisible();
    expect(screen.getByText(/não segue o contrato do painel/i)).toBeVisible();
    expect(screen.queryByText('53')).not.toBeInTheDocument();
  });

  it('API indisponível mostra erro em vez de cair no mock em silêncio', async () => {
    renderizarHibrido({ dashboard: { status: 503, corpo: { codigo: 'indisponivel', mensagem: 'Em manutenção.' } } });

    expect(await screen.findByText('Serviço indisponível')).toBeVisible();
    expect(screen.getByText('Em manutenção.')).toBeVisible();
  });
});

describe('cadastros continuam em demonstração', () => {
  it('a programação vem do mock, não da API', async () => {
    const { falso } = renderizarHibrido({ rota: '/programacao' });

    const linha = await screen.findByTestId('linha-ses_d1-09_00-abertura');
    expect(within(linha).getByText('Abertura')).toBeVisible();

    /* Nenhuma requisição de cadastro saiu — só perfil e dashboard. */
    expect(falso.ultima('/admin/sessions')).toBeUndefined();
    for (const chamada of falso.chamadas) {
      expect(chamada.url).toMatch(/\/admin\/(me|dashboard)/);
    }
  });

  it('espaços, ofertas e documentos seguem no banco em memória', async () => {
    const { falso, unmount } = renderizarHibrido({ rota: '/espacos' });
    await screen.findByTestId('linha-esp_arena-mind');
    expect(screen.getByText('palco principal')).toBeVisible();
    unmount();

    const segundo = renderizarHibrido({ rota: '/ofertas' });
    const linha = await screen.findByTestId('linha-ofe_mind');
    expect(within(linha).getByText(/R\$\s*890,00/)).toBeVisible();

    for (const chamada of [...falso.chamadas, ...segundo.falso.chamadas]) {
      expect(chamada.url).toMatch(/\/admin\/(me|dashboard)/);
    }
  });

  it('salvar um cadastro não envia nada ao backend', async () => {
    const usuario = userEvent.setup();
    const { falso } = renderizarHibrido({ rota: '/estandes/est_mind' });

    const contato = await screen.findByLabelText(/^Contato/);
    await waitFor(() => expect(contato).toHaveValue('estande@exemplo.com.br'));

    await usuario.clear(contato);
    await usuario.type(contato, 'novo@exemplo.com.br');
    await usuario.click(screen.getByRole('button', { name: /^Salvar$/ }));

    await waitFor(() => expect(contato).toHaveValue('novo@exemplo.com.br'));

    /* Nenhum PATCH, nenhum POST: escrita nesta etapa é só em memória. */
    const escritas = falso.chamadas.filter((c) => c.metodo !== 'GET');
    expect(escritas).toEqual([]);
  });

  it('publicar e arquivar também ficam em memória', async () => {
    const usuario = userEvent.setup();
    const { falso } = renderizarHibrido({ rota: '/conteudo/con_produtos' });

    await screen.findByDisplayValue('Plataformas e produtos');
    await usuario.click(screen.getByRole('button', { name: /publicar/i }));
    await screen.findByText(/^Publicado em .+ por .+/);

    expect(falso.chamadas.filter((c) => c.metodo !== 'GET')).toEqual([]);
  });
});

describe('HybridAdminDataProvider', () => {
  function montar(dashboardHttp: () => Promise<unknown>) {
    const mock = new MockAdminDataProvider({ latenciaMs: 0 });
    const http = {
      modo: 'http' as const,
      getDashboard: dashboardHttp,
    } as unknown as HttpAdminDataProvider;
    return { hibrido: new HybridAdminDataProvider(http, mock), mock };
  }

  it('anuncia o modo como hybrid — nem mock, nem http', () => {
    const { hibrido } = montar(async () => RESUMO_DA_API);
    expect(hibrido.modo).toBe('hybrid');
  });

  it('manda getDashboard para o HTTP e o resto para o mock', async () => {
    const { hibrido } = montar(async () => RESUMO_DA_API);

    const resumo = await hibrido.getDashboard();
    expect(resumo.metricas[0].valor).toBe(777);

    const sessoes = await hibrido.list('sessions');
    expect(sessoes.total).toBeGreaterThan(40);
  });

  it('escrita não passa pelo HTTP nesta etapa', async () => {
    const { hibrido, mock } = montar(async () => RESUMO_DA_API);

    const atualizado = await hibrido.update('booths', 'est_mind', { contato: 'x@exemplo.com.br' });
    expect(atualizado.contato).toBe('x@exemplo.com.br');

    const noBanco = await mock.get('booths', 'est_mind');
    expect(noBanco.contato).toBe('x@exemplo.com.br');
  });

  it('recusa dashboard fora do contrato em vez de devolver meia tela', async () => {
    const { hibrido } = montar(async () => ({ metricas: [] }));

    await expect(hibrido.getDashboard()).rejects.toSatisfy(
      (e: unknown) => ehErroAdmin(e) && /pendencias, alertas/.test(e.message),
    );
  });
});
