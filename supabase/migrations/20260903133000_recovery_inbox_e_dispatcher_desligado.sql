-- Inbox operacional de retomada comercial.
--
-- Esta migration NÃO envia mensagens, NÃO cria cron e NÃO habilita o
-- dispatcher. Ela transforma a análise que já existe em uma fila revisável,
-- usando compra transacional como autoridade e respeitando a janela do
-- WhatsApp. Rascunhos personalizados são gravados por um worker separado.

begin;

insert into intelligence.config (chave, valor)
values (
  'recovery_dispatch_v1',
  jsonb_build_object(
    'enabled', false,
    'dry_run', true,
    'timezone', 'America/Sao_Paulo',
    'send_from', '09:30',
    'send_until', '20:30',
    'abandonment_after_hours', 12,
    'whatsapp_window_hours', 24,
    'max_attempts', 3
  )::text
)
on conflict (chave) do update
set valor = (coalesce(nullif(intelligence.config.valor,''),'{}')::jsonb || jsonb_build_object(
  'enabled', false,
  'dry_run', true
))::text;

create table if not exists intelligence.recovery_inbox (
  conversation_id uuid primary key references engagement.conversas(id) on delete cascade,
  analysis_id uuid not null references intelligence.analise_conversa(id) on delete cascade,
  participant_id uuid references pessoas.pessoas(id) on delete set null,
  channel text not null,
  audience text,
  route text,
  contact_name text,
  last_lead_at timestamptz,
  last_agent_at timestamptz,
  last_activity_at timestamptz,
  whatsapp_window_expires_at timestamptz,
  next_send_at timestamptz,
  purchase_status text not null check (purchase_status in ('purchased','not_purchased','unknown')),
  inbox_state text not null check (inbox_state in (
    'excluded_purchased','blocked_optout','blocked_human_owned','purchase_check_required',
    'waiting_window','freeform_ready','needs_hsm','app_inbox','insufficient_evidence'
  )),
  heat text not null check (heat in ('cold','warm','hot','very_hot')),
  objection text,
  objection_group text not null check (objection_group in (
    'price','availability_logistics','payment_technical','internal_approval',
    'stopped_replying','interested_not_bought','promised_to_return','other'
  )),
  summary text,
  learned jsonb not null default '{}'::jsonb,
  recommended_action text,
  followup_anchor text,
  response_target text,
  freeform_message_draft text,
  hsm_message_draft text,
  hsm_template_key text,
  draft_status text not null default 'pending' check (draft_status in ('pending','processing','ready','failed','stale')),
  draft_model text,
  draft_prompt_version integer,
  draft_error text,
  draft_locked_until timestamptz,
  source_analysis_updated_at timestamptz not null,
  refreshed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists recovery_inbox_state_due_idx
  on intelligence.recovery_inbox (inbox_state, next_send_at, heat);
create index if not exists recovery_inbox_hsm_group_idx
  on intelligence.recovery_inbox (objection_group, heat)
  where inbox_state='needs_hsm';

alter table intelligence.recovery_inbox enable row level security;
revoke all on intelligence.recovery_inbox from public, anon, authenticated;
grant select, insert, update, delete on intelligence.recovery_inbox to service_role;

create table if not exists engagement.recovery_dispatch_queue (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references engagement.conversas(id) on delete cascade,
  analysis_id uuid not null references intelligence.analise_conversa(id) on delete cascade,
  mode text not null check (mode in ('freeform','hsm','app')),
  template_key text,
  message text not null check (char_length(message) between 1 and 1200),
  scheduled_at timestamptz not null,
  status text not null default 'draft' check (status in ('draft','approved','queued','processing','sent','canceled','failed')),
  attempts smallint not null default 0 check (attempts between 0 and 3),
  locked_until timestamptz,
  provider_message_id text,
  error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at timestamptz,
  unique (conversation_id, analysis_id, mode)
);

create index if not exists recovery_dispatch_queue_claim_idx
  on engagement.recovery_dispatch_queue (status, scheduled_at)
  where status='queued';

alter table engagement.recovery_dispatch_queue enable row level security;
revoke all on engagement.recovery_dispatch_queue from public, anon, authenticated;
grant select, insert, update, delete on engagement.recovery_dispatch_queue to service_role;

create or replace function public.mind_recovery_purchase_status(p_conversation_id uuid)
returns text
language plpgsql
stable
security definer
set search_path=''
as $function$
begin
  if exists (
    select 1 from intelligence.v_conversoes_agente v
    where v.conversation_id=p_conversation_id and v.paid
  ) then
    return 'purchased';
  end if;
  return public.silence_compra_summit_2026(p_conversation_id);
end
$function$;

create or replace function public.mind_recovery_delivery_slot(
  p_due timestamptz,
  p_expiry timestamptz,
  p_channel text
)
returns timestamptz
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_due timestamptz:=greatest(coalesce(p_due,now()),now());
  v_local timestamp;
  v_candidate_local timestamp;
  v_candidate timestamptz;
begin
  if p_channel<>'whatsapp' then return v_due; end if;
  v_local:=v_due at time zone 'America/Sao_Paulo';
  if v_local::time < time '09:30' then
    v_candidate_local:=v_local::date+time '09:30';
  elsif v_local::time > time '20:30' then
    v_candidate_local:=(v_local::date+1)+time '09:30';
  else
    v_candidate_local:=v_local;
  end if;
  v_candidate:=v_candidate_local at time zone 'America/Sao_Paulo';
  if p_expiry is not null and v_candidate>=p_expiry then return null; end if;
  return v_candidate;
end
$function$;

create or replace function public.mind_recovery_refresh(p_limit integer default 2000)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare v_count integer; v_now timestamptz:=now();
begin
  with agent_paid as materialized (
    select distinct v.conversation_id
    from intelligence.v_conversoes_agente v where v.paid
  ), crm_paid as materialized (
    select distinct nc.contato_hubspot_id hubspot_id
    from crm.negocio_contatos nc
    join crm.vendas_historicas_mind_summit vh on vh.hubspot_deal_id=nc.hubspot_deal_id
    where vh.status_de_pagamento='Pago' and vh.summit_year='2026'
  ), optout_message as materialized (
    select distinct m.conversa_id conversation_id
    from engagement.mensagens m where m.papel='lead'
      and lower(trim(coalesce(m.conteudo,''))) in ('sair','descadastrar')
  ), latest as materialized (
    select distinct on (a.conversa_id)
      a.id analysis_id,a.conversa_id conversation_id,a.participante_id participant_id,a.dados,a.atualizado_em,
      c.canal,c.audience,c.variables,c.nome_contato,c.ultima_atividade,
      cc.continuation_status,cc.next_review_at,
      case when ap.conversation_id is not null or cp.hubspot_id is not null
              or coalesce(ce.summit__participacao_anual,'') like '%2026%' then 'purchased'
           when ce.hubspot_id is not null then 'not_purchased' else 'unknown' end purchase_status,
      case
        when om.conversation_id is not null then 'opt_out_message'
        when lower(coalesce(cta.value,''))='descadastrar' then 'opt_out_cta'
        when lower(coalesce(cta.value,''))='já comprei meu ingresso' then 'declared_purchase'
        else null end exclusion_reason,
      lm.last_lead_at,lm.last_agent_at
    from intelligence.analise_conversa a
    join engagement.conversas c on c.id=a.conversa_id
    left join pessoas.pessoas p on p.id=a.participante_id
    left join crm.contato_espelho ce on ce.hubspot_id=p.hubspot_id
    left join crm_paid cp on cp.hubspot_id=p.hubspot_id
    left join agent_paid ap on ap.conversation_id=a.conversa_id
    left join optout_message om on om.conversation_id=a.conversa_id
    left join intelligence.continuidade_comercial cc on cc.conversa_id=a.conversa_id
    left join lateral (
      select case
        when jsonb_typeof(c.variables)='object' then coalesce(
          c.variables->>'hubspot_opcao_selecionada_treble',c.variables->>'opcao_selecionada')
        when jsonb_typeof(c.variables)='array' then (
          select v->>'value' from jsonb_array_elements(c.variables) v
          where v->>'key' in ('hubspot_opcao_selecionada_treble','opcao_selecionada')
          order by (v->>'key'='hubspot_opcao_selecionada_treble') desc limit 1)
        else null end value
    ) cta on true
    left join lateral (
      select max(m.criado_em) filter(where m.papel='lead') last_lead_at,
             max(m.criado_em) filter(where m.papel<>'lead') last_agent_at
      from engagement.mensagens m where m.conversa_id=a.conversa_id
    ) lm on true
    where a.funcao='comercial' and c.canal in ('whatsapp','mindagent-web')
    order by a.conversa_id,a.atualizado_em desc,a.id desc
    limit greatest(1,least(coalesce(p_limit,2000),10000))
  ), normalized as materialized (
    select l.*,
      coalesce(nullif(l.variables->>'rota_ativa',''),nullif(l.dados->>'motion','')) route,
      case lower(coalesce(l.dados->>'purchase_intent',''))
        when 'very_high' then 'very_hot' when 'high' then 'hot'
        when 'medium' then 'warm' else 'cold' end heat,
      lower(coalesce(nullif(l.dados->>'primary_barrier',''),'unclear')) objection,
      case
        when lower(coalesce(l.dados->>'primary_barrier','')) in ('price','personal_budget','company_budget','value') then 'price'
        when lower(coalesce(l.dados->>'primary_barrier','')) in ('schedule','availability','travel_logistics','format') then 'availability_logistics'
        when lower(coalesce(l.dados->>'primary_barrier','')) in ('payment','technical','transaction') then 'payment_technical'
        when lower(coalesce(l.dados->>'primary_barrier',''))='approval' then 'internal_approval'
        when lower(coalesce(l.dados->>'continuation_status',''))='commitment_pending'
          or l.dados#>>'{commitment,due}' is not null then 'promised_to_return'
        when lower(coalesce(l.dados->>'purchase_intent','')) in ('high','very_high') then 'interested_not_bought'
        when lower(coalesce(l.dados->>'continuation_status','')) in ('silence','active') then 'stopped_replying'
        else 'other' end objection_group,
      case when l.canal='whatsapp' and l.last_lead_at is not null
           then l.last_lead_at+interval '24 hours' end window_expiry,
      greatest(coalesce(l.next_review_at,'-infinity'::timestamptz),
               coalesce(l.last_lead_at+interval '12 hours','-infinity'::timestamptz)) raw_due
    from latest l
  ), classified as materialized (
    select n.*,
      public.mind_recovery_delivery_slot(n.raw_due,n.window_expiry,n.canal) slot,
      case
        when n.purchase_status='purchased' then 'excluded_purchased'
        when n.exclusion_reason in ('opt_out_message','opt_out_cta') then 'blocked_optout'
        when n.exclusion_reason='declared_purchase' then 'purchase_check_required'
        when lower(coalesce(n.dados#>>'{ownership,handoff_status}','')) in ('done','accepted','assigned','in_progress')
          or nullif(btrim(coalesce(n.dados#>>'{ownership,human_owner}','')),'') is not null then 'blocked_human_owned'
        when n.purchase_status='unknown' then 'purchase_check_required'
        when n.canal='mindagent-web' then 'app_inbox'
        when n.last_lead_at is null then 'insufficient_evidence'
        when v_now>=n.window_expiry then 'needs_hsm'
        when public.mind_recovery_delivery_slot(n.raw_due,n.window_expiry,n.canal) is null then 'needs_hsm'
        when public.mind_recovery_delivery_slot(n.raw_due,n.window_expiry,n.canal)<=v_now then 'freeform_ready'
        else 'waiting_window' end inbox_state
    from normalized n
  ), written as (
    insert into intelligence.recovery_inbox as r (
      conversation_id,analysis_id,participant_id,channel,audience,route,contact_name,
      last_lead_at,last_agent_at,last_activity_at,whatsapp_window_expires_at,next_send_at,
      purchase_status,inbox_state,heat,objection,objection_group,summary,learned,
      recommended_action,followup_anchor,response_target,source_analysis_updated_at,refreshed_at,updated_at
    )
    select conversation_id,analysis_id,participant_id,canal,audience,route,nome_contato,
      last_lead_at,last_agent_at,greatest(last_lead_at,last_agent_at,ultima_atividade),window_expiry,slot,
      purchase_status,inbox_state,heat,objection,objection_group,
      nullif(btrim(dados->>'conversation_summary'),''),
      jsonb_strip_nulls(jsonb_build_object(
        'customer_memory',dados->'customer_memory','agent_learning',dados->'agent_learning',
        'buyer_objective',dados->>'buyer_objective','commercial_signals',dados->'commercial_signals'
      )),
      nullif(btrim(dados->>'next_best_move'),''),nullif(btrim(dados->>'followup_anchor'),''),
      nullif(btrim(dados->>'response_target'),''),atualizado_em,v_now,v_now
    from classified
    on conflict (conversation_id) do update set
      analysis_id=excluded.analysis_id,participant_id=excluded.participant_id,channel=excluded.channel,
      audience=excluded.audience,route=excluded.route,contact_name=excluded.contact_name,
      last_lead_at=excluded.last_lead_at,last_agent_at=excluded.last_agent_at,
      last_activity_at=excluded.last_activity_at,
      whatsapp_window_expires_at=excluded.whatsapp_window_expires_at,next_send_at=excluded.next_send_at,
      purchase_status=excluded.purchase_status,inbox_state=excluded.inbox_state,heat=excluded.heat,
      objection=excluded.objection,objection_group=excluded.objection_group,summary=excluded.summary,
      learned=excluded.learned,recommended_action=excluded.recommended_action,
      followup_anchor=excluded.followup_anchor,response_target=excluded.response_target,
      draft_status=case when r.source_analysis_updated_at<>excluded.source_analysis_updated_at then 'stale' else r.draft_status end,
      source_analysis_updated_at=excluded.source_analysis_updated_at,refreshed_at=v_now,updated_at=v_now
    returning 1
  ) select count(*) into v_count from written;

  update engagement.recovery_dispatch_queue q set status='canceled',updated_at=v_now,
    error_code='conversation_no_longer_eligible'
  from intelligence.recovery_inbox r
  where q.conversation_id=r.conversation_id and q.status not in ('sent','canceled')
    and r.inbox_state in ('excluded_purchased','blocked_optout','blocked_human_owned','purchase_check_required');

  return jsonb_build_object('ok',true,'refreshed',v_count,'at',v_now,
    'dispatcher_enabled',false);
end
$function$;

create or replace function public.mind_recovery_claim_drafts(p_limit integer default 20)
returns table(conversation_id uuid,analysis_id uuid,inbox_state text,objection_group text,heat text,context jsonb)
language plpgsql
security definer
set search_path=''
as $function$
begin
  return query
  with target as (
    select r.conversation_id from intelligence.recovery_inbox r
    where r.inbox_state in ('freeform_ready','needs_hsm','app_inbox')
      and r.draft_status in ('pending','stale','failed')
      and (r.draft_locked_until is null or r.draft_locked_until<now())
    order by case r.heat when 'very_hot' then 1 when 'hot' then 2 when 'warm' then 3 else 4 end,
             r.last_activity_at desc nulls last
    limit greatest(1,least(coalesce(p_limit,20),50)) for update skip locked
  ), locked as (
    update intelligence.recovery_inbox r set draft_status='processing',draft_locked_until=now()+interval '10 minutes',updated_at=now()
    from target t where r.conversation_id=t.conversation_id returning r.*
  )
  select l.conversation_id,l.analysis_id,l.inbox_state,l.objection_group,l.heat,
    public.silence_montar_contexto(l.conversation_id) from locked l;
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
  if p_objection_group not in ('price','availability_logistics','payment_technical','internal_approval',
    'stopped_replying','interested_not_bought','promised_to_return','other')
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

create or replace function public.mind_recovery_prepare_queue(p_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare v_count integer;
begin
  with eligible as (
    select r.*,
      case when r.inbox_state='needs_hsm' then 'hsm'
           when r.inbox_state='app_inbox' then 'app' else 'freeform' end mode,
      case when r.inbox_state='needs_hsm' then r.hsm_message_draft else r.freeform_message_draft end message
    from intelligence.recovery_inbox r
    where r.draft_status='ready'
      and r.inbox_state in ('freeform_ready','needs_hsm','app_inbox')
    order by case r.heat when 'very_hot' then 1 when 'hot' then 2 when 'warm' then 3 else 4 end
    limit greatest(1,least(coalesce(p_limit,100),500))
  ), written as (
    insert into engagement.recovery_dispatch_queue as q
      (conversation_id,analysis_id,mode,template_key,message,scheduled_at,status)
    select conversation_id,analysis_id,mode,
      case when mode='hsm' then hsm_template_key end,message,coalesce(next_send_at,now()),'draft'
    from eligible where message is not null
      and (mode<>'hsm' or hsm_template_key is not null)
    on conflict (conversation_id,analysis_id,mode) do update set
      template_key=excluded.template_key,message=excluded.message,scheduled_at=excluded.scheduled_at,
      status=case when q.status='draft' then 'draft' else q.status end,updated_at=now()
    returning 1
  ) select count(*) into v_count from written;
  return jsonb_build_object('ok',true,'drafts_prepared',v_count,'dispatcher_enabled',false);
end
$function$;

create or replace function public.mind_recovery_claim_dispatch(p_limit integer default 10)
returns setof engagement.recovery_dispatch_queue
language plpgsql
security definer
set search_path=''
as $function$
declare v_enabled boolean;
begin
  select coalesce((c.valor::jsonb->>'enabled')::boolean,false) into v_enabled
  from intelligence.config c where c.chave='recovery_dispatch_v1';
  if not coalesce(v_enabled,false) then return; end if;
  return query
  with target as (
    select q.id from engagement.recovery_dispatch_queue q
    where q.status='queued' and q.scheduled_at<=now()
      and (q.locked_until is null or q.locked_until<now()) and q.attempts<3
    order by q.scheduled_at limit greatest(1,least(coalesce(p_limit,10),50))
    for update skip locked
  )
  update engagement.recovery_dispatch_queue q set status='processing',attempts=q.attempts+1,
    locked_until=now()+interval '10 minutes',updated_at=now()
  from target t where q.id=t.id returning q.*;
end
$function$;

create or replace view intelligence.v_recovery_inbox_actionable
with (security_invoker=true)
as select * from intelligence.recovery_inbox
where inbox_state not in ('excluded_purchased','blocked_optout','blocked_human_owned');

create or replace view intelligence.v_recovery_hsm_groups
with (security_invoker=true)
as select objection_group,heat,count(*) conversation_count,
  min(last_activity_at) oldest_activity,max(last_activity_at) newest_activity,
  array_agg(distinct hsm_template_key) filter(where hsm_template_key is not null) suggested_templates
from intelligence.recovery_inbox where inbox_state='needs_hsm'
group by objection_group,heat;

revoke all on intelligence.v_recovery_inbox_actionable,intelligence.v_recovery_hsm_groups
  from public,anon,authenticated;
grant select on intelligence.v_recovery_inbox_actionable,intelligence.v_recovery_hsm_groups
  to service_role;

revoke all on function public.mind_recovery_purchase_status(uuid),
  public.mind_recovery_delivery_slot(timestamptz,timestamptz,text),
  public.mind_recovery_refresh(integer),public.mind_recovery_claim_drafts(integer),
  public.mind_recovery_save_draft(uuid,uuid,text,text,text,text,text,text,text,text,text,integer,text),
  public.mind_recovery_prepare_queue(integer),public.mind_recovery_claim_dispatch(integer)
from public,anon,authenticated;
grant execute on function public.mind_recovery_purchase_status(uuid),
  public.mind_recovery_delivery_slot(timestamptz,timestamptz,text),
  public.mind_recovery_refresh(integer),public.mind_recovery_claim_drafts(integer),
  public.mind_recovery_save_draft(uuid,uuid,text,text,text,text,text,text,text,text,text,integer,text),
  public.mind_recovery_prepare_queue(integer),public.mind_recovery_claim_dispatch(integer)
to service_role;

do $guard$
declare v_cfg jsonb; v_claims integer;
begin
  select valor::jsonb into v_cfg from intelligence.config where chave='recovery_dispatch_v1';
  if coalesce((v_cfg->>'enabled')::boolean,true) or not coalesce((v_cfg->>'dry_run')::boolean,false) then
    raise exception 'dispatcher precisa nascer desligado e em dry-run';
  end if;
  select count(*) into v_claims from public.mind_recovery_claim_dispatch(1);
  if v_claims<>0 then raise exception 'dispatcher desligado ainda entregou item'; end if;
end
$guard$;

commit;
