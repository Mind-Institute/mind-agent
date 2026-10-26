import {
  ROTULO_TIPO_PRODUTO,
  ROTULO_VERTICAL_PRODUTO,
  TIPOS_PRODUTO,
  VERTICAIS_PRODUTO,
  type ProdutoCatalogo,
  type ProdutoCatalogoForm,
  type TipoProduto,
  type VerticalProduto,
} from '@/contracts';
import type { OpcaoCategoria, Rotulo } from './rotulos';

/* ============================================================
   CATÁLOGO — regras que a tela usa
   ============================================================
   Conversão entre o registro (o que o banco guarda) e o formulário (o
   que a pessoa edita), e o recorte do que vai para o banco ao salvar.
   Moram aqui, e não na página, para serem testadas sozinhas. */

/* O fuso do Mind é o de Brasília, que não tem horário de verão desde
   2019: -03:00 o ano todo. É nele que a janela de venda é editada. */
const DESLOCAMENTO_BRASILIA_MS = -3 * 60 * 60 * 1000;
const SUFIXO_BRASILIA = '-03:00';

/** Instante do banco → valor do `<input type="datetime-local" step="1">`, em Brasília. */
export function paraCampoDataHora(iso: string | null | undefined): string {
  if (!iso) return '';
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return '';
  return new Date(t + DESLOCAMENTO_BRASILIA_MS).toISOString().slice(0, 19);
}

/** Valor do campo, em Brasília → instante com fuso explícito, para o banco. */
export function deCampoDataHora(local: string): string | null {
  if (!local) return null;
  const comSegundos = local.length === 16 ? `${local}:00` : local;
  return `${comSegundos}${SUFIXO_BRASILIA}`;
}

export function paraFormularioProduto(p: ProdutoCatalogo): ProdutoCatalogoForm {
  return {
    nome: p.nome,
    tipo: p.tipo,
    vertical: p.vertical ?? '',
    categoria: p.categoria ?? '',
    descricaoCurta: p.descricaoCurta ?? '',
    descricao: p.descricao ?? '',
    periodo: p.periodo ?? '',
    ativo: p.ativo,
    vende: p.vende,
    vendeDe: paraCampoDataHora(p.vendeDe),
    vendeAte: paraCampoDataHora(p.vendeAte),
    comecaEm: p.comecaEm ?? '',
    encerraEm: p.encerraEm ?? '',
    pipelinesHubspot: [...p.pipelinesHubspot],
  };
}

type CampoForm = keyof ProdutoCatalogoForm;

/** Campo do formulário → valor que o banco espera. */
function paraBanco(campo: CampoForm, v: ProdutoCatalogoForm): unknown {
  switch (campo) {
    case 'nome':
      return v.nome.trim();
    case 'vendeDe':
    case 'vendeAte':
      return deCampoDataHora(v[campo]);
    case 'ativo':
    case 'vende':
      return v[campo];
    case 'pipelinesHubspot':
      return v.pipelinesHubspot.map((s) => s.trim()).filter(Boolean);
    default:
      return (v[campo] as string).trim() || null;
  }
}

const CAMPOS: CampoForm[] = [
  'nome', 'tipo', 'vertical', 'categoria', 'descricaoCurta', 'descricao', 'periodo',
  'ativo', 'vende', 'vendeDe', 'vendeAte', 'comecaEm', 'encerraEm', 'pipelinesHubspot',
];

/**
 * O que vai para o banco ao salvar: SÓ o que mudou.
 *
 * Não é economia de bytes. O banco aplica apenas os campos que chegam, e
 * mandar o formulário inteiro regravaria campos que ninguém tocou — a
 * janela de venda tem segundos (`02:59:59`) que o campo de data e hora
 * poderia arredondar, e a auditoria registraria como mudança o que não
 * mudou. Sem registro de origem, vai tudo.
 */
export function payloadDaEdicaoProduto(
  valores: ProdutoCatalogoForm,
  original: ProdutoCatalogo | undefined,
): Partial<ProdutoCatalogo> {
  const antes = original ? paraFormularioProduto(original) : null;
  const payload: Record<string, unknown> = {};
  for (const campo of CAMPOS) {
    /* Datas que vêm da turma não saem daqui: mudam na turma, não na cópia. */
    if (original?.datasDaTurma && (campo === 'comecaEm' || campo === 'encerraEm')) continue;
    const mudou = !antes || !mesmoValor(campo, antes, valores);
    if (mudou) payload[campo] = paraBanco(campo, valores);
  }
  return payload as Partial<ProdutoCatalogo>;
}

/* Data e hora comparam o INSTANTE, não o texto: o campo pode devolver
   `23:59:59` ou `23:59:59.000` para a mesma hora, e a diferença de grafia
   não pode virar regravação. */
function mesmoValor(campo: CampoForm, a: ProdutoCatalogoForm, b: ProdutoCatalogoForm): boolean {
  if (campo === 'vendeDe' || campo === 'vendeAte') {
    const x = deCampoDataHora(a[campo]);
    const y = deCampoDataHora(b[campo]);
    if (x === null || y === null) return x === y;
    return new Date(x).getTime() === new Date(y).getTime();
  }
  return JSON.stringify(a[campo]) === JSON.stringify(b[campo]);
}

function resolver<T extends string>(mapa: Record<T, string>, valor: string | null): Rotulo {
  if (!valor) return { texto: '—', conhecido: true };
  const conhecido = Object.prototype.hasOwnProperty.call(mapa, valor);
  return conhecido ? { texto: mapa[valor as T], conhecido: true } : { texto: valor, conhecido: false };
}

export function rotuloTipoProduto(tipo: string): Rotulo {
  return resolver<TipoProduto>(ROTULO_TIPO_PRODUTO, tipo);
}

export function rotuloVerticalProduto(vertical: string | null): Rotulo {
  return resolver<VerticalProduto>(ROTULO_VERTICAL_PRODUTO, vertical);
}

export const OPCOES_TIPO_PRODUTO: OpcaoCategoria[] = TIPOS_PRODUTO.map((t) => ({
  valor: t,
  rotulo: ROTULO_TIPO_PRODUTO[t],
}));

export const OPCOES_VERTICAL_PRODUTO: OpcaoCategoria[] = VERTICAIS_PRODUTO.map((v) => ({
  valor: v,
  rotulo: ROTULO_VERTICAL_PRODUTO[v],
}));
