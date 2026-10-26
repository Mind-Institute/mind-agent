import { afterEach, describe, expect, it, vi } from 'vitest';
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { criarPortaFalsa, renderizarPainel, SESSAO_DE_TESTE } from './utils';
import { buscarBusinessConsulting } from '@/services/business-consulting';

const LIVRO = '11111111-1111-4111-8111-111111111111';
const CAP = '22222222-2222-4222-8222-222222222222';
const PARTE = '33333333-3333-4333-8333-333333333333';
const A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

const objeto = (id: string, nome: string) => ({
  id, livro_id: LIVRO, familia: 'MODEL', tipo: 'framework', nome, resumo: `Resumo de ${nome}`,
  escopo: null, topicos: ['gtm'], confianca: 0.9, status: 'full_book_candidate', capitulo: 'Revenue Model', secao_id: CAP,
});

const corpo = {
  fonte: 'business_strategy',
  livros: [{
    id: LIVRO, titulo: 'Revenue Architecture', autores: ['Jacco van der Kooij'], tipo: 'book', ano: null,
    acesso: 'mind_only', status: 'full_book_ingested', paginas: 518, secoes: 2, secoes_processadas: 2,
    objetos: 2, criado_em: '2026-10-24T21:51:47Z', atualizado_em: '2026-10-24T22:06:23Z',
  }],
  objetos: [objeto(A, 'Revenue Factory'), objeto(B, 'Bowtie Model')],
  secoes: [
    { id: PARTE, livro_id: LIVRO, pai_id: null, tipo: 'part', numero: '1', titulo: 'Fundamentals', ordem: 1, pagina_inicio: 10, pagina_fim: 90 },
    { id: CAP, livro_id: LIVRO, pai_id: null, tipo: 'chapter', numero: '2', titulo: 'Revenue Model', ordem: 2, pagina_inicio: 20, pagina_fim: 60 },
  ],
  relacoes: [{ de: A, para: B, tipo: 'uses' }],
  totais: { livros: 1, objetos: 2, citacoes: 3, relacoes: 1 },
};

const detalhe = {
  fonte: 'business_strategy',
  objeto: {
    ...objeto(B, 'Bowtie Model'), livro: 'Revenue Architecture', aliases: [], condicoes: [], limitacoes: [],
    status_epistemico: 'author_methodology', portabilidade: 'source_specific', dominios: ['revenue'],
    niveis: ['business_system'], detalhes: { stages: ['awareness', 'education'] },
  },
  citacoes: [{ papel: 'primary_explanation', localizador: 'Section 05', pagina_inicio: 120, pagina_fim: 140,
    resumo: 'Onde o livro explica o Bowtie.', capitulo: 'Revenue Model' }],
  relacoes: [{ direcao: 'entrada', tipo: 'uses', outro_id: A, outro_nome: 'Revenue Factory', resumo: 'A fábrica usa o bowtie.', confianca: 0.95 }],
};

function conectar() {
  vi.stubEnv('VITE_SUPABASE_URL', 'https://test.supabase.co');
  const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
    const u = String(url);
    const payload = u.endsWith('/admin/me') ? { papel: 'administrador', nome: 'Teste' }
      : u.endsWith(`/admin/business-consulting/${B}`) ? detalhe
      : corpo;
    return new Response(JSON.stringify(payload), { status: 200 });
  });
  vi.stubGlobal('fetch', fetchImpl);
  renderizarPainel({
    rota: '/business-consulting',
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

describe('Business Consulting Knowledge', () => {
  it('não inventa conhecimento no modo demonstração', async () => {
    renderizarPainel({ rota: '/business-consulting' });
    expect(await screen.findByRole('heading', { name: 'Business Consulting Knowledge', level: 1 })).toBeVisible();
    expect(screen.getByText(/Conecte o painel ao Supabase/)).toBeVisible();
  });

  it('abre a árvore livro → capítulo → objeto → relação, e a ficha com a página', async () => {
    const pedidos = conectar();
    const arvore = await screen.findByRole('list', { name: 'Árvore do conhecimento' });
    expect(pedidos.mock.calls.some(([u]) => String(u).endsWith('/mindagent-home/admin/business-consulting'))).toBe(true);

    await userEvent.click(within(arvore).getAllByRole('button', { name: 'Expandir' })[0]);
    // Parte sem objetos é divisória; o capítulo abre.
    expect(within(arvore).getByText('Fundamentals')).toBeVisible();
    await userEvent.click(within(arvore).getAllByRole('button', { name: 'Expandir' })[0]);
    expect(within(arvore).getByRole('button', { name: 'Revenue Factory' })).toBeVisible();

    // Revenue Factory usa o Bowtie: abrir o objeto mostra a relação.
    const linhaFactory = within(arvore).getByRole('button', { name: 'Revenue Factory' }).closest('li')!;
    await userEvent.click(within(linhaFactory).getByRole('button', { name: 'Expandir' }));
    expect(within(linhaFactory).getByText('uses')).toBeVisible();

    await userEvent.click(within(linhaFactory).getAllByRole('button', { name: 'Bowtie Model' })[0]);
    expect(await screen.findByText('Onde o livro explica o Bowtie.')).toBeVisible();
    expect(screen.getByText(/p\. 120–140/)).toBeVisible();
  });

  it('a lista busca por nome', async () => {
    conectar();
    await screen.findByRole('list', { name: 'Árvore do conhecimento' });
    await userEvent.click(screen.getByRole('tab', { name: 'Lista' }));
    await userEvent.type(screen.getByPlaceholderText(/Buscar modelo/), 'bowtie');
    expect(screen.getByText('1 de 2 objetos exibidos.', { exact: false })).toBeVisible();
  });

  it('recusa resposta de outra fonte', async () => {
    const fake = vi.fn(async () => new Response(JSON.stringify({ ...corpo, fonte: 'outra' })));
    await expect(buscarBusinessConsulting({ token: 't', baseUrl: 'https://test.invalid', fetchImpl: fake })).rejects.toThrow();
  });
});
