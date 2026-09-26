/* ============================================================
   HybridAdminDataProvider — meio caminho, dito em voz alta
   ============================================================
   Nesta etapa o painel tem estas origens:

   - o núcleo do evento — visão geral, evento, programação, palestrantes,
     espaços e temas — vem da `mindagent-admin`, em leitura e escrita;
   - o catálogo (`catalogo.produtos`) vem da `mindagent-catalogo`, outra
     função separada, pelo mesmo motivo. Lê e edita — criar e arquivar
     produto não existem por aqui;
   - rotas, estandes, ofertas, conteúdo institucional, documentos,
     conversas, perguntas, usuários e auditoria continuam no banco em
     memória.

   Desde 26/09/2026 o painel não tem mais tela do evento (visão geral,
   evento, programação, palestrantes, espaços, rotas, estandes) nem da
   Home V3: eram do app do Summit, e a Adriana tirou. Na tela, o que é
   real é o catálogo. O encaminhamento do núcleo do evento continua aqui
   até a limpeza da camada de dados.

   Essa mistura é a coisa mais perigosa do painel: quem edita um
   palestrante real e um estande falso na mesma sessão precisa saber
   qual é qual. Por isso o modo é `hybrid` e não `http`, a faixa do topo
   nomeia os módulos reais, e `origemDoRecurso()` deixa cada página
   ajustar o que diz depois de salvar.

   NÃO EXISTE QUEDA PARA O MOCK. Se um recurso real falha, a tela mostra
   o erro. Cair no mock em silêncio faria o painel apresentar dado
   inventado como se fosse do banco — e é justamente o que o projeto
   inteiro existe para não fazer. */

import type {
  ListFilters,
  ListResult,
  MapaRecursos,
  NomeRecurso,
  OpcoesEscrita,
  ReciboReindexacao,
  ResumoPainel,
} from '@/contracts';
import { AdminApiError } from '@/contracts';
import type { AdminDataProvider } from './admin-data-provider';

/** Recursos servidos pela API real nesta etapa. */
export const RECURSOS_REAIS = [
  'event',
  'sessions',
  'speakers',
  'spaces',
  'themes',
] as const satisfies readonly NomeRecurso[];

export type RecursoReal = (typeof RECURSOS_REAIS)[number];

/** Servido pela `mindagent-catalogo`: ler e editar, nada além. */
export const RECURSOS_DO_CATALOGO = ['products'] as const satisfies readonly NomeRecurso[];

const CONJUNTO_CATALOGO = new Set<string>(RECURSOS_DO_CATALOGO);

export function ehRecursoDoCatalogo(resource: NomeRecurso): boolean {
  return CONJUNTO_CATALOGO.has(resource);
}

const OPERACOES_DO_CATALOGO = new Set(['list', 'get', 'update']);

const CONJUNTO_REAIS = new Set<string>(RECURSOS_REAIS);

export function ehRecursoReal(resource: NomeRecurso): boolean {
  return CONJUNTO_REAIS.has(resource);
}

/**
 * O que cada recurso real aceita, conforme os endpoints publicados.
 *
 * Existe para o painel recusar a operação com uma frase explicando o
 * porquê, em vez de mandar a requisição e traduzir o 404 do gateway em
 * "Registro não encontrado" — que mandaria o operador procurar um
 * problema de dado onde o problema é de contrato.
 */
const OPERACOES: Record<RecursoReal, Set<string>> = {
  event: new Set(['list', 'get', 'update']),
  sessions: new Set(['list', 'get', 'create', 'update', 'publish', 'archive']),
  speakers: new Set(['list', 'get', 'create', 'update', 'publish', 'archive']),
  spaces: new Set(['list', 'get', 'create', 'update', 'archive']),
  /* Temas são somente leitura nesta etapa: só existe GET /admin/themes. */
  themes: new Set(['list']),
};

const NOME_OPERACAO: Record<string, string> = {
  list: 'listar',
  get: 'abrir',
  create: 'criar',
  update: 'atualizar',
  publish: 'publicar',
  archive: 'arquivar',
};

/**
 * Conferência mínima da resposta do dashboard.
 *
 * O painel prefere falhar a desenhar pela metade — é o mesmo princípio
 * do `conferir()` em `data-service.js`, do chat. Um dashboard "real"
 * que renderiza vazio porque o formato mudou é pior que uma tela de
 * erro: ele parece que funcionou.
 */
function conferirResumo(resumo: unknown): ResumoPainel {
  const candidato = resumo as Partial<ResumoPainel> | null;
  if (!candidato || typeof candidato !== 'object') {
    throw new AdminApiError('desconhecido', 'A API devolveu um dashboard vazio.');
  }
  const faltando: string[] = [];
  if (!Array.isArray(candidato.metricas)) faltando.push('metricas');
  if (!Array.isArray(candidato.pendencias)) faltando.push('pendencias');
  if (!Array.isArray(candidato.alertas)) faltando.push('alertas');
  if (faltando.length) {
    throw new AdminApiError(
      'desconhecido',
      `A resposta de /admin/dashboard não segue o contrato do painel — faltando ${faltando.join(', ')}.`,
    );
  }
  return candidato as ResumoPainel;
}

export class HybridAdminDataProvider implements AdminDataProvider {
  readonly modo = 'hybrid' as const;

  constructor(
    private readonly http: AdminDataProvider,
    private readonly mock: AdminDataProvider,
    /* Ausente, o catálogo fica em memória — nos testes e em build sem
       endereço do Supabase. */
    private readonly catalogo?: AdminDataProvider,
  ) {}

  origemDoRecurso(resource: NomeRecurso): 'http' | 'mock' {
    if (ehRecursoDoCatalogo(resource)) return this.catalogo ? 'http' : 'mock';
    return ehRecursoReal(resource) ? 'http' : 'mock';
  }

  /** Escolhe o destino e, para recurso real, confere se a operação existe. */
  private destino(resource: NomeRecurso, operacao: string): AdminDataProvider {
    if (ehRecursoDoCatalogo(resource)) {
      /* A recusa vale também em demonstração: a tela não pode ensinar um
         botão que a API de verdade não tem. */
      if (!OPERACOES_DO_CATALOGO.has(operacao)) {
        throw new AdminApiError(
          'validacao',
          `O catálogo aceita leitura e edição; ${NOME_OPERACAO[operacao] ?? operacao} produto ainda não existe no painel.`,
        );
      }
      return this.catalogo ?? this.mock;
    }
    if (!ehRecursoReal(resource)) return this.mock;

    const permitidas = OPERACOES[resource as RecursoReal];
    if (!permitidas.has(operacao)) {
      throw new AdminApiError(
        'validacao',
        resource === 'themes'
          ? 'Temas são somente leitura nesta etapa: a API expõe apenas GET /admin/themes.'
          : `A API administrativa não expõe ${NOME_OPERACAO[operacao] ?? operacao} para ${resource} nesta etapa.`,
      );
    }
    return this.http;
  }

  /* ------------------------------------------------------------ */
  /* Visão geral — sempre real                                     */
  /* ------------------------------------------------------------ */

  async getDashboard(): Promise<ResumoPainel> {
    return conferirResumo(await this.http.getDashboard());
  }

  /* ------------------------------------------------------------ */
  /* Leitura                                                       */
  /* ------------------------------------------------------------ */

  /* Os métodos são `async` de propósito: assim a recusa do guard sai
     como promessa rejeitada, igual a qualquer erro de API, e a tela não
     precisa de um caminho especial para erro síncrono. */
  async list<K extends NomeRecurso>(
    resource: K,
    filters?: ListFilters,
  ): Promise<ListResult<MapaRecursos[K]>> {
    return this.destino(resource, 'list').list(resource, filters);
  }

  async get<K extends NomeRecurso>(resource: K, id: string): Promise<MapaRecursos[K]> {
    return this.destino(resource, 'get').get(resource, id);
  }

  /* ------------------------------------------------------------ */
  /* Escrita — real nos módulos reais                              */
  /* ------------------------------------------------------------ */

  async create<K extends NomeRecurso>(
    resource: K,
    payload: Partial<MapaRecursos[K]>,
  ): Promise<MapaRecursos[K]> {
    return this.destino(resource, 'create').create(resource, payload);
  }

  async update<K extends NomeRecurso>(
    resource: K,
    id: string,
    payload: Partial<MapaRecursos[K]>,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    return this.destino(resource, 'update').update(resource, id, payload, opcoes);
  }

  async publish<K extends NomeRecurso>(
    resource: K,
    id: string,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    return this.destino(resource, 'publish').publish(resource, id, opcoes);
  }

  async archive<K extends NomeRecurso>(
    resource: K,
    id: string,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    return this.destino(resource, 'archive').archive(resource, id, opcoes);
  }

  /** Documentos seguem em demonstração — a reindexação também. */
  requestReindex(documentId: string): Promise<ReciboReindexacao> {
    return this.mock.requestReindex(documentId);
  }
}
