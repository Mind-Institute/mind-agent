/* ============================================================
   MIA — a conversa da página `/mia`
   ============================================================
   Só a tela. Quem fala com o agente é o `chat-service.js`, o mesmo do
   app; quem decide que agente responde é o banco, pela porta de entrada:
   `institute_learnworlds` está em `agentes.canal_competencia.entradas_diretas`
   da MIA no canal `mindagent-web` (painel → Canais e Roteador). Com o
   canal da MIA desligado, a porta não vale e o roteador decide — por isso
   o embed só vai ao ar depois de ligar a MIA.
*/

import { ligarTeclado, tecladoAberto } from '../teclado.js';
import { conversaPropria, enviarMensagem } from '../chat-service.js';
import { formatarResposta } from './formato.js';

/* O espaço da sessão e a porta. Mudar a porta é mudar também o dado no
   painel, senão a página cai no roteador. */
conversaPropria('mia', 'institute_learnworlds');
ligarTeclado();

const mensagens = document.getElementById('mia-mensagens');
const form = document.getElementById('mia-form');
const campo = document.getElementById('mia-campo');
const enviar = form.querySelector('.enviar');
const sugestoes = document.getElementById('mia-sugestoes');

const ABERTURA =
  'Oi! Eu sou a MIA 💚 Conheço por dentro as palestras, painéis, workshops e ' +
  'masterclasses do Mind Summit 2026.\n\n' +
  'Me pergunte o que um palestrante disse sobre um tema, peça o resumo de uma ' +
  'sessão ou me conte uma situação do seu trabalho — eu trago as ideias que ' +
  'ajudam e onde elas aparecem, para você assistir.';

/* Começos de frase, não perguntas prontas: a pessoa completa com o tema
   dela. Pergunta pronta seria conteúdo inventado aqui. */
const SUGESTOES = [
  { rotulo: 'Resumir uma sessão', texto: 'Me resuma a sessão sobre ' },
  { rotulo: 'O que disseram sobre um tema', texto: 'O que os palestrantes disseram sobre ' },
  { rotulo: 'Uma situação do meu trabalho', texto: 'Tenho uma situação no meu trabalho: ' },
];

/* Resposta longa (resumo de sessão) não pode abrir rolada até o fim: a
   pessoa perderia o começo. A conversa para no INÍCIO da resposta.
   Sem `scrollIntoView`, que dentro de um iframe rola também a página do
   LearnWorlds. */
function mostrarInicio(el) {
  const delta = el.getBoundingClientRect().top - mensagens.getBoundingClientRect().top;
  mensagens.scrollTop += delta - 12;
}

function bolha(conteudo, quem) {
  const el = document.createElement('div');
  el.className = 'bolha ' + quem;
  if (quem === 'mind') el.innerHTML = formatarResposta(conteudo);
  else el.textContent = conteudo;
  mensagens.appendChild(el);
  if (quem === 'mind') mostrarInicio(el);
  else mensagens.scrollTop = mensagens.scrollHeight;
  return el;
}

function digitando() {
  const el = document.createElement('div');
  el.className = 'bolha mind';
  el.innerHTML = '<span class="digitando"><i></i><i></i><i></i></span>';
  mensagens.appendChild(el);
  mensagens.scrollTop = mensagens.scrollHeight;
  /* A MIA lê transcrições antes de responder e pode levar alguns
     segundos. Três pontinhos parados por vinte segundos parecem travamento. */
  const aviso = setTimeout(() => {
    const t = document.createElement('span');
    t.className = 'mia-buscando';
    t.textContent = 'Procurando nas sessões…';
    el.appendChild(t);
  }, 4000);
  return { remover: () => { clearTimeout(aviso); el.remove(); } };
}

let emAndamento = false;

async function perguntar(texto) {
  const limpo = String(texto || '').trim();
  if (!limpo || emAndamento) return;
  emAndamento = true;
  sugestoes.hidden = true;
  bolha(limpo, 'eu');
  const espera = digitando();
  /* O campo continua habilitado, como no app: desabilitar campo focado
     fecha o teclado no iOS. Quem segura o envio duplo é `emAndamento`. */
  enviar.disabled = true;
  try {
    const resposta = await enviarMensagem(limpo);
    espera.remover();
    bolha(resposta.answer, 'mind');
  } catch (erro) {
    espera.remover();
    /* Erro de rede chega com a frase do navegador ("Load failed",
       "Failed to fetch"); isso nunca aparece para a pessoa. */
    const mensagem = erro?.name === 'AbortError'
      ? 'A resposta demorou demais. Tente novamente.'
      : erro instanceof TypeError
      ? 'Não consegui responder agora. Tente novamente.'
      : (erro?.message || 'Não consegui responder agora. Tente novamente.');
    bolha(mensagem, 'mind');
  } finally {
    emAndamento = false;
    enviar.disabled = false;
    /* Só devolve o foco se ele estava nesta página: dentro do LearnWorlds,
       a pessoa pode ter ido ler outra coisa enquanto a resposta vinha. */
    if (document.hasFocus() && document.activeElement !== campo && !tecladoAberto()) {
      campo.focus({ preventScroll: true });
    }
  }
}

/* O campo cresce com o texto até um teto; acima disso, rola por dentro. */
function ajustarAltura() {
  campo.style.height = 'auto';
  campo.style.height = Math.min(campo.scrollHeight, 160) + 'px';
}

form.addEventListener('submit', (e) => {
  e.preventDefault();
  const texto = campo.value;
  campo.value = '';
  ajustarAltura();
  perguntar(texto);
});

/* Enter envia; Shift+Enter quebra a linha. Composição de acento (IME)
   não envia no meio da palavra. */
campo.addEventListener('keydown', (e) => {
  if (e.key !== 'Enter' || e.shiftKey || e.isComposing || e.keyCode === 229) return;
  e.preventDefault();
  if (form.requestSubmit) form.requestSubmit();
  else form.dispatchEvent(new Event('submit', { cancelable: true }));
});
campo.addEventListener('input', ajustarAltura);

for (const s of SUGESTOES) {
  const b = document.createElement('button');
  b.type = 'button';
  b.textContent = s.rotulo;
  b.addEventListener('click', () => {
    campo.value = s.texto;
    ajustarAltura();
    campo.focus({ preventScroll: true });
    campo.setSelectionRange(campo.value.length, campo.value.length);
  });
  sugestoes.appendChild(b);
}

bolha(ABERTURA, 'mind');
