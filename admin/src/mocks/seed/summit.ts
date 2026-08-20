/* ============================================================
   SEMENTE — dados/summit.json
   ============================================================
   `../dados/summit.json` é a origem inicial do painel: evento, temas,
   sessões e pessoas saem dele. O arquivo é LIDO, nunca escrito — ele
   pertence ao chat da raiz e continua sendo gerado por
   `scripts/gerar-dados-mindagent.mjs` no repositório do site.

   Aqui o JSON vira o formato administrativo (ids estáveis, espaço como
   entidade própria, status editorial). A conversão é determinística:
   nada de `Math.random()`, para o painel abrir igual em toda sessão e
   os testes poderem afirmar valores. */

import summitJson from '@dados/summit.json';
import type { Espaco, Palestrante, Sessao, Tema } from '@/contracts';
import { TIPOS_SESSAO } from '@/contracts';
import { gerarSlug } from '@/lib/format';

interface SessaoBruta {
  id: string;
  dia: string;
  inicio: string;
  fim: string | null;
  titulo: string;
  descricao: string;
  quem: string;
  espaco: string;
  formato: string;
  etiqueta: string;
  trilhas: string[];
  vaga_limitada: boolean;
  online: boolean;
  temas: string[];
}

interface PessoaBruta {
  nome: string;
  credencial: string;
  resumo: string;
  foto: string;
  destaque: boolean;
  na_grade: boolean;
  temas: string[];
}

interface SummitBruto {
  evento: {
    nome: string;
    dias: string[];
    local: string;
    regra_reserva: string;
    regra_vagas: string;
  };
  temas: { codigo: string; rotulo: string }[];
  sessoes: SessaoBruta[];
  pessoas: PessoaBruta[];
}

export const SUMMIT = summitJson as unknown as SummitBruto;

/** Carimbo fixo dos registros vindos do arquivo: eles não foram editados
 *  no painel, foram importados. */
const IMPORTADO_EM = '2026-08-01T12:00:00.000Z';
const IMPORTADO_POR = 'importação · summit.json';

/* ------------------------------------------------------------------ */
/* Temas                                                               */
/* ------------------------------------------------------------------ */
export const temasSemente: Tema[] = SUMMIT.temas.map((t) => ({
  id: t.codigo,
  codigo: t.codigo,
  rotulo: t.rotulo,
}));

/* ------------------------------------------------------------------ */
/* Espaços                                                             */
/* ------------------------------------------------------------------ */
/** Aliases são como o participante fala, não como o crachá escreve. */
const ALIASES: Record<string, string[]> = {
  'arena-mind': ['palco mind', 'palco principal', 'arena principal'],
  'arena-sextante': ['palco sextante', 'sextante'],
  'sala-masterclass': ['masterclass', 'sala prime'],
  'livraria-da-vila': ['livraria', 'loja de livros'],
  'prime-lounge': ['lounge prime', 'lounge'],
};

const TIPO_POR_ESPACO: Record<string, Espaco['tipo']> = {
  'arena-mind': 'arena',
  'arena-sextante': 'arena',
  'arena-top-voice': 'arena',
  'sala-masterclass': 'sala',
  'sala-workshop-1': 'sala',
  'sala-workshop-2': 'sala',
  'sala-workshop-3': 'sala',
  'livraria-da-vila': 'area_expositiva',
  'prime-lounge': 'lounge',
};

const COMO_CHEGAR: Record<string, string> = {
  'arena-mind':
    'Entrando pelo credenciamento, siga em frente pelo corredor central. A Arena Mind é o palco grande ao fundo, à esquerda.',
  'arena-sextante':
    'Do credenciamento, vire à direita no primeiro corredor. A Arena Sextante fica depois da área de patrocinadores.',
  'sala-workshop-1': 'Corredor lateral esquerdo, primeira porta depois do café.',
  'sala-workshop-2': 'Corredor lateral esquerdo, segunda porta depois do café.',
  'prime-lounge':
    'Mezanino, acesso pela escada ao lado da Arena Mind. Exclusivo para credencial Prime.',
};

const nomesDeEspacos = Array.from(new Set(SUMMIT.sessoes.map((s) => s.espaco))).filter(Boolean);

export const espacosSemente: Espaco[] = nomesDeEspacos.map((nome) => {
  const slug = gerarSlug(nome);
  return {
    id: 'esp_' + slug,
    nome,
    slug,
    tipo: TIPO_POR_ESPACO[slug] ?? 'sala',
    aliases: ALIASES[slug] ?? [],
    descricao: '',
    comoChegar: COMO_CHEGAR[slug] ?? '',
    localPrincipal: 'Pavilhão principal',
    espacoPaiId: null,
    andar: slug === 'prime-lounge' ? 'Mezanino' : 'Térreo',
    coordenadaX: null,
    coordenadaY: null,
    acessivel: true,
    observacaoAcessibilidade: '',
    ativo: true,
    criadoEm: IMPORTADO_EM,
    atualizadoEm: IMPORTADO_EM,
    atualizadoPor: IMPORTADO_POR,
  };
});

/** Coordenadas só para parte dos espaços — o resto fica visível como buraco. */
const COORDENADAS: Record<string, [number, number]> = {
  'esp_arena-mind': [52, 28],
  'esp_arena-sextante': [80, 46],
  'esp_arena-top-voice': [22, 46],
  'esp_sala-workshop-1': [16, 70],
  'esp_sala-workshop-2': [34, 72],
  'esp_sala-masterclass': [68, 70],
  'esp_prime-lounge': [88, 20],
};
for (const espaco of espacosSemente) {
  const par = COORDENADAS[espaco.id];
  if (par) {
    espaco.coordenadaX = par[0];
    espaco.coordenadaY = par[1];
  }
}

const espacoPorNome = new Map(espacosSemente.map((e) => [e.nome, e.id]));

/* ------------------------------------------------------------------ */
/* Palestrantes                                                        */
/* ------------------------------------------------------------------ */
/** `Harvard · Segurança psicológica` → organização + cargo. */
function partirCredencial(credencial: string): { organizacao: string; cargo: string } {
  const partes = credencial
    .split('·')
    .map((p) => p.trim())
    .filter(Boolean);
  if (partes.length >= 2) return { organizacao: partes[0], cargo: partes.slice(1).join(' · ') };
  return { organizacao: partes[0] ?? '', cargo: '' };
}

export const palestrantesSemente: Palestrante[] = SUMMIT.pessoas.map((pessoa, i) => {
  const slug = gerarSlug(pessoa.nome);
  const { organizacao, cargo } = partirCredencial(pessoa.credencial);
  /* Alguns registros ficam fora de "publicado" de propósito: sem conteúdo
     em rascunho o painel não teria o que revisar, e a fila editorial da
     visão geral nasceria vazia. */
  const status: Palestrante['status'] =
    i % 17 === 5 ? 'rascunho' : i % 17 === 11 ? 'em_revisao' : 'publicado';
  return {
    id: 'pal_' + slug,
    nome: pessoa.nome,
    cargo,
    organizacao,
    /* Biografia vazia é pendência real: o card do chat fica sem texto. */
    biografia: i % 13 === 7 ? '' : pessoa.resumo,
    foto: pessoa.foto,
    temas: pessoa.temas,
    destaque: pessoa.destaque,
    sessaoIds: [],
    status,
    publicadoEm: status === 'publicado' ? IMPORTADO_EM : null,
    publicadoPor: status === 'publicado' ? IMPORTADO_POR : null,
    criadoEm: IMPORTADO_EM,
    atualizadoEm: IMPORTADO_EM,
    atualizadoPor: IMPORTADO_POR,
  };
});

const palestrantePorNome = new Map(palestrantesSemente.map((p) => [p.nome.toLowerCase(), p.id]));

/** `Izabella Camargo; Lailson Lima` e `João e Ana` viram lista de ids. */
function ligarPalestrantes(quem: string): string[] {
  if (!quem) return [];
  return quem
    .split(/;| e |,/)
    .map((n) => n.trim().toLowerCase())
    .map((n) => palestrantePorNome.get(n))
    .filter((id): id is string => Boolean(id));
}

/* ------------------------------------------------------------------ */
/* Sessões                                                             */
/* ------------------------------------------------------------------ */
function inferirTipo(bruta: SessaoBruta): Sessao['tipo'] {
  const etiqueta = bruta.etiqueta.toLowerCase();
  if (etiqueta.includes('abertura')) return 'abertura';
  if (etiqueta.includes('lançamento')) return 'lancamento';
  if (etiqueta.includes('autógrafos')) return 'autografos';
  const candidato = TIPOS_SESSAO.find((t) => t === bruta.formato);
  return candidato ?? 'palestra';
}

const CAPACIDADE_POR_ESPACO: Record<string, number> = {
  'esp_sala-workshop-1': 60,
  'esp_sala-workshop-2': 60,
  'esp_sala-workshop-3': 60,
  'esp_sala-masterclass': 90,
  'esp_arena-sextante': 220,
  'esp_arena-top-voice': 180,
};

const TRILHAS_VALIDAS = new Set(['mind', 'vip', 'prime']);

export const sessoesSemente: Sessao[] = SUMMIT.sessoes.map((bruta, i) => {
  /* Duas sessões perdem o espaço de propósito: é a pendência
     "sessões sem espaço" da visão geral, e ela precisa ser real. */
  const espacoId = i % 24 === 13 ? null : espacoPorNome.get(bruta.espaco) ?? null;
  const palestranteIds = ligarPalestrantes(bruta.quem);
  const capacidade = espacoId ? CAPACIDADE_POR_ESPACO[espacoId] ?? null : null;
  const status: Sessao['status'] =
    i % 19 === 4 ? 'rascunho' : i % 19 === 9 ? 'em_revisao' : 'publicado';

  return {
    id: 'ses_' + bruta.id,
    titulo: bruta.titulo,
    descricao: bruta.descricao,
    dia: bruta.dia,
    inicio: bruta.inicio,
    /* Coquetel e autógrafos vêm sem `fim` no arquivo — o painel
       preserva o vazio em vez de arbitrar uma hora de término. */
    fim: bruta.fim ?? null,
    espacoId,
    tipo: inferirTipo(bruta),
    formato: bruta.online ? 'online' : 'presencial',
    trilhas: bruta.trilhas.filter((t): t is Sessao['trilhas'][number] => TRILHAS_VALIDAS.has(t)),
    temas: bruta.temas,
    palestranteIds,
    quemTexto: bruta.quem,
    necessitaReserva: bruta.vaga_limitada,
    vagasTotais: bruta.vaga_limitada ? capacidade : null,
    vagasDisponiveis:
      bruta.vaga_limitada && capacidade ? Math.max(0, capacidade - 12 - (i % 30)) : null,
    nivel: i % 3 === 0 ? 'introdutorio' : i % 3 === 1 ? 'intermediario' : 'avancado',
    resultadosEsperados: [],
    status,
    publicadoEm: status === 'publicado' ? IMPORTADO_EM : null,
    publicadoPor: status === 'publicado' ? IMPORTADO_POR : null,
    criadoEm: IMPORTADO_EM,
    atualizadoEm: IMPORTADO_EM,
    atualizadoPor: IMPORTADO_POR,
  };
});

/* A ligação sessão → palestrante é usada nos dois sentidos na tela. */
for (const sessao of sessoesSemente) {
  for (const palestranteId of sessao.palestranteIds) {
    const palestrante = palestrantesSemente.find((p) => p.id === palestranteId);
    if (palestrante && !palestrante.sessaoIds.includes(sessao.id)) {
      palestrante.sessaoIds.push(sessao.id);
    }
  }
}

export const METADADOS_IMPORTACAO = { IMPORTADO_EM, IMPORTADO_POR };
