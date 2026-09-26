import type { OfertaCatalogo, ProdutoCatalogo } from '@/contracts';

/* ============================================================
   OFERTAS NA DEMONSTRAÇÃO — o que o banco calcula, imitado
   ============================================================
   Em produção quem monta a oferta, calcula a situação e decide se ela
   pode ir ao ar é o banco (`mind_admin_read_ofertas` e
   `mind_admin_mutate_ofertas`). O banco em memória imita o suficiente para
   a tela se comportar igual: a oferta nasce desligada, "pôr no ar" fica
   travado com o motivo, e cada escrita entra no histórico de alterações. */

export interface EscritaOferta {
  acao: 'criar' | 'atualizar' | 'publicar' | 'arquivar';
  por: string;
}

type Linha = Record<string, unknown>;

/** A mesma regra de situação do banco, com as duas pontas da janela incluídas. */
export function situacaoDaOferta(o: Pick<OfertaCatalogo, 'historico' | 'ativo' | 'publico' | 'iniciaEm' | 'encerraEm'>, agora = Date.now()) {
  const situacao = o.historico
    ? 'historico'
    : !o.ativo
      ? 'desligada'
      : o.iniciaEm && agora < Date.parse(o.iniciaEm)
        ? 'agendada'
        : o.encerraEm && agora > Date.parse(o.encerraEm)
          ? 'encerrada'
          : !o.publico
            ? 'so_link'
            : 'no_ar';
  const ordem = { no_ar: 1, so_link: 2, agendada: 3, encerrada: 4, desligada: 5, historico: 6 }[situacao];
  return { situacao, situacaoOrdem: ordem };
}

/**
 * Por que a oferta não pode ir ao ar agora, na ordem do banco. Na
 * demonstração nenhum site lê o catálogo (como antes da virada), a não ser
 * que o teste ligue o leitor.
 */
export function bloqueioDaOferta(o: OfertaCatalogo, todas: OfertaCatalogo[], comLeitor: boolean, agora = Date.now()): string | null {
  if (o.historico) return 'historico_so_leitura';
  if (o.precos.length === 0 || o.precos.some((p) => p.valor === null)) return 'sem_preco';
  if (o.tipo === 'condicional' && !o.requer.some((r) => r.ativo)) return 'condicional_sem_exigencia';
  if (o.encerraEm && Date.parse(o.encerraEm) <= agora) return 'prazo_vencido';
  if (!comLeitor) return 'sem_leitor';
  if (
    o.tipo === 'base' &&
    todas.some(
      (x) =>
        x.id !== o.id &&
        x.ativo &&
        !x.historico &&
        x.tipo === 'base' &&
        x.precos.some((p) => o.precos.some((q) => q.produtoCodigo === p.produtoCodigo)),
    )
  ) {
    return 'base_duplicada';
  }
  return null;
}

function nomeDoProduto(produtos: ProdutoCatalogo[], codigo: string) {
  return produtos.find((p) => p.codigo === codigo) ?? null;
}

/** Completa as linhas que chegam do formulário com o que o banco junta (nome e vertical do produto). */
export function montarLinhas(payload: Linha, produtos: ProdutoCatalogo[]): Linha {
  const saida: Linha = {};
  if (Array.isArray(payload.precos)) {
    saida.precos = (payload.precos as Linha[]).map((p) => {
      const produto = nomeDoProduto(produtos, String(p.produtoCodigo));
      return {
        moeda: 'BRL',
        descricao: null,
        noSite: false,
        vigenteNoSite: false,
        eduzz: null,
        produtoCategoria: produto?.categoria ?? null,
        ...p,
        produtoNome: produto?.nome ?? null,
        produtoVertical: produto?.vertical ?? null,
      };
    });
  }
  if (Array.isArray(payload.bonus)) {
    saida.bonus = (payload.bonus as Linha[]).map((b) => ({
      ...b,
      inclusoNome: nomeDoProduto(produtos, String(b.inclusoCodigo))?.nome ?? null,
    }));
  }
  if (Array.isArray(payload.requer)) {
    saida.requer = (payload.requer as Linha[]).map((r) => ({
      ...r,
      prioridade: r.prioridade ?? 100,
      produtoNome: nomeDoProduto(produtos, String(r.produtoCodigo))?.nome ?? null,
    }));
  }
  return saida;
}

/** Depois de cada escrita: o que o banco recalcula na leitura. */
export function recalcular(o: OfertaCatalogo, todas: OfertaCatalogo[], comLeitor: boolean): OfertaCatalogo {
  const verticais = [...new Set(o.precos.map((p) => p.produtoVertical).filter((v): v is string => Boolean(v)))];
  const produtos = [...new Set(o.precos.map((p) => p.produtoCodigo))];
  const comSituacao = { ...o, ...situacaoDaOferta(o), verticais, produtos };
  return {
    ...comSituacao,
    bloqueioPorNoAr: comSituacao.ativo ? null : bloqueioDaOferta(comSituacao, todas, comLeitor),
  };
}

/** A linha nova do histórico de alterações, com os campos que mudaram. */
export function registrarAlteracao(antes: OfertaCatalogo | null, depois: OfertaCatalogo, escrita: EscritaOferta, em: string) {
  const ignorar = new Set(['atualizadoEm', 'situacao', 'situacaoOrdem', 'noSite', 'jaFoiAoAr', 'bloqueioPorNoAr', 'sobrepostas', 'alteracoes', 'atualizadoPor']);
  const campos = antes
    ? Object.keys(depois)
        .filter((c) => !ignorar.has(c))
        .filter((c) => JSON.stringify((antes as Linha)[c]) !== JSON.stringify((depois as Linha)[c]))
        .sort()
    : [];
  return [{ acao: escrita.acao, em, por: escrita.por, campos }, ...(antes?.alteracoes ?? [])];
}
