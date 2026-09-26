import { describe, expect, it } from 'vitest';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { contarLinhas, renderizarPainel } from './utils';

/* As listagens dos módulos em demonstração saíram (26/09/2026). A que
   ficou é a do Catálogo. */

describe('listagens', () => {
  it('busca textual estreita a lista', async () => {
    const usuario = userEvent.setup();
    const { container } = renderizarPainel({ rota: '/catalogo' });

    await screen.findByTestId('linha-prd_journey_2027');
    const antes = contarLinhas(container);

    await usuario.type(screen.getByRole('searchbox', { name: 'Buscar' }), 'Journey');

    await screen.findByTestId('linha-prd_journey_2027');
    expect(contarLinhas(container)).toBeLessThan(antes);
    expect(contarLinhas(container)).toBe(1);
  });
});
