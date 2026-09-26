import { describe, expect, it } from 'vitest';
import { screen, within } from '@testing-library/react';
import { renderizarPainel } from './utils';
import { ITENS_NAVEGACAO, NAVEGACAO } from '@/routes/navegacao';

describe('navegação', () => {
  it('mostra o Catálogo, um título por vertical e os admins do sistema', async () => {
    renderizarPainel();
    const menu = await screen.findByRole('navigation', { name: /navegação principal/i });

    expect(ITENS_NAVEGACAO.map((item) => item.rotulo)).toEqual(['Catálogo', 'Admins do sistema']);
    for (const item of ITENS_NAVEGACAO) {
      expect(
        within(menu).getByRole('link', { name: (nome) => nome.trim() === item.rotulo }),
      ).toBeVisible();
    }
    /* Pedido da Adriana (26/09/2026): um título por vertical. Por ora só o
       título — as principais tabelas de cada uma entram quando ela mapear. */
    for (const vertical of ['Summit', 'Institute', 'Dash']) {
      expect(within(menu).getByText(vertical)).toBeVisible();
    }
    expect(NAVEGACAO.filter((g) => ['summit', 'institute', 'dash'].includes(g.id)).map((g) => g.itens))
      .toEqual([[], [], []]);
    /* Pedido dela no mesmo dia: no lugar do antigo grupo de administração,
       só o quadro de quem entra no painel. */
    expect(within(menu).getByText('Administração')).toBeVisible();
    expect(NAVEGACAO.at(-1)?.itens.map((item) => item.caminho)).toEqual(['/admins']);
  });

  it('os admins do sistema aparecem travados para quem não é administrador', async () => {
    renderizarPainel({ papel: 'editor' });
    const menu = await screen.findByRole('navigation', { name: /navegação principal/i });

    const admins = within(menu).getByRole('link', { name: (nome) => nome.trim() === 'Admins do sistema' });
    expect(admins).toHaveAttribute('title', expect.stringMatching(/^Sem permissão/));
  });

  it('a barra lateral não fala mais do Summit 2026', async () => {
    renderizarPainel();
    const menu = await screen.findByRole('navigation', { name: /navegação principal/i });

    /* Pedido da Adriana (26/09/2026): o rodapé com data e local do evento
       era do app, não da inteligência do Mind. */
    expect(within(menu).queryByText(/16 e 17 de setembro/)).toBeNull();
    expect(within(menu).queryByText(/America\/Sao_Paulo/)).toBeNull();
  });

  /* Decisões da Adriana (26/09/2026): o que era do app do Summit saiu do
     painel, e depois tudo o que não era dado real. Promessa negativa
     apodrece calada — daí o teste. */
  it('não mostra o que saiu do painel: app do Summit e módulos em demonstração', async () => {
    renderizarPainel();
    const menu = await screen.findByRole('navigation', { name: /navegação principal/i });

    for (const rotulo of ['Visão geral', 'Home V3', 'Visualização', 'Avisos', 'Evento', 'Programação',
                          'Palestrantes', 'Espaços', 'Rotas', 'Estandes', 'Ingressos e ofertas',
                          'Conteúdo da Mind', 'FAQ e documentos', 'Conversas', 'Perguntas sem resposta',
                          'Usuários e permissões', 'Auditoria', 'Avaliação do dia', 'Avaliação do evento',
                          'Configurações']) {
      expect(
        within(menu).queryByRole('link', { name: (nome) => nome.trim() === rotulo }),
        `${rotulo} não deveria estar no menu`,
      ).toBeNull();
    }
    for (const caminho of ['/evento', '/programacao', '/palestrantes', '/espacos', '/rotas', '/estandes',
                           '/home/visualizacao', '/home/avisos', '/ofertas', '/conteudo', '/documentos',
                           '/conversas', '/perguntas', '/usuarios', '/auditoria', '/avaliacao-do-dia',
                           '/avaliacao-do-evento', '/configuracoes']) {
      expect(ITENS_NAVEGACAO.some((item) => item.caminho === caminho), caminho).toBe(false);
    }
  });

  it('a raiz abre o Catálogo', async () => {
    renderizarPainel();

    expect(await screen.findByRole('heading', { name: 'Catálogo', level: 1 })).toBeVisible();
  });

  it('endereço de módulo que saiu do painel cai na página de não encontrada', async () => {
    for (const rota of ['/programacao', '/ofertas', '/usuarios', '/avaliacao-do-dia', '/configuracoes']) {
      const { unmount } = renderizarPainel({ rota });
      expect(
        await screen.findByRole('heading', { name: /não existe no painel/i }),
        rota,
      ).toBeVisible();
      unmount();
    }
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
