import { describe, expect, it } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderizarPainel } from './utils';

/* Os formulários de evento, sessão, espaço, palestrante e dos módulos em
   demonstração saíram com as telas deles (decisões da Adriana, 26/09/2026).
   Fica o que é do painel todo: o drawer não fecha em silêncio por cima de
   alteração pendente. */
describe('alterações não salvas', () => {
  it('fechar o drawer com alteração pendente pede confirmação', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/catalogo/prd_dash' });

    const nome = await screen.findByLabelText(/^Nome/);
    await waitFor(() => expect(nome).toHaveValue('Mind Dash'));
    await usuario.type(nome, 'x');

    await usuario.click(screen.getByRole('button', { name: 'Fechar' }));

    expect(
      await screen.findByRole('heading', { name: /você tem alterações não salvas/i }),
    ).toBeVisible();

    await usuario.click(screen.getByRole('button', { name: /descartar e fechar/i }));
    await waitFor(() => expect(screen.queryByLabelText(/^Nome/)).not.toBeInTheDocument());
  });
});
