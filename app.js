/* ============================================================
   MIND AGENT — a aplicação
   ============================================================
   Conteúdo nenhum mora aqui: a programação vem de `data-service.js`
   e a identidade de quem está usando vem de `config.js`. Este arquivo
   só desenha e reage.
*/

import { CONFIG, PARTICIPANTE, capturarIdentidade, primeiroNome } from './config.js';
import { carregarDadosSummit, carregarHomeDoEvento, carregarIngressoDoParticipante } from './data-service.js';
import { montarHome } from './home/home.js';
import { definirMomento, definirAvisos, definirMomentoDoServidor, momentoDoServidor } from './home/estado.js';
import { listaDeAvisos, leituraDeAviso, marcarLido, naoLidos } from './home/avisos.js';
import { enviarMensagem, enviarSinalJornada } from './chat-service.js';
import { ligarTeclado, tecladoAberto } from './teclado.js';

/* A altura do app passa a vir do viewport VISUAL, antes de qualquer tela
   aparecer: é o que impede o Safari de rolar a página inteira quando o teclado
   abre. Chamado aqui, no topo, porque toda vista depende dessa altura. */
ligarTeclado();

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
/* TOCAR EM QUALQUER LUGAR FECHA. O "Pular" é uma pílula de 13px no canto
   superior; quem está olhando o símbolo no meio da tela não procura lá. Sem
   isto, a única saída da abertura é esperar — e esperar sem saber quanto é o
   que faz uma tela parecer travada. */
splash.addEventListener('click', fecharSplash);

/* A ABERTURA É UMA VEZ POR SESSÃO. Ela dura alguns segundos de propósito: é a
   marca se apresentando a quem chega. Repetir isso a cada recarga transforma
   apresentação em pedágio — e recarregar é exatamente o que a pessoa faz
   quando acha que travou. Quem já viu entra direto. */
const CHAVE_ABERTURA = 'mindagent:v1:abertura-vista';
let jaViuAbertura = false;
try {
  jaViuAbertura = sessionStorage.getItem(CHAVE_ABERTURA) === '1';
  sessionStorage.setItem(CHAVE_ABERTURA, '1');
} catch (e) { /* aba anônima: mostra a abertura, que é o comportamento antigo */ }

/* A fala vem digitada. Cada letra é um span que acende: assim o "Mind" em
   coral atravessa a animação sem precisar recortar HTML no meio. */
const FALA = [
  ['Oi, eu sou o agente do ', false], ['Mind', true],
  [' e estou aqui para responder qualquer dúvida sobre o evento.', false],
];
(function digitar() {
  /* Já viu nesta sessão: sai sem fade e sem animação. Nada de meio segundo de
     cortesia para quem só recarregou a página. */
  if (jaViuAbertura) { splash.remove(); return; }

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

  /* O RITMO DA ABERTURA, num lugar só — é aqui que se afina se ela ficar
     comprida ou curta demais.

     Era `ATRASO 900 + PASSO 26 + LEITURA 4000`: com 88 caracteres, quase 7,2s
     até a tela começar a sair, mais 0,55s de fade. Oito segundos parado no
     símbolo do Mind, e foi assim que a abertura passou a ser lida como tela
     travada — porque, do lado de quem espera, não há diferença entre uma
     animação longa e um app que não carrega.

     A frase continua sendo digitada e continua legível. O que encolheu foi a
     espera DEPOIS que ela termina, que era mais da metade do tempo total. */
  const ATRASO  = 350;    /* antes de a primeira letra acender */
  const PASSO   = 16;     /* por letra */
  const LEITURA = 1500;   /* com a frase inteira na tela, antes de sair */

  if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
    letras.forEach((g) => g.classList.add('on'));
    setTimeout(fecharSplash, LEITURA);
    return;
  }
  letras.forEach((g, i) => setTimeout(() => {
    g.classList.add('on');
    g.after(cursor);              /* o cursor anda junto, não fica no fim do texto todo */
  }, ATRASO + i * PASSO));
  setTimeout(fecharSplash, ATRASO + letras.length * PASSO + LEITURA);
})();

/* ---------- Navegação entre vistas ---------- */
const vistas = {
  home: document.getElementById('vista-home'),
  avisos: document.getElementById('vista-avisos'),
  chat: document.getElementById('vista-chat'),
  summit: document.getElementById('vista-summit'),
  tour: document.getElementById('vista-tour'),
};
function abrirVista(nome, opcoes) {
  Object.entries(vistas).forEach(([n, el]) => el.classList.toggle('ativa', n === nome));
  if (nome === 'chat') iniciarChat(opcoes);
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

/* ---------- Home V3: as ações dos cards ----------
   Os cards não navegam nem chamam backend: avisam o que foi pedido e a
   decisão mora aqui. É o único ponto que conhece as duas pontas, e é por
   ele que a integração real vai entrar. */
function irParaConversa(intencao) {
  abrirVista('chat', { comAssunto: Boolean(intencao) });
  if (intencao) setTimeout(() => abrirIntencao(intencao), 200);
}

function acaoDaHome(acao) {
  if (!acao) return;
  /* Não existe mais tour rápido: o card abre a prática direto. */
  if (acao === 'tour') return abrirTourCompleto();
  /* `roteiro:` faz o CAMINHO ate a tela; `tour:` mostra a tela sozinha.
     São promessas diferentes e por isso são ações diferentes. */
  if (acao.startsWith('roteiro:')) return abrirTourCompleto(acao.slice(8));
  if (acao.startsWith('tour:')) return abrirTutorialEm(acao.slice(5));
  if (acao === 'jornada') return irParaConversa('jornada');
  if (acao.startsWith('chat:')) return irParaConversa('desafio');
  if (acao === 'insight') return irParaConversa('insight');
  if (acao === 'entrevista') return irParaConversa('plano');
  if (acao === 'insights') return abrirVista('summit');
  if (acao === 'avisos') return abrirAvisos();
  if (acao.startsWith('aviso:')) return abrirAvisos(acao.slice(6));
  if (acao.startsWith('em-breve:')) return painelEmBreve(acao.slice(9));
  return irParaConversa(null);
}

/* ---------- A próxima experiência ----------
   Lê a grade de verdade: pega o que ainda vai começar hoje, olha o
   horário mais próximo e, entre as sessões que começam junto, escolhe a
   que mais conversa com os temas que a pessoa já demonstrou. Sem tema
   escolhido não há preferência — vale a ordem da grade. */
const MINUTOS = (h) => Number(h.slice(0, 2)) * 60 + Number(h.slice(3, 5));

/* Fora dos dias do evento não existe "agora" na grade. Para o momento de
   demonstração, um instante fixo da manhã do primeiro dia.
   API: no ar, isto é só `new Date()`. */
const INSTANTE_DEMO = '08:50';

function agoraNoEvento() {
  const dias = ((DADOS && DADOS.evento && DADOS.evento.dias) || [])
    .filter((dia) => typeof dia === 'string');
  if (!dias.length) return null;
  const hoje = new Date();
  const iso = hoje.getFullYear() + '-' +
    String(hoje.getMonth() + 1).padStart(2, '0') + '-' +
    String(hoje.getDate()).padStart(2, '0');
  if (dias.includes(iso)) {
    return { dia: iso, hora: String(hoje.getHours()).padStart(2, '0') + ':' +
                            String(hoje.getMinutes()).padStart(2, '0'), real: true };
  }
  return { dia: dias[0], hora: INSTANTE_DEMO, real: false };
}

function proximaExperiencia() {
  if (!DADOS || !DADOS.sessoes) return null;
  const agora = agoraNoEvento();
  if (!agora) return null;
  const adiante = DADOS.sessoes.filter((s) => s.dia === agora.dia && s.inicio >= agora.hora);
  if (!adiante.length) return null;
  const cedo = adiante.reduce((menor, s) => (s.inicio < menor ? s.inicio : menor), '99:99');
  /* Empate de horário é onde a preferência decide. */
  const escolhida = adiante
    .filter((s) => s.inicio === cedo)
    .map((s) => ({ s, peso: afinidade(s.temas) || 0 }))
    .sort((a, b) => b.peso - a.peso)[0].s;
  return { sessao: escolhida, minutos: Math.max(0, MINUTOS(cedo) - MINUTOS(agora.hora)) };
}

/* ============================================================
   EM QUE PALESTRA A PESSOA ESTÁ
   ============================================================
   Não há check-in por sala: o app não tem como saber. Então ele
   pergunta — e pergunta com o que a grade permite responder, as sessões
   que estão no ar naquele minuto. A resposta fica guardada na sessão do
   navegador porque quem anota uma vez costuma anotar de novo na mesma
   palestra, e perguntar duas vezes a mesma coisa é ruído.

   MOCK: API: hoje é sessionStorage. Vai virar campo do participante
   quando a home tiver backend — a leitura e a escrita já estão nestas
   duas funções, e só nelas. */
const CHAVE_SESSAO = 'mindagent:v1:sessao-do-insight';

function sessoesNoAr() {
  if (!DADOS || !DADOS.sessoes) return [];
  const agora = agoraNoEvento();
  if (!agora) return [];
  const doDia = DADOS.sessoes.filter((s) => s.dia === agora.dia);
  const noAr = doDia.filter((s) => s.inicio <= agora.hora && (!s.fim || agora.hora < s.fim));
  if (noAr.length) return noAr;
  /* Intervalo, ou o dia ainda não começou: oferece o que está ao redor
     em vez de deixar a pessoa sem opção nenhuma. */
  const passou = doDia.filter((s) => s.inicio <= agora.hora).slice(-1);
  const vem = doDia.filter((s) => s.inicio > agora.hora).slice(0, 2);
  return [...passou, ...vem];
}

function sessaoDoInsight() {
  if (!DADOS || !DADOS.sessoes) return null;
  let id = null;
  try { id = sessionStorage.getItem(CHAVE_SESSAO); } catch (e) { /* modo restrito */ }
  return id ? DADOS.sessoes.find((s) => s.id === id) || null : null;
}

function definirSessaoDoInsight(id) {
  try { sessionStorage.setItem(CHAVE_SESSAO, id); } catch (e) { /* modo restrito */ }
}

/* O que a home não sabe calcular sozinha. */
function contextoDaHome() {
  const agora = agoraNoEvento();
  const ctx = {
    hora: agora ? Number(agora.hora.slice(0, 2)) : new Date().getHours(),
    remontar: montarHomeV3,
  };
  if (ingressoDoParticipante) ctx.ingresso = ingressoDoParticipante;
  const emCurso = sessaoDoInsight();
  if (emCurso) ctx.sessaoDoInsight = emCurso.titulo;
  const p = proximaExperiencia();
  if (!p) return ctx;
  /* Etiqueta curta, não frase: o card logo abaixo já diz a hora, a sala
     e o nome. Repetir a contagem em texto é dizer duas vezes. */
  ctx.resumoDaProxima = p.minutos === 0 ? 'Começando agora:' : 'Começa em breve:';
  ctx.proxima = {
    hora: p.sessao.inicio + (p.sessao.espaco ? ', ' + p.sessao.espaco : ''),
    titulo: p.sessao.titulo,
    texto: p.sessao.quem && !/^(em breve|em curadoria)$/i.test(p.sessao.quem) ? p.sessao.quem : '',
  };
  return ctx;
}

function montarHomeV3() {
  montarHome(document.getElementById('home-v3'), acaoDaHome, contextoDaHome());
  atualizarContadorAvisos();
  ligarContagem();
}

/* ---------- O TIPO DE INGRESSO NO CABEÇALHO ----------
   Aparece em dois lugares, com um dado só: a pílula ao lado do `?`, que
   mora na barra de cima e fica fora da home, e a sobrancelha do hero,
   que é da home e vem por `contextoDaHome`.

   Quem sabe o tipo é o espelho do credenciamento, e a única chave que o
   app tem é o e-mail que a Yazo mandou. Sem e-mail, sem rede, ou com um
   ingresso sem tipo mapeado, `carregarIngressoDoParticipante` devolve
   `null` — e aí nada acontece: o cabeçalho continua exatamente o que
   era. Não há estado de carregando, porque não há nada a esperar; se a
   resposta chega, a pílula aparece e a home é remontada. */
let ingressoDoParticipante = null;
const ingressoEl = document.getElementById('perfil-ingresso');

carregarIngressoDoParticipante(PARTICIPANTE.email).then((tipo) => {
  if (!tipo || !ingressoEl) return;
  ingressoDoParticipante = tipo;
  ingressoEl.querySelector('b').textContent = tipo;
  ingressoEl.hidden = false;
  montarHomeV3();
});

/* ---------- Contagem regressiva até a abertura ----------
   07:00 do primeiro dia, quando abre o credenciamento. Este número NÃO é
   mais o mesmo da virada da tela: a programação do painel leva a home
   para "no evento" à meia-noite do dia 16, e a contagem continua mirando
   a abertura do credenciamento. São duas perguntas diferentes — "que tela
   é esta?" e "quanto falta para começar?" — e desde que a programação
   existe elas têm respostas próprias. Se a abertura mudar, muda aqui; a
   virada da tela muda no painel, em Home V3 › Visualização.

   API: o alvo virá do evento, junto com a data. */
const HORA_DE_ABERTURA = 7;
let relogioContagem = null;

function inicioDoEvento() {
  const dias = ((DADOS && DADOS.evento && DADOS.evento.dias) || [])
    .filter((data) => typeof data === 'string');
  if (!dias.length) return null;
  const [ano, mes, dia] = dias[0].split('-').map(Number);
  if (!ano || !mes || !dia) return null;
  /* Construído em partes, não por `new Date(iso)`: string sem fuso é
     lida como UTC em alguns navegadores, e a contagem sairia com três
     horas de diferença. */
  return new Date(ano, mes - 1, dia, HORA_DE_ABERTURA, 0, 0, 0);
}

/** Só os dias na tela, ou null quando o tempo acabou.
 *
 *  A conta continua ao segundo por dentro: é ela que vira a tela na hora
 *  exata. O que muda é o que se mostra — hora e minuto correndo na
 *  manchete puxavam o olho para o relógio em vez do conteúdo.
 *
 *  Conta os dias inteiros que ainda faltam, e não as frações: com 14 dias
 *  e meio pela frente, faltam 14 dias. No último dia não existe "faltam 0
 *  dias" — vira "é hoje". */
function textoDaContagem(restante) {
  if (restante <= 0) return null;
  const dias = Math.floor(restante / 86400000);
  if (dias === 0) return 'é hoje';
  return dias === 1 ? 'falta 1 dia' : 'faltam ' + dias + ' dias';
}

function ligarContagem() {
  /* Sempre desliga antes: a home é remontada a cada troca de momento, e
     sem isto os relógios se empilhariam. */
  if (relogioContagem) { clearInterval(relogioContagem); relogioContagem = null; }

  const alvo = document.getElementById('v3-contagem');
  if (!alvo) return;                      /* momento sem contagem */
  const inicio = inicioDoEvento();
  if (!inicio) { alvo.textContent = ''; return; }

  const bater = () => {
    const texto = textoDaContagem(inicio.getTime() - Date.now());
    if (texto === null) {
      /* Zerou: o evento começou. */
      clearInterval(relogioContagem);
      relogioContagem = null;
      /* Com o painel no comando, a virada é dele — duas autoridades
         decidindo a mesma tela é como se perde o controle no dia. O
         relógio só vira sozinho quando ninguém está mandando de fora. */
      if (!momentoDoServidor()) definirMomento('no-evento');
      montarHomeV3();
      return;
    }
    alvo.textContent = texto;
  };
  bater();
  /* De meio em meio minuto: o texto só muda uma vez por dia, mas a virada
     da tela precisa acontecer perto do horário — meio minuto de atraso é
     aceitável, uma hora não. */
  relogioContagem = setInterval(bater, 30000);
}

/* ---------- Painel da home ----------
   Uma folha só, três conteúdos: "em breve", a lista de avisos e um aviso
   aberto. Voltar da lista para o aviso e vice-versa não recarrega nada. */
const painelFundo = document.getElementById('painel-fundo');
const painelCartao = document.getElementById('painel-cartao');
let focoAntesDoPainel = null;

function abrirPainel(titulo, corpo, rodape) {
  focoAntesDoPainel = document.activeElement;
  painelCartao.innerHTML =
    '<div class="p-topo"><h3 id="painel-titulo">' + titulo + '</h3>' +
    '<button type="button" class="p-fechar" aria-label="Fechar">×</button></div>' +
    '<div class="p-corpo"></div>';
  painelCartao.querySelector('.p-corpo').appendChild(corpo);
  if (rodape) painelCartao.appendChild(rodape);
  painelCartao.querySelector('.p-fechar').addEventListener('click', fecharPainel);
  painelFundo.classList.add('aberto');
  painelCartao.querySelector('.p-fechar').focus();
}

function fecharPainel() {
  painelFundo.classList.remove('aberto');
  if (focoAntesDoPainel && focoAntesDoPainel.isConnected) focoAntesDoPainel.focus();
  focoAntesDoPainel = null;
}
painelFundo.addEventListener('click', (e) => { if (e.target === painelFundo) fecharPainel(); });
painelFundo.addEventListener('keydown', (e) => { if (e.key === 'Escape') fecharPainel(); });

const EM_BREVE = {
  diagnostico: {
    titulo: 'Diagnóstico de maturidade',
    texto: 'É uma entrevista guiada de sete minutos sobre como a sua empresa cuida hoje de bem-estar e performance. O resultado sai depois do Summit, cruzado com o que você viveu aqui.',
    nota: 'Ainda não está no ar. Assim que abrir, ele aparece nesta mesma tela.',
  },
  resultado: {
    titulo: 'Resultado do diagnóstico',
    texto: 'O resultado reúne as lacunas que a entrevista identificou e sugere por onde começar na sua empresa.',
    nota: 'Ainda não está no ar. Ele é liberado depois do Summit.',
  },
};

function painelEmBreve(qual) {
  const c = EM_BREVE[qual] || EM_BREVE.diagnostico;
  const corpo = document.createElement('div');
  corpo.className = 'p-breve';
  corpo.innerHTML = '<span class="p-selo">Disponível em breve</span>' +
    '<p>' + c.texto + '</p><p class="p-nota">' + c.nota + '</p>';
  abrirPainel(c.titulo, corpo);
}

/* ---------- Avisos: uma tela, dois níveis ----------
   Sem id, mostra a lista; com id, mostra o aviso. O voltar sabe onde
   está: da leitura volta para a lista, da lista volta para a home. */
const avisosCorpo = document.getElementById('avisos-corpo');
const avisosTitulo = document.getElementById('avisos-titulo');
const avisosSub = document.getElementById('avisos-sub');
let avisoAberto = null;

function abrirAvisos(id) {
  avisoAberto = id || null;
  avisosCorpo.innerHTML = '';
  avisosCorpo.scrollTop = 0;

  if (avisoAberto) {
    /* Abrir É ler: a marcação acontece aqui, não num botão de "marcar
       como lido" que ninguém tocaria. */
    marcarLido(avisoAberto);
    avisosTitulo.textContent = 'Aviso';
    avisosSub.textContent = 'De volta para a lista pelo ‹';
    /* O aviso aponta para um roteiro, não para uma tela solta: quem toca
       em "ver onde fica" quer ser levado, não largado numa tela. */
    /* `verNoApp` levava só a roteiro da demonstração. O aviso "Precisa de
       ajuda para reservar?" precisa de outro destino: o Concierge é uma
       vista do app, não uma tela do app do Summit. */
    avisosCorpo.appendChild(leituraDeAviso(avisoAberto, (destino) => {
      /* Três destinos, e o de fora é o único que sai do app: material que
         mora no YouTube não tem como ser uma tela daqui. `noopener` porque
         a aba nova não precisa — nem deve — alcançar esta. */
      if (/^https:\/\//.test(destino)) return window.open(destino, '_blank', 'noopener');
      if (destino === 'chat') return irParaConversa(null);
      abrirTourCompleto(destino);
    }));
  } else {
    avisosTitulo.textContent = 'Avisos importantes';
    const n = naoLidos();
    avisosSub.textContent = n === 0
      ? 'Você está em dia'
      : n === 1 ? '1 não lido' : n + ' não lidos';
    avisosCorpo.appendChild(listaDeAvisos((escolhido) => abrirAvisos(escolhido)));
  }
  abrirVista('avisos');
  atualizarContadorAvisos();
}

document.getElementById('avisos-voltar').addEventListener('click', () => {
  if (avisoAberto) return abrirAvisos();   /* leitura → lista */
  abrirVista('home');                       /* lista → home */
  montarHomeV3();                           /* o contador acompanha */
});

/* O contador vive no título da seção de avisos da home. Ele existe para
   chamar atenção — e some sozinho quando não há o que chamar. */
function atualizarContadorAvisos() {
  const n = naoLidos();
  document.querySelectorAll('#home-v3 .v3-secao').forEach((secao) => {
    const h = secao.querySelector('h2');
    const link = secao.querySelector('.v3-link');
    if (!h || !link || !/avisos/i.test(h.textContent || '')) return;
    let selo = link.querySelector('.v3-contador');
    if (n === 0) { if (selo) selo.remove(); return; }
    if (!selo) {
      /* Colado no "Ver todos": é o que a pessoa vai tocar. Ao lado do
         título ele só informava; aqui ele puxa para a ação. */
      selo = document.createElement('span');
      selo.className = 'v3-contador';
      link.appendChild(selo);
    }
    selo.textContent = String(n);
    selo.setAttribute('aria-label', n === 1 ? '1 aviso não lido' : n + ' avisos não lidos');
  });
}
document.getElementById('btn-perfil').addEventListener('click', () => abrirVista('summit'));

/* Campo da home → chat */
const campoHome = document.getElementById('campo-home');

/* Tocar na barra já abre a conversa. Sem isto, quem volta para a home só
   reencontra o histórico mandando outra mensagem — a conversa existe, mas
   fica invisível.

   Trocar de vista e mover o foco acontecem no MESMO evento, de propósito:
   no celular, focar outro campo fora do gesto do usuário fecha o teclado. */
function abrirConversa(comAssunto) {
  if (vistas.chat.classList.contains('ativa')) return;
  const rascunho = campoHome.value;
  campoHome.value = '';
  abrirVista('chat', { comAssunto: Boolean(comAssunto) });
  if (rascunho) campoChat.value = rascunho;
  campoChat.focus();
  /* Voltar para a conversa é voltar para o fim dela, não para onde parou
     a rolagem. */
  mensagens.scrollTop = mensagens.scrollHeight;
}

campoHome.addEventListener('focus', abrirConversa);

/* O "enviar" do teclado do celular tem de mandar a mensagem. Form com
   campo de texto e botão submit já faz isso por especificação, mas em
   teclado virtual o caminho passa pelo IME: parte dos Android entrega a
   tecla como composição (keyCode 229) e não submete nada. Aqui o envio é
   explícito, e o preventDefault impede o envio dobrado onde o
   comportamento nativo funciona. */
function enviarComEnter(form) {
  const campo = form.querySelector('input[type="text"]');
  if (!campo) return;
  campo.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter' || e.isComposing || e.keyCode === 229) return;
    e.preventDefault();
    if (form.requestSubmit) form.requestSubmit();
    else form.dispatchEvent(new Event('submit', { cancelable: true }));
  });
}

/* Continua valendo para quem digitar e mandar sem passar pelo foco —
   autofill, teclado físico, automação. */
document.getElementById('form-home').addEventListener('submit', (e) => {
  e.preventDefault();
  const v = campoHome.value.trim();
  campoHome.value = '';
  abrirConversa(Boolean(v));
  if (v) setTimeout(() => perguntar(v), 200);
});
enviarComEnter(document.getElementById('form-home'));
/* O microfone saiu dos dois campos: ele não gravava nada — na home só
   dava foco, e no chat não tinha ação nenhuma. Botão que não faz o que
   desenha é promessa quebrada. */

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
  /* ESTRELA, não robô. No app o Concierge é uma estrela; o robozinho era do
     tempo em que a aba se chamava "Mind" e representava um agente. Ícone e
     rótulo são a mesma promessa — a pessoa procura os dois juntos na barra. */
  agente: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M12 3l2.6 5.6 6.1.8-4.5 4.2 1.2 6-5.4-3-5.4 3 1.2-6L3.3 9.4l6.1-.8z"/></svg>',
  agenda: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3" y="4" width="18" height="17" rx="3"/><path d="M8 2v4M16 2v4M3 9h18"/></svg>',
  minha:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3" y="4" width="18" height="17" rx="3"/><path d="M8 2v4M16 2v4M3 9h18M8.5 14.5l2.5 2.5 4.5-4.5"/></svg>',
  qr:     '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><path d="M14 14h3v3h-3zM20 14h1M14 20h1M18 18h3v3h-2"/></svg>',
  menu:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9"><path d="M4 6h16M4 12h16M4 18h16"/></svg>',
};

/* OS NOMES SÃO OS DO APP DE VERDADE, e é o app que manda.
   O tour existe para ensinar onde as coisas ficam; ensinar um nome que a
   pessoa não vai encontrar é pior do que não ensinar. Os rótulos aqui eram
   "Mind · Agenda · Minha · Ingresso · Menu" — encurtados na época para caber
   em 360px — enquanto o app hoje mostra "Concierge · Programação · Minha
   Agenda · Ingresso · Menu". Quem fizesse o tour aprenderia a procurar
   "Agenda" pela programação, que no app é outro menu.

   `rotulo` volta a ser igual a `nome`: o app cabe com os nomes inteiros, e
   duas grafias para o mesmo menu é como a divergência nasce de novo. O
   tamanho da fonte da barra passou a se ajustar ao rótulo mais longo — ver
   `.fnav` em `styles.css`.

   Os `id` e os destinos (`vai`) NÃO mudam: são chaves internas amarradas às
   capturas de tela do tour e às missões. O que a pessoa lê é `rotulo`. */
const ABAS = [
  { id: 'agente', rotulo: 'Concierge',    nome: 'Concierge',    ico: ICO.agente, folha: 'agente' },
  { id: 'agenda', rotulo: 'Programação',  nome: 'Programação',  ico: ICO.agenda, vai: 'agenda' },
  { id: 'minha',  rotulo: 'Minha Agenda', nome: 'Minha Agenda', ico: ICO.minha,  vai: 'minha-agenda' },
  { id: 'qr',     rotulo: 'Ingresso',     nome: 'Ingresso',     ico: ICO.qr,     vai: 'scanner' },
  { id: 'menu',   rotulo: 'Menu',         nome: 'Menu',         ico: ICO.menu,   vai: 'menu' },
];

/* Popups do app, refeitos em HTML */
const FOLHAS = {
  agente: { titulo: 'Concierge', texto: 'Oi! É aqui que eu moro dentro do app. Me chame para dúvidas do evento, sugestão de conteúdo, bios de palestrantes e logística.', botao: 'Legal!' },
  contato: { titulo: 'Solicitação enviada', texto: 'Quando a pessoa aceitar, ela entra em Contatos. Enquanto isso fica em Pendentes.', botao: 'Entendi' },
  /* O texto e da Adriana, palavra por palavra. O aviso dos 5 minutos e a
     mesma regra que "Sua reserva vale ate 5 minutos antes" conta na tela
     de avisos: e aqui, no gesto de reservar, que ela pega. */
  /* SEM TÍTULO: o texto já abre com "Seu lugar está reservado!", e um
     `<h3>` dizendo "Lugar reservado!" logo acima repetia a mesma frase
     duas vezes na mesma caixa. */
  reservado: { titulo: null, texto: 'Seu lugar está reservado! Mas atenção: é importante chegar com pelo menos 5 minutos de antecedência para garantir o seu acesso a esta experiência. Faltando cinco minutos para o início, abriremos assentos remanescentes para a fila de espera.', botao: 'Combinado' },
};

/* As telas do app. x/y/w/h em % da foto — remedidos sobre as capturas
   novas (agosto/2026), que trocaram a ordem do Menu e o layout da Agenda.
   `serve` explica para que a tela existe e fica sempre visível no alto. */
const TELAS = {
  'agenda': {
    img: 'agenda', aba: 'agenda', rotulo: 'Programação',
    serve: 'Toda a programação dos dias 16 e 17, por horário e arena. É aqui que você escolhe o que assistir.',
    alvos: [
      { id: 'topo', x: 92.1, y: 4.6, w: 8, h: 4.5, brinde: 'Filtre por trilha, arena e horário.' },
      { id: 'card1', x: 49.9, y: 15.5, w: 92.4, h: 12.5, brinde: 'Cada card é uma sessão. Toque para abrir.' },
      /* Largura inteira: não há mais coração de salvar dividindo a linha. */
      { id: 'card', x: 49.9, y: 65.7, w: 92.4, h: 28.8, vai: 'detalhe', modo: 'push',
        dica: 'Toque na <b>sessão</b> para abrir os detalhes.' },
    ],
  },
  'detalhe': {
    img: 'detalhe', aba: 'agenda', volta: 'agenda', rotulo: 'Sessão',
    serve: 'A página da sessão: descrição, horário, local, palestrantes e a reserva, quando a vaga é limitada.',
    alvos: [
      { id: 'voltar', x: 7.8, y: 4.6, w: 12, h: 4.5, volta: true },
      { id: 'calendario', x: 29.5, y: 47.9, w: 47, h: 4.5, brinde: 'Exporta a sessão para o calendário do seu celular.' },
      { id: 'palestrante', x: 49.9, y: 90.7, w: 88.6, h: 6.9, brinde: 'A bio de quem fala — e o coração salva a pessoa, não a sessão.' },
      { id: 'reservar', x: 49.9, y: 65.7, w: 88.8, h: 4.9, faz: 'reservar', missao: 'm2', vai: 'confirmada', modo: 'troca',
        folha: 'reservado', obrigatoria: true,
        dica: 'Esta sessão tem vaga limitada. Toque em <b>Reservar lugar</b>.' },
    ],
  },
  'confirmada': {
    img: 'confirmada', aba: 'agenda', volta: 'agenda', rotulo: 'Sessão reservada',
    /* O modal que abre em cima já explica o check-in; repetir aqui a
       mesma frase só fazia a tela dizer duas vezes a mesma coisa. */
    serve: 'Sua vaga está garantida nesta sessão.',
    /* Mesma página da sessão, agora no estado reservado: a geometria é a
       de `detalhe`, não a da captura antiga. */
    alvos: [
      { id: 'voltar', x: 7.8, y: 4.6, w: 12, h: 4.5, volta: true },
      { id: 'calendario', x: 29.5, y: 47.9, w: 47, h: 4.5, brinde: 'Exporta a sessão para o calendário do seu celular.' },
      { id: 'confirmacao', x: 49.9, y: 65.7, w: 88.8, h: 4.9,
        brinde: 'No dia da sessão, o check-in é feito aqui mesmo.' },
    ],
  },
  'minha-agenda': {
    img: 'minha-agenda', aba: 'minha', rotulo: 'Minha Agenda',
    serve: 'As sessões que você reservou, em ordem de horário. É aqui que o seu dia toma forma.',
    alvos: [
      { id: 'nova', x: 82, y: 8, w: 30, h: 5, brinde: 'Dá para montar mais de uma agenda.' },
      { id: 'busca', x: 50, y: 14.3, w: 88, h: 5, brinde: 'Busque pelo nome da sessão.' },
      { id: 'sessao', x: 49.9, y: 36, w: 92.4, h: 29.8,
        brinde: 'A sessão que você reservou. No dia, o check-in é aqui dentro.' },
    ],
  },
  /* O QR do perfil fica atrás do leitor: a aba cai no leitor, e "Meu Qr
     Code" leva até aqui. Era o contrário no tour, e não é assim no app. */
  'qrcode': {
    img: 'qrcode', aba: 'qr', volta: 'scanner', rotulo: 'Seu ingresso',
    serve: 'Este QR Code é o seu ingresso e o seu cartão de visita.',
    alvos: [
      { id: 'meucodigo', x: 50, y: 40, w: 70, h: 26,
        brinde: 'É este código que você apresenta na entrada.' },
      { id: 'escanear', x: 49.8, y: 95.9, w: 90, h: 5.8, vai: 'scanner', modo: 'troca',
        brinde: 'Daqui você escaneia o código de outra pessoa.' },
    ],
  },
  'scanner': {
    img: 'scanner', aba: 'qr', rotulo: 'Leitor de QR',
    serve: 'O menu Ingresso abre no leitor. O seu ingresso está atrás de "Meu Qr Code".',
    alvos: [
      { id: 'meuqr', x: 49.8, y: 95.9, w: 90, h: 5.8, vai: 'qrcode', modo: 'push',
        dica: 'Toque em <b>Meu Qr Code</b> para abrir o seu ingresso.' },
    ],
  },
  'menu': {
    img: 'menu', aba: 'menu', rotulo: 'Menu',
    serve: 'Mapa do evento, Área de Networking, e mais!',
    alvos: [
      { id: 'qrmini', x: 90.7, y: 13.9, w: 13, h: 6.5, vai: 'qrcode', modo: 'troca' },
      { id: 'mapa', x: 25.9, y: 28.2, w: 44.4, h: 10.9, vai: 'mapa', modo: 'push', dica: 'Abra o <b>Mapa do evento</b>.' },
      { id: 'rede', x: 74.1, y: 28.2, w: 44.4, h: 10.9, vai: 'rede', modo: 'push', dica: 'Abra a <b>Área de Networking</b>.' },
      { id: 'palestrantes', x: 25.9, y: 41.1, w: 44.4, h: 10.9, vai: 'palestrantes', modo: 'push', dica: 'Abra <b>Palestrantes</b>.' },
      { id: 'chat', x: 25.9, y: 54.1, w: 44.4, h: 10.9, vai: 'chat', modo: 'push', dica: 'Abra o <b>Chat</b> — é onde eu fico.' },
      { id: 'qrtile', x: 74.1, y: 54.1, w: 44.4, h: 10.9, vai: 'qrcode', modo: 'troca' },
    ],
  },
  'mapa': {
    img: 'mapa', aba: 'menu', volta: 'menu', rotulo: 'Mapa do evento',
    serve: 'Arenas, lounges, estandes e banheiros do São Paulo Expo — com filtro por tipo de espaço.',
    alvos: [
      { id: 'voltar', x: 7.7, y: 4.7, w: 12, h: 4.5, volta: true, dica: 'Toque em <b>‹</b> para voltar ao Menu.' },
      { id: 'filtroArenas', x: 33.8, y: 41.3, w: 18.5, h: 4.5, faz: 'filtrar',
        brinde: 'Só as arenas. A Arena Mind é a maior — fica à esquerda.' },
    ],
  },
  'rede': {
    img: 'rede', aba: 'menu', volta: 'menu', rotulo: 'Área de Networking',
    serve: 'Quem está no evento. Envie convite, acompanhe contatos aceitos e pedidos pendentes.',
    alvos: [
      { id: 'voltar', x: 7.7, y: 2.2, w: 12, h: 4.5, volta: true, dica: 'Toque em <b>‹</b> para voltar ao Menu.' },
      { id: 'abas', x: 50, y: 8.4, w: 70, h: 5, brinde: 'Contatos aceitos e convites pendentes.' },
      { id: 'add1', x: 81.4, y: 27.1, w: 24, h: 6, faz: 'contato', missao: 'm6', folha: 'contato', obrigatoria: true,
        dica: 'Toque em <b>Adicionar</b> para enviar um convite de contato.' },
    ],
  },
  'palestrantes': {
    img: 'palestrantes', aba: 'menu', volta: 'menu', rotulo: 'Palestrantes',
    serve: 'Todos os nomes do Summit, com bio e as sessões de cada um. O coração salva a pessoa.',
    alvos: [
      { id: 'voltar', x: 7.7, y: 4.7, w: 12, h: 4.5, volta: true, dica: 'Toque em <b>‹</b> para voltar ao Menu.' },
      { id: 'busca', x: 50, y: 11.5, w: 88, h: 5, brinde: 'Busque pelo nome de quem você quer ver.' },
      { id: 'fav1', x: 89.7, y: 20.5, w: 12, h: 5, faz: 'favoritar-pal', brinde: 'Palestrante salvo 💚' },
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
  'scanner': { aba: 'qr' },
  'menu': { aba: 'menu' },
  'detalhe': { de: 'agenda', alvo: 'card' },
  'confirmada': { de: 'detalhe', alvo: 'reservar' },
  'minha-agenda-17': { de: 'minha-agenda', alvo: 'chip17' },
  'qrcode': { de: 'scanner', alvo: 'meuqr' },
  'mapa': { de: 'menu', alvo: 'mapa' },
  'rede': { de: 'menu', alvo: 'rede' },
  'palestrantes': { de: 'menu', alvo: 'palestrantes' },
  'chat': { de: 'menu', alvo: 'chat' },
};

/* ============================================================
   ROTEIROS
   ============================================================
   Cada roteiro é um tutorial curto e fechado: uma pergunta prática, os
   passos para respondê-la, e o texto do fim. Nada de tour geral.

   `reserva` é o da home. `ingresso` sai do aviso "Seu ingresso está
   aqui" e responde só onde fica o QR — de propósito: quem toca ali quer
   o ingresso, não uma volta pelo app. */
const ROTEIROS = {
  reserva: {
    nome: 'Lugar reservado',
    de: 'agenda',
    missoes: [
      { id: 'm2', txt: 'Reservar seu lugar numa sessão', tela: 'detalhe', alvo: 'reservar' },
      { id: 'm3', txt: 'Ver a reserva na sua agenda', tela: 'minha-agenda' },
    ],
    concluido: 'Pronto — você já sabe reservar 💚',
  },
  /* O MAPA NAO SE ACHA SOZINHO. Ele mora dentro do Menu, e e justamente
     isso que precisa ser ensinado — abrir a tela do mapa direto mostraria
     o mapa e esconderia o caminho. Por isso este roteiro comeca no Menu e
     pede o toque em "Mapa do evento". `ROTA` ja sabe que `mapa` vem de
     `menu` pelo alvo `mapa`, entao a dica e o anel saem prontos. */
  mapa: {
    nome: 'Mapa do evento',
    de: 'menu',
    missoes: [
      { id: 'p1', txt: 'Abrir o Mapa do evento', tela: 'mapa' },
    ],
    concluido: 'Pronto — o mapa fica no Menu 💚',
  },
  ingresso: {
    /* Começa já no leitor, que é onde a aba cai. Um passo só. */
    nome: 'Seu ingresso',
    de: 'scanner',
    missoes: [
      { id: 'i1', txt: 'Abrir o seu ingresso', tela: 'qrcode' },
    ],
    concluido: 'Pronto — o seu ingresso está aí 💚',
  },
};

let roteiroAtual = 'reserva';
let MISSOES = ROTEIROS.reserva.missoes;
/* Quando a pessoa toca num ATALHO da home, ela pediu UMA tela — "Meu
   ingresso" —, não um roteiro. Com esta bandeira ligada a demonstração
   abre a tela sozinha: sem missão pendurada, sem barra de progresso e
   sem dica. Era o defeito de 02/09: o atalho trocava a tela mas deixava
   o roteiro de reserva rodando por baixo, e o anel circulava
   "Programação" enquanto a pessoa estava em "Minha Agenda". */
let telaAvulsa = null;

const frame = document.getElementById('frame');
const conteudo = document.getElementById('conteudo');
const telaImg = document.getElementById('tela-img');
const balao = document.getElementById('balao');
const explica = document.getElementById('t-explica');
const previa  = document.getElementById('t-previa');
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
/* O caminho de volta do voltar. Zerado sempre que se anda para a frente. */
let refazer = [];
let feitas = new Set();
const marcas = {};
let timerBrinde;

/* --- barra de abas (HTML de verdade) --- */
ABAS.forEach((aba) => {
  const b = document.createElement('button');
  b.type = 'button';
  b.dataset.aba = aba.id;
  b.innerHTML = aba.ico + '<span>' + aba.rotulo + '</span>';
  b.setAttribute('aria-label', aba.nome);   /* o rótulo é curto por espaço; o nome inteiro fica aqui */
  b.addEventListener('click', () => {
    if (aba.folha) { abrirFolha(aba.folha); return; }
    if (TELAS[telaAtual].aba === aba.id && !TELAS[telaAtual].volta) { avisar('Você já está aqui.'); return; }
    pilha = []; refazer = [];
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

/* `aoConfirmar` existe para o modal obrigatório: a missão só avança
   depois que a pessoa leu e fechou. Enquanto ele está aberto, o modal
   também prende o foco e devolve para quem o abriu. */
let focoAntesDaFolha = null;
let folhaObrigatoria = null;

function abrirFolha(nome, aoConfirmar) {
  const f = FOLHAS[nome];
  if (!f) return;
  folhaObrigatoria = aoConfirmar || null;
  /* A navegação já pintou a dica antes de o modal abrir. Repinta para
     apagá-la: com o modal obrigatório em cima, ela não é acionável e só
     contradiz o botão. `fecharFolha` repinta de novo e ela volta. */
  if (folhaObrigatoria) pintar();
  focoAntesDaFolha = document.activeElement;
  folhaEl.setAttribute('role', 'dialog');
  folhaEl.setAttribute('aria-modal', 'true');
  /* SEM TÍTULO, o rótulo do diálogo passa a ser o próprio texto. Um
     `aria-labelledby` apontando para um `<h3>` que não existe deixa o
     leitor de tela anunciar um diálogo sem nome. */
  if (f.titulo) {
    folhaEl.setAttribute('aria-labelledby', 'folha-titulo');
    folhaEl.removeAttribute('aria-label');
  } else {
    folhaEl.removeAttribute('aria-labelledby');
    folhaEl.setAttribute('aria-label', f.texto || 'Aviso');
  }
  folhaEl.innerHTML =
    (f.titulo ? '<h3 id="folha-titulo">' + f.titulo + '</h3>' : '') +
    (f.texto ? '<p>' + f.texto + '</p>' : '') +
    (f.itens ? '<ul>' + f.itens.map((i) => '<li><b>' + i[0] + '</b>' + i[1] + '</li>').join('') + '</ul>' : '') +
    '<button type="button">' + f.botao + '</button>';
  const botao = folhaEl.querySelector('button');
  botao.addEventListener('click', fecharFolha);
  folhaFundo.classList.add('aberta');
  botao.focus();
}

function fecharFolha() {
  folhaFundo.classList.remove('aberta');
  const confirmar = folhaObrigatoria;
  folhaObrigatoria = null;
  if (confirmar) {
    confirmar();
    /* A missão só avançou agora; sem repintar, o anel azul ficaria no alvo
       que a pessoa acabou de usar em vez de apontar o próximo. */
    pintar();
  }
  if (focoAntesDaFolha && focoAntesDaFolha.isConnected) focoAntesDaFolha.focus();
  focoAntesDaFolha = null;
}

/* Modal obrigatório não sai por toque no fundo nem por Esc: ele existe
   justamente para ser lido antes de a próxima instrução aparecer. */
folhaFundo.addEventListener('click', (e) => {
  if (e.target === folhaFundo && !folhaObrigatoria) fecharFolha();
});
folhaFundo.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && !folhaObrigatoria) { e.preventDefault(); fecharFolha(); }
  if (e.key !== 'Tab') return;
  /* prende o foco dentro do modal */
  const focaveis = folhaEl.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
  if (!focaveis.length) return;
  const primeiro = focaveis[0], ultimo = focaveis[focaveis.length - 1];
  if (e.shiftKey && document.activeElement === primeiro) { e.preventDefault(); ultimo.focus(); }
  else if (!e.shiftKey && document.activeElement === ultimo) { e.preventDefault(); primeiro.focus(); }
});

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

/* --- pré-carga: nenhuma etapa começa sem os pixels na mão ---
   Guarda a promessa de cada imagem decodificada. Enquanto a primeira não
   chega, o palco mostra o estado de carregamento em vez de um quadro
   vazio. */
const IMAGENS = new Map();

function prontaTela(nome) {
  if (!IMAGENS.has(nome)) {
    IMAGENS.set(nome, new Promise((resolve) => {
      const im = new Image();
      let feito = false;
      const pronto = () => { if (!feito) { feito = true; resolve(im); } };
      im.onload = pronto;
      im.onerror = pronto;            /* falhou? segue: melhor sem foto que travado */
      im.src = TOUR_IMG_SRC(nome);
      if (im.complete) pronto();
      /* Rede ruim não pode prender o tour. Sem este limite, uma imagem que
         não chega deixa a etapa travada para sempre. */
      setTimeout(pronto, 3000);
    }));
  }
  return IMAGENS.get(nome);
}

function precarregarTour() {
  return Promise.all(Object.values(TELAS).map((t) => prontaTela(t.img)));
}

/* Uma transição de cada vez, e sem toque enquanto ela corre: é o que
   impede toque duplo e acerto em hotspot da etapa anterior. */
let emTransicao = false;
const DURACAO_TROCA = matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : 260;

function travar(v) {
  emTransicao = v;
  frame.classList.toggle('travado', v);
  fnav.classList.toggle('travado', v);
}

const espera = (ms) => new Promise((r) => setTimeout(r, ms));

/* Solta a trava quando o deslize acaba de verdade, não num número fixo.
   Com `espera(260)` sobrava uma fresta: o slide dura 320ms, e nela o
   toque caía onde o alvo ainda não tinha chegado. O teto de 600ms existe
   para aba em segundo plano, onde a animação fica congelada e `finished`
   nunca resolveria. */
function fimDaEntrada() {
  const animacoes = conteudo.getAnimations ? conteudo.getAnimations() : [];
  if (!animacoes.length) return espera(DURACAO_TROCA);
  return Promise.race([
    Promise.all(animacoes.map((a) => a.finished.catch(() => {}))),
    espera(600),
  ]);
}

/* Alvo comprido ganha anel retangular; o redondo cortaria as pontas. */
const ehLargo = (a) => a.w > 40 || a.h > 12 || a.w / a.h > 3;

/* --- desenha a tela atual --- */
/* A seta que aponta o alvo. `deCima` diz de que lado ela chega: vindo de
   cima ela aponta para baixo, e vice-versa. O `<i>` interno existe só
   para a animação — o `<span>` já gasta o `transform` para se centrar, e
   as duas coisas no mesmo nó se anulariam. */
function setaDica(deCima, esquerda, topo) {
  const s = document.createElement('span');
  s.className = 'seta-dica ' + (deCima ? 'baixo' : 'cima');
  s.setAttribute('aria-hidden', 'true');
  s.style.left = esquerda;
  if (topo !== null) s.style.top = topo;
  s.innerHTML = '<i><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
    'stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M12 3v18M12 21l-7-7M12 21l7-7"/></svg></i>';
  return s;
}

function pintar(modo) {
  const tela = TELAS[telaAtual];
  telaImg.src = TOUR_IMG_SRC(tela.img);
  telaImg.alt = 'Tela ' + telaAtual + ' do app';

  conteudo.querySelectorAll('.alvo, .marca, .veu').forEach((el) => el.remove());
  fone.querySelectorAll('.seta-dica').forEach((el) => el.remove());

  /* Com um modal obrigatório aberto, a única ação possível é o botão
     dele. Apontar para a próxima etapa aqui dava duas instruções que se
     contradizem: o anel mandava voltar para a Agenda — refazer a missão
     recém-concluída — enquanto o modal bloqueava qualquer toque. */
  const dica = folhaObrigatoria ? null : calcularDica();

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
      if (ehLargo(a)) b.classList.add('largo');
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
    if (tipo === 'pendente' || tipo === 'escolhido') { el.style.width = alvo.w + '%'; el.style.height = (alvo.h * 0.86) + '%'; }
    if (tipo === 'coracao') {
      el.innerHTML = '<svg viewBox="0 0 24 24" fill="#68ee95"><path d="M12 21s-7.5-4.8-9.5-9A5.4 5.4 0 0 1 12 6.4 5.4 5.4 0 0 1 21.5 12c-2 4.2-9.5 9-9.5 9z"/></svg>';
    } else if (tipo === 'pendente') {
      el.textContent = 'Pendente';
    }
    conteudo.appendChild(el);
  });

  /* PARA QUE SERVE ESTA TELA — no rodapé, fora do print. Antes era uma
     faixa por cima da própria captura: escurecia o topo da tela que a
     demonstração existe para mostrar. Fora dela, a captura fica inteira. */
  explica.textContent = tela.serve || '';

  /* balão azul: só a próxima ação */
  const alvoDica = dica && dica.alvo ? (tela.alvos || []).find((a) => a.id === dica.alvo) : null;
  if (dica && dica.aba) {
    balao.hidden = false;
    balao.className = 'balao acao base';
    balao.innerHTML = '<span class="rot">Próxima ação</span>Toque na aba <b>' +
      ABAS.find((x) => x.id === dica.aba).nome + '</b>, aqui embaixo.';
  } else if (alvoDica && alvoDica.dica) {
    balao.hidden = false;
    /* nunca em cima do alvo: alvo embaixo → balão logo abaixo do rótulo */
    balao.className = 'balao acao ' + (alvoDica.y > 58 ? 'topo' : 'base');
    balao.innerHTML = '<span class="rot">Próxima ação</span>' + alvoDica.dica;
  } else {
    balao.hidden = true;
  }

  /* Véu: a tela escurece e só a próxima ação fica em evidência. O buraco
     é uma sombra gigante em volta do próprio alvo — sem máscara nem SVG,
     e `.frame` tem `overflow: hidden`, então ela para na borda. Quando a
     ação é numa aba, o véu cobre a foto inteira: a barra fica fora dele. */
  if (dica) {
    const veu = document.createElement('span');
    if (alvoDica) {
      const largo = ehLargo(alvoDica);
      veu.className = 'veu' + (largo ? ' largo' : '');
      veu.style.left = alvoDica.x + '%';
      veu.style.top = alvoDica.y + '%';
      if (largo) { veu.style.width = alvoDica.w + '%'; veu.style.height = alvoDica.h + '%'; }
    } else {
      veu.className = 'veu tudo';
    }
    conteudo.appendChild(veu);
  }

  /* SETA: onde tocar, apontado com o dedo.
     O anel pulsante já marcava o lugar, mas anel é sinal de "algo aqui" —
     seta é instrução. Ela nasce do lado do balão e aponta para o alvo,
     então balão, seta e anel contam a mesma coisa na mesma direção.

     `alvoDica.y > 58` é a MESMA conta que escolhe o lado do balão logo
     acima: alvo embaixo manda o balão para o topo, e então a seta desce
     de cima. Duplicar o número aqui deixaria os dois brigando na primeira
     vez que alguém mexesse num só — por isso vem da mesma expressão. */
  if (dica && alvoDica) {
    const deCima = alvoDica.y > 58;
    /* Ancorada na BORDA do alvo, não no centro dele. O cartão de uma
       sessão ocupa um quarto da tela: mirando o centro, a seta caía
       dentro do próprio cartão e apontava para o meio do nada. Da borda,
       a mesma conta serve para o alvo grande e para o pequeno — no
       pequeno a borda quase encosta no centro, e o recuo de 7cqw do CSS
       passa por fora do anel. */
    const borda = deCima ? alvoDica.y - alvoDica.h / 2 : alvoDica.y + alvoDica.h / 2;
    conteudo.appendChild(setaDica(deCima, alvoDica.x + '%', borda + '%'));
  } else if (dica && dica.aba) {
    /* Aba: a seta mora no telefone, não na foto — a barra fica fora do
       `.frame`, e o botão da aba tem `overflow: hidden` por causa dos
       rótulos longos, então ali dentro ela seria cortada. */
    const i = ABAS.findIndex((x) => x.id === dica.aba);
    if (i >= 0) {
      const s = setaDica(true, ((i + 0.5) / ABAS.length) * 100 + '%', null);
      s.classList.add('na-aba');
      fone.appendChild(s);
    }
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

/* Troca atômica: carrega o asset, trava o toque, muda imagem, rótulo,
   progresso, instrução e hotspots JUNTOS, anima, e só então libera. */
async function trocarTela(destino, modo) {
  if (emTransicao || !TELAS[destino]) return;
  travar(true);
  try {
    await prontaTela(TELAS[destino].img);
    telaAtual = destino;
    folhaFundo.classList.remove('aberta');
    /* chegar na tela já cumpre missões que só pedem visita */
    const m = missaoAtual();
    if (m && m.tela === destino && !m.alvo) concluirMissao(m.id);
    pintar(modo);
    await fimDaEntrada();
  } finally {
    travar(false);
  }
}

function irPara(tela, modo) {
  if (!TELAS[tela]) return Promise.resolve();
  if (modo === 'push') pilha.push(telaAtual);
  /* Navegar para a frente por conta própria apaga o "depois", como em
     qualquer histórico: o caminho que existia deixou de ser o caminho. */
  refazer = [];
  return trocarTela(tela, modo || 'troca');
}

/* Existe para onde voltar? A `pilha` é o histórico desta sessão; `volta`
   é o pai declarado da tela, que serve quando se entrou direto nela por
   um atalho da home. Sem nenhum dos dois NÃO se volta — o `|| 'menu'`
   de `voltar()` é um paraquedas para o toque no "‹" desenhado na foto, e
   como resposta a um arrastar ele teletransportaria para o Menu quem só
   queria ver a tela anterior. */
function temVolta() {
  return pilha.length > 0 || Boolean(TELAS[telaAtual] && TELAS[telaAtual].volta);
}

function voltar() {
  const daqui = telaAtual;
  const anterior = pilha.pop() || TELAS[telaAtual].volta || 'menu';
  refazer.push(daqui);
  return trocarTela(anterior, 'pop');
}

/* O "depois": desfaz um voltar. Só anda por onde já se passou, então
   nunca pula a instrução — refazer não é adiantar. */
function avancar() {
  if (!refazer.length) return Promise.resolve();
  const destino = refazer.pop();
  pilha.push(telaAtual);
  return trocarTela(destino, 'push');
}

/* ---------- ARRASTAR PARA VER A TELA ANTERIOR ----------
   Vale para TODAS as demonstrações: é uma só engrenagem, e todas as
   telas passam por ela.

   Arrastar para a DIREITA volta, como no iOS e no Android. Para a
   ESQUERDA refaz o que se voltou — e só isso: `avancar()` anda apenas
   por onde já se passou, então o gesto nunca pula a instrução.

   O gesto convive com os alvos: eles são botões dentro desta mesma área,
   e um dedo que arrasta começa igual a um dedo que toca. Quem decide é a
   distância — passou do limiar, é arrastar, e o `click` que viria em
   seguida é engolido na fase de captura. Sem isso, arrastar por cima de
   um cartão abriria o cartão. */
/* O gesto é invisível, e gesto que ninguém descobre não facilita nada.
   Uma vez por aparelho, ao abrir a primeira demonstração, o próprio aviso
   transitório do tour conta que ele existe. Uma vez, não sempre: quem já
   sabe não precisa ouvir de novo, e o aviso ocupa a mesma faixa que os
   brindes das telas. */
const CHAVE_ARRASTE = 'mindagent:v1:dica-arraste';
function dicaDeArraste() {
  try {
    if (localStorage.getItem(CHAVE_ARRASTE) === '1') return;
    localStorage.setItem(CHAVE_ARRASTE, '1');
  } catch (e) { return; }   /* aba anônima: melhor não avisar do que avisar sempre */
  setTimeout(() => avisar('Arraste para o lado para ver a tela anterior.'), 900);
}

const ARRASTE_MIN = 56;      /* px até virar gesto — abaixo disso é toque */
const ARRASTE_EIXO = 1.4;    /* quanto mais horizontal que vertical */
let arrasteDe = null;
let arrastou = false;

frame.addEventListener('pointerdown', (e) => {
  if (emTransicao || folhaObrigatoria) return;
  arrasteDe = { x: e.clientX, y: e.clientY };
  arrastou = false;
});

frame.addEventListener('pointermove', (e) => {
  if (!arrasteDe || arrastou) return;
  const dx = e.clientX - arrasteDe.x;
  const dy = e.clientY - arrasteDe.y;
  if (Math.abs(dx) < ARRASTE_MIN || Math.abs(dx) < Math.abs(dy) * ARRASTE_EIXO) return;
  arrastou = true;
  if (dx > 0) {
    /* Sem para onde voltar, o gesto não faz nada em silêncio: diz que
       esta é a primeira tela, senão parece que o arrastar não funciona. */
    if (temVolta()) voltar(); else avisar('Esta é a primeira tela.');
  } else if (refazer.length) {
    avancar();
  }
}, { passive: true });

/* O `click` chega depois do `pointerup`; matá-lo aqui, na captura,
   impede que o alvo por baixo do dedo seja acionado pelo arrastar. */
frame.addEventListener('click', (e) => {
  if (!arrastou) return;
  e.stopPropagation();
  e.preventDefault();
  arrastou = false;
}, true);

['pointerup', 'pointercancel', 'pointerleave'].forEach((ev) =>
  frame.addEventListener(ev, () => { arrasteDe = null; }));

async function tocar(a) {
  if (emTransicao) return;                       /* nada de toque duplo */
  if (a.faz === 'favoritar-pal') { marcas[telaAtual] = marcas[telaAtual] || {}; marcas[telaAtual][a.id] = 'coracao'; }
  if (a.faz === 'contato') { marcas[telaAtual] = marcas[telaAtual] || {}; marcas[telaAtual][a.id] = 'pendente'; }
  if (a.faz === 'filtrar') { marcas[telaAtual] = marcas[telaAtual] || {}; marcas[telaAtual][a.id] = 'escolhido'; }

  /* Missão com modal obrigatório só conclui quando a pessoa confirmar:
     senão a instrução já era da etapa seguinte enquanto o "Lugar
     reservado" ainda nem tinha aparecido. */
  const concluir = () => { if (a.missao) concluirMissao(a.missao); };

  if (a.volta) { await voltar(); return; }

  if (a.vai) {
    await irPara(a.vai, a.modo || 'troca');
    if (a.folha) {
      abrirFolha(a.folha, a.obrigatoria ? concluir : null);
      if (!a.obrigatoria) concluir();
    } else concluir();
    if (a.brinde) avisar(a.brinde);
    return;
  }

  if (a.folha) {
    abrirFolha(a.folha, a.obrigatoria ? concluir : null);
    if (!a.obrigatoria) concluir();
  } else concluir();
  if (a.brinde) avisar(a.brinde);
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
  /* O FIM NÃO É MAIS UM POP-UP. Era um cartão por cima de tudo, e ele
     tapava justamente a tela que a pessoa acabou de aprender a usar: para
     voltar a vê-la era preciso fechar mais uma coisa. Agora o fim é a
     mesma faixa transitória dos brindes, com a frase que cada roteiro já
     trazia em `concluido`, e a saída continua sendo o `×`, que fica
     visível o tempo todo.

     O aviso a quem embeda a página continua saindo daqui: o contrato é
     `mindagent:tour-concluido` ao concluir, e ele nunca foi do cartão —
     era só o botão dele que disparava. */
  if (!telaAvulsa && MISSOES.length && feitas.size === MISSOES.length) {
    parent.postMessage({ tipo: 'mindagent:tour-concluido' }, '*');
    const r = ROTEIROS[roteiroAtual];
    if (r && r.concluido) setTimeout(() => avisar(r.concluido), 600);
  }
}

/* "Prévia da tela · não é o seu ingresso" — a segunda metade muda com a
   tela, porque negar a coisa CERTA é o que faz o aviso pegar. Dizer "não
   é o seu app" na tela do ingresso é vago justamente onde a confusão é
   mais cara: é ali que a pessoa tentaria apresentar o código na entrada. */
const NEGA_POR_TELA = {
  qrcode:  'não é o seu ingresso',
  scanner: 'não é o seu ingresso',
  'minha-agenda': 'não é a sua agenda',
  agenda:  'não é a programação ao vivo',
};

function textoDePrevia() {
  const n = NEGA_POR_TELA[telaAtual];
  return 'Prévia da tela' + (n ? ' · ' + n : ' · não é o seu app');
}

function atualizarMissao() {
  previa.textContent = textoDePrevia();
  if (telaAvulsa) {
    const t = TELAS[telaAtual];
    /* `textContent`: o rótulo é constante nossa, mas a barra aceita HTML
       no caminho das missões e não é lugar de abrir exceção. */
    missaoTexto.textContent = (t && t.rotulo) || '';
    missaoProg.innerHTML = '';
    /* Sem roteiro não há missões: o botão que abre a lista sairia vazio. */
    document.getElementById('ver-missoes').hidden = true;
    return;
  }
  document.getElementById('ver-missoes').hidden = false;
  const m = missaoAtual();
  const i = m ? MISSOES.indexOf(m) : MISSOES.length;
  /* NOME DA DEMONSTRAÇÃO, não a missão. O título do frame é irmão de "Seu
     ingresso" e "Mapa do evento" — nome curto de tela. A missão inteira
     ali dentro virava uma frase comprida com um contador que as bolinhas
     ao lado já mostram, e o que fazer agora já está dito no balão coral,
     dentro do quadro, onde a ação acontece. */
  missaoTexto.textContent = ROTEIROS[roteiroAtual].nome
    || (TELAS[telaAtual] && TELAS[telaAtual].rotulo) || '';
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
   primeiro contato: quem chega vê a home, e entra aqui pelo card de como
   reservar ou por `?tutorial=`. */
function abrirTourCompleto(qual) {
  roteiroAtual = ROTEIROS[qual] ? qual : 'reserva';
  const roteiro = ROTEIROS[roteiroAtual];
  telaAvulsa = null;
  MISSOES = roteiro.missoes;
  telaAtual = roteiro.de; pilha = []; refazer = []; feitas = new Set();
  Object.keys(marcas).forEach((k) => delete marcas[k]);
  abrirVista('tour');
  dicaDeArraste();
  medirFone();
  pintar('troca');
  dicaDeArraste();
}
document.getElementById('fechar-tour').addEventListener('click', () => abrirVista('home'));
/* Duas saidas para o mesmo lugar, de proposito: o `x` e o reflexo de quem
   quer fechar, e o botao nomeado e para quem procura o caminho de volta e
   nao arrisca o `x` sem saber onde vai parar. */
document.getElementById('voltar-funcoes').addEventListener('click', () => abrirVista('home'));

/* Pré-carrega assim que o módulo sobe: quando alguém abrir o tour, as
   telas já estão decodificadas e nenhuma etapa começa em branco. */
precarregarTour();

/* ---------- Chat conectado ao Mind Agent ---------- */
const mensagens = document.getElementById('mensagens');
const formChat = document.getElementById('form-chat');
const campoChat = document.getElementById('campo-chat');
let chatIniciado = false;

/* Passos que o agente sabe mostrar. Espelha a tabela `tutorial_passos` do
   Supabase: chave, a tela do app e o elemento que fica destacado. */
const PASSOS = {
  reservar:     { tela: 'detalhe',      alvo: 'reservar', onde: 'Dentro da sessão',
                  aviso: 'A reserva cai 5 minutos antes do início, para abrir a fila de espera.' },
  minha_agenda: { tela: 'minha-agenda', alvo: 'sessao',   onde: 'Menu Minha Agenda' },
  qr:           { tela: 'qrcode',       alvo: 'escanear', onde: 'Menu Ingresso' },
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
  telaAvulsa = tela;
  MISSOES = [];
  feitas = new Set();
  telaAtual = tela;
  pilha = []; refazer = [];
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
  /* O CAMPO NÃO É MAIS DESABILITADO ENQUANTO A RESPOSTA VEM.
     Desabilitar um campo focado tira o foco dele, e no iOS perder o foco fecha
     o teclado. Pior: devolver o foco depois, por código e fora de um toque da
     pessoa, o iOS costuma ignorar — então o teclado fechava a cada mensagem
     enviada e não voltava. Quem impede o envio duplicado é
     `respostaEmAndamento`, conferido em `perguntar()`; o `disabled` do campo
     era só aparência, e custava a continuidade da digitação. O botão continua
     desabilitado, que é onde a espera precisa aparecer. */
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
    formChat.querySelector('.enviar').disabled = false;
    /* Só devolve o foco a quem o perdeu. Como o campo não é mais desabilitado,
       quem estava digitando continua digitando e o teclado nunca piscou; este
       `focus()` cobre apenas o caso de a pessoa ter tocado fora enquanto
       esperava. Chamá-lo sempre reabriria o teclado de quem acabou de fechá-lo
       de propósito. */
    if (document.activeElement !== campoChat && !tecladoAberto()) campoChat.focus();
    /* Um respiro para a resposta ser lida antes de o convite entrar. */
    setTimeout(oferecerPalestrantes, 2600);
  }
}

/* Engajamento proativo, mas ancorado no que está na tela.
   A versão anterior anunciava, nove segundos depois de abrir o chat, uma
   reserva na Arena Mind que ninguém tinha feito, e oferecia um aviso que
   o app não sabe enviar. Duas afirmações falsas para puxar assunto.

   Agora o convite só existe quando existe referente: se a última resposta
   nomeou alguém da grade, dá para perguntar sobre "os palestrantes
   mencionados acima". Se ninguém foi citado, o agente fica quieto — é o
   que ele faria se não tivesse nada a dizer. */
let jaOfereceuPalestrantes = false;

function citouPalestrante() {
  if (!DADOS || !DADOS.pessoas) return false;
  const conversa = mensagens.textContent || '';
  return DADOS.pessoas.some((pessoa) => pessoa.nome && conversa.includes(pessoa.nome));
}

function oferecerPalestrantes() {
  if (jaOfereceuPalestrantes || respostaEmAndamento || !citouPalestrante()) return;
  jaOfereceuPalestrantes = true;
  bolha('Quer saber mais sobre os palestrantes mencionados acima?', 'mind');
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
    /* O desafio é sinal de jornada e já era pedido aqui: guardar custa
       uma linha e evita perguntar de novo lá dentro. */
    PERFIL.jornada.desafio = limpo;
    return responder(limpo).then(() => cardsDoDesafio(limpo));
  }
  responder(limpo);
}

let jaPerguntou = false;

/* Sem identidade, cumprimento sem nome — o agente não chuta quem você é.
   Quando a Yazo (ou o bootstrap) preencher PARTICIPANTE.nome, ele chama
   pelo nome sem que mais nada mude. */
/* Mesmo nome que a home usa: quem é "Ana" no título não pode virar
   "Ana Paula Rodrigues Silva" duas telas depois. */
function saudacao() {
  const nome = primeiroNome();
  return nome ? 'Oi, ' + nome + '! 💚 ' : 'Oi! 💚 ';
}

/* DEPOIS DE SE APRESENTAR, ELE PERGUNTA.

   Quem chega COM ASSUNTO já tem o próximo passo: uma intenção de card
   abre o fluxo dela, e uma pergunta digitada na home é respondida.
   Perguntar por cima disso seria falar em cima da pessoa.

   Sem assunto — o `?` do aviso, a home com o campo vazio — a conversa
   começava num vazio: a apresentação e mais nada, esperando que a pessoa
   soubesse o que pedir. É aí que a agenda passa a ser montada, e por isso
   a jornada entra DIRETA, sem o "Começar →": quem não escolheu começar
   não precisa de um botão para confirmar que quer. */
function iniciarChat(opcoes) {
  if (chatIniciado) return;
  chatIniciado = true;
  /* A ABERTURA É DA ADRIANA, palavra por palavra. O segundo parágrafo do
     que ela mandou já existe, em `FLUXOS.jornada` — é ele que anuncia as
     perguntas, logo antes do "Começar →". Repetido aqui, viraria promessa
     de perguntas para quem só abriu o chat para perguntar uma coisa. */
  bolha(saudacao() + 'Sou o agente do Mind e serei seu concierge no Mind Summit. Estou aqui para responder perguntas e para contribuir para que você saia do Mind Summit com algo mais concreto do que boas ideias — agenda montada, gente certa, e o que fazer na segunda-feira.', 'mind');
  /* O convite proativo mora em `oferecerPalestrantes`: ele só aparece
     depois que alguém da grade foi realmente citado na conversa. */
  if (!opcoes || !opcoes.comAssunto) setTimeout(() => FLUXOS.jornada(true), 500);
}

formChat.addEventListener('submit', (e) => {
  e.preventDefault();
  perguntar(campoChat.value);
  campoChat.value = '';
});
enviarComEnter(formChat);

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
    dica: 'Eu sugiro um roteiro dos dois dias sem choque de horário' },
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

/* Quem sabe de onde vem a programação é o data-service. Aqui só se guarda
   o que ele entregou — trocar arquivo local por API não passa por este
   arquivo. */
async function carregarDados() {
  DADOS = await carregarDadosSummit();

  /* Avisos e composição da home vêm de porta própria — o painel publica
     ali, não no bootstrap. Se ela não responder, valem os avisos
     embutidos e o momento padrão: a home não fica em branco por causa
     de uma função fora do ar. */
  const homeDoEvento = await carregarHomeDoEvento();
  if (homeDoEvento) {
    /* Lista vazia é resposta legítima — quer dizer que não há aviso em
       circulação, e o app respeita em vez de mostrar os embutidos. */
    definirAvisos(homeDoEvento.avisos);
    definirMomentoDoServidor(homeDoEvento.home && homeDoEvento.home.momento);
  }
}


/* ============================================================
   PERFIL VIVO — o que o Summit sabe sobre você até agora
   ============================================================
   Cresce por AÇÃO, nunca por palpite: tema escolhido, sessão salva, pessoa
   marcada, insight escrito. É a mesma separação do banco — o que a pessoa faz
   é fato; o que o agente conclui é leitura. */
/* `temas` continua sendo objeto de PESOS (código → peso), não lista: é o
   que `afinidade()` consome, e é o sinal principal do motor. A jornada
   fica ao lado, como sinal que COMPLEMENTA — nenhuma resposta dela é
   convertida em tema artificialmente. */
const PERFIL = {
  temas: {}, sessoes: [], pessoas: [], insights: [], plano: [],
  jornada: {
    objetivos: [],
    desafio: null,
    perfilProfissional: null,
    experiencias: [],
    palestrantesImperdiveis: [],
    ritmo: 'equilibrado',
    disponibilidade: null,
    observacoes: null,
  },
};

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
    .filter((s) => sessaoAcessivelPeloIngresso(s) && (!filtro || filtro(s)))
    .map((s) => ({ s, a: afinidade(s.temas) }))
    .filter((x) => x.a !== null)
    .sort((x, y) => y.a - x.a || (x.s.dia + x.s.inicio).localeCompare(y.s.dia + y.s.inicio));
}

function chaveDoIngresso() {
  const normalizado = String(ingressoDoParticipante || '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  return ['mind', 'vip', 'prime'].find((chave) =>
    new RegExp('(^|[^a-z])' + chave + '([^a-z]|$)').test(normalizado)) || null;
}

function sessaoAcessivelPeloIngresso(sessao) {
  const chave = chaveDoIngresso();
  /* Sem ingresso identificado, a experiência pública continua disponível.
     Com um rótulo identificado mas ainda sem regra oficial (por exemplo uma
     categoria nova), falhamos fechados: é melhor não recomendar do que
     prometer um acesso que o ingresso talvez não conceda. */
  if (!ingressoDoParticipante) return true;
  if (!chave) return false;
  return !Array.isArray(sessao.trilhas) || sessao.trilhas.length === 0 || sessao.trilhas.includes(chave);
}

function textoDoIngressoNaRecomendacao() {
  if (!ingressoDoParticipante) return null;
  return chaveDoIngresso()
    ? 'Vou considerar os acessos do seu ingresso ' + ingressoDoParticipante + ' nas recomendações.'
    : 'Identifiquei seu ingresso ' + ingressoDoParticipante + ', mas ainda não tenho a regra oficial de acesso dessa categoria. Não vou sugerir uma sessão sem conseguir confirmar que ela está liberada para você.';
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

/* '16 set' a partir do ISO. Montado em partes, não por `new Date(iso)`:
   string sem fuso é lida como UTC em alguns navegadores e volta um dia. */
const MESES_CURTOS = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
const DIA_CURTO = (iso) => {
  const [, mes, dia] = String(iso).split('-');
  return Number(dia) + ' ' + (MESES_CURTOS[Number(mes) - 1] || '');
};

function fotoDe(nome) {
  const p = DADOS.pessoas.find((x) => nome && nome.startsWith(x.nome));
  return p ? p.foto : null;
}

function cardSessao(s, pct, porque) {
  const el = document.createElement('article');
  el.className = 'cs';
  const foto = fotoDe(s.quem);
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
        '<button type="button" class="principal" data-acao="onde">Onde reservar no app</button>' +
      '</div>' +
    '</div>';
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

/* Iniciais de quem não tem retrato: "Amy Edmondson" → "AE". Uma letra
   quando o nome é só um. */
function iniciais(nome) {
  const partes = String(nome || '').trim().split(/\s+/).filter(Boolean);
  if (!partes.length) return '?';
  const primeira = partes[0][0];
  const ultima = partes.length > 1 ? partes[partes.length - 1][0] : '';
  return (primeira + ultima).toUpperCase();
}

function cardPessoa(p, pct, porque) {
  const el = document.createElement('article');
  el.className = 'cs';
  const marcada = PERFIL.pessoas.some((x) => x.nome === p.nome);
  /* Sem foto, iniciais — e não `./assets/null`, que o navegador desenha
     como imagem quebrada. A base de palestrantes deixou de ter retrato;
     card vazio é melhor do que card com defeito. */
  const retrato = p.foto
    ? '<img src="./assets/' + p.foto + '" alt="" loading="lazy" />'
    : '<i class="iniciais">' + iniciais(p.nome) + '</i>';
  el.innerHTML =
    '<span class="foto">' + retrato + '</span>' +
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
  ok.addEventListener('click', () => {
    ok.remove();
    const temas = Object.keys(PERFIL.temas).map(TEMA);
    if (temas.length) enviarSinalJornada('temas', temas)
      .catch(() => bolha('Não consegui guardar esses temas no seu perfil agora, mas vou seguir com eles nesta tela.', 'mind'));
    depois();
  });
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
/* ============================================================
   ROTEIRO — uma montagem só, dois fluxos
   ============================================================
   `FLUXOS.agenda()` e a jornada montam o MESMO roteiro; o que muda são
   os sinais que entram. A nota continua vindo de `afinidade()`, que
   continua vindo de `PERFIL.temas`. Nada aqui mexe na nota.

     filtro    → quem nem entra na conta (dia em que a pessoa não vem)
     fixas     → entram antes de todo mundo (palestrante imperdível)
     formatos  → que tipos de sessão a pessoa quer; sem isso, o padrão
                 histórico continua valendo (tudo menos experiência)
     porDia    → quantas por dia (ritmo); `total` corta o conjunto

   Nenhuma sessão entra se colide com uma que já entrou. */
function montarRoteiro(opcoes) {
  const o = opcoes || {};
  const roteiro = [];
  const cabe = (s) => !roteiro.some((x) => choca(x.s, s));

  /* Vontade declarada não é desempatada por afinidade: se a pessoa disse
     que não quer perder alguém, esse alguém entra primeiro. */
  (o.fixas || []).forEach((s) => { if (cabe(s)) roteiro.push({ s, a: afinidade(s.temas) }); });

  const doFormato = o.formatos && o.formatos.length
    ? (s) => o.formatos.includes(s.formato)
    : (s) => s.formato !== 'experiencia';

  sessoesPorAfinidade((s) => doFormato(s) && (!o.filtro || o.filtro(s)))
    .forEach(({ s, a }) => { if (cabe(s)) roteiro.push({ s, a }); });

  roteiro.sort((x, y) => (x.s.dia + x.s.inicio).localeCompare(y.s.dia + y.s.inicio));

  if (!o.porDia) return roteiro.slice(0, o.total || 6);
  const conta = {};
  return roteiro.filter(({ s }) => {
    conta[s.dia] = (conta[s.dia] || 0) + 1;
    return conta[s.dia] <= o.porDia;
  });
}

/* ============================================================
   JORNADA — perguntas rápidas, roteiro no fim
   ============================================================
   A entrada do card "Monte sua jornada no Summit". Não é formulário e
   não é chat vazio: é escolha em botão, uma pergunta por vez, e no fim
   o roteiro dos dois dias que `FLUXOS.agenda()` já sabe montar.

   AS PERGUNTAS SÃO DADO. Acrescentar a próxima é acrescentar um item
   nesta lista — nada no motor muda.

   `tipo` diz a forma da resposta:
     'multipla' → chips, até `max` escolhas
     'unica'    → chips, uma só
     'texto'    → campo livre; usar só quando escolher não resolve

   `campo` é onde a resposta fica guardada em `JORNADA`. */
const PERGUNTAS_JORNADA = [
  {
    campo: 'objetivos',
    tipo: 'multipla',
    max: 2,
    pergunta: 'O que faria você sair do Mind pensando “valeu muito a pena”?',
    micro: 'Escolha até 2.',
    opcoes: [
      'Levar ideias práticas para minha equipe',
      'Repensar minha forma de liderar',
      'Estruturar melhor saúde mental e bem-estar',
      'Conhecer pesquisas e tendências',
      'Fazer conexões relevantes',
      'Encontrar inspiração para um desafio atual',
      'Conhecer grandes referências de perto',
      'Ainda não sei — quero explorar',
    ],
  },

  /* O SINAL PRINCIPAL. Reaproveita `pedirTemas()`, que é quem escreve em
     `PERFIL.temas` — a jornada não cria um segundo caminho para o que o
     motor já consome. */
  {
    campo: 'temas',
    tipo: 'temas',
    pergunta: 'Em que você está mexendo agora? Isso é o que mais pesa no que eu vou sugerir.',
  },

  /* "Em quais dias você vem?" saiu em 03/09 a pedido da Adriana: não se
     pergunta; o roteiro cobre os dois dias. `disponibilidade` ausente já
     era lido como "todos" por quem monta o roteiro. */

  {
    campo: 'ritmo',
    tipo: 'unica',
    pergunta: 'Que ritmo você quer nesses dias?',
    /* COPY PROVISÓRIA — o número de sessões por dia de cada ritmo está em
       `SESSOES_POR_DIA`, logo abaixo, e é chute honesto até você dizer. */
    opcoes: [
      { valor: 'leve', rotulo: 'Leve — poucas sessões, tempo para conversar' },
      { valor: 'equilibrado', rotulo: 'Equilibrado — um meio-termo' },
      { valor: 'intenso', rotulo: 'Intenso — quero aproveitar cada horário' },
    ],
  },

  {
    campo: 'palestrantesImperdiveis',
    tipo: 'palestrantes',
    max: 3,
    opcional: true,
    pergunta: 'Tem alguém que você não quer perder?',
    micro: 'Digite o nome e escolha até 3 pessoas. Se não tiver, pode pular.',
  },

  {
    campo: 'experiencias',
    tipo: 'multipla',
    opcional: true,
    pergunta: 'Que tipo de coisa você quer no seu roteiro?',
    micro: 'Marque quantos quiser, ou pule para eu decidir.',
    /* Os formatos são os que existem na grade — se a programação mudar,
       esta pergunta muda junto. */
    opcoes: () => {
      const rotulo = { palestra: 'Palestras', painel: 'Painéis', masterclass: 'Masterclasses',
                       workshop: 'Workshops', experiencia: 'Experiências' };
      return [...new Set((DADOS.sessoes || []).map((s) => s.formato))]
        .filter((f) => rotulo[f])
        .map((f) => ({ valor: f, rotulo: rotulo[f] }));
    },
  },
];

/* Quantas sessões por dia cada ritmo pede. PROVISÓRIO: os números são
   meus, não seus — trocar aqui muda o roteiro inteiro. */
const SESSOES_POR_DIA = { leve: 2, equilibrado: 3, intenso: 5 };


function botaoAvancar(texto, aoTocar) {
  const b = document.createElement('button');
  b.type = 'button';
  b.className = 'avancar';
  b.textContent = texto;
  b.addEventListener('click', aoTocar);
  return b;
}

/** Uma pergunta da jornada. Chama a próxima quando é respondida. */
function perguntaDaJornada(indice) {
  const q = PERGUNTAS_JORNADA[indice];
  if (!q) return fecharJornada();

  /* A pergunta é fala da Mind, não rótulo de painel: `painel-tit` é
     caixa alta, e frase inteira em caixa alta não se lê. O painel fica
     só com as escolhas. */
  bolha(q.pergunta, 'mind');
  /* O tema tem tela própria desde antes da jornada: é a mesma, e ela
     escreve direto em `PERFIL.temas`. */
  if (q.tipo === 'temas') {
    return setTimeout(() => pedirTemas(() => perguntaDaJornada(indice + 1)), 380);
  }
  setTimeout(() => escolhasDaJornada(q, indice), 380);
}

/* Busca aberta sobre a lista canônica inteira. O texto digitado só filtra:
   o valor guardado continua sendo o nome exato que veio do bootstrap. */
function normalizarBuscaPalestrante(valor) {
  return String(valor || '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function seletorPalestrantesDaJornada(q, indice, alvo) {
  const nomes = (DADOS.pessoas || [])
    .filter((p) => p.na_grade && p.nome)
    .map((p) => p.nome)
    .sort((a, b) => a.localeCompare(b, 'pt-BR'));
  const selecionadas = [];

  const caixa = document.createElement('div');
  caixa.className = 'ins jornada-palestrantes';

  const campo = document.createElement('input');
  campo.type = 'search';
  campo.className = 'busca-palestrante';
  campo.placeholder = 'Digite o nome do palestrante';
  campo.autocomplete = 'off';
  campo.setAttribute('aria-label', 'Buscar palestrante');

  const escolhidas = document.createElement('div');
  escolhidas.className = 'chips palestrantes-escolhidos';
  escolhidas.setAttribute('aria-live', 'polite');

  const resultados = document.createElement('div');
  resultados.className = 'sugestoes-palestrantes';
  resultados.setAttribute('role', 'listbox');
  resultados.hidden = true;

  const ok = botaoAvancar('Pular', () => {
    PERFIL.jornada[q.campo] = selecionadas.slice();
    ok.remove();
    if (selecionadas.length) {
      enviarSinalJornada('palestrantes_imperdiveis', selecionadas.slice())
        .catch(() => bolha('Não consegui guardar essa resposta no seu perfil agora, mas vou seguir com ela nesta tela.', 'mind'));
    }
    perguntaDaJornada(indice + 1);
  });

  function renderEscolhidas() {
    escolhidas.replaceChildren();
    selecionadas.forEach((nome) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.setAttribute('aria-pressed', 'true');
      b.setAttribute('aria-label', 'Remover ' + nome);
      b.textContent = nome + ' ×';
      b.addEventListener('click', () => {
        selecionadas.splice(selecionadas.indexOf(nome), 1);
        renderEscolhidas();
        renderResultados();
      });
      escolhidas.appendChild(b);
    });
    ok.textContent = selecionadas.length ? 'Continuar' : 'Pular';
  }

  function selecionar(nome) {
    if (selecionadas.includes(nome) || selecionadas.length >= (q.max || 3)) return;
    selecionadas.push(nome);
    campo.value = '';
    renderEscolhidas();
    renderResultados();
    campo.focus();
  }

  function renderResultados() {
    resultados.replaceChildren();
    const busca = normalizarBuscaPalestrante(campo.value);
    if (busca.length < 2) {
      resultados.hidden = true;
      return;
    }
    const candidatos = nomes
      .filter((nome) => !selecionadas.includes(nome) &&
        normalizarBuscaPalestrante(nome).includes(busca))
      .sort((a, b) => {
        const aComeca = normalizarBuscaPalestrante(a).startsWith(busca);
        const bComeca = normalizarBuscaPalestrante(b).startsWith(busca);
        return Number(bComeca) - Number(aComeca) || a.localeCompare(b, 'pt-BR');
      });
    resultados.hidden = false;
    if (!candidatos.length) {
      const vazio = document.createElement('p');
      vazio.textContent = 'Não encontrei esse nome na grade.';
      resultados.appendChild(vazio);
      return;
    }
    candidatos.forEach((nome) => {
      const b = document.createElement('button');
      b.type = 'button';
      b.setAttribute('role', 'option');
      b.textContent = nome;
      b.addEventListener('click', () => selecionar(nome));
      resultados.appendChild(b);
    });
  }

  campo.addEventListener('input', renderResultados);
  campo.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter') return;
    const primeira = resultados.querySelector('button');
    if (!primeira) return;
    e.preventDefault();
    primeira.click();
  });

  caixa.appendChild(campo);
  caixa.appendChild(resultados);
  caixa.appendChild(escolhidas);
  alvo.appendChild(caixa);
  alvo.appendChild(ok);
  mensagens.scrollTop = mensagens.scrollHeight;
  campo.focus();
}

function escolhasDaJornada(q, indice) {
  const alvo = painel('');
  if (q.micro) {
    const m = document.createElement('p');
    m.className = 'ins-dica';
    m.textContent = q.micro;
    alvo.appendChild(m);
  }

  if (q.tipo === 'palestrantes') {
    return seletorPalestrantesDaJornada(q, indice, alvo);
  }

  if (q.tipo === 'texto') {
    const campo = document.createElement('textarea');
    campo.placeholder = q.placeholder || 'Escreva do seu jeito.';
    const ok = botaoAvancar(q.opcional ? 'Pular' : 'Continuar', () => {
      const valor = campo.value.trim() || null;
      PERFIL.jornada[q.campo] = valor;
      ok.remove();
      if (valor) enviarSinalJornada(q.campo, [valor])
        .catch(() => bolha('Não consegui guardar essa resposta no seu perfil agora, mas vou seguir com ela nesta tela.', 'mind'));
      perguntaDaJornada(indice + 1);
    });
    const caixa = document.createElement('div');
    caixa.className = 'ins';
    caixa.appendChild(campo);
    alvo.appendChild(caixa);
    alvo.appendChild(ok);
    mensagens.scrollTop = mensagens.scrollHeight;
    return;
  }

  /* As opções podem ser lista fixa ou função da base — palestrante e dia
     não se escrevem à mão. Cada uma vira {valor, rotulo}. */
  const opcoes = (typeof q.opcoes === 'function' ? q.opcoes() : q.opcoes)
    .map((o) => (typeof o === 'string' ? { valor: o, rotulo: o } : o));
  const teto = q.tipo === 'unica' ? 1 : (q.max || opcoes.length);
  const escolhidas = [];
  const chips = document.createElement('div');
  chips.className = 'chips';
  chips.innerHTML = opcoes.map((o, i) =>
    '<button type="button" aria-pressed="false" data-i="' + i + '">' + o.rotulo + '</button>').join('');

  const ok = botaoAvancar(q.opcional ? 'Pular' : 'Continuar', () => {
    const valores = escolhidas.map((i) => opcoes[i].valor);
    PERFIL.jornada[q.campo] = q.tipo === 'unica' ? (valores[0] || null) : valores;
    ok.remove();
    if (valores.length) enviarSinalJornada(
      q.campo === 'palestrantesImperdiveis' ? 'palestrantes_imperdiveis' : q.campo,
      valores,
    ).catch(() => bolha('Não consegui guardar essa resposta no seu perfil agora, mas vou seguir com ela nesta tela.', 'mind'));
    perguntaDaJornada(indice + 1);
  });
  ok.disabled = !q.opcional;

  chips.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-i]');
    if (!b) return;
    const i = Number(b.dataset.i);
    const pos = escolhidas.indexOf(i);
    if (pos >= 0) {
      escolhidas.splice(pos, 1);
    } else {
      /* No teto, a mais antiga sai para a nova entrar: o toque sempre
         responde. Ignorar em silêncio parece tela travada. */
      while (escolhidas.length >= teto) {
        const saiu = escolhidas.shift();
        chips.querySelector('[data-i="' + saiu + '"]').setAttribute('aria-pressed', 'false');
      }
      escolhidas.push(i);
    }
    b.setAttribute('aria-pressed', escolhidas.includes(i) ? 'true' : 'false');
    ok.disabled = !q.opcional && !escolhidas.length;
    /* Pergunta que pode ser pulada troca o rótulo do botão conforme a
       pessoa marca: "Pular" vira "Continuar" quando há resposta. */
    if (q.opcional) ok.textContent = escolhidas.length ? 'Continuar' : 'Pular';
  });

  alvo.appendChild(chips);
  alvo.appendChild(ok);
  mensagens.scrollTop = mensagens.scrollHeight;
}

/* O fim da jornada: o roteiro. A nota de cada sessão continua sendo a
   afinidade com `PERFIL.temas` — o que a jornada faz é escolher quem
   entra na conta, quem entra antes de todo mundo e quantas cabem. */
function fecharJornada() {
  const j = PERFIL.jornada;
  bolha('Pronto. Montei a partir do que você me contou.', 'mind');
  setTimeout(() => {
    const dia = j.disponibilidade && j.disponibilidade !== 'todos' ? j.disponibilidade : null;

    /* Palestrante imperdível vira sessão pelo nome em `quem` — é o que a
       base entrega ao app; não há id de pessoa na sessão. */
    const querVer = j.palestrantesImperdiveis || [];
    const fixas = !querVer.length ? [] : DADOS.sessoes.filter((s) =>
      sessaoAcessivelPeloIngresso(s) && (!dia || s.dia === dia) &&
      querVer.some((nome) => String(s.quem || '').includes(nome)));

    const roteiro = montarRoteiro({
      filtro: dia ? (s) => s.dia === dia : null,
      fixas,
      formatos: j.experiencias,
      porDia: SESSOES_POR_DIA[j.ritmo] || SESSOES_POR_DIA.equilibrado,
    });

    if (!roteiro.length) {
      return bolha(chaveDoIngresso()
        ? 'Com esses filtros não sobrou nenhuma sessão compatível com o seu ingresso. Me diz o que quer ver que eu procuro de outro jeito.'
        : 'Ainda não consigo confirmar quais sessões estão liberadas para a categoria do seu ingresso. Não vou montar uma jornada com acesso incerto.', 'mind');
    }

    const alvo = painel('Sua jornada no Summit', roteiro.length + ' sessões, sem choque de horário');
    /* Os objetivos voltam para a tela como o PORQUÊ do roteiro. É assim
       que eles complementam: dizendo a intenção que o roteiro serve, sem
       virar tema nenhum. */
    if (j.objetivos && j.objetivos.length) {
      const p = document.createElement('p');
      p.className = 'ins-dica';
      p.textContent = 'Montado para: ' + j.objetivos.join(' · ').toLowerCase() + '.';
      alvo.appendChild(p);
    }
    roteiro.forEach(({ s, a }) => alvo.appendChild(cardSessao(s, a,
      fixas.includes(s) ? 'Você marcou como imperdível.' : null)));
    alvo.appendChild(blocoRegra(DADOS.evento.regra_reserva +
      ' Quem reserva é você, no app — eu só mostro onde fica.'));
    tocarPerfil();
  }, 550);
}

const FLUXOS = {
  /* `direto` pula o "Começar →". Ele existe para quem tocou num card e
     merece confirmar antes de entrar; para quem só abriu o Concierge, o
     botão seria um passo entre a apresentação e a primeira pergunta. */
  jornada(direto) {
    bolha('Vou montar uma jornada que faça sentido para você. São algumas perguntas rápidas sobre o que você quer levar destes dois dias.', 'mind');
    const ingresso = textoDoIngressoNaRecomendacao();
    if (ingresso) bolha(ingresso, 'mind');
    if (direto) return setTimeout(() => perguntaDaJornada(0), 450);
    const alvo = painel('');
    alvo.appendChild(botaoAvancar('Começar →', function () {
      this.remove();
      perguntaDaJornada(0);
    }));
    mensagens.scrollTop = mensagens.scrollHeight;
  },

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
      const corte = montarRoteiro({ total: 6 });
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
    /* Anotação sobre a palestra que a pessoa está assistindo. Como o app
       não sabe qual é, a primeira coisa é perguntar — com as sessões no
       ar agora, não com o que ela salvou algum dia. A escolha é gravada
       no momento do toque e aparece na home. */
    const noAr = sessoesNoAr();
    const jaEscolhida = sessaoDoInsight();
    /* A guardada entra na lista mesmo fora do horário: se a pessoa disse
       que está nela, quem manda é ela, não o relógio. */
    const base = jaEscolhida && !noAr.some((s) => s.id === jaEscolhida.id)
      ? [jaEscolhida, ...noAr] : noAr;
    if (!base.length) {
      bolha('A grade não tem nada no ar agora. Quando a próxima palestra começar, me chame que eu guardo sua anotação nela.', 'mind');
      return;
    }
    const escolhida = jaEscolhida || base[0];
    /* Fora de horário a pergunta muda: oferecer o que está ao redor e
       chamar de "agora" seria mentira pequena, mas mentira. */
    const alvo = painel(noAr.length
      ? 'Em que palestra você está?'
      : 'Nada no ar agora. De que palestra é a anotação?');
    const cx = document.createElement('div');
    cx.className = 'ins';
    cx.innerHTML =
      '<div class="chips">' + base.map((s) =>
        '<button type="button" aria-pressed="' + (s.id === escolhida.id) + '" data-s="' + s.id + '">' +
        s.titulo.slice(0, 30) + (s.titulo.length > 30 ? '…' : '') + '</button>').join('') + '</div>' +
      '<p class="ins-dica">Sua anotação fica guardada nessa palestra.</p>' +
      '<textarea placeholder="O que essa palestra te trouxe? Escreva do seu jeito."></textarea>';
    const salvar = document.createElement('button');
    salvar.type = 'button';
    salvar.className = 'avancar';
    salvar.textContent = 'Guardar anotação';
    /* Grava no toque, não no fim: a home precisa refletir a escolha
       mesmo que a pessoa desista de escrever agora. */
    definirSessaoDoInsight(escolhida.id);
    cx.querySelector('.chips').addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      cx.querySelectorAll('.chips button').forEach((x) => x.setAttribute('aria-pressed', 'false'));
      b.setAttribute('aria-pressed', 'true');
      definirSessaoDoInsight(b.dataset.s);
      montarHomeV3();
    });
    salvar.addEventListener('click', () => {
      const txt = cx.querySelector('textarea').value.trim();
      if (!txt) return cx.querySelector('textarea').focus();
      const id = cx.querySelector('.chips button[aria-pressed="true"]').dataset.s;
      const sessao = base.find((x) => x.id === id);
      PERFIL.insights.push({ sessao: sessao.titulo, texto: txt, temas: sessao.temas });
      (sessao.temas || []).forEach((t) => pesoTema(t, 1));
      cx.remove(); salvar.remove();
      bolha('Anotado em “' + sessao.titulo + '”. Isso muda o seu mapa e o que eu vou sugerir daqui pra frente. 💚', 'mind');
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
  if (!FLUXOS[id]) return;
  /* Sem entrada em INTENCOES o fluxo ainda abre — é o caso de quem chega
     por um card da home, que não escolheu chip nenhum para ecoar. */
  if (i) bolha(i.titulo, 'eu');
  setTimeout(() => FLUXOS[id](), i ? 550 : 120);
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
/* A home V3 não depende da programação para existir: ela sobe primeiro,
   e os dados chegam para quem precisa deles (o chat, o tour). */
montarHomeV3();
/* A grade chega depois: a próxima experiência só existe a partir daqui. */
carregarDados().then(montarHomeV3).catch((e) => {
  const aviso = document.createElement('p');
  aviso.className = 'erro-dados';
  aviso.innerHTML = '<b>Não consegui carregar a programação.</b>' +
    'Esta página não guarda conteúdo dentro do código — ela lê da camada de dados, ' +
    'e a leitura falhou (' + e.message + '). Recarregue em um instante.';
  document.getElementById('home-v3').prepend(aviso);
});
