import { describe, expect, it } from 'vitest';
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { contarLinhas, renderizarPainel } from './utils';

describe('listagens', () => {
  it('formata valores de oferta em BRL e sinaliza as quebradas', async () => {
    renderizarPainel({ rota: '/ofertas' });

    const linhaMind = await screen.findByTestId('linha-ofe_mind');
    expect(within(linhaMind).getByText(/R\$\s*890,00/)).toBeVisible();

    const linhaCorp = screen.getByTestId('linha-ofe_corp');
    expect(within(linhaCorp).getByText('sem valor')).toBeVisible();

    const linhaPrime = screen.getByTestId('linha-ofe_prime');
    expect(within(linhaPrime).getByText(/sem checkout/i)).toBeVisible();

    const linhaLote = screen.getByTestId('linha-ofe_lote1');
    expect(within(linhaLote).getByText(/vencida/i)).toBeVisible();
  });

  it('mostra os seis estados de indexação dos documentos', async () => {
    renderizarPainel({ rota: '/documentos' });

    expect(await screen.findByText('FAQ geral do Summit')).toBeVisible();
    for (const rotulo of ['Indexado', 'Desatualizado', 'Não indexado', 'Erro', 'Na fila']) {
      expect(screen.getAllByText(rotulo).length).toBeGreaterThan(0);
    }
  });

  it('a auditoria mostra antes, depois e o identificador da requisição', async () => {
    renderizarPainel({ rota: '/auditoria' });

    expect(await screen.findByRole('heading', { name: 'Auditoria', level: 1 })).toBeVisible();
    const linha = await screen.findByTestId('linha-aud_001');
    expect(within(linha).getByText('req_5f2c1a90')).toBeVisible();
    expect(within(linha).getByText(/em_revisao/)).toBeVisible();
    expect(within(linha).getByText(/publicado/)).toBeVisible();
  });

  it('busca textual estreita a lista', async () => {
    const usuario = userEvent.setup();
    const { container } = renderizarPainel({ rota: '/conteudo' });

    await screen.findByTestId('linha-con_produtos');
    const antes = contarLinhas(container);

    await usuario.type(screen.getByRole('searchbox', { name: 'Buscar' }), 'Plataformas');

    await screen.findByTestId('linha-con_produtos');
    expect(contarLinhas(container)).toBeLessThan(antes);
    expect(contarLinhas(container)).toBe(1);
  });
});
