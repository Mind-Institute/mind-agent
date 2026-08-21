import { carregarDadosSummit } from './data-service.js';
import { CONFIG as APP_CONFIG } from './config.js';

/* ============================================================
   MIND AGENT — CAMADA DE DADOS DA CENTRAL DO EVENTO
   ============================================================
   Espelha o contrato de `data-service.js` do repositório: quem consome
   chama `carregarCentral()` e recebe sempre a mesma forma. Trocar o
   arquivo local pela API do `mindagent-bootstrap` é preencher
   `CONFIG.apiBaseUrl` — nenhuma linha da tela muda.

   O que JÁ existe no banco (via summit.json / bootstrap):
     evento, temas, sessoes, pessoas
   O que AINDA não existe no contrato e por isso vive em
   `interacoesPrevia()`, isolado e marcado:
     enquetes, avisos, conteudos, avaliacoes, recomendacoes
   Essas cinco listas são de PRÉVIA DE DESIGN — chaveadas por ids reais
   de sessão, prontas para virarem endpoint sem tocar na interface.
*/

export const FUSO = 'America/Sao_Paulo';
export const OFFSET = '-03:00'; // São Paulo não observa horário de verão
export const MIN = 60000;

export const CONFIG = APP_CONFIG;

/* ---------- tempo, sempre no fuso oficial do evento ---------- */
export function ts(dia, hhmm) {
  return new Date(`${dia}T${hhmm}:00${OFFSET}`).getTime();
}
export function hora(t) {
  return new Intl.DateTimeFormat('pt-BR', { timeZone: FUSO, hour: '2-digit', minute: '2-digit' }).format(new Date(t));
}
export function diaCurto(dia) {
  const t = ts(dia, '12:00');
  return new Intl.DateTimeFormat('pt-BR', { timeZone: FUSO, day: '2-digit', month: 'short' })
    .format(new Date(t)).replace('.', '');
}
export function diaLongo(dia) {
  const t = ts(dia, '12:00');
  return new Intl.DateTimeFormat('pt-BR', { timeZone: FUSO, weekday: 'long', day: '2-digit', month: 'long' })
    .format(new Date(t));
}
export function relativo(agora, t) {
  const d = t - agora;
  if (d <= 30000) return 'agora';
  const m = Math.round(d / MIN);
  if (m <= 1) return 'em 1 minuto';
  if (m < 60) return `em ${m} minutos`;
  const h = Math.floor(m / 60);
  const r = m % 60;
  return r ? `em ${h}h${String(r).padStart(2, '0')}` : `em ${h}h`;
}

/* ---------- identidade: vem da Yazo pela URL, nunca é chutada ---------- */
export function lerIdentidade(search, win) {
  const w = win || (typeof window !== 'undefined' ? window : null);
  const q = new URLSearchParams(search != null ? search : (w ? w.location.search : ''));
  let embutido = q.has('yazo') || q.has('iaso') || q.has('embed');
  try { if (w && w.self !== w.top) embutido = true; } catch (e) { embutido = true; }
  const previa = q.get('preview') === '1';
  const trilha = previa ? (q.get('trilha') || 'vip').toLowerCase() : '';
  return {
    nome: previa ? ((q.get('nome') || '').trim() || null) : null,
    email: previa ? (q.get('email') || q.get('e') || null) : null,
    trilha: ['mind', 'vip', 'prime'].indexOf(trilha) >= 0 ? trilha : null,
    embutido,
    previa,
    possuiEmailNaoVerificado: !!(q.get('email') || q.get('e')) && !previa,
  };
}

/* ---------- carga ---------- */
function conferir(d) {
  if (!d || typeof d !== 'object') throw new Error('resposta vazia');
  const faltando = ['temas', 'sessoes', 'pessoas'].filter((k) => !Array.isArray(d[k]));
  if (!d.evento || !Array.isArray(d.evento.dias)) faltando.push('evento.dias');
  if (faltando.length) throw new Error('faltando ' + faltando.join(', '));
  return d;
}

export async function carregarCentral(opcoes) {
  const o = opcoes || {};
  const bruto = o.adaptador
    ? await o.adaptador.carregar({ eventSlug: CONFIG.eventSlug })
    : await carregarDadosSummit();
  return normalizar(conferir(bruto), o.adaptador ? 'adaptador' : (CONFIG.apiBaseUrl ? 'api' : 'arquivo'));
}

export function normalizar(bruto, origem = 'arquivo') {
  const rotuloTema = {};
  bruto.temas.forEach((t) => { rotuloTema[t.codigo] = t.rotulo; });
  const pessoaPorNome = {};
  bruto.pessoas.forEach((p) => { pessoaPorNome[p.nome] = p; });

  const sessoes = bruto.sessoes.map((s) => {
    const inicio = ts(s.dia, s.inicio);
    const fim = s.fim ? ts(s.dia, s.fim) : inicio + 60 * MIN;
    const pessoa = pessoaPorNome[s.quem] || null;
    return {
      id: s.id,
      dia: s.dia,
      inicio,
      fim,
      horaInicio: s.inicio,
      horaFim: s.fim || hora(fim),
      titulo: limparTitulo(s.titulo),
      descricao: s.descricao || '',
      quem: s.quem,
      credencial: pessoa ? pessoa.credencial : '',
      foto: pessoa && pessoa.foto ? `assets/${pessoa.foto}` : null,
      /* O bootstrap manda `espaco: null` em 8 das 67 sessões (credenciamento,
         intervalos). Sem isto o `null` chega inteiro na tela, porque os cards
         interpolam o campo em template string. Mesma frase que a experiência
         clássica usa — dizer que falta, sem inventar sala. */
      espaco: s.espaco || 'Espaço a confirmar',
      formato: s.formato,
      etiqueta: s.etiqueta,
      trilhas: s.trilhas || [],
      vagaLimitada: !!s.vaga_limitada,
      temas: s.temas || [],
      temasRotulos: (s.temas || []).map((c) => rotuloTema[c]).filter(Boolean),
    };
  }).sort((a, b) => a.inicio - b.inicio);

  return {
    origem,
    evento: bruto.evento,
    dias: bruto.evento.dias,
    temas: bruto.temas,
    pessoas: bruto.pessoas,
    sessoes,
  };
}

/* Os títulos do banco usam " . " como separador de subtítulo. */
function limparTitulo(t) {
  return String(t).replace(/\s+\.\s+/g, ' — ').replace(/\s{2,}/g, ' ').trim();
}

/* ---------- perfil ---------- */
export const TRILHAS = { mind: 'Mind', vip: 'VIP', prime: 'Prime' };

const AGENDA_PREVIA = {
  mind: ['d1-09_40-como_bem-estar_afeta_o_b', 'd1-11_30-entre_o_riso_e_o_resulta', 'd1-15_00-quando_mudar_deixa_de_se', 'd1-18_10-o_mito_do_colaborador_re'],
  vip: ['d1-09_40-como_bem-estar_afeta_o_b', 'd1-11_30-decidir_sob_press_o_co', 'd1-15_00-quando_mudar_deixa_de_se', 'd1-18_10-o_mito_do_colaborador_re'],
  prime: ['d1-09_40-como_bem-estar_afeta_o_b', 'd1-11_30-mensurar_intervir_prov', 'd1-15_00-os_tr_s_movimentos_do_l_', 'd1-18_10-o_mito_do_colaborador_re'],
};

/** Perfil de prévia. `nome` só é preenchido se a Yazo mandar — nunca inventado. */
export function perfilPrevia(trilha, identidade) {
  const t = trilha && TRILHAS[trilha] ? trilha : 'vip';
  const id = identidade || {};
  return {
    identificado: !!t,
    nome: id.nome || null,
    email: id.email || null,
    trilha: t,
    trilhaRotulo: TRILHAS[t],
    interesses: ['performance', 'lideranca_humana', 'saude_mental'],
    salvas: AGENDA_PREVIA[t].slice(),
  };
}

export const PERFIL_ANONIMO = {
  identificado: false, nome: null, email: null,
  trilha: null, trilhaRotulo: null, interesses: [], salvas: [],
};

/* ---------- interações (prévia de design — ainda sem endpoint) ---------- */
export function interacoesPrevia(dia) {
  const d = dia;
  const t = (h) => ts(d, h);
  return {
    _previaDeDesign: true,
    enquetes: [{
      id: 'enq-1',
      sessaoId: 'd1-15_00-quando_mudar_deixa_de_se',
      espaco: 'Arena Mind',
      pergunta: 'O que mais trava a adaptação no seu time hoje?',
      opcoes: [
        { id: 'a', rotulo: 'Falta de clareza sobre o rumo' },
        { id: 'b', rotulo: 'Medo de errar em público' },
        { id: 'c', rotulo: 'Sobrecarga de mudanças ao mesmo tempo' },
        { id: 'd', rotulo: 'Pouca autonomia para decidir' },
      ],
      abre: t('15:20'), fecha: t('15:50'),
    }],
    avisos: [{
      id: 'av-1',
      espacos: ['Arena Mind'],
      titulo: 'Arena Mind com casa cheia',
      corpo: 'Chegue com alguns minutos de folga: a fila de espera abre 5 minutos antes de começar.',
      abre: t('14:40'), fecha: t('15:05'),
    }],
    conteudos: [{
      id: 'cont-1',
      sessaoId: 'd1-09_40-como_bem-estar_afeta_o_b',
      tipo: 'slides',
      titulo: 'Slides: Como bem-estar afeta o bottom-line?',
      itens: 3,
      libera: t('11:00'), ate: t('23:30'),
      url: null,
    }, {
      id: 'cont-2',
      sessaoId: 'd1-11_30-decidir_sob_press_o_co',
      tipo: 'material',
      titulo: 'Material do workshop: Decidir sob pressão',
      itens: 2,
      libera: t('13:00'), ate: t('23:30'),
      url: null,
    }],
    avaliacoes: [{
      id: 'av-nps-1', sessaoId: 'd1-09_40-como_bem-estar_afeta_o_b', tipo: 'nps',
      abre: t('10:32'), fecha: t('19:00'),
    }, {
      id: 'av-nps-2', sessaoId: 'd1-11_30-decidir_sob_press_o_co', tipo: 'nps',
      abre: t('12:32'), fecha: t('19:00'),
    }],
    recomendacoes: [{
      id: 'rec-1',
      sessaoId: 'd1-16_00-como_a_consci_ncia_da_fi',
      motivo: 'Combina com o que você salvou em saúde mental e liderança',
      abre: t('13:45'), fecha: t('15:55'),
    }],
  };
}

export function interacoesVazias() {
  return { _previaDeDesign: false, enquetes: [], avisos: [], conteudos: [], avaliacoes: [], recomendacoes: [] };
}

/** Estado local do participante — trocável por persistência real. */
export function estadoInicial() {
  return { votos: {}, notas: {}, salvasExtra: [], vistos: {} };
}
