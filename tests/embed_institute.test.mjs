/* ============================================================
   O EMBED DO INSTITUTE — a moldura precisa ser a da agente
   ============================================================
   O banco já mandava a conversa para a MIA desde o primeiro turno:
   `agentes.canal_competencia` tem `entradas_diretas =
   {institute_learnworlds}` na rota `mia_summit_2026`. A TELA é que ainda
   era a do Summit — marca do evento, cards de plano pós-Summit, a doca
   dizendo "Pergunte qualquer coisa ao Concierge" — e a primeira bolha do
   chat, que é escrita no frontend e não vem da agente, se apresentava
   como concierge de um evento encerrado, seguida das seis intenções que
   montam agenda e escolhem palestras.

   Nada disso dá erro: o app funciona, a MIA responde a partir da segunda
   bolha, e um diff de uma linha em `iniciarChat` desfaz tudo em silêncio.
   Por isso as decisões ficam travadas aqui, no texto vivo dos arquivos.

   A política de enquadramento do Worker nasceu na mesma investigação e
   mora em `enquadramento_embed.test.mjs`: ela é mudança de segurança,
   tem gate próprio e não subiu junto com esta.
*/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lerFonte, semComentarios } from './helpers/ler-fonte.mjs';

const config = lerFonte(new URL('../config.js', import.meta.url));
const app = lerFonte(new URL('../app.js', import.meta.url));
const pagina = lerFonte(new URL('../index.html', import.meta.url));

const appSemComentarios = semComentarios(app);

/* ============================================================
   A PORTA TEM CARA, E SÓ CARA
   ============================================================ */

test('existe uma porta para o embed do Institute', () => {
  assert.match(config, /institute_learnworlds:\s*\{/,
    'a porta do LearnWorlds saiu de `PORTAS`: o embed volta a abrir a central '
    + 'do participante do Summit');
});

test('a porta traz nome, papel, abertura e o que a agente faz', () => {
  const porta = config.slice(config.indexOf('institute_learnworlds: {'),
                             config.indexOf('export function faceDaPorta'));
  for (const campo of ['agente', 'papel', 'placeholder', 'abertura', 'sugestoes']) {
    assert.ok(new RegExp('\\b' + campo + ':').test(porta),
      `a porta perdeu \`${campo}\`; sem ele a tela volta a ser a do Concierge nesse ponto`);
  }
  assert.match(porta, /MIA/,
    'o cabeçalho do chat deixou de nomear a agente — quem abre o embed lê "Mind Agent"');
});

test('a porta não escolhe agente, rota nem identidade — isso é do banco', () => {
  const porta = config.slice(config.indexOf('const PORTAS = {'),
                             config.indexOf('export function faceDaPorta'));
  for (const proibido of ['rota', 'next_route', 'agente_id', 'email', 'token']) {
    assert.ok(!new RegExp('\\b' + proibido + '\\s*:').test(semComentarios(porta)),
      `a tabela de apresentação começou a decidir \`${proibido}\`. Quem escolhe `
      + 'competência é `agentes.canal_competencia` pelas entradas diretas; esta '
      + 'tabela é moldura, e moldura que decide rota vira um segundo roteador');
  }
});

test('a moldura é desta carga da página, não da aba', () => {
  assert.match(semComentarios(config),
    /export function faceDaPorta\(\)\s*\{\s*return PORTA_DESTA_CARGA;\s*\}/,
    'faceDaPorta() voltou a ler a origem guardada na aba. Abrindo o app do Summit '
    + 'na mesma aba em que o embed já rodou, a pessoa recebia o chat da MIA sem home '
    + 'e sem volta — a competência gruda na aba de propósito, a tela não');
  assert.match(semComentarios(config), /PORTA_DESTA_CARGA = Object\.prototype\.hasOwnProperty\.call\(PORTAS, bruto\)/,
    '`?origem_codigo=constructor` numa URL hostil volta a devolver o construtor de '
    + 'Object, que passaria por porta válida');
});

/* ============================================================
   O QUE O EMBED NÃO MOSTRA
   ============================================================ */

test('o chat da porta abre com a apresentação dela, nunca com a jornada', () => {
  const inicio = appSemComentarios.slice(appSemComentarios.indexOf('function iniciarChat('));
  const corpo = inicio.slice(0, inicio.indexOf('\n}\n'));
  const porta = corpo.indexOf('if (PORTA) {');
  const jornada = corpo.indexOf('FLUXOS.jornada');
  assert.ok(porta >= 0, 'iniciarChat não olha mais a porta: o embed volta a ser cumprimentado '
    + 'como participante do Summit');
  assert.ok(jornada > porta,
    'a jornada do Concierge passou a rodar antes (ou no lugar) do desvio da porta. '
    + 'Ela monta agenda e escolhe palestras de um evento que já aconteceu');
  assert.match(corpo.slice(porta), /PORTA\.abertura[\s\S]*?return;/,
    'o desvio da porta deixou de sair antes da abertura do Concierge');
});

test('o embed não mostra a abertura da marca', () => {
  assert.match(appSemComentarios, /if \(SO_CHAT\) \{ splash\.remove\(\); return; \}/,
    'o splash voltou ao embed. A fala dele ainda diz "o agente do Mind… sobre o evento", '
    + 'que é o Concierge, e símbolo parado dentro de um iframe é lido como aula travada');
  const digitar = appSemComentarios.indexOf('function digitar()');
  assert.ok(appSemComentarios.indexOf('if (SO_CHAT)', digitar) <
            appSemComentarios.indexOf('jaViuAbertura', digitar),
    'a guarda do embed ficou depois da guarda de sessão; quem abre o curso pela '
    + 'primeira vez ainda espera a abertura');
});

test('o embed não oferece o "‹", que levaria a uma central que não é a dele', () => {
  assert.match(appSemComentarios, /if \(SO_CHAT\) document\.getElementById\('chat-voltar'\)\.hidden = true/,
    'o voltar reapareceu no embed: ele abre a central do Summit, que não é o curso '
    + 'da pessoa');
});

test('o embed não sobe a central do participante por trás', () => {
  const partida = appSemComentarios.slice(appSemComentarios.indexOf('\nif (SO_CHAT) {\n'));
  const bloco = partida.slice(0, partida.indexOf('} else {'));
  assert.match(bloco, /vestirDaPorta\(\);/);
  assert.match(bloco, /abrirVista\('chat'\);/);
  assert.ok(!bloco.includes('montarHomeV3'),
    'a home do Summit voltou a ser montada no embed: avisos e momento de um evento '
    + 'encerrado, carregados para uma tela que ninguém vê');
});

test('o embed não vai buscar o que só a home usaria', () => {
  const inicio = appSemComentarios.indexOf('async function carregarDados()');
  const corpo = appSemComentarios.slice(inicio, appSemComentarios.indexOf('\n}', inicio));
  const grade = corpo.indexOf('carregarDadosSummit()');
  const corte = corpo.indexOf('if (SO_CHAT) return;');
  assert.ok(corte > grade,
    'o corte do embed sumiu de carregarDados(), ou ficou antes da grade. '
    + 'Avisos e momento só alimentam cards da central do participante: no '
    + 'embed seria uma ida ao servidor por carga, sem tela');
  for (const daHome of ['carregarHomeDoEvento']) {
    assert.ok(corpo.indexOf(daHome) > corte,
      `\`${daHome}\` voltou a rodar antes do corte, e o embed volta a chamá-lo`);
  }
});

test('o convite do Concierge aos palestrantes não dispara pela porta', () => {
  const inicio = appSemComentarios.indexOf('function oferecerPalestrantes()');
  const corpo = appSemComentarios.slice(inicio, appSemComentarios.indexOf('\n}', inicio));
  assert.match(corpo, /if \(PORTA\) return;/,
    'o convite voltou a valer no embed. A MIA cita palestrante em quase toda resposta '
    + '— é o desenho dela —, então ele dispararia sempre e levaria para a grade');
});

test('a página tem os ganchos que a porta escreve', () => {
  for (const id of ['chat-agente', 'chat-papel', 'chat-voltar']) {
    assert.ok(pagina.includes('id="' + id + '"'),
      `o id \`${id}\` sumiu do index.html; vestirDaPorta() quebra no embed`);
  }
});

/* ============================================================
   A PELE — a identidade da MIA, e só dentro dela
   ============================================================
   O embed vestia a casca do app do Summit: fundo quase preto, verde de
   interface, resposta em balão escuro. A MIA é produto do Institute e
   se apresenta em roxo, como "MIA — Mind Intelligence Agent". O risco
   desta mudança não é ela não funcionar: é vazar para o app do Summit,
   que divide a mesma folha de estilo e o mesmo `app.js`.
*/

const estilos = lerFonte(new URL('../styles.css', import.meta.url));

test('a porta diz qual pele veste, com rótulo e símbolo próprios', () => {
  const porta = config.slice(config.indexOf('institute_learnworlds: {'),
                             config.indexOf('let PORTA_DESTA_CARGA'));
  assert.match(porta, /pele: 'mia'/, 'a porta perdeu a pele: o embed volta ao escuro do Summit');
  assert.match(porta, /rotulo: 'MIA'/,
    'sem rótulo a fala dela deixa de ser assinada — e ela não responde em balão, '
    + 'então a resposta ficaria sem dono ao rolar');
  assert.match(porta, /simbolo-mind-branco\.png/,
    'o símbolo voltou a ser o verde, que sobre o roxo é a cor do app do Summit');
});

test('a pele é posta no html, não no body', () => {
  assert.match(appSemComentarios, /document\.documentElement\.dataset\.pele = PORTA\.pele/,
    'a pele saiu do `html`. É ele que pinta o que sobra fora da caixa do app e a '
    + 'área sob o teclado: no `body`, a conversa fica clara dentro de moldura escura');
});

test('toda a pele é escopada — nada dela alcança o app do Summit', () => {
  const inicio = estilos.indexOf('A PELE DA MIA');
  assert.ok(inicio > 0, 'o bloco da pele sumiu da folha de estilo');
  const bloco = semComentarios(estilos.slice(inicio));
  const seletores = bloco.split('\n')
    .filter((l) => l.trim().endsWith('{') && !l.trim().startsWith('@'))
    .map((l) => l.trim());
  assert.ok(seletores.length >= 10, 'o bloco da pele encolheu demais para ser o bloco da pele');
  for (const s of seletores) {
    assert.ok(s.startsWith('html[data-pele='),
      `\`${s}\` não está escopado na pele e vale para o app do Summit também`);
  }
});

test('o coração verde do Concierge não vai para a pele roxa', () => {
  const inicio = appSemComentarios.indexOf('function saudacao()');
  const corpo = appSemComentarios.slice(inicio, appSemComentarios.indexOf('\n}', inicio));
  assert.match(corpo, /PORTA && PORTA\.pele \? '! ' : '! 💚 '/,
    'a saudação voltou a mandar o 💚 sempre. Na tela roxa ele é a única coisa verde, '
    + 'e verde ali é a cor do app do Summit — o produto de onde ela se distingue');
});

test('o rótulo da fala só existe na porta, e só na fala dela', () => {
  const inicio = appSemComentarios.indexOf('function bolha(');
  const corpo = appSemComentarios.slice(inicio, appSemComentarios.indexOf('\n}', inicio));
  assert.match(corpo, /quem === 'mind' && PORTA && PORTA\.rotulo/,
    'o rótulo passou a ser escrito sem olhar a porta (ou foi parar na bolha de quem '
    + 'pergunta): no app do Summit nenhuma bolha deve ganhar nome');
});
