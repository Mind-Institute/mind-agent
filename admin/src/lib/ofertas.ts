import type {
  AlteracaoOferta,
  BonusForm,
  ExigenciaForm,
  OfertaCatalogo,
  OfertaForm,
  PrecoForm,
} from '@/contracts';
import { deCampoDataHora, paraCampoDataHora } from './catalogo';
import { formatarReais } from './format';

/* ============================================================
   OFERTAS — regras que a tela usa
   ============================================================
   Conversão entre a oferta como o banco devolve e o formulário, o recorte
   do que vai ao banco ao salvar, a cópia para duplicar e as frases de cada
   motivo do banco. Moram aqui, e não na página, para serem testadas
   sozinhas. As regras de verdade são as do banco
   (`mind_admin_mutate_ofertas`, migration 20260926210134). */

/** Número do banco → texto do campo. */
function paraCampoNumero(valor: number | null | undefined): string {
  return valor === null || valor === undefined ? '' : String(valor);
}

/** Texto do campo → número para o banco; aceita vírgula decimal. */
export function deCampoNumero(texto: string): number | null {
  const limpo = texto.trim().replace(',', '.');
  if (limpo === '') return null;
  const n = Number(limpo);
  return Number.isFinite(n) ? n : null;
}

export const FORMULARIO_VAZIO: OfertaForm = {
  codigo: '',
  nome: '',
  descricao: '',
  tipo: '',
  publico: true,
  iniciaEm: '',
  encerraEm: '',
  meiosPagamento: ['cartao', 'pix', 'boleto'],
  precos: [],
  bonus: [],
  requer: [],
};

export const PRECO_VAZIO: PrecoForm = {
  produtoCodigo: '',
  codigo: '',
  nome: '',
  valor: '',
  parcelas: '',
  valorParcela: '',
  valorRiscado: '',
  checkoutUrl: '',
  sistemaExterno: '',
  skuExterno: '',
};

export const BONUS_VAZIO: BonusForm = {
  produtoCodigo: '',
  inclusoCodigo: '',
  nome: '',
  descricao: '',
  detalhe: '',
  nota: '',
  valor: '',
  valorReferencia: '',
  iniciaEm: '',
  encerraEm: '',
};

export const EXIGENCIA_VAZIA: ExigenciaForm = {
  produtoCodigo: '',
  modo: 'carrinho',
  prioridade: '',
  grupoExclusivo: '',
  ativo: true,
  iniciaEm: '',
  encerraEm: '',
  observacao: '',
};

export function paraFormularioOferta(o: OfertaCatalogo): OfertaForm {
  return {
    codigo: o.codigo,
    nome: o.nome,
    descricao: o.descricao ?? '',
    tipo: o.tipo,
    publico: o.publico,
    iniciaEm: paraCampoDataHora(o.iniciaEm),
    encerraEm: paraCampoDataHora(o.encerraEm),
    meiosPagamento: [...o.meiosPagamento],
    precos: o.precos.map((p) => ({
      produtoCodigo: p.produtoCodigo,
      codigo: p.codigo,
      nome: p.nome ?? '',
      valor: paraCampoNumero(p.valor),
      parcelas: paraCampoNumero(p.parcelas),
      valorParcela: paraCampoNumero(p.valorParcela),
      valorRiscado: paraCampoNumero(p.valorRiscado),
      checkoutUrl: p.checkoutUrl ?? '',
      sistemaExterno: p.sistemaExterno ?? '',
      skuExterno: p.skuExterno ?? '',
    })),
    bonus: o.bonus.map((b) => ({
      produtoCodigo: b.produtoCodigo,
      inclusoCodigo: b.inclusoCodigo,
      nome: b.nome ?? '',
      descricao: b.descricao ?? '',
      detalhe: b.detalhe ?? '',
      nota: b.nota ?? '',
      valor: paraCampoNumero(b.valor),
      valorReferencia: paraCampoNumero(b.valorReferencia),
      iniciaEm: paraCampoDataHora(b.iniciaEm),
      encerraEm: paraCampoDataHora(b.encerraEm),
    })),
    requer: o.requer.map((r) => ({
      produtoCodigo: r.produtoCodigo,
      modo: r.modo === 'posse' ? 'posse' : 'carrinho',
      prioridade: paraCampoNumero(r.prioridade),
      grupoExclusivo: r.grupoExclusivo ?? '',
      ativo: r.ativo,
      iniciaEm: paraCampoDataHora(r.iniciaEm),
      encerraEm: paraCampoDataHora(r.encerraEm),
      observacao: r.observacao ?? '',
    })),
  };
}

/**
 * Duplicar: copia preços, bônus e exigências; prazo e códigos ficam em
 * branco (Passo 4 do plano). O histórico importado serve de base assim.
 */
export function duplicarOferta(o: OfertaCatalogo): OfertaForm {
  const base = paraFormularioOferta(o);
  return {
    ...base,
    codigo: '',
    nome: `Cópia de ${o.nome}`,
    iniciaEm: '',
    encerraEm: '',
    precos: base.precos.map((p) => ({ ...p, codigo: '' })),
    bonus: base.bonus.map((b) => ({ ...b, iniciaEm: '', encerraEm: '' })),
    requer: base.requer.map((r) => ({ ...r, iniciaEm: '', encerraEm: '' })),
  };
}

const textoOuNulo = (v: string) => v.trim() || null;

function precoParaBanco(p: PrecoForm, i: number) {
  return {
    produtoCodigo: p.produtoCodigo.trim(),
    codigo: p.codigo.trim(),
    nome: textoOuNulo(p.nome),
    valor: deCampoNumero(p.valor),
    parcelas: deCampoNumero(p.parcelas),
    valorParcela: deCampoNumero(p.valorParcela),
    valorRiscado: deCampoNumero(p.valorRiscado),
    checkoutUrl: textoOuNulo(p.checkoutUrl),
    sistemaExterno: textoOuNulo(p.sistemaExterno),
    skuExterno: textoOuNulo(p.skuExterno),
    ordem: i + 1,
  };
}

function bonusParaBanco(b: BonusForm, i: number) {
  return {
    produtoCodigo: b.produtoCodigo.trim(),
    inclusoCodigo: b.inclusoCodigo.trim(),
    nome: textoOuNulo(b.nome),
    descricao: textoOuNulo(b.descricao),
    detalhe: textoOuNulo(b.detalhe),
    nota: textoOuNulo(b.nota),
    valor: deCampoNumero(b.valor) ?? 0,
    valorReferencia: deCampoNumero(b.valorReferencia),
    iniciaEm: deCampoDataHora(b.iniciaEm),
    encerraEm: deCampoDataHora(b.encerraEm),
    ordem: i + 1,
  };
}

function exigenciaParaBanco(r: ExigenciaForm, i: number) {
  return {
    produtoCodigo: r.produtoCodigo.trim(),
    modo: r.modo,
    prioridade: deCampoNumero(r.prioridade),
    grupoExclusivo: textoOuNulo(r.grupoExclusivo),
    ativo: r.ativo,
    iniciaEm: deCampoDataHora(r.iniciaEm),
    encerraEm: deCampoDataHora(r.encerraEm),
    observacao: textoOuNulo(r.observacao),
    ordem: i + 1,
  };
}

type CampoForm = keyof OfertaForm;

/** Campo do formulário → valor que o banco espera. */
function paraBanco(campo: CampoForm, v: OfertaForm): unknown {
  switch (campo) {
    case 'codigo':
    case 'nome':
    case 'tipo':
      return v[campo].trim();
    case 'descricao':
      return textoOuNulo(v.descricao);
    case 'publico':
      return v.publico;
    case 'iniciaEm':
    case 'encerraEm':
      /* Preço sem prazo não tem janela: o que ficou no campo não vai. */
      return v.tipo === 'base' ? null : deCampoDataHora(v[campo]);
    case 'meiosPagamento':
      return [...v.meiosPagamento];
    case 'precos':
      return v.precos.map(precoParaBanco);
    case 'bonus':
      return v.bonus.map(bonusParaBanco);
    case 'requer':
      return v.requer.map(exigenciaParaBanco);
  }
}

const CAMPOS: CampoForm[] = [
  'codigo', 'nome', 'descricao', 'tipo', 'publico', 'iniciaEm', 'encerraEm', 'meiosPagamento',
  'precos', 'bonus', 'requer',
];

/* Data e hora comparam o INSTANTE, não o texto (como no Catálogo). O resto,
   pelo valor que iria ao banco: lista igual não viaja. */
function mesmoValor(campo: CampoForm, a: OfertaForm, b: OfertaForm): boolean {
  if (campo === 'iniciaEm' || campo === 'encerraEm') {
    const x = paraBanco(campo, a) as string | null;
    const y = paraBanco(campo, b) as string | null;
    if (x === null || y === null) return x === y;
    return new Date(x).getTime() === new Date(y).getTime();
  }
  return JSON.stringify(paraBanco(campo, a)) === JSON.stringify(paraBanco(campo, b));
}

/**
 * O que vai ao banco ao salvar: SÓ o que mudou; uma lista que mudou vai
 * inteira (o banco trata a lista como a lista toda). Criar manda tudo.
 */
export function payloadDaOferta(valores: OfertaForm, original?: OfertaCatalogo): Record<string, unknown> {
  const antes = original ? paraFormularioOferta(original) : null;
  const payload: Record<string, unknown> = {};
  for (const campo of CAMPOS) {
    if (!antes || !mesmoValor(campo, antes, valores)) payload[campo] = paraBanco(campo, valores);
  }
  /* Mudou o tipo para "sem prazo": a janela antiga tem de sair junto. */
  if (antes && payload.tipo === 'base') {
    payload.iniciaEm = null;
    payload.encerraEm = null;
  }
  return payload;
}

/* ---------- o que muda para quem compra ---------- */

export interface MudancaDePreco {
  produto: string;
  antes: string | null;
  depois: string | null;
  eduzz: string | null;
}

function precoLegivel(valor: number | null, parcelas: number | null, parcela: number | null): string | null {
  if (valor === null) return null;
  const avista = formatarReais(valor);
  return parcelas && parcela !== null ? `${avista} · ${parcelas}× de ${formatarReais(parcela)}` : avista;
}

/** Os preços que mudam, produto a produto, para a confirmação antes de salvar. */
export function mudancasDePreco(original: OfertaCatalogo, valores: OfertaForm): MudancaDePreco[] {
  const mudancas: MudancaDePreco[] = [];
  for (const p of valores.precos) {
    const antigo = original.precos.find((x) => x.produtoCodigo === p.produtoCodigo);
    const depois = precoLegivel(deCampoNumero(p.valor), deCampoNumero(p.parcelas), deCampoNumero(p.valorParcela));
    const antes = antigo ? precoLegivel(antigo.valor, antigo.parcelas, antigo.valorParcela) : null;
    if (antes !== depois) {
      mudancas.push({
        produto: antigo?.produtoNome ?? p.produtoCodigo,
        antes,
        depois,
        eduzz: antigo?.eduzz?.preco !== undefined && antigo?.eduzz?.preco !== null ? formatarReais(antigo.eduzz.preco) : null,
      });
    }
  }
  return mudancas;
}

/* ---------- frases ---------- */

/**
 * Por que "pôr no ar" está travado: o motivo que o banco devolve, na mesma
 * frase da `mindagent-catalogo`.
 */
export const MOTIVO_BLOQUEIO: Record<string, string> = {
  historico_so_leitura: 'Esta oferta é histórico: só consulta. Para usar como base, duplique.',
  sem_preco: 'Só vai ao ar oferta com valor em todos os preços.',
  condicional_sem_exigencia: 'Order bump ou upgrade só vai ao ar com pelo menos uma exigência ligada.',
  prazo_vencido: 'O prazo desta oferta já terminou. Mude o fim (prorrogar) antes de pôr no ar.',
  sem_leitor:
    'Nenhum site lê ainda as ofertas deste produto no catálogo: o Institute passa a ler na virada; os outros produtos, quando um site passar a ler. Até lá, a oferta fica como rascunho.',
  base_duplicada: 'Este produto já tem um preço sem prazo no ar. Tire aquele do ar antes.',
};

export function motivoDoBloqueio(codigo: string | null): string | null {
  if (!codigo) return null;
  return Object.prototype.hasOwnProperty.call(MOTIVO_BLOQUEIO, codigo) ? MOTIVO_BLOQUEIO[codigo] : codigo;
}

const ROTULO_ACAO: Record<string, string> = {
  criar: 'Criou',
  atualizar: 'Editou',
  publicar: 'Pôs no ar',
  arquivar: 'Tirou do ar',
};

const ROTULO_CAMPO: Record<string, string> = {
  codigo: 'código',
  nome: 'nome',
  descricao: 'descrição',
  tipo: 'tipo',
  ativo: 'no ar',
  publico: 'aparece no site',
  iniciaEm: 'início',
  encerraEm: 'fim',
  meiosPagamento: 'meios de pagamento',
  precos: 'preços',
  bonus: 'bônus',
  requer: 'exigências',
};

/** "Editou preços e fim", como a linha do histórico de alterações diz. */
export function resumoDaAlteracao(a: AlteracaoOferta): string {
  const acao = ROTULO_ACAO[a.acao] ?? a.acao;
  const campos = a.campos.map((c) => ROTULO_CAMPO[c]).filter(Boolean);
  if (a.acao !== 'atualizar' || campos.length === 0) return acao;
  const lista = campos.length === 1 ? campos[0] : `${campos.slice(0, -1).join(', ')} e ${campos.at(-1)}`;
  return `${acao} ${lista}`;
}

/**
 * "12× de R$ 500,00 = R$ 6.000,00 (R$ 3,00 acima do à vista)": a conta que
 * o banco confere (a parcela fecha entre o à vista e o à vista + R$ 1 por
 * parcela), mostrada enquanto a pessoa digita.
 */
export function conferirParcelas(
  valorTexto: string,
  parcelasTexto: string,
  parcelaTexto: string,
): { texto: string; fecha: boolean } | null {
  const valor = deCampoNumero(valorTexto);
  const parcelas = deCampoNumero(parcelasTexto);
  const parcela = deCampoNumero(parcelaTexto);
  if (valor === null || parcelas === null || parcela === null || parcelas < 1) return null;
  const total = Math.round(parcelas * parcela * 100) / 100;
  const diferenca = Math.round((total - valor) * 100) / 100;
  const fecha = diferenca >= 0 && diferenca <= parcelas;
  const conta = `${parcelas}× de ${formatarReais(parcela)} = ${formatarReais(total)}`;
  if (diferenca === 0) return { texto: `${conta}, igual ao à vista`, fecha };
  if (diferenca > 0) return { texto: `${conta} (${formatarReais(diferenca)} acima do à vista)`, fecha };
  return { texto: `${conta} (${formatarReais(-diferenca)} abaixo do à vista)`, fecha };
}
