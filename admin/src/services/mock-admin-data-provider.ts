/* ============================================================
   MockAdminDataProvider — modo demonstração
   ============================================================
   Lê e escreve no banco em memória de `src/mocks/db.ts`. Recarregar a
   página zera tudo: NADA é persistido, e o painel avisa isso na tela.

   O mock tem duas coisas que um mock preguiçoso não teria, e que os
   testes precisam:

   1. `configurarFalha()` — injeta erro por recurso, para exercitar a
      tela de erro sem depender de rede caída.
   2. controle de concorrência — `atualizadoEmEsperado` de verdade, para
      o aviso de "conflito de atualização" ser testável. */

import {
  AdminApiError,
  type ListFilters,
  type ListResult,
  type MapaRecursos,
  type NomeRecurso,
  type OpcoesEscrita,
  type CodigoErroAdmin,
  type ReciboReindexacao,
  type ResumoPainel,
  type Documento,
  type StatusEditorial,
} from '@/contracts';
import { criarBanco, rotuloDoRegistro, type BancoMock } from '@/mocks/db';
import { montarResumoPainel } from '@/mocks/dashboard';
import type { AdminDataProvider, ContextoAutor } from './admin-data-provider';

/** Campos varridos pela busca textual de cada recurso. */
const CAMPOS_BUSCA: Record<NomeRecurso, string[]> = {
  event: ['nome', 'slug', 'local', 'cidade'],
  sessions: ['titulo', 'descricao', 'quemTexto'],
  speakers: ['nome', 'organizacao', 'cargo', 'biografia'],
  spaces: ['nome', 'slug', 'descricao', 'comoChegar', 'aliases'],
  routes: ['instrucoes'],
  booths: ['nome', 'slug', 'descricao', 'contato'],
  offers: ['codigo', 'nome', 'descricao', 'elegibilidade'],
  content: ['titulo', 'slug', 'conteudo'],
  documents: ['titulo', 'previa', 'urlOrigem'],
  sources: ['nome', 'descricao'],
  conversations: ['assuntos'],
  unanswered: ['pergunta', 'categoriaSugerida', 'responsavel'],
  users: ['nome', 'papel'],
  audit: ['usuario', 'recurso', 'registroRotulo', 'requestId'],
  themes: ['codigo', 'rotulo'],
};

/** Filtro cujo nome na URL difere do campo do registro. */
const ALIAS_FILTRO: Record<string, string> = {
  tema: 'temas',
  palestranteId: 'palestranteIds',
  agente: 'agentes',
  trilha: 'trilhas',
  assunto: 'assuntos',
};

const CHAVES_RESERVADAS = new Set(['busca', 'pagina', 'porPagina', 'ordenar']);

function normalizar(texto: unknown): string {
  return String(texto ?? '')
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toLowerCase();
}

function valorDoCampo(registro: unknown, campo: string): unknown {
  return (registro as Record<string, unknown>)[campo];
}

function combinaBusca(registro: unknown, campos: string[], termo: string): boolean {
  const alvo = normalizar(termo).trim();
  if (!alvo) return true;
  return campos.some((campo) => {
    const valor = valorDoCampo(registro, campo);
    if (Array.isArray(valor)) return valor.some((v) => normalizar(v).includes(alvo));
    return normalizar(valor).includes(alvo);
  });
}

function combinaFiltro(registro: unknown, chave: string, valor: unknown): boolean {
  if (valor === undefined || valor === null || valor === '' || valor === 'todos') return true;
  const campo = ALIAS_FILTRO[chave] ?? chave;
  const doRegistro = valorDoCampo(registro, campo);
  if (Array.isArray(valor)) {
    if (valor.length === 0) return true;
    return valor.some((v) => combinaFiltro(registro, chave, v));
  }
  if (Array.isArray(doRegistro)) return doRegistro.map(String).includes(String(valor));
  if (typeof doRegistro === 'boolean') return String(doRegistro) === String(valor);
  if (doRegistro === null || doRegistro === undefined) return String(valor) === 'null';
  return String(doRegistro) === String(valor);
}

function ordenarItens<T>(itens: T[], ordenar?: string): T[] {
  if (!ordenar) return itens;
  const desc = ordenar.startsWith('-');
  const campo = desc ? ordenar.slice(1) : ordenar;
  return [...itens].sort((a, b) => {
    const va = valorDoCampo(a, campo);
    const vb = valorDoCampo(b, campo);
    if (va === vb) return 0;
    if (va === null || va === undefined) return 1;
    if (vb === null || vb === undefined) return -1;
    const cmp = va > vb ? 1 : -1;
    return desc ? -cmp : cmp;
  });
}

export interface OpcoesMock {
  /** Latência simulada em ms. Os testes usam 0. */
  latenciaMs?: number;
  /** Instante base das sementes que dependem de "agora". */
  agora?: number;
  autor?: ContextoAutor;
  banco?: BancoMock;
}

export class MockAdminDataProvider implements AdminDataProvider {
  readonly modo = 'mock' as const;

  readonly banco: BancoMock;
  private latenciaMs: number;
  private autor: ContextoAutor;
  private falhas = new Map<string, CodigoErroAdmin>();
  private sequencia = 0;

  constructor(opcoes: OpcoesMock = {}) {
    this.banco = opcoes.banco ?? criarBanco(opcoes.agora ?? Date.now());
    this.latenciaMs = opcoes.latenciaMs ?? 260;
    this.autor = opcoes.autor ?? { nome: 'Você (demonstração)' };
  }

  /* -------------------------------------------------------------- */
  /* Instrumentação para testes e para o menu "simular erro"          */
  /* -------------------------------------------------------------- */

  /** `configurarFalha('sessions', 'rede')` faz a próxima leitura falhar. */
  configurarFalha(escopo: NomeRecurso | 'dashboard' | 'reindex', codigo: CodigoErroAdmin | null) {
    if (codigo) this.falhas.set(escopo, codigo);
    else this.falhas.delete(escopo);
  }

  limparFalhas() {
    this.falhas.clear();
  }

  definirAutor(autor: ContextoAutor) {
    this.autor = autor;
  }

  definirLatencia(ms: number) {
    this.latenciaMs = ms;
  }

  private async esperar() {
    if (this.latenciaMs > 0) {
      await new Promise((resolve) => {
        setTimeout(resolve, this.latenciaMs);
      });
    }
  }

  private verificarFalha(escopo: NomeRecurso | 'dashboard' | 'reindex') {
    const codigo = this.falhas.get(escopo);
    if (!codigo) return;
    const mensagens: Record<CodigoErroAdmin, string> = {
      rede: 'Não foi possível falar com a API administrativa.',
      sem_permissao: 'Seu papel não permite acessar estes dados.',
      nao_encontrado: 'Registro não encontrado.',
      conflito: 'O registro mudou desde que esta tela carregou.',
      validacao: 'Os dados enviados foram recusados.',
      indisponivel: 'A API administrativa está indisponível no momento.',
      desconhecido: 'Erro inesperado.',
    };
    throw new AdminApiError(codigo, mensagens[codigo], { requestId: this.proximoRequestId() });
  }

  private proximoRequestId(): string {
    this.sequencia += 1;
    return `req_mock_${String(this.sequencia).padStart(6, '0')}`;
  }

  private agora(): string {
    return new Date().toISOString();
  }

  private tabela<K extends NomeRecurso>(resource: K): MapaRecursos[K][] {
    const tabela = this.banco[resource];
    if (!tabela) {
      throw new AdminApiError('nao_encontrado', `Recurso desconhecido: ${resource}`);
    }
    return tabela as MapaRecursos[K][];
  }

  private encontrar<K extends NomeRecurso>(resource: K, id: string): MapaRecursos[K] {
    const registro = this.tabela(resource).find(
      (item) => (item as { id: string }).id === id,
    );
    if (!registro) {
      throw new AdminApiError('nao_encontrado', `${resource}/${id} não existe.`);
    }
    return registro;
  }

  private conferirConcorrencia(registro: unknown, opcoes?: OpcoesEscrita) {
    const esperado = opcoes?.atualizadoEmEsperado;
    if (!esperado) return;
    const atual = (registro as { atualizadoEm?: string }).atualizadoEm;
    if (atual && atual !== esperado) {
      throw new AdminApiError(
        'conflito',
        'Este registro foi alterado por outra pessoa depois que você abriu a tela.',
        { detalhes: { atualizadoEm: atual }, requestId: this.proximoRequestId() },
      );
    }
  }

  private registrarAuditoria(
    acao: 'criar' | 'atualizar' | 'publicar' | 'arquivar' | 'reindexar',
    recurso: NomeRecurso | 'documents',
    registro: Record<string, unknown>,
    antes: Record<string, unknown> | null,
    depois: Record<string, unknown> | null,
  ) {
    this.banco.audit.unshift({
      id: `aud_mock_${String(this.banco.audit.length + 1).padStart(3, '0')}`,
      usuario: this.autor.nome,
      acao,
      recurso,
      registroId: String(registro.id ?? ''),
      registroRotulo: rotuloDoRegistro(recurso as NomeRecurso, registro),
      antes,
      depois,
      ocorridoEm: this.agora(),
      requestId: this.proximoRequestId(),
    });
  }

  /* -------------------------------------------------------------- */
  /* Leitura                                                         */
  /* -------------------------------------------------------------- */

  async list<K extends NomeRecurso>(
    resource: K,
    filters: ListFilters = {},
  ): Promise<ListResult<MapaRecursos[K]>> {
    await this.esperar();
    this.verificarFalha(resource);

    const campos = CAMPOS_BUSCA[resource] ?? [];
    let itens = this.tabela(resource).filter((item) => {
      if (filters.busca && !combinaBusca(item, campos, String(filters.busca))) return false;
      return Object.entries(filters).every(([chave, valor]) => {
        if (CHAVES_RESERVADAS.has(chave)) return true;
        return combinaFiltro(item, chave, valor);
      });
    });

    itens = ordenarItens(itens, filters.ordenar);

    const total = itens.length;
    const porPagina = Number(filters.porPagina ?? 0) || total || 1;
    const pagina = Number(filters.pagina ?? 1) || 1;
    const inicio = (pagina - 1) * porPagina;

    return {
      itens: itens.slice(inicio, inicio + porPagina).map((item) => ({ ...item })),
      total,
      pagina,
      porPagina,
    };
  }

  async get<K extends NomeRecurso>(resource: K, id: string): Promise<MapaRecursos[K]> {
    await this.esperar();
    this.verificarFalha(resource);
    return { ...this.encontrar(resource, id) };
  }

  async getDashboard(): Promise<ResumoPainel> {
    await this.esperar();
    this.verificarFalha('dashboard');
    return montarResumoPainel(this.banco);
  }

  /* -------------------------------------------------------------- */
  /* Escrita                                                         */
  /* -------------------------------------------------------------- */

  async create<K extends NomeRecurso>(
    resource: K,
    payload: Partial<MapaRecursos[K]>,
  ): Promise<MapaRecursos[K]> {
    await this.esperar();
    this.verificarFalha(resource);

    const agora = this.agora();
    const tabela = this.tabela(resource);
    const registro = {
      ...(payload as Record<string, unknown>),
      id: `${resource.slice(0, 3)}_novo_${String(tabela.length + 1).padStart(3, '0')}`,
      criadoEm: agora,
      atualizadoEm: agora,
      atualizadoPor: this.autor.nome,
    } as MapaRecursos[K];

    tabela.unshift(registro);
    this.registrarAuditoria('criar', resource, registro as Record<string, unknown>, null, {
      ...(payload as Record<string, unknown>),
    });
    return { ...registro };
  }

  async update<K extends NomeRecurso>(
    resource: K,
    id: string,
    payload: Partial<MapaRecursos[K]>,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    await this.esperar();
    this.verificarFalha(resource);

    const registro = this.encontrar(resource, id) as Record<string, unknown>;
    this.conferirConcorrencia(registro, opcoes);

    const antes: Record<string, unknown> = {};
    for (const chave of Object.keys(payload as Record<string, unknown>)) {
      antes[chave] = registro[chave];
    }

    Object.assign(registro, payload, {
      atualizadoEm: this.agora(),
      atualizadoPor: this.autor.nome,
    });

    this.registrarAuditoria('atualizar', resource, registro, antes, {
      ...(payload as Record<string, unknown>),
    });
    return { ...(registro as MapaRecursos[K]) };
  }

  async publish<K extends NomeRecurso>(
    resource: K,
    id: string,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    await this.esperar();
    this.verificarFalha(resource);

    const registro = this.encontrar(resource, id) as Record<string, unknown>;
    this.conferirConcorrencia(registro, opcoes);

    const antes = { status: registro.status as StatusEditorial | undefined };
    const agora = this.agora();
    Object.assign(registro, {
      status: 'publicado' satisfies StatusEditorial,
      publicadoEm: agora,
      publicadoPor: this.autor.nome,
      atualizadoEm: agora,
      atualizadoPor: this.autor.nome,
    });

    this.registrarAuditoria('publicar', resource, registro, antes, { status: 'publicado' });
    return { ...(registro as MapaRecursos[K]) };
  }

  /**
   * Arquivar é o "excluir" do painel. O registro continua no banco, sai
   * das listagens ativas e mantém o rastro na auditoria — apagar de
   * verdade não é oferecido nesta versão, de propósito.
   */
  async archive<K extends NomeRecurso>(
    resource: K,
    id: string,
    opcoes?: OpcoesEscrita,
  ): Promise<MapaRecursos[K]> {
    await this.esperar();
    this.verificarFalha(resource);

    const registro = this.encontrar(resource, id) as Record<string, unknown>;
    this.conferirConcorrencia(registro, opcoes);

    const antes: Record<string, unknown> = {};
    const depois: Record<string, unknown> = {};

    if ('status' in registro) {
      antes.status = registro.status;
      depois.status = 'arquivado';
      registro.status = 'arquivado';
    }
    if ('ativo' in registro) {
      antes.ativo = registro.ativo;
      depois.ativo = false;
      registro.ativo = false;
    }

    Object.assign(registro, { atualizadoEm: this.agora(), atualizadoPor: this.autor.nome });
    this.registrarAuditoria('arquivar', resource, registro, antes, depois);
    return { ...(registro as MapaRecursos[K]) };
  }

  /**
   * Enfileira o documento e diz, em texto, que NÃO indexou.
   *
   * A tentação aqui seria mudar o status para `indexado` e mostrar um
   * "pronto!" — o que faria o painel mentir sobre o estado do agente.
   * O recibo carrega `simulado: true` e a tela repete isso.
   */
  async requestReindex(documentId: string): Promise<ReciboReindexacao> {
    await this.esperar();
    this.verificarFalha('reindex');

    const documento = this.encontrar('documents', documentId) as Documento;
    const statusAnterior = documento.statusIndexacao;

    documento.statusIndexacao = 'na_fila';
    documento.erroIndexacao = null;
    documento.atualizadoEm = this.agora();
    documento.atualizadoPor = this.autor.nome;

    this.registrarAuditoria(
      'reindexar',
      'documents',
      documento as unknown as Record<string, unknown>,
      { statusIndexacao: statusAnterior },
      { statusIndexacao: 'na_fila' },
    );

    return {
      documentoId: documentId,
      statusAnterior,
      statusAtual: 'na_fila',
      enfileiradoEm: this.agora(),
      simulado: true,
      mensagem:
        'Pedido registrado em modo demonstração. Nada foi indexado: o pipeline de indexação vive no backend e ainda não está ligado.',
    };
  }
}
