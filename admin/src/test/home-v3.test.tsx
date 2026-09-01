import { describe, expect, it } from 'vitest';
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderizarPainel } from './utils';

/* ============================================================
   HOME V3
   ============================================================
   O módulo responde a uma pergunta operacional: o que o participante
   está vendo agora, e o que ele vai receber.

   Os testes cobrem o que quebraria em silêncio — a troca de momento que
   não persiste, o aviso que sai sem mensagem, e o disparo imediato que
   deveria entrar no ar mas fica agendado. */

describe('Home V3 · visualização', () => {
  it('mostra as quatro telas e marca a que está no ar', async () => {
    renderizarPainel({ rota: '/home/visualizacao' });

    expect(
      await screen.findByRole('heading', { name: 'Visualização da home', level: 1 }),
    ).toBeVisible();

    /* O esqueleto sai só quando a lista responde — esperar aqui é o que
       diferencia "a tela não tem os botões" de "a tela ainda não carregou". */
    expect(await screen.findByRole('button', { name: /^Antes/i })).toBeVisible();
    for (const rotulo of ['No evento', 'Entre dias', 'Depois']) {
      expect(screen.getByRole('button', { name: new RegExp('^' + rotulo, 'i') })).toBeVisible();
    }

    /* A semente começa em "Antes", e o botão da tela no ar fica pressionado
       e desabilitado — não faz sentido trocar para onde já se está. */
    const antes = screen.getByRole('button', { name: /^Antes/i });
    expect(antes).toHaveAttribute('aria-pressed', 'true');
    expect(antes).toBeDisabled();
  });

  it('troca a tela no ar e a marcação acompanha', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/home/visualizacao' });

    await usuario.click(await screen.findByRole('button', { name: /^No evento/i }));

    const noEvento = await screen.findByRole('button', { name: /^No evento/i });
    expect(noEvento).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('button', { name: /^Antes/i })).toHaveAttribute(
      'aria-pressed',
      'false',
    );
  });

  it('lista as trocas programadas e aceita uma nova', async () => {
    const usuario = userEvent.setup();
    const { container } = renderizarPainel({ rota: '/home/visualizacao' });

    expect(await screen.findByText('Trocas programadas')).toBeVisible();
    const antes = container.querySelectorAll('li').length;

    await usuario.type(screen.getByLabelText('Data e hora'), '2026-09-17T12:00');
    await usuario.click(screen.getByRole('button', { name: /programar/i }));

    expect(container.querySelectorAll('li').length).toBeGreaterThan(antes);
  });
});

describe('Home V3 · avisos', () => {
  it('lista os avisos existentes com título, subtítulo e mensagem', async () => {
    renderizarPainel({ rota: '/home/avisos' });

    expect(await screen.findByRole('heading', { name: 'Avisos', level: 1 })).toBeVisible();
    expect(await screen.findByText('Masterclass mudou de sala')).toBeVisible();
    expect(screen.getByText('Amy Edmondson, agora na Sala Estratégica.')).toBeVisible();
    expect(screen.getByText(/saiu da Arena Mind/i)).toBeVisible();
  });

  it('recusa aviso sem mensagem, em vez de publicar um card vazio', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/home/avisos' });

    await usuario.click(await screen.findByRole('button', { name: /novo aviso/i }));
    await usuario.type(screen.getByLabelText('Título'), 'Fila da entrada');
    await usuario.click(screen.getByRole('button', { name: /programar aviso/i }));

    expect(await screen.findByText(/escreva a mensagem/i)).toBeVisible();
  });

  it('exige horário quando o disparo não é imediato', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/home/avisos' });

    await usuario.click(await screen.findByRole('button', { name: /novo aviso/i }));
    await usuario.type(screen.getByLabelText('Título'), 'Fila da entrada');
    await usuario.type(screen.getByLabelText('Descrição'), 'A fila anda melhor pela lateral.');
    await usuario.click(screen.getByRole('button', { name: /programar aviso/i }));

    expect(await screen.findByText(/horário de disparo ou marque disparo imediato/i)).toBeVisible();
  });

  it('a prévia mostra o card do jeito que o app vai desenhar', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/home/avisos' });

    await usuario.click(await screen.findByRole('button', { name: /novo aviso/i }));
    const previa = screen.getByRole('complementary', { name: /prévia do aviso no app/i });

    /* Antes de digitar, a prévia mostra o esqueleto do card — senão não
       haveria o que olhar enquanto se escreve. */
    expect(within(previa).getByText('Na lista de avisos')).toBeVisible();
    expect(within(previa).getByText('Quando a pessoa toca')).toBeVisible();

    await usuario.type(screen.getByLabelText('Título'), 'Fila da entrada');
    await usuario.type(screen.getByLabelText('Subtítulo'), 'Entre pela lateral');
    await usuario.type(screen.getByLabelText('Descrição'), 'A fila da entrada principal está longa.');

    /* O título aparece nos dois estados: no card e no texto aberto. */
    expect(within(previa).getAllByText('Fila da entrada')).toHaveLength(2);
    expect(within(previa).getByText('Entre pela lateral')).toBeVisible();
    expect(within(previa).getByText('A fila da entrada principal está longa.')).toBeVisible();
  });

  it('disparo imediato entra no ar, não fica agendado', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/home/avisos' });

    await usuario.click(await screen.findByRole('button', { name: /novo aviso/i }));
    await usuario.type(screen.getByLabelText('Título'), 'Fila da entrada');
    await usuario.type(screen.getByLabelText('Descrição'), 'A fila anda melhor pela lateral.');
    await usuario.click(screen.getByLabelText(/disparo imediato/i));
    await usuario.click(screen.getByRole('button', { name: /disparar agora/i }));

    const novo = await screen.findByText('Fila da entrada');
    const cartao = novo.closest('li');
    expect(cartao).not.toBeNull();
    expect(within(cartao as HTMLElement).getByText('No ar')).toBeVisible();
  });
});
