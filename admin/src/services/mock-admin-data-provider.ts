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
  type StatusEditorial,
} from '@/contracts';
import { criarBanco, type BancoMock } from '@/mocks/db';
import type { AdminDataProvider, ContextoAutor } from './admin-data-provider';

/** Campos varridos pela busca textual de cada recurso. */
const CAMPOS_BUSCA: Record<NomeRecurso, string[]> = {
  products: ['codigo', 'nome', 'descricaoCurta', 'descricao'],
  admins: ['nome', 'email'],
  summit_2026_sessions: ['titulo', 'descricao', 'espaco', 'palestrantes'],
};

/* O que o banco preenche ao criar, para a linha nova aparecer inteira na
   tela. Dar acesso manda só e-mail e papel; o resto vem do Mind ID. */
const PADRAO_AO_CRIAR: Partial<Record<NomeRecurso, Record<string, unknown>>> = {
  admins: { mindId: null, nome: null, ativo: true, loginLigado: false, ultimoLoginEm: null },
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
  const doRegistro = valorDoCampo(registro, chave);
  if (Array.isArray(valor)) {
    if (valor.length === 0) return true;
    return valor.some((v) => combinaFiltro(registro, chave, v));
  }
  if (Array.isArray(doRegistro)) return doRegistro.map(String).includes(String(valor));
  if (typeof doRegistro === 'boolean') return String(doRegistro) === String(valor);
  if (doRegistro === null || doRegistro === undefined) return String(valor) === 'null';
  return String(doRegistro) === String(valor);
}

/* A mesma comparação da `mindagent-catalogo`, para a demonstração ordenar
   como o banco: vazio no fim nos dois sentidos, instante como instante
   (fusos diferentes) e texto no alfabeto do português. */
const INSTANTE = /^\d{4}-\d{2}-\d{2}T/;

function vazio(valor: unknown): boolean {
  return valor === null || valor === undefined || valor === '';
}

function comparar(a: unknown, b: unknown): number {
  if (typeof a === 'string' && typeof b === 'string' && INSTANTE.test(a) && INSTANTE.test(b)) {
    const ta = Date.parse(a);
    const tb = Date.parse(b);
    if (!Number.isNaN(ta) && !Number.isNaN(tb)) return ta === tb ? 0 : ta < tb ? -1 : 1;
  }
  return String(a).localeCompare(String(b), 'pt-BR');
}

function ordenarItens<T>(itens: T[], ordenar?: string): T[] {
  if (!ordenar) return itens;
  const desc = ordenar.startsWith('-');
  const campo = desc ? ordenar.slice(1) : ordenar;
  return [...itens].sort((a, b) => {
    const va = valorDoCampo(a, campo);
    const vb = valorDoCampo(b, campo);
    if (vazio(va) || vazio(vb)) return vazio(va) === vazio(vb) ? 0 : vazio(va) ? 1 : -1;
    return comparar(va, vb) * (desc ? -1 : 1);
  });
}

export interface OpcoesMock {
  /** Latência simulada em ms. Os testes usam 0. */
  latenciaMs?: number;
  autor?: ContextoAutor;
  banco?: BancoMock;
}

export class MockAdminDataProvider implements AdminDataProvider {
  readonly modo = 'mock' as const;

  origemDoRecurso(): 'mock' {
    return 'mock';
  }

  readonly banco: BancoMock;
  private latenciaMs: number;
  private autor: ContextoAutor;
  private falhas = new Map<string, CodigoErroAdmin>();
  private sequencia = 0;

  constructor(opcoes: OpcoesMock = {}) {
    this.banco = opcoes.banco ?? criarBanco();
    this.latenciaMs = opcoes.latenciaMs ?? 260;
    this.autor = opcoes.autor ?? { nome: 'Você (demonstração)' };
  }

  /* -------------------------------------------------------------- */
  /* Instrumentação para testes e para o menu "simular erro"          */
  /* -------------------------------------------------------------- */

  /** `configurarFalha('products', 'rede')` faz a próxima leitura falhar. */
  configurarFalha(escopo: NomeRecurso, codigo: CodigoErroAdmin | null) {
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

  private verificarFalha(escopo: NomeRecurso) {
    const codigo = this.falhas.get(escopo);
    if (!codigo) return;
    const mensagens: Record<CodigoErroAdmin, string> = {
      rede: 'Não foi possível falar com a API administrativa.',
      sem_permissao: 'Seu papel não permite acessar estes dados.',
      sessao_expirada: 'Sua sessão expirou. Entre novamente.',
      credenciais_invalidas: 'E-mail ou senha incorretos.',
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
      ...PADRAO_AO_CRIAR[resource],
      ...(payload as Record<string, unknown>),
      id: `${resource.slice(0, 3)}_novo_${String(tabela.length + 1).padStart(3, '0')}`,
      criadoEm: agora,
      atualizadoEm: agora,
      atualizadoPor: this.autor.nome,
    } as MapaRecursos[K];

    tabela.unshift(registro);
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

    Object.assign(registro, payload, {
      atualizadoEm: this.agora(),
      atualizadoPor: this.autor.nome,
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

    const agora = this.agora();
    Object.assign(registro, {
      status: 'publicado' satisfies StatusEditorial,
      publicadoEm: agora,
      publicadoPor: this.autor.nome,
      atualizadoEm: agora,
      atualizadoPor: this.autor.nome,
    });

    return { ...(registro as MapaRecursos[K]) };
  }

  /**
   * Arquivar é o "excluir" do painel. O registro continua no banco e sai
   * das listagens ativas — apagar de verdade não é oferecido nesta
   * versão, de propósito.
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

    if ('status' in registro) registro.status = 'arquivado';
    if ('ativo' in registro) registro.ativo = false;

    Object.assign(registro, { atualizadoEm: this.agora(), atualizadoPor: this.autor.nome });
    return { ...(registro as MapaRecursos[K]) };
  }
}
