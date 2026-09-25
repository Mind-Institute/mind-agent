import { describe, expect, it } from 'vitest';
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderizarPainel } from './utils';
import { ITENS_NAVEGACAO } from '@/routes/navegacao';

describe('navegação', () => {
  it('mostra os vinte módulos do menu lateral', async () => {
    renderizarPainel();
    const menu = await screen.findByRole('navigation', { name: /navegação principal/i });

    expect(ITENS_NAVEGACAO).toHaveLength(20);
    for (const item of ITENS_NAVEGACAO) {
      /* NOME INTEIRO, e não pedaço: "Evento" e "Avaliação do evento" são
         dois itens do menu, e um regex solto casa com os dois. */
      expect(
        within(menu).getByRole('link', { name: (nome) => nome.trim() === item.rotulo }),
      ).toBeVisible();
    }
  });

  it('abre a visão geral na raiz, com métricas e pendências', async () => {
    renderizarPainel();

    expect(await screen.findByRole('heading', { name: 'Visão geral', level: 1 })).toBeVisible();
    expect(await screen.findByText('Pendências importantes')).toBeVisible();
    expect(await screen.findByText('Sessões sem espaço')).toBeVisible();
    expect(screen.getByText('Palcos sem aliases')).toBeVisible();
  });

  it('navega da visão geral para a programação pelo menu', async () => {
    const usuario = userEvent.setup();
    renderizarPainel();

    const menu = await screen.findByRole('navigation', { name: /navegação principal/i });
    await usuario.click(within(menu).getByRole('link', { name: /programação/i }));

    expect(await screen.findByRole('heading', { name: 'Programação', level: 1 })).toBeVisible();
  });

  /* O TEMPO DESTE TESTE CRESCE COM O MENU: ele monta e desmonta o painel
     uma vez por módulo, e cada módulo novo o deixa mais lento. Com o
     limite padrão de 5 s ele passou a estourar em rodada cheia ao chegar
     ao décimo nono — não por lentidão de um módulo, mas por ser O(n). O
     limite acompanha o que o teste faz. */
  it('cada módulo abre sem quebrar', async () => {
    for (const item of ITENS_NAVEGACAO) {
      const { unmount } = renderizarPainel({ rota: item.caminho });
      expect(
        await screen.findByRole('heading', { level: 1 }),
        `módulo ${item.rotulo} não renderizou título`,
      ).toBeVisible();
      unmount();
    }
  }, 20_000);

  it('endereço desconhecido cai na página de não encontrada', async () => {
    renderizarPainel({ rota: '/rota-que-nao-existe' });
    expect(
      await screen.findByRole('heading', { name: /não existe no painel/i }),
    ).toBeVisible();
  });
});
