import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { checkoutCurto } from '../supabase/functions/_shared/checkout-attribution.ts';

const migration = readFileSync(new URL('../supabase/migrations/20260903143000_checkout_redirect_e_abandono.sql', import.meta.url), 'utf8');
const edge = readFileSync(new URL('../supabase/functions/mindagent-checkout/index.ts', import.meta.url), 'utf8');
const app = readFileSync(new URL('../supabase/functions/mindagent-chat/index.ts', import.meta.url), 'utf8');
const whatsapp = readFileSync(new URL('../supabase/functions/treble-inbound-agent/index.ts', import.meta.url), 'utf8');
const worker = readFileSync(new URL('../cloudflare/worker.ts', import.meta.url), 'utf8');
const wrangler = readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8');

test('link curto aceita apenas HTTPS e UUID opaco', () => {
  const id = 'aaaaaaaa-aaaa-5aaa-8aaa-aaaaaaaaaaaa';
  assert.equal(checkoutCurto(id, 'https://go.mindsummit.com.br/c'), `https://go.mindsummit.com.br/c/${id}`);
  assert.equal(checkoutCurto('nome-email-telefone', 'https://go.mindsummit.com.br/c'), null);
  assert.equal(checkoutCurto(id, 'http://go.mindsummit.com.br/c'), null);
});

test('App e WhatsApp entregam o redirecionador com fallback funcional', () => {
  for (const runtime of [app, whatsapp]) {
    assert.match(runtime, /CHECKOUT_REDIRECT_BASE/);
    assert.match(runtime, /functions\/v1\/mindagent-checkout/);
    assert.match(runtime, /checkoutCurto/);
  }
});

test('redirecionador registra clique antes do 302 e reconstrói UTMs', () => {
  assert.match(edge, /mind_checkout_click_registrar/);
  assert.ok(edge.indexOf('mind_checkout_click_registrar') < edge.indexOf('status: 302'));
  assert.match(edge, /checkoutRastreado/);
  assert.match(edge, /Referrer-Policy.*no-referrer/s);
  assert.doesNotMatch(edge, /email|telefone|cpf|documento/i);
});

test('abandono só fica pronto após 12h, sem compra, e respeita 24h', () => {
  assert.match(migration, /first_clicked_at\+interval '12 hours'/);
  assert.match(migration, /mind_recovery_purchase_status\(c\.conversation_id\)='not_purchased'/);
  assert.match(migration, /last_lead_at\+interval '24 hours'/);
  assert.match(migration, /objection_group='checkout_abandonment'/);
});

test('rota curta da Cloudflare apenas encaminha ao redirecionador', () => {
  assert.match(wrangler, /"\/c\/\*"/);
  assert.match(worker, /\/c\\\/\[0-9a-f-\]\{36\}/);
  assert.match(worker, /Response\.redirect\(origin \+ '\/' \+ eventId, 307\)/);
});
