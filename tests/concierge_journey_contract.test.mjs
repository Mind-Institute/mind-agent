import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const app = readFileSync(new URL('../app.js', import.meta.url), 'utf8');
const service = readFileSync(new URL('../chat-service.js', import.meta.url), 'utf8');
const migration = readFileSync(
  new URL('../supabase/migrations/20260903120000_concierge_jornada_ingresso_contextual.sql', import.meta.url),
  'utf8',
);

test('recomendação não finge salvar sessão no Summit', () => {
  assert.doesNotMatch(app, /Salvar no meu Summit|data-acao="salvar"|Salva ✓/);
  assert.match(app, /Onde reservar no app/);
});

test('cada resposta estruturada da jornada vai ao Core sem LLM', () => {
  assert.match(app, /enviarSinalJornada/);
  assert.match(service, /journey_signal: \{ field, values: lista \}/);
  assert.match(service, /client_action_id: clientActionId/);
  assert.match(migration, /mind_kit_programacao_filtrada/);
});

test('recomendações locais e do Agent respeitam o ingresso conhecido', () => {
  assert.match(app, /sessaoAcessivelPeloIngresso/);
  assert.match(app, /Vou considerar os acessos do seu ingresso/);
  assert.match(migration, /coalesce\(s\.ingressos,'\{\}'::text\[\]\) && v_categorias/);
  assert.match(migration, /recomendacoes_filtradas/);
  assert.match(migration, /categoria_sem_regra_de_acesso/);
});

test('ICP inferido do cargo é hipótese explícita e não regra de produto', () => {
  assert.match(migration, /'confidence',0\.55,'source','role_inference'/);
  assert.match(migration, /Use cargo, empresa e ICP apenas para personalizar linguagem/);
  assert.match(migration, /nunca para presumir dor, interesse ou compra/);
});
