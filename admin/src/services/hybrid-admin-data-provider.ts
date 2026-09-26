/* ============================================================
   HybridAdminDataProvider — o dado real, dito em voz alta
   ============================================================
   Desde 26/09/2026 o painel mostra só dado real (decisão da Adriana).
   Saíram o evento, a Home V3, a visão geral e os módulos que eram
   demonstração. O que ficou no provedor é o Catálogo
   (`catalogo.produtos`), servido pela `mindagent-catalogo`: lê e edita —
   criar, publicar e arquivar produto não existem por aqui.

   Sem a função do catálogo configurada (os testes e o preview de cada
   versão, que é montado sem as variáveis do Supabase), o catálogo fica
   no banco em memória, e a listagem diz "demonstração" no selo.

   NÃO EXISTE QUEDA PARA O MOCK. Se o recurso real falha, a tela mostra
   o erro. Cair no mock em silêncio faria o painel apresentar dado
   inventado como se fosse do banco — e é justamente o que o projeto
   inteiro existe para não fazer. */

import type {
  ListFilters,
  ListResult,
  MapaRecursos,
  NomeRecurso,
  OpcoesEscrita,
} from '@/contracts';
import { AdminApiError } from '@/contracts';
import type { AdminDataProvider } from './admin-data-provider';

/** Servido pela `mindagent-catalogo`: ler e editar, nada além. */
export const RECURSOS_DO_CATALOGO = ['products'] as const satisfies readonly NomeRecurso[];

const CONJUNTO_CATALOGO = new Set<string>(RECURSOS_DO_CATALOGO);

export function ehRecursoDoCatalogo(resource: NomeRecurso): boolean {
  return CONJUNTO_CATALOGO.has(resource);
}

/**
 * O que a `mindagent-catalogo` aceita.
 *
 * Existe para o painel recusar a operação com uma frase explicando o
 * porquê, em vez de mandar a requisição e traduzir o 404 do gateway em
 * "Registro não encontrado" — que mandaria o operador procurar um
 * problema de dado onde o problema é de contrato.
 */
const OPERACOES_DO_CATALOGO = new Set(['list', 'get', 'update']);

const NOME_OPERACAO: Record<string, string> = {
  list: 'listar',
  get: 'abrir',
  create: 'criar',
  update: 'atualizar',
  publish: 'publicar',
  archive: 'arquivar',
};

export class HybridAdminDataProvider implements AdminDataProvider {
  readonly modo = 'hybrid' as const;

  constructor(
    private readonly mock: AdminDataProvider,
    /* Ausente, o catálogo fica em memória — nos testes e em build sem
       endereço do Supabase. */
    private readonly catalogo?: AdminDataProvider,
  ) {}

  origemDoRecurso(resource: NomeRecurso): 'http' | 'mock' {
    if (ehRecursoDoCatalogo(resource)) return this.catalogo ? 'http' : 'mock';
    return 'mock';
  }

  /** Escolhe o destino e confere se a operação existe. */
  private destino(resource: NomeRecurso, operacao: string): AdminDataProvider {
    if (!ehRecursoDoCatalogo(resource)) return this.mock;
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
}
