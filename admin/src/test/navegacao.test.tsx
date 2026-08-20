import { describe, expect, it } from 'vitest';
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderizarPainel } from './utils';
import { ITENS_NAVEGACAO } from '@/routes/navegacao';

describe('navegação', () => {
  it('mostra os quinze módulos do menu lateral', async () => {
    renderizarPainel();
    const menu = await screen.findByRole('navigation', { name: /navegação principal/i });

    expect(ITENS_NAVEGACAO).toHaveLength(15);
    for (const item of ITENS_NAVEGACAO) {
      expect(within(menu).getByRole('link', { name: new RegExp(item.rotulo, 'i') })).toBeVisible();
    }
  });

  it('abre a visão geral na raiz, com métricas e pendências', async () => {
    renderizarPainel();

    expect(await screen.findByRole('heading', { name: 'Visão geral', level: 1 })).toBeVisible();
    expect(await screen.findByText('Pendências importantes')).toBeVisible();
    expect(await screen.findByText('Sessões sem espaço')).toBeVisible();
    expect(screen.getByText('Palcos sem aliases')).toBeVisible();
  });

  it('navega da visão geral para a programação pelo menu', async () => {
    const usuario = userEvent.setup();
    renderizarPainel();

    const menu = await screen.findByRole('navigation', { name: /navegação principal/i });
    await usuario.click(within(menu).getByRole('link', { name: /programação/i }));

    expect(await screen.findByRole('heading', { name: 'Programação', level: 1 })).toBeVisible();
  });

  it('cada módulo abre sem quebrar', async () => {
    for (const item of ITENS_NAVEGACAO) {
      const { unmount } = renderizarPainel({ rota: item.caminho });
      expect(
        await screen.findByRole('heading', { level: 1 }),
        `módulo ${item.rotulo} não renderizou título`,
      ).toBeVisible();
      unmount();
    }
  });

  it('endereço desconhecido cai na página de não encontrada', async () => {
    renderizarPainel({ rota: '/rota-que-nao-existe' });
    expect(
      await screen.findByRole('heading', { name: /não existe no painel/i }),
    ).toBeVisible();
  });

  it('avisa em toda página que o painel está em modo demonstração', async () => {
    renderizarPainel({ rota: '/espacos' });
    expect(await screen.findByText(/modo demonstração/i)).toBeVisible();
    expect(screen.getByText(/nada é gravado no supabase/i)).toBeVisible();
  });
});
