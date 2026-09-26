import { z } from 'zod';

/* ============================================================
   OFERTAS E CUPONS — o schema `catalogo`, como está no banco
   ============================================================
   Decisão da Adriana (26/09/2026): preço, oferta, order bump e cupom moram
   no schema `catalogo`, em tabelas separadas, e "o painel é o controle deste
   schema". A oferta chega montada pelo banco (`mind_admin_read_ofertas`):
   a linha de `catalogo.ofertas` com os preços (`oferta_precos`), o bônus
   (`oferta_inclui`), o que ela exige — bump e upgrade (`oferta_requer`) — e
   a SITUAÇÃO calculada com as mesmas pontas de janela do site.

   Por enquanto é só leitura (Passo 2 de docs/PLANO_OFERTAS_PASSO_A_PASSO.md);
   a edição é o Passo 4. Os schemas conferem o que a tela usa e deixam passar
   o resto (`passthrough`): coluna nova no banco aparece no detalhe sem
   versão nova do painel. */

export const precoOfertaSchema = z
  .object({
    codigo: z.string().min(1),
    produtoCodigo: z.string().min(1),
    produtoNome: z.string().nullable().default(null),
    produtoVertical: z.string().nullable().default(null),
    produtoCategoria: z.string().nullable().default(null),
    nome: z.string().nullable().default(null),
    descricao: z.string().nullable().default(null),
    /* Em reais, como o banco guarda (numeric) — não em centavos. */
    valor: z.number().nullable().default(null),
    parcelas: z.number().nullable().default(null),
    valorParcela: z.number().nullable().default(null),
    valorRiscado: z.number().nullable().default(null),
    moeda: z.string().default('BRL'),
    checkoutUrl: z.string().nullable().default(null),
    sistemaExterno: z.string().nullable().default(null),
    skuExterno: z.string().nullable().default(null),
    noSite: z.boolean().default(false),
    vigenteNoSite: z.boolean().default(false),
    eduzz: z
      .object({
        preco: z.number().nullable().default(null),
        lidoEm: z.string().nullable().default(null),
        arquivado: z.boolean().nullable().default(null),
      })
      .nullable()
      .default(null),
  })
  .passthrough();
export type PrecoOferta = z.infer<typeof precoOfertaSchema>;

export const bonusOfertaSchema = z
  .object({
    produtoCodigo: z.string().min(1),
    inclusoCodigo: z.string().min(1),
    inclusoNome: z.string().nullable().default(null),
    nome: z.string().nullable().default(null),
    descricao: z.string().nullable().default(null),
    valorReferencia: z.number().nullable().default(null),
    iniciaEm: z.string().nullable().default(null),
    encerraEm: z.string().nullable().default(null),
  })
  .passthrough();
export type BonusOferta = z.infer<typeof bonusOfertaSchema>;

export const exigenciaOfertaSchema = z
  .object({
    produtoCodigo: z.string().min(1),
    produtoNome: z.string().nullable().default(null),
    /* carrinho = order bump (exige no carrinho); posse = upgrade (exige ter comprado). */
    modo: z.string().min(1),
    prioridade: z.number().nullable().default(null),
    grupoExclusivo: z.string().nullable().default(null),
    ativo: z.boolean().default(true),
  })
  .passthrough();
export type ExigenciaOferta = z.infer<typeof exigenciaOfertaSchema>;

export const ofertaCatalogoSchema = z
  .object({
    /* Sem estes a linha não abre, não se ordena nem se entende. */
    id: z.string().min(1),
    codigo: z.string().min(1),
    nome: z.string().min(1),
    tipo: z.string().min(1),
    situacao: z.string().min(1),
    atualizadoEm: z.string().min(1),
    descricao: z.string().nullable().default(null),
    ativo: z.boolean(),
    publico: z.boolean().default(true),
    historico: z.boolean().default(false),
    iniciaEm: z.string().nullable().default(null),
    encerraEm: z.string().nullable().default(null),
    meiosPagamento: z.array(z.string()).default([]),
    situacaoOrdem: z.number().default(9),
    noSite: z.boolean().default(false),
    verticais: z.array(z.string()).default([]),
    produtos: z.array(z.string()).default([]),
    precos: z.array(precoOfertaSchema).default([]),
    bonus: z.array(bonusOfertaSchema).default([]),
    requer: z.array(exigenciaOfertaSchema).default([]),
    origem: z.record(z.unknown()).nullable().default(null),
  })
  .passthrough();
export type OfertaCatalogo = z.infer<typeof ofertaCatalogoSchema>;

export const cupomCatalogoSchema = z
  .object({
    id: z.string().min(1),
    codigo: z.string().min(1),
    situacao: z.string().min(1),
    atualizadoEm: z.string().min(1),
    descricao: z.string().nullable().default(null),
    tipo: z.string().min(1),
    /* Em reais (tipo "valor") ou em % (tipo "percentual"). */
    valor: z.number(),
    aplicaEm: z.string().nullable().default(null),
    ofertas: z.array(z.string()).default([]),
    programas: z.array(z.string()).default([]),
    produtos: z.array(z.string()).default([]),
    valorMinimo: z.number().nullable().default(null),
    tetoDesconto: z.number().nullable().default(null),
    usosMaximos: z.number().nullable().default(null),
    usos: z.number().default(0),
    usosPorEmail: z.number().nullable().default(null),
    iniciaEm: z.string().nullable().default(null),
    encerraEm: z.string().nullable().default(null),
    ativo: z.boolean(),
    sistema: z.string().default('checkout_proprio'),
    historico: z.boolean().default(false),
    situacaoOrdem: z.number().default(9),
    origem: z.record(z.unknown()).nullable().default(null),
  })
  .passthrough();
export type CupomCatalogo = z.infer<typeof cupomCatalogoSchema>;

/* Os rótulos da situação — a mesma regra do banco e das mesmas pontas de
   janela que o site usa (ver a migration 20260926202049). Situação nova
   aparece crua. */
export const SITUACOES_OFERTA: { valor: string; rotulo: string; dica: string }[] = [
  { valor: 'no_ar', rotulo: 'No ar', dica: 'Ligada, pública e dentro do prazo.' },
  { valor: 'so_link', rotulo: 'Só por link', dica: 'Ligada e dentro do prazo, mas não aparece no site.' },
  { valor: 'agendada', rotulo: 'Agendada', dica: 'Ligada; o prazo ainda não começou.' },
  { valor: 'encerrada', rotulo: 'Encerrada', dica: 'Ligada; o prazo já passou.' },
  { valor: 'desligada', rotulo: 'Desligada', dica: 'Tirada do ar.' },
  { valor: 'historico', rotulo: 'Histórico', dica: 'Importada como histórico: só consulta.' },
];

export const SITUACOES_CUPOM: { valor: string; rotulo: string; dica: string }[] = [
  { valor: 'valendo', rotulo: 'Valendo', dica: 'Ligado e dentro do prazo.' },
  { valor: 'agendado', rotulo: 'Agendado', dica: 'O prazo ainda não começou.' },
  { valor: 'esgotado', rotulo: 'Esgotado', dica: 'Atingiu o limite de usos.' },
  { valor: 'encerrado', rotulo: 'Encerrado', dica: 'O prazo já passou.' },
  { valor: 'desligado', rotulo: 'Desligado', dica: 'Tirado do ar.' },
  { valor: 'historico', rotulo: 'Histórico', dica: 'Importado como histórico: só consulta.' },
];

export const TIPOS_OFERTA: { valor: string; rotulo: string }[] = [
  { valor: 'base', rotulo: 'Preço sem prazo' },
  { valor: 'periodo', rotulo: 'Condição com prazo' },
  { valor: 'combo', rotulo: 'Combo' },
  { valor: 'condicional', rotulo: 'Order bump / upgrade' },
];
