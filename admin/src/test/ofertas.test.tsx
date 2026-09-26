import { describe, expect, it } from 'vitest';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ehErroAdmin, type CupomCatalogo, type OfertaCatalogo } from '@/contracts';
import { validarRegistro } from '@/services/validacao-api';
import { HybridAdminDataProvider } from '@/services/hybrid-admin-data-provider';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { CATALOGO_FALSO, contarLinhas, lista, renderizarHibrido, renderizarPainel } from './utils';

/* ============================================================
   OFERTAS E CUPONS — o schema `catalogo` no painel
   ============================================================
   Decisão da Adriana (26/09/2026): preço, oferta, order bump e cupom moram
   no schema `catalogo`, e "o painel é o controle deste schema". Quem monta
   a oferta e calcula a situação é o banco (`tests/ofertas_painel_contract.sql`);
   a porta é a `mindagent-catalogo` (`tests/mindagent_catalogo_ofertas.test.mjs`).
   Aqui: de onde a tela lê, o que ela mostra e que ela ainda não escreve. */

/* Como a `mindagent-catalogo` devolve uma oferta. Inventada. */
const OFERTA: OfertaCatalogo = {
  id: '6b0f7a1e-2c3d-4e5f-8a9b-0c1d2e3f4a5b',
  codigo: 'oferta-da-api',
  nome: 'Oferta vinda da API',
  tipo: 'periodo',
  situacao: 'no_ar',
  situacaoOrdem: 1,
  atualizadoEm: '2026-09-26T12:00:00+00:00',
  descricao: null,
  ativo: true,
  publico: true,
  historico: false,
  iniciaEm: '2026-09-20T03:00:00+00:00',
  encerraEm: '2026-10-01T02:59:00+00:00',
  meiosPagamento: ['cartao', 'pix', 'boleto'],
  noSite: true,
  verticais: ['institute'],
  produtos: ['produto-da-api'],
  precos: [
    {
      codigo: 'produto-da-api-condicao',
      produtoCodigo: 'produto-da-api',
      produtoNome: 'Produto da API',
      produtoVertical: 'institute',
      produtoCategoria: null,
      nome: null,
      descricao: null,
      valor: 1997,
      parcelas: 12,
      valorParcela: 167,
      valorRiscado: null,
      moeda: 'BRL',
      checkoutUrl: null,
      sistemaExterno: null,
      skuExterno: null,
      noSite: true,
      vigenteNoSite: true,
      eduzz: null,
    },
  ],
  bonus: [
    {
      produtoCodigo: 'produto-da-api',
      inclusoCodigo: 'evento-da-api',
      inclusoNome: 'Evento da API',
      nome: 'Ingresso do evento',
      descricao: 'Bônus da API.',
      valorReferencia: 1697,
      iniciaEm: null,
      encerraEm: '2026-10-01T02:59:00+00:00',
    },
  ],
  requer: [],
  origem: { tabela: 'tabela.antiga', id: 'x' },
  coluna_nova: 'ok',
};

const CUPOM: CupomCatalogo = {
  id: '7c1a2b3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
  codigo: 'CUPOMDAAPI',
  descricao: 'Cupom da API',
  tipo: 'percentual',
  valor: 15,
  aplicaEm: 'principais',
  ofertas: [],
  programas: [],
  produtos: ['produto-da-api'],
  valorMinimo: null,
  tetoDesconto: 300,
  usosMaximos: 20,
  usos: 5,
  usosPorEmail: 1,
  iniciaEm: null,
  encerraEm: null,
  ativo: true,
  sistema: 'checkout_proprio',
  historico: false,
  situacao: 'valendo',
  situacaoOrdem: 1,
  atualizadoEm: '2026-09-26T12:00:00+00:00',
  origem: null,
};

describe('ofertas — a tela em demonstração', () => {
  it('lista a semente com situação, tipo, preço e o selo "no site"', async () => {
    const { container } = renderizarPainel({ rota: '/ofertas' });
    expect(await screen.findByRole('heading', { name: 'Ofertas', level: 1 })).toBeVisible();
    await waitFor(() => expect(contarLinhas(container)).toBe(4));
    expect(screen.getByTestId('selo-origem-mock')).toBeVisible();
    expect(screen.getByTestId('aviso-virada')).toHaveTextContent('As ofertas do Institute entram aqui na virada');

    const balcao = screen.getByTestId('linha-of_balcao');
    expect(within(balcao).getByText('No ar')).toBeVisible();
    expect(within(balcao).getByText('Preço sem prazo')).toBeVisible();
    expect(within(balcao).getByText('no site')).toBeVisible();
    expect(within(balcao).getByText(/R\$\s?1\.200,00 · 12× de R\$\s?100,00/)).toBeVisible();

    expect(within(screen.getByTestId('linha-of_bump')).getByText('Order bump / upgrade')).toBeVisible();
    expect(within(screen.getByTestId('linha-of_lote')).getByText('Histórico')).toBeVisible();
  });

  it('o filtro de situação recorta a lista', async () => {
    const usuario = userEvent.setup();
    const { container } = renderizarPainel({ rota: '/ofertas' });
    await waitFor(() => expect(contarLinhas(container)).toBe(4));
    await usuario.click(screen.getByRole('combobox', { name: 'Situação' }));
    await usuario.click(await screen.findByRole('option', { name: 'Histórico' }));
    await waitFor(() => expect(contarLinhas(container)).toBe(1));
    expect(screen.getByTestId('linha-of_lote')).toBeVisible();
  });

  it('abrir uma oferta mostra preços, bônus, o que ela exige e de onde veio', async () => {
    renderizarPainel({ rota: '/ofertas/of_condicao' });
    const detalhe = await screen.findByRole('dialog', { name: 'Formação Exemplo — condição especial' });
    const precos = await within(detalhe).findByTestId('precos-da-oferta');
    expect(within(precos).getByText(/R\$\s?900,00 · 12× de R\$\s?75,00/)).toBeVisible();
    expect(within(within(detalhe).getByTestId('bonus-da-oferta')).getByText('Ingresso para o Evento Exemplo')).toBeVisible();
    expect(within(detalhe).getByText('Agendada')).toBeVisible();
    /* Nada de salvar: por enquanto é leitura. */
    expect(within(detalhe).queryByRole('button', { name: /salvar/i })).toBeNull();
  });

  it('o bump diz em que checkout aparece; o histórico mostra a Eduzz e de onde veio', async () => {
    const { unmount } = renderizarPainel({ rota: '/ofertas/of_bump' });
    const bump = await screen.findByRole('dialog', { name: 'Formação Exemplo no checkout de outra' });
    const exige = await within(bump).findByTestId('exigencias-da-oferta');
    expect(within(exige).getByText(/Aparece no checkout de/)).toBeVisible();
    expect(within(exige).getByText('Outra Formação')).toBeVisible();
    expect(within(bump).getByText(/de R\$\s?1\.200,00 \(riscado\)/)).toBeVisible();
    unmount();

    renderizarPainel({ rota: '/ofertas/of_lote' });
    const lote = await screen.findByRole('dialog', { name: 'Evento Exemplo — Lote 1' });
    expect(await within(lote).findByTestId('eduzz-mind-lote-1-exemplo')).toHaveTextContent(/preço de lista atual R\$\s?850,00/);
    expect(within(lote).getByTestId('origem-da-oferta')).toHaveTextContent('tabela.antiga');
    expect(within(lote).getByText('Histórico: só consulta.')).toBeVisible();
  });
});

describe('ofertas — a lista real', () => {
  it('vem da mindagent-catalogo, com filtro e ordem na query', async () => {
    const usuario = userEvent.setup();
    const { falso } = renderizarHibrido({
      rota: '/ofertas',
      rotas: { '/admin/offers': { corpo: lista([OFERTA]) } },
    });
    const linha = await screen.findByTestId(`linha-${OFERTA.id}`);
    expect(within(linha).getByText('Oferta vinda da API')).toBeVisible();
    expect(screen.getByTestId('selo-origem-real')).toBeVisible();
    const pedido = () => new URL(falso.ultima('/admin/offers')!.url);
    expect(pedido().href.startsWith(`${CATALOGO_FALSO}/admin/offers`)).toBe(true);

    await usuario.click(within(screen.getByRole('columnheader', { name: /^Situação/ })).getByRole('button'));
    await waitFor(() => expect(pedido().searchParams.get('ordenar')).toBe('situacaoOrdem'));

    await usuario.click(screen.getByRole('combobox', { name: 'Vertical' }));
    await usuario.click(await screen.findByRole('option', { name: 'Institute' }));
    await waitFor(() => expect(pedido().searchParams.get('verticais')).toBe('institute'));
  });

  it('abrir mostra a oferta da API, com as colunas do banco', async () => {
    renderizarHibrido({
      rota: `/ofertas/${OFERTA.id}`,
      rotas: {
        '/admin/offers': { corpo: lista([OFERTA]) },
        [`/admin/offers/${OFERTA.id}`]: { corpo: OFERTA },
      },
    });
    const detalhe = await screen.findByRole('dialog', { name: 'Oferta vinda da API' });
    const colunas = await within(detalhe).findByTestId('colunas-da-oferta');
    for (const coluna of ['codigo', 'situacao', 'meiosPagamento', 'coluna_nova']) {
      expect(within(colunas).getByText(coluna), coluna).toBeVisible();
    }
    expect(within(detalhe).getByText('Sim — o site lê esta oferta agora')).toBeVisible();
  });

  it('oferta sem situação é quebra de contrato; coluna nova passa', () => {
    const { situacao: _s, ...semSituacao } = OFERTA;
    expect(() => validarRegistro('offers', semSituacao)).toThrow(/Contrato incompatível/);
    const comNova = validarRegistro('offers', { ...OFERTA, outra_coluna: 1 });
    expect((comNova as Record<string, unknown>).outra_coluna).toBe(1);
  });
});

describe('cupons', () => {
  it('em demonstração, lista os cupons com o desconto e a situação', async () => {
    const { container } = renderizarPainel({ rota: '/cupons' });
    expect(await screen.findByRole('heading', { name: 'Cupons', level: 1 })).toBeVisible();
    await waitFor(() => expect(contarLinhas(container)).toBe(2));
    const valendo = screen.getByTestId('linha-cp_valendo');
    expect(within(valendo).getByText('10%')).toBeVisible();
    expect(within(valendo).getByText('Valendo')).toBeVisible();
    expect(within(valendo).getByText('4 de 50')).toBeVisible();
    const antigo = screen.getByTestId('linha-cp_antigo');
    expect(within(antigo).getByText(/R\$\s?200,00/)).toBeVisible();
    expect(within(antigo).getByText('Eduzz')).toBeVisible();
  });

  it('a lista real vem da mindagent-catalogo, e abrir mostra o cupom', async () => {
    renderizarHibrido({
      rota: `/cupons/${CUPOM.id}`,
      rotas: {
        '/admin/coupons': { corpo: lista([CUPOM]) },
        [`/admin/coupons/${CUPOM.id}`]: { corpo: CUPOM },
      },
    });
    const detalhe = await screen.findByRole('dialog', { name: 'CUPOMDAAPI' });
    const dados = await within(detalhe).findByTestId('dados-do-cupom');
    expect(within(dados).getByText('15%')).toBeVisible();
    expect(within(dados).getByText(/5 de 20 · até 1 por e-mail/)).toBeVisible();
    expect(within(dados).getByText('produto-da-api')).toBeVisible();
  });
});

describe('ofertas e cupons — só leitura por enquanto', () => {
  it('escrever é recusado antes de sair, real ou demonstração', async () => {
    const hibrido = new HybridAdminDataProvider(
      new MockAdminDataProvider({ latenciaMs: 0 }),
      new MockAdminDataProvider({ latenciaMs: 0 }),
    );
    for (const escrever of [
      () => hibrido.update('offers', OFERTA.id, { nome: 'x' }),
      () => hibrido.create('offers', {}),
      () => hibrido.publish('offers', OFERTA.id),
      () => hibrido.update('coupons', CUPOM.id, { descricao: 'x' }),
    ]) {
      await expect(escrever()).rejects.toSatisfy(
        (e: unknown) => ehErroAdmin(e) && /só leitura/.test(e.message),
      );
    }
    expect(hibrido.origemDoRecurso('offers')).toBe('http');
    expect(hibrido.origemDoRecurso('coupons')).toBe('http');
  });
});
