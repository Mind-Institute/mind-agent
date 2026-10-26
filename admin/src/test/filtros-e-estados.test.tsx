import { describe, expect, it } from 'vitest';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { contarLinhas, renderizarPainel } from './utils';

/* Desde 26/09/2026 o painel só tem tela com dado real, e a listagem que
   ficou é a do Catálogo — é nela que filtros e estados são conferidos. */

describe('filtros', () => {
  it('o filtro vem da URL e estreita a lista', async () => {
    const { container } = renderizarPainel({ rota: '/catalogo?vertical=institute' });

    await screen.findByTestId('linha-prd_journey_2027');
    expect(contarLinhas(container)).toBe(2);
    expect(screen.queryByTestId('linha-prd_mind')).not.toBeInTheDocument();
  });

  it('o botão limpar devolve a lista inteira', async () => {
    const usuario = userEvent.setup();
    const { container } = renderizarPainel({ rota: '/catalogo?vertical=dash' });

    await screen.findByTestId('linha-prd_dash');
    expect(contarLinhas(container)).toBe(1);

    await usuario.click(screen.getByRole('button', { name: /limpar/i }));

    await screen.findByTestId('linha-prd_mind');
    expect(contarLinhas(container)).toBeGreaterThan(1);
  });
});

describe('estados das páginas', () => {
  it('estado vazio quando nada bate com a busca', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/catalogo' });

    await screen.findByTestId('linha-prd_mind');
    await usuario.type(screen.getByRole('searchbox', { name: 'Buscar' }), 'zzzzz-inexistente');

    expect(await screen.findByText('Nenhum produto no recorte')).toBeVisible();
  });

  it('estado de erro quando a API falha, com botão de tentar novamente', async () => {
    const provedor = new MockAdminDataProvider({ latenciaMs: 0 });
    provedor.configurarFalha('products', 'rede');

    renderizarPainel({ rota: '/catalogo', provedor });

    expect(await screen.findByText('Não foi possível carregar')).toBeVisible();
    expect(
      screen.getByText(/não foi possível falar com a api administrativa/i),
    ).toBeVisible();

    const usuario = userEvent.setup();
    provedor.limparFalhas();
    await usuario.click(screen.getByRole('button', { name: /tentar novamente/i }));

    expect(await screen.findByTestId('linha-prd_mind')).toBeVisible();
  });

  it('mostra o esqueleto de carregamento antes dos dados chegarem', async () => {
    const provedor = new MockAdminDataProvider({ latenciaMs: 40 });
    renderizarPainel({ rota: '/catalogo', provedor });

    expect(screen.getByRole('status')).toHaveAttribute('aria-busy', 'true');
    expect(await screen.findByTestId('linha-prd_mind')).toBeVisible();
  });
});
