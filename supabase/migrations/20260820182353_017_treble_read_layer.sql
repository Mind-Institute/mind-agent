
create table if not exists mind.venues (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references mind.events(id) on delete cascade,
 slug text not null,
 nome text not null,
 endereco jsonb not null default '{}'::jsonb,
 transporte text,
 acessibilidade text,
 mapa_url text,
 ativo boolean not null default true,
 atualizado_em timestamptz not null default now(),
 unique(event_id,slug),
 check(jsonb_typeof(endereco)='object')
);
alter table mind.venues enable row level security;

alter table mind.locations add column if not exists venue_id uuid references mind.venues(id) on delete set null;
alter table mind.locations add column if not exists parent_id uuid references mind.locations(id) on delete set null;
alter table mind.locations add column if not exists slug text;
alter table mind.locations add column if not exists aliases text[] not null default '{}';
alter table mind.locations add column if not exists descricao text;
alter table mind.locations add column if not exists andar text;
alter table mind.locations add column if not exists coordenadas_mapa jsonb not null default '{}'::jsonb;
alter table mind.locations add column if not exists acessibilidade jsonb not null default '{}'::jsonb;
alter table mind.locations add column if not exists ativo boolean not null default true;
create unique index if not exists locations_event_slug_uq on mind.locations(event_id,slug) where slug is not null;
create index if not exists locations_venue_idx on mind.locations(venue_id);
create index if not exists locations_parent_idx on mind.locations(parent_id);
create index if not exists locations_event_tipo_idx on mind.locations(event_id,tipo,ativo);
create index if not exists locations_nome_trgm_idx on mind.locations using gin(nome gin_trgm_ops);

create table if not exists mind.exhibitors (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references mind.events(id) on delete cascade,
 location_id uuid references mind.locations(id) on delete set null,
 slug text not null,
 nome text not null,
 descricao text,
 categoria text,
 site_url text,
 contato jsonb not null default '{}'::jsonb,
 metadata jsonb not null default '{}'::jsonb,
 ativo boolean not null default true,
 atualizado_em timestamptz not null default now(),
 unique(event_id,slug),
 check(jsonb_typeof(contato)='object'),
 check(jsonb_typeof(metadata)='object')
);
create index if not exists exhibitors_event_location_idx on mind.exhibitors(event_id,location_id,ativo);
create index if not exists exhibitors_nome_trgm_idx on mind.exhibitors using gin(nome gin_trgm_ops);
alter table mind.exhibitors enable row level security;

create table if not exists mind.route_edges (
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references mind.events(id) on delete cascade,
 origem_location_id uuid not null references mind.locations(id) on delete cascade,
 destino_location_id uuid not null references mind.locations(id) on delete cascade,
 instrucoes text not null,
 distancia_metros integer,
 minutos_estimados integer,
 acessivel boolean not null default true,
 bidirecional boolean not null default true,
 ativo boolean not null default true,
 metadata jsonb not null default '{}'::jsonb,
 atualizado_em timestamptz not null default now(),
 unique(event_id,origem_location_id,destino_location_id),
 check(origem_location_id<>destino_location_id),
 check(distancia_metros is null or distancia_metros>=0),
 check(minutos_estimados is null or minutos_estimados>=0),
 check(jsonb_typeof(metadata)='object')
);
create index if not exists route_edges_origem_idx on mind.route_edges(event_id,origem_location_id,ativo);
create index if not exists route_edges_destino_idx on mind.route_edges(event_id,destino_location_id,ativo);
alter table mind.route_edges enable row level security;

create table if not exists mind.organization_content (
 id uuid primary key default gen_random_uuid(),
 event_id uuid references mind.events(id) on delete cascade,
 categoria text not null check(categoria in ('sobre','missao','historia','produto','faq','politica','contato','acessibilidade','transporte')),
 slug text not null,
 titulo text not null,
 corpo text not null,
 metadata jsonb not null default '{}'::jsonb,
 publico boolean not null default true,
 ativo boolean not null default true,
 valido_de timestamptz,
 valido_ate timestamptz,
 atualizado_em timestamptz not null default now(),
 unique(event_id,slug),
 check(valido_ate is null or valido_de is null or valido_ate>valido_de),
 check(jsonb_typeof(metadata)='object')
);
create unique index if not exists organization_content_global_slug_uq on mind.organization_content(slug) where event_id is null;
create index if not exists organization_content_lookup_idx on mind.organization_content(event_id,categoria,ativo,publico);
alter table mind.organization_content enable row level security;

create table if not exists mind.offers (
 id uuid primary key default gen_random_uuid(),
 event_id uuid references mind.events(id) on delete cascade,
 codigo text not null,
 nome text not null,
 descricao text,
 moeda char(3) not null default 'BRL',
 valor numeric(12,2),
 condicoes_pagamento text,
 checkout_url text,
 elegibilidade jsonb not null default '{}'::jsonb,
 publico boolean not null default true,
 ativo boolean not null default true,
 inicia_em timestamptz,
 encerra_em timestamptz,
 atualizado_em timestamptz not null default now(),
 unique(event_id,codigo),
 check(valor is null or valor>=0),
 check(encerra_em is null or inicia_em is null or encerra_em>inicia_em),
 check(jsonb_typeof(elegibilidade)='object')
);
create unique index if not exists offers_global_codigo_uq on mind.offers(codigo) where event_id is null;
create index if not exists offers_ativas_idx on mind.offers(event_id,ativo,inicia_em,encerra_em);
alter table mind.offers enable row level security;

revoke all on mind.venues,mind.exhibitors,mind.route_edges,mind.organization_content,mind.offers from anon,authenticated;
revoke all on mind.locations from anon,authenticated;
grant all on mind.venues,mind.exhibitors,mind.route_edges,mind.organization_content,mind.offers to service_role;

create or replace function api.treble_event_bundle(p_event_slug text default 'mind-summit-2026')
returns jsonb
language sql stable security definer
set search_path=pg_catalog,mind
as $$
with ev as (
 select e.* from mind.events e where e.slug=p_event_slug and e.ativo limit 1
)
select jsonb_build_object(
 'event',(select jsonb_build_object(
   'slug',e.slug,'name',e.nome,'dates',e.dias,'location',e.local,'city',e.cidade,'timezone',e.fuso
 ) from ev e),
 'venues',coalesce((select jsonb_agg(jsonb_build_object(
   'slug',v.slug,'name',v.nome,'address',v.endereco,'transport',v.transporte,
   'accessibility',v.acessibilidade,'map_url',v.mapa_url
 ) order by v.nome) from mind.venues v join ev e on e.id=v.event_id where v.ativo),'[]'::jsonb),
 'locations',coalesce((select jsonb_agg(jsonb_build_object(
   'slug',l.slug,'name',l.nome,'type',l.tipo,'venue',v.nome,'parent',p.slug,
   'aliases',l.aliases,'description',l.descricao,'floor',l.andar,
   'how_to_get_there',l.como_chegar,'map_coordinates',l.coordenadas_mapa,
   'accessibility',l.acessibilidade
 ) order by l.tipo,l.nome)
 from mind.locations l join ev e on e.id=l.event_id
 left join mind.venues v on v.id=l.venue_id
 left join mind.locations p on p.id=l.parent_id where l.ativo),'[]'::jsonb),
 'program',coalesce((select jsonb_agg(jsonb_build_object(
   'id',s.id,'title',s.titulo,'description',s.descricao,'date',s.dia,
   'starts_at',s.inicio,'ends_at',s.fim,'location_slug',l.slug,'stage',l.nome,
   'type',s.tipo,'tracks',s.trilhas,'requires_reservation',s.precisa_reserva,
   'available_places',s.vagas_disponiveis,
   'speakers',coalesce((select jsonb_agg(jsonb_build_object(
      'name',sp.nome,'role',sp.cargo,'organization',sp.organizacao,'bio',sp.bio,'photo_url',sp.foto_url
    ) order by sp.nome)
    from mind.session_speakers ss join mind.speakers sp on sp.id=ss.palestrante_id
    where ss.sessao_id=s.id),'[]'::jsonb)
 ) order by s.inicio)
 from mind.sessions s join ev e on e.id=s.event_id
 left join mind.locations l on l.id=s.espaco_id),'[]'::jsonb),
 'speakers',coalesce((select jsonb_agg(distinct jsonb_build_object(
   'name',sp.nome,'role',sp.cargo,'organization',sp.organizacao,'bio',sp.bio,'photo_url',sp.foto_url
 ))
 from mind.speakers sp where exists(
   select 1 from mind.session_speakers ss join mind.sessions s on s.id=ss.sessao_id
   join ev e on e.id=s.event_id where ss.palestrante_id=sp.id
 )),'[]'::jsonb),
 'exhibitors',coalesce((select jsonb_agg(jsonb_build_object(
   'slug',x.slug,'name',x.nome,'description',x.descricao,'category',x.categoria,
   'location_slug',l.slug,'location',l.nome,'website_url',x.site_url
 ) order by x.nome)
 from mind.exhibitors x join ev e on e.id=x.event_id
 left join mind.locations l on l.id=x.location_id where x.ativo),'[]'::jsonb),
 'mind',coalesce((select jsonb_agg(jsonb_build_object(
   'category',o.categoria,'slug',o.slug,'title',o.titulo,'body',o.corpo,'metadata',o.metadata
 ) order by o.categoria,o.titulo)
 from mind.organization_content o
 where o.ativo and o.publico and(o.event_id is null or o.event_id=(select id from ev))
 and(o.valido_de is null or o.valido_de<=now()) and(o.valido_ate is null or o.valido_ate>now())),'[]'::jsonb),
 'offers',coalesce((select jsonb_agg(jsonb_build_object(
   'code',o.codigo,'name',o.nome,'description',o.descricao,'currency',o.moeda,
   'amount',o.valor,'payment_terms',o.condicoes_pagamento,'checkout_url',o.checkout_url,
   'eligibility',o.elegibilidade
 ) order by o.nome)
 from mind.offers o
 where o.ativo and o.publico and(o.event_id is null or o.event_id=(select id from ev))
 and(o.inicia_em is null or o.inicia_em<=now()) and(o.encerra_em is null or o.encerra_em>now())),'[]'::jsonb)
);
$$;

create or replace function api.treble_find_location(p_event_slug text,p_query text)
returns jsonb
language sql stable security definer
set search_path=pg_catalog,mind,public
as $$
with ranked as (
 select l.*,v.nome venue_nome,p.nome parent_nome,greatest(
  similarity(lower(l.nome),lower(left(trim(p_query),120))),
  coalesce((select max(similarity(lower(a),lower(left(trim(p_query),120)))) from unnest(l.aliases)a),0)
 ) score
 from mind.locations l join mind.events e on e.id=l.event_id
 left join mind.venues v on v.id=l.venue_id left join mind.locations p on p.id=l.parent_id
 where e.slug=p_event_slug and e.ativo and l.ativo and length(trim(p_query)) between 2 and 120
 and(lower(l.nome)%lower(trim(p_query)) or lower(l.nome) like '%'||lower(trim(p_query))||'%'
   or exists(select 1 from unnest(l.aliases)a where lower(a)%lower(trim(p_query))))
 order by score desc,l.nome limit 5
)
select coalesce(jsonb_agg(jsonb_build_object(
 'slug',r.slug,'name',r.nome,'type',r.tipo,'venue',r.venue_nome,'parent',r.parent_nome,
 'floor',r.andar,'description',r.descricao,'how_to_get_there',r.como_chegar,
 'accessibility',r.acessibilidade,'score',round(r.score::numeric,3)
) order by r.score desc),'[]'::jsonb) from ranked r;
$$;

create or replace function api.treble_route(
 p_event_slug text,p_from_slug text,p_to_slug text,p_accessible boolean default false
) returns jsonb
language sql stable security definer
set search_path=pg_catalog,mind
as $$
with ev as(select id from mind.events where slug=p_event_slug and ativo limit 1),
src as(select l.id,l.nome from mind.locations l join ev on ev.id=l.event_id where l.slug=p_from_slug and l.ativo limit 1),
dst as(select l.id,l.nome from mind.locations l join ev on ev.id=l.event_id where l.slug=p_to_slug and l.ativo limit 1),
edge as(
 select r.*,s.nome origem_nome,d.nome destino_nome from mind.route_edges r
 join src s on(r.origem_location_id=s.id or(r.bidirecional and r.destino_location_id=s.id))
 join dst d on(r.destino_location_id=d.id or(r.bidirecional and r.origem_location_id=d.id))
 where r.ativo and(not p_accessible or r.acessivel) limit 1
)
select coalesce((select jsonb_build_object(
 'found',true,'from',origem_nome,'to',destino_nome,'instructions',instrucoes,
 'distance_meters',distancia_metros,'estimated_minutes',minutos_estimados,'accessible',acessivel
) from edge),jsonb_build_object('found',false));
$$;

revoke all on function api.treble_event_bundle(text) from public;
revoke all on function api.treble_find_location(text,text) from public;
revoke all on function api.treble_route(text,text,text,boolean) from public;
grant execute on function api.treble_event_bundle(text) to anon,authenticated,service_role;
grant execute on function api.treble_find_location(text,text) to anon,authenticated,service_role;
grant execute on function api.treble_route(text,text,text,boolean) to anon,authenticated,service_role;

