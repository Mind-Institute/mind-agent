import { describe, expect, it } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ehErroAdmin, type SessaoSummit2026 } from '@/contracts';
import { validarRegistro } from '@/services/validacao-api';
import { HybridAdminDataProvider } from '@/services/hybrid-admin-data-provider';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { enderecoDoSummit } from '@/services/provider-context';
import { SUMMIT_FALSO, contarLinhas, lista, renderizarHibrido, renderizarPainel } from './utils';

/* ============================================================
   MIND SUMMIT 2026 — A PROGRAMAÇÃO COMO ESTÁ NO BANCO
   ============================================================
   Pedido da Adriana (26/09/2026): SUMMIT → Mind Summit 2026 →
   Programação, com a tabela "conforme está no backend". Quem monta a linha
   é o banco (`tests/summit_programacao_contract.sql`); a porta é a
   `mindagent-summit` (`tests/mindagent_summit_comportamento.test.mjs`).
   Aqui: de onde a tela lê, o que ela mostra e que ela não escreve. */

/* Como a `mindagent-summit` devolve: as colunas do banco + espaço e palestrantes. Inventada. */
const SESSAO: SessaoSummit2026 = {
  id: '0f8e2a4c-1b3d-4e5f-8a9b-0c1d2e3f4a5b',
  titulo: 'Sessão vinda da API',
  dia: '2026-09-17',
  inicio: '2026-09-17T13:30:00+00:00',
  fim: '2026-09-17T14:15:00+00:00',
  tipo: 'painel',
  espaco_id: 'a1b2c3d4-0000-4000-8000-000000000001',
  espaco: 'Palco da API',
  palestrantes: ['Pessoa Um', 'Pessoa Dois'],
  precisa_reserva: true,
  vagas_total: 80,
  vagas_disponiveis: 7,
  atualizado_em: '2026-09-15T12:00:00+00:00',
  trilhas: ['lideranca'],
  topicos_aprendizado: ['tema A'],
  yazo_id: null,
};

describe('programação — a tela em demonstração', () => {
  it('lista a semente com o horário de São Paulo e a reserva', async () => {
    const { container } = renderizarPainel({ rota: '/summit/2026/programacao' });
    expect(await screen.findByRole('heading', { name: /Programação · Mind Summit 2026/, level: 1 })).toBeVisible();
    await waitFor(() => expect(contarLinhas(container)).toBe(3));
    expect(screen.getByTestId('selo-origem-mock')).toBeVisible();

    const workshop = screen.getByTestId('linha-ses_workshop');
    /* 14:00 UTC é 11:00 em São Paulo. */
    expect(within(workshop).getByText('11:00–12:30')).toBeVisible();
    expect(within(workshop).getByText('com reserva')).toBeVisible();
    expect(within(workshop).getByText(/12 de 40 vagas/)).toBeVisible();
    expect(within(workshop).getByText('Bruno Exemplo, Carla Exemplo')).toBeVisible();
  });

  it('qualquer papel vê a programação', async () => {
    const { container } = renderizarPainel({ rota: '/summit/2026/programacao', papel: 'analista' });
    await waitFor(() => expect(contarLinhas(container)).toBe(3));
  });
});

describe('programação — a lista real', () => {
  it('vem da mindagent-summit, com filtro e ordem na query', async () => {
    const usuario = userEvent.setup();
    const { falso } = renderizarHibrido({
      rota: '/summit/2026/programacao',
      rotas: { '/admin/summit_2026_sessions': { corpo: lista([SESSAO]) } },
    });
    const linha = await screen.findByTestId(`linha-${SESSAO.id}`);
    expect(within(linha).getByText('Sessão vinda da API')).toBeVisible();
    expect(screen.getByTestId('selo-origem-real')).toBeVisible();
    const pedido = () => new URL(falso.ultima('/admin/summit_2026_sessions')!.url);
    expect(pedido().href.startsWith(`${SUMMIT_FALSO}/admin/summit_2026_sessions`)).toBe(true);

    await usuario.click(within(screen.getByRole('columnheader', { name: /^Horário/ })).getByRole('button'));
    await waitFor(() => expect(pedido().searchParams.get('ordenar')).toBe('inicio'));

    await usuario.click(screen.getByRole('combobox', { name: 'Dia' }));
    await usuario.click(await screen.findByRole('option', { name: /17\/09/ }));
    await waitFor(() => expect(pedido().searchParams.get('dia')).toBe('2026-09-17'));
  });

  it('abrir uma sessão mostra todas as colunas, com os nomes do banco', async () => {
    renderizarHibrido({
      rota: `/summit/2026/programacao/${SESSAO.id}`,
      rotas: {
        '/admin/summit_2026_sessions': { corpo: lista([SESSAO]) },
        [`/admin/summit_2026_sessions/${SESSAO.id}`]: { corpo: SESSAO },
      },
    });
    const detalhe = await screen.findByRole('dialog', { name: 'Sessão vinda da API' });
    const colunas = await within(detalhe).findByTestId('colunas-da-sessao');
    for (const coluna of ['titulo', 'dia', 'inicio', 'espaco_id', 'precisa_reserva', 'vagas_disponiveis', 'trilhas', 'yazo_id']) {
      expect(within(colunas).getByText(coluna), coluna).toBeVisible();
    }
    expect(within(colunas).getByText('lideranca')).toBeVisible();
    expect(within(detalhe).getByText('Palco da API')).toBeVisible();
    expect(within(detalhe).getByText('Pessoa Um, Pessoa Dois')).toBeVisible();
    /* Nada de salvar: é leitura. */
    expect(within(detalhe).queryByRole('button', { name: /salvar/i })).toBeNull();
  });
});

describe('programação — só leitura', () => {
  it('escrever é recusado antes de sair, real ou demonstração', async () => {
    const hibrido = new HybridAdminDataProvider(
      new MockAdminDataProvider({ latenciaMs: 0 }),
      undefined,
      undefined,
      new MockAdminDataProvider({ latenciaMs: 0 }),
    );
    for (const escrever of [
      () => hibrido.update('summit_2026_sessions', SESSAO.id, { titulo: 'x' }),
      () => hibrido.create('summit_2026_sessions', {}),
      () => hibrido.archive('summit_2026_sessions', SESSAO.id),
    ]) {
      await expect(escrever()).rejects.toSatisfy(
        (e: unknown) => ehErroAdmin(e) && /só leitura/.test(e.message),
      );
    }
    expect(hibrido.origemDoRecurso('summit_2026_sessions')).toBe('http');
  });

  it('linha sem título é quebra de contrato; coluna nova do banco passa para o detalhe', () => {
    const { titulo: _t, ...semTitulo } = SESSAO;
    expect(() => validarRegistro('summit_2026_sessions', semTitulo)).toThrow(/Contrato incompatível/);
    const comColunaNova = validarRegistro('summit_2026_sessions', { ...SESSAO, coluna_nova: 'ok' });
    expect((comColunaNova as Record<string, unknown>).coluna_nova).toBe('ok');
  });

  it('o endereço da função sai do projeto do login', () => {
    expect(enderecoDoSummit('https://projeto.supabase.co/')).toBe('https://projeto.supabase.co/functions/v1/mindagent-summit');
    expect(enderecoDoSummit('')).toBeNull();
  });
});
