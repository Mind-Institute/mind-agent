import { describe, expect, it, vi } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import { ehErroAdmin, NOMES_RECURSOS } from '@/contracts';
import {
  HybridAdminDataProvider,
  RECURSOS_DO_CATALOGO,
} from '@/services/hybrid-admin-data-provider';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { CATALOGO_FALSO, SESSAO_DE_TESTE, lista, renderizarHibrido } from './utils';

/* ============================================================
   MODO HÍBRIDO — o de produção
   ============================================================
   Desde 26/09/2026 o painel só mostra dado real (decisão da Adriana).
   No modo híbrido o Catálogo vem da `mindagent-catalogo`; sem a função
   configurada ele cai no banco em memória e a tela diz "demonstração"
   (ver `catalogo.test.tsx`). */

/* O produto como a `mindagent-catalogo` devolve. Nome que o mock não tem:
   se a tela mostrar "Produto vindo da API", veio da API. */
const PRODUTO_DA_API = {
  id: '7a2b3c4d-5e6f-4a1b-8c2d-3e4f5a6b7c8d',
  criadoEm: '',
  atualizadoEm: '2026-09-13T15:30:00.123456+00:00',
  atualizadoPor: null,
  codigo: 'produto-da-api',
  nome: 'Produto vindo da API',
  tipo: 'curso',
  vertical: 'institute',
  categoria: null,
  descricaoCurta: null,
  descricao: null,
  ativo: true,
  vende: true,
  vendeDe: null,
  vendeAte: null,
  comecaEm: null,
  encerraEm: null,
  periodo: null,
  schemaDados: null,
  pipelinesHubspot: [],
};

const ROTAS_BASICAS = {
  '/admin/products': { corpo: lista([PRODUTO_DA_API]) },
};

describe('encaminhamento', () => {
  it('o catálogo é o único recurso do painel', () => {
    expect([...NOMES_RECURSOS]).toEqual(['products']);
    expect([...RECURSOS_DO_CATALOGO]).toEqual(['products']);
  });

  it('anuncia o modo como hybrid — nem mock, nem http', () => {
    const hibrido = new HybridAdminDataProvider(new MockAdminDataProvider({ latenciaMs: 0 }));
    expect(hibrido.modo).toBe('hybrid');
  });

  it('origemDoRecurso diz real com a função do catálogo, e demonstração sem ela', () => {
    const mock = new MockAdminDataProvider({ latenciaMs: 0 });
    const catalogo = new MockAdminDataProvider({ latenciaMs: 0 });
    expect(new HybridAdminDataProvider(mock, catalogo).origemDoRecurso('products')).toBe('http');
    expect(new HybridAdminDataProvider(mock).origemDoRecurso('products')).toBe('mock');
  });

  it('operação que a função não tem é recusada antes de sair', async () => {
    const hibrido = new HybridAdminDataProvider(
      new MockAdminDataProvider({ latenciaMs: 0 }),
      new MockAdminDataProvider({ latenciaMs: 0 }),
    );
    await expect(hibrido.create('products', {})).rejects.toSatisfy(
      (e: unknown) => ehErroAdmin(e) && /criar produto ainda não existe/.test(e.message),
    );
  });
});

describe('módulo real na tela', () => {
  it('o catálogo lista o que a API devolveu, não o mock', async () => {
    const { falso } = renderizarHibrido({ rota: '/catalogo', rotas: ROTAS_BASICAS });

    const linha = await screen.findByTestId(`linha-${PRODUTO_DA_API.id}`);
    expect(within(linha).getByText('Produto vindo da API')).toBeVisible();
    expect(screen.queryByTestId('linha-prd_mind')).not.toBeInTheDocument();
    expect(falso.ultima('/admin/products')?.url.startsWith(CATALOGO_FALSO)).toBe(true);
  });

  it('a listagem real é marcada como real', async () => {
    renderizarHibrido({ rota: '/catalogo', rotas: ROTAS_BASICAS });
    expect(await screen.findByTestId('selo-origem-real')).toHaveTextContent('dados reais');
    expect(screen.queryByTestId('selo-origem-mock')).not.toBeInTheDocument();
  });
});

describe('sem queda para o mock', () => {
  it('erro na listagem real mostra a tela de erro, não dado simulado', async () => {
    renderizarHibrido({
      rota: '/catalogo',
      rotas: {
        '/admin/products': {
          status: 503,
          corpo: { codigo: 'indisponivel', mensagem: 'Em manutenção.' },
        },
      },
    });

    expect(await screen.findByText('Serviço indisponível')).toBeVisible();
    expect(screen.getByText('Em manutenção.')).toBeVisible();
    /* Nenhuma linha do mock aparece no lugar. */
    expect(screen.queryByTestId('linha-prd_mind')).not.toBeInTheDocument();
  });

  it('erro de rede também não cai no mock', async () => {
    renderizarHibrido({
      rota: '/catalogo',
      rotas: { '/admin/products': { erroDeRede: true } },
    });

    expect(await screen.findByText('Não foi possível carregar')).toBeVisible();
    expect(screen.queryByTestId('linha-prd_mind')).not.toBeInTheDocument();
  });
});

describe('o token no modo híbrido', () => {
  it('vai no Authorization das chamadas reais e nunca na URL', async () => {
    const { falso } = renderizarHibrido({ rota: '/catalogo', rotas: ROTAS_BASICAS });

    await screen.findByTestId(`linha-${PRODUTO_DA_API.id}`);
    await waitFor(() => expect(falso.ultima('/admin/products')).toBeDefined());

    for (const chamada of falso.chamadas) {
      expect(chamada.cabecalhos.Authorization).toBe(`Bearer ${SESSAO_DE_TESTE.accessToken}`);
      expect(chamada.cabecalhos.apikey).toBe('sb_publishable_de_teste');
      expect(chamada.url).not.toContain(SESSAO_DE_TESTE.accessToken);
      expect(chamada.url.toLowerCase()).not.toContain('token');
    }
  });

  it('não aparece em nenhuma saída de console', async () => {
    const escrito: string[] = [];
    const capturar = (...args: unknown[]) => escrito.push(args.map(String).join(' '));
    const espioes = (['log', 'info', 'warn', 'error', 'debug'] as const).map((nivel) =>
      vi.spyOn(console, nivel).mockImplementation(capturar),
    );

    try {
      const { falso } = renderizarHibrido({ rota: '/catalogo', rotas: ROTAS_BASICAS });
      await screen.findByTestId(`linha-${PRODUTO_DA_API.id}`);
      await waitFor(() => expect(falso.ultima('/admin/products')).toBeDefined());
    } finally {
      espioes.forEach((e) => e.mockRestore());
    }

    const tudo = escrito.join('\n');
    expect(tudo).not.toContain(SESSAO_DE_TESTE.accessToken);
    expect(tudo).not.toMatch(/bearer/i);
    expect(tudo).not.toMatch(/sb_publishable/i);
  });
});

describe('o selo do topo', () => {
  it('diz que o que está na tela é dado real', async () => {
    renderizarHibrido({ rotas: ROTAS_BASICAS });

    await screen.findByTestId(`linha-${PRODUTO_DA_API.id}`);
    /* O selo do topo e o da listagem dizem o mesmo — e dizem a verdade. */
    const selos = screen.getAllByText('dados reais');
    expect(selos.length).toBeGreaterThanOrEqual(2);
    for (const selo of selos) expect(selo).toBeVisible();
    /* Os textos antigos, de quando havia módulo em demonstração. */
    expect(screen.queryByText(/dashboard real · cadastros mock/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/núcleo real/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/parte em demonstração/i)).not.toBeInTheDocument();
  });
});
