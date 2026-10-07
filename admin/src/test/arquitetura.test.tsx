import { describe, expect, it } from 'vitest';
import { screen, within } from '@testing-library/react';
import { renderizarPainel } from './utils';
import { DECISOES } from '@/lib/arquitetura';

/* Pedido da Adriana (07/10/2026): menu "Arquitetura do sistema" com o
   espelho das decisões D1–D6 e o mapa de onde cada uma está aplicada. */
describe('arquitetura do sistema', () => {
  it('o menu tem o título e leva às decisões', async () => {
    renderizarPainel();
    const menu = await screen.findByRole('navigation', { name: /navegação principal/i });

    expect(within(menu).getByText('Arquitetura do sistema')).toBeVisible();
    expect(within(menu).getByRole('link', { name: (nome) => nome.trim() === 'Decisões' }))
      .toHaveAttribute('href', '/arquitetura/decisoes');
  });

  it('mostra D1 a D6, o mapa e onde cada uma está aplicada', async () => {
    renderizarPainel({ rota: '/arquitetura/decisoes' });

    expect(await screen.findByRole('heading', { name: 'Decisões do sistema' })).toBeVisible();
    expect(DECISOES.map((d) => d.id)).toEqual(['D1', 'D2', 'D3', 'D4', 'D5', 'D6']);

    const mapa = screen.getByRole('table');
    for (const decisao of DECISOES) {
      expect(within(mapa).getByRole('rowheader', { name: decisao.id })).toBeVisible();
      expect(screen.getByRole('heading', { name: decisao.titulo })).toBeVisible();
      expect(decisao.lugares.length).toBeGreaterThan(0);
    }
    expect(within(mapa).getByLabelText('D5 · Funções e gatilhos: 5')).toBeVisible();
    expect(screen.getAllByText('mind_identidade_resolver').length).toBeGreaterThan(0);
  });
});
