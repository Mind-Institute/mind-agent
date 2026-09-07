import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';

const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
const styles = readFileSync(new URL('../styles.css', import.meta.url), 'utf8');
const migration = readFileSync(
  new URL('../supabase/migrations/20260903183000_bootstrap_acesso_fotos_palestrantes.sql', import.meta.url),
  'utf8',
);

/* O QUESTIONÁRIO DA JORNADA NÃO EXISTE MAIS (Adriana, 06/09): ela quer
   continuar recomendando sem a pessoa clicando. Os dois testes que moravam
   aqui cobriam o seletor de palestrantes e as chips do questionário — as
   duas telas que saíram. O que ficou é a garantia de que não voltem por
   descuido, e de que o que elas entregavam de útil continua saindo. */
test('o questionário da jornada não voltou', () => {
  for (const morto of ['PERGUNTAS_JORNADA', 'perguntaDaJornada', 'fecharJornada',
                       'seletorPalestrantesDaJornada', 'escolhasDaJornada', 'SESSOES_POR_DIA']) {
    assert.ok(!app.includes(morto), 'o questionário da jornada voltou: ' + morto);
  }
  /* Nem a moldura dele: chips de escolha única, "Continuar", "Pular". */
  assert.ok(!app.includes("tipo: 'palestrantes'"), 'o seletor de palestrantes voltou');
  assert.ok(!styles.includes('.busca-palestrante'), 'sobrou o CSS do seletor de palestrantes');
});

test('a abertura pergunta em texto e o sinal de temas continua saindo', () => {
  /* A pergunta é conteúdo da Adriana e mora numa constante só. */
  assert.match(app, /const PERGUNTA_DE_ABERTURA =/,
    'a pergunta de abertura deixou de morar numa casa só');
  assert.match(app, /O que te trouxe ao Mind Summit\? O que você gostaria de aprender aqui\?/,
    'a pergunta de abertura mudou');
  /* O que o ingresso libera é dito antes de a pessoa contar o que quer. */
  assert.match(app, /function abrirComPergunta\(\)[\s\S]{0,400}textoDoIngressoNaRecomendacao\(\)/,
    'a abertura parou de avisar o que o ingresso libera');
  /* Era o botão que mandava `temas` ao Core; agora é o texto da pessoa.
     Sem isto, tirar o questionário levaria junto a inteligência sobre ela. */
  assert.match(app, /enviarSinalJornada\('temas', usar\.map\(\(t\) => t\.rotulo\)\)/,
    'o sinal de temas parou de sair do que a pessoa escreveu');
  /* E a resposta em texto passa pela IA ANTES de qualquer card. */
  assert.match(app, /return responder\(limpo\)\.then\(\(\) => cardsDoRelato\(limpo\)\)/,
    'os cards voltaram a aparecer sem a IA ler o que a pessoa escreveu');
  /* Nada de chips quando o texto não casa tema: a resposta da IA basta. */
  assert.ok(!app.includes('marque o tema que chega mais perto'),
    'o pedido de clique voltou para quando o texto não casa tema');
  assert.match(styles, /\.ins textarea\s*\{[^}]*font-size:\s*16px/s);
});

test('bootstrap preserva o campo público trilhas usando ingresso canônico', () => {
  assert.match(migration, /'trilhas',coalesce\(s\.ingressos,'\{\}'::text\[\]\)/);
  assert.doesNotMatch(migration, /'trilhas',coalesce\(s\.trilhas/);
  assert.match(migration, /Bootstrap possui % divergências de acesso/);
});

test('fotos pertencem ao palestrante canônico e todos os assets semeados existem', () => {
  assert.match(migration, /alter table ecossistema\.palestrantes_especialistas/);
  assert.match(migration, /add column if not exists foto_asset text/);
  assert.match(migration, /'foto',sp\.foto_asset/);
  assert.match(migration, /'destaque',sp\.destaque/);

  const caminhos = [...migration.matchAll(/'palestrantes\/([a-z0-9-]+\.webp)'/g)]
    .map((match) => match[1]);
  assert.equal(caminhos.length, 39);
  assert.equal(new Set(caminhos).size, 39);
  caminhos.forEach((arquivo) => {
    assert.ok(
      existsSync(new URL('../assets/palestrantes/' + arquivo, import.meta.url)),
      'asset ausente: ' + arquivo,
    );
  });
});
