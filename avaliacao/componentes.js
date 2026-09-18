/* ============================================================
   AS PEÇAS DAS DUAS PESQUISAS
   ============================================================
   O bloco numerado, a escala de 0 a 5 e o campo de texto são os mesmos
   na Avaliação do dia e na do evento inteiro. Ficam aqui porque uma
   segunda cópia divergiria na primeira correção de acessibilidade — e
   divergiria em silêncio, já que as duas telas continuariam abrindo.

   O CSS continua em `avaliacao.css`, com as mesmas classes `av-`: as
   peças são as mesmas, então a folha é a mesma.

   Nada aqui conhece pergunta, resposta ou estado de tela. Quem monta o
   formulário é quem sabe o que está perguntando.
*/

export const NOTAS = [0, 1, 2, 3, 4, 5];

export function no(tag, classe, texto) {
  const el = document.createElement(tag);
  if (classe) el.className = classe;
  if (texto != null) el.textContent = texto;
  return el;
}

export function bloco(numero, pergunta, obrigatoria, apoio) {
  const el = no('section', 'av-bloco');
  const cabeca = no('div', 'av-cabeca');
  const h = no('h2', null, pergunta);
  if (numero) h.prepend(no('span', 'av-numero', String(numero)));
  cabeca.appendChild(h);
  if (obrigatoria) {
    const selo = no('span', 'av-obrigatoria', 'obrigatória');
    cabeca.appendChild(selo);
  }
  el.appendChild(cabeca);
  if (apoio) el.appendChild(no('p', 'av-apoio', apoio));
  return el;
}

/* Escala de 0 a 5 com rádios de verdade: leitor de tela e teclado saem
   de graça, e "0" é uma opção como qualquer outra — nunca o estado de
   quem não respondeu. */
export function escala({ nome, valor, pontas, aoEscolher, aoLimpar, rotuloDoGrupo }) {
  const el = no('div', 'av-escala');
  const grupo = no('div', 'av-notas');
  grupo.setAttribute('role', 'radiogroup');
  grupo.setAttribute('aria-label', rotuloDoGrupo || 'Nota de 0 a 5');

  NOTAS.forEach((n) => {
    const id = nome + '-' + n;
    const entrada = document.createElement('input');
    entrada.type = 'radio';
    entrada.name = nome;
    entrada.id = id;
    entrada.value = String(n);
    entrada.className = 'av-radio';
    entrada.checked = valor === n;
    entrada.addEventListener('change', () => aoEscolher(n));

    const rotulo = document.createElement('label');
    rotulo.className = 'av-nota';
    rotulo.htmlFor = id;
    rotulo.textContent = String(n);
    /* O número sozinho não diz o que significa para quem ouve a tela. */
    rotulo.setAttribute('aria-label', pontas && pontas[n] ? n + ' — ' + pontas[n] : 'Nota ' + n);

    grupo.appendChild(entrada);
    grupo.appendChild(rotulo);
  });
  el.appendChild(grupo);

  if (pontas) {
    const legenda = no('div', 'av-pontas');
    legenda.appendChild(no('small', null, '0 · ' + pontas[0]));
    legenda.appendChild(no('small', null, '5 · ' + pontas[5]));
    el.appendChild(legenda);
  }

  if (aoLimpar && valor != null) {
    const limpar = no('button', 'av-limpar', 'Limpar nota');
    limpar.type = 'button';
    limpar.addEventListener('click', aoLimpar);
    el.appendChild(limpar);
  }
  return el;
}

export function campoTexto({ valor, limite, linhas, placeholder, aoDigitar, rotulo }) {
  const el = no('div', 'av-campo');
  const entrada = document.createElement(linhas > 1 ? 'textarea' : 'input');
  if (linhas > 1) entrada.rows = linhas; else entrada.type = 'text';
  entrada.className = 'av-entrada';
  entrada.value = valor || '';
  entrada.maxLength = limite;
  entrada.placeholder = placeholder || '';
  if (rotulo) entrada.setAttribute('aria-label', rotulo);
  const contador = no('small', 'av-contador', (valor || '').length + '/' + limite);
  entrada.addEventListener('input', () => {
    contador.textContent = entrada.value.length + '/' + limite;
    aoDigitar(entrada.value);
  });
  el.appendChild(entrada);
  el.appendChild(contador);
  return el;
}

/* O ERRO DE CAMPO NÃO ESTÁ AQUI, de propósito. Ele vive no estado de
   cada tela — quais campos faltam, qual aviso está no topo, qual foi o
   último envio — e trazê-lo para cá exigiria reescrever uns vinte pontos
   da Avaliação do dia, que já está no ar recebendo resposta de verdade,
   sem mudar comportamento nenhum. Quando as duas telas precisarem da
   mesma correção ali, é essa correção que paga a mudança. */
