import { describe, expect, it } from 'vitest';
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderizarPainel } from './utils';

/* ============================================================
   MASCARAMENTO NA TELA
   ============================================================
   Os testes acima (`dominio.test.ts`) provam as funções de máscara.
   Estes provam que as telas realmente as usam — que é onde o
   vazamento aconteceria. */

describe('mascaramento de dados pessoais nas telas', () => {
  it('a listagem de conversas não mostra e-mail nem telefone inteiros', async () => {
    const { container } = renderizarPainel({ rota: '/conversas' });

    await screen.findByTestId('linha-cnv_001');

    const texto = container.textContent ?? '';
    expect(texto).not.toContain('participante.dois@exemplo.com.br');
    expect(texto).not.toContain('5511900000001');

    const linha = screen.getByTestId('linha-cnv_002');
    expect(within(linha).getByText('pa•••@exemplo.com.br')).toBeVisible();
    expect(within(linha).getByText('Participante D.')).toBeVisible();
  });

  it('marca no DOM tudo que passou por máscara', async () => {
    const { container } = renderizarPainel({ rota: '/conversas' });
    await screen.findByTestId('linha-cnv_001');

    const mascarados = container.querySelectorAll('[data-mascarado="true"]');
    expect(mascarados.length).toBeGreaterThan(0);
  });

  it('o detalhe da conversa mascara contato digitado dentro da mensagem', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/conversas' });

    await usuario.click(await screen.findByTestId('linha-cnv_002'));

    const painel = await screen.findByRole('dialog');
    const texto = painel.textContent ?? '';

    /* A mensagem do participante contém o e-mail no meio da frase. */
    expect(texto).toContain('meu contato é');
    expect(texto).not.toContain('participante.dois@exemplo.com.br');
    expect(texto).toContain('pa•••@exemplo.com.br');
    expect(texto).toMatch(/somente leitura/i);
  });

  it('a listagem de usuários mascara o e-mail', async () => {
    const { container } = renderizarPainel({ rota: '/usuarios' });

    await screen.findByTestId('linha-usr_ana');
    const texto = container.textContent ?? '';

    expect(texto).not.toContain('ana.ribeiro@exemplo.com.br');
    expect(screen.getByText('an•••@exemplo.com.br')).toBeVisible();
  });

  it('a fila de perguntas mascara contato escrito na pergunta', async () => {
    renderizarPainel({ rota: '/perguntas' });

    await screen.findByTestId('linha-psr_001');
    /* Nenhuma pergunta do mock traz contato, e nenhuma deve trazer:
       o mascaramento é rede de segurança, não desculpa para semear
       dado pessoal. */
    const { container } = renderizarPainel({ rota: '/perguntas' });
    expect(container.textContent ?? '').not.toMatch(/@exemplo\.com\.br/);
  });
});
