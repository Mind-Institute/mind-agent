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

test('os três atalhos levam a destinos que existem', () => {
  /* Um atalho é uma promessa: "toque e você chega em Meu ingresso". Se o
     destino não existir, `acaoDaHome` cai no `irParaConversa(null)` do
     fim e a pessoa vai parar no chat — sem erro nenhum na tela, que é o
     que torna isto invisível em revisão. */
  const bloco = estado.slice(estado.indexOf("tipo: 'atalhos'"), estado.indexOf("tipo: 'secao', titulo: 'Avisos"));
  const destinos = [...bloco.matchAll(/acao: '([^']+)'/g)].map((m) => m[1]);
  assert.deepEqual(destinos, ['tour:qrcode', 'tour:minha-agenda', 'tour'],
    'os destinos dos atalhos mudaram');

  /* O tile do mapa saiu em 02/09 para os três caberem numa linha e sobrar
     altura para mais um aviso. O ROTEIRO `mapa` continua existindo e
     continua alcançável — de dentro do tour, pelo Menu, e por
     `abrirTourCompleto('mapa')`. O que saiu foi o atalho, não o caminho. */
  assert.match(app, /if \(acao\.startsWith\('roteiro:'\)\) return abrirTourCompleto/,
    'a ação de roteiro guiado deixou de ser tratada');
  const roteiroMapa = app.slice(app.indexOf('  mapa: {'), app.indexOf('  ingresso: {'));
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

test('três atalhos cabem numa linha, e sem descrição', () => {
  /* Em 360px cada tile fica com ~99px. A descrição ali vira palavra
     picada em quatro linhas; o título sozinho já diz para onde vai. */
  assert.match(cards, /itens\.length === 3 \? ' trio' : ''/,
    'a grade parou de reconhecer o trio e volta a duas colunas');
  assert.match(cards, /repeat\(' \+ Math\.min\(itens\.length, 3\)/,
    'o número de colunas voltou a ser fixo no CSS em vez de vir da quantidade');
  assert.match(css, /\.v3-atalhos\.trio \.v3-atalho\s*\{[^}]*text-align:\s*center/,
    'o tile do trio perdeu a centralização');
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
  for (const c of ['antes_de_ir', 'no_evento', 'reservas', 'ingressos']) {
    assert.ok(estado.includes("'" + c + "'"), 'a categoria ' + c + ' sumiu de estado.js');
  }
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

test('o título da demonstração é nome de tela, não instrução', () => {
  assert.match(app, /nome: 'Lugar reservado'/,
    'o roteiro de reserva perdeu o nome curto e o título volta a ser a missão inteira');
  assert.match(app, /missaoTexto\.textContent = ROTEIROS\[roteiroAtual\]\.nome/,
    'o cabeçalho voltou a escrever a missão com contador no lugar do nome');
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

test('a home mostra os cinco avisos que a Adriana condensou', () => {
  /* Quem escolhe os cards da home é a ORDEM DE DISPARO — os `quantos`
     mais recentes. Os cinco textos curtos foram escritos para o card, e
     é por isso que eles são os mais recentes da lista. Mexer no `em` de
     qualquer aviso reordena a home sem tocar em layout nenhum. */
  assert.match(estado, /\{ tipo: 'avisos', quantos: 5 \}/,
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
  assert.equal(datas.length, 17, 'a lista embutida deixou de ter 17 avisos');
  const ordenado = [...datas].sort().reverse();
  assert.deepEqual(datas, ordenado,
    'a lista embutida saiu da ordem de disparo, e a home passa a mostrar outros cinco');
  const titulos = [...bloco.matchAll(/titulo: '([^']+)'/g)].map((m) => m[1]).slice(0, 5);
  assert.deepEqual(titulos, [
    'Reserve agora as experiências que você não quer perder',
    'Leve um documento físico com foto',
    'Chegue cedo e siga para o Pavilhão 3',
    'Use o benefício da Rhino para chegar ao Summit',
    'Veja como o Summit funciona antes de chegar',
  ], 'os cinco da home mudaram');
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

test('o aviso sabe levar ao Concierge, não só à demonstração', () => {
  /* `verNoApp` só conhecia roteiro da demonstração; "Precisa de ajuda
     para reservar?" precisa abrir o chat, que é vista do app. */
  assert.match(app, /if \(destino === 'chat'\) return irParaConversa\(null\)/,
    'o aviso perdeu o caminho para o Concierge');
  assert.match(estado, /verNoApp: 'chat', botaoVerNoApp: 'Falar com o Concierge'/,
    'o aviso de ajuda perdeu o botão do Concierge');
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
  assert.ok(!/color:\s*var\(--texto-mudo\)/.test(
    css.slice(css.indexOf('.av-corpo small'), css.indexOf('.av-ponto'))),
    'a lista de avisos voltou ao cinza de apoio');
});
