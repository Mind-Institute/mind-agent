/* ============================================================
   MIND AGENT — a aplicação
   ============================================================
   Conteúdo nenhum mora aqui: a programação vem de `data-service.js`
   e a identidade de quem está usando vem de `config.js`. Este arquivo
   só desenha e reage.
*/

import { CONFIG, PARTICIPANTE, capturarIdentidade } from './config.js';
import { carregarDadosSummit } from './data-service.js';
import { enviarMensagem } from './chat-service.js';

/* Quem abriu a página, antes de qualquer tela: a Yazo manda `email` e
   `nome` na URL, e a saudação depende disso. Chamada explícita de
   propósito — importar `config.js` não captura nada. */
capturarIdentidade();

/* ---------- Splash ---------- */
const splash = document.getElementById('splash');
function fecharSplash() {
  if (!splash.parentNode) return;
  splash.classList.add('saindo');
  setTimeout(() => splash.remove(), 550);
}
document.getElementById('pular').addEventListener('click', fecharSplash);

/* A fala vem digitada. Cada letra é um span que acende: assim o "Mind" em
   coral atravessa a animação sem precisar recortar HTML no meio. */
const FALA = [
  ['Oi, eu sou o agente do ', false], ['Mind', true],
  [' e estou aqui para responder qualquer dúvida sobre o evento.', false],
];
(function digitar() {
  const alvo = document.getElementById('splash-fala');
  const letras = [];
  FALA.forEach(([texto, forte]) => {
    const pai = forte ? document.createElement('b') : alvo;
    for (const ch of texto) {
      const g = document.createElement('span');
      g.className = 'g'; g.textContent = ch;
      pai.appendChild(g); letras.push(g);
    }
    if (forte) alvo.appendChild(pai);
  });
  const cursor = document.createElement('span');
  cursor.className = 'splash-cursor';
  alvo.appendChild(cursor);

  /* Quanto tempo a frase inteira fica legível antes de a tela sair. Conta
     a partir da última letra; a saída ainda leva os .5s do fade. */
  const LEITURA = 4000;

  if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
    letras.forEach((g) => g.classList.add('on'));
    setTimeout(fecharSplash, LEITURA);
    return;
  }
  const PASSO = 26, ATRASO = 900;
  letras.forEach((g, i) => setTimeout(() => {
    g.classList.add('on');
    g.after(cursor);              /* o cursor anda junto, não fica no fim do texto todo */
  }, ATRASO + i * PASSO));
  setTimeout(fecharSplash, ATRASO + letras.length * PASSO + LEITURA);
})();

/* ---------- Navegação entre vistas ---------- */
const vistas = {
  home: document.getElementById('vista-home'),
  chat: document.getElementById('vista-chat'),
  summit: document.getElementById('vista-summit'),
  tour: document.getElementById('vista-tour'),
};
function abrirVista(nome) {
  Object.entries(vistas).forEach(([n, el]) => el.classList.toggle('ativa', n === nome));
  if (nome === 'chat') iniciarChat();
  if (nome === 'summit') desenharSummit();
}
document.querySelectorAll('[data-volta]').forEach((b) =>
  b.addEventListener('click', () => abrirVista('home'))
);

/* Ajuda (?) */
const ajuda = document.getElementById('ajuda');
document.getElementById('btn-ajuda').addEventListener('click', () => ajuda.classList.add('aberto'));
document.getElementById('fechar-ajuda').addEventListener('click', () => ajuda.classList.remove('aberto'));
ajuda.addEventListener('click', (e) => { if (e.target === ajuda) ajuda.classList.remove('aberto'); });

/* Intenções da home → chat, já no fluxo daquela intenção */
document.getElementById('intencoes').addEventListener('click', (e) => {
  const btn = e.target.closest('button');
  if (!btn) return;
  abrirVista('chat');
  setTimeout(() => abrirIntencao(btn.dataset.intencao), 200);
});
document.getElementById('btn-perfil').addEventListener('click', () => abrirVista('summit'));

/* Campo da home → chat */
const campoHome = document.getElementById('campo-home');

/* Tocar na barra já abre a conversa. Sem isto, quem volta para a home só
   reencontra o histórico mandando outra mensagem — a conversa existe, mas
   fica invisível.

   Trocar de vista e mover o foco acontecem no MESMO evento, de propósito:
   no celular, focar outro campo fora do gesto do usuário fecha o teclado. */
function abrirConversa() {
  if (vistas.chat.classList.contains('ativa')) return;
  const rascunho = campoHome.value;
  campoHome.value = '';
  abrirVista('chat');
  if (rascunho) campoChat.value = rascunho;
  campoChat.focus();
  /* Voltar para a conversa é voltar para o fim dela, não para onde parou
     a rolagem. */
  mensagens.scrollTop = mensagens.scrollHeight;
}

campoHome.addEventListener('focus', abrirConversa);

/* Continua valendo para quem digitar e mandar sem passar pelo foco —
   autofill, teclado físico, automação. */
document.getElementById('form-home').addEventListener('submit', (e) => {
  e.preventDefault();
  const v = campoHome.value.trim();
  campoHome.value = '';
  abrirConversa();
  if (v) setTimeout(() => perguntar(v), 200);
});
document.getElementById('btn-mic').addEventListener('click', () => campoHome.focus());

/* ============================================================
   MOTOR DO TOUR
   Cada tela é a captura real do app; os alvos são posicionados
   em % sobre a foto. Nada avança sozinho: a tela só muda quando
   a pessoa toca no lugar certo — igual ao app de verdade.
   ============================================================ */

/* Onde mora cada captura. A versão publicada usa arquivo; a prévia embutida
   substitui esta função por um mapa de data URIs. */
function TOUR_IMG_SRC(nome) { return './assets/tour/' + nome + '.webp'; }

const ICO = {
  agente: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="5" y="8" width="14" height="10" rx="3"/><path d="M9 8V6M15 8V6M9 2l1.5 2.5M15 2l-1.5 2.5"/><circle cx="9.5" cy="12" r=".9" fill="currentColor"/><circle cx="14.5" cy="12" r=".9" fill="currentColor"/></svg>',
  agenda: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3" y="4" width="18" height="17" rx="3"/><path d="M8 2v4M16 2v4M3 9h18"/></svg>',
  minha:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3" y="4" width="18" height="17" rx="3"/><path d="M8 2v4M16 2v4M3 9h18M8.5 14.5l2.5 2.5 4.5-4.5"/></svg>',
  qr:     '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><path d="M14 14h3v3h-3zM20 14h1M14 20h1M18 18h3v3h-2"/></svg>',
  menu:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M4 6h16M4 12h16M4 18h16"/></svg>',
};

const ABAS = [
  { id: 'agente', rotulo: 'Mind Age…', ico: ICO.agente, folha: 'agente' },
  { id: 'agenda', rotulo: 'Agenda', ico: ICO.agenda, vai: 'agenda' },
  { id: 'minha',  rotulo: 'Minha age…', ico: ICO.minha, vai: 'minha-agenda' },
  { id: 'qr',     rotulo: 'QR Code', ico: ICO.qr, vai: 'qrcode' },
  { id: 'menu',   rotulo: 'Menu', ico: ICO.menu, vai: 'menu' },
];

/* Popups do app, refeitos em HTML */
const FOLHAS = {
  agente: { titulo: 'Mind Agent', texto: 'Oi! É aqui que eu moro dentro do app. Me chame para dúvidas do evento, sugestão de conteúdo, bios de palestrantes e logística.', botao: 'Legal!' },
  notificacoes: { titulo: 'Notificações', itens: [
      ['A Arena Mind abre em 15 minutos', 'Keynote de abertura · 09:15'],
      ['Sua reserva foi confirmada', 'Da mensuração ao PGR · Sala Workshop 2 · 11:30'],
    ], botao: 'Fechar' },
  contato: { titulo: 'Solicitação enviada', texto: 'Quando a pessoa aceitar, ela entra em Contatos. Enquanto isso fica em Pendentes.', botao: 'Entendi' },
  comousar: { titulo: 'Como usar o mapa', texto: 'Use os filtros para ver só arenas, estandes ou lounges. Toque num espaço para ver o que acontece nele.', botao: 'Entendi' },
  logout: { titulo: 'É só uma demonstração', texto: 'Aqui você sairia da sua conta. Neste tour, ninguém sai de lugar nenhum. 🙂', botao: 'Voltar ao tour' },
  reservado: { titulo: 'Lugar reservado!', texto: 'Faça o check-in até o início da sessão para garantir sua vaga. A reserva é exclusiva por horário.', botao: 'Combinado' },
};

/* As telas do app. x/y/w/h em % da foto. `serve` explica para que a tela
   existe e fica sempre visível no alto. */
const TELAS = {
  'agenda': {
    img: 'agenda', aba: 'agenda', rotulo: 'Agenda',
    serve: 'Toda a programação dos dias 16 e 17, por horário e arena. É aqui que você escolhe o que assistir.',
    alvos: [
      { id: 'topo', x: 88, y: 2.2, w: 22, h: 4.5, brinde: 'Filtre por trilha, arena ou só os seus favoritos.' },
      { id: 'card1', x: 50, y: 19.9, w: 92, h: 26, brinde: 'Cada card é uma sessão. Toque para abrir.' },
      { id: 'card', x: 50, y: 56.8, w: 92, h: 29, vai: 'detalhe', modo: 'push',
        dica: 'Agora toque na <b>sessão</b> para abrir os detalhes.' },
      { id: 'coracao', x: 88.6, y: 46, w: 14, h: 5.5, faz: 'favoritar', missao: 'm1',
        dica: 'Toque no <b>coração</b> para salvar esta sessão na sua agenda.',
        brinde: 'Salvo em Minha agenda 💚' },
    ],
  },
  'detalhe': {
    img: 'detalhe', aba: 'agenda', volta: 'agenda', rotulo: 'Sessão',
    serve: 'A página da sessão: descrição, horário, local, palestrantes e a reserva, quando a vaga é limitada.',
    alvos: [
      { id: 'voltar', x: 7.7, y: 2.2, w: 12, h: 4.5, volta: true },
      { id: 'calendario', x: 44, y: 67, w: 70, h: 4.5, brinde: 'Exporta a sessão para o calendário do seu celular.' },
      { id: 'coracao', x: 88.6, y: 72, w: 14, h: 5, faz: 'favoritar', missao: 'm1', brinde: 'Salvo em Minha agenda 💚' },
      { id: 'reservar', x: 49.8, y: 85.9, w: 90, h: 6, faz: 'reservar', missao: 'm2', vai: 'confirmada', modo: 'troca',
        folha: 'reservado', dica: 'Esta sessão tem vaga limitada. Toque em <b>Reservar lugar</b>.' },
    ],
  },
  'confirmada': {
    img: 'confirmada', aba: 'agenda', volta: 'agenda', rotulo: 'Sessão reservada',
    serve: 'Sua vaga está garantida. Faça o check-in até o início da sessão para não perder o lugar.',
    alvos: [
      { id: 'voltar', x: 7.7, y: 2.2, w: 12, h: 4.5, volta: true },
      { id: 'coracao', x: 88.6, y: 68.9, w: 14, h: 5, faz: 'favoritar', missao: 'm1', brinde: 'Salvo em Minha agenda 💚' },
      { id: 'aviso', x: 50, y: 81.5, w: 90, h: 10, brinde: 'O check-in é feito aqui mesmo, no dia da sessão.' },
      { id: 'cancelar', x: 49.8, y: 95.6, w: 90, h: 6, brinde: 'Aqui você cancelaria — deixa reservado. 🙂' },
    ],
  },
  'minha-agenda': {
    img: 'minha-agenda', aba: 'minha', rotulo: 'Minha agenda',
    serve: 'O que você salvou e reservou, em ordem de horário. A sessão reservada agora aparece aqui.',
    alvos: [
      { id: 'nova', x: 78, y: 2.2, w: 34, h: 5, brinde: 'Dá para montar mais de uma agenda.' },
      { id: 'chip16', x: 11.2, y: 20.2, w: 15, h: 10, brinde: 'Você já está no dia 16.' },
      { id: 'chip17', x: 30.3, y: 20.2, w: 15, h: 10, vai: 'minha-agenda-17', modo: 'troca',
        dica: 'Toque em <b>17 Set</b> para ver o outro dia.' },
      { id: 'card', x: 50, y: 49.6, w: 92, h: 32, vai: 'confirmada', modo: 'push',
        brinde: 'É a sessão que você acabou de reservar.' },
      { id: 'card2', x: 50, y: 87, w: 92, h: 24, brinde: 'Sessões salvas no coração também entram aqui.' },
    ],
  },
  'minha-agenda-17': {
    img: 'minha-agenda-17', aba: 'minha', rotulo: 'Minha agenda · dia 17',
    serve: 'O filtro de dia troca a lista sem perder nada: cada dia mostra o que você salvou para ele.',
    alvos: [
      { id: 'chip16', x: 11.2, y: 20.2, w: 15, h: 10, vai: 'minha-agenda', modo: 'troca',
        brinde: 'E volta para o dia 16.' },
      { id: 'card', x: 50, y: 49.6, w: 92, h: 32, brinde: 'Coração cheio: sessão salva por você.' },
    ],
  },
  'qrcode': {
    img: 'qrcode', aba: 'qr', rotulo: 'QR Code',
    serve: 'Sua credencial de entrada e seu cartão de visita: quem escaneia seu código vê o seu perfil.',
    alvos: [
      { id: 'escanear', x: 49.8, y: 95.1, w: 90, h: 6, vai: 'scanner', modo: 'push',
        dica: 'Toque em <b>Escanear Qr Code</b> para ler o código de alguém.' },
    ],
  },
  'scanner': {
    img: 'scanner', aba: 'qr', volta: 'qrcode', rotulo: 'Leitor de QR',
    serve: 'Aponte para o QR Code de outra pessoa: o contato entra direto na sua rede.',
    alvos: [
      { id: 'meuqr', x: 49.8, y: 95.1, w: 90, h: 6, volta: true, dica: 'Toque em <b>Meu Qr Code</b> para voltar.' },
    ],
  },
  'menu': {
    img: 'menu', aba: 'menu', rotulo: 'Menu',
    serve: 'O resto do app: rede, palestrantes, avisos, chat, QR Code e o mapa do evento.',
    alvos: [
      { id: 'perfil', x: 30, y: 11.5, w: 56, h: 7, brinde: 'Em Editar Perfil você põe foto e cargo.' },
      { id: 'qrmini', x: 89, y: 11.5, w: 14, h: 7, vai: 'qrcode', modo: 'troca' },
      { id: 'rede', x: 25, y: 25.6, w: 42, h: 11, vai: 'rede', modo: 'push', dica: 'Abra a <b>Área de network</b>.' },
      { id: 'palestrantes', x: 75, y: 25.6, w: 42, h: 11, vai: 'palestrantes', modo: 'push', dica: 'Abra <b>Palestrantes</b>.' },
      { id: 'notificacoes', x: 25, y: 39, w: 42, h: 11, folha: 'notificacoes' },
      { id: 'chat', x: 75, y: 39, w: 42, h: 11, vai: 'chat', modo: 'push', dica: 'Abra o <b>Chat</b> — é onde eu fico.' },
      { id: 'qrtile', x: 25, y: 52.3, w: 42, h: 11, vai: 'qrcode', modo: 'troca' },
      { id: 'mapa', x: 75, y: 52.3, w: 42, h: 11, vai: 'mapa', modo: 'push', dica: 'Abra o <b>Mapa do evento</b>.' },
      { id: 'logout', x: 50, y: 90.6, w: 90, h: 5, folha: 'logout' },
    ],
  },
  'mapa': {
    img: 'mapa', aba: 'menu', volta: 'menu', rotulo: 'Mapa do evento',
    serve: 'Arenas, lounges, estandes e banheiros do Pavilhão 3 — com filtro por tipo de espaço.',
    alvos: [
      { id: 'voltar', x: 7.7, y: 2.2, w: 12, h: 4.5, volta: true, dica: 'Toque em <b>‹</b> para voltar ao Menu.' },
      { id: 'filtros', x: 50, y: 38.3, w: 92, h: 6, brinde: 'Filtre por arenas, estandes ou lounges.' },
      { id: 'comousar', x: 17, y: 93, w: 30, h: 6, folha: 'comousar' },
    ],
  },
  'rede': {
    img: 'rede', aba: 'menu', volta: 'menu', rotulo: 'Área de network',
    serve: 'Quem está no evento. Envie convite, acompanhe contatos aceitos e pedidos pendentes.',
    alvos: [
      { id: 'voltar', x: 7.7, y: 2.2, w: 12, h: 4.5, volta: true, dica: 'Toque em <b>‹</b> para voltar ao Menu.' },
      { id: 'abas', x: 50, y: 8.4, w: 70, h: 5, brinde: 'Contatos aceitos e convites pendentes.' },
      { id: 'add1', x: 81.4, y: 27.1, w: 24, h: 6, faz: 'contato', missao: 'm6', folha: 'contato',
        dica: 'Toque em <b>Adicionar</b> para enviar um convite de contato.' },
    ],
  },
  'palestrantes': {
    img: 'palestrantes', aba: 'menu', volta: 'menu', rotulo: 'Palestrantes',
    serve: 'Todos os nomes do Summit, com bio e sessões. O coração salva quem você quer ver.',
    alvos: [
      { id: 'voltar', x: 7.7, y: 2.2, w: 12, h: 4.5, volta: true, dica: 'Toque em <b>‹</b> para voltar ao Menu.' },
      { id: 'busca', x: 50, y: 9, w: 88, h: 6, brinde: 'Busque pelo nome de quem você quer ver.' },
      { id: 'fav1', x: 88.6, y: 18.7, w: 14, h: 6, faz: 'favoritar', brinde: 'Palestrante salvo 💚' },
    ],
  },
  'chat': {
    img: 'chat', aba: 'menu', volta: 'menu', rotulo: 'Chat',
    serve: 'Converse com quem você conheceu no evento — e comigo, o Mind Agent.',
    alvos: [
      { id: 'voltar', x: 7.7, y: 2.2, w: 12, h: 4.5, volta: true },
      { id: 'nova', x: 91.7, y: 9.2, w: 12, h: 6, brinde: 'Comece uma conversa nova.' },
      { id: 'conversa', x: 50, y: 43.7, w: 92, h: 8, brinde: 'Abre a conversa com a pessoa.' },
    ],
  },
};

/* Como se chega em cada tela (para calcular a dica) */
const ROTA = {
  'agenda': { aba: 'agenda' },
  'minha-agenda': { aba: 'minha' },
  'qrcode': { aba: 'qr' },
  'menu': { aba: 'menu' },
  'detalhe': { de: 'agenda', alvo: 'card' },
  'confirmada': { de: 'detalhe', alvo: 'reservar' },
  'minha-agenda-17': { de: 'minha-agenda', alvo: 'chip17' },
  'scanner': { de: 'qrcode', alvo: 'escanear' },
  'mapa': { de: 'menu', alvo: 'mapa' },
  'rede': { de: 'menu', alvo: 'rede' },
  'palestrantes': { de: 'menu', alvo: 'palestrantes' },
  'chat': { de: 'menu', alvo: 'chat' },
};

const MISSOES = [
  { id: 'm1', txt: 'Salvar uma sessão na sua agenda', tela: 'agenda', alvo: 'coracao' },
  { id: 'm2', txt: 'Reservar seu lugar na sessão', tela: 'detalhe', alvo: 'reservar' },
  { id: 'm3', txt: 'Ver a sua agenda pessoal', tela: 'minha-agenda' },
  { id: 'm4', txt: 'Abrir o seu QR Code', tela: 'qrcode' },
  { id: 'm5', txt: 'Ver o mapa do evento', tela: 'mapa' },
  { id: 'm6', txt: 'Adicionar um contato', tela: 'rede', alvo: 'add1' },
  { id: 'm7', txt: 'Falar com o Mind Agent no Chat', tela: 'chat' },
];

const frame = document.getElementById('frame');
const conteudo = document.getElementById('conteudo');
const telaImg = document.getElementById('tela-img');
const balao = document.getElementById('balao');
const rotulo = document.getElementById('rotulo');
const brinde = document.getElementById('brinde');
const fnav = document.getElementById('fnav');
const folhaFundo = document.getElementById('folha-fundo');
const folhaEl = document.getElementById('folha');
const missaoTexto = document.getElementById('missao-texto');
const missaoProg = document.getElementById('missao-prog');

const fone = document.getElementById('fone');
const palco = document.querySelector('.t-palco');
const PROPORCAO = 780 / 1570;

/* O "telefone" ocupa o máximo possível do palco sem deformar */
function medirFone() {
  const r = palco.getBoundingClientRect();
  if (!r.width || !r.height) return;
  const largura = Math.min(r.width, r.height * PROPORCAO);
  fone.style.width = largura + 'px';
  fone.style.height = (largura / PROPORCAO) + 'px';
}
addEventListener('resize', medirFone);

let telaAtual = 'agenda';
let pilha = [];
let feitas = new Set();
const marcas = {};
let timerBrinde;

/* --- barra de abas (HTML de verdade) --- */
ABAS.forEach((aba) => {
  const b = document.createElement('button');
  b.type = 'button';
  b.dataset.aba = aba.id;
  b.innerHTML = aba.ico + '<span>' + aba.rotulo + '</span>';
  b.addEventListener('click', () => {
    if (aba.folha) { abrirFolha(aba.folha); return; }
    if (TELAS[telaAtual].aba === aba.id && !TELAS[telaAtual].volta) { avisar('Você já está aqui.'); return; }
    pilha = [];
    irPara(aba.vai, 'troca');
  });
  fnav.appendChild(b);
});

function avisar(txt) {
  brinde.textContent = txt;
  brinde.classList.add('on');
  clearTimeout(timerBrinde);
  timerBrinde = setTimeout(() => brinde.classList.remove('on'), 2600);
}

function abrirFolha(nome) {
  const f = FOLHAS[nome];
  if (!f) return;
  folhaEl.innerHTML =
    '<h3>' + f.titulo + '</h3>' +
    (f.texto ? '<p>' + f.texto + '</p>' : '') +
    (f.itens ? '<ul>' + f.itens.map((i) => '<li><b>' + i[0] + '</b>' + i[1] + '</li>').join('') + '</ul>' : '') +
    '<button type="button">' + f.botao + '</button>';
  folhaEl.querySelector('button').addEventListener('click', () => folhaFundo.classList.remove('aberta'));
  folhaFundo.classList.add('aberta');
}
folhaFundo.addEventListener('click', (e) => { if (e.target === folhaFundo) folhaFundo.classList.remove('aberta'); });

/* --- qual é a próxima ação? --- */
function missaoAtual() { return MISSOES.find((m) => !feitas.has(m.id)); }

function calcularDica() {
  const m = missaoAtual();
  if (!m) return null;
  if (telaAtual === m.tela) return m.alvo ? { alvo: m.alvo } : null;
  let destino = m.tela;
  for (let i = 0; i < 6; i++) {
    const r = ROTA[destino];
    if (!r) return null;
    if (r.aba) return { aba: r.aba };
    if (r.de === telaAtual) return { alvo: r.alvo };
    destino = r.de;
  }
  return null;
}

/* --- desenha a tela atual --- */
function pintar(modo) {
  const tela = TELAS[telaAtual];
  telaImg.src = TOUR_IMG_SRC(tela.img);
  telaImg.alt = 'Tela ' + telaAtual + ' do app';

  conteudo.querySelectorAll('.alvo, .marca').forEach((el) => el.remove());

  const dica = calcularDica();

  (tela.alvos || []).forEach((a) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'alvo';
    b.dataset.id = a.id;
    b.style.left = a.x + '%';
    b.style.top = a.y + '%';
    b.style.width = a.w + '%';
    b.style.height = a.h + '%';
    b.setAttribute('aria-label', (a.dica || a.brinde || a.id).replace(/<[^>]+>/g, ''));
    if (dica && dica.alvo === a.id) {
      b.classList.add('dica');
      if (a.w > 40 || a.h > 12) b.classList.add('largo');
    }
    b.addEventListener('click', (e) => { e.stopPropagation(); tocar(a); });
    conteudo.appendChild(b);
  });

  /* marcas já conquistadas nesta tela */
  const m = marcas[telaAtual] || {};
  Object.entries(m).forEach(([id, tipo]) => {
    const alvo = (tela.alvos || []).find((a) => a.id === id);
    if (!alvo) return;
    const el = document.createElement('span');
    el.className = 'marca ' + tipo;
    el.style.left = alvo.x + '%';
    el.style.top = alvo.y + '%';
    if (tipo === 'pendente') { el.style.width = alvo.w + '%'; el.style.height = (alvo.h * 0.86) + '%'; }
    if (tipo === 'coracao') {
      el.innerHTML = '<svg viewBox="0 0 24 24" fill="#68ee95"><path d="M12 21s-7.5-4.8-9.5-9A5.4 5.4 0 0 1 12 6.4 5.4 5.4 0 0 1 21.5 12c-2 4.2-9.5 9-9.5 9z"/></svg>';
    } else {
      el.textContent = 'Pendente';
    }
    conteudo.appendChild(el);
  });

  /* para que serve esta tela — sempre visível */
  rotulo.innerHTML = '<b>' + tela.rotulo + '</b><span>' + tela.serve + '</span>';

  /* balão azul: só a próxima ação */
  const alvoDica = dica && dica.alvo ? (tela.alvos || []).find((a) => a.id === dica.alvo) : null;
  if (dica && dica.aba) {
    balao.hidden = false;
    balao.className = 'balao acao base';
    balao.innerHTML = '<span class="rot">Próxima ação</span>Toque na aba <b>' +
      ABAS.find((x) => x.id === dica.aba).rotulo.replace('…', '') + '</b>, aqui embaixo.';
  } else if (alvoDica && alvoDica.dica) {
    balao.hidden = false;
    /* nunca em cima do alvo: alvo embaixo → balão logo abaixo do rótulo */
    balao.className = 'balao acao ' + (alvoDica.y > 58 ? 'topo' : 'base');
    balao.innerHTML = '<span class="rot">Próxima ação</span>' + alvoDica.dica;
  } else {
    balao.hidden = true;
  }

  /* abas: ativa + dica */
  [...fnav.children].forEach((b) => {
    b.classList.toggle('on', b.dataset.aba === tela.aba);
    b.classList.toggle('dica', !!(dica && dica.aba === b.dataset.aba));
  });

  if (modo) {
    conteudo.classList.remove('push', 'pop', 'troca');
    void conteudo.offsetWidth;
    conteudo.classList.add(modo);
  }
  atualizarMissao();
}

function irPara(tela, modo) {
  if (!TELAS[tela]) return;
  if (modo === 'push') pilha.push(telaAtual);
  telaAtual = tela;
  folhaFundo.classList.remove('aberta');
  /* chegar na tela já cumpre missões que só pedem visita */
  const m = missaoAtual();
  if (m && m.tela === tela && !m.alvo) concluirMissao(m.id);
  pintar(modo || 'troca');
}

function voltar() {
  const anterior = pilha.pop() || TELAS[telaAtual].volta || 'menu';
  telaAtual = anterior;
  pintar('pop');
}

function tocar(a) {
  if (a.faz === 'favoritar') { marcas[telaAtual] = marcas[telaAtual] || {}; marcas[telaAtual][a.id] = 'coracao'; }
  if (a.faz === 'favoritar-pal') { marcas[telaAtual] = marcas[telaAtual] || {}; marcas[telaAtual][a.id] = 'coracao'; }
  if (a.faz === 'contato') { marcas[telaAtual] = marcas[telaAtual] || {}; marcas[telaAtual][a.id] = 'pendente'; }
  if (a.missao) concluirMissao(a.missao);
  if (a.brinde) avisar(a.brinde);
  if (a.volta) { voltar(); return; }
  if (a.vai) {
    irPara(a.vai, a.modo || 'troca');
    if (a.folha) setTimeout(() => abrirFolha(a.folha), 420);
    return;
  }
  if (a.folha) { abrirFolha(a.folha); }
  pintar();
}

/* toque fora de qualquer alvo: mostra de novo onde é */
frame.addEventListener('click', (e) => {
  if (e.target.closest('.alvo') || e.target.closest('.folha-fundo')) return;
  const d = calcularDica();
  if (!d) return;
  const el = d.aba ? fnav.querySelector('[data-aba="' + d.aba + '"]')
                   : conteudo.querySelector('.alvo[data-id="' + d.alvo + '"]');
  if (el) {
    el.classList.remove('erra');
    void el.offsetWidth;
    el.classList.add('erra');
    avisar('Toque no ponto azul para continuar');
  }
});

function concluirMissao(id) {
  if (feitas.has(id)) return;
  feitas.add(id);
  atualizarMissao();
  if (feitas.size === MISSOES.length) {
    setTimeout(() => document.getElementById('fim-fundo').classList.add('aberto'), 700);
  }
}

function atualizarMissao() {
  const m = missaoAtual();
  const i = m ? MISSOES.indexOf(m) : MISSOES.length;
  missaoTexto.innerHTML = m
    ? '<i>' + (i + 1) + '/' + MISSOES.length + '</i>' + m.txt
    : '<i>✓</i>Tour concluído — você conhece o app 💚';
  missaoProg.innerHTML = MISSOES.map((x, j) =>
    '<i class="' + (feitas.has(x.id) ? 'ok' : (j === i ? 'atual' : '')) + '"></i>').join('');
}

/* Painel de missões */
const missoesFundo = document.getElementById('missoes-fundo');
document.getElementById('ver-missoes').addEventListener('click', () => {
  const atual = missaoAtual();
  document.getElementById('missoes-lista').innerHTML = MISSOES.map((m) =>
    '<li class="' + (feitas.has(m.id) ? 'ok' : (m === atual ? 'atual' : '')) + '"><span>✓</span>' + m.txt + '</li>').join('');
  missoesFundo.classList.add('aberto');
});
document.getElementById('fechar-missoes').addEventListener('click', () => missoesFundo.classList.remove('aberto'));
document.getElementById('sair-tour').addEventListener('click', () => { missoesFundo.classList.remove('aberto'); abrirVista('home'); });

/* Abrir / fechar o tour */
/* O tour completo — as telas do app com as sete missões. Deixou de ser o
   primeiro contato: quem chega vê antes o guia da barra (final do arquivo),
   e chega aqui pelo botão de lá ou por `?tutorial=`. */
function abrirTourCompleto() {
  telaAtual = 'agenda'; pilha = []; feitas = new Set();
  Object.keys(marcas).forEach((k) => delete marcas[k]);
  document.getElementById('fim-fundo').classList.remove('aberto');
  abrirVista('tour');
  medirFone();
  pintar('troca');
}
document.getElementById('fechar-tour').addEventListener('click', () => abrirVista('home'));
document.getElementById('btn-concluir').addEventListener('click', () => {
  parent.postMessage({ tipo: 'mindagent:tour-concluido' }, '*');
  document.getElementById('fim-fundo').classList.remove('aberto');
  abrirVista('home');
});
document.getElementById('tour-para-chat').addEventListener('click', () => {
  document.getElementById('fim-fundo').classList.remove('aberto');
  abrirVista('chat');
});

/* pré-carrega as telas para a navegação não piscar */
Object.values(TELAS).forEach((t) => { const i = new Image(); i.src = TOUR_IMG_SRC(t.img); });

/* ---------- Chat conectado ao Mind Agent ---------- */
const mensagens = document.getElementById('mensagens');
const formChat = document.getElementById('form-chat');
const campoChat = document.getElementById('campo-chat');
let chatIniciado = false;

/* Passos que o agente sabe mostrar. Espelha a tabela `tutorial_passos` do
   Supabase: chave, a tela do app e o elemento que fica destacado. */
const PASSOS = {
  favoritar:    { tela: 'agenda',       alvo: 'coracao',  onde: 'Aba Agenda',
                  aviso: 'Arena Sextante, Arena LinkedIn, workshops e masterclasses têm vagas limitadas — nesses vale agendar antes.' },
  reservar:     { tela: 'detalhe',      alvo: 'reservar', onde: 'Dentro da sessão',
                  aviso: 'A reserva cai 5 minutos antes do início, para abrir a fila de espera.' },
  minha_agenda: { tela: 'minha-agenda', alvo: 'card',     onde: 'Aba Minha agenda' },
  qr:           { tela: 'qrcode',       alvo: 'escanear', onde: 'Aba QR Code' },
  escanear:     { tela: 'scanner',      alvo: 'meuqr',    onde: 'QR Code → Escanear' },
  mapa:         { tela: 'menu',         alvo: 'mapa',     onde: 'Menu → Mapa do evento' },
  rede:         { tela: 'menu',         alvo: 'rede',     onde: 'Menu → Área de network' },
  palestrantes: { tela: 'menu',         alvo: 'palestrantes', onde: 'Menu → Palestrantes' },
  chat:         { tela: 'menu',         alvo: 'chat',     onde: 'Menu → Chat' },
};

/* A frase que abre todo cartão de "onde fica". Espelha o template
   `agente.nao_agendo` do Supabase: quem executa é a pessoa, sempre. */
const NAO_AGENDO =
  '<span><b>Quem faz é você.</b> Eu ainda não consigo agendar no seu lugar — ' +
  'te mostro o print da tela para você achar o botão e tocar.</span>';

/* Monta o recorte da tela real em volta do elemento, com o anel azul em cima.
   A imagem tem proporção 780/1421, então a altura dela vale 3.3118 alturas do
   recorte — é dessa conta que sai o deslocamento vertical. */
const RECORTE_ALTURAS = (1421 / 780) / 1.50;

function cartaoOndeFica(chave) {
  const passo = PASSOS[chave];
  if (!passo) return null;
  const tela = TELAS[passo.tela];
  const alvo = (tela.alvos || []).find((a) => a.id === passo.alvo);
  if (!alvo) return null;

  const limite = -(RECORTE_ALTURAS - 1) * 100;
  const topo = Math.max(limite, Math.min(0, (0.5 - RECORTE_ALTURAS * (alvo.y / 100)) * 100));

  const cartao = document.createElement('div');
  cartao.className = 'cartao-onde';
  cartao.innerHTML =
    '<div class="selo-voce">' + NAO_AGENDO + '</div>' +
    '<div class="recorte">' +
      '<img src="' + TOUR_IMG_SRC(tela.img) + '" alt="Tela ' + passo.tela + ' do app" />' +
      '<span class="anel" style="left:' + alvo.x + '%; top:' + (topo + RECORTE_ALTURAS * alvo.y) + '%"></span>' +
    '</div>' +
    '<div class="rodape"><span class="onde"><i>Fica aqui</i> ' + passo.onde + '</span>' +
      (passo.aviso ? '<span class="aviso-regra">' + passo.aviso + '</span>' : '') +
    '</div>';
  cartao.querySelector('img').style.top = topo + '%';

  const b = document.createElement('button');
  b.type = 'button';
  b.className = 'ir-tutorial';
  b.textContent = 'Abrir no app';
  b.addEventListener('click', () => abrirTutorialEm(passo.tela));
  cartao.querySelector('.rodape').appendChild(b);
  return cartao;
}

/* O agente não agenda por você: ele mostra onde é. Quando a resposta tem um
   passo, a bolha ganha o recorte da tela e o botão que abre o tour ali. */
function bolha(texto, quem, passo) {
  const el = document.createElement('div');
  el.className = 'bolha ' + quem;
  el.textContent = texto;
  if (passo) {
    const cartao = cartaoOndeFica(passo);
    if (cartao) el.appendChild(cartao);
  }
  mensagens.appendChild(el);
  mensagens.scrollTop = mensagens.scrollHeight;
  return el;
}

/* Abre o tour direto numa tela — usado pelo agente e por quem embeda a página
   (?tutorial=agenda ou postMessage {tipo:'mindagent:tutorial', tela:'agenda'}). */
function abrirTutorialEm(tela) {
  if (!TELAS[tela]) return;
  telaAtual = tela;
  pilha = [];
  abrirVista('tour');
  medirFone();
  pintar('troca');
}
addEventListener('message', (e) => {
  const d = e.data;
  if (d && d.tipo === 'mindagent:tutorial') abrirTutorialEm(d.tela);
});
{
  const alvo = new URLSearchParams(location.search).get('tutorial');
  if (alvo) addEventListener('load', () => { fecharSplash(); abrirTutorialEm(alvo); });
}

let respostaEmAndamento = false;

async function responder(pergunta) {
  const digitando = document.createElement('div');
  digitando.className = 'bolha mind';
  digitando.innerHTML = '<span class="digitando"><i></i><i></i><i></i></span>';
  mensagens.appendChild(digitando);
  mensagens.scrollTop = mensagens.scrollHeight;

  respostaEmAndamento = true;
  campoChat.disabled = true;
  formChat.querySelector('.enviar').disabled = true;
  try {
    const resposta = await enviarMensagem(pergunta);
    digitando.remove();
    const q = pergunta.toLowerCase();
    const passo = ['onde fica', 'mapa', 'arena', 'palco', 'sala', 'lounge', 'banheiro']
      .some((chave) => q.includes(chave)) ? 'mapa' : null;
    bolha(resposta.answer, 'mind', passo);
  } catch (erro) {
    digitando.remove();
    const mensagem = erro?.name === 'AbortError'
      ? 'A resposta demorou demais. Tente novamente.'
      : (erro?.message || 'Não consegui responder agora. Tente novamente.');
    bolha(mensagem, 'mind');
  } finally {
    respostaEmAndamento = false;
    campoChat.disabled = false;
    formChat.querySelector('.enviar').disabled = false;
    campoChat.focus();
  }
}

function perguntar(texto) {
  if (!texto || !texto.trim() || respostaEmAndamento) return;
  const limpo = texto.trim();
  jaPerguntou = true;
  bolha(limpo, 'eu');
  /* Quando o agente pediu o desafio, a próxima frase não é uma pergunta de
     FAQ — é o problema da pessoa. A leitura vem da IA; os cards vêm depois,
     para o fluxo não terminar em parágrafo. */
  if (esperandoDesafio) {
    esperandoDesafio = false;
    return responder(limpo).then(() => cardsDoDesafio(limpo));
  }
  responder(limpo);
}

let jaPerguntou = false;

/* Sem identidade, cumprimento sem nome — o agente não chuta quem você é.
   Quando a Yazo (ou o bootstrap) preencher PARTICIPANTE.nome, ele chama
   pelo nome sem que mais nada mude. */
function saudacao() {
  const nome = PARTICIPANTE.nome && PARTICIPANTE.nome.trim();
  return nome ? 'Oi, ' + nome + '! 💚 ' : 'Oi! 💚 ';
}

function iniciarChat() {
  if (chatIniciado) return;
  chatIniciado = true;
  bolha(saudacao() + 'Sou o Mind Agent. Não estou aqui só para responder pergunta: estou para você sair daqui com algo mais concreto do que boas ideias — agenda montada, gente certa, e o que fazer na segunda-feira.', 'mind');
  /* Engajamento proativo: o agente também começa conversa quando é útil */
  setTimeout(() => {
    if (jaPerguntou) return;
    bolha('A propósito: a sessão que você reservou na Arena Mind começa em 15 minutos. Quer que eu te avise 5 minutos antes? ⏰', 'mind');
  }, 9000);
}

formChat.addEventListener('submit', (e) => {
  e.preventDefault();
  perguntar(campoChat.value);
  campoChat.value = '';
});

/* ============================================================
   DADOS — nenhum conteúdo mora neste arquivo
   ============================================================
   A página pede a programação ao `data-service.js` e desenha a partir dela.
   É o mesmo contrato que ela vai ter com o mindagent-bootstrap depois: trocar
   a fonte é mexer no config, não reescrever a página. Se a busca falhar, ela
   diz — não inventa. */
let DADOS = null;
const TEMA = (codigo) => (DADOS.temas.find((t) => t.codigo === codigo) || {}).rotulo || codigo;

/* As seis intenções. Ícone e ordem são apresentação; o texto vem do JSON. */
const ICONES = {
  agenda:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><rect x="3" y="4.5" width="18" height="16" rx="4"/><path d="M8 2.5v4M16 2.5v4M3 10h18"/></svg>',
  palestras:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M12 3v10M9 6l3-3 3 3"/><rect x="4" y="13" width="16" height="8" rx="3"/></svg>',
  pessoas:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><circle cx="9" cy="8" r="3.4"/><path d="M3 20c0-3.2 2.7-5.4 6-5.4s6 2.2 6 5.4"/><path d="M16.5 5.4a3.4 3.4 0 0 1 0 6.5M18 20c0-2.2-.9-4-2.3-5"/></svg>',
  desafio:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M16.2 16.2 21 21M11 8v3.2l2.2 1.4"/></svg>',
  insight:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M9 18h6M10 21h4"/><path d="M12 3a6 6 0 0 0-3.5 10.9c.5.4.8 1 .8 1.6h5.4c0-.6.3-1.2.8-1.6A6 6 0 0 0 12 3z"/></svg>',
  plano:    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"><path d="M5 4.5h14v16l-7-3.4-7 3.4z"/><path d="M9 9.5h6M9 13h4"/></svg>',
};

const INTENCOES = [
  { id: 'agenda',    titulo: 'Montar minha agenda',
    dica: 'Eu monto um roteiro dos dois dias sem choque de horário' },
  { id: 'palestras', titulo: 'Escolher palestras',
    dica: 'Vejo a grade inteira e trago o que fala do seu problema' },
  { id: 'pessoas',   titulo: 'Conhecer pessoas',
    dica: 'Quem está aqui que vale você conhecer, e por quê' },
  { id: 'desafio',   titulo: 'Encontrar conteúdos para meu desafio',
    dica: 'Me conte a dificuldade; eu trago a leitura antes da indicação' },
  { id: 'insight',   titulo: 'Registrar meus insights',
    dica: 'O que ficou de cada sessão, guardado no seu Summit' },
  { id: 'plano',     titulo: 'Criar meu plano pós-Summit',
    dica: 'O que você faz na segunda-feira com tudo isso' },
];

function montarIntencoes() {
  document.getElementById('intencoes').innerHTML = INTENCOES.map((i) =>
    '<button type="button" data-intencao="' + i.id + '">' +
      '<span class="ic">' + ICONES[i.id] + '</span>' +
      '<span class="tx"><b>' + i.titulo + '</b><small>' + i.dica + '</small></span>' +
    '</button>').join('');
}

/* Quem sabe de onde vem a programação é o data-service. Aqui só se guarda
   o que ele entregou — trocar arquivo local por API não passa por este
   arquivo. */
async function carregarDados() {
  DADOS = await carregarDadosSummit();
}

/* ============================================================
   PERFIL VIVO — o que o Summit sabe sobre você até agora
   ============================================================
   Cresce por AÇÃO, nunca por palpite: tema escolhido, sessão salva, pessoa
   marcada, insight escrito. É a mesma separação do banco — o que a pessoa faz
   é fato; o que o agente conclui é leitura. */
const PERFIL = { temas: {}, sessoes: [], pessoas: [], insights: [], plano: [] };

function pesoTema(codigo, quanto) {
  PERFIL.temas[codigo] = (PERFIL.temas[codigo] || 0) + quanto;
  if (PERFIL.temas[codigo] <= 0) delete PERFIL.temas[codigo];
  tocarPerfil();
}
function tocarPerfil() {
  const total = Object.keys(PERFIL.temas).length + PERFIL.sessoes.length +
                PERFIL.pessoas.length + PERFIL.insights.length;
  const btn = document.getElementById('btn-perfil');
  btn.hidden = total === 0;
  const pontos = document.getElementById('perfil-pontos');
  const n = Math.min(5, total);
  pontos.innerHTML = Array.from({ length: 5 },
    (_, i) => '<i class="' + (i < n ? 'on' : '') + '"></i>').join('');
  if (vistas.summit.classList.contains('ativa')) desenharSummit();
}

/* Afinidade = quanto do seu peso de temas essa sessão cobre. Sem tema
   escolhido não existe número — e a página não inventa um. */
function afinidade(temas) {
  const meus = Object.keys(PERFIL.temas);
  if (!meus.length || !temas || !temas.length) return null;
  const total = meus.reduce((soma, t) => soma + PERFIL.temas[t], 0);
  const casados = temas.filter((t) => meus.includes(t));
  const bate = casados.reduce((soma, t) => soma + PERFIL.temas[t], 0);
  if (!bate) return null;
  /* Foco: uma sessão que fala só dos seus temas conversa mais com você do que
     uma que os menciona no meio de outros cinco. Sem isso tudo empata em 98%. */
  const foco = Math.pow(casados.length / temas.length, 0.45);
  return Math.round(46 + (bate / total) * foco * 52);
}

const HORA = (h) => (h || '23:59');
const choca = (a, b) =>
  a.dia === b.dia && a.inicio < HORA(b.fim) && b.inicio < HORA(a.fim);

function sessoesPorAfinidade(filtro) {
  return DADOS.sessoes
    .filter((s) => !filtro || filtro(s))
    .map((s) => ({ s, a: afinidade(s.temas) }))
    .filter((x) => x.a !== null)
    .sort((x, y) => y.a - x.a || (x.s.dia + x.s.inicio).localeCompare(y.s.dia + y.s.inicio));
}

/* ============================================================
   UI GENERATIVA — a resposta se monta como interface
   ============================================================
   Em vez de "estas são as palestras recomendadas", vêm os cards: quem fala,
   quando, onde, o quanto conversa com o que você disse, e o que dá para
   fazer dali. O chat vira o trilho, não o produto. */
function painel(titulo, destaque) {
  const el = document.createElement('div');
  el.className = 'painel';
  if (titulo) {
    const t = document.createElement('p');
    t.className = 'painel-tit';
    t.innerHTML = titulo + (destaque ? ' <b>' + destaque + '</b>' : '');
    el.appendChild(t);
  }
  mensagens.appendChild(el);
  mensagens.scrollTop = mensagens.scrollHeight;
  return el;
}

function anelAfinidade(pct) {
  if (pct === null) return '';
  const c = 2 * Math.PI * 11;
  return '<span class="afin" title="Afinidade com os seus temas">' +
    '<svg viewBox="0 0 26 26"><circle class="trilho" cx="13" cy="13" r="11"/>' +
    '<circle class="arco" cx="13" cy="13" r="11" stroke-dasharray="' +
    (c * pct / 100).toFixed(1) + ' ' + c.toFixed(1) + '"/></svg>' +
    '<b>' + pct + '%</b></span>';
}

const DIA_CURTO = (iso) => (iso === DADOS.evento.dias[0] ? '16 set' : '17 set');

function fotoDe(nome) {
  const p = DADOS.pessoas.find((x) => nome && nome.startsWith(x.nome));
  return p ? p.foto : null;
}

function cardSessao(s, pct, porque) {
  const el = document.createElement('article');
  el.className = 'cs';
  const foto = fotoDe(s.quem);
  const salva = PERFIL.sessoes.some((x) => x.id === s.id);
  el.innerHTML =
    '<span class="foto">' + (foto
      ? '<img src="./assets/' + foto + '" alt="" loading="lazy" />'
      : '<span>' + (s.titulo[0] || '·') + '</span>') + '</span>' +
    '<div class="corpo">' +
      '<p class="quando">' + DIA_CURTO(s.dia) + ' · ' + s.inicio +
        (s.fim ? '–' + s.fim : '') + ' <em>' + s.etiqueta + '</em>' +
        anelAfinidade(pct) + '</p>' +
      '<h4>' + s.titulo + '</h4>' +
      (s.quem && !/^(em breve|em curadoria)$/i.test(s.quem)
        ? '<p class="quem">' + s.quem + '</p>'
        : '<p class="onde">Palestrante em curadoria</p>') +
      '<p class="onde">' + (s.espaco || 'Espaço a confirmar') +
        (s.vaga_limitada ? ' · <span class="limitada">vaga limitada</span>' : '') + '</p>' +
      (porque ? '<p class="porque">' + porque + '</p>' : '') +
      '<div class="acoes">' +
        '<button type="button" class="principal" data-acao="salvar">' +
          (salva ? 'Salva ✓' : 'Salvar no meu Summit') + '</button>' +
        '<button type="button" data-acao="onde">Onde reservar</button>' +
      '</div>' +
    '</div>';
  el.querySelector('[data-acao="salvar"]').addEventListener('click', (e) => {
    if (PERFIL.sessoes.some((x) => x.id === s.id)) return;
    PERFIL.sessoes.push(s);
    s.temas.forEach((t) => pesoTema(t, 1));
    e.target.textContent = 'Salva ✓';
    el.classList.add('salva');
    tocarPerfil();
  });
  el.querySelector('[data-acao="onde"]').addEventListener('click', () => {
    bolha('Onde eu reservo "' + s.titulo + '"?', 'eu');
    setTimeout(() => bolha(
      s.vaga_limitada
        ? DADOS.evento.regra_vagas + ' ' + DADOS.evento.regra_reserva
        : DADOS.evento.regra_reserva,
      'mind', 'reservar'), 500);
  });
  return el;
}

function cardPessoa(p, pct, porque) {
  const el = document.createElement('article');
  el.className = 'cs';
  const marcada = PERFIL.pessoas.some((x) => x.nome === p.nome);
  el.innerHTML =
    '<span class="foto"><img src="./assets/' + p.foto + '" alt="" loading="lazy" /></span>' +
    '<div class="corpo">' +
      '<p class="quando">' + (p.destaque ? 'Legend' : 'Palestrante') +
        ' <em>' + (p.na_grade ? 'está na grade' : 'no evento') + '</em>' +
        anelAfinidade(pct) + '</p>' +
      '<h4>' + p.nome + '</h4>' +
      '<p class="quem">' + p.credencial + '</p>' +
      (porque ? '<p class="porque">' + porque + '</p>' : '') +
      '<div class="acoes">' +
        '<button type="button" class="principal" data-acao="marcar">' +
          (marcada ? 'Na sua lista ✓' : 'Quero conhecer') + '</button>' +
        '<button type="button" data-acao="como">Como trocar contato</button>' +
      '</div>' +
    '</div>';
  el.querySelector('[data-acao="marcar"]').addEventListener('click', (e) => {
    if (PERFIL.pessoas.some((x) => x.nome === p.nome)) return;
    PERFIL.pessoas.push(p);
    e.target.textContent = 'Na sua lista ✓';
    el.classList.add('salva');
    tocarPerfil();
  });
  el.querySelector('[data-acao="como"]').addEventListener('click', () => {
    bolha('Como eu troco contato com alguém?', 'eu');
    setTimeout(() => bolha(
      'O contato é pelo QR Code do app: você escaneia o código da pessoa e ela entra em Contatos.',
      'mind', 'escanear'), 500);
  });
  return el;
}

function blocoRegra(texto) {
  const el = document.createElement('p');
  el.className = 'regra';
  el.innerHTML = '<b>!</b><span>' + texto + '</span>';
  return el;
}

/* Chips de tema: é assim que o perfil começa a existir. */
function pedirTemas(depois) {
  const alvo = painel('Escolha o que está te puxando');
  const chips = document.createElement('div');
  chips.className = 'chips';
  chips.innerHTML = DADOS.temas.map((t) =>
    '<button type="button" aria-pressed="' + (PERFIL.temas[t.codigo] ? 'true' : 'false') +
    '" data-tema="' + t.codigo + '">' + t.rotulo + '</button>').join('');
  const ok = document.createElement('button');
  ok.type = 'button';
  ok.className = 'avancar';
  ok.textContent = 'Pronto, continuar';
  ok.disabled = !Object.keys(PERFIL.temas).length;
  chips.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-tema]');
    if (!b) return;
    const ligado = b.getAttribute('aria-pressed') === 'true';
    b.setAttribute('aria-pressed', ligado ? 'false' : 'true');
    pesoTema(b.dataset.tema, ligado ? -2 : 2);
    ok.disabled = !Object.keys(PERFIL.temas).length;
  });
  ok.addEventListener('click', () => { ok.remove(); depois(); });
  alvo.appendChild(chips);
  alvo.appendChild(ok);
  mensagens.scrollTop = mensagens.scrollHeight;
}

function comTemas(depois) {
  if (Object.keys(PERFIL.temas).length) return depois();
  bolha('Antes de eu sugerir qualquer coisa: em que você está mexendo agora? Pode marcar mais de um.', 'mind');
  setTimeout(() => pedirTemas(depois), 450);
}

/* ---------- Os seis fluxos ---------- */
const FLUXOS = {
  palestras() {
    comTemas(() => {
      const lista = sessoesPorAfinidade((s) => s.formato !== 'experiencia').slice(0, 4);
      if (!lista.length) return bolha('Ainda não encontrei sessão que converse com esses temas. Marque outro que eu tento de novo.', 'mind');
      const alvo = painel('O que mais conversa com', Object.keys(PERFIL.temas).map(TEMA).join(', '));
      lista.forEach(({ s, a }) => alvo.appendChild(cardSessao(s, a,
        'Fala de ' + s.temas.filter((t) => PERFIL.temas[t]).map(TEMA).join(' e ') + '.')));
      if (lista.some(({ s }) => s.vaga_limitada)) alvo.appendChild(blocoRegra(DADOS.evento.regra_vagas));
    });
  },

  agenda() {
    comTemas(() => {
      /* Roteiro sem choque: pega a de maior afinidade e vai encaixando o que
         não colide com o que já entrou. */
      const roteiro = [];
      sessoesPorAfinidade((s) => s.formato !== 'experiencia')
        .forEach(({ s, a }) => { if (!roteiro.some((x) => choca(x.s, s))) roteiro.push({ s, a }); });
      roteiro.sort((x, y) => (x.s.dia + x.s.inicio).localeCompare(y.s.dia + y.s.inicio));
      const corte = roteiro.slice(0, 6);
      const alvo = painel('Seu roteiro dos dois dias', corte.length + ' sessões, sem choque de horário');
      corte.forEach(({ s, a }) => alvo.appendChild(cardSessao(s, a, null)));
      alvo.appendChild(blocoRegra(DADOS.evento.regra_reserva +
        ' Quem reserva é você, no app — eu só mostro onde fica.'));
    });
  },

  pessoas() {
    comTemas(() => {
      const meus = Object.keys(PERFIL.temas);
      const lista = DADOS.pessoas
        .map((p) => ({ p, a: afinidade(p.temas) }))
        .filter((x) => x.a !== null)
        .sort((x, y) => y.a - x.a || (y.p.destaque - x.p.destaque))
        .slice(0, 4);
      if (!lista.length) return bolha('Não achei ninguém com afinidade clara com esses temas ainda.', 'mind');
      const alvo = painel('Quem vale você conhecer');
      lista.forEach(({ p, a }) => alvo.appendChild(cardPessoa(p, a,
        'Trabalha com ' + p.temas.filter((t) => meus.includes(t)).map(TEMA).join(' e ') + '.')));
    });
  },

  desafio() {
    bolha('Me conta o desafio com as suas palavras — o que está acontecendo aí que você quer resolver. Eu leio antes de indicar qualquer coisa.', 'mind');
    esperandoDesafio = true;
    campoChat.focus();
  },

  insight() {
    const base = PERFIL.sessoes.length ? PERFIL.sessoes
               : sessoesPorAfinidade().slice(0, 3).map((x) => x.s);
    if (!base.length) {
      bolha('Primeiro salve alguma sessão — aí eu tenho onde pendurar o insight. Quer escolher palestras agora?', 'mind');
      return;
    }
    const alvo = painel('O que ficou');
    const cx = document.createElement('div');
    cx.className = 'ins';
    cx.innerHTML =
      '<div class="chips">' + base.map((s, i) =>
        '<button type="button" aria-pressed="' + (i === 0) + '" data-s="' + s.id + '">' +
        s.titulo.slice(0, 30) + (s.titulo.length > 30 ? '…' : '') + '</button>').join('') + '</div>' +
      '<textarea placeholder="O que dessa sessão conversou com o que você está tentando resolver?"></textarea>';
    const salvar = document.createElement('button');
    salvar.type = 'button';
    salvar.className = 'avancar';
    salvar.textContent = 'Guardar no meu Summit';
    cx.querySelector('.chips').addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      cx.querySelectorAll('.chips button').forEach((x) => x.setAttribute('aria-pressed', 'false'));
      b.setAttribute('aria-pressed', 'true');
    });
    salvar.addEventListener('click', () => {
      const txt = cx.querySelector('textarea').value.trim();
      if (!txt) return cx.querySelector('textarea').focus();
      const id = cx.querySelector('.chips button[aria-pressed="true"]').dataset.s;
      const sessao = base.find((x) => x.id === id);
      PERFIL.insights.push({ sessao: sessao.titulo, texto: txt, temas: sessao.temas });
      sessao.temas.forEach((t) => pesoTema(t, 1));
      cx.remove(); salvar.remove();
      bolha('Guardei. Isso muda o seu mapa e o que eu vou sugerir daqui pra frente. 💚', 'mind');
      tocarPerfil();
    });
    alvo.appendChild(cx); alvo.appendChild(salvar);
    mensagens.scrollTop = mensagens.scrollHeight;
  },

  plano() {
    if (!PERFIL.insights.length && !PERFIL.sessoes.length) {
      bolha('O plano sai do que você viveu aqui — e ainda não tenho nada seu. Comece escolhendo palestras ou registrando um insight.', 'mind');
      return;
    }
    const alvo = painel('Seu plano para segunda-feira');
    const ul = document.createElement('ul');
    ul.className = 'plano';
    const itens = [];
    PERFIL.insights.forEach((i) =>
      itens.push(['Aplicar', i.texto, 'De "' + i.sessao + '"']));
    Object.keys(PERFIL.temas)
      .sort((a, b) => PERFIL.temas[b] - PERFIL.temas[a]).slice(0, 2)
      .forEach((t) => itens.push(['Aprofundar', TEMA(t),
        'Foi o que mais apareceu nas suas escolhas']));
    PERFIL.pessoas.slice(0, 2).forEach((p) =>
      itens.push(['Retomar', 'Falar com ' + p.nome, p.credencial]));
    if (PERFIL.sessoes.length)
      itens.push(['Revisitar', 'Rever o material de ' + PERFIL.sessoes.length +
        ' sessão(ões) salva(s)', 'Chega por e-mail depois do evento']);
    ul.innerHTML = itens.map(([tag, txt, sub], i) =>
      '<li><i>' + (i + 1) + '</i><span><b>' + tag + ':</b> ' + txt +
      '<small>' + sub + '</small></span></li>').join('');
    alvo.appendChild(ul);
    PERFIL.plano = itens;
    const ver = document.createElement('button');
    ver.type = 'button'; ver.className = 'avancar';
    ver.textContent = 'Ver o meu Summit inteiro';
    ver.addEventListener('click', () => abrirVista('summit'));
    alvo.appendChild(ver);
    tocarPerfil();
  },
};

let esperandoDesafio = false;

function abrirIntencao(id) {
  const i = INTENCOES.find((x) => x.id === id);
  if (!i) return;
  bolha(i.titulo, 'eu');
  setTimeout(() => FLUXOS[id](), 550);
}

/* Desafio em texto livre: a leitura passou a vir da IA, que responde antes
   disto rodar. O que fica aqui é o que o fluxo entrega de visual e é local —
   casar o texto com os temas da grade, dar peso ao perfil e abrir os cards.
   Continua sendo "entender antes de recomendar": a recomendação vem depois. */
function cardsDoDesafio(texto) {
  const achados = DADOS.temas.filter((t) =>
    t.rotulo.toLowerCase().split(/[^a-zà-ÿ]+/).some((w) => w.length > 4 &&
      texto.toLowerCase().includes(w)) ||
    DADOS.sessoes.some((s) => s.temas.includes(t.codigo) &&
      s.titulo.toLowerCase().split(/[^a-zà-ÿ]+/).some((w) => w.length > 5 &&
        texto.toLowerCase().includes(w))));
  const usar = achados.length ? achados : DADOS.temas.filter((t) => PERFIL.temas[t.codigo]);
  if (!usar.length) {
    bolha('Para eu te mostrar as sessões, marque o tema que chega mais perto do que você descreveu:', 'mind');
    return setTimeout(() => pedirTemas(() => FLUXOS.palestras()), 400);
  }
  usar.forEach((t) => pesoTema(t.codigo, 3));
  setTimeout(() => FLUXOS.palestras(), 500);
}

/* ============================================================
   O MAPA — você vê o seu Summit tomando forma
   ============================================================ */
function desenharSummit() {
  const caixa = document.getElementById('mapa-caixa');
  const temas = Object.entries(PERFIL.temas).sort((a, b) => b[1] - a[1]);
  const total = temas.length + PERFIL.sessoes.length + PERFIL.pessoas.length +
                PERFIL.insights.length;
  document.getElementById('summit-sub').textContent = total
    ? total + ' marcas no seu mapa' : 'Vai se desenhando conforme você usa';

  if (!total) {
    caixa.innerHTML = '<p class="mapa-vazio">Seu mapa está vazio. Escolha um tema, salve uma sessão ou registre um insight — cada gesto vira um ponto aqui.</p>';
    document.getElementById('contadores').innerHTML = '';
    document.getElementById('s-linha').innerHTML = '';
    return;
  }

  const R = 100, cx = 100, cy = 100;
  const partes = [];
  partes.push('<circle class="anelbase" cx="100" cy="100" r="42"/>');
  partes.push('<circle class="anelbase" cx="100" cy="100" r="72"/>');

  const maxPeso = Math.max(...temas.map((t) => t[1]), 1);
  const nos = [];
  temas.forEach(([codigo, peso], i) => {
    const ang = (i / Math.max(temas.length, 1)) * Math.PI * 2 - Math.PI / 2;
    const x = cx + Math.cos(ang) * 42, y = cy + Math.sin(ang) * 42;
    const r = 5 + (peso / maxPeso) * 7;
    nos.push({ x, y, r, cor: 'var(--verde)', rotulo: TEMA(codigo), ang, atraso: i * 60 });
  });

  const orbita = (itens, raio, cor, base) => itens.forEach((it, i) => {
    const ang = ((i + 0.5) / Math.max(itens.length, 1)) * Math.PI * 2 - Math.PI / 2 + base;
    nos.push({ x: cx + Math.cos(ang) * raio, y: cy + Math.sin(ang) * raio,
               r: 4, cor, atraso: 300 + i * 55 });
  });
  orbita(PERFIL.sessoes, 72, 'var(--acao)', 0.15);
  orbita(PERFIL.pessoas, 88, 'var(--roxo)', 0.4);
  orbita(PERFIL.insights, 60, 'var(--coral)', 0.7);

  nos.forEach((n) => {
    partes.push('<line class="fio" x1="100" y1="100" x2="' + n.x.toFixed(1) +
                '" y2="' + n.y.toFixed(1) + '"/>');
  });
  nos.forEach((n) => {
    partes.push('<g class="no" style="animation-delay:' + n.atraso + 'ms">' +
      '<circle cx="' + n.x.toFixed(1) + '" cy="' + n.y.toFixed(1) + '" r="' +
      n.r.toFixed(1) + '" fill="' + n.cor + '"/>' +
      (n.rotulo ? '<text class="rot" x="' + n.x.toFixed(1) + '" y="' +
        (n.y + (n.y < cy ? -n.r - 5 : n.r + 11)).toFixed(1) +
        '" text-anchor="middle">' + n.rotulo.split(' ')[0] + '</text>' : '') +
      '</g>');
  });
  partes.push('<circle cx="100" cy="100" r="15" fill="var(--surface)" stroke="var(--verde)" stroke-width="1.5"/>');
  partes.push('<text class="voce" x="100" y="104" text-anchor="middle">Você</text>');

  caixa.innerHTML = '<svg viewBox="0 0 200 200" role="img" aria-label="Mapa do seu Summit">' +
                    partes.join('') + '</svg>';

  document.getElementById('contadores').innerHTML = [
    [temas.length, 'temas'], [PERFIL.sessoes.length, 'sessões'],
    [PERFIL.pessoas.length, 'pessoas'], [PERFIL.insights.length, 'insights'],
  ].map(([n, r]) => '<div><b>' + n + '</b><small>' + r + '</small></div>').join('');

  const linha = [];
  if (temas.length) linha.push(['Seu foco',
    temas.slice(0, 3).map(([c]) => TEMA(c)).join(' · '), 'Pelo que você marcou e salvou']);
  PERFIL.insights.slice(-3).reverse().forEach((i) =>
    linha.push(['Insight', i.texto, i.sessao]));
  if (PERFIL.sessoes.length) linha.push(['Na sua agenda',
    PERFIL.sessoes.map((s) => s.titulo).join(' · '), PERFIL.sessoes.length + ' salvas']);
  if (PERFIL.pessoas.length) linha.push(['Quer conhecer',
    PERFIL.pessoas.map((p) => p.nome).join(' · '), '']);
  document.getElementById('s-linha').innerHTML = linha.map(([t, txt, sub]) =>
    '<h3>' + t + '</h3><p>' + txt + (sub ? '<em>' + sub + '</em>' : '') + '</p>').join('');
}

/* ---------- Partida ---------- */
carregarDados().then(() => {
  montarIntencoes();
}).catch((e) => {
  document.getElementById('intencoes').innerHTML =
    '<p class="erro-dados"><b>Não consegui carregar a programação.</b>' +
    'Esta página não guarda conteúdo dentro do código — ela lê da camada de dados, ' +
    'e a leitura falhou (' + e.message + '). Recarregue em um instante.</p>';
});

/* ============================================================
   GUIA DA BARRA — tela cheia, passando sozinho
   ============================================================
   A barra de abas é do aplicativo do evento, não desta página: ela mora
   logo abaixo da nossa borda inferior. Não dá para destacar um elemento
   fora do nosso DOM, então o guia faz por fora o que o app faz por
   dentro — a seta aponta para a coluna do ícone e a barrinha de aba
   selecionada é desenhada rente à borda, igual à que o app acende.

   As colunas são frações da largura: é como uma barra de cinco abas se
   divide, em qualquer tela. Muda o número de abas, muda só esta lista.

   Aparece no primeiro acesso e pelo botão "Fazer tour do app". */

/* Mesma convenção de chave do chat-service, para tudo desta pessoa
   viver sob o mesmo prefixo. */
const GUIA_VISTO = 'mindagent:v1:' + CONFIG.eventSlug + ':guia-visto';

/* Devagar de propósito: é para ler sem correr, não para despachar. */
const GUIA_DURACAO = 7000;

const GUIA = [
  { rotulo: 'Mind Agent', selo: 'Você está aqui', x: 0.10,
    texto: 'Eu monto seu roteiro dos dois dias, indico palestras e pessoas pelo que você me contar, e respondo dúvida de programação, sala, horário e credenciamento.' },
  { rotulo: 'Agenda', selo: 'A programação', x: 0.30,
    texto: 'A grade inteira dos dias 16 e 17. Toque no coração para salvar o que não quer perder — é o que aparece na próxima aba.' },
  { rotulo: 'Minha Agenda', selo: 'O seu roteiro', x: 0.50,
    texto: 'O que você salvou e reservou, em ordem de horário. É aqui que o seu dia toma forma.' },
  { rotulo: 'QR Code', selo: 'Credencial e rede', x: 0.70,
    texto: 'Sua credencial e sua câmera. Faça check-in nas sessões e troque contato com quem conhecer: escaneie o QR da pessoa e ela entra na sua rede.' },
  { rotulo: 'Menu', selo: 'E o resto', x: 0.90,
    texto: 'Mapa do evento, área de networking, palestrantes, notificações, chat e mais.' },
];

const guia = document.getElementById('guia');
const guiaSeta = document.getElementById('guia-seta');
const guiaCena = document.getElementById('guia-cena');
const guiaBarra = document.getElementById('guia-barra');
const guiaFim = document.getElementById('guia-fim');
let guiaPasso = 0;
let guiaRelogio = null;

/* A seta: curva do texto até a coluna do ícone, desenhada com bolinhas
   (traço zero + espaço, ponta redonda) e ponta cheia. O ângulo da ponta
   vem da tangente da curva, senão ela aponta torto. */
function desenharSeta() {
  const L = innerWidth, A = innerHeight;
  const alvo = GUIA[guiaPasso];
  const r = guiaCena.getBoundingClientRect();

  const ax = alvo.x * L;                                  /* coluna do ícone */
  const ay = A - 12;                                      /* rente à borda: o ícone fica abaixo */
  const px = Math.min(Math.max(ax, 40), L - 40);
  const py = Math.min(r.bottom + 18, A - 150);

  /* Controle jogado para o lado: dá o gingado de desenho à mão em vez de
     uma reta de régua. */
  const cx = px + (ax - px) * 0.7 + (ax < px ? -30 : 30);
  const cy = py + (ay - py) * 0.45;

  const ang = Math.atan2(ay - cy, ax - cx);
  const P = 10, ABERT = 0.44;
  const ponta = [
    [ax, ay],
    [ax - P * Math.cos(ang - ABERT), ay - P * Math.sin(ang - ABERT)],
    [ax - P * Math.cos(ang + ABERT), ay - P * Math.sin(ang + ABERT)],
  ].map((p) => p[0].toFixed(1) + ',' + p[1].toFixed(1)).join(' ');

  guiaSeta.setAttribute('viewBox', '0 0 ' + L + ' ' + A);
  guiaSeta.innerHTML =
    '<path class="trilha" d="M' + px.toFixed(1) + ' ' + py.toFixed(1) +
      ' Q' + cx.toFixed(1) + ' ' + cy.toFixed(1) + ' ' + ax.toFixed(1) + ' ' + (ay - 13).toFixed(1) + '"/>' +
    '<polygon class="ponta" points="' + ponta + '"/>';

  guiaSeta.classList.remove('desenhando');
  void guiaSeta.offsetWidth;
  guiaSeta.classList.add('desenhando');

  /* A barrinha da aba: mesma proporção que o app usa — pouco menos de um
     quinto da tela, centrada na coluna. Ela desliza de um passo ao outro. */
  const larguraBarra = L * 0.19;
  guiaBarra.style.width = larguraBarra + 'px';
  guiaBarra.style.left = (ax - larguraBarra / 2) + 'px';
}

function pintarGuia(primeiro) {
  const p = GUIA[guiaPasso];
  const ultimo = guiaPasso === GUIA.length - 1;

  document.getElementById('guia-trilha').innerHTML = GUIA.map((_, i) =>
    '<i class="' + (i < guiaPasso ? 'ok' : i === guiaPasso ? 'atual' : '') + '"><span></span></i>').join('');
  document.getElementById('guia-trilha').style.setProperty('--dur', GUIA_DURACAO + 'ms');

  document.getElementById('guia-selo').textContent = p.selo;
  /* O ponto final verde, como no site do Summit */
  document.getElementById('guia-titulo').innerHTML =
    p.rotulo.replace(/[<>&]/g, '') + '<em>.</em>';
  document.getElementById('guia-texto').textContent = p.texto;

  guiaCena.classList.remove('sai');
  guiaCena.classList.remove('mostra');
  void guiaCena.offsetWidth;
  guiaCena.classList.add('mostra');

  desenharSeta();

  guiaFim.hidden = !ultimo;
  if (primeiro) guiaBarra.style.transition = 'none';
  if (primeiro) requestAnimationFrame(() => { guiaBarra.style.transition = ''; });
}

/* Passa sozinho. A cena sai antes de a próxima entrar, para a troca não
   ser um corte seco. */
function agendarProximo() {
  clearTimeout(guiaRelogio);
  guiaRelogio = setTimeout(() => {
    if (guiaPasso >= GUIA.length - 1) return;   /* o último fica, esperando decisão */
    guiaCena.classList.add('sai');
    setTimeout(() => { guiaPasso++; pintarGuia(); agendarProximo(); }, 280);
  }, GUIA_DURACAO);
}

function abrirGuia() {
  guiaPasso = 0;
  guia.hidden = false;
  pintarGuia(true);
  agendarProximo();
}

function fecharGuia() {
  clearTimeout(guiaRelogio);
  guia.hidden = true;
  try { localStorage.setItem(GUIA_VISTO, '1'); } catch (e) { /* sessão anônima, tudo bem */ }
}

/* Tocar em qualquer lugar adianta — quem lê rápido não fica esperando. */
guia.addEventListener('click', (e) => {
  if (e.target.closest('#guia-pular') || e.target.closest('#guia-fim')) return;
  if (guiaPasso >= GUIA.length - 1) return;
  clearTimeout(guiaRelogio);
  guiaCena.classList.add('sai');
  setTimeout(() => { guiaPasso++; pintarGuia(); agendarProximo(); }, 200);
});

document.getElementById('guia-pular').addEventListener('click', fecharGuia);
guiaFim.addEventListener('click', () => { fecharGuia(); abrirTourCompleto(); });
addEventListener('resize', () => { if (!guia.hidden) desenharSeta(); });

/* O botão da home abre o guia; o tour completo fica no último passo. */
document.getElementById('abrir-tour').addEventListener('click', abrirGuia);

/* Primeiro acesso: espera o splash sair para não competir com ele. */
(function guiaNoPrimeiroAcesso() {
  let visto = false;
  try { visto = !!localStorage.getItem(GUIA_VISTO); } catch (e) { visto = false; }
  if (visto) return;
  const tentar = () => {
    if (document.getElementById('splash')) return setTimeout(tentar, 400);
    if (guia.hidden && vistas.home.classList.contains('ativa')) abrirGuia();
  };
  setTimeout(tentar, 600);
})();
