import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const migration = readFileSync(new URL(
  '../supabase/migrations/20260903133000_recovery_inbox_e_dispatcher_desligado.sql', import.meta.url,
), 'utf8');
const worker = readFileSync(new URL('../supabase/functions/mindagent-recovery/index.ts', import.meta.url), 'utf8');

test('compra transacional vence qualquer leitura do modelo', () => {
  assert.match(migration, /v_conversoes_agente v[\s\S]*v\.paid/);
  assert.match(migration, /status_de_pagamento='Pago'/);
  assert.match(migration, /when n\.purchase_status='purchased' then 'excluded_purchased'/);
  assert.match(migration, /purchased_actionable|v_recovery_inbox_actionable|excluded_purchased/);
});

test('janela de WhatsApp é limitada a 24h e ao horário de 09:30–20:30', () => {
  assert.match(migration, /last_lead_at\+interval '24 hours'/);
  assert.match(migration, /time '09:30'/);
  assert.match(migration, /time '20:30'/);
  assert.match(migration, /when v_now>=n\.window_expiry then 'needs_hsm'/);
});

test('fila nasce desligada, em rascunho e sem cron', () => {
  assert.match(migration, /'enabled', false/);
  assert.match(migration, /'dry_run', true/);
  assert.match(migration, /status text not null default 'draft'/);
  assert.match(migration, /if not coalesce\(v_enabled,false\) then return/);
  assert.doesNotMatch(migration, /cron\.schedule|net\.http_post/);
});

test('worker só prepara rascunhos e exige credencial administrativa', () => {
  assert.match(worker, /constantTimeEqual/);
  assert.match(worker, /mind_recovery_claim_drafts/);
  assert.match(worker, /mind_recovery_save_draft/);
  assert.match(worker, /mind_recovery_prepare_queue/);
  assert.doesNotMatch(worker, /api\.treble|sendMessage|provider_message_id/);
});

test('HSM é agrupado por objeção sem inventar oferta ou link', () => {
  assert.match(migration, /v_recovery_hsm_groups/);
  assert.match(worker, /Não invente preço, desconto, lote, prazo, acesso, palestrante, checkout ou fato/);
  assert.match(worker, /não inclua dados pessoais nem URL/);
});
