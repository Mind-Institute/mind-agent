
create table if not exists mind.organization_content (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references mind.events(id) on delete cascade,
  category text not null check (category in ('about','mission','history','product','faq','policy','contact','accessibility','transport')),
  slug text not null,
  title text not null,
  body text not null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  is_public boolean not null default true,
  active boolean not null default true,
  valid_from timestamptz,
  valid_until timestamptz,
  updated_at timestamptz not null default now(),
  constraint organization_content_validity check (valid_until is null or valid_from is null or valid_until > valid_from),
  unique (event_id, slug)
);
create unique index if not exists organization_content_global_slug_uq
  on mind.organization_content(slug) where event_id is null;
create index if not exists organization_content_lookup_idx
  on mind.organization_content(event_id, category, active, is_public);
alter table mind.organization_content enable row level security;

alter table mind.locations add column if not exists parent_id uuid references mind.locations(id) on delete set null;
alter table mind.locations add column if not exists slug text;
alter table mind.locations add column if not exists aliases text[] not null default '{}';
alter table mind.locations add column if not exists description text;
alter table mind.locations add column if not exists floor_label text;
alter table mind.locations add column if not exists map_coordinates jsonb not null default '{}'::jsonb;
alter table mind.locations add column if not exists accessibility jsonb not null default '{}'::jsonb;
alter table mind.locations add column if not exists active boolean not null default true;
create unique index if not exists locations_event_slug_uq on mind.locations(event_id, slug) where slug is not null;
create index if not exists locations_parent_idx on mind.locations(parent_id);
create index if not exists locations_event_type_idx on mind.locations(event_id, tipo, active);
create index if not exists locations_name_trgm_idx on mind.locations using gin (nome gin_trgm_ops);

create table if not exists mind.exhibitors (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references mind.events(id) on delete cascade,
  location_id uuid references mind.locations(id) on delete set null,
  slug text not null,
  name text not null,
  description text,
  category text,
  website_url text,
  contact jsonb not null default '{}'::jsonb check (jsonb_typeof(contact)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique(event_id, slug)
);
create index if not exists exhibitors_event_location_idx on mind.exhibitors(event_id, location_id, active);
create index if not exists exhibitors_name_trgm_idx on mind.exhibitors using gin (name gin_trgm_ops);
alter table mind.exhibitors enable row level security;

create table if not exists mind.route_edges (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references mind.events(id) on delete cascade,
  from_location_id uuid not null references mind.locations(id) on delete cascade,
  to_location_id uuid not null references mind.locations(id) on delete cascade,
  instructions text not null,
  distance_meters integer check (distance_meters is null or distance_meters >= 0),
  estimated_minutes integer check (estimated_minutes is null or estimated_minutes >= 0),
  accessible boolean not null default true,
  bidirectional boolean not null default true,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  updated_at timestamptz not null default now(),
  constraint route_edges_distinct_locations check (from_location_id <> to_location_id),
  unique(event_id, from_location_id, to_location_id)
);
create index if not exists route_edges_from_idx on mind.route_edges(event_id, from_location_id, active);
create index if not exists route_edges_to_idx on mind.route_edges(event_id, to_location_id, active);
alter table mind.route_edges enable row level security;

create table if not exists mind.offers (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references mind.events(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  currency char(3) not null default 'BRL',
  amount numeric(12,2) check (amount is null or amount >= 0),
  payment_terms text,
  checkout_url text,
  eligibility jsonb not null default '{}'::jsonb check (jsonb_typeof(eligibility)='object'),
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint offers_window check (ends_at is null or starts_at is null or ends_at > starts_at),
  unique(event_id, code)
);
create unique index if not exists offers_global_code_uq on mind.offers(code) where event_id is null;
create index if not exists offers_active_idx on mind.offers(event_id, active, starts_at, ends_at);
alter table mind.offers enable row level security;

create table if not exists concierge.integration_events (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  external_event_id text not null,
  event_type text not null,
  aggregate_type text,
  aggregate_external_id text,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'received' check (status in ('received','processing','processed','retrying','failed','ignored')),
  attempts integer not null default 0 check (attempts >= 0),
  error text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  next_retry_at timestamptz,
  unique(source, external_event_id)
);
create index if not exists integration_events_work_idx
  on concierge.integration_events(status, next_retry_at, received_at);
alter table concierge.integration_events enable row level security;

create or replace function api.event_guide(p_event text default null)
returns jsonb
language sql stable security definer
set search_path = pg_catalog, mind
as $$
  with ev as (
    select e.* from mind.events e
    where e.ativo and (p_event is null or e.slug=p_event)
    order by e.atualizado_em desc limit 1
  )
  select jsonb_build_object(
    'event', (select to_jsonb(e) - 'id' from ev e),
    'locations', coalesce((select jsonb_agg(jsonb_build_object(
      'slug',l.slug,'name',l.nome,'type',l.tipo,'parent_slug',p.slug,
      'description',l.description,'how_to_get_there',l.como_chegar,
      'floor',l.floor_label,'accessibility',l.accessibility
    ) order by l.tipo,l.nome)
      from mind.locations l join ev e on e.id=l.event_id
      left join mind.locations p on p.id=l.parent_id where l.active),'[]'::jsonb),
    'sessions', coalesce((select jsonb_agg(jsonb_build_object(
      'title',s.titulo,'description',s.descricao,'date',s.dia,
      'starts_at',s.inicio,'ends_at',s.fim,'stage',l.nome,'type',s.tipo,'tracks',s.trilhas
    ) order by s.inicio)
      from mind.sessions s join ev e on e.id=s.event_id
      left join mind.locations l on l.id=s.espaco_id),'[]'::jsonb),
    'speakers', coalesce((select jsonb_agg(jsonb_build_object(
      'name',sp.nome,'role',sp.cargo,'organization',sp.organizacao,'bio',sp.bio,'photo_url',sp.foto_url
    ) order by sp.nome)
      from mind.speakers sp where exists (
        select 1 from mind.session_speakers ss join mind.sessions s on s.id=ss.sessao_id
        join ev e on e.id=s.event_id where ss.palestrante_id=sp.id
      )),'[]'::jsonb),
    'exhibitors', coalesce((select jsonb_agg(jsonb_build_object(
      'slug',x.slug,'name',x.name,'description',x.description,'category',x.category,
      'location',l.nome,'website_url',x.website_url
    ) order by x.name)
      from mind.exhibitors x join ev e on e.id=x.event_id
      left join mind.locations l on l.id=x.location_id where x.active),'[]'::jsonb),
    'institutional', coalesce((select jsonb_agg(jsonb_build_object(
      'category',o.category,'slug',o.slug,'title',o.title,'body',o.body,'metadata',o.metadata
    ) order by o.category,o.title)
      from mind.organization_content o
      where o.active and o.is_public and (o.event_id is null or o.event_id=(select id from ev))
        and (o.valid_from is null or o.valid_from<=now())
        and (o.valid_until is null or o.valid_until>now())),'[]'::jsonb),
    'offers', coalesce((select jsonb_agg(jsonb_build_object(
      'code',o.code,'name',o.name,'description',o.description,'currency',o.currency,
      'amount',o.amount,'payment_terms',o.payment_terms,'checkout_url',o.checkout_url
    ) order by o.name)
      from mind.offers o
      where o.active and (o.event_id is null or o.event_id=(select id from ev))
        and (o.starts_at is null or o.starts_at<=now())
        and (o.ends_at is null or o.ends_at>now())),'[]'::jsonb)
  );
$$;

create or replace function api.find_location(p_event text, p_query text)
returns jsonb
language sql stable security definer
set search_path = pg_catalog, mind, public
as $$
  with ev as (select id from mind.events where ativo and slug=p_event limit 1),
  ranked as (
    select l.*, greatest(
      similarity(lower(l.nome),lower(left(p_query,120))),
      coalesce((select max(similarity(lower(a),lower(left(p_query,120)))) from unnest(l.aliases) a),0)
    ) score
    from mind.locations l join ev on ev.id=l.event_id
    where l.active and length(trim(p_query)) between 2 and 120
      and (lower(l.nome) % lower(p_query) or exists(select 1 from unnest(l.aliases) a where lower(a) % lower(p_query))
        or lower(l.nome) like '%'||lower(p_query)||'%')
    order by score desc,l.nome limit 5
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'slug',r.slug,'name',r.nome,'type',r.tipo,'description',r.description,
    'how_to_get_there',r.como_chegar,'floor',r.floor_label,'accessibility',r.accessibility,
    'parent',(select p.nome from mind.locations p where p.id=r.parent_id),
    'score',round(r.score::numeric,3)
  ) order by r.score desc),'[]'::jsonb) from ranked r;
$$;

create or replace function api.route_to_location(p_event text, p_from text, p_to text, p_accessible boolean default false)
returns jsonb
language sql stable security definer
set search_path = pg_catalog, mind
as $$
  with ev as (select id from mind.events where ativo and slug=p_event limit 1),
  src as (select l.id,l.nome from mind.locations l join ev on ev.id=l.event_id where l.active and l.slug=p_from limit 1),
  dst as (select l.id,l.nome from mind.locations l join ev on ev.id=l.event_id where l.active and l.slug=p_to limit 1),
  edge as (
    select r.*,s.nome from_name,d.nome to_name from mind.route_edges r
    join src s on (r.from_location_id=s.id or (r.bidirectional and r.to_location_id=s.id))
    join dst d on (r.to_location_id=d.id or (r.bidirectional and r.from_location_id=d.id))
    where r.active and (not p_accessible or r.accessible) limit 1
  )
  select coalesce((select jsonb_build_object(
    'from',from_name,'to',to_name,'instructions',instructions,'distance_meters',distance_meters,
    'estimated_minutes',estimated_minutes,'accessible',accessible
  ) from edge),jsonb_build_object('found',false));
$$;

create or replace function api.session_context(p_token text)
returns jsonb
language sql stable security definer
set search_path = pg_catalog, mind, concierge, api
as $$
  with person as (select api.quem_sou(p_token) id)
  select case when (select id from person) is null then jsonb_build_object('authenticated',false)
  else jsonb_build_object(
    'authenticated',true,
    'profile',(select jsonb_build_object('name',p.nome,'company',p.empresa,'role',p.cargo,'language',p.idioma)
      from mind.people p where p.id=(select id from person)),
    'registrations',coalesce((select jsonb_agg(jsonb_build_object(
      'event_slug',e.slug,'event_name',e.nome,'ticket_category',r.ticket_category,'status',r.status))
      from mind.registrations r join mind.events e on e.id=r.event_id where r.person_id=(select id from person)),'[]'::jsonb),
    'context',(select to_jsonb(c)-'participante_id' from concierge.participante_contexto c where c.participante_id=(select id from person)),
    'facts',coalesce((select jsonb_agg(jsonb_build_object(
      'type',m.tipo,'key',m.chave,'value',m.valor,'confidence',m.confianca,'source',m.origem,'status',m.status))
      from concierge.participante_memoria m where m.participante_id=(select id from person)
        and m.status='ativo' and (m.valido_ate is null or m.valido_ate>now())),'[]'::jsonb)
  ) end;
$$;

revoke all on function api.event_guide(text) from public;
revoke all on function api.find_location(text,text) from public;
revoke all on function api.route_to_location(text,text,text,boolean) from public;
revoke all on function api.session_context(text) from public;
grant execute on function api.event_guide(text) to anon, authenticated, service_role;
grant execute on function api.find_location(text,text) to anon, authenticated, service_role;
grant execute on function api.route_to_location(text,text,text,boolean) to anon, authenticated, service_role;
grant execute on function api.session_context(text) to service_role;

revoke all on mind.organization_content, mind.exhibitors, mind.route_edges, mind.offers from anon, authenticated;
revoke all on concierge.integration_events from anon, authenticated;
grant all on mind.organization_content, mind.exhibitors, mind.route_edges, mind.offers to service_role;
grant all on concierge.integration_events to service_role;

