import { describe, expect, it } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderizarPainel } from './utils';

/* Os formulários de evento, sessão, espaço e palestrante saíram com as telas
   do Evento (decisão da Adriana, 26/09/2026). Fica o que é do painel todo:
   o drawer não fecha em silêncio por cima de alteração pendente. */
describe('alterações não salvas', () => {
  it('fechar o drawer com alteração pendente pede confirmação', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/conteudo/con_produtos' });

    const titulo = await screen.findByLabelText(/^Título/);
    await waitFor(() => expect(titulo).toHaveValue('Plataformas e produtos'));
    await usuario.type(titulo, 'x');

    await usuario.click(screen.getByRole('button', { name: 'Fechar' }));

    expect(
      await screen.findByRole('heading', { name: /você tem alterações não salvas/i }),
    ).toBeVisible();

    await usuario.click(screen.getByRole('button', { name: /descartar e fechar/i }));
    await waitFor(() => expect(screen.queryByLabelText(/^Título/)).not.toBeInTheDocument());
  });
});
