import type { CupomCatalogo, OfertaCatalogo, PrecoOferta } from '@/contracts';

/* ============================================================
   OFERTAS E CUPONS — semente de demonstração
   ============================================================
   Valores inventados, no formato que a `mindagent-catalogo` devolve, para
   os testes e o preview de cada versão (montado sem as variáveis do
   Supabase). Em produção as ofertas e os cupons vêm do schema `catalogo`. */

function preco(p: Partial<PrecoOferta> & Pick<PrecoOferta, 'codigo' | 'produtoCodigo'>): PrecoOferta {
  return {
    produtoNome: null,
    produtoVertical: null,
    produtoCategoria: null,
    nome: null,
    descricao: null,
    valor: null,
    parcelas: null,
    valorParcela: null,
    valorRiscado: null,
    moeda: 'BRL',
    checkoutUrl: null,
    sistemaExterno: null,
    skuExterno: null,
    noSite: false,
    vigenteNoSite: false,
    eduzz: null,
    ...p,
  };
}

function oferta(o: Partial<OfertaCatalogo> & Pick<OfertaCatalogo, 'id' | 'codigo' | 'nome' | 'tipo' | 'situacao'>): OfertaCatalogo {
  return {
    atualizadoEm: '2026-09-20T12:00:00+00:00',
    descricao: null,
    ativo: true,
    publico: true,
    historico: false,
    iniciaEm: null,
    encerraEm: null,
    meiosPagamento: ['cartao', 'pix'],
    situacaoOrdem: 1,
    noSite: false,
    verticais: [],
    produtos: [],
    precos: [],
    bonus: [],
    requer: [],
    origem: null,
    ...o,
  };
}

export const ofertasSemente: OfertaCatalogo[] = [
  oferta({
    id: 'of_balcao',
    codigo: 'formacao-exemplo-balcao',
    nome: 'Formação Exemplo',
    tipo: 'base',
    situacao: 'no_ar',
    situacaoOrdem: 1,
    noSite: true,
    verticais: ['institute'],
    produtos: ['formacao-exemplo'],
    precos: [
      preco({
        codigo: 'formacao-exemplo-balcao',
        produtoCodigo: 'formacao-exemplo',
        produtoNome: 'Formação Exemplo',
        produtoVertical: 'institute',
        valor: 1200,
        parcelas: 12,
        valorParcela: 100,
        noSite: true,
        vigenteNoSite: true,
      }),
    ],
  }),
  oferta({
    id: 'of_condicao',
    codigo: 'formacao-exemplo-condicao',
    nome: 'Formação Exemplo — condição especial',
    tipo: 'periodo',
    situacao: 'agendada',
    situacaoOrdem: 3,
    iniciaEm: '2030-01-01T03:00:00+00:00',
    encerraEm: '2030-01-31T02:59:00+00:00',
    verticais: ['institute'],
    produtos: ['formacao-exemplo'],
    precos: [
      preco({
        codigo: 'formacao-exemplo-condicao',
        produtoCodigo: 'formacao-exemplo',
        produtoNome: 'Formação Exemplo',
        produtoVertical: 'institute',
        valor: 900,
        parcelas: 12,
        valorParcela: 75,
      }),
    ],
    bonus: [
      {
        produtoCodigo: 'formacao-exemplo',
        inclusoCodigo: 'evento-exemplo',
        inclusoNome: 'Evento Exemplo',
        nome: 'Ingresso para o Evento Exemplo',
        descricao: 'Bônus inventado.',
        valorReferencia: 500,
        iniciaEm: null,
        encerraEm: '2030-01-31T02:59:00+00:00',
      },
    ],
  }),
  oferta({
    id: 'of_bump',
    codigo: 'bump-exemplo',
    nome: 'Formação Exemplo no checkout de outra',
    tipo: 'condicional',
    situacao: 'no_ar',
    situacaoOrdem: 1,
    verticais: ['institute'],
    produtos: ['formacao-exemplo'],
    precos: [
      preco({
        codigo: 'bump-exemplo',
        produtoCodigo: 'formacao-exemplo',
        produtoNome: 'Formação Exemplo',
        produtoVertical: 'institute',
        valor: 600,
        valorRiscado: 1200,
      }),
    ],
    requer: [
      {
        produtoCodigo: 'outra-formacao',
        produtoNome: 'Outra Formação',
        modo: 'carrinho',
        prioridade: 100,
        grupoExclusivo: 'formacao',
        ativo: true,
      },
    ],
  }),
  oferta({
    id: 'of_lote',
    codigo: 'evento-exemplo-lote-1',
    nome: 'Evento Exemplo — Lote 1',
    tipo: 'periodo',
    situacao: 'historico',
    situacaoOrdem: 6,
    ativo: false,
    publico: false,
    historico: true,
    iniciaEm: '2026-06-01T03:00:00+00:00',
    encerraEm: '2026-06-30T02:59:00+00:00',
    meiosPagamento: [],
    verticais: ['summit'],
    produtos: ['evento-exemplo-mind', 'evento-exemplo-vip'],
    origem: { tabela: 'tabela.antiga', id: 'lote-1', confianca: 'copia_viva' },
    precos: [
      preco({
        codigo: 'mind-lote-1-exemplo',
        produtoCodigo: 'evento-exemplo-mind',
        produtoNome: 'Evento Exemplo — Mind',
        produtoVertical: 'summit',
        produtoCategoria: 'mind',
        nome: 'Experiência Mind — Lote 1',
        valor: 800,
        checkoutUrl: 'https://checkout.exemplo.invalido/mind-1',
        sistemaExterno: 'eduzz',
        skuExterno: '000001',
        eduzz: { preco: 850, lidoEm: '2026-09-24T21:02:00+00:00', arquivado: false },
      }),
      preco({
        codigo: 'vip-lote-1-exemplo',
        produtoCodigo: 'evento-exemplo-vip',
        produtoNome: 'Evento Exemplo — VIP',
        produtoVertical: 'summit',
        produtoCategoria: 'vip',
        nome: 'Experiência VIP — Lote 1',
        valor: 1500,
      }),
    ],
  }),
];

function cupom(c: Partial<CupomCatalogo> & Pick<CupomCatalogo, 'id' | 'codigo' | 'situacao' | 'tipo' | 'valor'>): CupomCatalogo {
  return {
    atualizadoEm: '2026-09-20T12:00:00+00:00',
    descricao: null,
    aplicaEm: 'principais',
    ofertas: [],
    programas: [],
    produtos: [],
    valorMinimo: null,
    tetoDesconto: null,
    usosMaximos: null,
    usos: 0,
    usosPorEmail: null,
    iniciaEm: null,
    encerraEm: null,
    ativo: true,
    sistema: 'checkout_proprio',
    historico: false,
    situacaoOrdem: 1,
    origem: null,
    ...c,
  };
}

export const cuponsSemente: CupomCatalogo[] = [
  cupom({
    id: 'cp_valendo',
    codigo: 'EXEMPLO10',
    descricao: 'Cupom inventado de 10%.',
    tipo: 'percentual',
    valor: 10,
    situacao: 'valendo',
    usosMaximos: 50,
    usos: 4,
  }),
  cupom({
    id: 'cp_antigo',
    codigo: 'EXEMPLO200',
    descricao: 'Cupom inventado de R$ 200, histórico.',
    tipo: 'valor',
    valor: 200,
    situacao: 'historico',
    situacaoOrdem: 6,
    ativo: false,
    historico: true,
    sistema: 'eduzz',
    ofertas: ['mind-lote-1-exemplo'],
    produtos: ['evento-exemplo'],
  }),
];
