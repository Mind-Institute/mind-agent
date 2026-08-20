import { describe, expect, it } from 'vitest';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { contarLinhas, renderizarPainel } from './utils';

describe('filtros', () => {
  it('filtrar por dia reduz a grade — e o filtro vem da URL', async () => {
    const { container, unmount } = renderizarPainel({ rota: '/programacao' });
    await screen.findByTestId('linha-ses_d1-09_00-abertura');
    const total = contarLinhas(container);
    unmount();

    const filtrado = renderizarPainel({ rota: '/programacao?dia=2026-09-17' });
    await filtrado.findByTestId('linha-ses_d2-09_00-quem_enxerga_antes_lide');
    const doSegundoDia = contarLinhas(filtrado.container);

    expect(doSegundoDia).toBeGreaterThan(0);
    expect(doSegundoDia).toBeLessThan(total);
    expect(screen.queryByTestId('linha-ses_d1-09_00-abertura')).not.toBeInTheDocument();
  });

  it('filtrar por espaço mostra só as sessões daquele palco', async () => {
    const { container } = renderizarPainel({
      rota: '/programacao?espacoId=esp_sala-workshop-1',
    });
    /* Cinco ocorrências: as quatro linhas da tabela mais o rótulo do
       filtro escolhido, que a barra mostra de volta. */
    expect(await screen.findAllByText('Sala Workshop 1')).toHaveLength(5);
    expect(contarLinhas(container)).toBe(4);
    expect(screen.queryByText('Arena Sextante')).not.toBeInTheDocument();
  });

  it('filtrar documentos por status de indexação', async () => {
    const { container } = renderizarPainel({ rota: '/documentos?statusIndexacao=erro' });
    await screen.findByTestId('linha-doc_precos');
    expect(contarLinhas(container)).toBe(1);
  });

  it('o botão limpar devolve a lista inteira', async () => {
    const usuario = userEvent.setup();
    const { container } = renderizarPainel({ rota: '/ofertas?publico=corporativo' });

    await screen.findByTestId('linha-ofe_corp');
    expect(contarLinhas(container)).toBe(1);

    await usuario.click(screen.getByRole('button', { name: /limpar/i }));

    await screen.findByTestId('linha-ofe_mind');
    expect(contarLinhas(container)).toBeGreaterThan(1);
  });
});

describe('estados das páginas', () => {
  it('estado vazio quando nada bate com a busca', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/estandes' });

    await screen.findByTestId('linha-est_mind');
    await usuario.type(screen.getByRole('searchbox', { name: 'Buscar' }), 'zzzzz-inexistente');

    expect(await screen.findByText('Nenhum estande cadastrado')).toBeVisible();
  });

  it('estado vazio próprio de cada módulo explica o efeito no agente', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/rotas' });

    await screen.findByTestId('linha-rot_001');
    await usuario.type(screen.getByRole('searchbox', { name: 'Buscar' }), 'xyzxyz');

    expect(await screen.findByText('Nenhuma rota cadastrada')).toBeVisible();
    expect(
      screen.getByText(/o agente sabe onde o espaço fica mas não sabe explicar como chegar/i),
    ).toBeVisible();
  });

  it('estado de erro quando a API falha, com botão de tentar novamente', async () => {
    const provedor = new MockAdminDataProvider({ latenciaMs: 0 });
    provedor.configurarFalha('booths', 'rede');

    renderizarPainel({ rota: '/estandes', provedor });

    expect(await screen.findByText('Não foi possível carregar')).toBeVisible();
    expect(
      screen.getByText(/não foi possível falar com a api administrativa/i),
    ).toBeVisible();

    const usuario = userEvent.setup();
    provedor.limparFalhas();
    await usuario.click(screen.getByRole('button', { name: /tentar novamente/i }));

    expect(await screen.findByTestId('linha-est_mind')).toBeVisible();
  });

  it('erro da visão geral não derruba a página', async () => {
    const provedor = new MockAdminDataProvider({ latenciaMs: 0 });
    provedor.configurarFalha('dashboard', 'indisponivel');

    renderizarPainel({ rota: '/', provedor });

    expect(await screen.findByText('Serviço indisponível')).toBeVisible();
    expect(screen.getByRole('heading', { name: 'Visão geral', level: 1 })).toBeVisible();
  });

  it('estado sem permissão quando o papel não pode ver o módulo', async () => {
    renderizarPainel({ rota: '/usuarios', papel: 'editor' });

    expect(await screen.findByText('Sem permissão')).toBeVisible();
    expect(screen.getByText(/não pode gerir usuários e permissões/i)).toBeVisible();
    /* A tela diz de onde vem o bloqueio de verdade. */
    expect(screen.getByText(/a recusa definitiva é do backend/i)).toBeVisible();
  });

  it('atendimento lê conversas mas não vê a auditoria', async () => {
    const { unmount } = renderizarPainel({ rota: '/conversas', papel: 'atendimento' });
    expect(await screen.findByRole('heading', { name: 'Conversas', level: 1 })).toBeVisible();
    expect(await screen.findByTestId('linha-cnv_001')).toBeVisible();
    unmount();

    renderizarPainel({ rota: '/auditoria', papel: 'atendimento' });
    expect(await screen.findByText('Sem permissão')).toBeVisible();
  });

  it('mostra o esqueleto de carregamento antes dos dados chegarem', async () => {
    const provedor = new MockAdminDataProvider({ latenciaMs: 40 });
    renderizarPainel({ rota: '/espacos', provedor });

    expect(screen.getByRole('status')).toHaveAttribute('aria-busy', 'true');
    expect(await screen.findByTestId('linha-esp_arena-mind')).toBeVisible();
  });
});
