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

   Desde o Passo 4 (docs/PLANO_OFERTAS_PASSO_A_PASSO.md) a oferta também se
   edita: criar (nasce desligada), editar, pôr no ar e tirar do ar — as
   regras moram no banco (`mind_admin_mutate_ofertas`). Os cupons seguem só
   leitura. Os schemas conferem o que a tela usa e deixam passar o resto
   (`passthrough`): coluna nova no banco aparece no detalhe sem versão nova
   do painel. */

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
    ordem: z.number().nullable().default(null),
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
    detalhe: z.string().nullable().default(null),
    nota: z.string().nullable().default(null),
    /* Quanto o bônus custa dentro da oferta: 0 é grátis. */
    valor: z.number().default(0),
    valorReferencia: z.number().nullable().default(null),
    iniciaEm: z.string().nullable().default(null),
    encerraEm: z.string().nullable().default(null),
    ordem: z.number().nullable().default(null),
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
    iniciaEm: z.string().nullable().default(null),
    encerraEm: z.string().nullable().default(null),
    observacao: z.string().nullable().default(null),
    ordem: z.number().nullable().default(null),
  })
  .passthrough();
export type ExigenciaOferta = z.infer<typeof exigenciaOfertaSchema>;

/* Uma linha do histórico de alterações da oferta, tirada da auditoria. As
   ações têm os nomes da auditoria: publicar = pôs no ar, arquivar = tirou do ar. */
export const alteracaoOfertaSchema = z
  .object({
    acao: z.string().min(1),
    em: z.string().min(1),
    por: z.string().nullable().default(null),
    campos: z.array(z.string()).default([]),
  })
  .passthrough();
export type AlteracaoOferta = z.infer<typeof alteracaoOfertaSchema>;

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
    /* Já esteve no ar: os códigos travam e nenhuma linha sai. */
    jaFoiAoAr: z.boolean().default(false),
    /* Por que "pôr no ar" seria recusado agora (o motivo do banco); nulo quando pode. */
    bloqueioPorNoAr: z.string().nullable().default(null),
    /* Outras ofertas ligadas, com prazo, valendo junto para o mesmo produto. */
    sobrepostas: z.array(z.string()).default([]),
    /* Só na leitura de uma oferta: quem mudou o quê e quando. */
    alteracoes: z.array(alteracaoOfertaSchema).nullable().default(null),
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

/* ============================================================
   FORMULÁRIO DE OFERTA
   ============================================================
   O que a pessoa edita. Número entra como texto (é o que o campo devolve)
   e vira número no envio; data e hora, no horário de Brasília. As regras
   de negócio moram no banco e voltam com frase própria; aqui ficam só as
   que dá para dizer antes de enviar. */

export const CODIGO_OFERTA = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const MENSAGEM_CODIGO = 'Só letras minúsculas, números e hífen.';

/** Texto de número em reais: vazio, ou número não negativo com até dois decimais. */
function numeroOpcional(rotulo: string) {
  return z
    .string()
    .trim()
    .refine((v) => v === '' || /^\d+([.,]\d{1,2})?$/.test(v), `${rotulo}: número com até dois decimais.`);
}

export const precoFormSchema = z.object({
  produtoCodigo: z.string().trim().min(1, 'Escolha o produto.'),
  codigo: z.string().trim().min(1, 'Informe o código vendável.').regex(CODIGO_OFERTA, MENSAGEM_CODIGO),
  nome: z.string(),
  valor: numeroOpcional('Valor'),
  parcelas: z
    .string()
    .trim()
    .refine((v) => v === '' || /^[1-9]\d?$/.test(v), 'Parcelas: de 1 a 99.'),
  valorParcela: numeroOpcional('Valor da parcela'),
  valorRiscado: numeroOpcional('Valor riscado'),
  checkoutUrl: z
    .string()
    .trim()
    .refine((v) => v === '' || /^https:\/\/\S+$/.test(v), 'O link precisa começar com https://.'),
  sistemaExterno: z.string(),
  skuExterno: z.string(),
});
export type PrecoForm = z.infer<typeof precoFormSchema>;

export const bonusFormSchema = z.object({
  produtoCodigo: z.string().trim().min(1, 'Escolha de qual preço é o bônus.'),
  inclusoCodigo: z.string().trim().min(1, 'Escolha o produto que o bônus entrega.'),
  nome: z.string(),
  descricao: z.string(),
  detalhe: z.string(),
  nota: z.string(),
  valor: numeroOpcional('Valor'),
  valorReferencia: numeroOpcional('Valor de referência'),
  iniciaEm: z.string(),
  encerraEm: z.string(),
});
export type BonusForm = z.infer<typeof bonusFormSchema>;

export const exigenciaFormSchema = z.object({
  produtoCodigo: z.string().trim().min(1, 'Escolha o produto exigido.'),
  modo: z.enum(['carrinho', 'posse']),
  prioridade: z
    .string()
    .trim()
    .refine((v) => v === '' || /^\d{1,4}$/.test(v), 'Prioridade: número inteiro.'),
  grupoExclusivo: z.string(),
  ativo: z.boolean(),
  iniciaEm: z.string(),
  encerraEm: z.string(),
  observacao: z.string(),
});
export type ExigenciaForm = z.infer<typeof exigenciaFormSchema>;

export const ofertaFormSchema = z
  .object({
    codigo: z.string().trim().min(1, 'Informe o código da oferta.').regex(CODIGO_OFERTA, MENSAGEM_CODIGO),
    nome: z.string().trim().min(1, 'Informe o nome da oferta.'),
    descricao: z.string(),
    tipo: z.string().min(1, 'Escolha o tipo da oferta.'),
    publico: z.boolean(),
    iniciaEm: z.string(),
    encerraEm: z.string(),
    meiosPagamento: z.array(z.string()),
    precos: z.array(precoFormSchema),
    bonus: z.array(bonusFormSchema),
    requer: z.array(exigenciaFormSchema),
  })
  .superRefine((v, ctx) => {
    if (v.tipo === 'base' && (v.iniciaEm || v.encerraEm)) {
      ctx.addIssue({ code: 'custom', path: ['encerraEm'], message: 'Preço sem prazo não tem início nem fim.' });
    }
    if (v.iniciaEm && v.encerraEm && v.iniciaEm >= v.encerraEm) {
      ctx.addIssue({ code: 'custom', path: ['encerraEm'], message: 'O fim não pode ser antes do início.' });
    }
    const produtos = v.precos.map((p) => p.produtoCodigo);
    produtos.forEach((produto, i) => {
      if (produto && produtos.indexOf(produto) !== i) {
        ctx.addIssue({ code: 'custom', path: ['precos', i, 'produtoCodigo'], message: 'Este produto já tem preço nesta oferta.' });
      }
    });
    v.precos.forEach((p, i) => {
      if ((p.parcelas === '') !== (p.valorParcela === '')) {
        ctx.addIssue({ code: 'custom', path: ['precos', i, 'valorParcela'], message: 'Parcelas e valor da parcela vão juntos.' });
      }
    });
    if (v.requer.length > 0 && v.tipo !== 'condicional') {
      ctx.addIssue({ code: 'custom', path: ['tipo'], message: 'Exigência só em oferta do tipo Order bump / upgrade.' });
    }
    v.bonus.forEach((b, i) => {
      if (b.produtoCodigo && !produtos.includes(b.produtoCodigo)) {
        ctx.addIssue({ code: 'custom', path: ['bonus', i, 'produtoCodigo'], message: 'O bônus pertence a um produto com preço nesta oferta.' });
      }
    });
  });
export type OfertaForm = z.infer<typeof ofertaFormSchema>;
