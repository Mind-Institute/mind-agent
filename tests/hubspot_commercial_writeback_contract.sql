-- Contract test for the write-back ledger RPCs.
-- Run only after applying 20260903090000_hubspot_commercial_writeback.sql.
-- The transaction is always rolled back: no fixture or ledger row persists.

begin;

insert into engagement.conversas (id, canal, agente)
values ('10000000-0000-4000-8000-000000000001', 'whatsapp', 'treble-inbound-agent');

insert into intelligence.analise_conversa (
  id, conversa_id, analisador, funcao, dados, prompt_versao
) values (
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
  'analise_vendas_summit',
  'vendas',
  '{}'::jsonb,
  1
);

-- Two conversations for the same person must produce exactly one candidate.
insert into pessoas.pessoas (
  id, primeiro_nome, sobrenome, origem
) values (
  '30000000-0000-4000-8000-000000000001', 'Contract', 'Participant', 'bot'
);

insert into engagement.conversas (id, participante_id, canal, agente)
values
  (
    '10000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000001',
    'whatsapp',
    'treble-inbound-agent'
  ),
  (
    '10000000-0000-4000-8000-000000000003',
    '30000000-0000-4000-8000-000000000001',
    'whatsapp',
    'treble-inbound-agent'
  );

insert into intelligence.analise_conversa (
  id, conversa_id, participante_id, analisador, funcao,
  dados, prompt_versao, analisado_em
) values
  (
    '20000000-0000-4000-8000-000000000002',
    '10000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000001',
    'analise_vendas_summit', 'vendas', '{}', 1,
    clock_timestamp() - interval '2 minutes'
  ),
  (
    '20000000-0000-4000-8000-000000000003',
    '10000000-0000-4000-8000-000000000003',
    '30000000-0000-4000-8000-000000000001',
    'analise_vendas_summit', 'vendas', '{}', 1,
    clock_timestamp() - interval '1 minute'
  );

do $contract$
declare
  v_ok boolean;
  v_row crm.hubspot_commercial_writeback%rowtype;
  v_candidate_count integer;
  v_candidate_analysis uuid;
begin
  select count(*), min(c.analysis_id::text)::uuid
    into v_candidate_count, v_candidate_analysis
    from public.hubspot_commercial_candidates(
      25,
      clock_timestamp() - interval '1 hour'
    ) c
   where c.participant_id = '30000000-0000-4000-8000-000000000001';
  assert v_candidate_count = 1,
    'one person with multiple conversations must produce one candidate';
  assert v_candidate_analysis = '20000000-0000-4000-8000-000000000003',
    'the newest analysis for the person must win';

  v_ok := public.hubspot_commercial_reserve(
    '20000000-0000-4000-8000-000000000001', 'create-hash',
    '10000000-0000-4000-8000-000000000001', 'contact-test',
    null, 'create', '{"kind":"create"}'::jsonb
  );
  assert v_ok, 'first create reservation must succeed';

  v_ok := public.hubspot_commercial_reserve(
    '20000000-0000-4000-8000-000000000001', 'create-hash',
    '10000000-0000-4000-8000-000000000001', 'contact-test',
    null, 'create', '{"kind":"create"}'::jsonb
  );
  assert not v_ok, 'duplicate create reservation must be blocked';

  v_ok := public.hubspot_commercial_fail(
    '20000000-0000-4000-8000-000000000001', 'create-hash',
    'simulated', true
  );
  assert v_ok, 'create failure transition must succeed';

  select * into strict v_row
    from crm.hubspot_commercial_writeback
   where analysis_id = '20000000-0000-4000-8000-000000000001'
     and payload_hash = 'create-hash';
  assert v_row.status = 'failed', 'create must be failed';
  assert not v_row.retryable, 'create must never be retryable';
  assert v_row.next_retry_at is null, 'create must have no retry timestamp';

  v_ok := public.hubspot_commercial_reserve(
    '20000000-0000-4000-8000-000000000001', 'create-hash',
    '10000000-0000-4000-8000-000000000001', 'contact-test',
    null, 'create', '{"kind":"create"}'::jsonb
  );
  assert not v_ok, 'failed create must never be auto-retried';

  v_ok := public.hubspot_commercial_reserve(
    '20000000-0000-4000-8000-000000000001', 'update-hash',
    '10000000-0000-4000-8000-000000000001', 'contact-test',
    'lead-test', 'update', '{"kind":"update"}'::jsonb
  );
  assert v_ok, 'first update reservation must succeed';

  v_ok := public.hubspot_commercial_fail(
    '20000000-0000-4000-8000-000000000001', 'update-hash',
    'simulated-1', true
  );
  assert v_ok, 'first update failure transition must succeed';

  select * into strict v_row
    from crm.hubspot_commercial_writeback
   where analysis_id = '20000000-0000-4000-8000-000000000001'
     and payload_hash = 'update-hash';
  assert v_row.status = 'failed' and v_row.retryable,
    'attempt 1 must be retryable';
  assert v_row.attempt_count = 1, 'attempt count must start at 1';
  assert v_row.next_retry_at is not null, 'attempt 1 must schedule retry';

  v_ok := public.hubspot_commercial_reserve(
    '20000000-0000-4000-8000-000000000001', 'update-hash',
    '10000000-0000-4000-8000-000000000001', 'contact-test',
    'lead-test', 'update', '{"kind":"update"}'::jsonb
  );
  assert not v_ok, 'update cannot retry before backoff';

  update crm.hubspot_commercial_writeback
     set next_retry_at = clock_timestamp() - interval '1 second'
   where analysis_id = '20000000-0000-4000-8000-000000000001'
     and payload_hash = 'update-hash';

  v_ok := public.hubspot_commercial_reserve(
    '20000000-0000-4000-8000-000000000001', 'update-hash',
    '10000000-0000-4000-8000-000000000001', 'contact-test',
    'lead-test', 'update', '{"kind":"update"}'::jsonb
  );
  assert v_ok, 'second update attempt must reserve after backoff';

  v_ok := public.hubspot_commercial_fail(
    '20000000-0000-4000-8000-000000000001', 'update-hash',
    'simulated-2', true
  );
  assert v_ok, 'second update failure transition must succeed';

  update crm.hubspot_commercial_writeback
     set next_retry_at = clock_timestamp() - interval '1 second'
   where analysis_id = '20000000-0000-4000-8000-000000000001'
     and payload_hash = 'update-hash';

  v_ok := public.hubspot_commercial_reserve(
    '20000000-0000-4000-8000-000000000001', 'update-hash',
    '10000000-0000-4000-8000-000000000001', 'contact-test',
    'lead-test', 'update', '{"kind":"update"}'::jsonb
  );
  assert v_ok, 'third update attempt must reserve after backoff';

  v_ok := public.hubspot_commercial_fail(
    '20000000-0000-4000-8000-000000000001', 'update-hash',
    'simulated-3', true
  );
  assert v_ok, 'third update failure transition must succeed';

  select * into strict v_row
    from crm.hubspot_commercial_writeback
   where analysis_id = '20000000-0000-4000-8000-000000000001'
     and payload_hash = 'update-hash';
  assert v_row.attempt_count = 3, 'update retries must stop at 3';
  assert not v_row.retryable, 'third update failure must close retries';
  assert v_row.next_retry_at is null,
    'third update failure must clear retry timestamp';

  v_ok := public.hubspot_commercial_reserve(
    '20000000-0000-4000-8000-000000000001', 'update-hash',
    '10000000-0000-4000-8000-000000000001', 'contact-test',
    'lead-test', 'update', '{"kind":"update"}'::jsonb
  );
  assert not v_ok, 'fourth update attempt must be blocked';

  v_ok := public.hubspot_commercial_reserve(
    '20000000-0000-4000-8000-000000000001', 'confirm-hash',
    '10000000-0000-4000-8000-000000000001', 'contact-test',
    'lead-test', 'update', '{"kind":"confirm"}'::jsonb
  );
  assert v_ok, 'confirm test reservation must succeed';

  v_ok := public.hubspot_commercial_confirm(
    '20000000-0000-4000-8000-000000000001', 'confirm-hash', 'lead-test'
  );
  assert v_ok, 'first confirm must succeed';

  v_ok := public.hubspot_commercial_confirm(
    '20000000-0000-4000-8000-000000000001', 'confirm-hash', 'lead-test'
  );
  assert not v_ok, 'duplicate confirm must be idempotently blocked';

  v_ok := public.hubspot_commercial_reserve(
    '20000000-0000-4000-8000-000000000001', 'confirm-hash',
    '10000000-0000-4000-8000-000000000001', 'contact-test',
    'lead-test', 'update', '{"kind":"confirm"}'::jsonb
  );
  assert not v_ok, 'sent payload must never reserve again';
end
$contract$;

rollback;
