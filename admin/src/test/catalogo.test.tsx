import { describe, expect, it, vi } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { AdminApiError, codigoDoErro, type ProdutoCatalogo } from '@/contracts';
import {
  deCampoDataHora,
  paraCampoDataHora,
  paraFormularioProduto,
  payloadDaEdicaoProduto,
  rotuloTipoProduto,
} from '@/lib/catalogo';
import { validarRegistro } from '@/services/validacao-api';
import { HybridAdminDataProvider } from '@/services/hybrid-admin-data-provider';
import { HttpAdminDataProvider } from '@/services/http-admin-data-provider';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { enderecoDoCatalogo } from '@/services/provider-context';
import { produtosSemente } from '@/mocks/seed/catalogo';
import { CHAVE_FALSA, contarLinhas, criarFetchFalso, lista, renderizarHibrido, renderizarPainel } from './utils';

/* O produto como a `mindagent-catalogo` devolve. */
const DO_BANCO: ProdutoCatalogo = {
  id: '6f1c2d3e-4b5a-4c6d-8e9f-0a1b2c3d4e5f',
  criadoEm: '',
  atualizadoEm: '2026-09-13T15:30:00.123456+00:00',
  atualizadoPor: null,
  codigo: 'mind-summit-2026',
  nome: 'Mind Summit 2026',
  tipo: 'evento',
  vertical: 'summit',
  categoria: null,
  descricaoCurta: null,
  descricao: null,
  ativo: true,
  vende: false,
  vendeDe: null,
  vendeAte: '2026-09-18T02:59:59+00:00',
  comecaEm: '2026-09-16',
  encerraEm: '2026-09-17',
  periodo: null,
  schemaDados: 'summit_2026',
  pipelinesHubspot: [],
  datasDaTurma: null,
};

describe('catálogo — conversão entre banco e formulário', () => {
  it('mostra a janela de venda no horário de Brasília, com segundos', () => {
    expect(paraCampoDataHora('2026-09-18T02:59:59+00:00')).toBe('2026-09-17T23:59:59');
    expect(paraCampoDataHora(null)).toBe('');
    expect(paraCampoDataHora('não é data')).toBe('');
  });

  it('devolve o horário de Brasília ao banco com o fuso escrito', () => {
    expect(deCampoDataHora('2026-09-17T23:59:59')).toBe('2026-09-17T23:59:59-03:00');
    expect(deCampoDataHora('2026-09-17T23:59')).toBe('2026-09-17T23:59:00-03:00');
    expect(deCampoDataHora('')).toBeNull();
  });

  it('ida e volta preserva o instante', () => {
    const original = '2026-09-18T02:59:59+00:00';
    const volta = deCampoDataHora(paraCampoDataHora(original));
    expect(new Date(volta!).getTime()).toBe(new Date(original).getTime());
  });

  it('salvar manda só o que mudou — a janela com segundos não é regravada', () => {
    const valores = { ...paraFormularioProduto(DO_BANCO), nome: '  Mind Summit 2026 — edição  ' };
    expect(payloadDaEdicaoProduto(valores, DO_BANCO)).toEqual({ nome: 'Mind Summit 2026 — edição' });
  });

  it('a mesma hora escrita com milissegundos não conta como mudança', () => {
    const valores = { ...paraFormularioProduto(DO_BANCO), vendeAte: '2026-09-17T23:59:59.000' };
    expect(payloadDaEdicaoProduto(valores, DO_BANCO)).toEqual({});
  });

  it('texto vazio vira nulo e a lista de pipelines chega limpa', () => {
    const valores = {
      ...paraFormularioProduto({ ...DO_BANCO, descricaoCurta: 'antes' }),
      descricaoCurta: '   ',
      pipelinesHubspot: [' 123 ', '', '456'],
      vertical: '',
    };
    expect(payloadDaEdicaoProduto(valores, { ...DO_BANCO, descricaoCurta: 'antes' })).toEqual({
      descricaoCurta: null,
      pipelinesHubspot: ['123', '456'],
      vertical: null,
    });
  });

  it('produto com turma: as datas ficam fora do salvar, mesmo que o formulário mude', () => {
    const comTurma = { ...DO_BANCO, datasDaTurma: { programa: 'turma-x', inicioPrevisto: false } };
    const valores = { ...paraFormularioProduto(comTurma), comecaEm: '2030-01-01', nome: 'Outro nome' };
    expect(payloadDaEdicaoProduto(valores, comTurma)).toEqual({ nome: 'Outro nome' });
  });

  it('sem o registro de origem, manda o formulário inteiro', () => {
    const payload = payloadDaEdicaoProduto(paraFormularioProduto(DO_BANCO), undefined);
    expect(Object.keys(payload)).toHaveLength(14);
    expect(payload).not.toHaveProperty('codigo');
    expect(payload).not.toHaveProperty('schemaDados');
  });

  it('tipo que o painel não conhece aparece cru, sem tradução', () => {
    expect(rotuloTipoProduto('evento')).toEqual({ texto: 'Evento', conhecido: true });
    expect(rotuloTipoProduto('mesa_redonda')).toEqual({ texto: 'mesa_redonda', conhecido: false });
  });
});

describe('catálogo — endereço da API', () => {
  it('a variável explícita vence', () => {
    expect(enderecoDoCatalogo('https://outra.exemplo/fn/', 'https://proj.supabase.co')).toBe(
      'https://outra.exemplo/fn',
    );
  });

  it('sem ela, sai do projeto Supabase do login', () => {
    expect(enderecoDoCatalogo('', 'https://proj.supabase.co/')).toBe(
      'https://proj.supabase.co/functions/v1/mindagent-catalogo',
    );
  });

  it('sem nenhuma das duas, não inventa endereço', () => {
    expect(enderecoDoCatalogo('', '')).toBeNull();
    expect(enderecoDoCatalogo(undefined, undefined)).toBeNull();
  });
});

describe('catálogo — contrato da resposta', () => {
  it('aceita o registro do banco e preenche só o que é opcional', () => {
    const { pipelinesHubspot: _fora, ...semLista } = DO_BANCO;
    const lido = validarRegistro('products', semLista);
    expect(lido.pipelinesHubspot).toEqual([]);
    expect(lido.codigo).toBe('mind-summit-2026');
  });

  it('sem `ativo` é erro de contrato, não um produto inativo inventado', () => {
    const { ativo: _fora, ...semAtivo } = DO_BANCO;
    try {
      validarRegistro('products', semAtivo);
      throw new Error('devia ter recusado');
    } catch (erro) {
      expect(erro).toBeInstanceOf(AdminApiError);
      expect((erro as AdminApiError).message).toMatch(/Contrato incompatível/);
      expect((erro as AdminApiError).detalhes).toEqual(['ativo: esperado boolean, veio undefined']);
    }
  });
});

describe('catálogo — roteamento no modo híbrido', () => {
  function montar(comCatalogo: boolean) {
    const mock = new MockAdminDataProvider({ latenciaMs: 0 });
    const catalogo = new MockAdminDataProvider({ latenciaMs: 0 });
    catalogo.banco.products = [{ ...DO_BANCO, id: 'do-catalogo' }];
    const hibrido = new HybridAdminDataProvider(mock, comCatalogo ? catalogo : undefined);
    return { hibrido, catalogo, mock };
  }

  it('com a função do catálogo, os produtos vêm dela', async () => {
    const { hibrido } = montar(true);
    expect(hibrido.origemDoRecurso('products')).toBe('http');
    const r = await hibrido.list('products');
    expect(r.itens.map((p) => p.id)).toEqual(['do-catalogo']);
  });

  it('sem ela, ficam em memória e a tela diz demonstração', async () => {
    const { hibrido } = montar(false);
    expect(hibrido.origemDoRecurso('products')).toBe('mock');
    const r = await hibrido.list('products');
    expect(r.total).toBe(produtosSemente.length);
  });

  it('editar vai para a função do catálogo', async () => {
    const { hibrido, catalogo } = montar(true);
    await hibrido.update('products', 'do-catalogo', { nome: 'Novo nome' });
    expect(catalogo.banco.products[0].nome).toBe('Novo nome');
  });

  it('criar, publicar e arquivar são recusados antes de sair — real ou demonstração', async () => {
    for (const comCatalogo of [true, false]) {
      const { hibrido } = montar(comCatalogo);
      for (const operacao of [
        () => hibrido.create('products', { nome: 'x' }),
        () => hibrido.publish('products', 'do-catalogo'),
        () => hibrido.archive('products', 'do-catalogo'),
      ]) {
        const erro = await operacao().catch((e: unknown) => e);
        expect(codigoDoErro(erro)).toBe('validacao');
        expect((erro as Error).message).toMatch(/O catálogo aceita leitura e edição/);
      }
    }
  });
});

describe('catálogo — HTTP da mindagent-catalogo', () => {
  const BASE = 'https://api.exemplo.invalido/mindagent-catalogo';

  function provedor(rotas: Parameters<typeof criarFetchFalso>[0]) {
    const falso = criarFetchFalso(rotas);
    const http = new HttpAdminDataProvider({
      baseUrl: BASE,
      fetchImpl: falso.fetch,
      chavePublicavel: CHAVE_FALSA,
      obterToken: async () => 'token-de-teste',
    });
    return { http, falso };
  }

  it('lista em /admin/products com os filtros na query e valida o contrato', async () => {
    const { http, falso } = provedor({ '/admin/products': { corpo: lista([DO_BANCO]) } });
    const r = await http.list('products', { vertical: 'summit', ativo: 'true' });
    expect(r.itens[0].codigo).toBe('mind-summit-2026');
    const chamada = falso.ultima('/admin/products')!;
    expect(chamada.url).toContain(`${BASE}/admin/products?`);
    expect(chamada.url).toContain('vertical=summit');
    expect(chamada.cabecalhos.Authorization).toBe('Bearer token-de-teste');
    expect(chamada.url).not.toContain('token-de-teste');
  });

  it('edita com PATCH e manda a versão que a tela viu', async () => {
    const { http, falso } = provedor({
      [`PATCH /admin/products/${DO_BANCO.id}`]: { corpo: { ...DO_BANCO, nome: 'Novo' } },
    });
    const r = await http.update('products', DO_BANCO.id, { nome: 'Novo' }, {
      atualizadoEmEsperado: DO_BANCO.atualizadoEm,
    });
    expect(r.nome).toBe('Novo');
    const chamada = falso.ultima(`/admin/products/${DO_BANCO.id}`)!;
    expect(chamada.metodo).toBe('PATCH');
    expect(chamada.cabecalhos['If-Unmodified-Since-Version']).toBe(DO_BANCO.atualizadoEm);
  });

  it('409 da função vira conflito, e 422 traz a frase do banco', async () => {
    const { http } = provedor({
      [`PATCH /admin/products/${DO_BANCO.id}`]: {
        status: 409,
        corpo: { codigo: 'conflito', mensagem: 'O produto foi alterado por outra pessoa. Recarregue antes de salvar.' },
      },
    });
    const erro = await http.update('products', DO_BANCO.id, { nome: 'x' }).catch((e: unknown) => e);
    expect(codigoDoErro(erro)).toBe('conflito');

    const { http: outro } = provedor({
      [`PATCH /admin/products/${DO_BANCO.id}`]: {
        status: 422,
        corpo: { codigo: 'validacao', mensagem: 'O código do produto não se edita pelo painel.' },
      },
    });
    const recusa = await outro.update('products', DO_BANCO.id, { nome: 'x' }).catch((e: unknown) => e);
    expect(codigoDoErro(recusa)).toBe('validacao');
    expect((recusa as Error).message).toBe('O código do produto não se edita pelo painel.');
  });
});

describe('catálogo — a tela', () => {
  it('lista os produtos com o selo de demonstração', async () => {
    const { container } = renderizarPainel({ rota: '/catalogo' });
    expect(await screen.findByRole('heading', { name: 'Catálogo' })).toBeVisible();
    await waitFor(() => expect(contarLinhas(container)).toBe(produtosSemente.length));
    expect(screen.getByTestId('selo-origem-mock')).toBeVisible();
    expect(screen.getByText('mind-summit-2026')).toBeVisible();
  });

  it('abre o produto com o código travado e salva só o nome', async () => {
    const usuario = userEvent.setup();
    const { provedor } = renderizarPainel({ rota: '/catalogo/prd_summit_2026' });

    const nome = await screen.findByLabelText(/^Nome/);
    await waitFor(() => expect(nome).toHaveValue('Mind Summit 2026'));
    expect(screen.getByLabelText(/^Código/)).toBeDisabled();
    expect(screen.getByLabelText(/^Código/)).toHaveValue('mind-summit-2026');
    /* O jsdom, como alguns navegadores, acrescenta os milissegundos. */
    expect((screen.getByLabelText(/^Vende até/) as HTMLInputElement).value).toMatch(/^2026-09-17T23:59:59(\.000)?$/);

    await usuario.clear(nome);
    await usuario.type(nome, 'Mind Summit 2026 — São Paulo');
    await usuario.click(screen.getByRole('button', { name: /^Salvar$/ }));

    expect(await screen.findByText('Salvo')).toBeVisible();
    const salvo = provedor.banco.products.find((p) => p.id === 'prd_summit_2026')!;
    expect(salvo.nome).toBe('Mind Summit 2026 — São Paulo');
    /* O que ninguém tocou ficou exatamente como estava. */
    expect(salvo.vendeAte).toBe('2026-09-18T02:59:59+00:00');
    expect(salvo.codigo).toBe('mind-summit-2026');
  });

  it('no Institute, as datas vêm da turma: aparecem travadas e não vão no salvar', async () => {
    const usuario = userEvent.setup();
    const { provedor } = renderizarPainel({ rota: '/catalogo/prd_cert_lideranca_2027' });

    const aviso = await screen.findByTestId('datas-da-turma');
    expect(aviso).toHaveTextContent('certificacao-lideranca-positiva');
    expect(aviso).toHaveTextContent('O início ainda é previsão.');
    expect(screen.getByLabelText(/^Começa em/)).toBeDisabled();
    expect(screen.getByLabelText(/^Encerra em/)).toBeDisabled();
    expect(screen.getByLabelText(/^Começa em/)).toHaveValue('2027-01-28');

    const espiao = vi.spyOn(provedor, 'update');
    const curta = screen.getByLabelText(/^Descrição curta/);
    await usuario.clear(curta);
    await usuario.type(curta, 'Nova descrição');
    await usuario.click(screen.getByRole('button', { name: /^Salvar$/ }));
    await screen.findByText('Salvo');
    expect(espiao).toHaveBeenCalledWith(
      'products', 'prd_cert_lideranca_2027', { descricaoCurta: 'Nova descrição' }, expect.anything(),
    );
  });

  it('produto sem turma continua com as datas editáveis', async () => {
    renderizarPainel({ rota: '/catalogo/prd_summit_2026' });
    const comeca = await screen.findByLabelText(/^Começa em/);
    await waitFor(() => expect(comeca).toHaveValue('2026-09-16'));
    expect(comeca).toBeEnabled();
    expect(screen.queryByTestId('datas-da-turma')).toBeNull();
  });

  it('explica na tela a diferença entre ativo e vende', async () => {
    renderizarPainel({ rota: '/catalogo/prd_dash' });
    const explicacao = await screen.findByTestId('explicacao-ativo-vende');
    expect(explicacao).toHaveTextContent(/Ativo — O produto existe hoje no vocabulário do Mind/);
    expect(explicacao).toHaveTextContent(/Vende — Dá para comprar agora/);
    /* E junto de cada chave, na edição do produto. */
    const dialogo = await screen.findByRole('dialog');
    expect(within(dialogo).getByText(/fica guardado por causa do histórico de vendas e do NPS/)).toBeVisible();
    expect(within(dialogo).getByText(/"vendável agora" é ativo e vende/)).toBeVisible();
  });

  it('quem só visualiza vê o produto e não salva', async () => {
    renderizarPainel({ rota: '/catalogo/prd_dash', papel: 'analista' });
    const nome = await screen.findByLabelText(/^Nome/);
    await waitFor(() => expect(nome).toHaveValue('Mind Dash'));
    expect(nome).toBeDisabled();
    const rodape = screen.getByRole('button', { name: /^Salvar$/ });
    expect(rodape).toBeDisabled();
    expect(within(screen.getByRole('dialog')).getByText('mind-dash')).toBeVisible();
  });
});

/* Pedido da Adriana (26/09/2026): ordenar os produtos por qualquer coluna,
   em ordem crescente e decrescente. */
describe('catálogo — ordenar pelas colunas', () => {
  function nomesNaTela(container: HTMLElement) {
    return [...container.querySelectorAll('tbody tr')].map((tr) => tr.querySelector('td p')?.textContent);
  }
  const cabecalho = (nome: RegExp) => screen.getByRole('columnheader', { name: nome });

  it('um clique ordena crescente, o segundo decrescente, o terceiro volta à ordem padrão', async () => {
    const usuario = userEvent.setup();
    const { container } = renderizarPainel({ rota: '/catalogo' });
    await waitFor(() => expect(contarLinhas(container)).toBe(produtosSemente.length));
    const padrao = nomesNaTela(container);
    const crescente = [
      'Certificação Avançada em Liderança Positiva', 'Mind', 'Mind Dash', 'Mind Journey',
      'Mind Summit 2025', 'Mind Summit 2026',
    ];
    expect(cabecalho(/Produto/)).toHaveAttribute('aria-sort', 'none');

    await usuario.click(within(cabecalho(/Produto/)).getByRole('button'));
    await waitFor(() => expect(nomesNaTela(container)).toEqual(crescente));
    expect(cabecalho(/Produto/)).toHaveAttribute('aria-sort', 'ascending');

    await usuario.click(within(cabecalho(/Produto/)).getByRole('button'));
    await waitFor(() => expect(nomesNaTela(container)).toEqual([...crescente].reverse()));
    expect(cabecalho(/Produto/)).toHaveAttribute('aria-sort', 'descending');

    await usuario.click(within(cabecalho(/Produto/)).getByRole('button'));
    await waitFor(() => expect(nomesNaTela(container)).toEqual(padrao));
    expect(cabecalho(/Produto/)).toHaveAttribute('aria-sort', 'none');
  });

  it('toda coluna do catálogo ordena', async () => {
    const usuario = userEvent.setup();
    const { container } = renderizarPainel({ rota: '/catalogo' });
    await waitFor(() => expect(contarLinhas(container)).toBe(produtosSemente.length));
    for (const coluna of ['Produto', 'Vertical', 'Tipo', 'Situação', 'Venda', 'Janela de venda', 'Acontece']) {
      await usuario.click(within(cabecalho(new RegExp(`^${coluna}`))).getByRole('button'));
      await waitFor(() => expect(cabecalho(new RegExp(`^${coluna}`)), coluna).toHaveAttribute('aria-sort', 'ascending'));
    }
  });

  it('pelo teclado o ciclo continua: o foco fica no cabeçalho', async () => {
    const usuario = userEvent.setup();
    const { container } = renderizarPainel({ rota: '/catalogo' });
    await waitFor(() => expect(contarLinhas(container)).toBe(produtosSemente.length));

    within(cabecalho(/^Acontece/)).getByRole('button').focus();
    await usuario.keyboard('{Enter}');
    await waitFor(() => expect(cabecalho(/^Acontece/)).toHaveAttribute('aria-sort', 'ascending'));
    expect(document.activeElement).toBe(within(cabecalho(/^Acontece/)).getByRole('button'));
    await usuario.keyboard('{Enter}');
    await waitFor(() => expect(cabecalho(/^Acontece/)).toHaveAttribute('aria-sort', 'descending'));
  });

  it('abrir um produto e fechar mantém a ordem da lista', async () => {
    const usuario = userEvent.setup();
    const { container } = renderizarPainel({ rota: '/catalogo' });
    await waitFor(() => expect(contarLinhas(container)).toBe(produtosSemente.length));
    await usuario.click(within(cabecalho(/Produto/)).getByRole('button'));
    await usuario.click(within(cabecalho(/Produto/)).getByRole('button'));
    await waitFor(() => expect(cabecalho(/Produto/)).toHaveAttribute('aria-sort', 'descending'));
    const decrescente = nomesNaTela(container);

    await usuario.click(container.querySelector('tbody tr') as HTMLElement);
    const dialogo = await screen.findByRole('dialog');
    expect(nomesNaTela(container)).toEqual(decrescente);

    await usuario.click(within(dialogo).getByRole('button', { name: /^Fechar$/ }));
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull());
    expect(cabecalho(/Produto/)).toHaveAttribute('aria-sort', 'descending');
    expect(nomesNaTela(container)).toEqual(decrescente);
  });

  it('"Limpar" tira busca e filtros, e a ordem fica', async () => {
    const usuario = userEvent.setup();
    const { container } = renderizarPainel({ rota: '/catalogo?ordenar=-nome&ativo=true' });
    await waitFor(() => expect(contarLinhas(container)).toBeGreaterThan(0));
    expect(cabecalho(/Produto/)).toHaveAttribute('aria-sort', 'descending');

    await usuario.click(screen.getByRole('button', { name: /Limpar/ }));
    await waitFor(() => expect(contarLinhas(container)).toBe(produtosSemente.length));
    expect(cabecalho(/Produto/)).toHaveAttribute('aria-sort', 'descending');
  });

  it('a ordem vai para a função do catálogo e volta à página 1', async () => {
    const usuario = userEvent.setup();
    const { falso } = renderizarHibrido({
      rota: '/catalogo?pagina=2',
      rotas: { '/admin/products': { corpo: lista([DO_BANCO], { total: 120, pagina: 2, porPagina: 50 }) } },
    });
    await screen.findByTestId(`linha-${DO_BANCO.id}`);
    const pedido = () => new URL(falso.ultima('/admin/products')!.url).searchParams;
    expect(pedido().get('pagina')).toBe('2');

    await usuario.click(within(cabecalho(/^Acontece/)).getByRole('button'));
    await waitFor(() => expect(pedido().get('ordenar')).toBe('comecaEm'));
    expect(pedido().get('pagina')).toBe('1');

    await usuario.click(within(cabecalho(/^Acontece/)).getByRole('button'));
    await waitFor(() => expect(pedido().get('ordenar')).toBe('-comecaEm'));

    await usuario.click(within(cabecalho(/^Acontece/)).getByRole('button'));
    await waitFor(() => expect(pedido().has('ordenar')).toBe(false));
  });

  it('trocar um filtro também volta à página 1', async () => {
    const usuario = userEvent.setup();
    const { falso } = renderizarHibrido({
      rota: '/catalogo?pagina=2',
      rotas: { '/admin/products': { corpo: lista([DO_BANCO], { total: 120, pagina: 2, porPagina: 50 }) } },
    });
    await screen.findByTestId(`linha-${DO_BANCO.id}`);
    const pedido = () => new URL(falso.ultima('/admin/products')!.url).searchParams;

    await usuario.click(screen.getByRole('combobox', { name: 'Situação' }));
    await usuario.click(await screen.findByRole('option', { name: 'Ativos' }));
    await waitFor(() => expect(pedido().get('ativo')).toBe('true'));
    expect(pedido().get('pagina')).toBe('1');
  });
});
