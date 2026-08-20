/* ============================================================
   HybridAdminDataProvider — meio caminho, dito em voz alta
   ============================================================
   A visão geral já vem do backend real. Os cadastros ainda são
   simulados. Essa mistura é a coisa mais perigosa do painel: quem olha
   um número real e edita um registro falso na mesma tela precisa saber
   qual é qual.

   Por isso o modo é `hybrid` e não `http`, a faixa do topo diz
   "Dashboard real · Cadastros em demonstração", e a listagem continua
   com a mesma marcação de demonstração de antes.

   Nesta etapa NENHUMA escrita vai para o backend. Criar, atualizar,
   publicar, arquivar e reindexar mexem só no banco em memória. */

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
  const faltando: string[] = [];
  if (!candidato || typeof candidato !== 'object') {
    throw new AdminApiError('desconhecido', 'A API devolveu um dashboard vazio.');
  }
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
    /** Backend real. Hoje serve só o dashboard. */
    private readonly http: AdminDataProvider,
    /** Banco em memória. Serve todo o resto. */
    private readonly mock: AdminDataProvider,
  ) {}

  /* ------------------------------------------------------------ */
  /* Real                                                          */
  /* ------------------------------------------------------------ */

  async getDashboard(): Promise<ResumoPainel> {
    /* Sem rede de segurança para o mock aqui, de propósito: cair no
       mock em silêncio faria o painel dizer "dashboard real" enquanto
       mostra número inventado. */
    return conferirResumo(await this.http.getDashboard());
  }

  /* ------------------------------------------------------------ */
  /* Demonstração                                                  */
  /* ------------------------------------------------------------ */

  list<K extends NomeRecurso>(
    resource: K,
    filters?: ListFilters,
  ): Promise<ListResult<MapaRecursos[K]>> {
    return this.mock.list(resource, filters);
  }

  get<K extends NomeRecurso>(resource: K, id: string): Promise<MapaRecursos[K]> {
    return this.mock.get(resource, id);
  }

  create<K extends NomeRecurso>(
    resource: K,
    payload: Partial<MapaRecursos[K]>,
  ): Promise<MapaRecursos[K]> {
    return this.mock.create(resource, payload);
  }

  update<K extends NomeRecurso>(
    resource: K,
    id: string,
    payload: Partial<MapaRecursos[K]>,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    return this.mock.update(resource, id, payload, opcoes);
  }

  publish<K extends NomeRecurso>(
    resource: K,
    id: string,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    return this.mock.publish(resource, id, opcoes);
  }

  archive<K extends NomeRecurso>(
    resource: K,
    id: string,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    return this.mock.archive(resource, id, opcoes);
  }

  requestReindex(documentId: string): Promise<ReciboReindexacao> {
    return this.mock.requestReindex(documentId);
  }
}
