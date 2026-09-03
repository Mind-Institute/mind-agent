-- Redirecionador de checkout e sinal de abandono.
-- O identificador público continua sendo somente o UUID opaco do envio.

begin;

create table if not exists engagement.checkout_clicks (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references engagement.agente_eventos(id) on delete cascade,
  conversation_id uuid not null references engagement.conversas(id) on delete cascade,
  participant_id uuid references pessoas.pessoas(id) on delete set null,
  request_id uuid not null unique,
  clicked_at timestamptz not null default now()
);

create index if not exists checkout_clicks_event_idx
  on engagement.checkout_clicks(event_id,clicked_at);
create index if not exists checkout_clicks_conversation_idx
  on engagement.checkout_clicks(conversation_id,clicked_at desc);

alter table engagement.checkout_clicks enable row level security;
revoke all on engagement.checkout_clicks from public,anon,authenticated;
grant select,insert on engagement.checkout_clicks to service_role;

create or replace function public.mind_checkout_click_registrar(
  p_event_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare v_event engagement.agente_eventos%rowtype; v_click engagement.checkout_clicks%rowtype;
begin
  if p_event_id is null or p_request_id is null then
    raise exception 'checkout_click_invalid' using errcode='22023';
  end if;
  select e.* into v_event from engagement.agente_eventos e
  where e.id=p_event_id and e.tipo='checkout_link_enviado';
  if not found then return jsonb_build_object('ok',false,'reason','not_found'); end if;
  if coalesce(v_event.dados->>'checkout_url_original','') !~* '^https://([a-z0-9-]+\.)*eduzz\.com/' then
    raise exception 'checkout_destination_invalid' using errcode='22023';
  end if;
  insert into engagement.checkout_clicks(event_id,conversation_id,participant_id,request_id)
  values(v_event.id,v_event.conversa_id,v_event.participante_id,p_request_id)
  on conflict(request_id) do nothing;
  select c.* into v_click from engagement.checkout_clicks c where c.request_id=p_request_id;
  if v_click.event_id is distinct from p_event_id then
    raise exception 'checkout_click_request_conflict' using errcode='23505';
  end if;
  return jsonb_build_object(
    'ok',true,'event_id',v_event.id,'conversation_id',v_event.conversa_id,
    'checkout_url',v_event.dados->>'checkout_url_original',
    'channel',v_event.dados->>'canal','agent_id',v_event.dados->>'agente',
    'route',v_event.dados->>'rota','reason',v_event.dados->>'motivo',
    'clicked_at',v_click.clicked_at
  );
end
$function$;

alter table intelligence.recovery_inbox
  add column if not exists checkout_event_id uuid references engagement.agente_eventos(id) on delete set null,
  add column if not exists checkout_clicked_at timestamptz;

alter table intelligence.recovery_inbox
  drop constraint if exists recovery_inbox_objection_group_check;
alter table intelligence.recovery_inbox
  add constraint recovery_inbox_objection_group_check check (objection_group in (
    'checkout_abandonment','price','availability_logistics','payment_technical','internal_approval',
    'stopped_replying','interested_not_bought','promised_to_return','other'
  ));

create or replace view intelligence.v_checkout_abandonment
with (security_invoker=true)
as
with click_summary as (
  select e.id event_id,e.conversa_id conversation_id,e.participante_id,
    e.dados->>'canal' channel,e.dados->>'agente' agent_id,e.dados->>'motivo' checkout_reason,
    min(c.clicked_at) first_clicked_at,max(c.clicked_at) last_clicked_at,count(*) click_count
  from engagement.agente_eventos e join engagement.checkout_clicks c on c.event_id=e.id
  where e.tipo='checkout_link_enviado'
  group by e.id,e.conversa_id,e.participante_id,e.dados
), last_lead as (
  select m.conversa_id,max(m.criado_em) last_lead_at
  from engagement.mensagens m where m.papel='lead' group by m.conversa_id
)
select c.*,l.last_lead_at,l.last_lead_at+interval '24 hours' whatsapp_window_expires_at,
  c.first_clicked_at+interval '12 hours' abandonment_due_at,
  case
    when now()<c.first_clicked_at+interval '12 hours' then 'monitoring'
    when c.channel='whatsapp' and now()>=l.last_lead_at+interval '24 hours' then 'needs_hsm'
    when c.channel='whatsapp' and public.mind_recovery_delivery_slot(
      c.first_clicked_at+interval '12 hours',l.last_lead_at+interval '24 hours','whatsapp') is null then 'needs_hsm'
    else 'ready' end abandonment_state
from click_summary c left join last_lead l on l.conversa_id=c.conversation_id
where public.mind_recovery_purchase_status(c.conversation_id)='not_purchased'
  and not exists(select 1 from intelligence.v_conversoes_agente v where v.event_id=c.event_id and v.paid);

revoke all on intelligence.v_checkout_abandonment from public,anon,authenticated;
grant select on intelligence.v_checkout_abandonment to service_role;

create or replace function public.mind_checkout_abandonment_refresh()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare v_count integer;
begin
  with latest as materialized (
    select distinct on (a.conversation_id) a.*
    from intelligence.v_checkout_abandonment a
    where a.abandonment_state<>'monitoring'
    order by a.conversation_id,a.last_clicked_at desc,a.event_id
  ), updated as (
    update intelligence.recovery_inbox r set
      checkout_event_id=a.event_id,checkout_clicked_at=a.last_clicked_at,
      heat='very_hot',objection='checkout_abandonment',objection_group='checkout_abandonment',
      recommended_action='retomar_checkout_sem_reabrir_a_decisao',
      followup_anchor='checkout aberto e pagamento ainda não confirmado',
      inbox_state=case when a.abandonment_state='needs_hsm' then 'needs_hsm'
                       when a.channel='mindagent-web' then 'app_inbox'
                       else 'freeform_ready' end,
      next_send_at=case when a.channel='whatsapp' then public.mind_recovery_delivery_slot(
        a.abandonment_due_at,a.whatsapp_window_expires_at,'whatsapp') else greatest(a.abandonment_due_at,now()) end,
      draft_status=case when r.checkout_event_id is distinct from a.event_id then 'stale' else r.draft_status end,
      refreshed_at=now(),updated_at=now()
    from latest a where r.conversation_id=a.conversation_id
      and r.purchase_status='not_purchased'
      and r.inbox_state not in ('excluded_purchased','blocked_optout','blocked_human_owned','purchase_check_required')
    returning 1
  ) select count(*) into v_count from updated;
  return jsonb_build_object('ok',true,'abandonments_marked',v_count,'dispatcher_enabled',false);
end
$function$;

create or replace function public.mind_recovery_save_draft(
  p_conversation_id uuid,p_analysis_id uuid,p_summary text,p_objection text,p_objection_group text,
  p_heat text,p_recommended_action text,p_freeform_message text,p_hsm_message text,p_hsm_template_key text,
  p_model text,p_prompt_version integer,p_error text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare v_updated integer;
begin
  if p_objection_group not in ('checkout_abandonment','price','availability_logistics','payment_technical',
    'internal_approval','stopped_replying','interested_not_bought','promised_to_return','other')
    or p_heat not in ('cold','warm','hot','very_hot') then
    raise exception 'recovery_taxonomy_invalid' using errcode='22023';
  end if;
  update intelligence.recovery_inbox set
    summary=coalesce(nullif(btrim(p_summary),''),summary),objection=coalesce(nullif(btrim(p_objection),''),objection),
    objection_group=p_objection_group,heat=p_heat,
    recommended_action=coalesce(nullif(btrim(p_recommended_action),''),recommended_action),
    freeform_message_draft=left(nullif(btrim(p_freeform_message),''),1200),
    hsm_message_draft=left(nullif(btrim(p_hsm_message),''),1200),
    hsm_template_key=left(nullif(btrim(p_hsm_template_key),''),120),
    draft_status=case when p_error is null then 'ready' else 'failed' end,
    draft_model=nullif(btrim(p_model),''),draft_prompt_version=p_prompt_version,
    draft_error=left(nullif(btrim(p_error),''),500),draft_locked_until=null,updated_at=now()
  where conversation_id=p_conversation_id and analysis_id=p_analysis_id;
  get diagnostics v_updated=row_count;
  return jsonb_build_object('ok',v_updated=1,'updated',v_updated);
end
$function$;

revoke all on function public.mind_checkout_click_registrar(uuid,uuid),
  public.mind_checkout_abandonment_refresh(),
  public.mind_recovery_save_draft(uuid,uuid,text,text,text,text,text,text,text,text,text,integer,text)
from public,anon,authenticated;
grant execute on function public.mind_checkout_click_registrar(uuid,uuid),
  public.mind_checkout_abandonment_refresh(),
  public.mind_recovery_save_draft(uuid,uuid,text,text,text,text,text,text,text,text,text,integer,text)
to service_role;

commit;
