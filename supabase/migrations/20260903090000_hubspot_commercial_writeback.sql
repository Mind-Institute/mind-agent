-- Write-back comercial do agente inbound para Leads do HubSpot.
-- Esta migration cria apenas o ledger e RPCs restritas a service_role. Não cria cron,
-- não altera identidade e não produz escrita externa por conta própria.

create table if not exists crm.hubspot_commercial_writeback (
  id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references intelligence.analise_conversa(id),
  payload_hash text not null,
  conversation_id uuid not null references engagement.conversas(id),
  hubspot_contact_id text not null,
  hubspot_lead_id text,
  action text not null check (action in ('create', 'update')),
  payload jsonb not null,
  status text not null default 'reserved' check (status in ('reserved', 'sent', 'failed')),
  retryable boolean not null default false,
  attempt_count smallint not null default 1 check (attempt_count between 1 and 3),
  error text,
  reserved_at timestamptz not null default now(),
  last_attempt_at timestamptz not null default now(),
  next_retry_at timestamptz,
  sent_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (analysis_id, payload_hash)
);

create index if not exists hubspot_commercial_writeback_conversation_idx
  on crm.hubspot_commercial_writeback (conversation_id);

create index if not exists hubspot_commercial_writeback_contact_idx
  on crm.hubspot_commercial_writeback (hubspot_contact_id, reserved_at desc);

alter table crm.hubspot_commercial_writeback enable row level security;
revoke all on crm.hubspot_commercial_writeback from anon, authenticated;
grant select, insert, update on crm.hubspot_commercial_writeback to service_role;

create or replace function public.hubspot_commercial_candidates(
  p_limit integer,
  p_after timestamptz
)
returns table (
  analysis_id uuid,
  conversation_id uuid,
  participant_id uuid,
  contact_id text,
  contact_count bigint,
  contact_mirror_missing_count bigint,
  identity_pending boolean,
  existing_lead_id text,
  lead_count bigint,
  lead_name text,
  pipeline_id text,
  pipeline_config_count bigint,
  current_stage text,
  analysis jsonb
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with pipeline_config as materialized (
    select nullif(btrim(i.config ->> 'pipeline_leads_inbound'), '') as pipeline_id
      from platform.integracoes i
     where i.codigo = 'hubspot'
       and i.ativo
  ), pipeline as materialized (
    select
      case when count(*) = 1 then min(pipeline_id)
      end as pipeline_id,
      count(*)::bigint as config_count
    from pipeline_config
  ), latest_per_conversation as materialized (
    select distinct on (a.conversa_id)
      a.id,
      a.conversa_id,
      a.participante_id,
      a.dados,
      a.analisado_em
    from intelligence.analise_conversa a
    join engagement.conversas c on c.id = a.conversa_id
    where c.agente = 'treble-inbound-agent'
      and a.analisador = 'analise_vendas_summit'
      and a.analisado_em >= p_after
    order by a.conversa_id, a.analisado_em desc, a.id desc
  ), eligible as materialized (
    select a.*
      from latest_per_conversation a
     where not exists (
       select 1
         from crm.hubspot_commercial_writeback w
        where w.analysis_id = a.id
          and (
            w.status = 'sent'
            or (
              w.status = 'reserved'
              and (
                w.action = 'create'
                or w.attempt_count >= 3
                or w.reserved_at > now() - interval '15 minutes'
              )
            )
            or (
              w.status = 'failed'
              and (
                not w.retryable
                or w.action = 'create'
                or w.attempt_count >= 3
                or w.next_retry_at is null
                or w.next_retry_at > now()
              )
            )
          )
     )
  ), selected as materialized (
    select l.*
      from eligible l
     order by l.analisado_em, l.id
     limit greatest(1, least(coalesce(p_limit, 25), 50))
  ), facts as materialized (
    select
      s.*,
      public.mind_crm_comercial(s.participante_id) as commercial,
      public.mind_pessoa_fatos(s.participante_id) as person
    from selected s
  )
  select
    f.id as analysis_id,
    f.conversa_id as conversation_id,
    f.participante_id as participant_id,
    case
      when coalesce(leads.lead_count, 0) = 1 then leads.primary_contact_id
      when coalesce(leads.lead_count, 0) = 0 and coalesce(contacts.contact_count, 0) = 1
        then contacts.contact_ids[1]
    end as contact_id,
    coalesce(contacts.contact_count, 0)::bigint as contact_count,
    coalesce((f.person #>> '{meta,identidades_hubspot_sem_espelho}')::bigint, 0)
      as contact_mirror_missing_count,
    coalesce((f.person #>> '{meta,pendencia_identidade,aberta}')::boolean, false)
      as identity_pending,
    case when coalesce(leads.lead_count, 0) = 1 then leads.lead_id end as existing_lead_id,
    coalesce(leads.lead_count, 0)::bigint as lead_count,
    coalesce(
      nullif(btrim(concat_ws(' ',
        f.person #>> '{perfil,primeiro_nome}',
        f.person #>> '{perfil,sobrenome}'
      )), ''),
      nullif(btrim(c.nome_contato), ''),
      'Lead WhatsApp'
    ) || case
      when nullif(btrim(f.person #>> '{perfil,empresa}'), '') is not null
        then ' - ' || btrim(f.person #>> '{perfil,empresa}')
      else ''
    end as lead_name,
    p.pipeline_id,
    p.config_count as pipeline_config_count,
    case when coalesce(leads.lead_count, 0) = 1 then leads.current_stage end as current_stage,
    f.dados as analysis
  from facts f
  join engagement.conversas c on c.id = f.conversa_id
  cross join pipeline p
  left join lateral (
    select
      array_agg(distinct x.contact_id order by x.contact_id) as contact_ids,
      count(distinct x.contact_id)::bigint as contact_count
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(f.commercial #> '{meta,contatos_hubspot_considerados}') = 'array'
          then f.commercial #> '{meta,contatos_hubspot_considerados}'
        else '[]'::jsonb
      end
    ) x(contact_id)
    where nullif(btrim(x.contact_id), '') is not null
  ) contacts on true
  left join lateral (
    select
      count(distinct x.item ->> 'hubspot_lead_id')::bigint as lead_count,
      min(x.item ->> 'hubspot_lead_id') as lead_id,
      min(x.item ->> 'hs_pipeline_stage') as current_stage,
      min(x.item ->> 'hs_primary_contact_id') as primary_contact_id
    from jsonb_array_elements(
      case
        when jsonb_typeof(f.commercial -> 'lead_atual') = 'array'
          then f.commercial -> 'lead_atual'
        else '[]'::jsonb
      end
    ) x(item)
    where p.pipeline_id is not null
      and x.item ->> 'hs_pipeline' = p.pipeline_id
      and nullif(btrim(x.item ->> 'hubspot_lead_id'), '') is not null
      and nullif(btrim(x.item ->> 'hs_primary_contact_id'), '') is not null
  ) leads on true
  order by f.analisado_em, f.id;
$$;

create or replace function public.hubspot_commercial_reserve(
  p_analysis_id uuid,
  p_payload_hash text,
  p_conversation_id uuid,
  p_contact_id text,
  p_lead_id text,
  p_action text,
  p_payload jsonb
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_reserved boolean := false;
begin
  insert into crm.hubspot_commercial_writeback as w (
    analysis_id, payload_hash, conversation_id,
    hubspot_contact_id, hubspot_lead_id, action, payload,
    retryable, attempt_count, reserved_at, last_attempt_at
  ) values (
    p_analysis_id, p_payload_hash, p_conversation_id,
    p_contact_id, p_lead_id, p_action, p_payload,
    p_action = 'update', 1, clock_timestamp(), clock_timestamp()
  )
  on conflict (analysis_id, payload_hash) do update
     set conversation_id = excluded.conversation_id,
         hubspot_contact_id = excluded.hubspot_contact_id,
         hubspot_lead_id = excluded.hubspot_lead_id,
         action = excluded.action,
         payload = excluded.payload,
         status = 'reserved',
         retryable = excluded.action = 'update',
         attempt_count = w.attempt_count + 1,
         error = null,
         reserved_at = clock_timestamp(),
         last_attempt_at = clock_timestamp(),
         next_retry_at = null,
         updated_at = clock_timestamp()
   where w.action = 'update'
     and excluded.action = 'update'
     and w.attempt_count < 3
     and (
       (w.status = 'failed' and w.retryable and w.next_retry_at <= clock_timestamp())
       or (w.status = 'reserved' and w.reserved_at <= clock_timestamp() - interval '15 minutes')
     )
  returning true into v_reserved;

  return coalesce(v_reserved, false);
end;
$$;

create or replace function public.hubspot_commercial_confirm(
  p_analysis_id uuid,
  p_payload_hash text,
  p_lead_id text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_updated boolean := false;
begin
  update crm.hubspot_commercial_writeback
     set status = 'sent',
         hubspot_lead_id = p_lead_id,
         sent_at = clock_timestamp(),
         retryable = false,
         next_retry_at = null,
         error = null,
         updated_at = clock_timestamp()
   where analysis_id = p_analysis_id
     and payload_hash = p_payload_hash
     and status = 'reserved'
  returning true into v_updated;

  return coalesce(v_updated, false);
end;
$$;

create or replace function public.hubspot_commercial_fail(
  p_analysis_id uuid,
  p_payload_hash text,
  p_error text,
  p_retryable boolean
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_updated boolean := false;
begin
  update crm.hubspot_commercial_writeback
     set status = 'failed',
         retryable = coalesce(p_retryable, false)
           and action = 'update'
           and attempt_count < 3,
         next_retry_at = case
           when coalesce(p_retryable, false) and action = 'update' and attempt_count < 3
             then clock_timestamp() + interval '5 minutes'
           else null
         end,
         error = left(coalesce(p_error, 'unknown_error'), 1000),
         updated_at = clock_timestamp()
   where analysis_id = p_analysis_id
     and payload_hash = p_payload_hash
     and status = 'reserved'
  returning true into v_updated;

  return coalesce(v_updated, false);
end;
$$;

revoke all on function public.hubspot_commercial_candidates(integer, timestamptz) from public, anon, authenticated;
revoke all on function public.hubspot_commercial_reserve(uuid, text, uuid, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.hubspot_commercial_confirm(uuid, text, text) from public, anon, authenticated;
revoke all on function public.hubspot_commercial_fail(uuid, text, text, boolean) from public, anon, authenticated;

grant execute on function public.hubspot_commercial_candidates(integer, timestamptz) to service_role;
grant execute on function public.hubspot_commercial_reserve(uuid, text, uuid, text, text, text, jsonb) to service_role;
grant execute on function public.hubspot_commercial_confirm(uuid, text, text) to service_role;
grant execute on function public.hubspot_commercial_fail(uuid, text, text, boolean) to service_role;
