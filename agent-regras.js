/* ============================================================
   MIND AGENT — CAMADA DE REGRAS DA CENTRAL DO EVENTO
   ============================================================
   Única responsável por decidir o que aparece na tela em cada instante.
   Recebe: horário atual, dados do Summit, perfil e interações.
   Devolve: cards ativos com prioridade, ordem, estado, início, expiração
   e ações — mais a jornada do dia e a aba de conteúdos.
   Nenhuma condição de horário deve existir fora deste arquivo.
*/

import { MIN, hora, relativo, ts, interacoesPrevia, perfilPrevia, PERFIL_ANONIMO } from './agent-dados.js';

export const PRIORIDADE = { aviso: 1, enquete: 2, proxima: 3, avaliacao: 4, conteudo: 5, recomendacao: 6 };

export const MAX_CARDS = 3;          // destaque + 2 (decisão do produto)
const ANTECEDENCIA = 10 * MIN;       // "próxima atividade" entra 10 min antes
const RESERVA_CAI = 5 * MIN;         // regra_reserva do evento
const ENQUETE_FIM = 3 * MIN;         // encerrada segue visível por 3 min
const CONTEUDO_FRESCO = 45 * MIN;    // depois disso vive só na aba Conteúdos

function porId(dados, id) { return dados.sessoes.find((s) => s.id === id) || null; }

export function agendaDoPerfil(dados, perfil) {
  const salvas = perfil.salvas.concat(perfil.salvasExtra || []);
  return dados.sessoes.filter((s) => salvas.indexOf(s.id) >= 0);
}

export function grade(dados, perfil) {
  if (!perfil.identificado) return dados.sessoes;
  return dados.sessoes.filter((s) => s.trilhas.indexOf(perfil.trilha) >= 0);
}

export function diaDe(agora, dados) {
  const achou = dados.dias.find((d) => agora >= ts(d, '00:00') && agora <= ts(d, '23:59'));
  return achou || dados.dias[0];
}

/** Espaço em que o participante provavelmente está. */
export function espacoProvavel(agora, dados, perfil) {
  const minha = agendaDoPerfil(dados, perfil);
  const dentro = minha.find((s) => agora >= s.inicio - 5 * MIN && agora <= s.fim + 10 * MIN);
  if (dentro) return dentro.espaco;
  const aCaminho = minha.filter((s) => s.inicio > agora).sort((a, b) => a.inicio - b.inicio)[0];
  if (aCaminho && aCaminho.inicio - agora <= 15 * MIN) return aCaminho.espaco;
  return null;
}

export function conteudoLiberado(c, agora) {
  return !!c && agora >= c.libera && agora <= c.ate;
}

/* ---------------- jornada ---------------- */
export function jornada(agora, dados, perfil, estado) {
  const dia = diaDe(agora, dados);
  const doDia = (perfil.identificado ? agendaDoPerfil(dados, perfil) : grade(dados, perfil))
    .filter((s) => s.dia === dia);
  const st = estado || {};
  const salvas = perfil.salvas.concat(st.salvasExtra || []);

  const itens = doDia.map((s) => {
    let estadoItem = 'agendada';
    if (agora > s.fim) estadoItem = 'encerrada';
    else if (agora >= s.inicio) estadoItem = 'acontecendo';
    else if (s.inicio - agora <= ANTECEDENCIA) estadoItem = 'começando';
    return {
      id: s.id,
      titulo: s.titulo,
      quem: s.quem,
      espaco: s.espaco,
      etiqueta: s.etiqueta,
      foto: s.foto,
      horaInicio: hora(s.inicio),
      horaFim: hora(s.fim),
      inicio: s.inicio,
      fim: s.fim,
      salva: salvas.indexOf(s.id) >= 0,
      vagaLimitada: s.vagaLimitada,
      estado: estadoItem,
      relativo: agora < s.inicio ? relativo(agora, s.inicio) : '',
    };
  });

  const gradeDoDia = grade(dados, perfil).filter((s) => s.dia === dia);
  const abre = gradeDoDia.length ? gradeDoDia[0].inicio : ts(dia, '09:00');
  const fecha = gradeDoDia.length ? gradeDoDia[gradeDoDia.length - 1].fim : ts(dia, '19:00');

  return {
    dia,
    itens,
    atual: itens.find((i) => agora >= i.inicio && agora <= i.fim) || null,
    proxima: itens.find((i) => i.inicio > agora) || null,
    concluidas: itens.filter((i) => agora > i.fim).length,
    total: itens.length,
    percentual: Math.max(0, Math.min(100, Math.round(((agora - abre) / (fecha - abre)) * 100))),
    antesDeAbrir: agora < abre,
    depoisDeFechar: agora > fecha,
    abreEm: hora(abre),
    fechaEm: hora(fecha),
  };
}

/* ---------------- cards ---------------- */
export function resolver(ctx) {
  const agora = ctx.agora;
  const dados = ctx.dados;
  const perfil = ctx.perfil || PERFIL_ANONIMO;
  const inter = ctx.interacoes || { enquetes: [], avisos: [], conteudos: [], avaliacoes: [], recomendacoes: [] };
  const estado = ctx.estado || { votos: {}, notas: {}, salvasExtra: [] };
  const identificado = !!perfil.identificado;
  const espaco = espacoProvavel(agora, dados, perfil);
  const minha = agendaDoPerfil(dados, perfil);
  const salvas = minha.map((s) => s.id);
  const cards = [];

  const proximaSalva = minha.filter((s) => s.inicio > agora).sort((a, b) => a.inicio - b.inicio)[0] || null;
  const espacosRelevantes = [espaco, proximaSalva ? proximaSalva.espaco : null].filter(Boolean);

  /* 1 — Aviso importante. Vem de duas fontes: avisos publicados e a
        regra de reserva do próprio evento (cai 5 min antes). */
  (inter.avisos || []).forEach((a) => {
    if (agora < a.abre || agora > a.fecha) return;
    const noEscopo = !a.espacos || !a.espacos.length || a.espacos.some((e) => espacosRelevantes.indexOf(e) >= 0);
    if (!noEscopo) return;
    cards.push({
      id: a.id, tipo: 'aviso', prioridade: PRIORIDADE.aviso, estado: 'ativo',
      etiqueta: 'Aviso importante', titulo: a.titulo, corpo: a.corpo,
      meta: [`Vale até ${hora(a.fecha)}`],
      abre: a.abre, expira: a.fecha,
      acoes: [{ id: 'onde', rotulo: 'Como chegar', tipo: 'primaria' }],
    });
  });

  if (identificado) {
    minha.filter((s) => s.vagaLimitada).forEach((s) => {
      const de = s.inicio - ANTECEDENCIA;
      const ate = s.inicio - RESERVA_CAI;
      if (agora < de || agora > ate) return;
      cards.push({
        id: `reserva-${s.id}`, tipo: 'aviso', prioridade: PRIORIDADE.aviso, estado: 'ativo',
        etiqueta: 'Aviso importante',
        titulo: `Sua reserva cai às ${hora(ate)}`,
        corpo: `${dados.evento.regra_reserva} Você tem reserva em ${s.espaco}.`,
        meta: [s.espaco, `Começa ${relativo(agora, s.inicio)}`],
        abre: de, expira: ate,
        sessao: resumo(s),
        acoes: [{ id: 'onde', rotulo: 'Como chegar', tipo: 'primaria' }],
      });
    });
  }

  /* 2 — Enquete do espaço em que a pessoa provavelmente está */
  (inter.enquetes || []).forEach((e) => {
    if (agora < e.abre || agora > e.fecha + ENQUETE_FIM) return;
    if (!espaco || e.espaco !== espaco) return;
    const voto = estado.votos[e.id];
    const encerrada = agora > e.fecha;
    const s = porId(dados, e.sessaoId);
    cards.push({
      id: e.id, tipo: 'enquete', prioridade: PRIORIDADE.enquete,
      estado: encerrada ? 'encerrada' : voto ? 'respondida' : 'aberta',
      etiqueta: 'Enquete do palco',
      titulo: encerrada ? 'Enquete encerrada' : voto ? 'Voto registrado' : 'Participe agora',
      corpo: e.pergunta,
      meta: [e.espaco, encerrada ? `Encerrada às ${hora(e.fecha)}` : `Aberta até ${hora(e.fecha)}`],
      abre: e.abre, expira: e.fecha + ENQUETE_FIM,
      enquete: { id: e.id, opcoes: e.opcoes, escolhida: voto || null, travada: !!voto || encerrada },
      sessao: s ? resumo(s) : null,
      acoes: [],
    });
  });

  /* 3 — Próxima atividade → vira "acontecendo agora" quando começa */
  if (identificado) {
    minha.forEach((s) => {
      const de = s.inicio - ANTECEDENCIA;
      if (agora < de || agora > s.fim) return;
      const rodando = agora >= s.inicio;
      cards.push({
        id: `prox-${s.id}`, tipo: 'proxima', prioridade: PRIORIDADE.proxima,
        estado: rodando ? 'acontecendo' : 'a caminho',
        etiqueta: rodando ? 'Acontecendo agora' : 'Próxima atividade',
        titulo: s.titulo,
        corpo: `Com ${s.quem}`,
        meta: rodando
          ? [`Até ${hora(s.fim)}`, s.espaco]
          : [`Começa ${relativo(agora, s.inicio)}`, s.espaco],
        abre: de, expira: s.fim,
        sessao: resumo(s),
        acoes: rodando
          ? [{ id: 'detalhes', rotulo: 'Ver detalhes', tipo: 'fantasma' }]
          : [{ id: 'onde', rotulo: 'Como chegar', tipo: 'primaria' }, { id: 'detalhes', rotulo: 'Ver detalhes', tipo: 'fantasma' }],
      });
    });
  }

  /* 4 — Avaliação: editável até a janela fechar */
  if (identificado) {
    (inter.avaliacoes || []).forEach((a) => {
      const s = porId(dados, a.sessaoId);
      if (!s || salvas.indexOf(s.id) < 0) return;
      if (agora < a.abre || agora > a.fecha) return;
      const resposta = estado.notas[a.sessaoId];
      cards.push({
        id: a.id, tipo: 'avaliacao', prioridade: PRIORIDADE.avaliacao,
        estado: resposta ? 'enviada' : 'disponível',
        etiqueta: 'Sua opinião',
        selo: `Encerrada · ${hora(s.fim)}`,
        titulo: `Quanto você recomendaria “${s.titulo.replace(/[?.!]+$/, '')}”?`,
        corpo: resposta ? 'Nota registrada. Você pode mudar enquanto a avaliação estiver aberta.' : '',
        meta: [s.espaco, `Aberta até ${hora(a.fecha)}`],
        abre: a.abre, expira: a.fecha,
        nps: { sessaoId: a.sessaoId, nota: resposta ? resposta.nota : null, editavel: true },
        sessao: resumo(s),
        acoes: [],
      });
    });
  }

  /* 5 — Conteúdo liberado: fica na central enquanto é novidade,
        depois vive na aba Conteúdos */
  const conteudos = [];
  if (identificado) {
    (inter.conteudos || []).forEach((c) => {
      const s = porId(dados, c.sessaoId);
      if (!s || salvas.indexOf(s.id) < 0) return;
      if (!conteudoLiberado(c, agora)) return;
      const item = {
        id: c.id, tipo: 'conteudo', prioridade: PRIORIDADE.conteudo, estado: 'liberado',
        etiqueta: 'Conteúdo liberado após a palestra',
        selo: `Disponível · ${String(c.itens).padStart(2, '0')}`,
        titulo: c.titulo, corpo: `Com ${s.quem}`,
        meta: [`Liberado às ${hora(c.libera)}`, s.espaco],
        abre: c.libera, expira: c.ate,
        conteudo: { id: c.id, url: c.url, liberado: true },
        sessao: resumo(s),
        acoes: [{ id: 'abrir-conteudo', rotulo: 'Acessar', tipo: 'primaria' }],
      };
      conteudos.push(item);
      if (agora <= c.libera + CONTEUDO_FRESCO) cards.push(item);
    });
  }

  /* 6 — Recomendação pelos interesses */
  if (identificado) {
    (inter.recomendacoes || []).forEach((r) => {
      const s = porId(dados, r.sessaoId);
      if (!s || salvas.indexOf(s.id) >= 0) return;
      if (s.trilhas.indexOf(perfil.trilha) < 0) return;
      if (agora < r.abre || agora > Math.min(r.fecha, s.inicio - 15 * MIN)) return;
      if (!s.temas.some((t) => perfil.interesses.indexOf(t) >= 0)) return;
      cards.push({
        id: r.id, tipo: 'recomendacao', prioridade: PRIORIDADE.recomendacao, estado: 'ativa',
        etiqueta: 'Recomendação pelos seus interesses',
        titulo: s.titulo,
        corpo: `${s.etiqueta} com ${s.quem}`,
        meta: [`${hora(s.inicio)} – ${hora(s.fim)}`, s.espaco],
        motivo: r.motivo,
        abre: r.abre, expira: r.fecha,
        sessao: resumo(s),
        acoes: [{ id: 'salvar', rotulo: 'Salvar na jornada', tipo: 'primaria' }, { id: 'detalhes', rotulo: 'Ver detalhes', tipo: 'fantasma' }],
      });
    });
  }

  const ordenados = cards
    .filter((c) => !estado.vistos || !estado.vistos[c.id])
    .sort((a, b) => (a.prioridade - b.prioridade) || (a.expira - b.expira));

  return {
    todos: ordenados,
    visiveis: ordenados.slice(0, MAX_CARDS),
    espera: Math.max(0, ordenados.length - MAX_CARDS),
    conteudos,
    espacoProvavel: espaco,
  };
}

function resumo(s) {
  return {
    id: s.id, titulo: s.titulo, quem: s.quem, credencial: s.credencial, foto: s.foto,
    espaco: s.espaco, etiqueta: s.etiqueta, horaInicio: hora(s.inicio), horaFim: hora(s.fim),
    descricao: s.descricao, temasRotulos: s.temasRotulos,
  };
}

/* ---------------- cenários e testes das regras temporais ---------------- */
export const CENARIOS = [
  { id: 1, rotulo: 'Faltam 10 min', hora: '14:50' },
  { id: 2, rotulo: 'Acontecendo agora', hora: '15:12' },
  { id: 3, rotulo: 'Enquete no palco', hora: '15:25' },
  { id: 4, rotulo: 'Aviso de acesso', hora: '14:45' },
  { id: 5, rotulo: 'Reserva caindo', hora: '11:22' },
  { id: 6, rotulo: 'Conteúdo liberado', hora: '11:05' },
  { id: 7, rotulo: 'Avaliação aberta', hora: '12:40' },
  { id: 8, rotulo: 'Vários cards', hora: '14:55' },
  { id: 9, rotulo: 'Nenhum card', hora: '09:20' },
  { id: 10, rotulo: 'Antes de abrir', hora: '07:30' },
];

export function testes(dados) {
  const dia = dados.dias[0];
  const at = (h) => ts(dia, h);
  const perfil = perfilPrevia('vip');
  const inter = interacoesPrevia(dia);
  const base = { dados, perfil, interacoes: inter };
  const tipos = (agora, estado) => resolver(Object.assign({}, base, { agora, estado })).visiveis.map((c) => c.tipo);
  const out = [];
  const ok = (id, nome, esperado, obtido) => out.push({ id, nome, esperado, obtido, passou: esperado === obtido });

  ok(1, 'Faltam 10 min para uma atividade salva', 'próxima presente',
    tipos(at('14:52')).indexOf('proxima') >= 0 ? 'próxima presente' : 'ausente');

  const rodando = resolver(Object.assign({}, base, { agora: at('15:12') })).todos.find((c) => c.tipo === 'proxima');
  ok(2, 'A atividade começou', 'estado acontecendo', rodando ? `estado ${rodando.estado}` : 'card removido');

  ok(3, 'Enquete ativa no palco provável', 'enquete presente',
    tipos(at('15:25')).indexOf('enquete') >= 0 ? 'enquete presente' : 'ausente');

  ok(4, 'Aviso importante tem prioridade 1', 'aviso primeiro',
    resolver(Object.assign({}, base, { agora: at('14:45') })).visiveis[0].tipo === 'aviso' ? 'aviso primeiro' : 'outro card');

  ok(5, 'Regra de reserva vira aviso 10 min antes', 'aviso de reserva',
    resolver(Object.assign({}, base, { agora: at('11:22') })).todos.some((c) => c.id.indexOf('reserva-') === 0)
      ? 'aviso de reserva' : 'ausente');

  ok(6, 'Conteúdo aparece só depois de liberado', 'liberado 11:05, bloqueado 10:55',
    `${conteudoLiberado(inter.conteudos[0], at('11:05')) ? 'liberado 11:05' : 'bloqueado 11:05'}, ${conteudoLiberado(inter.conteudos[0], at('10:55')) ? 'liberado 10:55' : 'bloqueado 10:55'}`);

  ok(7, 'Avaliação abre após o encerramento', 'avaliação presente',
    tipos(at('12:40')).indexOf('avaliacao') >= 0 ? 'avaliação presente' : 'ausente');

  const comNota = { votos: {}, notas: { 'd1-09_40-como_bem-estar_afeta_o_b': { nota: 9, em: at('12:40') } }, salvasExtra: [] };
  const av = resolver(Object.assign({}, base, { agora: at('12:45'), estado: comNota })).todos.find((c) => c.tipo === 'avaliacao');
  ok(8, 'Nota enviada continua editável até fechar', 'enviada e editável',
    av && av.estado === 'enviada' && av.nps.editavel ? 'enviada e editável' : 'estado inesperado');

  const muitos = resolver(Object.assign({}, base, { agora: at('14:55') }));
  ok(9, 'Vários cards: no máximo 3 e por prioridade', 'no máximo 3, ordenados',
    muitos.visiveis.length <= 3 && muitos.visiveis.every((c, i, arr) => i === 0 || arr[i - 1].prioridade <= c.prioridade)
      ? 'no máximo 3, ordenados' : 'fora da regra');

  ok(10, 'Nenhum card ativo', 'zero cards',
    resolver(Object.assign({}, base, { agora: at('09:20') })).visiveis.length === 0 ? 'zero cards' : 'cards presentes');

  const anon = resolver({ agora: at('14:52'), dados, perfil: PERFIL_ANONIMO, interacoes: inter, estado: { votos: {}, notas: {} } });
  ok(11, 'Participante não identificado', 'sem cards personalizados',
    anon.visiveis.some((c) => ['proxima', 'avaliacao', 'conteudo', 'recomendacao'].indexOf(c.tipo) >= 0)
      ? 'vazou card pessoal' : 'sem cards personalizados');

  const comVoto = { votos: { 'enq-1': 'b' }, notas: {}, salvasExtra: [] };
  const enq = resolver(Object.assign({}, base, { agora: at('15:25'), estado: comVoto })).todos.find((c) => c.tipo === 'enquete');
  ok(12, 'Voto duplicado bloqueado', 'travado', enq && enq.enquete.travada ? 'travado' : 'permitido');

  ok(13, 'Fuso oficial do evento', '15:00', hora(at('15:00')));

  ok(14, 'Conteúdo sai da central e fica na aba', 'só na aba',
    (() => {
      const r = resolver(Object.assign({}, base, { agora: at('12:30') }));
      const naCentral = r.todos.some((c) => c.id === 'cont-1');
      const naAba = r.conteudos.some((c) => c.id === 'cont-1');
      return !naCentral && naAba ? 'só na aba' : `central:${naCentral} aba:${naAba}`;
    })());

  return { resultados: out, passou: out.filter((r) => r.passou).length, total: out.length };
}
