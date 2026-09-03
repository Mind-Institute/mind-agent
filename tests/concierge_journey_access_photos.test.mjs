import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';

const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
const styles = readFileSync(new URL('../styles.css', import.meta.url), 'utf8');
const migration = readFileSync(
  new URL('../supabase/migrations/20260903183000_bootstrap_acesso_fotos_palestrantes.sql', import.meta.url),
  'utf8',
);

test('jornada não pergunta dias e pesquisa toda a base canônica de palestrantes', () => {
  assert.doesNotMatch(app, /Em quais dias você vem\?/);
  assert.match(app, /tipo:\s*'palestrantes'/);
  assert.match(app, /function seletorPalestrantesDaJornada/);
  assert.match(app, /normalizarBusca/);
  assert.match(app, /DADOS\.pessoas/);
  assert.match(app, /palestrantes_imperdiveis/);
  assert.doesNotMatch(app, /DADOS\.pessoas\.slice\(0,\s*8\)/);
});

test('seletor guarda nomes canônicos, respeita máximo três e evita zoom no iOS', () => {
  assert.match(app, /q\.campo\]\s*=\s*selecionadas\.slice\(\)/);
  assert.match(app, /enviarSinalJornada\('palestrantes_imperdiveis',\s*selecionadas\.slice\(\)\)/);
  assert.match(app, /selecionadas\.length\s*>=\s*\(q\.max\s*\|\|\s*3\)/);
  assert.match(styles, /\.busca-palestrante\s*\{[^}]*font-size:\s*16px/s);
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
