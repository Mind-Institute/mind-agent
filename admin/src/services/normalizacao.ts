import type { ListResult, MapaRecursos, NomeRecurso } from '@/contracts';

/* ============================================================
   NORMALIZAÇÃO DE RESPOSTA
   ============================================================
   O que esta camada faz: preenche campo AUSENTE com o vazio do tipo
   certo — array que não veio vira `[]`, texto que não veio vira `''`.
   Sem isso, um `sessoes[].temas` faltando derruba a listagem inteira
   num `.map de undefined`, e o painel some por causa de um campo
   opcional.

   O que esta camada NÃO faz, e não pode fazer: mudar valor que veio.
   Categoria desconhecida passa intacta (ver `src/lib/rotulos.ts`),
   número não é arredondado, texto não é normalizado. Traduzir aqui
   seria mentir sobre o que está na base — o painel prefere mostrar o
   código estranho a inventar um familiar. */

type Molde = Record<string, unknown>;

/** Só os recursos que vêm da API real precisam de molde. */
const MOLDES: Partial<Record<NomeRecurso, Molde>> = {
  event: {
    nome: '',
    slug: '',
    dataInicio: '',
    dataFim: '',
    local: '',
    cidade: '',
    fusoHorario: '',
    descricao: '',
    regraReserva: '',
    regraVagas: '',
    ativo: true,
    locaisCandidatos: [],
  },
  sessions: {
    titulo: '',
    descricao: '',
    dia: '',
    inicio: '',
    fim: null,
    espacoId: null,
    tipo: '',
    formato: '',
    trilhas: [],
    temas: [],
    palestranteIds: [],
    quemTexto: '',
    necessitaReserva: false,
    vagasTotais: null,
    vagasDisponiveis: null,
    nivel: null,
    resultadosEsperados: [],
    status: 'rascunho',
    publicadoEm: null,
    publicadoPor: null,
  },
  speakers: {
    nome: '',
    cargo: '',
    organizacao: '',
    biografia: '',
    foto: '',
    temas: [],
    destaque: false,
    sessaoIds: [],
    status: 'rascunho',
    publicadoEm: null,
    publicadoPor: null,
  },
  spaces: {
    nome: '',
    slug: '',
    tipo: '',
    aliases: [],
    descricao: '',
    comoChegar: '',
    localPrincipal: '',
    espacoPaiId: null,
    andar: '',
    coordenadaX: null,
    coordenadaY: null,
    acessivel: true,
    observacaoAcessibilidade: '',
    ativo: true,
  },
  themes: { codigo: '', rotulo: '' },
};

const COMUNS: Molde = { id: '', criadoEm: '', atualizadoEm: '', atualizadoPor: null };

export function normalizarRegistro<K extends NomeRecurso>(
  resource: K,
  registro: unknown,
): MapaRecursos[K] {
  const molde = MOLDES[resource];
  if (!molde || !registro || typeof registro !== 'object') return registro as MapaRecursos[K];

  const bruto = registro as Molde;
  const saida: Molde = { ...bruto };

  for (const [chave, vazio] of Object.entries({ ...COMUNS, ...molde })) {
    if (saida[chave] !== undefined) continue;
    /* Array e objeto ganham cópia própria: molde compartilhado entre
       registros viraria estado compartilhado entre linhas da tabela. */
    saida[chave] = Array.isArray(vazio) ? [] : vazio;
  }

  return saida as MapaRecursos[K];
}

export function normalizarLista<K extends NomeRecurso>(
  resource: K,
  resposta: unknown,
): ListResult<MapaRecursos[K]> {
  const bruto = (resposta ?? {}) as Partial<ListResult<unknown>>;
  const itens = Array.isArray(bruto.itens)
    ? bruto.itens.map((item) => normalizarRegistro(resource, item))
    : [];
  return {
    itens,
    total: typeof bruto.total === 'number' ? bruto.total : itens.length,
    pagina: typeof bruto.pagina === 'number' ? bruto.pagina : 1,
    porPagina: typeof bruto.porPagina === 'number' ? bruto.porPagina : itens.length,
  };
}
