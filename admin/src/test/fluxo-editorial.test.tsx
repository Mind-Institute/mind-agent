import { describe, expect, it } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderizarPainel } from './utils';

describe('publicação (mock)', () => {
  it('aprovador publica um rascunho e a listagem passa a mostrar Publicado', async () => {
    const usuario = userEvent.setup();
    const { provedor } = renderizarPainel({ rota: '/conteudo/con_produtos', papel: 'aprovador' });

    await screen.findByDisplayValue('Plataformas e produtos');
    await usuario.click(screen.getByRole('button', { name: /publicar/i }));

    await waitFor(async () => {
      const registro = await provedor.get('content', 'con_produtos');
      expect(registro.status).toBe('publicado');
      expect(registro.publicadoEm).toBeTruthy();
      expect(registro.publicadoPor).toBeTruthy();
    });

    await usuario.click(screen.getByRole('button', { name: 'Fechar' }));
    const linha = await screen.findByTestId('linha-con_produtos');
    expect(within(linha).getByText('Publicado')).toBeVisible();
  });

  it('editor não vê o botão de publicar — ele só salva', async () => {
    renderizarPainel({ rota: '/conteudo/con_produtos', papel: 'editor' });

    await screen.findByDisplayValue('Plataformas e produtos');
    expect(screen.queryByRole('button', { name: /publicar/i })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /^Salvar$/ })).toBeInTheDocument();
  });

  it('registro publicado mostra data e responsável', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/conteudo/con_produtos', papel: 'administrador' });

    await screen.findByDisplayValue('Plataformas e produtos');
    await usuario.click(screen.getByRole('button', { name: /publicar/i }));

    expect(await screen.findByText(/^Publicado em .+ por .+/)).toBeVisible();
  });
});

describe('arquivamento (mock)', () => {
  it('pede confirmação, explica que não apaga e arquiva', async () => {
    const usuario = userEvent.setup();
    const { provedor } = renderizarPainel({ rota: '/estandes/est_mind' });

    await screen.findByDisplayValue('Mind Institute');
    await usuario.click(screen.getByRole('button', { name: /arquivar/i }));

    expect(await screen.findByRole('heading', { name: /arquivar registro/i })).toBeVisible();
    expect(screen.getByText(/não é apagado/i)).toBeVisible();
    expect(screen.getByText(/prefere arquivar a excluir de vez/i)).toBeVisible();

    await usuario.click(screen.getByRole('button', { name: /^Arquivar$/ }));

    await waitFor(async () => {
      const registro = await provedor.get('booths', 'est_mind');
      expect(registro.ativo).toBe(false);
    });

    /* Arquivado é diferente de apagado: o registro continua na lista. */
    const total = await provedor.list('booths');
    expect(total.itens.some((e) => e.id === 'est_mind')).toBe(true);
  });

  it('cancelar a confirmação não arquiva nada', async () => {
    const usuario = userEvent.setup();
    const { provedor } = renderizarPainel({ rota: '/estandes/est_mind' });

    await screen.findByDisplayValue('Mind Institute');
    await usuario.click(screen.getByRole('button', { name: /arquivar/i }));
    await usuario.click(await screen.findByRole('button', { name: 'Cancelar' }));

    const registro = await provedor.get('booths', 'est_mind');
    expect(registro.ativo).toBe(true);
  });

  it('atendimento não vê ação de arquivar', async () => {
    renderizarPainel({ rota: '/estandes/est_mind', papel: 'atendimento' });

    await screen.findByDisplayValue('Mind Institute');
    expect(screen.queryByRole('button', { name: /arquivar/i })).not.toBeInTheDocument();
  });
});

describe('conflito de atualização', () => {
  it('avisa quando o registro mudou desde que a tela abriu', async () => {
    const usuario = userEvent.setup();
    const { provedor } = renderizarPainel({ rota: '/estandes/est_sextante' });

    const contato = await screen.findByLabelText(/^Contato/);
    await waitFor(() => expect(contato).toHaveValue('contato@exemplo.com.br'));

    /* Outra pessoa salva o mesmo registro enquanto esta tela está aberta. */
    await provedor.update('booths', 'est_sextante', { descricao: 'alterado por outra pessoa' });

    await usuario.type(contato, 'x');
    await usuario.click(screen.getByRole('button', { name: /^Salvar$/ }));

    expect(await screen.findByRole('heading', { name: /conflito de atualização/i })).toBeVisible();
    expect(screen.getByText(/apagaria a alteração da outra pessoa/i)).toBeVisible();
    expect(screen.getByRole('button', { name: /recarregar versão atual/i })).toBeVisible();
  });
});

describe('reindexação (mock)', () => {
  it('enfileira e diz, em texto, que nada foi indexado', async () => {
    const usuario = userEvent.setup();
    const { provedor } = renderizarPainel({ rota: '/documentos/doc_mapa_pdf' });

    await screen.findByDisplayValue('Mapa do pavilhão (PDF)');
    /* A listagem por trás do drawer tem o mesmo botão em cada linha —
       a busca precisa ser dentro do drawer. */
    const drawer = within(screen.getByRole('dialog'));
    expect(drawer.getByText('Nunca indexado.')).toBeVisible();

    await usuario.click(drawer.getByRole('button', { name: /solicitar reindexação/i }));

    expect(
      await screen.findByRole('heading', { name: /pedido registrado — nada foi indexado/i }),
    ).toBeVisible();
    expect(screen.getByText(/o pipeline de indexação vive no backend/i)).toBeVisible();
    expect(screen.getByText(/Não indexado → Na fila/)).toBeVisible();

    const documento = await provedor.get('documents', 'doc_mapa_pdf');
    expect(documento.statusIndexacao).toBe('na_fila');
    /* O status NÃO pode ter virado "indexado": nada foi indexado. */
    expect(documento.indexadoEm).toBeNull();
  });

  it('a reindexação entra na auditoria', async () => {
    const usuario = userEvent.setup();
    const { provedor } = renderizarPainel({ rota: '/documentos/doc_mapa_pdf' });

    await screen.findByDisplayValue('Mapa do pavilhão (PDF)');
    const drawer = within(screen.getByRole('dialog'));
    await usuario.click(drawer.getByRole('button', { name: /solicitar reindexação/i }));
    await screen.findByRole('heading', { name: /pedido registrado/i });

    const auditoria = await provedor.list('audit', { ordenar: '-ocorridoEm' });
    const registro = auditoria.itens.find((r) => r.registroId === 'doc_mapa_pdf');
    expect(registro?.acao).toBe('reindexar');
    expect(registro?.depois).toMatchObject({ statusIndexacao: 'na_fila' });
  });

  it('analista não vê o botão de reindexar', async () => {
    renderizarPainel({ rota: '/documentos', papel: 'analista' });

    await screen.findByTestId('linha-doc_mapa_pdf');
    expect(
      screen.queryByRole('button', { name: /solicitar reindexação/i }),
    ).not.toBeInTheDocument();
  });
});
