import { afterEach, describe, expect, it, vi } from 'vitest';
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { criarPortaFalsa, renderizarPainel, SESSAO_DE_TESTE } from './utils';
import { buscarDecisoes } from '@/services/decisoes';

// Dados inventados de teste, sem copiar decisões reais para o código.
const registro = (codigo: string) => ({ codigo, titulo: `Título de teste ${codigo}`,
  texto: `Texto aprovado de teste ${codigo}`, significado: `Significado de teste ${codigo}`,
  decidida_em: '2026-10-07', aprovada_por: 'Responsável de teste', vigencia: 'vigente',
  substituida_por: null, situacao: null, leitura: null, lugares: null, medido_em: null });
const corpo = { fonte: 'arquitetura.decisoes', itens: [registro('D1'), registro('D27')] };
function conectar(status = 200, payload: unknown = corpo) {
  vi.stubEnv('VITE_SUPABASE_URL', 'https://test.supabase.co');
  const fetchImpl = vi.fn(async (url: RequestInfo | URL) => new Response(JSON.stringify(
    String(url).endsWith('/admin/me') ? { papel: 'administrador', nome: 'Teste' } : payload,
  ), { status: String(url).endsWith('/admin/me') ? 200 : status }));
  vi.stubGlobal('fetch', fetchImpl);
  renderizarPainel({ rota: '/arquitetura/decisoes?d=D27',
    porta: criarPortaFalsa({ sessaoInicial: SESSAO_DE_TESTE }),
    baseUrlApi: 'https://test.supabase.co/functions/v1/admin', fetchImpl });
  return fetchImpl;
}
afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });
describe('decisões oficiais', () => {
  it('o menu leva à tela e demonstração não inventa uma lista', async () => {
    renderizarPainel({ rota: '/arquitetura/decisoes' });
    expect(await screen.findByRole('heading', { name: 'Decisões do sistema' })).toBeVisible();
    expect(screen.getByText(/Conecte o painel ao Supabase/)).toBeVisible();
    expect(screen.queryByRole('table')).toBeNull();
  });
  it('mostra os registros recebidos e abre qualquer código pelo endereço', async () => {
    const request = conectar();
    expect(await screen.findByRole('heading', { name: 'Título de teste D27' })).toBeVisible();
    const mapa = screen.getByRole('table');
    expect(within(mapa).getByRole('rowheader', { name: 'D27' })).toBeVisible();
    expect(screen.getByText('Texto aprovado de teste D27')).toBeVisible();
    expect(screen.getByText('Significado de teste D27')).toBeVisible();
    expect(request.mock.calls.some(([url]) => String(url).endsWith('/mindagent-home/admin/decisoes'))).toBe(true);
    await userEvent.click(within(mapa).getByRole('button', { name: 'D1' }));
    expect(screen.getByRole('heading', { name: 'Título de teste D1' })).toBeVisible();
  });
  it('mostra falha sem usar uma cópia local', async () => {
    conectar(503, { codigo: 'indisponivel', mensagem: 'Erro de teste' });
    expect(await screen.findByText('Não foi possível consultar as decisões oficiais.')).toBeVisible();
    expect(screen.queryByRole('table')).toBeNull();
  });
  it('mostra lista vazia sem fabricar decisões', async () => {
    conectar(200, { fonte: 'arquitetura.decisoes', itens: [] });
    expect(await screen.findByText('Nenhuma decisão registrada.')).toBeVisible();
  });
  it('manda o token no header e recusa resposta com fonte incorreta', async () => {
    const fake = vi.fn(async () => new Response(JSON.stringify({ ...corpo, fonte: 'outra-fonte' })));
    await expect(buscarDecisoes({ token: 'token-falso', baseUrl: 'https://test.invalid', fetchImpl: fake })).rejects.toThrow();
    expect(fake).toHaveBeenCalledWith('https://test.invalid/admin/decisoes', expect.objectContaining({
      headers: expect.objectContaining({ Authorization: 'Bearer token-falso' }),
    }));
  });
});
