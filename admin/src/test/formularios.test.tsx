import { describe, expect, it } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderizarPainel } from './utils';

describe('validação de formulário', () => {
  it('o evento recusa nome vazio e slug inválido', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/evento' });

    const nome = await screen.findByLabelText(/^Nome/);
    await waitFor(() => expect(nome).toHaveValue('Mind Summit 2026'));

    await usuario.clear(nome);
    await usuario.clear(screen.getByLabelText(/^Slug/));
    await usuario.type(screen.getByLabelText(/^Slug/), 'Slug Inválido!');

    await usuario.click(screen.getByRole('button', { name: /salvar alterações/i }));

    expect(await screen.findByText('Informe o nome do evento.')).toBeVisible();
    expect(
      screen.getByText('Use apenas letras minúsculas, números e hífen.'),
    ).toBeVisible();
  });

  it('o evento recusa data final anterior à inicial', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/evento' });

    const dataFim = await screen.findByLabelText(/data final/i);
    await waitFor(() => expect(dataFim).toHaveValue('2026-09-17'));

    await usuario.clear(dataFim);
    await usuario.type(dataFim, '2026-09-15');
    await usuario.click(screen.getByRole('button', { name: /salvar alterações/i }));

    expect(await screen.findByText('A data final não pode ser anterior à inicial.')).toBeVisible();
  });

  it('salva o evento e confirma na tela', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/evento' });

    const cidade = await screen.findByLabelText(/^Cidade/);
    await waitFor(() => expect(cidade).toHaveValue('São Paulo'));

    await usuario.clear(cidade);
    await usuario.type(cidade, 'São Paulo · SP');
    await usuario.click(screen.getByRole('button', { name: /salvar alterações/i }));

    expect(await screen.findByText('Alterações salvas')).toBeVisible();
    expect(screen.getByText(/nada foi enviado ao supabase/i)).toBeVisible();
  });

  it('mostra a divergência de local sem escolher um dos dois', async () => {
    renderizarPainel({ rota: '/evento' });

    expect(
      await screen.findByText(/local do evento em divergência/i),
    ).toBeVisible();
    expect(screen.getByText('São Paulo Expo')).toBeVisible();
    expect(screen.getByText('Transamérica Expo Center')).toBeVisible();
    expect(screen.getByText(/o painel não decide qual está correto/i)).toBeVisible();
  });

  it('a sessão recusa horário final antes do inicial', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/programacao/ses_d1-09_00-abertura' });

    const fim = await screen.findByLabelText(/^Fim/);
    await waitFor(() => expect(fim).toHaveValue('09:15'));

    await usuario.clear(fim);
    await usuario.type(fim, '08:00');
    await usuario.click(screen.getByRole('button', { name: /^Salvar$/ }));

    expect(
      await screen.findByText('O horário final precisa ser depois do inicial.'),
    ).toBeVisible();
  });

  it('a sessão com reserva exige vagas totais', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/programacao/ses_d1-09_00-abertura' });

    const reserva = await screen.findByLabelText(/necessita reserva/i);
    await usuario.click(reserva);
    await usuario.click(screen.getByRole('button', { name: /^Salvar$/ }));

    expect(await screen.findByText('Sessão com reserva precisa de vagas totais.')).toBeVisible();
  });

  it('o espaço aceita adicionar e remover alias', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/espacos/esp_arena-top-voice' });

    const campo = await screen.findByLabelText(/apelidos reconhecidos/i);
    expect(screen.getByText(/palco ou arena sem alias vira pendência/i)).toBeVisible();

    await usuario.type(campo, 'top voice{Enter}');
    expect(await screen.findByText('top voice')).toBeVisible();

    await usuario.click(screen.getByRole('button', { name: 'Remover top voice' }));
    await waitFor(() => expect(screen.queryByText('top voice')).not.toBeInTheDocument());
  });

  it('a prévia do cartão do palestrante acompanha o formulário', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/palestrantes/pal_amy-edmondson' });

    await usuario.click(await screen.findByRole('tab', { name: /prévia no chat/i }));

    const previa = await screen.findByText(/como aparece no chat/i);
    const cartao = previa.parentElement as HTMLElement;
    expect(within(cartao).getByText('Amy Edmondson')).toBeVisible();

    await usuario.click(screen.getByRole('tab', { name: 'Dados' }));
    const biografia = screen.getByLabelText(/^Biografia/);
    await usuario.clear(biografia);

    await usuario.click(screen.getByRole('tab', { name: /prévia no chat/i }));
    expect(
      await screen.findByText(/sem biografia — o cartão sai vazio/i),
    ).toBeVisible();
  });
});

describe('alterações não salvas', () => {
  it('avisa na tela assim que o formulário fica sujo', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/evento' });

    const cidade = await screen.findByLabelText(/^Cidade/);
    await waitFor(() => expect(cidade).toHaveValue('São Paulo'));

    expect(screen.queryByText('Alterações não salvas')).not.toBeInTheDocument();
    await usuario.type(cidade, ' — capital');

    expect(await screen.findByText('Alterações não salvas')).toBeVisible();
  });

  it('bloqueia a troca de página e pede confirmação', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/evento' });

    const cidade = await screen.findByLabelText(/^Cidade/);
    await waitFor(() => expect(cidade).toHaveValue('São Paulo'));
    await usuario.type(cidade, ' — capital');

    const menu = screen.getByRole('navigation', { name: /navegação principal/i });
    await usuario.click(within(menu).getByRole('link', { name: /espaços/i }));

    /* A navegação não aconteceu: o diálogo segurou. Com o diálogo
       aberto, o Radix marca o resto da página como `aria-hidden` —
       por isso o `hidden: true` para alcançar o título por trás. */
    expect(
      await screen.findByRole('heading', { name: /você tem alterações não salvas/i }),
    ).toBeVisible();
    expect(
      screen.getByRole('heading', { name: 'Evento', level: 1, hidden: true }),
    ).toBeInTheDocument();

    await usuario.click(screen.getByRole('button', { name: /continuar editando/i }));
    await waitFor(() =>
      expect(
        screen.queryByRole('heading', { name: /você tem alterações não salvas/i }),
      ).not.toBeInTheDocument(),
    );
    expect(screen.getByRole('heading', { name: 'Evento', level: 1 })).toBeVisible();
  });

  it('sair sem salvar descarta e completa a navegação', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/evento' });

    const cidade = await screen.findByLabelText(/^Cidade/);
    await waitFor(() => expect(cidade).toHaveValue('São Paulo'));
    await usuario.type(cidade, ' — capital');

    const menu = screen.getByRole('navigation', { name: /navegação principal/i });
    await usuario.click(within(menu).getByRole('link', { name: /espaços/i }));
    await usuario.click(await screen.findByRole('button', { name: /sair sem salvar/i }));

    expect(await screen.findByRole('heading', { name: 'Espaços', level: 1 })).toBeVisible();
  });

  it('fechar o drawer com alteração pendente pede confirmação', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/estandes/est_mind' });

    const contato = await screen.findByLabelText(/^Contato/);
    await waitFor(() => expect(contato).toHaveValue('estande@exemplo.com.br'));
    await usuario.type(contato, 'x');

    await usuario.click(screen.getByRole('button', { name: 'Fechar' }));

    expect(
      await screen.findByRole('heading', { name: /você tem alterações não salvas/i }),
    ).toBeVisible();

    await usuario.click(screen.getByRole('button', { name: /descartar e fechar/i }));
    await waitFor(() => expect(screen.queryByLabelText(/^Contato/)).not.toBeInTheDocument());
  });
});
