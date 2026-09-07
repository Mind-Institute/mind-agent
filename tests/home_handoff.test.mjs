/* ============================================================
   O QUE O HANDOFF DE 02/09 DECIDIU, E QUE SOME SEM AVISAR
   ============================================================
   Este arquivo não abre navegador. Ele trava, nos bytes vivos, as
   decisões da home "antes" e da tela de avisos que um diff de uma linha
   desfaz sem parecer errado — e cujo estrago só aparece num celular.

   A prova de aparência foi feita em navegador, sobre o build, comparando
   com o protótipo do handoff em 393x852, 375x667 e 360x740. O que roda
   sempre é isto aqui.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const css = readFileSync(new URL('../styles.css', import.meta.url), 'utf8');
const estado = readFileSync(new URL('../home/estado.js', import.meta.url), 'utf8');
const cards = readFileSync(new URL('../home/cards.js', import.meta.url), 'utf8');
const avisosJs = readFileSync(new URL('../home/avisos.js', import.meta.url), 'utf8');
const avisos = readFileSync(new URL('../home/avisos.js', import.meta.url), 'utf8');
const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const dados = readFileSync(new URL('../data-service.js', import.meta.url), 'utf8');
const homeJs = readFileSync(new URL('../home/home.js', import.meta.url), 'utf8');
/* A migração VIGENTE da função — a de 21:00 abriu a porta, a de 22:00
   trocou a lista fechada de tipos pela exclusão da sentinela. É o
   comportamento vivo que estes testes travam. */
const migracao = readFileSync(new URL('../supabase/migrations/20260902220000_camarote_tambem_e_tipo_de_ingresso.sql', import.meta.url), 'utf8');
const funcaoHome = readFileSync(new URL('../supabase/functions/mindagent-home/index.ts', import.meta.url), 'utf8');
const config = readFileSync(new URL('../config.js', import.meta.url), 'utf8');
const bootstrap = readFileSync(new URL('../supabase/migrations/20260903151000_bootstrap_app_schema_vivo.sql', import.meta.url), 'utf8');
const temasVivos = readFileSync(new URL('../supabase/migrations/20260903152000_temas_grade_viva.sql', import.meta.url), 'utf8');
const temasHorariosVivos = readFileSync(new URL('../supabase/migrations/20260903153000_temas_grade_horarios_vivos.sql', import.meta.url), 'utf8');

test('os atalhos levam a destinos que existem', () => {
  /* Um atalho é uma promessa: "toque e você chega em Meu ingresso". Se o
     destino não existir, `acaoDaHome` cai no `irParaConversa(null)` do
     fim e a pessoa vai parar no chat — sem erro nenhum na tela, que é o
     que torna isto invisível em revisão. */
  /* A fatia começa em "Como usar o app": desde 06/09 há uma fileira ANTES
     desta, a dos dois recados de véspera, e ela tem teste próprio. */
  const bloco = estado.slice(estado.indexOf("tipo: 'secao', titulo: 'Como usar o app'"), estado.indexOf("tipo: 'secao', titulo: 'Avisos"));
  const destinos = [...bloco.matchAll(/acao: '([^']+)'/g)].map((m) => m[1]);
  assert.deepEqual(destinos, ['tour:qrcode', 'tour:minha-agenda'],
    'os destinos dos atalhos mudaram');
  /* E os dois de cima: o amarelo de reservar e a porta dos avisos. */
  const vespera = estado.slice(estado.indexOf("tipo: 'atalhos'"), estado.indexOf("tipo: 'destaque', marca: true"));
  assert.deepEqual([...vespera.matchAll(/acao: '([^']+)'/g)].map((m) => m[1]), ['tour', 'avisos'],
    'os destinos dos recados de véspera mudaram');
  assert.match(app, /if \(acao === 'avisos'\)/,
    'o destino dos avisos deixou de ser tratado');

  /* O tile do mapa saiu em 02/09 para os três caberem numa linha e sobrar
     altura para mais um aviso. O ROTEIRO `mapa` continua existindo e
     continua alcançável — de dentro do tour, pelo Menu, e por
     `abrirTourCompleto('mapa')`. O que saiu foi o atalho, não o caminho. */
  assert.match(app, /if \(acao\.startsWith\('roteiro:'\)\) return abrirTourCompleto/,
    'a ação de roteiro guiado deixou de ser tratada');
  const m = app.indexOf('  mapa: {');
  const roteiroMapa = app.slice(m, app.indexOf('  ingresso: {', m));
  assert.ok(m > 0 && roteiroMapa.length > 100, 'não achei o roteiro do mapa');
  assert.match(roteiroMapa, /de: 'menu'/,
    'o roteiro do mapa deixou de começar no Menu');

  assert.match(app, /if \(acao === 'tour'\) return abrirTourCompleto\(\)/,
    'o destino do atalho de reservas deixou de ser tratado');
  assert.match(app, /if \(acao\.startsWith\('tour:'\)\) return abrirTutorialEm/,
    'os destinos com tela deixaram de ser tratados');
  for (const tela of ['qrcode', 'minha-agenda', 'mapa']) {
    assert.ok(app.includes("'" + tela + "': {"),
      'a tela ' + tela + ' saiu do tour');
  }
});

test('os atalhos são deitados, um por linha, com descrição', () => {
  /* Foram tiles quadrados em trio: num aparelho de 360 cada um ficava com
     ~98px, a descrição era cortada e o título não passava de duas palavras.
     Deitado, o símbolo fica à esquerda e o texto ocupa a largura que sobra.

     O HTML é UM SÓ para todos: `display: contents` no invólucro do topo
     solta ícone e chevron como itens da grade. Um segundo formato de
     `innerHTML` aqui era o que cortava a descrição. */
  assert.doesNotMatch(cards, /' trio'/,
    'o trio voltou: os atalhos deixaram de ser deitados');
  assert.doesNotMatch(css, /\.v3-atalhos\.trio/,
    'sobrou CSS de trio para um layout que não existe mais');
  assert.doesNotMatch(cards, /gridTemplateColumns/,
    'a grade voltou a montar colunas por JS em vez de uma por linha');
  assert.match(cards, /'<span class="v3-atalho-topo">.*<\/span>' \+\s*'<strong>' \+ t\.titulo/s,
    'os atalhos voltaram a ter dois formatos de marcação');
  assert.match(cards, /'<small>' \+ t\.texto \+ '<\/small>'/,
    'a descrição do atalho sumiu da marcação');
  assert.match(css, /\.v3-atalho \.v3-atalho-topo \{ display: contents/,
    'ícone e chevron deixaram de entrar na grade do atalho');
  assert.match(css, /\.v3-atalho \{[^}]*grid-template-columns:\s*auto 1fr auto/,
    'o atalho deixou de ser deitado');
});

test('o atalho em destaque é o amarelo da marca, e só isso', () => {
  /* `destaque` não é mais layout — todos têm o mesmo. Ele diz só qual card
     é o amarelo, e o amarelo é o da paleta, não um inventado. */
  assert.match(css, /\.v3-atalhos \.v3-atalho\.destaque\s*\{[^}]*background:\s*var\(--amarelo\)/,
    'o destaque perdeu o fundo amarelo, que é o que o faz destaque');
  assert.match(css, /--amarelo:\s*#fbf4d0/i,
    'o amarelo deixou de ser o da marca (#FBF4D0)');
  assert.doesNotMatch(css, /\.v3-atalho\.destaque\s*\{[^}]*grid-column/,
    'o destaque voltou a precisar de regra de coluna própria');
  assert.match(cards, /' destaque' : ''/,
    'a classe do destaque sumiu da montagem');
  assert.match(estado, /titulo: 'Aprenda como reservar suas experiências'/,
    'o título do atalho de reserva mudou sem passar por aqui');
});

test('a pílula do ingresso tem uma cor por experiência', () => {
  /* O roxo era de todas e não dizia nada. Mind verde, VIP coral, Prime e
     Camarote roxo — e texto escuro sobre verde e coral, onde branco não
     teria contraste. */
  for (const [cor, fundo] of [['mind', '--verde'], ['vip', '--coral'], ['camarote', '--roxo']]) {
    assert.match(css, new RegExp('\\.h-ingresso\\[data-cor="' + cor + '"\\][^{]*\\{[^}]*var\\(' + fundo + '\\)'),
      'a pílula de ' + cor + ' perdeu a cor própria');
  }
  /* Medido em 393px: em caixa alta a pílula do Camarote dá 174px e passa
     6px da borda, empurrando a marca do evento para fora. */
  assert.match(css, /\.h-ingresso\[data-cor="camarote"\]\s*\{[^}]*text-transform:\s*none/,
    'o rótulo do Camarote voltou à caixa alta e não cabe mais no cabeçalho');
  assert.match(app, /camarote: \{ nome: 'Camarote Heineken'/,
    'o rótulo de tela do Camarote mudou sem passar por aqui');
});

test('nenhum bloco da home encolhe para caber', () => {
  /* Numa coluna flex que transborda, `flex-shrink` vale 1 e o navegador
     espreme os filhos em vez de rolar. Foi assim que a descrição do aviso
     saiu 4,8px por baixo da borda do próprio card. */
  assert.match(css, /\.v3-rolagem\s*>\s*\*\s*\{[^}]*flex:\s*none/,
    'a defesa contra o esmagamento dos blocos sumiu: texto de duas linhas '
    + 'volta a vazar para fora do card');
});

test('o modificador do card de marca não é uma classe solta', () => {
  /* `variante: 'marca'` casou com `.marca` do tour — `position: absolute` —
     e jogou o card do Concierge para fora da tela. Modificador de card
     carrega o nome do card. */
  assert.match(cards, /' destaque-marca'/,
    'o card de marca voltou a usar um nome de classe genérico');
  assert.doesNotMatch(estado, /variante: 'marca'/,
    'o conteúdo voltou a injetar `marca` como classe solta no DOM');
});

test('a escala grande do hero fica presa à tela que foi desenhada', () => {
  /* O handoff desenhou só a tela "antes". Soltar `.v3-titulo` em 34px
     mudaria "Bom dia." do dia do evento e as outras duas telas sem
     ninguém ter olhado. */
  assert.match(css, /\.v3-hero\.decorado \.v3-titulo\s*\{[^}]*font-size:\s*34px/,
    'a escala de display do hero saiu do modificador');
  const solto = css.match(/\n\.v3-titulo\s*\{[^}]*\}/);
  assert.ok(solto && !/34px/.test(solto[0]),
    'a escala de 34px vazou para o `.v3-titulo` solto e agora vale nas quatro telas');
});

test('categoria de aviso é dado, com queda para o verde', () => {
  for (const c of ['antes_de_ir', 'no_evento', 'reservas']) {
    assert.ok(estado.includes("'" + c + "'"), 'a categoria ' + c + ' sumiu de estado.js');
  }
  /* `ingressos` deixou de ser toggle em 03/09 (pedido da Adriana: três, e só
     três). Um aviso gravado assim no painel continua aparecendo — cai no
     verde pela queda abaixo — mas não ganha chip próprio. */
  assert.ok(!estado.includes("id: 'ingressos'"), 'a categoria ingressos voltou como toggle');
  assert.match(estado, /categoriaValida\(a\.categoria \|\| a\.cat\)/,
    'a leitura da categoria vinda do banco mudou de forma');
  /* Aviso gravado antes da coluna existir chega sem categoria. Ele tem
     que aparecer assim mesmo — um aviso é para ser lido. */
  assert.match(estado, /CATEGORIAS_AVISO\.some\(\(c\) => c\.id === id\) \? id : 'antes_de_ir'/,
    'categoria desconhecida deixou de cair no verde e pode sumir da tela');
  assert.match(css, /\.c-no_evento \.v3-ico[^}]*var\(--roxo\)/, 'a tinta roxa sumiu');
  assert.match(css, /\.c-reservas \.v3-ico[^}]*var\(--coral\)/, 'a tinta coral sumiu');
});

test('o filtro de avisos não mostra chip que não tem o que filtrar', () => {
  assert.match(avisos, /CATEGORIAS_AVISO\.filter\(\(c\) => AVISOS\.some\(/,
    'os chips voltaram a ser fixos: aparece "Reservas" mesmo sem nenhum aviso de reserva');
  assert.match(avisos, /Nenhum aviso nesta categoria agora/,
    'filtro sem resultado voltou a devolver tela em branco, que é lida como erro');
});

test('a home não rola para os lados', () => {
  /* `overflow-y: auto` sozinho não basta: quando um eixo deixa de ser
     `visible`, o CSS transforma o outro em `auto`. Foi assim que o halo
     do hero, sangrando 70px para fora da direita, virou 50px de rolagem
     lateral — a tela deslizando como carrossel. */
  const i = css.indexOf('.v3-rolagem {');
  const regra = css.slice(i, css.indexOf('\n}', i));
  assert.match(regra, /overflow-x:\s*hidden/,
    'a home voltou a poder rolar na horizontal; o halo do hero sangra 70px e '
    + 'é ele que vira barra de rolagem');
});

test('o atalho abre UMA tela, não um roteiro', () => {
  /* O atalho trocava a tela e deixava as missões da reserva rodando por
     baixo: a barra dizia "Reservar seu lugar" e o anel circulava
     "Programação" enquanto a pessoa estava em "Minha Agenda". */
  assert.match(app, /function abrirTutorialEm\(tela\)\s*\{[\s\S]{0,220}telaAvulsa = tela;[\s\S]{0,80}MISSOES = \[\];/,
    'abrirTutorialEm parou de limpar o roteiro: o atalho volta a arrastar as '
    + 'missões da reserva para dentro da tela pedida');
  assert.match(app, /telaAvulsa = null;\s*\n\s*MISSOES = roteiro\.missoes;/,
    'o roteiro completo parou de desligar a bandeira de tela avulsa');
});

test('arrastar volta, e não teleporta na primeira tela', () => {
  assert.match(app, /function temVolta\(\)/,
    'a guarda que impede o arrastar de cair no `|| \'menu\'` de voltar() sumiu');
  assert.match(app, /if \(temVolta\(\)\) voltar\(\); else avisar\(/,
    'o arrastar voltou a chamar voltar() sem checar se há para onde voltar');
  /* Arrastar por cima de um alvo não pode abrir o alvo. */
  assert.match(app, /addEventListener\('click',[\s\S]{0,140}arrastou[\s\S]{0,160}\}, true\)/,
    'o clique que fecha o arrastar deixou de ser engolido na captura');
  /* A imagem não pode ser arrastável: o gesto nativo do navegador rouba
     o ponteiro no primeiro milímetro e o arrastar nunca acontece. */
  assert.match(css, /\.frame img\s*\{[^}]*user-drag:\s*none/,
    'a captura voltou a ser arrastável e o gesto de voltar morre no primeiro pixel');
});

test('a demonstração diz o tempo todo que não é o app da pessoa', () => {
  /* Dentro do quadro está a captura da tela REAL e ela funciona: dá para
     tocar e navegar. É por funcionar que o aviso precisa ser insistente —
     senão alguém tenta apresentar o QR da demonstração na entrada.

     Três avisos independentes, porque quem entra com pressa lê um só. */
  const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  assert.match(html, /class="t-selo"/, 'o selo "Demonstração" sumiu do topo');
  assert.match(html, /id="t-previa"/, 'a frase de prévia sumiu do cabeçalho');
  assert.match(css, /\.fone\s*\{[^}]*border:\s*2px solid var\(--verde\)/,
    'a moldura verde em volta do quadro sumiu — era o aviso que não depende de leitura');
  assert.match(app, /const NEGA_POR_TELA = \{/,
    'a negação por tela sumiu: "não é o seu ingresso" vira "não é o seu app" '
    + 'justamente onde a confusão é mais cara');
});

test('o botão de missões some quando não há missão', () => {
  /* `hidden` vale por uma regra do navegador com especificidade zero, e
     `.c-voltar` define `display: grid` — sem esta regra o `☰` aparecia na
     tela avulsa e abria uma lista vazia. */
  assert.match(css, /\.t-demo \.c-voltar\[hidden\]\s*\{\s*display:\s*none/,
    'o `hidden` do botão de missões voltou a perder para o `display` do botão');
});

test('o título da demonstração é nome de tela, não a missão inteira', () => {
  assert.match(app, /nome: 'Lugar reservado'/,
    'o roteiro de reserva perdeu o nome curto e o título volta a ser a missão inteira');
  assert.match(app, /missaoTexto\.textContent = ROTEIROS\[roteiroAtual\]\.nome/,
    'o cabeçalho voltou a escrever a missão com contador no lugar do nome');
});

test('a tela que ensina pelo alto mostra a instrução, e só ela', () => {
  /* Pedido da Adriana em 06/09 para a primeira tela do tour: sai o nome do
     roteiro ("Lugar reservado") e sai a frase de prévia; entra, no alto, a
     instrução que antes ficava no rodapé. O rodapé fica vazio na mesma
     tela — a explicação é uma só, e repeti-la em cima e embaixo era dizer
     duas vezes. */
  assert.match(app, /instrucao: 'O menu programação mostra todas as experiências do evento\./,
    'a instrução da tela de Programação mudou ou saiu');
  assert.match(app, /explica\.textContent = tela\.instrucao \? '' : \(tela\.serve \|\| ''\)/,
    'o rodapé voltou a repetir a explicação que já está no alto');
  assert.match(app, /previa\.hidden = Boolean\(instrucao\)/,
    'a frase de prévia voltou a aparecer na tela que ensina pelo alto');
});

test('o aviso de prévia continua onde o erro seria caro', () => {
  /* A instrução só substitui a prévia na tela que a recebeu. Nas telas em
     que confundir a demonstração com o app custa caro — o QR que alguém
     tentaria apresentar na entrada, a agenda que alguém leria como a sua —
     `NEGA_POR_TELA` continua respondendo. */
  /* A tela do ingresso é a que sustenta o aviso: é o QR que alguém tentaria
     apresentar na entrada. As quatro telas do roteiro de reserva ensinam
     pelo alto e não mostram mais a frase; o selo verde e a moldura verde,
     que são os outros dois avisos, seguem em todas. */
  assert.match(app, /qrcode:\s*'não é o seu ingresso'/,
    'a tela do ingresso perdeu o aviso de que o QR não é o da pessoa');
  const telas = app.slice(app.indexOf('const TELAS = {'), app.indexOf('const ROTEIROS = {'));
  /* As quatro telas do roteiro de reserva, e só elas: quem ensina pelo alto
     é decisão de tela a tela, não um padrão que se espalha. */
  assert.equal((telas.match(/^\s+instrucao:/gm) || []).length, 4,
    'o número de telas que ensinam pelo alto mudou sem a decisão passar por aqui');
  assert.match(app, /instrucao: 'Ao abrir a página da experiência clique em Reservar lugar'/,
    'a instrução da página da experiência mudou ou saiu');
});

test('o aviso da reserva sobe para o cabeçalho, e só na tela que pediu', () => {
  /* Pedido da Adriana em 06/09: na tela da reserva confirmada o aviso sai
     de cima da captura — que fica limpa — e vira texto no cabeçalho com o
     botão logo abaixo. Quem decide é a TELA de destino, não a folha: a
     mesma `reservado` continua modal no roteiro do Camarote. */
  const telas = app.slice(app.indexOf('const TELAS = {'), app.indexOf('const ROTEIROS = {'));
  assert.equal((telas.match(/^\s+folhaNoAlto: true,/gm) || []).length, 1,
    'mais de uma tela passou a tirar o aviso de dentro do quadro');
  assert.match(app, /if \(TELAS\[telaAtual\] && TELAS\[telaAtual\]\.folhaNoAlto\) \{/,
    'o aviso voltou a abrir sempre como modal dentro do quadro');
  /* A confirmação continua obrigatória: é `folhaObrigatoria` que segura o
     toque no quadro até a pessoa ler. Sem isso o aviso viraria enfeite. */
  assert.match(app, /confirmaEl\.addEventListener\('click', fecharFolha\)/,
    'o botão do cabeçalho parou de confirmar o aviso');
  assert.match(app, /if \(emTransicao \|\| folhaObrigatoria\) return;/,
    'o quadro voltou a aceitar toque antes de a pessoa confirmar o aviso');
});

test('a tela da reserva confirmada aponta Minha Agenda, não o check-in', () => {
  /* Texto da Adriana em 06/09, no lugar de "No dia da experiência, o
     check-in é feito nesta mesma página". Depois de confirmar o aviso, o
     cabeçalho tem de dizer para onde ir agora — o menu onde as reservas
     ficam —, não o que fazer daqui a duas semanas. As duas casas mudam
     juntas: `instrucao` é o que aparece no alto, `serve` é o que responde
     quando a tela aparece fora de um roteiro. */
  const frase = 'Lugar garantido. Veja no menu minha agenda todas as experiências nas quais você está agendado.';
  const telas = app.slice(app.indexOf('const TELAS = {'), app.indexOf('const ROTEIROS = {'));
  assert.equal(telas.split(frase).length - 1, 2,
    'a frase da tela de reserva confirmada mudou ou saiu de uma das duas casas');
  assert.ok(!telas.includes('Lugar garantido. No dia da experiência'),
    'o texto antigo do check-in voltou para a tela da reserva confirmada');
  /* O aviso dos 5 minutos é outro texto e continua sendo o da folha: é ele
     que sobe para o cabeçalho ANTES de a pessoa confirmar. */
  assert.match(app, /texto: 'Seu lugar está reservado! Mas atenção/,
    'o aviso dos cinco minutos saiu da folha da reserva');
});

test('o título de seção com destino abre inteiro, não só o "Ver ..."', () => {
  /* Pedido da Adriana em 06/09: título de seção com destino tem de clicar
     inteiro. O dedo vai no título, que é o alvo grande; o "Ver ..." da
     direita é a legenda do destino, não o botão. Vale hoje para "Avisos
     importantes" — os dois recados de véspera, que motivaram o pedido,
     viraram botão na mesma tarde. Seção sem `acao` continua texto puro:
     não há para onde ir. */
  assert.match(cards, /const t = no\('button', 'v3-secao-tit', b\.titulo\);/,
    'o título de seção deixou de virar botão');
  assert.match(cards, /t\.addEventListener\('click', \(\) => aoAgir\(b\.acao, b\)\);/,
    'o título de seção virou botão sem levar a lugar nenhum');
  assert.match(cards, /if \(b\.acao\) \{/,
    'seção sem destino voltou a virar botão');
  /* O `<h2>` continua sendo o cabeçalho da seção: o botão mora dentro
     dele, para o toque não custar a estrutura da página. */
  assert.match(cards, /const h = no\('h2'\);/,
    'o cabeçalho da seção deixou de ser um h2');
});

test('os dois recados de véspera são botões, não títulos em texto', () => {
  /* Adriana, 06/09: o amarelo de reservar subiu para cima do quadrado do
     Concierge, no lugar do título em texto que o anunciava — eram dois
     avisos para a mesma coisa. E o "O que é importante saber", que tinha
     nascido título, virou botão do lado dele. */
  assert.match(estado, /titulo: 'Aprenda como reservar suas experiências',\s+texto: 'Garanta suas escolhas agora', acao: 'tour', destaque: true/,
    'o botão de reservar mudou de texto ou perdeu o destaque');
  assert.match(estado, /titulo: 'O que é importante saber antes do Mind Summit',\s+texto: 'Tudo que o evento comunicou', acao: 'avisos'/,
    'o recado de véspera não é mais um botão para os avisos');
  /* O título em texto que o anunciava não pode voltar: era a duplicata. */
  assert.ok(!estado.includes("titulo: 'Aprenda a reservar suas experiências'"),
    'o título em texto do tour voltou junto com o botão');
  /* E o amarelo é um só na tela — ele é o destaque porque é único. */
  assert.equal((estado.match(/destaque: true/g) || []).length, 1,
    'apareceu mais de um card amarelo na home');
});

test('a descrição da tela é branca e grande o bastante para ler', () => {
  /* Era 12,5px em `--texto-mudo` — o cinza de apoio. É o único texto do
     frame que ensina alguma coisa: não é apoio, é o conteúdo. */
  const i = css.indexOf('.t-rodape p {');
  const regra = css.slice(i, css.indexOf('\n}', i));
  assert.match(regra, /color:\s*var\(--texto\)/,
    'a descrição da tela voltou ao cinza de apoio e ficou difícil de ler');
  const tam = Number((regra.match(/font-size:\s*([\d.]+)px/) || [])[1]);
  assert.ok(tam >= 15, 'a descrição encolheu para ' + tam + 'px; abaixo de 15 volta a ser miúda');
});

test('o quadro não pode passar por cima do rodapé', () => {
  /* `.fone` tem `aspect-ratio` fixa: sem teto de altura ele calcula um
     quadro mais alto que o espaço e vaza por baixo, cobrindo o rodapé.
     Ficou invisível enquanto o rodapé tinha uma linha só — a fonte maior
     trouxe a terceira linha e a sobreposição apareceu. */
  const i = css.indexOf('.fone {');
  const fone = css.slice(i, css.indexOf('\n}', i));
  assert.match(fone, /max-height:\s*100%/,
    'o quadro perdeu o teto de altura e volta a vazar para cima do rodapé');
  const j = css.indexOf('.t-palco {');
  assert.match(css.slice(j, css.indexOf('\n}', j)), /overflow:\s*hidden/,
    'o palco parou de recortar, e o que vazar dele cobre o rodapé');
});

test('a demonstração termina sem pop-up', () => {
  /* O cartão "Você mandou bem!" abria sozinho por cima do palco dois
     segundos depois da última missão — tapando justamente a tela que a
     pessoa acabou de aprender a usar, e cobrando mais um fechar. O fim
     agora é a faixa transitória dos brindes, com a frase que cada roteiro
     já trazia em `concluido`.

     O aviso ao hospedeiro não era do cartão, era só o botão dele que
     disparava: `mindagent:tour-concluido` continua saindo na conclusão, e
     quem embeda a página depende disso. */
  assert.ok(!/fim-fundo|fim-cartao/.test(html + css + app),
    'o cartão do fim voltou — o fim da demonstração é faixa transitória, não pop-up');
  assert.match(app, /feitas\.size === MISSOES\.length\) \{\n\s*parent\.postMessage\(\{ tipo: 'mindagent:tour-concluido' \}/,
    'a conclusão parou de avisar quem embeda a página');
  assert.match(app, /setTimeout\(\(\) => avisar\(r\.concluido\)/,
    'a frase de conclusão de cada roteiro sumiu do fim');
  for (const frase of ['você já sabe reservar', 'o mapa fica no Menu', 'o seu ingresso está aí']) {
    assert.ok(app.includes(frase), 'o roteiro perdeu a frase de conclusão: ' + frase);
  }
});

test('o e-mail nunca vai na URL para buscar o ingresso', () => {
  /* O app inteiro trabalha para tirar e-mail da barra de endereço
     (`limparUrl`, em config.js). Mandá-lo em query string aqui o
     devolveria ao log de borda pela porta dos fundos. */
  const i = dados.indexOf('export async function carregarIngressoDoParticipante');
  assert.ok(i > 0, 'a leitura do tipo de ingresso sumiu do data-service');
  const fn = dados.slice(i, i + 1200);
  assert.match(fn, /method: 'POST'/, 'a busca do ingresso deixou de ser POST');
  assert.match(fn, /body: JSON\.stringify\(\{ email \}\)/, 'o e-mail saiu do corpo do pedido');
  assert.ok(!/participante\?/.test(fn), 'o e-mail voltou para a URL na busca do ingresso');
});

test('a tela confere a FORMA do tipo, não uma lista de nomes', () => {
  /* Começou como lista fechada — VIP, Mind, Prime — e se calou sozinha
     quando o espelho ganhou `Camarote`: 54 pessoas sem pílula e sem erro
     nenhum na tela. Uma lista de nomes no front-end é uma promessa de
     que alguém vai lembrar de voltar aqui. A tela garante só que o
     cabeçalho não vire campo de texto livre; quem decide o que é tipo é
     a função no banco. */
  assert.match(dados, /const FORMATO_INGRESSO = /,
    'a conferência de forma sumiu do data-service');
  assert.ok(!/new Set\(\['VIP'/.test(dados),
    'a lista fechada de tipos voltou — e ela se cala sozinha no próximo tipo novo');

  const re = new RegExp((dados.match(/const FORMATO_INGRESSO = \/(.+)\/u;/) || [])[1], 'u');
  for (const bom of ['VIP', 'Mind', 'Prime', 'Camarote', 'Área VIP']) {
    assert.ok(re.test(bom), 'a forma passou a recusar um tipo plausível: ' + bom);
  }
  for (const ruim of ['', 'x', '<b>oi</b>', 'Uma frase inteira que nao cabe no cabecalho']) {
    assert.ok(!re.test(ruim), 'a forma passou a aceitar lixo no cabeçalho: ' + JSON.stringify(ruim));
  }
});

test('a origem inválida cai no fallback antes de qualquer campo nulo chegar à Home', () => {
  assert.match(dados, /evento\.dias\.length > 0/,
    'a camada de dados deixou passar evento sem dia utilizável');
  assert.match(dados, /typeof dia === 'string' && \/\^\\d\{4\}-\\d\{2\}-\\d\{2\}\$\//,
    'a camada de dados deixou passar dia nulo ou fora do contrato ISO');
  assert.match(dados, /sessão sem id, dia, início ou título/,
    'a camada de dados deixou passar sessão que derruba o desenho');
  assert.match(app, /\.filter\(\(data\) => typeof data === 'string'\)/,
    'a contagem regressiva voltou a chamar split em um valor nulo');
});

test('o bootstrap vivo usa os schemas atuais e preserva avisos e composição da Home', () => {
  assert.match(bootstrap, /from summit_2026\.events/);
  assert.match(bootstrap, /ecossistema\.palestrantes_especialistas/);
  assert.match(bootstrap, /from concierge\.avisos/);
  assert.match(bootstrap, /from concierge\.config/);
  assert.doesNotMatch(bootstrap, /from summit\./,
    'o bootstrap voltou a consultar o schema removido summit');
  assert.doesNotMatch(bootstrap, /from comum\./,
    'o bootstrap voltou a consultar o schema removido comum');
});

test('a grade viva recebe a curadoria que alimenta afinidade e recomendações', () => {
  assert.equal((temasVivos.match(/\('2026-09-/g) || []).length, 39,
    'o mapa curado deixou de cobrir as 39 sessões já classificadas');
  assert.match(temasVivos, /set topicos_aprendizado=m\.temas/);
  assert.match(temasVivos, /e\.slug='mind-summit-2026'/);
  assert.match(temasHorariosVivos, /'2026-09-17'::date[\s\S]*'Bem-estar começa na agenda'/);
  assert.match(temasHorariosVivos, /'2026-09-16'::date[\s\S]*'Falhar melhor'/);
});

test('sem tipo de ingresso, o cabeçalho é exatamente o de antes', () => {
  assert.match(html, /<span class="h-ingresso" id="perfil-ingresso" hidden>/,
    'a pílula do ingresso deixou de nascer escondida');
  /* Mesma armadilha do `☰` na demonstração: `display: inline-flex` tem
     especificidade maior que a regra `[hidden]` do navegador. */
  assert.match(css, /\.h-ingresso\[hidden\]\s*\{\s*display:\s*none/,
    'o `hidden` da pílula voltou a perder para o `display`');
  assert.match(homeJs, /etiqueta: ctx\.ingresso && c\.etiqueta \? 'Experiência ' \+ ctx\.ingresso : c\.etiqueta/,
    'a sobrancelha parou de só SUBSTITUIR a que já existe — numa tela sem '
    + 'etiqueta, acrescentar uma cria linha onde o desenho não tem nenhuma');
  assert.match(css, /\.h-ingresso \{[^}]*background: var\(--roxo\)/,
    'a pílula deixou de usar o roxo da marca e virou cor nova');
});

test('a porta do ingresso não vira uma forma de descobrir quem tem ingresso', () => {
  /* Ausente, SEM MAPA, revogado e tipo em desacordo respondem a MESMA
     coisa. É isso que impede a rota de confirmar presença na lista. */
  assert.match(migracao, /and status = 'ativo'/, 'a porta parou de filtrar ingresso inativo');
  assert.match(migracao, /and revogado_em is null/, 'a porta parou de filtrar ingresso revogado');
  assert.match(migracao, /upper\(btrim\(ticket_type\)\) <> 'SEM MAPA'/,
    'a sentinela de importação voltou a passar como se fosse tipo de ingresso');
  assert.match(migracao, /char_length\(btrim\(ticket_type\)\) between 2 and 24/,
    'o teto de tamanho sumiu, e o cabeçalho volta a poder receber texto livre');
  assert.match(migracao, /count\(distinct btrim\(ticket_type\)\) = 1/,
    'o desacordo entre linhas do mesmo e-mail voltou a ser desempatado por conta própria');
  /* E ela não é alcançável com a chave publicável do navegador. */
  for (const alvo of ['api', 'public']) {
    const re = new RegExp('revoke all on function ' + alvo
      + '\\.mindagent_participante_ingresso\\(text\\) from public');
    assert.match(migracao, re, 'a função em `' + alvo + '` voltou a ser executável por qualquer papel');
  }
  assert.ok(!/ to anon| to authenticated/.test(migracao),
    'a função do ingresso ganhou grant para anon ou authenticated');
  assert.match(funcaoHome, /error: "participante_ingresso_failed"/, 'o log de erro da rota sumiu');
  assert.ok(!/request_id: requestId[^}]*email/.test(funcaoHome),
    'a rota passou a registrar o e-mail em log');
});

test('a home mostra os seis avisos na ordem que a Adriana pediu', () => {
  /* Quem escolhe os cards da home é a ORDEM DE DISPARO — os `quantos`
     mais recentes. Os seis da home receberam, no banco, os seis horários
     mais recentes, um minuto de diferença cada. Mexer no `em` de
     qualquer aviso reordena a home sem tocar em layout nenhum. */
  assert.match(estado, /\{ tipo: 'avisos', quantos: 6 \}/,
    'a home voltou a mostrar outro número de avisos');
  /* O fim é procurado A PARTIR do início: `\n];` aparece antes, no fim de
     `CATEGORIAS_AVISO`, e o slice saía vazio — com listas vazias os dois
     `deepEqual` passavam sem comparar nada. */
  const i = estado.indexOf('const CRUS = [');
  const bloco = estado.slice(i, estado.indexOf('\n];', i));
  assert.ok(bloco.length > 2000, 'não achei a lista embutida de avisos');
  /* O espaço antes de `em:` não é enfeite: sem ele o `mensagem:` de cada
     aviso também casa, e a lista de datas vem cheia de texto. */
  const datas = [...bloco.matchAll(/ em: '([^']+)'/g)].map((m) => m[1]);
  assert.equal(datas.length, 19, 'a lista embutida deixou de ter os 19 avisos em circulação');
  /* O do estacionamento entrou em 06/09, no banco e aqui, logo depois de
     "Como chegar ao São Paulo Expo" — que já fala do estacionamento
     coberto e da passarela, e a que este responde o que faltava. */
  assert.match(estado, /id: 'estacionamento', ico: ICO\.carro, cat: 'antes_de_ir', em: '2026-09-15T16:10'/,
    'o aviso do estacionamento saiu da lista embutida ou mudou de lugar');
  assert.ok(datas.indexOf('2026-09-15T16:10') === datas.indexOf('2026-09-15T16:20') + 1,
    'o aviso do estacionamento não vem logo depois do "Como chegar ao São Paulo Expo"');
  const ordenado = [...datas].sort().reverse();
  assert.deepEqual(datas, ordenado,
    'a lista embutida saiu da ordem de disparo, e a home passa a mostrar outros seis');
  const titulos = [...bloco.matchAll(/titulo: '([^']+)'/g)].map((m) => m[1]).slice(0, 6);
  assert.deepEqual(titulos, [
    'Reserve agora as experiências que você não quer perder',
    'Venha de Rhino para o Mind Summit',
    'Importante! Trazer um documento físico de identidade: RG ou CNH',
    'Seu ingresso está no app, no menu Ingresso!',
    'Chegue cedo e siga para o Pavilhão 3',
    'Vai aos autógrafos dos Legends? Prefira levar o livro',
  ], 'os seis da home mudaram');
  /* Três toggles, e só três: a Adriana pediu (03/09). "Ingressos" saiu e o
     aviso do ingresso passou a morar na primeira categoria — que em 06/09
     ela renomeou para "Importante Saber Antes do Summit", o mesmo nome do
     botão que abre esta tela na home. */
  const cats = [...estado.matchAll(/rotulo: '([^']+)',\s+ponto: true/g)].map((m) => m[1]);
  assert.deepEqual(cats, ['Importante Saber Antes do Summit', 'Reservas e Agenda', 'Durante e Depois'],
    'a tela de avisos deixou de ter exatamente os três toggles');
  assert.ok(!/id: 'ingressos'/.test(estado), 'a categoria "ingressos" voltou como toggle');
});

test('a tela de avisos abre numa categoria, sem o chip "Todos"', () => {
  /* Adriana, 06/09: "tire todos". Os três momentos são a navegação inteira,
     e a tela abre no primeiro — o que é importante saber antes. O valor
     `todos` continua existindo como rede: sem categoria em circulação, a
     lista mostra tudo em vez de abrir vazia. */
  assert.match(avisosJs, /const botoes = presentes;/,
    'o chip "Todos" voltou para a tela de avisos');
  assert.match(avisosJs, /let filtro = presentes\.length \? presentes\[0\]\.id : 'todos';/,
    'a tela de avisos deixou de abrir na primeira categoria');
  assert.ok(!avisosJs.includes("rotulo: 'Todos'"),
    'o rótulo "Todos" voltou para os chips');
  /* O `todos` do filtro continua servindo de rede — quem o tira precisa
     resolver o que a lista mostra quando não há categoria nenhuma. */
  assert.match(avisosJs, /filtro === 'todos' \|\| a\.cat === filtro/,
    'a rede que mostra tudo sem categoria saiu junto com o chip');
});

test('aviso no ar sem horário não derruba a home e aparece como Agora', async () => {
  /* `no-ar` significa publicação imediata; `disparo_em` só é obrigatório para
     agendamento. O aviso de livros/autógrafos chegou exatamente nessa forma e
     fazia `quandoLegivel(null)` abortar todo o bootstrap da tela. */
  const modulo = await import(new URL('../home/estado.js?teste-aviso-sem-horario', import.meta.url));
  modulo.definirAvisos([{
    id: 'imediato', situacao: 'no-ar', em: null, titulo: 'Aviso imediato',
    resumo: 'Resumo', mensagem: 'Mensagem', categoria: 'antes_de_ir', icone: 'sino',
  }, {
    id: 'antigo', situacao: 'no-ar', em: '2026-09-15T17:00', titulo: 'Aviso antigo',
    resumo: 'Resumo', mensagem: 'Mensagem', categoria: 'antes_de_ir', icone: 'sino',
  }]);
  assert.equal(modulo.AVISOS.length, 2);
  assert.equal(modulo.AVISOS[0].id, 'imediato');
  assert.equal(modulo.AVISOS[0].quando, 'Agora');
});

test('nenhum filtro de categoria fica fora da tela', () => {
  /* Com os rótulos que a Adriana escreveu, a fila de chips passou a medir
     617px numa tela de 390: o último ficava INTEIRO fora do quadro, com
     0px visíveis. Rolagem horizontal só resolve para quem descobre que
     dá para arrastar. */
  const i = css.indexOf('.av-chips {');
  const regra = css.slice(i, css.indexOf('\n}', i));
  assert.match(regra, /flex-wrap:\s*wrap/,
    'os chips voltaram a ficar numa linha só, e o último sai da tela');
  assert.ok(!/overflow-x:\s*auto/.test(regra),
    'a fila de chips voltou a rolar em vez de quebrar linha');
});

test('o texto do aviso vira parágrafos, e entra escapado', () => {
  /* O aviso das gravações tem três parágrafos; num `<p>` só viravam um
     bloco corrido. E o campo é escrito por gente no painel: `<` ali é
     `<`, não abertura de tag. */
  assert.match(avisos, /function paragrafos\(txt, classe\)/,
    'a quebra de parágrafo sumiu do aviso aberto');
  assert.match(avisos, /paragrafos\(a\.mensagem, 'av-texto'\)/,
    'a mensagem voltou a entrar num parágrafo só');
  assert.match(avisos, /function escapar\(txt\)/, 'o escape do texto do aviso sumiu');
  for (const campo of ['a.titulo', 'a.resumo', 'a.quando']) {
    assert.ok(avisos.includes('escapar(' + campo + ')'),
      'o campo ' + campo + ' voltou a entrar cru em innerHTML');
  }
  assert.match(css, /\.av-texto \+ \.av-texto \{ margin-top/,
    'os parágrafos voltaram a ficar colados');
});

test('o aviso sabe levar ao Concierge, à demonstração e ao mapa', () => {
  /* `verNoApp` só conhecia roteiro da demonstração; o caminho para o chat
     (vista do app) continua existindo para qualquer aviso que o peça. Em
     03/09 a Adriana reescreveu "Não sabe como reservar?" com o botão
     "Veja como funciona a reserva", que abre a demonstração — o texto do
     card é que manda a pessoa ao Concierge. */
  assert.match(app, /if \(destino === 'chat'\) return irParaConversa\(null\)/,
    'o aviso perdeu o caminho para o Concierge');
  assert.match(estado, /verNoApp: 'reserva', botaoVerNoApp: 'Veja como funciona a reserva'/,
    'o aviso de ajuda perdeu o botão da demonstração');
  assert.match(estado, /verNoApp: 'mapa'/, 'o aviso do mapa perdeu o botão');
});

test('a notificação é grande e clara o bastante para ler', () => {
  /* Era 14/12,5px no cinza de apoio sobre fundo quase preto — o menor
     contraste da tela justamente no texto que informa. */
  const i = css.indexOf('.v3-linha.aviso .v3-corpo small {');
  const regra = css.slice(i, css.indexOf('\n}', i));
  const tam = Number((regra.match(/font-size:\s*([\d.]+)px/) || [])[1]);
  assert.ok(tam >= 15, 'o resumo do aviso na home encolheu para ' + tam + 'px');
  assert.match(regra, /color:\s*var\(--texto-suave\)/,
    'o resumo do aviso na home voltou ao cinza de apoio');
  /* O fim procurado A PARTIR do início, e o recorte conferido antes de
     valer: com as duas buscas a partir do zero, bastava `.av-ponto`
     subir no arquivo para o recorte sair vazio — e um `assert.ok(!…)`
     sobre string vazia passa sempre. Foi assim que três testes meus
     passaram hoje sem comparar nada. */
  const k = css.indexOf('.av-corpo small');
  const recorte = css.slice(k, css.indexOf('.av-ponto', k));
  assert.ok(k > 0 && recorte.includes('.av-corpo em'),
    'não achei as duas linhas cinzas da lista de avisos');
  assert.ok(!/color:\s*var\(--texto-mudo\)/.test(recorte),
    'a lista de avisos voltou ao cinza de apoio');
});

test('o aviso sabe levar a material que mora fora do app', () => {
  /* O tour do Summit é um vídeo no YouTube: não tem como virar tela
     daqui. `verNoApp` passou a aceitar as três formas — URL externa,
     `chat` e roteiro da demonstração — e a externa é a única que sai do
     app, em aba nova e sem `opener`. */
  assert.match(app, /if \(\/\^https:\\\/\\\/\/\.test\(destino\)\) return window\.open\(destino, '_blank', 'noopener'\)/,
    'o aviso perdeu o caminho para material externo');
  assert.match(estado, /verNoApp: 'https:\/\/www\.youtube\.com\/watch\?v=Lw2lqkwxzMg'/,
    'o aviso do tour perdeu o link do vídeo');
  /* A ordem importa: `https://…` tem que ser testado ANTES de cair em
     `abrirTourCompleto`, que aceita qualquer coisa e cai no roteiro de
     reserva — uma URL viraria a demonstração errada, sem erro nenhum. */
  const i = app.indexOf("if (/^https:");
  const j = app.indexOf('abrirTourCompleto(destino)');
  assert.ok(i > 0 && i < j, 'a URL externa deixou de ser testada antes do roteiro');
});

test('a pessoa é chamada pelo primeiro nome, e pelo mesmo nos dois lugares', () => {
  /* A Yazo manda o nome do cadastro, e ali cabe nome inteiro: "Ana Paula
     Rodrigues Silva, seu Mind Summit começa agora" é frase que ninguém
     escreveria. A regra mora em `config.js`, ao lado da identidade, para
     que o título da home e a saudação do chat não divirjam. */
  assert.match(config, /export function primeiroNome\(\)/,
    'a regra do primeiro nome saiu de `config.js`');
  assert.match(config, /\.trim\(\)\.split\(\/\\s\+\/\)\[0\]/,
    'o primeiro nome deixou de ser o primeiro pedaço até o espaço');
  assert.match(homeJs, /return primeiroNome\(\);/,
    'a home voltou a mostrar o nome inteiro');
  assert.match(app, /function saudacao\(\) \{\n\s*const nome = primeiroNome\(\);/,
    'a saudação do chat voltou a usar outro nome que não o da home');
});

test('a quebra do título vem do conteúdo, não de marcação', () => {
  /* O título é uma linha só desde 06/09 — a quebra antes de "começa agora"
     saiu a pedido da Adriana. O `pre-line` continua na regra porque é ele
     que mantém a quebra sendo decisão de conteúdo: se voltar, volta como
     `\n` aqui, e não como marcação. Sem ele o `\n` vira espaço e a linha
     some sem erro nenhum. */
  assert.match(estado, /titulo: 'seu Mind Summit começa agora'/,
    'o título do hero mudou ou ganhou ponto final');
  assert.ok(!estado.includes('seu Mind Summit\\ncomeça'),
    'a quebra de linha voltou para o título do hero');
  /* Início de linha: `.v3-hero.decorado .v3-titulo {` vem antes e contém
     a mesma substring — sem a âncora o slice pega a regra errada. */
  const i = css.indexOf('\n.v3-titulo {');
  assert.ok(i > 0, 'não achei a regra do título');
  assert.match(css.slice(i, css.indexOf('\n}', i)), /white-space:\s*pre-line/,
    'o título parou de honrar a quebra escrita no conteúdo');
});

test('a folha da reserva não repete a mesma frase duas vezes', () => {
  /* O `<h3>` dizia "Lugar reservado!" e o texto abre com "Seu lugar está
     reservado!" — a mesma frase duas vezes na mesma caixa. Sem título, o
     rótulo do diálogo passa a ser o texto: `aria-labelledby` apontando
     para um `<h3>` que não existe deixa o diálogo sem nome. */
  assert.match(app, /reservado: \{ titulo: null, texto: 'Seu lugar está reservado!/,
    'a folha da reserva voltou a ter título repetindo o texto');
  assert.match(app, /\(f\.titulo \? '<h3 id="folha-titulo">' \+ f\.titulo \+ '<\/h3>' : ''\)/,
    'o título da folha voltou a ser obrigatório');
  assert.match(app, /folhaEl\.setAttribute\('aria-label', f\.texto \|\| 'Aviso'\)/,
    'a folha sem título ficou sem rótulo acessível');
});

test('a abertura do Concierge não promete pergunta que não vem', () => {
  /* A Adriana mandou o welcome em dois parágrafos. O segundo já existia,
     palavra por palavra, em `FLUXOS.jornada` — é ele que anuncia as
     perguntas, logo antes do "Começar →".

     Repetido na saudação, viraria promessa quebrada: duas das entradas
     do chat (digitar na home, `chat:` de um card) não abrem pergunta
     nenhuma. Uma ocorrência, e só dentro do fluxo. */
  const anuncio = 'São algumas perguntas rápidas sobre o que você quer levar destes dois dias.';
  assert.equal(app.split(anuncio).length - 1, 1,
    'o anúncio das perguntas aparece mais de uma vez — quem só abriu o chat '
    + 'para perguntar uma coisa passa a receber a promessa de um questionário');
  const j = app.indexOf('  jornada(direto) {');
  assert.ok(j > 0 && app.indexOf(anuncio) > j && app.indexOf(anuncio) < j + 400,
    'o anúncio das perguntas saiu de dentro de `FLUXOS.jornada`');

  assert.match(app, /Sou o agente do Mind e serei seu concierge no Mind Summit\./,
    'a abertura do Concierge mudou');
  assert.match(app, /bolha\(saudacao\(\) \+ 'Sou o agente do Mind/,
    'a abertura deixou de vir depois da saudação com o primeiro nome');
});

test('depois de se apresentar, o Concierge pergunta — mas não por cima de ninguém', () => {
  /* A conversa começava num vazio para quem abria o Concierge sem pedir
     nada: apresentação e mais nada, esperando que a pessoa soubesse o que
     pedir. Agora a jornada entra sozinha, e DIRETA — sem o "Começar →",
     que é passo a mais entre a apresentação e a primeira pergunta.

     Mas só para quem chega SEM ASSUNTO. Quem tocou num card tem o fluxo
     do card; quem digitou uma pergunta na home tem a resposta dela.
     Perguntar por cima disso é falar em cima da pessoa. */
  assert.match(app, /if \(!opcoes \|\| !opcoes\.comAssunto\) setTimeout\(\(\) => FLUXOS\.jornada\(true\)/,
    'a pergunta inicial sumiu, ou deixou de depender de haver assunto');
  assert.match(app, /abrirVista\('chat', \{ comAssunto: Boolean\(intencao\) \}\)/,
    'a intenção de card parou de contar como assunto — o card vira pergunta em cima do fluxo');
  assert.match(app, /abrirConversa\(Boolean\(v\)\);/,
    'a pergunta digitada na home parou de contar como assunto');
  assert.match(app, /jornada\(direto\) \{/, 'a jornada perdeu o modo direto');
  assert.match(app, /if \(direto\) return setTimeout\(\(\) => perguntaDaJornada\(0\)/,
    'o modo direto parou de ir à primeira pergunta');
});

test('o andaime de momento não manda em produção', () => {
  /* O seletor das quatro telas só é DESENHADO em localhost ou com
     `?dev=1` — mas a escolha ia para o `sessionStorage` e vencia o
     servidor em qualquer carga seguinte daquela aba, produção inclusive.

     Quem tocasse nele uma vez ficava presa numa tela que o painel não
     escolheu, e sem saída: o seletor nem aparece em produção para trocar
     de volta. Só a tela "antes" tem contagem regressiva e nome no título,
     então o sintoma era os dois sumirem juntos. */
  assert.match(estado, /export function seletorDisponivel\(\)/,
    'a regra de onde o andaime vale saiu de `estado.js`');
  const i = estado.indexOf('export function momentoAtual()');
  const fn = estado.slice(i, estado.indexOf('\n}', i));
  assert.ok(i > 0 && fn.includes('if (seletorDisponivel())'),
    'o momento guardado voltou a valer onde o seletor nem aparece');
  assert.ok(fn.indexOf('seletorDisponivel()') < fn.indexOf('sessionStorage'),
    'o guardado é lido antes de conferir se o andaime vale');
  assert.match(estado, /return momentoServidor \|\| 'antes';/,
    'a tela deixou de cair no que o painel manda');

  /* Uma regra só: duas cópias divergem, e divergir aqui é tela presa. */
  assert.match(homeJs, /const mostrarSeletor = seletorDisponivel;/,
    'o `home.js` voltou a ter a própria cópia da regra');
});

test('o campo do Concierge é o amarelo da marca, e nada claro vai em cima dele', () => {
  /* O campo é a única porta para o Concierge na home, e no escuro sobre
     escuro passava por moldura. Em creme, tudo o que vai em cima precisa
     ser escuro — e o risco aqui é silencioso: um placeholder claro que
     sobra de um tema anterior não quebra nada, só apaga o convite.
     Medido: texto do placeholder 4,97:1 e botão 16,69:1 sobre o creme. */
  assert.match(css, /\.doca input \{[^}]*background: var\(--amarelo\)/s,
    'o campo do Concierge perdeu o amarelo da marca');
  assert.match(css, /\.doca input \{[^}]*color: var\(--bg\);/s,
    'o texto digitado deixou de ser escuro — some dentro do próprio campo');
  assert.match(css, /\.doca input::placeholder \{ color: color-mix\(in srgb, var\(--bg\)/,
    'o placeholder voltou a ser claro sobre creme: o convite fica ilegível');
  assert.doesNotMatch(css, /\.doca input::placeholder \{ color: var\(--texto-mudo\)/,
    'o placeholder voltou ao cinza do tema escuro');

  /* O verde de interface sobre o creme dá 1,34:1: o botão sumia dentro do
     campo. Escuro sobre creme é o que o faz continuar sendo um botão. */
  assert.match(css, /\.doca \.enviar \{[^}]*background: var\(--bg\); color: var\(--amarelo\);/s,
    'o botão de enviar voltou ao verde, que desaparece sobre o creme');
});
