create table public.mind_admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role text not null check (role in ('administrador','editor','aprovador','atendimento','analista')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.mind_admin_users is 'Backend authorization source for the Mind Agent administration panel.';
comment on column public.mind_admin_users.role is 'Server-side role. Never derive authorization from auth.users.raw_user_meta_data.';

alter table public.mind_admin_users enable row level security;
revoke all on table public.mind_admin_users from public, anon, authenticated;
grant select, insert, update, delete on table public.mind_admin_users to service_role;

create table public.mind_admin_audit (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null check (action in ('criar','atualizar','publicar','arquivar','reindexar','login')),
  resource text not null,
  record_id text not null,
  record_label text,
  before_data jsonb,
  after_data jsonb,
  occurred_at timestamptz not null default now(),
  request_id uuid not null
);

create index mind_admin_audit_occurred_at_idx
  on public.mind_admin_audit (occurred_at desc);
create index mind_admin_audit_actor_idx
  on public.mind_admin_audit (actor_user_id, occurred_at desc);

comment on table public.mind_admin_audit is 'Append-only audit trail for authenticated administrative actions.';

alter table public.mind_admin_audit enable row level security;
revoke all on table public.mind_admin_audit from public, anon, authenticated;
grant select, insert on table public.mind_admin_audit to service_role;

insert into public.mind_admin_users (user_id, display_name, role, active)
values ('a1fac65c-0417-4bd6-89f0-982f390073f3', 'Administrador inicial', 'administrador', true);

create or replace function public.mind_admin_dashboard_counts()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select jsonb_build_object(
    'sessions', (select count(*) from mind.sessions),
    'speakers', (select count(*) from mind.speakers),
    'spaces', (select count(*) from mind.locations where ativo),
    'booths', (select count(*) from mind.exhibitors where ativo),
    'active_offers', (select count(*) from mind.offers where ativo),
    'documents', (select count(*) from mind.knowledge_documents where ativo),
    'documents_pending', (
      select count(*)
      from mind.knowledge_documents d
      where d.ativo
        and (
          not exists (select 1 from mind.knowledge_chunks c where c.doc_id = d.id)
          or exists (
            select 1 from mind.knowledge_chunks c
            where c.doc_id = d.id and (c.stale or c.embedding is null)
          )
        )
    ),
    'unanswered', (
      select count(*)
      from concierge.perguntas_feitas
      where not respondida and not recusada
    ),
    'conversations_24h', (
      select count(*)
      from concierge.conversas
      where ultima_atividade >= now() - interval '24 hours'
    ),
    'sessions_incomplete', (
      select count(*)
      from mind.sessions
      where espaco_id is null or inicio is null or fim is null
    ),
    'spaces_without_directions', (
      select count(*)
      from mind.locations
      where ativo and nullif(btrim(como_chegar), '') is null
    ),
    'offers_without_checkout', (
      select count(*)
      from mind.offers
      where ativo and nullif(btrim(checkout_url), '') is null
    ),
    'generated_at', now()
  );
$function$;

revoke all on function public.mind_admin_dashboard_counts() from public, anon, authenticated;
grant execute on function public.mind_admin_dashboard_counts() to service_role;

comment on function public.mind_admin_dashboard_counts() is 'Service-role-only aggregate for the Mind Agent admin dashboard.';
