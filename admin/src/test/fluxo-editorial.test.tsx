import { describe, expect, it } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderizarPainel } from './utils';

/* Publicar, arquivar e reindexar saíram com os módulos em demonstração
   (26/09/2026): o Catálogo lê e edita, nada além. Fica o que vale para
   toda escrita — não sobrescrever em silêncio a alteração de outra pessoa. */

describe('conflito de atualização', () => {
  it('avisa quando o registro mudou desde que a tela abriu', async () => {
    const usuario = userEvent.setup();
    const { provedor } = renderizarPainel({ rota: '/catalogo/prd_dash' });

    const nome = await screen.findByLabelText(/^Nome/);
    await waitFor(() => expect(nome).toHaveValue('Mind Dash'));

    /* Outra pessoa salva o mesmo registro enquanto esta tela está aberta. */
    await provedor.update('products', 'prd_dash', { descricao: 'alterado por outra pessoa' });

    await usuario.type(nome, 'x');
    await usuario.click(screen.getByRole('button', { name: /^Salvar$/ }));

    expect(await screen.findByRole('heading', { name: /conflito de atualização/i })).toBeVisible();
    expect(screen.getByText(/apagaria a alteração da outra pessoa/i)).toBeVisible();
    expect(screen.getByRole('button', { name: /recarregar versão atual/i })).toBeVisible();
  });
});
