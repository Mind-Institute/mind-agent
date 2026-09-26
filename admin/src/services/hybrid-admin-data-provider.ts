/* ============================================================
   HybridAdminDataProvider — o dado real, dito em voz alta
   ============================================================
   Desde 26/09/2026 o painel mostra só dado real (decisão da Adriana).
   Saíram o evento, a Home V3, a visão geral e os módulos que eram
   demonstração. Cada recurso que ficou tem a sua função:

   - o Catálogo (`catalogo.produtos`), na `mindagent-catalogo`: lê e
     edita — criar, publicar e arquivar produto não existem por aqui;
   - os admins do sistema (`mind_admin_users`), na `mindagent-acesso`:
     vê, dá acesso e muda papel ou situação — tirar o acesso é desligar
     a situação, e a linha fica;
   - a programação do Mind Summit 2026 (`summit_2026.sessions`), na
     `mindagent-summit`: só leitura.

   Sem a função configurada (os testes e o preview de cada versão, que é
   montado sem as variáveis do Supabase), o recurso fica no banco em
   memória, e a listagem diz "demonstração" no selo.

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

/** Servido pela `mindagent-acesso`: quem entra no painel. */
export const RECURSOS_DO_ACESSO = ['admins'] as const satisfies readonly NomeRecurso[];

/** Servido pela `mindagent-summit`: as tabelas do Summit, só leitura. */
export const RECURSOS_DO_SUMMIT = ['summit_2026_sessions'] as const satisfies readonly NomeRecurso[];

const CONJUNTO_CATALOGO = new Set<string>(RECURSOS_DO_CATALOGO);
const CONJUNTO_ACESSO = new Set<string>(RECURSOS_DO_ACESSO);
const CONJUNTO_SUMMIT = new Set<string>(RECURSOS_DO_SUMMIT);

/**
 * O que cada função aceita.
 *
 * Existe para o painel recusar a operação com uma frase explicando o
 * porquê, em vez de mandar a requisição e traduzir o 404 do gateway em
 * "Registro não encontrado" — que mandaria o operador procurar um
 * problema de dado onde o problema é de contrato. Recurso novo declara
 * aqui o que a função dele aceita: o tipo não deixa esquecer.
 */
const OPERACOES: Record<NomeRecurso, Set<string>> = {
  products: new Set(['list', 'get', 'update']),
  admins: new Set(['list', 'get', 'create', 'update']),
  summit_2026_sessions: new Set(['list', 'get']),
};

const RECUSA: Record<NomeRecurso, (operacao: string) => string> = {
  products: (op) => `O catálogo aceita leitura e edição; ${op} produto ainda não existe no painel.`,
  admins: (op) =>
    `A lista de admins aceita ver, dar acesso e mudar papel ou situação; ${op} admin não existe no painel.`,
  summit_2026_sessions: (op) =>
    `A programação do Summit 2026 é só leitura no painel; ${op} sessão não existe por aqui.`,
};

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
    /* Ausentes, o recurso fica em memória — nos testes e em build sem
       endereço do Supabase. */
    private readonly catalogo?: AdminDataProvider,
    private readonly acesso?: AdminDataProvider,
    private readonly summit?: AdminDataProvider,
  ) {}

  /** A função real do recurso, quando configurada. */
  private real(resource: NomeRecurso): AdminDataProvider | undefined {
    if (CONJUNTO_CATALOGO.has(resource)) return this.catalogo;
    if (CONJUNTO_ACESSO.has(resource)) return this.acesso;
    if (CONJUNTO_SUMMIT.has(resource)) return this.summit;
    return undefined;
  }

  origemDoRecurso(resource: NomeRecurso): 'http' | 'mock' {
    return this.real(resource) ? 'http' : 'mock';
  }

  /** Escolhe o destino e confere se a operação existe. */
  private destino(resource: NomeRecurso, operacao: string): AdminDataProvider {
    /* A recusa vale também em demonstração: a tela não pode ensinar um
       botão que a API de verdade não tem. */
    if (!OPERACOES[resource].has(operacao)) {
      throw new AdminApiError('validacao', RECUSA[resource](NOME_OPERACAO[operacao] ?? operacao));
    }
    return this.real(resource) ?? this.mock;
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
