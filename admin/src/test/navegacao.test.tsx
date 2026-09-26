import { describe, expect, it } from 'vitest';
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { renderizarPainel } from './utils';
import { ITENS_NAVEGACAO } from '@/routes/navegacao';

describe('navegação', () => {
  it('mostra os onze módulos do menu lateral', async () => {
    renderizarPainel();
    const menu = await screen.findByRole('navigation', { name: /navegação principal/i });

    expect(ITENS_NAVEGACAO).toHaveLength(11);
    for (const item of ITENS_NAVEGACAO) {
      /* NOME INTEIRO, e não pedaço: "Avaliação do dia" e "Avaliação do
         evento" são dois itens do menu, e um regex solto casa com os dois. */
      expect(
        within(menu).getByRole('link', { name: (nome) => nome.trim() === item.rotulo }),
      ).toBeVisible();
    }
  });

  /* Decisão da Adriana (26/09/2026): o que era do app do Summit saiu do
     painel. Promessa negativa apodrece calada — daí o teste. */
  it('não mostra o que saiu do painel: visão geral, Home V3 e Evento', async () => {
    renderizarPainel();
    const menu = await screen.findByRole('navigation', { name: /navegação principal/i });

    for (const rotulo of ['Visão geral', 'Home V3', 'Visualização', 'Avisos', 'Evento', 'Programação',
                          'Palestrantes', 'Espaços', 'Rotas', 'Estandes']) {
      expect(
        within(menu).queryByRole('link', { name: (nome) => nome.trim() === rotulo }),
        `${rotulo} não deveria estar no menu`,
      ).toBeNull();
    }
    for (const caminho of ['/evento', '/programacao', '/palestrantes', '/espacos', '/rotas', '/estandes',
                           '/home/visualizacao', '/home/avisos']) {
      expect(ITENS_NAVEGACAO.some((item) => item.caminho === caminho), caminho).toBe(false);
    }
  });

  it('a raiz abre o Catálogo', async () => {
    renderizarPainel();

    expect(await screen.findByRole('heading', { name: 'Catálogo', level: 1 })).toBeVisible();
  });

  it('endereço de módulo que saiu do painel cai na página de não encontrada', async () => {
    renderizarPainel({ rota: '/programacao' });
    expect(
      await screen.findByRole('heading', { name: /não existe no painel/i }),
    ).toBeVisible();
  });

  it('navega do Catálogo para outro módulo pelo menu', async () => {
    const usuario = userEvent.setup();
    renderizarPainel();

    const menu = await screen.findByRole('navigation', { name: /navegação principal/i });
    await usuario.click(within(menu).getByRole('link', { name: /conteúdo da mind/i }));

    expect(await screen.findByRole('heading', { name: 'Conteúdo da Mind', level: 1 })).toBeVisible();
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
