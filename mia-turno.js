/* ============================================================
   O TURNO DA MIA — o mesmo desenho do bloco do LearnWorlds
   ============================================================
   O app do Summit já tinha a PELE da MIA (`html[data-pele="mia"]` em
   `styles.css`): faixa roxa, balão claro, rótulo da fala. O que faltava era o
   COMPORTAMENTO, que é metade do desenho dela e vive em
   `learnworlds/mia-embed.html`:

   - o painel de raciocínio, com a pétala girando e os passos nomeados,
     trocados pelo relato real quando a resposta chega;
   - a resposta surgindo palavra a palavra, saindo do desfoque, em frente de
     onda diagonal quando o texto é grande;
   - o balão subindo para o topo antes de a resposta começar a surgir;
   - o markdown dela virando texto formatado.

   ESSE ÚLTIMO ERA DEFEITO, não falta de enfeite. O app escrevia a resposta
   com `textContent`, e a MIA responde em markdown: quem abria a página
   hospedada lia `**três movimentos**` com os asteriscos na tela.

   ============================================================
   DUAS CÓPIAS, E POR QUÊ
   ============================================================
   As regras daqui são as mesmas de `learnworlds/mia-embed.html`, e isso é
   duplicação de verdade — não há como fingir o contrário. Ela existe porque
   os dois lados não podem compartilhar arquivo: o bloco do LearnWorlds é
   COLADO numa página de terceiro, sem build e sem import, e por isso é ES5
   num arquivo só. Aqui é um módulo do app, que tem build e imports.

   Enquanto as duas existirem, mudança de desenho da MIA precisa passar nos
   dois lugares. A saída definitiva é gerar o bloco a partir daqui no
   `build-cloudflare.mjs`, ou o LearnWorlds carregar esta página num iframe —
   e essa é decisão de arquitetura, não deste arquivo.

   Os números e as decisões estão explicados lá, em quem nasceu primeiro.
   Aqui ficam só os ponteiros, para o comentário não virar cópia também. */

/* ============================================================
   O MARKDOWN DELA VIRA TEXTO
   ============================================================ */

function escapar(t) {
  return t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

/* Escapa ANTES de formatar: o que vem do servidor nunca vira marcação por
   conta própria, e só os pedaços que esta função decide viram tag. */
export function formatarResposta(texto) {
  return escapar(String(texto ?? ''))
    .split('\n')
    .map((linha) => {
      const titulo = linha.match(/^\s{0,3}#{1,4}\s+(.+)$/);
      if (titulo) return '<strong>' + titulo[1].replace(/\*\*/g, '') + '</strong>';
      return linha.replace(/^(\s*)[-*]\s+/, '$1• ');
    })
    .join('\n')
    .replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>')
    .replace(/https:\/\/[^\s<]+[^\s<.,;:!?)\]]/g, (url) =>
      '<a href="' + url + '" target="_blank" rel="noopener noreferrer">' + url + '</a>');
}

/* ============================================================
   O QUE A TELA DIZ ENQUANTO ELA PENSA
   ============================================================
   Expectativa do caminho normal dela, NÃO relato: quando a resposta chega,
   tudo isto é trocado pelo que o servidor diz ter feito. O porquê de cada
   tempo está em `learnworlds/mia-embed.html`, e os testes que guardam a
   cadência e os temas estão em `tests/passos_da_espera.test.mjs`. */

const SURGIR_MS = 600;
const PASSO_MAX_MS = 140;
const ABERTURA_DIAGONAL = 2;
const LINHAS_PARA_DIAGONAL = 4;

function passosDaEspera(tema) {
  return [
    [0, 'Lendo sua pergunta'],
    [1500, tema
      ? { antes: 'Procurando sobre ', destaque: tema, depois: ' no acervo do Summit' }
      : 'Procurando no acervo do Summit'],
    [5000, 'Abrindo as fichas das sessões'],
    [11000, 'Vendo o que cada palestrante disse'],
    [18000, 'Conferindo em que minuto aparece'],
    [27000, 'Escrevendo a resposta'],
    [38000, 'Ainda escrevendo — perguntas que cruzam várias sessões levam mais'],
  ];
}

/* PALAVRA → TEMA, e não os nomes dos mapas: ninguém escreve "dados,
   mensuração e roi" numa pergunta. Todo tema daqui é um dos 31 mapas
   temáticos que `summit_2026.knowledge_documents` tem de fato — um teste
   confere isso. A ORDEM IMPORTA: o específico antes do geral. */
const TEMA_POR_PALAVRA = [
  ['lideranca feminina', 'liderança feminina'], ['mulheres na lideranca', 'liderança feminina'],
  ['seguranca psicologica', 'segurança psicológica'], ['psicologicamente seguro', 'segurança psicológica'],
  ['conversas dificeis', 'conversas difíceis'], ['conversa dificil', 'conversas difíceis'],
  ['futuro do trabalho', 'futuro do trabalho e IA'], ['inteligencia artificial', 'futuro do trabalho e IA'],
  ['riscos psicossociais', 'NR-1 e riscos psicossociais'], ['psicossocial', 'NR-1 e riscos psicossociais'],
  ['psicossociais', 'NR-1 e riscos psicossociais'], ['nr-1', 'NR-1 e riscos psicossociais'],
  ['nr1', 'NR-1 e riscos psicossociais'], ['nr 1', 'NR-1 e riscos psicossociais'],
  ['roi', 'dados, mensuração e ROI'], ['mensuracao', 'dados, mensuração e ROI'],
  ['metricas', 'dados, mensuração e ROI'], ['metrica', 'dados, mensuração e ROI'],
  ['burnout', 'burnout'], ['esgotamento', 'burnout'], ['esgotado', 'burnout'],
  ['esgotada', 'burnout'], ['exausto', 'burnout'], ['exausta', 'burnout'],
  ['exaustao', 'burnout'], ['nao aguento', 'burnout'],
  ['saude mental', 'saúde mental'], ['adoecimento', 'saúde mental'],
  ['bem-estar', 'programas de bem-estar'], ['bem estar', 'programas de bem-estar'],
  ['wellness', 'programas de bem-estar'],
  ['alegria', 'emoções positivas e felicidade'], ['felicidade', 'emoções positivas e felicidade'],
  ['feliz', 'emoções positivas e felicidade'],
  ['sobrecarga', 'desenho do trabalho'], ['carga de trabalho', 'desenho do trabalho'],
  ['desenho do trabalho', 'desenho do trabalho'],
  ['produtividade', 'produtividade sustentável'], ['performance', 'produtividade sustentável'],
  ['distracao', 'tecnologia e distração'], ['notificacoes', 'tecnologia e distração'],
  ['celular', 'tecnologia e distração'],
  ['foco', 'foco e atenção'], ['atencao', 'foco e atenção'], ['concentracao', 'foco e atenção'],
  ['feedback', 'feedback e reconhecimento'], ['reconhecimento', 'feedback e reconhecimento'],
  ['elogio', 'feedback e reconhecimento'],
  ['hibrido', 'trabalho híbrido'], ['home office', 'trabalho híbrido'],
  ['remoto', 'trabalho híbrido'], ['presencial', 'trabalho híbrido'],
  ['lideranca', 'liderança'], ['lider', 'liderança'], ['lideres', 'liderança'],
  ['chefe', 'liderança'], ['gestor', 'liderança'], ['gestora', 'liderança'], ['gerente', 'liderança'],
  ['cultura', 'cultura organizacional'],
  ['fracasso', 'aprendizagem e erro'], ['errar', 'aprendizagem e erro'],
  ['erros', 'aprendizagem e erro'], ['erro', 'aprendizagem e erro'],
  ['aprendizagem', 'aprendizagem e erro'],
  ['engajamento', 'engajamento e propósito'], ['proposito', 'engajamento e propósito'],
  ['diversidade', 'diversidade e inclusão'], ['inclusao', 'diversidade e inclusão'],
  ['carreira', 'carreira'], ['promocao', 'carreira'],
  ['parentalidade', 'parentalidade'], ['maternidade', 'parentalidade'],
  ['paternidade', 'parentalidade'], ['filhos', 'parentalidade'],
  ['longevidade', 'longevidade e corpo'], ['sono', 'longevidade e corpo'],
  ['exercicio', 'longevidade e corpo'],
  ['finitude', 'finitude e sentido'], ['sentido da vida', 'finitude e sentido'],
  ['gratidao', 'gratidão'], ['autocompaixao', 'autocompaixão'],
  ['resiliencia', 'resiliência'], ['resiliente', 'resiliência'],
  ['solidao', 'relações e vínculos'], ['vinculos', 'relações e vínculos'],
  ['relacoes', 'relações e vínculos'],
  ['governanca', 'governança e compliance'], ['compliance', 'governança e compliance'],
  ['investidor', 'investidores e negócio'], ['investidores', 'investidores e negócio'],
];

function semAcento(s) {
  return String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
}

/* Por palavra inteira: sem a borda, "guerra" vira "erro" e a tela afirma um
   assunto que ninguém trouxe. */
export function temaDaPergunta(texto) {
  const t = semAcento(texto);
  for (const [palavra, tema] of TEMA_POR_PALAVRA) {
    const chave = palavra.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (new RegExp('(^|[^a-z0-9])' + chave + '([^a-z0-9]|$)').test(t)) return tema;
  }
  return null;
}

const NOME_DA_FERRAMENTA = {
  buscar_intelligence: 'Procurou no acervo do Summit',
  ler_intelligence: 'Leu o conteúdo encontrado',
};
/* Os cinco tipos que `sourceSummary` devolve em
   `supabase/functions/mindagent-chat/index.ts`. O que não está traduzido
   aparece cru, e nome de variável nossa não é texto de interface. */
const NOME_DA_FONTE = {
  event: 'evento', sessions: 'sessões', speakers: 'palestrantes',
  locations: 'locais', knowledge: 'acervo do Summit',
};

function relatoDoTurno(p) {
  const lista = [];
  const usadas = Array.isArray(p?.ferramentas) ? p.ferramentas : [];
  const contagem = new Map();
  for (const f of usadas) {
    const nome = f?.nome ? String(f.nome) : 'ferramenta';
    contagem.set(nome, (contagem.get(nome) || 0) + 1);
  }
  for (const [nome, vezes] of contagem) {
    const rotulo = NOME_DA_FERRAMENTA[nome] || nome;
    lista.push(vezes > 1 ? `${rotulo} (${vezes}×)` : rotulo);
  }
  if (!lista.length) lista.push('Respondeu sem consultar o acervo');
  const fontes = Array.isArray(p?.sources) ? p.sources : [];
  if (fontes.length) {
    lista.push('Contexto: ' + fontes
      .map((f) => `${NOME_DA_FONTE[f.type] || f.type} (${f.count})`).join(', '));
  }
  return lista;
}

/* O símbolo da marca, o mesmo do cabeçalho. No app o avatar do cabeçalho é um
   PNG branco — branco sobre o balão claro não se vê —, então aqui o desenho é
   inline e herda a cor do texto. */
const PETALA = '<svg class="mia-petala" aria-hidden="true" viewBox="698.13 264.35 522.24 522.24">'
  + '<path fill="currentColor" d="M1143.23,448.33c-21.02,0-40.08,8.41-53.99,22.05-32.36,27.8-75.06,45.12-121.83,46.93,1.81-46.77,19.14-89.47,46.93-121.83,13.64-13.91,22.05-32.97,22.05-53.99,0-42.6-34.54-77.14-77.14-77.14s-77.14,34.54-77.14,77.14c0,21.02,8.41,40.08,22.05,53.99,27.79,32.36,45.12,75.06,46.93,121.83-46.77-1.81-89.47-19.14-121.83-46.93-13.91-13.64-32.97-22.05-53.99-22.05-42.6,0-77.14,34.54-77.14,77.14s34.54,77.14,77.14,77.14c21.02,0,40.08-8.41,53.99-22.05,32.36-27.79,75.06-45.12,121.83-46.93-1.81,46.77-19.14,89.47-46.93,121.83-13.64,13.91-22.05,32.97-22.05,53.99,0,42.6,34.54,77.14,77.14,77.14s77.14-34.54,77.14-77.14c0-21.02-8.41-40.08-22.05-53.99-27.8-32.36-45.12-75.06-46.93-121.83,46.77,1.81,89.47,19.14,121.83,46.93,13.91,13.64,32.97,22.05,53.99,22.05,42.6,0,77.14-34.54,77.14-77.14s-34.54-77.14-77.14-77.14Z"/></svg>';

const SETA = '<span class="mia-chevron" aria-hidden="true">'
  + '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" '
  + 'stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l6 6-6 6"/></svg></span>';

/* ============================================================
   O BALÃO SOBE PARA O TOPO ANTES DE A RESPOSTA SURGIR
   ============================================================
   Duas armadilhas, as duas achadas rodando e nenhuma visível no código. Estão
   contadas por extenso em `learnworlds/mia-embed.html`:

   - `scrollHeight` NUNCA devolve menos que `clientHeight`, então numa conversa
     mais curta que a tela ele mente sobre o tamanho do conteúdo. A conta é
     contra o fundo do balão, que é o fim real;
   - `scrollTo({behavior:'smooth'})` não rola em todo navegador, e falha
     calada. A subida é animada na mão. */
function subirBalao(mensagens, el) {
  mensagens.style.paddingBottom = '';
  const topoDaArea = mensagens.getBoundingClientRect().top;
  const caixa = el.getBoundingClientRect();
  const topo = caixa.top - topoDaArea + mensagens.scrollTop;
  const fundo = caixa.bottom - topoDaArea + mensagens.scrollTop;
  const alvo = Math.max(0, topo - 10);
  const base = parseFloat(getComputedStyle(mensagens).paddingBottom) || 0;
  const falta = alvo + mensagens.clientHeight - (fundo + base);
  if (falta > 0) {
    mensagens.style.paddingBottom = Math.round(base + falta) + 'px';
    /* Obriga o navegador a refazer o layout AGORA: sem isso a rolagem logo
       abaixo acontece com a medida de antes de o espaço existir. */
    if (mensagens.scrollHeight < 0) return;
  }

  const partida = mensagens.scrollTop;
  const curso = alvo - partida;
  const comMovimento = !window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
  if (!comMovimento || !curso) { mensagens.scrollTop = alvo; return; }

  const comeco = Date.now();
  const subida = setInterval(() => {
    const f = Math.min(1, (Date.now() - comeco) / 320);
    mensagens.scrollTop = partida + curso * (1 - (1 - f) ** 3);
    if (f >= 1) { clearInterval(subida); mensagens.scrollTop = alvo; }
  }, 16);
}

/* ============================================================
   A RESPOSTA SURGE PALAVRA A PALAVRA, SAINDO DO DESFOQUE
   ============================================================
   A unidade é a palavra porque letra não aceita desfoque: para borrar uma
   letra é preciso um elemento para ela. O estado final é do CSS (`forwards`),
   então o texto está no DOM desde o primeiro quadro e o que entra é a
   opacidade — aba escondida não devolve resposta vazia. */

/* O atraso vem da POSIÇÃO da palavra, não da ordem: várias palavras de linhas
   diferentes entram juntas, em diagonal. Só vale para texto grande. */
function atrasosEmDiagonal(palavras, destino, corrida) {
  const caixa = destino.getBoundingClientRect();
  const largura = Math.max(1, caixa.width);
  const medidas = palavras.map((sp) => {
    const r = sp.getBoundingClientRect();
    return {
      /* Degraus de 4px: palavras da mesma linha não têm o topo exatamente
         igual quando há negrito ou link no meio. */
      topo: Math.round((r.top - caixa.top) / 4) * 4,
      fx: Math.min(1, Math.max(0, (r.left - caixa.left) / largura)),
    };
  });

  const linhas = [...new Set(medidas.map((m) => m.topo))].sort((a, b) => a - b);
  if (linhas.length < LINHAS_PARA_DIAGONAL) return null;

  const ondas = medidas.map((m) => linhas.indexOf(m.topo) + m.fx * ABERTURA_DIAGONAL);
  const menor = Math.min(...ondas);
  const vao = Math.max(0.001, Math.max(...ondas) - menor);
  return ondas.map((o) => Math.round(corrida * (o - menor) / vao));
}

function revelar(destino, html, aoMontar) {
  destino.innerHTML = html;

  const palavras = [];
  let letras = 0;
  (function varrer(no) {
    /* Os filhos são copiados antes: trocar nó enquanto se percorre
       `childNodes`, que é coleção viva, pula metade deles. */
    for (const filho of [...no.childNodes]) {
      if (filho.nodeType === 3) {
        const pedaco = document.createDocumentFragment();
        for (const parte of filho.nodeValue.split(/(\s+)/)) {
          if (!parte) continue;
          if (/^\s+$/.test(parte)) { pedaco.appendChild(document.createTextNode(parte)); continue; }
          const sp = document.createElement('span');
          sp.className = 'mia-palavra';
          sp.textContent = parte;
          pedaco.appendChild(sp);
          palavras.push(sp);
          letras += parte.length;
        }
        no.replaceChild(pedaco, filho);
      } else if (filho.nodeType === 1) varrer(filho);
    }
  })(destino);

  /* O balão só sobe depois de o texto estar montado: a altura dele é a do
     texto inteiro, e medir antes daria a altura errada. */
  aoMontar?.();
  if (!palavras.length) return { pular() {} };

  let vivo = true;
  let garantia = 0;

  /* Sem a classe, a regra do desfoque não casa com nada. Tirá-la também apaga
     o `filter` de todas as palavras — e `filter`, mesmo em `blur(0)`, mantém
     uma camada de composição por palavra enquanto estiver lá. */
  function tudo() {
    if (!vivo) return;
    vivo = false;
    clearTimeout(garantia);
    destino.removeEventListener('click', aoTocar);
    destino.classList.remove('mia-escrevendo');
    for (const sp of palavras) sp.style.animationDelay = '';
  }
  /* Sem `preventDefault`: clicar num link dentro da resposta continua
     abrindo o link. */
  function aoTocar() { tudo(); }
  destino.addEventListener('click', aoTocar);

  if (window.matchMedia?.('(prefers-reduced-motion: reduce)').matches) {
    destino.removeEventListener('click', aoTocar);
    return { pular() {} };
  }

  const duracao = Math.max(900, Math.min(12000, letras * 24));
  /* A última palavra precisa CABER dentro da duração, não começar nela. */
  const corrida = Math.max(0, duracao - SURGIR_MS);
  /* A medida da diagonal sai ANTES de a classe entrar: a classe põe
     `translateY`, e `getBoundingClientRect` devolve a posição já transformada. */
  const diagonal = atrasosEmDiagonal(palavras, destino, corrida);
  const passo = palavras.length > 1
    ? Math.min(PASSO_MAX_MS, corrida / (palavras.length - 1)) : 0;
  palavras.forEach((sp, i) => {
    sp.style.animationDelay = (diagonal ? diagonal[i] : Math.round(i * passo)) + 'ms';
  });
  destino.classList.add('mia-escrevendo');

  /* O estado final já é do CSS; isto existe para a classe e as camadas de
     composição saírem da tela quando o efeito acaba. */
  garantia = setTimeout(tudo, duracao + SURGIR_MS + 400);
  return { pular: tudo };
}

/* ============================================================
   O TURNO
   ============================================================ */

export function abrirTurnoDaMia(mensagens, pergunta, rotulo) {
  const el = document.createElement('div');
  el.className = 'bolha mind mia-turno';
  el.innerHTML = '<span class="quem">' + escapar(String(rotulo || 'MIA')) + '</span>'
    + '<button type="button" class="mia-pensou">' + PETALA
    + '<span class="mia-pensou-rotulo">Pensando</span></button>'
    + '<ol class="mia-passos"></ol>'
    + '<div class="mia-resposta"></div>';
  mensagens.appendChild(el);
  mensagens.scrollTop = mensagens.scrollHeight;

  const cabecalho = el.querySelector('.mia-pensou');
  const rotuloEl = el.querySelector('.mia-pensou-rotulo');
  const passos = el.querySelector('.mia-passos');
  const resposta = el.querySelector('.mia-resposta');
  const inicio = Date.now();
  const tempos = [];

  function montarPasso(t, andando) {
    const li = document.createElement('li');
    li.className = 'mia-passo' + (andando ? ' mia-andando' : ' mia-feito');
    const texto = document.createElement('span');
    texto.className = 'mia-passo-texto' + (andando ? ' mia-brilho' : '');
    /* O tema destacado é um pedaço separado, montado com `textContent`: nada
       vindo da pergunta de alguém ou do servidor vira marcação. */
    if (t && typeof t === 'object') {
      texto.appendChild(document.createTextNode(t.antes));
      const forte = document.createElement('b');
      forte.textContent = t.destaque;
      texto.appendChild(forte);
      if (t.depois) texto.appendChild(document.createTextNode(t.depois));
    } else {
      texto.textContent = t;
    }
    li.appendChild(texto);
    return li;
  }

  /* O passo novo entra EMBAIXO, e só ele. Redesenhar a lista a cada passo
     reinicia a animação de entrada dos que já estão na tela, e a lista pisca. */
  function acrescentar(t) {
    const atual = passos.lastElementChild;
    if (atual) {
      atual.classList.remove('mia-andando');
      atual.classList.add('mia-feito');
      atual.querySelector('.mia-brilho')?.classList.remove('mia-brilho');
    }
    passos.appendChild(montarPasso(t, true));
    mensagens.scrollTop = mensagens.scrollHeight;
  }

  /* Troca a lista inteira. Só o fim do turno faz isso: ali ela deixa de ser
     expectativa e vira o relato do que aconteceu. */
  function escrever(textos) {
    passos.innerHTML = '';
    textos.forEach((t, i) => {
      const li = montarPasso(t, false);
      li.style.animationDelay = (i * 45) + 'ms';
      passos.appendChild(li);
    });
    mensagens.scrollTop = mensagens.scrollHeight;
  }

  for (const [quando, texto] of passosDaEspera(temaDaPergunta(pergunta))) {
    tempos.push(setTimeout(() => acrescentar(texto), quando));
  }

  function pararEspera() {
    for (const t of tempos) clearTimeout(t);
    return Math.max(1, Math.round((Date.now() - inicio) / 1000));
  }

  return {
    concluir(p) {
      const segundos = pararEspera();
      cabecalho.classList.add('mia-pronto');
      rotuloEl.textContent = 'Pensou por ' + segundos + 's';
      cabecalho.insertAdjacentHTML('beforeend', SETA);
      cabecalho.setAttribute('aria-expanded', 'false');
      escrever(relatoDoTurno(p));
      passos.hidden = true;
      cabecalho.addEventListener('click', () => {
        passos.hidden = !passos.hidden;
        cabecalho.setAttribute('aria-expanded', passos.hidden ? 'false' : 'true');
      });
      return revelar(resposta, formatarResposta(p?.answer), () => subirBalao(mensagens, el));
    },
    falhar(texto) {
      pararEspera();
      cabecalho.remove();
      passos.remove();
      resposta.textContent = texto;
      mensagens.scrollTop = mensagens.scrollHeight;
    },
  };
}
