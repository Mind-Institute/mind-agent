import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { checkoutCurto } from '../supabase/functions/_shared/checkout-attribution.ts';

const migration = readFileSync(new URL('../supabase/migrations/20260903143000_checkout_redirect_e_abandono.sql', import.meta.url), 'utf8');
const identityStatus = readFileSync(new URL('../supabase/migrations/20260903150000_checkout_status_transacional_por_identidade.sql', import.meta.url), 'utf8');
const abandonmentInbox = readFileSync(new URL('../supabase/migrations/20260903154000_abandono_cria_inbox_sem_analise_previa.sql', import.meta.url), 'utf8');
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

test('não compra só é afirmada depois de a Eduzz sincronizar e resolver a identidade', () => {
  assert.match(identityStatus, /v_last_sync<v_clicked_at then return 'unknown'/);
  assert.match(identityStatus, /v_email is null and length\(coalesce\(v_phone,''\)\)<10/);
  assert.match(identityStatus, /from public\.espelho_estado/);
  assert.match(identityStatus, /e\.registros_lidos=e\.total_na_origem/);
  assert.match(identityStatus, /cliente_email/);
  assert.match(identityStatus, /cliente_telefone_norm/);
  assert.match(identityStatus, /return 'not_purchased'/);
});

test('abandono materializa inbox mesmo sem análise assíncrona anterior', () => {
  assert.match(abandonmentInbox, /'checkout_abandonment_v1'/);
  assert.match(abandonmentInbox, /on conflict \(conversa_id,analisador\) do update/);
  assert.match(abandonmentInbox, /a\.dados is distinct from excluded\.dados/,
    'refresh idempotente não pode envelhecer o rascunho em toda execução');
  assert.match(abandonmentInbox, /perform public\.mind_recovery_refresh\(10000\)/);
  assert.match(abandonmentInbox, /purchase_status='not_purchased'/);
  assert.match(abandonmentInbox, /in \('mindagent-web','app'\) then 'app_inbox'/);
  assert.match(abandonmentInbox, /dispatcher_enabled',false/);
});

test('rota curta da Cloudflare apenas encaminha ao redirecionador', () => {
  assert.match(wrangler, /"\/c\/\*"/);
  assert.match(worker, /\/c\\\/\[0-9a-f-\]\{36\}/);
  assert.match(worker, /Response\.redirect\(origin \+ '\/' \+ eventId, 307\)/);
});
