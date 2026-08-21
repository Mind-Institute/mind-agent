import * as D from './agent-dados.js';
import * as R from './agent-regras.js';
import { PARTICIPANTE, capturarIdentidade, definirParticipante } from './config.js';
import { enviarMensagem } from './chat-service.js';

/* Identificação leve vinda do app do evento (`?email=…&nome=…`), que
   embeda esta página. Personaliza saudação e nada mais: não é a
   identificação segura que libera a jornada pessoal — essa continua
   atrás de `perfil.identificado`. Em `?preview=1` a captura não roda
   (a prévia tem semântica própria em `lerIdentidade`), e ela limpa a
   URL depois de ler — por isso vem antes do `lerIdentidade` de `state`,
   que só usa `?nome`/`?email` no modo prévia, onde a URL fica intacta. */
capturarIdentidade();

const $ = (id) => document.getElementById(id);
const el = (tag, classe, texto) => {
  const node = document.createElement(tag);
  if (classe) node.className = classe;
  if (texto != null) node.textContent = texto;
  return node;
};

const cores = { aviso: '#ff7057', enquete: '#9843ff', proxima: '#68ee95', avaliacao: '#ff7057', conteudo: '#ffffff', recomendacao: '#9843ff' };
const state = {
  dados: null,
  perfil: D.PERFIL_ANONIMO,
  identidade: D.lerIdentidade(),
  interacoes: D.interacoesVazias(),
  estado: D.estadoInicial(),
  dia: null,
  agora: Date.now(),
  relogioReal: true,
  agendaAberta: false,
  aba: 'agora',
  mensagens: [],
  digitando: false,
  interesses: [],
};

let toastTimer = null;
let tickTimer = null;

function minutos(hhmm) {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

function horaMinutos(valor) {
  return `${String(Math.floor(valor / 60)).padStart(2, '0')}:${String(valor % 60).padStart(2, '0')}`;
}

function atualizarDia(dia) {
  state.dia = dia;
  if (!state.relogioReal) {
    const atual = minutos(D.hora(state.agora));
    state.agora = D.ts(dia, horaMinutos(atual));
  }
  state.interacoes = state.identidade.previa ? D.interacoesPrevia(dia) : D.interacoesVazias();
  render();
}

function jornadaAtual() {
  return R.jornada(state.agora, state.dados, state.perfil, state.estado);
}

function resultadoAtual() {
  return R.resolver({ agora: state.agora, dados: state.dados, perfil: state.perfil, interacoes: state.interacoes, estado: state.estado });
}

function mostrarToast(texto) {
  clearTimeout(toastTimer);
  const anterior = document.querySelector('.toast');
  if (anterior) anterior.remove();
  const toast = el('div', 'toast', texto);
  $('cards-area').prepend(toast);
  toastTimer = setTimeout(() => toast.remove(), 3800);
}

function renderDias() {
  const box = $('day-tabs');
  box.replaceChildren();
  state.dados.dias.forEach((dia, indice) => {
    const botao = el('button', dia === state.dia ? 'active' : '', `${indice + 1}º dia · ${D.diaCurto(dia)}`);
    botao.type = 'button';
    botao.role = 'tab';
    botao.ariaSelected = String(dia === state.dia);
    botao.addEventListener('click', () => atualizarDia(dia));
    box.append(botao);
  });
}

function renderStatus(jornada) {
  const area = $('status-area');
  area.replaceChildren();
  if (jornada.atual) {
    const card = el('div', 'current-card');
    if (jornada.atual.foto) {
      const foto = el('img');
      foto.src = jornada.atual.foto;
      foto.alt = '';
      card.append(foto);
    }
    const copy = el('span', 'current-copy');
    const label = el('span', 'current-label');
    label.append(el('i'), document.createTextNode('Acontecendo agora'));
    copy.append(label, el('strong', '', jornada.atual.titulo), el('small', '', `${jornada.atual.espaco} · ${jornada.atual.quem} · até ${jornada.atual.horaFim}`));
    card.append(copy);
    area.append(card);
    return;
  }
  const box = el('div', 'empty-current');
  let titulo = 'Sem atividades a seguir';
  let texto = 'A programação de hoje já foi concluída.';
  if (jornada.antesDeAbrir) {
    titulo = 'O dia começa em breve';
    texto = `A primeira atividade abre às ${jornada.abreEm}.`;
  } else if (jornada.proxima) {
    titulo = jornada.concluidas ? 'Intervalo' : 'Sua jornada começa em seguida';
    texto = `A seguir: ${jornada.proxima.titulo}, ${jornada.proxima.horaInicio}, ${jornada.proxima.espaco}.`;
  }
  box.append(el('span', '', titulo), el('span', '', texto));
  area.append(box);
}

function abrirDetalhe(item) {
  const sessao = state.dados.sessoes.find((s) => s.id === item.id) || item;
  $('detail-label').textContent = sessao.etiqueta || 'Atividade';
  $('detail-title').textContent = sessao.titulo;
  $('detail-line').textContent = `${sessao.horaInicio || D.hora(sessao.inicio)}–${sessao.horaFim || D.hora(sessao.fim)} · ${sessao.espaco} · ${sessao.quem || ''}`;
  $('detail-description').textContent = sessao.descricao || '';
  const tags = $('detail-tags');
  tags.replaceChildren(...(sessao.temasRotulos || []).map((tema) => el('span', '', tema)));
  $('detail-backdrop').hidden = false;
}

function renderAgenda(jornada) {
  $('agenda-label').textContent = state.perfil.identificado ? 'Sua agenda' : 'Programação de hoje';
  const lista = $('agenda-list');
  lista.replaceChildren();
  const itens = state.agendaAberta ? jornada.itens : jornada.itens.slice(0, 4);
  itens.forEach((item) => {
    const botao = el('button', 'agenda-row');
    botao.type = 'button';
    botao.dataset.state = item.estado;
    const copy = el('span');
    copy.append(el('strong', '', item.titulo), el('small', '', `${item.espaco} · ${item.quem}${item.vagaLimitada ? ' · vaga limitada' : ''}`));
    botao.append(el('time', '', item.horaInicio), copy, el('mark', '', item.estado));
    botao.addEventListener('click', () => abrirDetalhe(item));
    lista.append(botao);
  });
  const toggle = $('agenda-toggle');
  toggle.hidden = jornada.itens.length <= 4;
  toggle.textContent = state.agendaAberta ? 'Ver menos' : `Ver a jornada inteira · ${jornada.itens.length}`;
}

function executarAcao(card, acao) {
  if (acao.id === 'onde') {
    abrirChat(`Como chego na ${(card.sessao && card.sessao.espaco) || 'arena'}?`);
  } else if (acao.id === 'detalhes') {
    abrirDetalhe(card.sessao);
  } else if (acao.id === 'salvar' && card.sessao) {
    if (!state.estado.salvasExtra.includes(card.sessao.id)) state.estado.salvasExtra.push(card.sessao.id);
    mostrarToast('Atividade salva na sua jornada.');
    render();
  } else if (acao.id === 'abrir-conteudo') {
    mostrarToast('Abrindo o material no app do Summit.');
  }
}

function renderEnquete(card, article) {
  if (!card.enquete) return;
  const opcoes = el('div', 'poll-options');
  card.enquete.opcoes.forEach((opcao) => {
    const selecionada = card.enquete.escolhida === opcao.id;
    const botao = el('button', selecionada ? 'selected' : '', opcao.rotulo);
    botao.type = 'button';
    botao.disabled = card.enquete.travada;
    botao.addEventListener('click', () => {
      if (state.estado.votos[card.enquete.id]) return;
      state.estado.votos[card.enquete.id] = opcao.id;
      render();
      mostrarToast('Voto registrado. Obrigado por participar.');
    });
    opcoes.append(botao);
  });
  article.append(opcoes);
}

function renderNps(card, article) {
  if (!card.nps) return;
  const notas = el('div', 'nps-options');
  for (let nota = 0; nota <= 10; nota += 1) {
    const botao = el('button', card.nps.nota === nota ? 'selected' : '', String(nota));
    botao.type = 'button';
    botao.setAttribute('aria-label', `Nota ${nota}`);
    botao.addEventListener('click', () => {
      state.estado.notas[card.nps.sessaoId] = { nota, em: state.agora };
      render();
      mostrarToast('Avaliação registrada.');
    });
    notas.append(botao);
  }
  article.append(notas);
}

function cardDestaque(card) {
  const article = el('article', 'feature-card');
  article.style.setProperty('--card-color', cores[card.tipo] || '#68ee95');
  const head = el('div', 'card-head');
  head.append(el('i', 'card-dot'), el('span', 'card-label', card.etiqueta));
  if (card.selo) head.append(el('span', 'card-seal', card.selo));
  const body = el('div', 'feature-body');
  const copy = el('span');
  copy.append(el('h2', '', card.titulo));
  if (card.corpo) copy.append(el('p', '', card.corpo));
  body.append(copy);
  if (card.sessao && card.sessao.foto) {
    const foto = el('img');
    foto.src = card.sessao.foto;
    foto.alt = '';
    body.append(foto);
  }
  article.append(head, body);
  if (card.meta && card.meta.length) article.append(el('span', 'card-meta', card.meta.join(' · ')));
  renderEnquete(card, article);
  renderNps(card, article);
  if (card.motivo) article.append(el('p', 'card-meta', card.motivo));
  if (card.acoes && card.acoes.length) {
    const acoes = el('div', 'card-actions');
    card.acoes.forEach((acao) => {
      const botao = el('button', acao.tipo === 'primaria' ? '' : 'secondary', acao.rotulo);
      botao.type = 'button';
      botao.addEventListener('click', () => executarAcao(card, acao));
      acoes.append(botao);
    });
    article.append(acoes);
  }
  return article;
}

function cardCompacto(card) {
  const botao = el('button', 'compact-card');
  botao.type = 'button';
  botao.style.setProperty('--card-color', cores[card.tipo] || '#68ee95');
  const copy = el('span');
  copy.append(el('span', 'card-label', card.etiqueta), el('strong', '', card.titulo), el('small', '', (card.meta || []).join(' · ')));
  botao.append(el('i', 'card-dot'), copy, el('b', '', '→'));
  botao.addEventListener('click', () => abrirDetalhe(card.sessao || card));
  return botao;
}

function renderCards(resultado) {
  const area = $('cards-area');
  area.replaceChildren();
  const itens = state.aba === 'conteudos' ? resultado.conteudos : resultado.visiveis;
  if (!itens.length) {
    const vazio = el('div', 'empty-cards');
    const imagem = el('img');
    imagem.src = './assets/simbolo-mind-verde.png';
    imagem.alt = '';
    const conteudo = state.aba === 'conteudos';
    vazio.append(imagem, el('span', 'eyebrow', conteudo ? 'Nada liberado ainda' : 'Nada exigindo sua atenção'), el('h2', '', conteudo ? 'O material chega aqui' : 'Sua jornada está em dia'), el('p', '', conteudo ? 'Slides e materiais aparecem depois que forem publicados.' : 'Avisos oficiais, próximas atividades e interações aparecem aqui no momento certo.'));
    area.append(vazio);
    return;
  }
  area.append(cardDestaque(itens[0]));
  itens.slice(1).forEach((card) => area.append(cardCompacto(card)));
  if (state.aba === 'agora' && resultado.espera) area.append(el('small', 'card-meta', `Mais ${resultado.espera} card(s) em espera.`));
}

function render() {
  if (!state.dados) return;
  const jornada = jornadaAtual();
  const resultado = resultadoAtual();
  renderDias();
  renderStatus(jornada);
  renderAgenda(jornada);
  renderCards(resultado);
  $('progress-label').textContent = state.perfil.identificado ? 'Sua jornada de hoje' : 'Programação oficial';
  $('progress-value').textContent = `${jornada.concluidas}/${jornada.total} · ${jornada.percentual}% do dia`;
  $('progress-bar').style.width = `${jornada.percentual}%`;
  $('anonymous-note').hidden = state.perfil.identificado;
  $('chat-status').textContent = resultado.espacoProvavel ? `Com você na ${resultado.espacoProvavel}` : 'Responde na hora';
  $('event-footer').textContent = `${state.dados.evento.nome} · ${D.diaCurto(state.dados.dias[0])}–${D.diaCurto(state.dados.dias[1])} · ${state.dados.evento.local}`;
  [...$('content-tabs').querySelectorAll('button')].forEach((button) => button.classList.toggle('active', button.dataset.tab === state.aba));
  if (!state.relogioReal) {
    $('preview-badge').hidden = false;
    $('preview-badge').textContent = `Prévia · ${D.diaCurto(state.dia)} ${D.hora(state.agora)}`;
  }
}

function mensagem(de, texto) {
  const node = el('div', `message ${de}`, texto);
  $('chat-messages').append(node);
  $('chat-messages').scrollTop = $('chat-messages').scrollHeight;
}

function renderDigitando(ativo) {
  const existente = $('chat-messages').querySelector('.typing');
  if (existente) existente.remove();
  if (!ativo) return;
  const box = el('div', 'typing');
  box.append(el('i'), el('i'), el('i'));
  $('chat-messages').append(box);
  $('chat-messages').scrollTop = $('chat-messages').scrollHeight;
}

async function enviarChat(texto) {
  const limpo = String(texto || '').trim();
  if (!limpo || state.digitando) return;
  mensagem('user', limpo);
  $('chat-input').value = '';
  state.digitando = true;
  $('chat-input').disabled = true;
  $('chat-form').querySelector('button').disabled = true;
  renderDigitando(true);
  try {
    const resposta = await enviarMensagem(limpo);
    renderDigitando(false);
    mensagem('agent', resposta.answer);
    if (Array.isArray(resposta.interests)) {
      state.interesses = resposta.interests;
      if (state.perfil.identificado) state.perfil.interesses = [...new Set([...state.perfil.interesses, ...resposta.interests.map((i) => i.key).filter(Boolean)])];
    }
  } catch (erro) {
    renderDigitando(false);
    mensagem('agent', erro.name === 'AbortError' ? 'A resposta demorou demais. Tente novamente.' : erro.message);
  } finally {
    state.digitando = false;
    $('chat-input').disabled = false;
    $('chat-form').querySelector('button').disabled = false;
    $('chat-input').focus();
  }
}

function abrirChat(pergunta) {
  $('chat-overlay').hidden = false;
  if (!state.mensagens.length) {
    state.mensagens.push(true);
    const nome = state.perfil.nome || PARTICIPANTE.nome;
    mensagem('agent', (nome ? `Oi, ${nome}! ` : '') + 'Estou acompanhando a programação oficial do Summit. O que você precisa?');
  }
  if (pergunta) setTimeout(() => enviarChat(pergunta), 120);
  else $('chat-input').focus();
}

function fecharChat() {
  $('chat-overlay').hidden = true;
  $('chat-open').focus();
}

function configurarChat() {
  const sugestoes = ['Minha próxima atividade', 'Onde fica a Arena Mind?', 'Qual é a programação?', 'Como funciona a reserva?'];
  sugestoes.forEach((texto) => {
    const botao = el('button', '', texto);
    botao.type = 'button';
    botao.addEventListener('click', () => enviarChat(texto));
    $('suggestions').append(botao);
  });
  $('chat-open').addEventListener('click', () => abrirChat());
  $('chat-close').addEventListener('click', fecharChat);
  $('chat-form').addEventListener('submit', (event) => {
    event.preventDefault();
    enviarChat($('chat-input').value);
  });
}

function configurarSheets() {
  $('detail-close').addEventListener('click', () => { $('detail-backdrop').hidden = true; });
  $('detail-backdrop').addEventListener('click', (event) => { if (event.target === $('detail-backdrop')) $('detail-backdrop').hidden = true; });
  $('help-open').addEventListener('click', () => {
    /* O jeito de conferir, dentro do app, qual identidade chegou pela URL —
       textContent de propósito: nome e e-mail vêm de fora, nunca viram HTML. */
    $('ajuda-identidade').textContent = PARTICIPANTE.email
      ? 'Identificado pelo app do evento: ' +
        (PARTICIPANTE.nome ? PARTICIPANTE.nome + ' — ' : '') + PARTICIPANTE.email
      : 'Este dispositivo ainda não foi identificado pelo app do evento.';
    $('help-backdrop').hidden = false;
  });
  $('help-close').addEventListener('click', () => { $('help-backdrop').hidden = true; });
  $('help-backdrop').addEventListener('click', (event) => { if (event.target === $('help-backdrop')) $('help-backdrop').hidden = true; });
}

function configurarAbas() {
  $('content-tabs').addEventListener('click', (event) => {
    const button = event.target.closest('button[data-tab]');
    if (!button) return;
    state.aba = button.dataset.tab;
    render();
  });
  $('agenda-toggle').addEventListener('click', () => {
    state.agendaAberta = !state.agendaAberta;
    render();
  });
}

function boasVindas() {
  let visto = false;
  try { visto = localStorage.getItem('mind-agent:boas-vindas:v2') === '1'; } catch { visto = false; }
  if (visto || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const modal = $('welcome');
  const nome = state.perfil.nome || PARTICIPANTE.nome;
  const falas = [nome ? `Olá, ${nome}.` : 'Bem-vindo ao Mind Summit.', 'Sou a Mind. Fico com você nos dois dias.', 'Sempre que precisar, me chame aqui embaixo.'];
  modal.hidden = false;
  let passo = 0;
  const intervalo = setInterval(() => {
    passo += 1;
    $('welcome-copy').textContent = falas.slice(0, passo + 1).join(' ');
    if (passo >= falas.length - 1) clearInterval(intervalo);
  }, 1450);
  const fechar = () => {
    clearInterval(intervalo);
    modal.hidden = true;
    try { localStorage.setItem('mind-agent:boas-vindas:v2', '1'); } catch { /* sem persistência */ }
  };
  $('welcome-skip').onclick = fechar;
  setTimeout(fechar, 4900);
}

function configurarPreview() {
  if (!state.identidade.previa) return;
  $('simulation').hidden = false;
  $('simulation-toggle').addEventListener('click', () => { $('simulation-panel').hidden = !$('simulation-panel').hidden; });
  const range = $('simulation-range');
  range.value = String(minutos(D.hora(state.agora)));
  range.addEventListener('input', () => {
    state.relogioReal = false;
    state.agora = D.ts(state.dia, horaMinutos(Number(range.value)));
    $('simulation-clock').textContent = D.hora(state.agora);
    render();
  });
  R.CENARIOS.forEach((cenario) => {
    const botao = el('button', '', cenario.rotulo);
    botao.type = 'button';
    botao.addEventListener('click', () => {
      state.relogioReal = false;
      state.agora = D.ts(state.dia, cenario.hora);
      range.value = String(minutos(cenario.hora));
      $('simulation-clock').textContent = cenario.hora;
      render();
    });
    $('simulation-scenarios').append(botao);
  });
  $('rules-test').addEventListener('click', () => {
    const resultado = R.testes(state.dados);
    $('rules-result').textContent = `${resultado.passou}/${resultado.total} regras validadas`;
    $('rules-result').style.color = resultado.passou === resultado.total ? '#68ee95' : '#ff7057';
  });
}

async function iniciar() {
  configurarChat();
  configurarSheets();
  configurarAbas();
  $('status-area').append(el('div', 'skeleton'));
  try {
    state.dados = await D.carregarCentral();
    state.dia = state.dados.dias[0];
    if (state.identidade.previa) {
      state.perfil = D.perfilPrevia(state.identidade.trilha || 'vip', state.identidade);
      state.interacoes = D.interacoesPrevia(state.dia);
      state.relogioReal = false;
      state.agora = D.ts(state.dia, '14:55');
    }
    configurarPreview();
    render();
    boasVindas();
    tickTimer = setInterval(() => {
      if (!state.relogioReal) return;
      state.agora = Date.now();
      render();
    }, 15000);
  } catch (erro) {
    const area = $('status-area');
    area.replaceChildren();
    const card = el('div', 'error-card');
    card.append(el('span', '', 'Não foi possível carregar'), el('strong', '', 'Não conseguimos carregar a programação agora.'), el('small', '', erro.message));
    const tentar = el('button', 'retry-button', 'Tentar novamente');
    tentar.type = 'button';
    tentar.addEventListener('click', () => location.reload());
    card.append(tentar);
    area.append(card);
  }
}

/* O app do evento também pode mandar a identidade depois do load —
   mesma regra da URL: identifica a pessoa, não autentica. */
window.addEventListener('message', (event) => {
  const d = event.data;
  if (d && d.tipo === 'mindagent:identidade') definirParticipante(d);
});

window.addEventListener('beforeunload', () => clearInterval(tickTimer));
iniciar();
