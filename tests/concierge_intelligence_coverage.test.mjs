/*
 * Cobertura source -> Intelligence do Mind Summit 2026.
 *
 * Este teste e offline e roda em `npm run test:edge`. Ele impede que a secao
 * canonica de livros/autografos seja alterada ou removida sem que a migration
 * que publica a regra e o aviso acompanhe a mudanca. O contrato SQL irmao
 * verifica o outro lado, a instalacao viva no Supabase.
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const canon = readFileSync(
  new URL('../SUMMIT_2026_CANON_AGENTES.md', import.meta.url),
  'utf8',
);
const migration = readFileSync(
  new URL(
    '../supabase/migrations/20260903100000_concierge_intelligence_unificada.sql',
    import.meta.url,
  ),
  'utf8',
);

const normalizar = (texto) => texto
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .toLowerCase()
  .replace(/\s+/g, ' ');

const secao = canon.match(/# 9\. Livros e aut[oó]grafos([\s\S]*?)(?=\n---|\n# 10\.)/)?.[1];

test('a regra operacional de livros continua completa no canon e na Intelligence', () => {
  assert.ok(secao, 'a secao canonica de livros e autografos sumiu');

  const fonte = normalizar(secao);
  const destino = normalizar(migration);
  const fatos = [
    'participantes prime levem seus proprios exemplares',
    'disponibilidade nao e garantida',
    'livros importados podem existir em quantidades extremamente limitadas',
    'jan-emmanuel de neve, christina maslach e sonja lyubomirsky',
    'nao prometer estoque, titulo, quantidade, idioma',
    'mesmo com esforco de abastecimento, um titulo pode acabar',
  ];

  for (const fato of fatos) {
    assert.ok(fonte.includes(fato), `o canon perdeu o fato: ${fato}`);
    assert.ok(destino.includes(fato), `a Intelligence nao publica o fato: ${fato}`);
  }

  assert.match(migration, /'livros-autografos'/);
  assert.match(migration, /'livros_autografos'/);
});

test('a busca e a leitura cobrem todas as casas aprovadas do Summit', () => {
  for (const casa of [
    'summit_2026.knowledge_documents',
    'summit_2026.event_rules',
    'concierge.avisos',
    'summit_2026.sessions',
    'summit_2026.locations',
    'summit_2026.exhibitors',
  ]) {
    assert.ok(migration.includes(casa), `a busca unificada perdeu ${casa}`);
  }

  for (const tipo of [
    'palestrante',
    'sessao',
    'conhecimento',
    'regra_evento',
    'aviso',
    'local',
    'expositor',
  ]) {
    assert.ok(migration.includes(`'${tipo}'`), `a interface perdeu o tipo ${tipo}`);
  }
});

test('o kit permanece enxuto e resolve o evento explicitamente', () => {
  assert.match(migration, /p_necessidade->>'event_slug'/);
  assert.match(migration, /r\.prioridade <= 2/);
  assert.match(migration, /'regras_criticas'/);
  assert.match(migration, /'avisos_importantes'/);
});
