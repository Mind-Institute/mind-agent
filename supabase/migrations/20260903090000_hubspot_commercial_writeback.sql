-- Write-back comercial do agente inbound para Leads do HubSpot.
-- A migration cria apenas a fila/ledger e RPCs de service_role. Nenhum cron é criado e
-- nenhuma escrita externa acontece até a Edge ser habilitada explicitamente.

create table if not exists crm.hubspot_commercial_writeback (
  id uuid primary key default gen_random_uuid(),
  analysis_id uuid not null references intelligence.analise_conversa(id) on delete cascade,
  payload_hash text not null,
  conversation_id uuid not null references engagement.conversas(id) on delete cascade,
  hubspot_contact_id text not null,
  hubspot_lead_id text,
  action text not null check (action in ('create', 'update')),
  payload jsonb not null,
  status text not null default 'reserved' check (status in ('reserved', 'sent', 'failed')),
  error text,
  reserved_at timestamptz not null default now(),
  sent_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (analysis_id, payload_hash)
);

create index if not exists hubspot_commercial_writeback_contact_idx
  on crm.hubspot_commercial_writeback (hubspot_contact_id, reserved_at desc);

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
  existing_lead_id text,
  lead_count bigint,
  lead_name text,
  pipeline_id text,
  current_stage text,
  analysis jsonb
)
language sql
stable
security definer
set search_path = public, intelligence, engagement, pessoas, crm, platform, pg_temp
as $$
  with latest as (
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
    order by a.conversa_id, a.analisado_em desc
  ), identity as (
    select
      a.*,
      array_agg(distinct i.identificador) filter (
        where i.canal = 'hubspot' and nullif(trim(i.identificador), '') is not null
      ) as contact_ids,
      count(distinct i.identificador) filter (
        where i.canal = 'hubspot' and nullif(trim(i.identificador), '') is not null
      )::bigint as contact_count
    from latest a
    left join engagement.identidades i on i.pessoa_id = a.participante_id
    group by a.id, a.conversa_id, a.participante_id, a.dados, a.analisado_em
  ), base as (
    select
      a.*,
      p.primeiro_nome,
      p.sobrenome,
      p.empresa,
      c.nome_contato
    from identity a
    join engagement.conversas c on c.id = a.conversa_id
    join pessoas.pessoas p on p.id = a.participante_id
  ), pipeline as (
    select coalesce(
      (select i.config ->> 'pipeline_leads_inbound'
         from platform.integracoes i
        where i.codigo = 'hubspot' and i.ativo
        limit 1),
      '918902366'
    ) as id
  )
  select
    b.id,
    b.conversa_id,
    b.participante_id,
    case
      when coalesce(li.lead_count, 0) = 1 then li.primary_contact_id
      when b.contact_count = 1 then b.contact_ids[1]
    end,
    b.contact_count,
    case when coalesce(li.lead_count, 0) = 1 then li.lead_id end,
    coalesce(li.lead_count, 0),
    coalesce(
      nullif(trim(concat_ws(' ', b.primeiro_nome, b.sobrenome)), ''),
      nullif(trim(b.nome_contato), ''),
      'Lead WhatsApp'
    ) || case
      when nullif(trim(b.empresa), '') is not null
        then ' - ' || trim(b.empresa)
      else ''
    end,
    pipeline.id,
    case when coalesce(li.lead_count, 0) = 1 then li.current_stage end,
    b.dados
  from base b
  cross join pipeline
  left join lateral (
    select
      count(*)::bigint as lead_count,
      min(l.hubspot_lead_id) as lead_id,
      min(l.hs_pipeline_stage) as current_stage,
      min(l.hs_primary_contact_id) as primary_contact_id
    from crm.pipeline_leads_inbound l
    where l.hs_pipeline = pipeline.id
      and l.hs_primary_contact_id = any(coalesce(b.contact_ids, array[]::text[]))
  ) li on true
  order by b.analisado_em
  limit greatest(1, least(coalesce(p_limit, 25), 50));
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
set search_path = public, crm, pg_temp
as $$
begin
  insert into crm.hubspot_commercial_writeback (
    analysis_id, payload_hash, conversation_id,
    hubspot_contact_id, hubspot_lead_id, action, payload
  ) values (
    p_analysis_id, p_payload_hash, p_conversation_id,
    p_contact_id, p_lead_id, p_action, p_payload
  ) on conflict (analysis_id, payload_hash) do nothing;
  return found;
end;
$$;

create or replace function public.hubspot_commercial_confirm(
  p_analysis_id uuid,
  p_payload_hash text,
  p_lead_id text
)
returns void
language sql
security definer
set search_path = public, crm, pg_temp
as $$
  update crm.hubspot_commercial_writeback
     set status = 'sent',
         hubspot_lead_id = p_lead_id,
         sent_at = now(),
         error = null,
         updated_at = now()
   where analysis_id = p_analysis_id
     and payload_hash = p_payload_hash
     and status = 'reserved';
$$;

create or replace function public.hubspot_commercial_fail(
  p_analysis_id uuid,
  p_payload_hash text,
  p_error text
)
returns void
language sql
security definer
set search_path = public, crm, pg_temp
as $$
  update crm.hubspot_commercial_writeback
     set status = 'failed',
         error = left(coalesce(p_error, 'unknown_error'), 1000),
         updated_at = now()
   where analysis_id = p_analysis_id
     and payload_hash = p_payload_hash
     and status = 'reserved';
$$;

revoke all on function public.hubspot_commercial_candidates(integer, timestamptz) from public, anon, authenticated;
revoke all on function public.hubspot_commercial_reserve(uuid, text, uuid, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.hubspot_commercial_confirm(uuid, text, text) from public, anon, authenticated;
revoke all on function public.hubspot_commercial_fail(uuid, text, text) from public, anon, authenticated;

grant execute on function public.hubspot_commercial_candidates(integer, timestamptz) to service_role;
grant execute on function public.hubspot_commercial_reserve(uuid, text, uuid, text, text, text, jsonb) to service_role;
grant execute on function public.hubspot_commercial_confirm(uuid, text, text) to service_role;
grant execute on function public.hubspot_commercial_fail(uuid, text, text) to service_role;
