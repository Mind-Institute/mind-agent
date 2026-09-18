/* ============================================================
   AVALIAÇÃO DO DIA — a tela
   ============================================================
   Uma tela interna do Mind Agent: mesma aba, mesma sessão, a conversa
   continua onde estava. Não abre janela, não redireciona e não recarrega.

   O MÓDULO É FECHADO. Ele recebe uma raiz para desenhar dentro e dois
   avisos para dar (`aoVoltar`, `aoEnviar`). Não conhece home, chat nem
   tour, e nada fora daqui conhece o estado do formulário.

   A DATA É FIXADA NA ABERTURA. `estado.dia` vem do servidor com o dia
   corrente do evento no fuso America/Sao_Paulo, e não é recalculado: um
   formulário aberto às 23h50 continua avaliando o dia 16 depois da
   meia-noite. É o servidor que decide o dia, e é ele que valida de novo
   no envio.
*/

import { carregarEstado, enviar, lerRascunho, salvarRascunho, limparRascunho } from './servico.js';
import { NOTAS, no, bloco, escala, campoTexto } from './componentes.js';


/* As pontas acompanham a pergunta. "Não atendeu / Atendeu completamente"
   respondia a expectativa; a pergunta agora é sobre relevância, e a
   legenda não pode continuar medindo outra coisa. */
const ESCALA_RELEVANCIA = { 0: 'Nada relevante', 5: 'Muito relevante' };
const ESCALA_PROGRAMACAO = { 0: 'Muito ruim', 5: 'Excelente' };

const EXPERIENCIAS = [
  { id: 'mind', rotulo: 'Mind' },
  { id: 'vip', rotulo: 'VIP' },
  { id: 'prime', rotulo: 'Prime' },
];

/* Os filtros pedidos, na ordem pedida. `todos` não filtra nada; os
   outros três casam com a CATEGORIA DE ACESSO da sessão (`ingressos`),
   que é o que separa quem pode entrar onde. Não é trilha: `trilhas`
   existe na tabela e está vazia em todas as sessões, e filtrar por ela
   devolveria uma lista vazia que pareceria grade sem conteúdo. */
const FILTROS = [
  { id: 'todos', rotulo: 'Todos' },
  { id: 'mind', rotulo: 'Mind' },
  { id: 'vip', rotulo: 'VIP' },
  { id: 'prime', rotulo: 'Prime' },
];

const LIMITES = { profissao: 120, expectativas: 1000, aberta: 1000 };

const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

/** "2026-09-16" → "16 de setembro". Sem `new Date`: o ISO já é o dia certo,
    e construir Date a partir dele reintroduz fuso onde não há fuso. */
function diaPorExtenso(iso) {
  const p = String(iso || '').split('-');
  if (p.length !== 3) return '';
  return Number(p[2]) + ' de ' + (MESES[Number(p[1]) - 1] || '');
}


/* ============================================================
   O ESTADO DA TELA
   ============================================================ */

let raiz = null;
let aoVoltar = null;
let aoEnviar = null;

let estado = null;          /* o que o servidor respondeu */
let resposta = null;        /* o que a pessoa preencheu */
let filtro = 'todos';
let etapa = 'formulario';   /* formulario · conferencia · obrigado */
let enviando = false;
let erros = {};
let avisoGeral = null;

function respostaVazia() {
  return {
    experiencia: null,
    profissao: '',
    expectativas: '',
    notaRelevancia: null,
    notaProgramacao: null,
    maisGostou: '',
    melhorar: '',
    comentario: '',
    /* `{ [sessaoId]: nota }`. A ausência da chave é a ausência de
       avaliação — nunca zero. Zero é uma nota que alguém deu. */
    atividades: {},
  };
}

/** O que vale guardar como rascunho é o que a pessoa escreveu. */
function guardarRascunho() {
  if (!estado || etapa === 'obrigado') return;
  salvarRascunho(estado.dia, estado.formularioVersao, resposta);
}

/* ============================================================
   A ABERTURA
   ============================================================ */

/**
 * Monta a tela dentro de `elemento`.
 * `voltar()` é chamado quando a pessoa sai; `enviada(estado)` quando o
 * servidor confirmou o envio — é por ele que a home troca o card.
 */
export async function abrirAvaliacao(elemento, voltar, enviada) {
  raiz = elemento;
  aoVoltar = voltar;
  aoEnviar = enviada;
  erros = {};
  avisoGeral = null;
  enviando = false;

  /* Volta para o formulário, mas preserva o que já estava preenchido:
     sair e voltar não pode apagar nota nenhuma. */
  if (etapa !== 'obrigado') etapa = 'formulario';

  desenharCarregando();

  const novo = await carregarEstado(estado && estado.dia ? estado.dia : null);
  if (!novo) {
    estado = null;
    return desenharIndisponivel(
      'Não consegui abrir a avaliação agora.',
      'Pode ser a conexão. Volte para a home e tente de novo em instantes.',
    );
  }
  estado = novo;

  if (!estado.identificado) {
    return desenharIndisponivel(
      'Não reconhecemos quem você é.',
      'Abra a avaliação pelo app do evento, com o link que você recebeu, para que a sua resposta fique ligada ao seu cadastro.',
    );
  }
  if (!estado.ativo) {
    return desenharIndisponivel(
      'A avaliação não está disponível agora.',
      estado.motivo === 'fora_do_evento'
        ? 'Ela abre nos dias do Summit.'
        : 'Assim que ela abrir, o card aparece na home.',
    );
  }
  if (estado.enviado) {
    etapa = 'obrigado';
    limparRascunho(estado.dia, estado.formularioVersao);
    return desenhar();
  }

  /* Rascunho da MESMA pessoa, do MESMO dia e da MESMA versão. Qualquer
     um dos três diferente e ele não serve — a chave garante isso. */
  resposta = lerRascunho(estado.dia, estado.formularioVersao) || respostaVazia();
  resposta.atividades = resposta.atividades && typeof resposta.atividades === 'object'
    ? resposta.atividades : {};
  if (!resposta.experiencia && estado.experienciaSugerida) {
    /* Sugestão, não decisão: já vem marcada e a pessoa confirma ou troca.
       Trocar aqui não mexe em ingresso, cadastro nem permissão. */
    resposta.experiencia = estado.experienciaSugerida;
  }

  desenhar();
}

function desenharCarregando() {
  raiz.innerHTML = '';
  raiz.appendChild(no('p', 'av-aviso', 'Abrindo a avaliação…'));
}

function desenharIndisponivel(titulo, texto) {
  raiz.innerHTML = '';
  const caixa = no('div', 'av-vazio');
  caixa.appendChild(no('strong', null, titulo));
  caixa.appendChild(no('p', null, texto));
  const b = no('button', 'av-botao secundario', 'Voltar para a home');
  b.type = 'button';
  b.addEventListener('click', () => aoVoltar && aoVoltar());
  caixa.appendChild(b);
  raiz.appendChild(caixa);
}

/* ============================================================
   PEÇAS DO FORMULÁRIO
   ============================================================ */


function mostrarErro(el, campo) {
  if (!erros[campo]) return;
  const p = no('p', 'av-erro', erros[campo]);
  p.id = 'erro-' + campo;
  p.setAttribute('role', 'alert');
  el.appendChild(p);
}

/* Some com o erro sem redesenhar a tela. Redesenhar a cada toque num
   rádio tiraria o foco e faria a página saltar — num formulário longo
   isso é o suficiente para a pessoa desistir. */
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

/* Escala de 0 a 5 com rádios de verdade: leitor de tela e teclado saem
   de graça, e "0" é uma opção como qualquer outra — nunca o estado de
   quem não respondeu. */


/* ============================================================
   A LISTA DE ATIVIDADES
   ============================================================ */

function atividadesVisiveis() {
  const todas = Array.isArray(estado.atividades) ? estado.atividades : [];
  if (filtro === 'todos') return todas;
  /* Filtrar ESCONDE linhas, não apaga notas: `resposta.atividades` não é
     tocado aqui, e uma nota dada com o filtro em "VIP" continua lá
     quando o filtro volta para "Todos". */
  return todas.filter((a) => Array.isArray(a.ingressos) && a.ingressos.includes(filtro));
}

function quantasAvaliadas() {
  return Object.keys(resposta.atividades).length;
}

function linhaDeAtividade(a) {
  const el = no('article', 'av-atividade' + (a.operacional ? ' operacional' : ''));

  const topo = no('div', 'av-at-topo');
  topo.appendChild(no('span', 'av-hora', a.fim ? a.inicio + '–' + a.fim : a.inicio));
  if (a.espaco) topo.appendChild(no('span', 'av-espaco', a.espaco));
  el.appendChild(topo);

  el.appendChild(no('strong', 'av-at-titulo', a.titulo));

  if (Array.isArray(a.palestrantes) && a.palestrantes.length) {
    el.appendChild(no('small', 'av-quem', a.palestrantes.join(' · ')));
  }

  if (a.operacional) {
    /* Credenciamento, intervalo e almoço ficam na lista para a grade do
       dia continuar inteira, e é dito na tela por que eles não têm nota:
       são blocos de operação, não atividades para avaliar. */
    el.appendChild(no('p', 'av-informativo', 'Bloco da operação do evento — sem avaliação.'));
    return el;
  }

  /* A LINHA SE ATUALIZA SOZINHA. Redesenhar o formulário inteiro a cada
     nota faria a tela saltar no meio de uma lista de 35 atividades e
     tiraria o foco do dedo que acabou de tocar. Aqui trocamos só a
     escala desta linha e o contador lá em cima. */
    const trocarEscala = () => {
    const antiga = el.querySelector('.av-escala');
    const nova = montarEscalaDaAtividade(a, trocarEscala);
    if (antiga) el.replaceChild(nova, antiga); else el.appendChild(nova);
    atualizarContagem();
  };
  el.appendChild(montarEscalaDaAtividade(a, trocarEscala));

  return el;
}

function montarEscalaDaAtividade(a, aoMudar) {
  const atual = Object.prototype.hasOwnProperty.call(resposta.atividades, a.id)
    ? resposta.atividades[a.id] : null;
  return escala({
    nome: 'at-' + a.id,
    valor: atual,
    rotuloDoGrupo: 'Nota de 0 a 5 para ' + a.titulo,
    aoEscolher: (n) => { resposta.atividades[a.id] = n; guardarRascunho(); aoMudar(); },
    aoLimpar: () => { delete resposta.atividades[a.id]; guardarRascunho(); aoMudar(); },
  });
}

/* O contador de avaliadas vive fora das linhas e é atualizado por elas. */
let contagemEl = null;

function textoDaContagem() {
  const n = quantasAvaliadas();
  return n === 0 ? 'Nenhuma atividade avaliada até agora'
    : n === 1 ? '1 atividade avaliada' : n + ' atividades avaliadas';
}

function atualizarContagem() {
  if (contagemEl && contagemEl.isConnected) contagemEl.textContent = textoDaContagem();
}

function secaoDeAtividades() {
  const el = bloco(6, 'Avalie as atividades de que você participou hoje', false,
    'Avalie apenas as atividades de que você participou. Todas as notas aqui são opcionais — deixar em branco é não avaliar, e não é nota zero.');

  const barra = no('div', 'av-filtros');
  barra.setAttribute('role', 'group');
  barra.setAttribute('aria-label', 'Filtrar atividades por experiência');
  FILTROS.forEach((f) => {
    const b = no('button', 'av-filtro' + (filtro === f.id ? ' on' : ''), f.rotulo);
    b.type = 'button';
    b.setAttribute('aria-pressed', String(filtro === f.id));
    b.addEventListener('click', () => { filtro = f.id; desenhar(); });
    barra.appendChild(b);
  });
  el.appendChild(barra);

  contagemEl = no('p', 'av-contagem', textoDaContagem());
  contagemEl.setAttribute('aria-live', 'polite');
  el.appendChild(contagemEl);

  const lista = atividadesVisiveis();
  if (!lista.length) {
    /* Lista vazia aqui é resultado de filtro, e é dito assim. Falha ao
       carregar a grade nunca chega neste ponto: sem grade a tela inteira
       não abre. */
    el.appendChild(no('p', 'av-aviso', 'Nenhuma atividade desta experiência na programação de hoje.'));
    return el;
  }
  lista.forEach((a) => el.appendChild(linhaDeAtividade(a)));
  return el;
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

  /* O E-MAIL SAIU DA TELA, NÃO DO CONTRATO. Ele nunca foi um campo: era um
     texto fixo confirmando quem estava respondendo. Quem responde continua
     sendo decidido no servidor, pelo vínculo canônico do token — a tela nunca
     mandou e-mail junto das respostas e continua não mandando. O que mudou é
     que a pessoa não precisa mais ler o próprio cadastro para começar. */

  /* 1 — experiência */
  const b2 = bloco(1, 'Qual experiência você vivenciou hoje?', true);
  const opcoes = no('div', 'av-opcoes');
  opcoes.setAttribute('role', 'radiogroup');
  opcoes.setAttribute('aria-label', 'Experiência vivenciada hoje');
  EXPERIENCIAS.forEach((e) => {
    const id = 'exp-' + e.id;
    const entrada = document.createElement('input');
    entrada.type = 'radio';
    entrada.name = 'experiencia';
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
       VIP coral, Prime roxo. `data-cor` é o mesmo atributo de
       `.h-ingresso`, e por isso a regra é uma leitura da paleta que já
       existe, não uma segunda. */
    rotulo.dataset.cor = e.id;
    rotulo.textContent = e.rotulo;
    opcoes.appendChild(entrada);
    opcoes.appendChild(rotulo);
  });
  b2.appendChild(opcoes);
  /* A sugestão não se explica mais na tela. Os três botões já mostram que
     dá para trocar, e a frase ocupava quatro linhas para dizer isso. A
     ressalva que ela carregava continua verdadeira e continua valendo: a
     resposta é autodeclarada e não toca em ingresso, cadastro nem
     permissão — quem garante isso é a tabela, não o texto. */
  mostrarErro(b2, 'experiencia');
  raiz.appendChild(b2);

  /* 3 — profissão */
  const b3 = bloco(2, 'Qual é a sua profissão?', true);
  b3.appendChild(campoTexto({
    valor: resposta.profissao, limite: LIMITES.profissao, linhas: 1,
    placeholder: 'Ex.: gerente de RH', rotulo: 'Sua profissão',
    aoDigitar: (v) => { resposta.profissao = v; limparErro('profissao'); guardarRascunho(); },
  }));
  mostrarErro(b3, 'profissao');
  raiz.appendChild(b3);

  /* 4 — expectativas */
  const b4 = bloco(3, 'Quais eram suas principais expectativas pessoais e profissionais em relação ao evento?', true);
  b4.appendChild(campoTexto({
    valor: resposta.expectativas, limite: LIMITES.expectativas, linhas: 4,
    placeholder: 'O que você esperava encontrar aqui', rotulo: 'Suas expectativas',
    aoDigitar: (v) => { resposta.expectativas = v; limparErro('expectativas'); guardarRascunho(); },
  }));
  mostrarErro(b4, 'expectativas');
  raiz.appendChild(b4);

  /* 5 — nota das expectativas */
  const b5 = bloco(4,
    'Quanto o que você vivenciou hoje no Mind foi relevante para sua vida pessoal ou profissional?',
    true);
  b5.appendChild(escala({
    nome: 'nota-relevancia', valor: resposta.notaRelevancia, pontas: ESCALA_RELEVANCIA,
    rotuloDoGrupo: 'Quanto o que você vivenciou hoje foi relevante para sua vida pessoal ou profissional, de 0 a 5',
    aoEscolher: (n) => {
      resposta.notaRelevancia = n; limparErro('notaRelevancia'); guardarRascunho();
    },
  }));
  mostrarErro(b5, 'notaRelevancia');
  raiz.appendChild(b5);

  /* 6 — nota da programação */
  const b6 = bloco(5, 'De 0 a 5, como você avalia a programação de hoje?', true);
  b6.appendChild(escala({
    nome: 'nota-programacao', valor: resposta.notaProgramacao, pontas: ESCALA_PROGRAMACAO,
    rotuloDoGrupo: 'Sua avaliação da programação de hoje, de 0 a 5',
    aoEscolher: (n) => {
      resposta.notaProgramacao = n; limparErro('notaProgramacao'); guardarRascunho();
    },
  }));
  mostrarErro(b6, 'notaProgramacao');
  raiz.appendChild(b6);

  /* 7 — as atividades */
  raiz.appendChild(secaoDeAtividades());

  /* 8, 9, 10 — as abertas */
  [
    { n: 7, p: 'O que você mais gostou hoje?', c: 'maisGostou' },
    { n: 8, p: 'O que podemos melhorar?', c: 'melhorar' },
    { n: 9, p: 'Quer deixar mais algum comentário?', c: 'comentario' },
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

/** Devolve `true` quando dá para seguir. Preenche `erros` quando não dá. */
function validar() {
  erros = {};
  if (!resposta.experiencia) erros.experiencia = 'Escolha a experiência que você vivenciou hoje.';
  if (!resposta.profissao.trim()) erros.profissao = 'Conte qual é a sua profissão.';
  else if (resposta.profissao.trim().length > LIMITES.profissao) {
    erros.profissao = 'Use até ' + LIMITES.profissao + ' caracteres.';
  }
  if (!resposta.expectativas.trim()) erros.expectativas = 'Conte o que você esperava do evento.';
  else if (resposta.expectativas.trim().length > LIMITES.expectativas) {
    erros.expectativas = 'Use até ' + LIMITES.expectativas + ' caracteres.';
  }
  /* `== null` de propósito: zero é resposta válida e não pode cair aqui. */
  if (resposta.notaRelevancia == null) erros.notaRelevancia = 'Escolha uma nota de 0 a 5.';
  if (resposta.notaProgramacao == null) erros.notaProgramacao = 'Escolha uma nota de 0 a 5.';
  avisoGeral = Object.keys(erros).length ? 'Faltam respostas obrigatórias. Elas estão marcadas abaixo.' : null;
  return !Object.keys(erros).length;
}

function linhaDeConferencia(rotulo, valor) {
  const el = no('div', 'av-conf-linha');
  el.appendChild(no('dt', null, rotulo));
  el.appendChild(no('dd', valor ? null : 'av-vazio-linha', valor || 'Sem resposta'));
  return el;
}

function desenharConferencia() {
  const topo = no('div', 'av-confirma');
  topo.appendChild(no('strong', null, 'Confira suas respostas. Após enviar, você não poderá alterá-las.'));
  raiz.appendChild(topo);

  if (avisoGeral) {
    const faixa = no('p', 'av-faixa', avisoGeral);
    faixa.setAttribute('role', 'alert');
    raiz.appendChild(faixa);
  }

  const lista = no('dl', 'av-conferencia');
  const nomeExp = (EXPERIENCIAS.find((e) => e.id === resposta.experiencia) || {}).rotulo;
  lista.appendChild(linhaDeConferencia('Experiência', nomeExp));
  lista.appendChild(linhaDeConferencia('Profissão', resposta.profissao.trim()));
  lista.appendChild(linhaDeConferencia('Expectativas', resposta.expectativas.trim()));
  lista.appendChild(linhaDeConferencia('Relevância do que você vivenciou', resposta.notaRelevancia + ' de 5'));
  lista.appendChild(linhaDeConferencia('Programação de hoje', resposta.notaProgramacao + ' de 5'));

  const n = quantasAvaliadas();
  lista.appendChild(linhaDeConferencia('Atividades avaliadas',
    n === 0 ? 'Nenhuma' : n === 1 ? '1 atividade' : n + ' atividades'));

  if (resposta.maisGostou.trim()) lista.appendChild(linhaDeConferencia('O que mais gostou', resposta.maisGostou.trim()));
  if (resposta.melhorar.trim()) lista.appendChild(linhaDeConferencia('O que melhorar', resposta.melhorar.trim()));
  if (resposta.comentario.trim()) lista.appendChild(linhaDeConferencia('Comentário', resposta.comentario.trim()));
  raiz.appendChild(lista);

  const rodape = no('div', 'av-rodape');

  const enviarBotao = no('button', 'av-botao', enviando ? 'Enviando…' : 'Enviar avaliação');
  enviarBotao.type = 'button';
  /* Clique duplo não vira envio duplo: o botão desliga antes da primeira
     chamada sair, e o `enviando` cobre o caso do toque que escapou entre
     o clique e o redesenho. */
  enviarBotao.disabled = enviando;
  enviarBotao.addEventListener('click', confirmarEnvio);
  rodape.appendChild(enviarBotao);

  const voltarBotao = no('button', 'av-botao secundario', 'Voltar e corrigir');
  voltarBotao.type = 'button';
  voltarBotao.disabled = enviando;
  voltarBotao.addEventListener('click', () => { etapa = 'formulario'; avisoGeral = null; desenhar(); });
  rodape.appendChild(voltarBotao);

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
    dia: estado.dia,
    experiencia: resposta.experiencia,
    profissao: resposta.profissao.trim(),
    expectativas: resposta.expectativas.trim(),
    notaRelevancia: resposta.notaRelevancia,
    notaProgramacao: resposta.notaProgramacao,
    maisGostou: resposta.maisGostou.trim() || null,
    melhorar: resposta.melhorar.trim() || null,
    comentario: resposta.comentario.trim() || null,
    atividades: Object.keys(resposta.atividades)
      .map((id) => ({ sessaoId: id, nota: resposta.atividades[id] })),
  };

  try {
    await enviar(corpo);
    return concluir();
  } catch (e) {
    /* JÁ ENVIADA é sucesso do ponto de vista da pessoa: a resposta dela
       está gravada, e é isso que importa. Acontece quando ela abriu em
       dois aparelhos. */
    if (e.codigo === 'ja_enviada') return concluir();

    /* Não sabemos se gravou — timeout, rede caída no meio. PERGUNTAMOS
       ao servidor antes de concluir ou de deixar tentar de novo, porque
       a alternativa é gravar duas vezes ou perder o envio. */
    if (e.codigo === 'indeterminado') {
      const conferido = await carregarEstado(estado.dia);
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
  limparRascunho(estado.dia, estado.formularioVersao);
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
    'Sua avaliação de ' + diaPorExtenso(estado.dia) + ' foi registrada e não pode mais ser alterada.'));
  const b = no('button', 'av-botao', 'Voltar para a home');
  b.type = 'button';
  b.addEventListener('click', () => aoVoltar && aoVoltar());
  caixa.appendChild(b);
  raiz.appendChild(caixa);
}

/** O subtítulo da tela: "Sua experiência no Mind · 16 de setembro". */
export function subtituloDaAvaliacao() {
  if (!estado || !estado.dia) return 'Sua experiência no Mind';
  return 'Sua experiência no Mind · ' + diaPorExtenso(estado.dia);
}

/** Existe rascunho ou envio em andamento? A home não pergunta isto — o
    `app.js` usa para decidir se vale avisar antes de sair. */
export function temRascunho() {
  return Boolean(resposta && etapa === 'formulario' && (
    resposta.experiencia || resposta.profissao || resposta.expectativas ||
    resposta.notaRelevancia != null || resposta.notaProgramacao != null ||
    Object.keys(resposta.atividades).length
  ));
}
