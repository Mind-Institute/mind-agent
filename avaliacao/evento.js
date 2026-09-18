/* ============================================================
   AVALIAÇÃO DO EVENTO — a tela
   ============================================================
   A segunda pesquisa: o Mind Summit inteiro, respondido depois que ele
   acaba. As mesmas oito perguntas da Avaliação do dia, com "hoje"
   trocado por "o evento" — e sem a grade de atividades, porque as duas
   pesquisas do dia já colheram essa nota com a memória fresca.

   O QUE ELA DIVIDE com a tela do dia: as peças (`componentes.js`), a
   folha (`avaliacao.css`, mesmas classes `av-`), a sessão e a porta
   (`servico.js`). O que ela NÃO divide é o estado: são duas respostas
   diferentes, e misturá-las seria deixar uma apagar a outra.

   REGRA QUE VALE PARA O ARQUIVO INTEIRO
   Uma falha da pesquisa nunca derruba a home nem o chat. Nada aqui
   lança para fora; quem chama recebe tela de erro, não exceção.

   NOTA AUSENTE NÃO É NOTA ZERO. Toda checagem de nota usa `== null`, e
   nunca `!nota` — zero é resposta.
*/

import {
  carregarEstadoDoEvento, enviarDoEvento, ESCOPO_DO_EVENTO,
  lerRascunho, salvarRascunho, limparRascunho,
} from './servico.js';
import { no, bloco, escala, campoTexto } from './componentes.js';

const ESCALA_RELEVANCIA = { 0: 'Nada relevante', 5: 'Muito relevante' };
const ESCALA_PROGRAMACAO = { 0: 'Muito ruim', 5: 'Excelente' };

const EXPERIENCIAS = [
  { id: 'mind', rotulo: 'Mind' },
  { id: 'vip', rotulo: 'VIP' },
  { id: 'prime', rotulo: 'Prime' },
];

const LIMITES = { profissao: 120, expectativas: 1000, aberta: 1000 };

/* ============================================================
   O ESTADO DA TELA
   ============================================================ */

let raiz = null;
let aoVoltar = null;
let aoEnviar = null;
let aoNomear = null;

let estado = null;          /* o que o servidor respondeu */
let resposta = null;        /* o que a pessoa preencheu */
let etapa = 'formulario';   /* formulario · conferencia · obrigado */
let enviando = false;
let erros = {};
let avisoGeral = null;

function respostaVazia() {
  return {
    experiencia: '',
    profissao: '',
    expectativas: '',
    notaRelevancia: null,
    notaProgramacao: null,
    maisGostou: '',
    melhorar: '',
    comentario: '',
  };
}

function guardarRascunho() {
  if (!estado) return;
  salvarRascunho(ESCOPO_DO_EVENTO, estado.formularioVersao, resposta);
}

/* ============================================================
   ABRIR
   ============================================================ */

export async function abrirAvaliacaoDoEvento(elemento, voltar, enviada, nomear) {
  raiz = elemento;
  aoVoltar = voltar;
  aoEnviar = enviada;
  aoNomear = nomear || null;
  erros = {};
  avisoGeral = null;
  enviando = false;

  /* Volta para o formulário, mas preserva o que já estava preenchido:
     sair e voltar não pode apagar nota nenhuma. */
  if (etapa !== 'obrigado') etapa = 'formulario';

  desenharCarregando();

  const novo = await carregarEstadoDoEvento();
  if (!novo) {
    estado = null;
    /* QUEM CHEGOU POR LINK NÃO TEM HOME PARA ONDE VOLTAR, e mandá-la
       voltar para lá é mandá-la para uma tela que não é dela e que pede
       login. A instrução muda com o lugar de onde a pessoa veio. */
    return desenharIndisponivel(
      'Não consegui abrir a avaliação agora.',
      aoVoltar
        ? 'Pode ser a conexão. Volte para a home e tente de novo em instantes.'
        : 'Pode ser a conexão. Recarregue esta página em instantes.',
    );
  }
  estado = novo;

  if (!estado.identificado) {
    /* Por convite, "não reconhecemos você" quer dizer que o link não
       vale — e o motivo vem do servidor. Mandar essa pessoa "abrir pelo
       app" seria mandá-la para onde ela não consegue entrar. */
    return desenharIndisponivel(
      aoVoltar ? 'Não reconhecemos quem você é.' : 'Este link não é mais válido.',
      aoVoltar
        ? 'Abra a avaliação pelo app do evento, com o link que você recebeu, para que a sua resposta fique ligada ao seu cadastro.'
        : {
            expirado: 'O prazo deste link terminou. Peça um novo para a organização.',
            ja_respondida: 'Esta avaliação já foi respondida. Obrigado!',
          }[estado.motivo] || 'Peça um novo link para a organização do evento.',
    );
  }
  if (!estado.ativo) {
    /* O MOTIVO MUDA A FRASE. Quem chega cedo demais e quem chega tarde
       demais não podem receber o mesmo texto: um deve voltar, o outro
       não tem mais o que fazer ali. */
    return desenharIndisponivel(
      estado.motivo === 'ja_fechou'
        ? 'A avaliação já foi encerrada.'
        : 'A avaliação ainda não está aberta.',
      {
        ja_fechou: 'Obrigado pelo interesse — o prazo de resposta terminou.',
        ainda_nao_abriu: 'Assim que ela abrir, o card aparece na home.',
        desligada: 'Assim que ela abrir, o card aparece na home.',
      }[estado.motivo] || 'Assim que ela abrir, o card aparece na home.',
    );
  }
  if (estado.enviado) {
    etapa = 'obrigado';
    limparRascunho(ESCOPO_DO_EVENTO, estado.formularioVersao);
    return desenhar();
  }

  /* Rascunho da MESMA pessoa e da MESMA versão do formulário. O escopo
     é `evento`, e não uma data: esta pesquisa não tem dia. */
  if (aoNomear) aoNomear(subtituloDaAvaliacaoDoEvento());

  resposta = lerRascunho(ESCOPO_DO_EVENTO, estado.formularioVersao) || respostaVazia();
  if (!resposta.experiencia && estado.experienciaSugerida) {
    /* Sugestão, não decisão: já vem marcada e a pessoa confirma ou troca.
       Trocar aqui não mexe em ingresso, cadastro nem permissão. */
    resposta.experiencia = estado.experienciaSugerida;
  }

  desenhar();
}

function desenharCarregando() {
  raiz.innerHTML = '';
  raiz.appendChild(no('p', 'av-carregando', 'Abrindo a avaliação…'));
}

function desenharIndisponivel(titulo, texto) {
  raiz.innerHTML = '';
  const caixa = no('div', 'av-vazio');
  caixa.appendChild(no('strong', null, titulo));
  caixa.appendChild(no('p', null, texto));
  /* QUEM CHEGA POR LINK NÃO TEM PARA ONDE VOLTAR. O botão só existe
     quando existe home atrás dele; oferecê-lo sem destino é um botão
     que não faz nada. */
  if (aoVoltar) {
    const b = no('button', 'av-botao secundario', 'Voltar para a home');
    b.type = 'button';
    b.addEventListener('click', () => aoVoltar());
    caixa.appendChild(b);
  }
  raiz.appendChild(caixa);
}

/* ============================================================
   ERRO DE CAMPO
   ============================================================ */

function mostrarErro(el, campo) {
  if (!erros[campo]) return;
  const p = no('p', 'av-erro', erros[campo]);
  p.id = 'erro-' + campo;
  p.setAttribute('role', 'alert');
  el.appendChild(p);
}

/* Some com o erro sem redesenhar a tela. Redesenhar a cada toque num
   rádio tiraria o foco e faria a página saltar. */
function limparErro(campo) {
  delete erros[campo];
  const p = raiz && raiz.querySelector('#erro-' + campo);
  if (p) p.remove();
  if (!Object.keys(erros).length) {
    avisoGeral = null;
    const faixa = raiz && raiz.querySelector('.av-faixa');
    if (faixa) faixa.remove();
  }
}

/* ============================================================
   O DESENHO
   ============================================================ */

function desenhar() {
  if (!raiz) return;
  const rolagem = raiz.scrollTop;
  raiz.innerHTML = '';

  if (etapa === 'obrigado') return desenharObrigado();
  if (etapa === 'conferencia') return desenharConferencia();

  desenharFormulario();
  raiz.scrollTop = rolagem;
}

function desenharFormulario() {
  if (avisoGeral) {
    const faixa = no('p', 'av-faixa', avisoGeral);
    faixa.setAttribute('role', 'alert');
    raiz.appendChild(faixa);
  }

  /* 1 — experiência */
  const b1 = bloco(1, 'Qual experiência você vivenciou no Mind Summit?', true);
  const opcoes = no('div', 'av-opcoes');
  opcoes.setAttribute('role', 'radiogroup');
  opcoes.setAttribute('aria-label', 'Experiência vivenciada no evento');
  EXPERIENCIAS.forEach((e) => {
    const id = 'ev-exp-' + e.id;
    const entrada = document.createElement('input');
    entrada.type = 'radio';
    entrada.name = 'experiencia-evento';
    entrada.id = id;
    entrada.className = 'av-radio';
    entrada.checked = resposta.experiencia === e.id;
    entrada.addEventListener('change', () => {
      resposta.experiencia = e.id;
      limparErro('experiencia');
      guardarRascunho();
    });
    const rotulo = document.createElement('label');
    rotulo.className = 'av-opcao';
    rotulo.htmlFor = id;
    /* A MESMA COR QUE O CABEÇALHO JÁ USA para o ingresso: Mind verde,
       VIP coral, Prime roxo. */
    rotulo.dataset.cor = e.id;
    rotulo.textContent = e.rotulo;
    opcoes.appendChild(entrada);
    opcoes.appendChild(rotulo);
  });
  b1.appendChild(opcoes);
  mostrarErro(b1, 'experiencia');
  raiz.appendChild(b1);

  /* 2 — profissão */
  const b2 = bloco(2, 'Qual é a sua profissão?', true);
  b2.appendChild(campoTexto({
    valor: resposta.profissao, limite: LIMITES.profissao, linhas: 1,
    placeholder: 'Ex.: gerente de RH', rotulo: 'Sua profissão',
    aoDigitar: (v) => { resposta.profissao = v; limparErro('profissao'); guardarRascunho(); },
  }));
  mostrarErro(b2, 'profissao');
  raiz.appendChild(b2);

  /* 3 — expectativas */
  const b3 = bloco(3, 'Quais eram suas principais expectativas pessoais e profissionais em relação ao evento?', true);
  b3.appendChild(campoTexto({
    valor: resposta.expectativas, limite: LIMITES.expectativas, linhas: 4,
    placeholder: 'O que você esperava encontrar aqui', rotulo: 'Suas expectativas',
    aoDigitar: (v) => { resposta.expectativas = v; limparErro('expectativas'); guardarRascunho(); },
  }));
  mostrarErro(b3, 'expectativas');
  raiz.appendChild(b3);

  /* 4 — relevância */
  const b4 = bloco(4,
    'Quanto o que você vivenciou no Mind foi relevante para sua vida pessoal ou profissional?',
    true);
  b4.appendChild(escala({
    nome: 'ev-nota-relevancia', valor: resposta.notaRelevancia, pontas: ESCALA_RELEVANCIA,
    rotuloDoGrupo: 'Quanto o que você vivenciou no evento foi relevante para sua vida pessoal ou profissional, de 0 a 5',
    aoEscolher: (n) => {
      resposta.notaRelevancia = n; limparErro('notaRelevancia'); guardarRascunho();
    },
  }));
  mostrarErro(b4, 'notaRelevancia');
  raiz.appendChild(b4);

  /* 5 — programação */
  const b5 = bloco(5, 'De 0 a 5, como você avalia a programação do evento?', true);
  b5.appendChild(escala({
    nome: 'ev-nota-programacao', valor: resposta.notaProgramacao, pontas: ESCALA_PROGRAMACAO,
    rotuloDoGrupo: 'Sua avaliação da programação do evento, de 0 a 5',
    aoEscolher: (n) => {
      resposta.notaProgramacao = n; limparErro('notaProgramacao'); guardarRascunho();
    },
  }));
  mostrarErro(b5, 'notaProgramacao');
  raiz.appendChild(b5);

  /* 6, 7, 8 — as abertas */
  [
    { n: 6, p: 'O que você mais gostou no Mind Summit?', c: 'maisGostou' },
    { n: 7, p: 'O que podemos melhorar?', c: 'melhorar' },
    { n: 8, p: 'Quer deixar mais algum comentário?', c: 'comentario' },
  ].forEach((q) => {
    const el = bloco(q.n, q.p, false, 'Opcional');
    el.appendChild(campoTexto({
      valor: resposta[q.c], limite: LIMITES.aberta, linhas: 3, rotulo: q.p,
      aoDigitar: (v) => { resposta[q.c] = v; guardarRascunho(); },
    }));
    raiz.appendChild(el);
  });

  const rodape = no('div', 'av-rodape');
  const avancar = no('button', 'av-botao', 'Revisar e enviar');
  avancar.type = 'button';
  avancar.addEventListener('click', () => {
    if (!validar()) { desenhar(); return; }
    etapa = 'conferencia';
    desenhar();
    raiz.scrollTop = 0;
  });
  rodape.appendChild(avancar);
  raiz.appendChild(rodape);
}

/* ============================================================
   VALIDAR
   ============================================================ */

function validar() {
  erros = {};
  if (!resposta.experiencia) erros.experiencia = 'Escolha a experiência que você vivenciou.';
  if (!resposta.profissao.trim()) erros.profissao = 'Conte qual é a sua profissão.';
  if (!resposta.expectativas.trim()) erros.expectativas = 'Conte o que você esperava do evento.';
  /* `== null` e não `!`: zero é nota, e `!0` é verdadeiro. */
  if (resposta.notaRelevancia == null) erros.notaRelevancia = 'Dê uma nota de 0 a 5.';
  if (resposta.notaProgramacao == null) erros.notaProgramacao = 'Dê uma nota de 0 a 5.';

  avisoGeral = Object.keys(erros).length
    ? 'Faltam respostas obrigatórias. Elas estão marcadas abaixo.' : null;
  return !Object.keys(erros).length;
}

/* ============================================================
   CONFERIR E ENVIAR
   ============================================================ */

function linhaDeConferencia(rotulo, valor) {
  const el = no('div', 'av-linha');
  el.appendChild(no('dt', null, rotulo));
  el.appendChild(no('dd', null, valor));
  return el;
}

function desenharConferencia() {
  if (avisoGeral) {
    const faixa = no('p', 'av-faixa', avisoGeral);
    faixa.setAttribute('role', 'alert');
    raiz.appendChild(faixa);
  }

  const topo = no('div', 'av-conferencia');
  topo.appendChild(no('h2', null, 'Confira antes de enviar'));
  topo.appendChild(no('p', 'av-apoio',
    'Confira suas respostas. Após enviar, você não poderá alterá-las.'));
  raiz.appendChild(topo);

  const lista = no('dl', 'av-lista');
  const nomeExp = (EXPERIENCIAS.find((e) => e.id === resposta.experiencia) || {}).rotulo;
  lista.appendChild(linhaDeConferencia('Experiência', nomeExp || '—'));
  lista.appendChild(linhaDeConferencia('Profissão', resposta.profissao.trim()));
  lista.appendChild(linhaDeConferencia('Expectativas', resposta.expectativas.trim()));
  lista.appendChild(linhaDeConferencia('Relevância', resposta.notaRelevancia + ' de 5'));
  lista.appendChild(linhaDeConferencia('Programação', resposta.notaProgramacao + ' de 5'));
  if (resposta.maisGostou.trim()) lista.appendChild(linhaDeConferencia('O que mais gostou', resposta.maisGostou.trim()));
  if (resposta.melhorar.trim()) lista.appendChild(linhaDeConferencia('O que melhorar', resposta.melhorar.trim()));
  if (resposta.comentario.trim()) lista.appendChild(linhaDeConferencia('Comentário', resposta.comentario.trim()));
  raiz.appendChild(lista);

  const rodape = no('div', 'av-rodape');
  const voltarBotao = no('button', 'av-botao secundario', 'Voltar e ajustar');
  voltarBotao.type = 'button';
  voltarBotao.addEventListener('click', () => { etapa = 'formulario'; avisoGeral = null; desenhar(); });

  const enviarBotao = no('button', 'av-botao', enviando ? 'Enviando…' : 'Enviar avaliação');
  enviarBotao.type = 'button';
  /* Clique duplo não vira envio duplo, e o botão diz o que está havendo. */
  enviarBotao.disabled = enviando;
  enviarBotao.addEventListener('click', confirmarEnvio);

  rodape.appendChild(voltarBotao);
  rodape.appendChild(enviarBotao);
  raiz.appendChild(rodape);
}

async function confirmarEnvio() {
  if (enviando) return;
  if (!validar()) { etapa = 'formulario'; desenhar(); return; }

  enviando = true;
  avisoGeral = null;
  desenhar();

  const corpo = {
    eventSlug: estado.evento && estado.evento.slug,
    experiencia: resposta.experiencia,
    profissao: resposta.profissao.trim(),
    expectativas: resposta.expectativas.trim(),
    notaRelevancia: resposta.notaRelevancia,
    notaProgramacao: resposta.notaProgramacao,
    maisGostou: resposta.maisGostou.trim() || null,
    melhorar: resposta.melhorar.trim() || null,
    comentario: resposta.comentario.trim() || null,
  };

  try {
    await enviarDoEvento(corpo);
    return concluir();
  } catch (e) {
    /* JÁ ENVIADA é sucesso do ponto de vista da pessoa: a resposta dela
       está gravada, e é isso que importa. */
    if (e.codigo === 'ja_enviada') return concluir();

    /* Não sabemos se gravou — timeout, rede caída no meio. PERGUNTAMOS
       ao servidor antes de concluir ou de deixar tentar de novo, porque
       a alternativa é gravar duas vezes ou perder o envio. */
    if (e.codigo === 'indeterminado') {
      const conferido = await carregarEstadoDoEvento();
      if (conferido && conferido.enviado) return concluir();
      avisoGeral = 'A conexão oscilou e o envio não foi concluído. Suas respostas continuam aqui — toque em enviar de novo.';
    } else {
      avisoGeral = e.message;
    }
    enviando = false;
    desenhar();
    raiz.scrollTop = 0;
  }
}

/* Só depois da confirmação REAL do servidor. Antes disso o rascunho não
   é apagado e o card da home não muda. */
function concluir() {
  limparRascunho(ESCOPO_DO_EVENTO, estado.formularioVersao);
  estado = { ...estado, enviado: true };
  etapa = 'obrigado';
  enviando = false;
  desenhar();
  if (aoEnviar) aoEnviar(estado);
}

function desenharObrigado() {
  const caixa = no('div', 'av-obrigado');
  caixa.appendChild(no('span', 'av-tique', '✓'));
  caixa.appendChild(no('strong', null, 'Avaliação enviada. Obrigado!'));
  caixa.appendChild(no('p', null,
    'Sua avaliação do Mind Summit foi registrada e não pode mais ser alterada.'));
  if (aoVoltar) {
    const b = no('button', 'av-botao', 'Voltar para a home');
    b.type = 'button';
    b.addEventListener('click', () => aoVoltar());
    caixa.appendChild(b);
  }
  raiz.appendChild(caixa);
}

/** O subtítulo da tela. Por convite ele diz o nome de quem o link é —
    é como a pessoa reconhece que o link é dela, e não de outra. */
export function subtituloDaAvaliacaoDoEvento() {
  const nome = estado && estado.primeiroNome;
  return nome ? 'Olá, ' + nome + ' · sua experiência no Mind Summit'
              : 'Sua experiência no Mind Summit';
}

/** Existe rascunho ou envio em andamento? O `app.js` usa para decidir se
    vale avisar antes de sair. */
export function temRascunhoDoEvento() {
  return Boolean(resposta && etapa === 'formulario' && (
    resposta.experiencia || resposta.profissao || resposta.expectativas ||
    resposta.notaRelevancia != null || resposta.notaProgramacao != null
  ));
}
