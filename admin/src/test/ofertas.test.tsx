import { describe, expect, it } from 'vitest';
import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ehErroAdmin, type CupomCatalogo, type OfertaCatalogo } from '@/contracts';
import { validarRegistro } from '@/services/validacao-api';
import { HybridAdminDataProvider } from '@/services/hybrid-admin-data-provider';
import { MockAdminDataProvider } from '@/services/mock-admin-data-provider';
import { conferirParcelas, duplicarOferta, paraFormularioOferta, payloadDaOferta } from '@/lib/ofertas';
import { ofertasSemente } from '@/mocks/seed/ofertas';
import { CATALOGO_FALSO, contarLinhas, lista, renderizarHibrido, renderizarPainel } from './utils';

/* ============================================================
   OFERTAS E CUPONS — o schema `catalogo` no painel
   ============================================================
   Decisão da Adriana (26/09/2026): preço, oferta, order bump e cupom moram
   no schema `catalogo`, e "o painel é o controle deste schema". Quem monta
   a oferta, calcula a situação e aplica as regras é o banco
   (`tests/ofertas_painel_contract.sql`, `tests/ofertas_edicao_contract.sql`);
   a porta é a `mindagent-catalogo` (`tests/mindagent_catalogo_ofertas.test.mjs`).
   Aqui: o que a tela mostra, o que ela manda ao salvar, e que cupom ainda
   é só leitura. Passo 4 do plano: criar (nasce desligada), editar,
   duplicar, pôr no ar e tirar do ar. */

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
      ordem: 1,
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
      detalhe: null,
      nota: null,
      valor: 0,
      valorReferencia: 1697,
      iniciaEm: null,
      encerraEm: '2026-10-01T02:59:00+00:00',
      ordem: 1,
    },
  ],
  requer: [],
  origem: { tabela: 'tabela.antiga', id: 'x' },
  jaFoiAoAr: true,
  bloqueioPorNoAr: null,
  sobrepostas: [],
  alteracoes: [{ acao: 'atualizar', em: '2026-09-26T11:00:00+00:00', por: 'Ana', campos: ['precos', 'encerraEm'] }],
  coluna_nova: 'ok',
};

/* Um rascunho que nunca foi ao ar e que nada impede de ir (depois da virada). */
const RASCUNHO: OfertaCatalogo = {
  ...OFERTA,
  id: '8d2e3f4a-5b6c-4d7e-8f9a-0b1c2d3e4f5a',
  codigo: 'rascunho-da-api',
  nome: 'Rascunho vindo da API',
  situacao: 'desligada',
  situacaoOrdem: 5,
  ativo: false,
  noSite: false,
  jaFoiAoAr: false,
  origem: null,
  alteracoes: [],
  precos: [{ ...OFERTA.precos[0], codigo: 'rascunho-da-api', noSite: false, vigenteNoSite: false }],
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

/** O provedor em memória, com as escritas de oferta anotadas. */
function provedorEspiao() {
  const provedor = new MockAdminDataProvider({ latenciaMs: 0 });
  const escritas: { metodo: string; id?: string; payload?: unknown; versao?: string | null }[] = [];
  const update = provedor.update.bind(provedor);
  const create = provedor.create.bind(provedor);
  const publish = provedor.publish.bind(provedor);
  const archive = provedor.archive.bind(provedor);
  provedor.update = (async (r, id, payload, opcoes) => {
    escritas.push({ metodo: 'update', id, payload, versao: opcoes?.atualizadoEmEsperado });
    return update(r, id, payload, opcoes);
  }) as typeof provedor.update;
  provedor.create = (async (r, payload) => {
    escritas.push({ metodo: 'create', payload });
    return create(r, payload);
  }) as typeof provedor.create;
  provedor.publish = (async (r, id, opcoes) => {
    escritas.push({ metodo: 'publish', id, versao: opcoes?.atualizadoEmEsperado });
    return publish(r, id, opcoes);
  }) as typeof provedor.publish;
  provedor.archive = (async (r, id, opcoes) => {
    escritas.push({ metodo: 'archive', id, versao: opcoes?.atualizadoEmEsperado });
    return archive(r, id, opcoes);
  }) as typeof provedor.archive;
  return { provedor, escritas };
}

async function abrirOferta(nome: string) {
  return screen.findByRole('dialog', { name: nome });
}

describe('ofertas — a tela em demonstração', () => {
  it('lista a semente com situação, tipo, preço e o selo "no site"', async () => {
    const { container } = renderizarPainel({ rota: '/ofertas' });
    expect(await screen.findByRole('heading', { name: 'Ofertas', level: 1 })).toBeVisible();
    await waitFor(() => expect(contarLinhas(container)).toBe(5));
    expect(screen.getByTestId('selo-origem-mock')).toBeVisible();
    expect(screen.getByTestId('aviso-virada')).toHaveTextContent('As ofertas do Institute entram aqui na virada');
    expect(screen.getByRole('button', { name: 'Nova oferta' })).toBeVisible();

    const balcao = screen.getByTestId('linha-of_balcao');
    expect(within(balcao).getByText('No ar')).toBeVisible();
    expect(within(balcao).getByText('Preço sem prazo')).toBeVisible();
    expect(within(balcao).getByText('no site')).toBeVisible();
    expect(within(balcao).getByText(/R\$\s?1\.200,00 · 12× de R\$\s?100,00/)).toBeVisible();

    expect(within(screen.getByTestId('linha-of_bump')).getByText('Order bump / upgrade')).toBeVisible();
    expect(within(screen.getByTestId('linha-of_rascunho')).getByText('Desligada')).toBeVisible();
    expect(within(screen.getByTestId('linha-of_lote')).getByText('Histórico')).toBeVisible();
  });

  it('o filtro de situação recorta a lista', async () => {
    const usuario = userEvent.setup();
    const { container } = renderizarPainel({ rota: '/ofertas' });
    await waitFor(() => expect(contarLinhas(container)).toBe(5));
    await usuario.click(screen.getByRole('combobox', { name: 'Situação' }));
    await usuario.click(await screen.findByRole('option', { name: 'Histórico' }));
    await waitFor(() => expect(contarLinhas(container)).toBe(1));
    expect(screen.getByTestId('linha-of_lote')).toBeVisible();
  });

  it('abrir uma oferta traz o formulário com o que está no banco, e os códigos travados se já esteve no ar', async () => {
    renderizarPainel({ rota: '/ofertas/of_condicao' });
    const detalhe = await abrirOferta('Formação Exemplo — condição especial');
    const codigo = await within(detalhe).findByLabelText(/Código da oferta/);
    expect(codigo).toHaveValue('formacao-exemplo-condicao');
    expect(codigo).toHaveAttribute('readonly');
    const preco = within(detalhe).getByTestId('preco-0');
    expect(within(preco).getByLabelText('À vista (R$)')).toHaveValue('900');
    expect(within(preco).getByTestId('conta-parcelas-0')).toHaveTextContent(/12× de R\$\s?75,00 = R\$\s?900,00, igual ao à vista/);
    expect(within(preco).getByRole('button', { name: /Tirar/ })).toBeDisabled();
    expect(within(within(detalhe).getByTestId('bonus-0')).getByLabelText('Nome')).toHaveValue('Ingresso para o Evento Exemplo');
    expect(within(detalhe).getByRole('button', { name: 'Salvar' })).toBeVisible();
    expect(within(detalhe).getByRole('button', { name: /Tirar do ar/ })).toBeVisible();
  });

  it('o bump mostra em que checkout aparece, e o histórico importado é só consulta, com a Eduzz e de onde veio', async () => {
    const { unmount } = renderizarPainel({ rota: '/ofertas/of_bump' });
    const bump = await abrirOferta('Formação Exemplo no checkout de outra');
    const exige = await within(bump).findByTestId('exigencia-0');
    expect(within(exige).getByRole('combobox', { name: 'Produto exigido 1' })).toHaveTextContent('outra-formacao');
    expect(within(exige).getByRole('combobox', { name: 'Como' })).toHaveTextContent('No carrinho (order bump)');
    expect(within(within(bump).getByTestId('preco-0')).getByLabelText('Riscado — de (R$)')).toHaveValue('1200');
    unmount();

    renderizarPainel({ rota: '/ofertas/of_lote' });
    const lote = await abrirOferta('Evento Exemplo — Lote 1');
    expect(await within(lote).findByTestId('eduzz-mind-lote-1-exemplo')).toHaveTextContent(/preço de lista atual R\$\s?850,00/);
    expect(within(lote).getByTestId('origem-da-oferta')).toHaveTextContent('tabela.antiga');
    expect(within(lote).getByText('Histórico: só consulta.')).toBeVisible();
    expect(within(lote).queryByRole('button', { name: /salvar/i })).toBeNull();
    expect(within(lote).getByRole('button', { name: /Duplicar/ })).toBeVisible();
  });
});

describe('ofertas — editar no painel', () => {
  it('nova oferta nasce desligada, como rascunho, e abre para editar com o motivo de não poder ir ao ar', async () => {
    const usuario = userEvent.setup();
    const { provedor, escritas } = provedorEspiao();
    renderizarPainel({ rota: '/ofertas', provedor });
    await usuario.click(await screen.findByRole('button', { name: 'Nova oferta' }));
    const nova = await abrirOferta('Nova oferta');

    await usuario.type(within(nova).getByLabelText(/Código da oferta/), 'journey-condicao-teste');
    await usuario.type(within(nova).getByLabelText(/^Nome\*$/), 'Journey — condição de teste');
    await usuario.click(within(nova).getByRole('combobox', { name: /Tipo/ }));
    await usuario.click(await screen.findByRole('option', { name: 'Condição com prazo' }));
    await usuario.click(within(nova).getByRole('button', { name: /Adicionar preço/ }));
    const preco = within(nova).getByTestId('preco-0');
    await usuario.click(within(preco).getByRole('combobox', { name: 'Produto do preço 1' }));
    await usuario.click(await screen.findByRole('option', { name: /Mind Journey/ }));
    await usuario.type(within(preco).getByLabelText(/Código vendável/), 'journey-condicao-teste');
    await usuario.type(within(preco).getByLabelText('À vista (R$)'), '1997');
    await usuario.type(within(preco).getByLabelText('Parcelas'), '12');
    await usuario.type(within(preco).getByLabelText('Valor da parcela (R$)'), '167');
    expect(within(preco).getByTestId('conta-parcelas-0')).toHaveTextContent(/R\$\s?7,00 acima do à vista/);
    await usuario.click(within(nova).getByRole('button', { name: /Criar rascunho/ }));

    const criada = await abrirOferta('Journey — condição de teste');
    expect(escritas.map((e) => e.metodo)).toEqual(['create']);
    expect(escritas[0].payload).toMatchObject({
      codigo: 'journey-condicao-teste',
      tipo: 'periodo',
      precos: [{ produtoCodigo: 'mind-journey-2027', codigo: 'journey-condicao-teste', valor: 1997, parcelas: 12, valorParcela: 167 }],
    });
    expect(provedor.banco.offers[0]).toMatchObject({ codigo: 'journey-condicao-teste', ativo: false, situacao: 'desligada' });
    expect(await within(criada).findByTestId('bloqueio-por-no-ar')).toHaveTextContent('o Institute passa a ler na virada');
    expect(within(criada).getByRole('button', { name: /Pôr no ar/ })).toBeDisabled();
    expect(within(criada).getByTestId('historico-alteracoes')).toHaveTextContent('Criou');
  });

  it('o formulário diz o que falta antes de enviar', async () => {
    const usuario = userEvent.setup();
    const { provedor, escritas } = provedorEspiao();
    renderizarPainel({ rota: '/ofertas/nova', provedor });
    const nova = await abrirOferta('Nova oferta');
    await usuario.type(within(nova).getByLabelText(/^Nome\*$/), 'Sem código');
    await usuario.type(within(nova).getByLabelText(/Código da oferta/), 'Com Espaço');
    await usuario.click(within(nova).getByRole('button', { name: /Criar rascunho/ }));
    expect(await within(nova).findByText('Só letras minúsculas, números e hífen.')).toBeVisible();
    expect(within(nova).getByText('Escolha o tipo da oferta.')).toBeVisible();
    expect(escritas).toEqual([]);
  });

  it('salvar um rascunho manda só o que mudou, com a versão que a tela viu', async () => {
    const usuario = userEvent.setup();
    const { provedor, escritas } = provedorEspiao();
    renderizarPainel({ rota: '/ofertas/of_rascunho', provedor });
    const rascunho = await abrirOferta('Formação Exemplo — próxima condição');
    const nome = await within(rascunho).findByLabelText(/^Nome\*$/);
    await usuario.clear(nome);
    await usuario.type(nome, 'Formação Exemplo — condição de novembro');
    await usuario.click(within(rascunho).getByRole('button', { name: 'Salvar' }));

    await screen.findByRole('dialog', { name: 'Formação Exemplo — condição de novembro' });
    expect(escritas).toEqual([
      { metodo: 'update', id: 'of_rascunho', payload: { nome: 'Formação Exemplo — condição de novembro' }, versao: '2026-09-20T12:00:00+00:00' },
    ]);
    expect(await screen.findByTestId('oferta-salva')).toBeVisible();
    expect(screen.getByTestId('historico-alteracoes')).toHaveTextContent('Editou nome');
  });

  it('oferta ligada: salvar pede confirmação com o preço antes e depois, e só então grava', async () => {
    const usuario = userEvent.setup();
    const { provedor, escritas } = provedorEspiao();
    renderizarPainel({ rota: '/ofertas/of_balcao', provedor });
    const balcao = await abrirOferta('Formação Exemplo');
    const preco = await within(balcao).findByTestId('preco-0');
    await usuario.clear(within(preco).getByLabelText('À vista (R$)'));
    await usuario.type(within(preco).getByLabelText('À vista (R$)'), '1300');
    await usuario.clear(within(preco).getByLabelText('Valor da parcela (R$)'));
    await usuario.type(within(preco).getByLabelText('Valor da parcela (R$)'), '109');
    await usuario.click(within(balcao).getByRole('button', { name: 'Salvar' }));

    const confirmacao = await screen.findByRole('dialog', { name: 'Salvar oferta que está ligada?' });
    expect(within(confirmacao).getByTestId('mudancas-de-preco')).toHaveTextContent(
      /R\$\s?1\.200,00 · 12× de R\$\s?100,00 → R\$\s?1\.300,00 · 12× de R\$\s?109,00/,
    );
    expect(within(confirmacao).getByText(/passam a mostrar o que você mudou em até 1 minuto/)).toBeVisible();
    expect(escritas).toEqual([]);

    await usuario.click(within(confirmacao).getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(escritas.map((e) => e.metodo)).toEqual(['update']));
    expect(Object.keys(escritas[0].payload as object)).toEqual(['precos']);
    await waitFor(() => expect(provedor.banco.offers.find((o) => o.id === 'of_balcao')?.precos[0].valor).toBe(1300));
  });

  it('se outra pessoa salvou antes, abre o aviso de conflito', async () => {
    const usuario = userEvent.setup();
    const { provedor } = provedorEspiao();
    renderizarPainel({ rota: '/ofertas/of_rascunho', provedor });
    const rascunho = await abrirOferta('Formação Exemplo — próxima condição');
    const nome = await within(rascunho).findByLabelText(/^Nome\*$/);
    /* Outra aba salvou enquanto esta estava aberta. */
    provedor.banco.offers.find((o) => o.id === 'of_rascunho')!.atualizadoEm = '2026-09-26T20:00:00+00:00';
    await usuario.type(nome, ' (revisada)');
    await usuario.click(within(rascunho).getByRole('button', { name: 'Salvar' }));
    expect(await screen.findByRole('dialog', { name: 'Conflito de atualização' })).toBeVisible();
  });

  it('pôr no ar: travado com o motivo antes da virada; depois, confirma e liga', async () => {
    const usuario = userEvent.setup();
    const antes = provedorEspiao();
    const { unmount } = renderizarPainel({ rota: '/ofertas/of_rascunho', provedor: antes.provedor });
    const travada = await abrirOferta('Formação Exemplo — próxima condição');
    expect(await within(travada).findByTestId('bloqueio-por-no-ar')).toHaveTextContent('Nenhum site lê ainda');
    expect(within(travada).getByRole('button', { name: /Pôr no ar/ })).toBeDisabled();
    unmount();

    const depois = provedorEspiao();
    depois.provedor.ligarLeitorDoCatalogo(true);
    renderizarPainel({ rota: '/ofertas/of_rascunho', provedor: depois.provedor });
    const liberada = await abrirOferta('Formação Exemplo — próxima condição');
    await waitFor(() => expect(within(liberada).getByRole('button', { name: /Pôr no ar/ })).toBeEnabled());
    expect(within(liberada).queryByTestId('bloqueio-por-no-ar')).toBeNull();
    await usuario.click(within(liberada).getByRole('button', { name: /Pôr no ar/ }));
    const confirmacao = await screen.findByRole('dialog', { name: 'Pôr esta oferta no ar?' });
    expect(confirmacao).toHaveTextContent(/R\$\s?700,00 · 10× de R\$\s?70,00/);
    expect(confirmacao).toHaveTextContent('troque também lá');
    await usuario.click(within(confirmacao).getByRole('button', { name: 'Pôr no ar' }));

    await waitFor(() => expect(depois.escritas.map((e) => e.metodo)).toEqual(['publish']));
    expect(depois.escritas[0].versao).toBe('2026-09-20T12:00:00+00:00');
    expect(await within(liberada).findByRole('button', { name: /Tirar do ar/ })).toBeVisible();
    expect(within(liberada).getByTestId('historico-alteracoes')).toHaveTextContent('Pôs no ar');
    expect(depois.provedor.banco.offers.find((o) => o.id === 'of_rascunho')).toMatchObject({ ativo: true, situacao: 'agendada', jaFoiAoAr: true });
  });

  it('tirar do ar pede confirmação e não apaga nada', async () => {
    const usuario = userEvent.setup();
    const { provedor, escritas } = provedorEspiao();
    renderizarPainel({ rota: '/ofertas/of_bump', provedor });
    const bump = await abrirOferta('Formação Exemplo no checkout de outra');
    await usuario.click(await within(bump).findByRole('button', { name: /Tirar do ar/ }));
    const confirmacao = await screen.findByRole('dialog', { name: 'Tirar esta oferta do ar?' });
    expect(confirmacao).toHaveTextContent('Nada é apagado');
    await usuario.click(within(confirmacao).getByRole('button', { name: 'Tirar do ar' }));
    await waitFor(() => expect(escritas.map((e) => e.metodo)).toEqual(['archive']));
    expect(await within(bump).findByRole('button', { name: /Pôr no ar/ })).toBeVisible();
    expect(provedor.banco.offers.find((o) => o.id === 'of_bump')).toMatchObject({ ativo: false, situacao: 'desligada' });
  });

  it('duplicar copia preços, bônus e exigências; prazo e códigos ficam em branco', async () => {
    const usuario = userEvent.setup();
    renderizarPainel({ rota: '/ofertas/of_lote' });
    const lote = await abrirOferta('Evento Exemplo — Lote 1');
    await usuario.click(within(lote).getByRole('button', { name: /Duplicar/ }));
    const copia = await abrirOferta('Duplicar Evento Exemplo — Lote 1');
    expect(await within(copia).findByTestId('aviso-duplicar')).toHaveTextContent('evento-exemplo-lote-1');
    expect(within(copia).getByLabelText(/Código da oferta/)).toHaveValue('');
    expect(within(copia).getByLabelText(/^Nome\*$/)).toHaveValue('Cópia de Evento Exemplo — Lote 1');
    expect(within(copia).getByLabelText(/Começa em/)).toHaveValue('');
    for (const i of [0, 1]) {
      const preco = within(copia).getByTestId(`preco-${i}`);
      expect(within(preco).getByLabelText(/Código vendável/)).toHaveValue('');
    }
    expect(within(within(copia).getByTestId('preco-1')).getByLabelText('À vista (R$)')).toHaveValue('1500');
  });

  it('as datas do formulário ficam no horário de Brasília e vão ao banco com o fuso', async () => {
    const usuario = userEvent.setup();
    const { provedor, escritas } = provedorEspiao();
    renderizarPainel({ rota: '/ofertas/of_rascunho', provedor });
    const rascunho = await abrirOferta('Formação Exemplo — próxima condição');
    const fim = await within(rascunho).findByLabelText(/Termina em/);
    /* O campo mostra sem os segundos quando eles são zero; o instante é o mesmo. */
    expect(fim).toHaveValue('2030-02-27T23:59');
    fireEvent.change(fim, { target: { value: '2030-03-31T23:59:59' } });
    await usuario.click(within(rascunho).getByRole('button', { name: 'Salvar' }));
    await waitFor(() => expect(escritas).toHaveLength(1));
    /* O campo pode devolver os milissegundos; o instante e o fuso de Brasília são o que importa. */
    expect(escritas[0].payload).toEqual({ encerraEm: expect.stringMatching(/^2030-03-31T23:59:59(\.000)?-03:00$/) });
  });
});

describe('ofertas — regras da tela, sozinhas', () => {
  const [balcao, condicao, bump, , lote] = ofertasSemente;

  it('a conta das parcelas diz quando fecha com o à vista', () => {
    expect(conferirParcelas('5997', '12', '500')).toEqual({ texto: expect.stringMatching(/R\$\s?3,00 acima do à vista/), fecha: true });
    expect(conferirParcelas('1997', '12', '180')?.fecha).toBe(false);
    expect(conferirParcelas('1997', '12', '166')?.texto).toMatch(/abaixo do à vista/);
    expect(conferirParcelas('', '12', '100')).toBeNull();
  });

  it('sem mudança, nada vai; mudar para preço sem prazo leva a janela junto', () => {
    expect(payloadDaOferta(paraFormularioOferta(bump), bump)).toEqual({});
    const semPrazo = { ...paraFormularioOferta(condicao), tipo: 'base', iniciaEm: '', encerraEm: '' };
    expect(payloadDaOferta(semPrazo, condicao)).toEqual({ tipo: 'base', iniciaEm: null, encerraEm: null });
  });

  it('criar manda tudo, com número como número e texto vazio como nulo', () => {
    const payload = payloadDaOferta(paraFormularioOferta(balcao));
    expect(payload).toMatchObject({
      codigo: 'formacao-exemplo-balcao',
      descricao: null,
      iniciaEm: null,
      precos: [{ produtoCodigo: 'formacao-exemplo', valor: 1200, parcelas: 12, valorParcela: 100, valorRiscado: null, checkoutUrl: null, ordem: 1 }],
    });
  });

  it('duplicar não leva código nem prazo', () => {
    const copia = duplicarOferta(lote);
    expect(copia.codigo).toBe('');
    expect(copia.iniciaEm).toBe('');
    expect(copia.encerraEm).toBe('');
    expect(copia.precos.map((p) => p.codigo)).toEqual(['', '']);
    expect(copia.precos.map((p) => p.produtoCodigo)).toEqual(['evento-exemplo-mind', 'evento-exemplo-vip']);
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

  it('abrir mostra a oferta da API, com o histórico de alterações e as colunas do banco', async () => {
    const usuario = userEvent.setup();
    renderizarHibrido({
      rota: `/ofertas/${OFERTA.id}`,
      rotas: {
        '/admin/offers': { corpo: lista([OFERTA]) },
        [`/admin/offers/${OFERTA.id}`]: { corpo: OFERTA },
      },
    });
    const detalhe = await abrirOferta('Oferta vinda da API');
    expect(await within(detalhe).findByTestId('historico-alteracoes')).toHaveTextContent(/Editou preços e fim.*Ana/);
    await usuario.click(within(detalhe).getByText('Como está no banco'));
    const colunas = within(detalhe).getByTestId('colunas-da-oferta');
    for (const coluna of ['codigo', 'situacao', 'meiosPagamento', 'coluna_nova']) {
      expect(within(colunas).getByText(coluna), coluna).toBeVisible();
    }
    expect(within(detalhe).getByText('Sim — o site lê esta oferta agora')).toBeVisible();
  });

  it('salvar vai como PATCH só com o que mudou, e a recusa do banco aparece com a frase dele', async () => {
    const usuario = userEvent.setup();
    const { falso } = renderizarHibrido({
      rota: `/ofertas/${RASCUNHO.id}`,
      rotas: {
        '/admin/offers': { corpo: lista([RASCUNHO]) },
        [`GET /admin/offers/${RASCUNHO.id}`]: { corpo: RASCUNHO },
        [`PATCH /admin/offers/${RASCUNHO.id}`]: {
          status: 422,
          corpo: { codigo: 'validacao', mensagem: 'As parcelas não fecham com o preço à vista.' },
        },
      },
    });
    const rascunho = await abrirOferta('Rascunho vindo da API');
    const preco = await within(rascunho).findByTestId('preco-0');
    await usuario.clear(within(preco).getByLabelText('Valor da parcela (R$)'));
    await usuario.type(within(preco).getByLabelText('Valor da parcela (R$)'), '160');
    await usuario.click(within(rascunho).getByRole('button', { name: 'Salvar' }));

    expect(await within(rascunho).findByTestId('erro-escrita')).toHaveTextContent('As parcelas não fecham com o preço à vista.');
    const chamada = falso.ultima(`/admin/offers/${RASCUNHO.id}`)!;
    expect(chamada.metodo).toBe('PATCH');
    expect(chamada.cabecalhos['If-Unmodified-Since-Version']).toBe(RASCUNHO.atualizadoEm);
    expect(Object.keys(chamada.corpo as object)).toEqual(['precos']);
    expect((chamada.corpo as { precos: { valorParcela: number }[] }).precos[0].valorParcela).toBe(160);
  });

  it('pôr no ar vai como POST em /publish, com a versão', async () => {
    const usuario = userEvent.setup();
    const { falso } = renderizarHibrido({
      rota: `/ofertas/${RASCUNHO.id}`,
      rotas: {
        '/admin/offers': { corpo: lista([RASCUNHO]) },
        [`GET /admin/offers/${RASCUNHO.id}`]: { corpo: RASCUNHO },
        [`POST /admin/offers/${RASCUNHO.id}/publish`]: { corpo: { ...RASCUNHO, ativo: true, situacao: 'no_ar', jaFoiAoAr: true } },
      },
    });
    const rascunho = await abrirOferta('Rascunho vindo da API');
    await usuario.click(await within(rascunho).findByRole('button', { name: /Pôr no ar/ }));
    await usuario.click(within(await screen.findByRole('dialog', { name: 'Pôr esta oferta no ar?' })).getByRole('button', { name: 'Pôr no ar' }));
    await waitFor(() => expect(falso.ultima('/publish')?.metodo).toBe('POST'));
    expect(falso.ultima('/publish')!.cabecalhos['If-Unmodified-Since-Version']).toBe(RASCUNHO.atualizadoEm);
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

  it('cupom ainda é só leitura: escrever é recusado antes de sair; oferta passa', async () => {
    const real = new MockAdminDataProvider({ latenciaMs: 0 });
    const hibrido = new HybridAdminDataProvider(new MockAdminDataProvider({ latenciaMs: 0 }), real);
    for (const escrever of [
      () => hibrido.update('coupons', CUPOM.id, { descricao: 'x' }),
      () => hibrido.create('coupons', {}),
      () => hibrido.archive('coupons', CUPOM.id),
    ]) {
      await expect(escrever()).rejects.toSatisfy((e: unknown) => ehErroAdmin(e) && /só leitura/.test(e.message));
    }
    /* A oferta chega à função real (aqui, o banco em memória no lugar dela). */
    const arquivada = await hibrido.archive('offers', 'of_bump');
    expect(arquivada.ativo).toBe(false);
    expect(hibrido.origemDoRecurso('offers')).toBe('http');
    expect(hibrido.origemDoRecurso('coupons')).toBe('http');
  });
});
