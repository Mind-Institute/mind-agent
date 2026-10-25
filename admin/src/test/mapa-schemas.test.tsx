import { afterEach, describe, expect, it, vi } from 'vitest';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { criarPortaFalsa, renderizarPainel, SESSAO_DE_TESTE } from './utils';
import { buscarMapaSchemas } from '@/services/mapa-schemas';

const item = (schema_name: string, tipo = 'mind') => ({
  schema_name,
  categoria: `Categoria ${schema_name}`,
  funcao: `Função ${schema_name}`,
  fronteira: `Fronteira ${schema_name}`,
  tipo,
  objetos: [
    { nome: 'tabela_exemplo', tipo: 'table', comentario: 'Comentário de teste' },
    { nome: 'view_exemplo', tipo: 'view', comentario: null },
  ],
  auditado_em: '2026-10-23',
  observacoes: null,
  atualizado_em: '2026-10-23T12:00:00Z',
});

const corpo = {
  fonte: 'arquitetura.mapa_schemas',
  itens: [item('business_strategy'), item('auth', 'infra_plataforma')],
};

function conectar(payload: unknown = corpo, status = 200) {
  vi.stubEnv('VITE_SUPABASE_URL', 'https://test.supabase.co');
  const fetchImpl = vi.fn(async (url: RequestInfo | URL) => new Response(JSON.stringify(
    String(url).endsWith('/admin/me') ? { papel: 'administrador', nome: 'Teste' } : payload,
  ), { status: String(url).endsWith('/admin/me') ? 200 : status }));
  vi.stubGlobal('fetch', fetchImpl);
  renderizarPainel({
    rota: '/arquitetura/schemas',
    porta: criarPortaFalsa({ sessaoInicial: SESSAO_DE_TESTE }),
    baseUrlApi: 'https://test.supabase.co/functions/v1/admin',
    fetchImpl,
  });
  return fetchImpl;
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

describe('mapa de schemas', () => {
  it('não inventa arquitetura no modo demonstração', async () => {
    renderizarPainel({ rota: '/arquitetura/schemas' });
    expect(await screen.findByRole('heading', { name: 'Mapa de schemas' })).toBeVisible();
    expect(screen.getByText(/Conecte o painel ao Supabase/)).toBeVisible();
    expect(screen.queryByText('business_strategy')).toBeNull();
  });

  it('mostra dados vindos do Supabase, filtra e expande objetos', async () => {
    const request = conectar();
    expect(await screen.findByText('business_strategy')).toBeVisible();
    expect(screen.getByText('auth')).toBeVisible();
    expect(request.mock.calls.some(([url]) => String(url).endsWith('/mindagent-home/admin/mapa-schemas'))).toBe(true);

    await userEvent.type(screen.getByPlaceholderText(/Buscar schema/), 'business');
    expect(screen.getByText('business_strategy')).toBeVisible();
    expect(screen.queryByText('auth')).toBeNull();

    await userEvent.click(screen.getByText(/Ver tabelas e views/));
    expect(screen.getByText('tabela_exemplo')).toBeVisible();
    expect(screen.getByText('Comentário de teste')).toBeVisible();
  });

  it('recusa resposta de outra fonte', async () => {
    const fake = vi.fn(async () => new Response(JSON.stringify({ ...corpo, fonte: 'outra-fonte' })));
    await expect(buscarMapaSchemas({
      token: 'token-falso',
      baseUrl: 'https://test.invalid',
      fetchImpl: fake,
    })).rejects.toThrow();
  });
});
