-- Índices de cobertura para as FKs novas. Além das leituras normais, eles
-- evitam varredura integral quando a linha-pai é alterada ou removida.

begin;

create index if not exists checkout_clicks_participant_idx
  on engagement.checkout_clicks(participant_id);
create index if not exists recovery_dispatch_queue_analysis_idx
  on engagement.recovery_dispatch_queue(analysis_id);
create index if not exists recovery_inbox_analysis_idx
  on intelligence.recovery_inbox(analysis_id);
create index if not exists recovery_inbox_checkout_event_idx
  on intelligence.recovery_inbox(checkout_event_id);
create index if not exists recovery_inbox_participant_idx
  on intelligence.recovery_inbox(participant_id);

commit;
