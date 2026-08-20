import { describe, expect, it } from 'vitest';
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { contarLinhas, renderizarPainel } from './utils';

describe('listagens', () => {
  it('a programação lista as sessões do summit.json', async () => {
    const { container } = renderizarPainel({ rota: '/programacao' });

    expect(await screen.findByRole('heading', { name: 'Programação', level: 1 })).toBeVisible();
    /* O título da página aparece antes dos dados: esperar por uma
       linha da tabela é o que garante que a lista chegou. */
    const linha = await screen.findByTestId('linha-ses_d1-09_00-abertura');
    expect(within(linha).getByText('Abertura')).toBeVisible();
    expect(contarLinhas(container)).toBeGreaterThan(40);
  });

  it('marca na linha a sessão sem espaço', async () => {
    renderizarPainel({ rota: '/programacao?espacoId=null' });

    const selos = await screen.findAllByText('sem espaço');
    expect(selos.length).toBeGreaterThan(0);
  });

  it('mostra os aliases do espaço na listagem', async () => {
    renderizarPainel({ rota: '/espacos' });

    expect(await screen.findByText('Arena Mind')).toBeVisible();
    expect(screen.getByText('palco principal')).toBeVisible();
    expect(screen.getByText('palco mind')).toBeVisible();
    expect(screen.getByText('arena principal')).toBeVisible();
  });

  it('marca palco sem alias como pendência', async () => {
    renderizarPainel({ rota: '/espacos' });
    /* Arena Top Voice existe no summit.json e nasce sem alias. */
    expect(await screen.findByText('Arena Top Voice')).toBeVisible();
    expect(screen.getAllByText('palco sem alias').length).toBeGreaterThan(0);
  });

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

  it('busca textual estreita a lista de palestrantes', async () => {
    const usuario = userEvent.setup();
    const { container } = renderizarPainel({ rota: '/palestrantes' });

    await screen.findByText('Amy Edmondson');
    const antes = contarLinhas(container);

    await usuario.type(screen.getByRole('searchbox', { name: 'Buscar' }), 'Edmondson');

    await screen.findByText('Amy Edmondson');
    expect(contarLinhas(container)).toBeLessThan(antes);
    expect(contarLinhas(container)).toBe(1);
  });
});

describe('detecção de conflito de horário', () => {
  it('marca as sessões que dividem espaço e horário', async () => {
    renderizarPainel({ rota: '/programacao' });

    const linhaDemo = await screen.findByTestId('linha-ses_demo_conflito');
    expect(within(linhaDemo).getByText('conflito de horário')).toBeVisible();

    /* Conflito é sempre de dois: a sessão original também é marcada. */
    const linhaAbertura = screen.getByTestId('linha-ses_d1-09_00-abertura');
    expect(within(linhaAbertura).getByText('conflito de horário')).toBeVisible();

    expect(
      await screen.findByText(/sessão\(ões\) com conflito de horário no mesmo espaço/i),
    ).toBeVisible();
  });
});
