import { describe, expect, it } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ehErroAdmin } from '@/contracts';
import { HttpAdminDataProvider } from '@/services/http-admin-data-provider';
import {
  API_FALSA,
  CHAVE_FALSA,
  SESSAO_DE_TESTE,
  criarFetchFalso,
  lista,
  renderizarHibrido,
} from './utils';

/* ============================================================
   API REAL — verbos, cabeçalhos, contrato e códigos de erro
   ============================================================
   Tudo hermético: um `fetch` falso registra método, URL e cabeçalhos.
   Nenhuma requisição sai da máquina e o Supabase real nunca é tocado.

   Desde 26/09/2026 o único recurso real do painel é o Catálogo
   (`products`, na `mindagent-catalogo`) — o resto não era dado real e
   saiu. É por ele que o contrato e cada status são conferidos. */

/* O produto como a `mindagent-catalogo` devolve. */
const PRODUTO_REAL = {
  id: '5c6d7e8f-9a0b-4c1d-8e2f-3a4b5c6d7e8f',
  criadoEm: '',
  atualizadoEm: '2026-09-13T15:30:00.123456+00:00',
  atualizadoPor: null,
  codigo: 'produto-real',
  nome: 'Produto real',
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

const ROTAS_CATALOGO = { '/admin/products': { corpo: lista([PRODUTO_REAL]) } };

/**
 * Rotas com corpo VÁLIDO: envelope na listagem (`/admin/products`) e
 * registro nas rotas de item (`/admin/products/`), inclusive publish e
 * archive. Serve aos testes cuja asserção é sobre verbo, URL e
 * cabeçalho — não sobre o formato do corpo.
 */
function rotasValidas() {
  return {
    'GET /admin/products': { corpo: lista([PRODUTO_REAL]) },
    /* POST na raiz do recurso é criação: devolve o registro criado. */
    'POST /admin/products': { corpo: PRODUTO_REAL },
    '/admin/products/': { corpo: PRODUTO_REAL },
  } as Record<string, { corpo: unknown }>;
}

/** Provedor HTTP puro, para afirmar verbo, caminho e cabeçalho. */
function criarProvedorHttp(
  rotas: Record<string, { status?: number; corpo?: unknown; erroDeRede?: boolean }> = {},
) {
  /* A rota do teste substitui a padrão do mesmo caminho — inclusive as
     variantes por método. Sem isso a padrão, mais específica, venceria e
     o teste nunca veria o corpo que pediu. */
  const caminho = (chave: string) => chave.trim().split(' ').pop();
  const doTeste = new Set(Object.keys(rotas).map(caminho));
  const padrao = Object.fromEntries(
    Object.entries(rotasValidas()).filter(([chave]) => !doTeste.has(caminho(chave))),
  );

  const falso = criarFetchFalso({ ...padrao, ...rotas });
  const http = new HttpAdminDataProvider({
    baseUrl: API_FALSA,
    fetchImpl: falso.fetch,
    chavePublicavel: CHAVE_FALSA,
    obterToken: async () => SESSAO_DE_TESTE.accessToken,
  });
  return { http, falso };
}

describe('verbos e caminhos', () => {
  it('listagem, item, criação, atualização, publicação e arquivamento', async () => {
    const { http, falso } = criarProvedorHttp();

    await http.list('products');
    await http.get('products', 'prd_1');
    await http.create('products', { nome: 'Novo' });
    await http.update('products', 'prd_1', { nome: 'Editado' });
    await http.publish('products', 'prd_1');
    await http.archive('products', 'prd_1');

    expect(falso.chamadas.map((c) => `${c.metodo} ${c.url.replace(API_FALSA, '')}`)).toEqual([
      'GET /admin/products',
      'GET /admin/products/prd_1',
      'POST /admin/products',
      'PATCH /admin/products/prd_1',
      'POST /admin/products/prd_1/publish',
      'POST /admin/products/prd_1/archive',
    ]);
  });

  it('toda escrita manda If-Unmodified-Since-Version com o atualizadoEm visto', async () => {
    const { http, falso } = criarProvedorHttp();
    const versao = '2026-09-13T15:30:00.123456+00:00';

    await http.update('products', 'x', { nome: 'a' }, { atualizadoEmEsperado: versao });
    await http.publish('products', 'x', { atualizadoEmEsperado: versao });
    await http.archive('products', 'y', { atualizadoEmEsperado: versao });

    for (const chamada of falso.chamadas) {
      expect(chamada.cabecalhos['If-Unmodified-Since-Version'], chamada.url).toBe(versao);
    }
  });

  it('sem versão conhecida, o header não é inventado', async () => {
    const { http, falso } = criarProvedorHttp();
    await http.update('products', 'x', { nome: 'a' });
    expect(falso.chamadas[0].cabecalhos['If-Unmodified-Since-Version']).toBeUndefined();
  });

  it('token no Authorization e publicável no apikey, em toda chamada', async () => {
    const { http, falso } = criarProvedorHttp();

    await http.list('products');
    await http.update('products', 'x', {});

    for (const chamada of falso.chamadas) {
      expect(chamada.cabecalhos.Authorization).toBe(`Bearer ${SESSAO_DE_TESTE.accessToken}`);
      expect(chamada.cabecalhos.apikey).toBe(CHAVE_FALSA);
      expect(chamada.url).not.toContain(SESSAO_DE_TESTE.accessToken);
      expect(chamada.url).not.toContain(CHAVE_FALSA);
    }
  });
});

describe('contrato das respostas reais', () => {
  /** Produto completo, menos o campo que o teste quer derrubar. */
  function produtoSem(campo: string) {
    const copia: Record<string, unknown> = { ...PRODUTO_REAL };
    delete copia[campo];
    return copia;
  }

  it('resposta válida é aceita, com os opcionais vindo do default do schema', async () => {
    const { http } = criarProvedorHttp({
      '/admin/products': {
        corpo: lista([
          {
            id: 'prd_minimo',
            codigo: 'so-o-essencial',
            nome: 'Só o essencial',
            tipo: 'mentoria',
            ativo: true,
            vende: false,
            atualizadoEm: '2026-09-13T15:30:00.000Z',
          },
        ]),
      },
    });

    const { itens } = await http.list('products');
    expect(itens).toHaveLength(1);
    /* Opcionais ganham o default declarado no schema… */
    expect(itens[0].vertical).toBeNull();
    expect(itens[0].descricao).toBeNull();
    expect(itens[0].pipelinesHubspot).toEqual([]);
    expect(itens[0].criadoEm).toBe('');
    /* …e o tipo desconhecido passa intacto, sem tradução. */
    expect(itens[0].tipo).toBe('mentoria');
    expect(itens[0].nome).toBe('Só o essencial');
  });

  it('registro sem id é recusado como contrato incompatível', async () => {
    const { http } = criarProvedorHttp({
      '/admin/products': { corpo: lista([produtoSem('id')]) },
    });

    await expect(http.list('products')).rejects.toSatisfy((e: unknown) => {
      if (!ehErroAdmin(e)) return false;
      expect(e.message).toMatch(/Contrato incompatível em GET \/admin\/products/);
      expect(e.detalhes).toContain('itens.0.id: esperado string, veio undefined');
      return true;
    });
  });

  it('registro sem atualizadoEm é recusado — a escrita perderia o controle de versão', async () => {
    const { http } = criarProvedorHttp({
      '/admin/products/': { corpo: produtoSem('atualizadoEm') },
    });

    await expect(http.get('products', 'prd_1')).rejects.toSatisfy((e: unknown) => {
      if (!ehErroAdmin(e)) return false;
      expect(e.message).toMatch(/Contrato incompatível em GET \/admin\/products\/prd_1/);
      expect(e.detalhes).toContain('atualizadoEm: esperado string, veio undefined');
      return true;
    });
  });

  it('nome ou ativo ausente não é preenchido em silêncio', async () => {
    const semNome = criarProvedorHttp({
      '/admin/products': { corpo: lista([produtoSem('nome')]) },
    });
    await expect(semNome.http.list('products')).rejects.toSatisfy(
      (e: unknown) => ehErroAdmin(e) && String(e.detalhes).includes('itens.0.nome'),
    );

    const semAtivo = criarProvedorHttp({
      '/admin/products': { corpo: lista([produtoSem('ativo')]) },
    });
    await expect(semAtivo.http.list('products')).rejects.toSatisfy(
      (e: unknown) => ehErroAdmin(e) && String(e.detalhes).includes('itens.0.ativo'),
    );
  });

  it('listagem sem itens é recusada no envelope', async () => {
    const { http } = criarProvedorHttp({
      '/admin/products': { corpo: { total: 27, pagina: 1, porPagina: 50 } },
    });

    await expect(http.list('products')).rejects.toSatisfy((e: unknown) => {
      if (!ehErroAdmin(e)) return false;
      expect(e.detalhes).toContain('itens: esperado array, veio undefined');
      return true;
    });
  });

  it('envelope sem total, pagina ou porPagina também é recusado', async () => {
    const { http } = criarProvedorHttp({
      '/admin/products': { corpo: { itens: [PRODUTO_REAL] } },
    });

    await expect(http.list('products')).rejects.toSatisfy((e: unknown) => {
      if (!ehErroAdmin(e)) return false;
      const d = String(e.detalhes);
      expect(d).toContain('total');
      expect(d).toContain('pagina');
      expect(d).toContain('porPagina');
      return true;
    });
  });

  it('o erro diz QUAL registro quebrou, sem revelar o conteúdo dele', async () => {
    const { http } = criarProvedorHttp({
      '/admin/products': {
        corpo: lista([PRODUTO_REAL, { ...PRODUTO_REAL, id: undefined, nome: 'Sigilo Absoluto' }]),
      },
    });

    await expect(http.list('products')).rejects.toSatisfy((e: unknown) => {
      if (!ehErroAdmin(e)) return false;
      const texto = e.message + ' ' + JSON.stringify(e.detalhes);
      /* Aponta o índice… */
      expect(texto).toContain('itens.1.id');
      /* …e não carrega o corpo da resposta. */
      expect(texto).not.toContain('Sigilo Absoluto');
      expect(texto).not.toContain('produto-real');
      return true;
    });
  });

  it('nada é escrito no console quando o contrato quebra', async () => {
    const escrito: string[] = [];
    const capturar = (...args: unknown[]) => escrito.push(args.map(String).join(' '));
    const espioes = (['log', 'info', 'warn', 'error', 'debug'] as const).map((nivel) =>
      vi.spyOn(console, nivel).mockImplementation(capturar),
    );

    try {
      const { http } = criarProvedorHttp({
        '/admin/products': {
          corpo: lista([{ ...PRODUTO_REAL, id: undefined, descricao: 'Conteúdo Sigiloso' }]),
        },
      });
      await expect(http.list('products')).rejects.toThrow(/Contrato incompatível/);
    } finally {
      espioes.forEach((e) => e.mockRestore());
    }

    expect(escrito.join('\n')).toBe('');
  });
});

describe('códigos de erro da API real', () => {
  it('401 devolve ao login com aviso de sessão expirada', async () => {
    const { porta } = renderizarHibrido({
      rota: '/catalogo',
      rotas: {
        ...ROTAS_CATALOGO,
        '/admin/products': {
          status: 401,
          corpo: { codigo: 'sem_permissao', mensagem: 'Sessão inválida ou expirada.' },
        },
      },
    });

    expect(await screen.findByText(/sua sessão expirou/i)).toBeVisible();
    await waitFor(() => expect(porta.chamadas.sair).toBeGreaterThanOrEqual(1));
  });

  it('403 mostra sem permissão, sem cair no mock', async () => {
    renderizarHibrido({
      rota: '/catalogo',
      rotas: {
        ...ROTAS_CATALOGO,
        '/admin/products': {
          status: 403,
          corpo: { codigo: 'sem_permissao', mensagem: 'Seu papel não acessa o catálogo.' },
        },
      },
    });

    expect(await screen.findByText('Sem permissão')).toBeVisible();
    expect(screen.getByText('Seu papel não acessa o catálogo.')).toBeVisible();
    expect(screen.queryByTestId('linha-prd_mind')).not.toBeInTheDocument();
  });

  it('404 no item mostra registro não encontrado', async () => {
    const inexistente = '0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f';
    renderizarHibrido({
      rota: `/catalogo/${inexistente}`,
      rotas: {
        ...ROTAS_CATALOGO,
        [`/admin/products/${inexistente}`]: {
          status: 404,
          corpo: { codigo: 'nao_encontrado', mensagem: 'Produto não existe.' },
        },
      },
    });

    expect(await screen.findByText('Registro não encontrado')).toBeVisible();
    expect(screen.getByText('Produto não existe.')).toBeVisible();
  });

  it('409 no salvamento abre o diálogo de conflito', async () => {
    const usuario = userEvent.setup();
    renderizarHibrido({
      rota: `/catalogo/${PRODUTO_REAL.id}`,
      rotas: {
        ...ROTAS_CATALOGO,
        [`GET /admin/products/${PRODUTO_REAL.id}`]: { corpo: PRODUTO_REAL },
        [`PATCH /admin/products/${PRODUTO_REAL.id}`]: {
          status: 409,
          corpo: {
            codigo: 'conflito',
            mensagem: 'O registro mudou desde que a tela carregou.',
          },
        },
      },
    });

    const nome = await screen.findByLabelText(/^Nome/);
    await waitFor(() => expect(nome).toHaveValue('Produto real'));
    await usuario.type(nome, ' editado');
    await usuario.click(screen.getByRole('button', { name: /^Salvar$/ }));

    expect(await screen.findByRole('heading', { name: /conflito de atualização/i })).toBeVisible();
    expect(screen.getByText(/apagaria a alteração da outra pessoa/i)).toBeVisible();
  });

  it('422 mostra o motivo da recusa e mantém o que foi editado', async () => {
    const usuario = userEvent.setup();
    renderizarHibrido({
      rota: `/catalogo/${PRODUTO_REAL.id}`,
      rotas: {
        ...ROTAS_CATALOGO,
        [`GET /admin/products/${PRODUTO_REAL.id}`]: { corpo: PRODUTO_REAL },
        [`PATCH /admin/products/${PRODUTO_REAL.id}`]: {
          status: 422,
          corpo: {
            codigo: 'validacao',
            mensagem: 'Nome já usado por outro produto.',
            detalhes: ['nome: precisa ser único'],
          },
        },
      },
    });

    const nome = await screen.findByLabelText(/^Nome/);
    await waitFor(() => expect(nome).toHaveValue('Produto real'));
    await usuario.clear(nome);
    await usuario.type(nome, 'Outro nome');
    await usuario.click(screen.getByRole('button', { name: /^Salvar$/ }));

    const aviso = await screen.findByTestId('erro-escrita');
    expect(aviso).toHaveTextContent('A API recusou estes dados');
    expect(aviso).toHaveTextContent('Nome já usado por outro produto.');
    expect(aviso).toHaveTextContent('nome: precisa ser único');
    /* O que a pessoa digitou continua no formulário. */
    expect(screen.getByLabelText(/^Nome/)).toHaveValue('Outro nome');
  });

  it('503 mostra serviço indisponível na listagem real', async () => {
    renderizarHibrido({
      rota: '/catalogo',
      rotas: {
        ...ROTAS_CATALOGO,
        '/admin/products': {
          status: 503,
          corpo: { codigo: 'indisponivel', mensagem: 'Em manutenção programada.' },
        },
      },
    });

    expect(await screen.findByText('Serviço indisponível')).toBeVisible();
    expect(screen.getByText('Em manutenção programada.')).toBeVisible();
  });

  it('o requestId da resposta aparece na tela de erro', async () => {
    renderizarHibrido({
      rota: '/catalogo',
      rotas: { ...ROTAS_CATALOGO, '/admin/products': { status: 503, corpo: { codigo: 'indisponivel' } } },
    });

    expect(await screen.findByText(/requisição req_teste_0001/)).toBeVisible();
  });

  it('o provedor HTTP traduz cada status no código do contrato', async () => {
    const casos: [number, string, string][] = [
      [401, 'sessao_expirada', 'sem_permissao'],
      [403, 'sem_permissao', 'sem_permissao'],
      [404, 'nao_encontrado', 'nao_encontrado'],
      [409, 'conflito', 'conflito'],
      [422, 'validacao', 'validacao'],
      [503, 'indisponivel', 'indisponivel'],
    ];

    for (const [status, esperado, codigoNoCorpo] of casos) {
      const { http } = criarProvedorHttp({
        'GET /admin/products': { status, corpo: { codigo: codigoNoCorpo, mensagem: 'x' } },
      });
      await expect(http.list('products'), `status ${status}`).rejects.toSatisfy(
        (e: unknown) => ehErroAdmin(e) && e.codigo === esperado,
      );
    }
  });
});
