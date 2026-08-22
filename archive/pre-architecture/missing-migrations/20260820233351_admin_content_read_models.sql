create table if not exists public.mind_admin_editorial (
  resource text not null check (resource in ('sessions','speakers')),
  record_id uuid not null,
  status text not null default 'rascunho' check (status in ('rascunho','em_revisao','publicado','arquivado')),
  published_at timestamptz,
  published_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (resource, record_id)
);

create table if not exists public.mind_admin_event_details (
  event_id uuid primary key references mind.events(id) on delete cascade,
  descricao text not null default '',
  regra_reserva text not null default '',
  regra_vagas text not null default '',
  locais_candidatos jsonb not null default '[]'::jsonb check (jsonb_typeof(locais_candidatos) = 'array'),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.mind_admin_editorial enable row level security;
alter table public.mind_admin_event_details enable row level security;
revoke all on public.mind_admin_editorial from public, anon, authenticated;
revoke all on public.mind_admin_event_details from public, anon, authenticated;
grant select, insert, update on public.mind_admin_editorial to service_role;
grant select, insert, update on public.mind_admin_event_details to service_role;

comment on table public.mind_admin_editorial is 'Editorial workflow sidecar for Mind Agent admin resources.';
comment on table public.mind_admin_event_details is 'Admin-only event fields not present in the operational event table.';

insert into public.mind_admin_editorial (resource, record_id, status, published_at)
select 'sessions', id, 'publicado', atualizado_em from mind.sessions
on conflict (resource, record_id) do nothing;

insert into public.mind_admin_editorial (resource, record_id, status, published_at)
select 'speakers', id, 'publicado', atualizado_em from mind.speakers
on conflict (resource, record_id) do nothing;

insert into public.mind_admin_event_details (
  event_id, descricao, regra_reserva, regra_vagas, locais_candidatos
)
select
  e.id,
  '',
  coalesce((
    select string_agg(r.texto, E'\n\n' order by r.prioridade, r.chave)
    from mind.event_rules r
    where r.event_id = e.id and r.ativo
      and r.aplica_em && array['reserva','reservar','assento']::text[]
  ), ''),
  coalesce((
    select string_agg(r.texto, E'\n\n' order by r.prioridade, r.chave)
    from mind.event_rules r
    where r.event_id = e.id and r.ativo
      and r.aplica_em && array['sem_vaga','reservar','reserva']::text[]
  ), ''),
  jsonb_build_array(
    jsonb_build_object('valor', e.local, 'origem', 'Cadastro oficial do evento'),
    jsonb_build_object('valor', 'São Paulo Expo', 'origem', 'Regra logística ainda divergente')
  )
from mind.events e
where e.slug = 'mind-summit-2026'
on conflict (event_id) do nothing;

create or replace function public.mind_admin_read_resource(
  p_resource text,
  p_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, mind
as $$
declare
  v_result jsonb;
begin
  if p_resource = 'event' then
    select coalesce(jsonb_agg(x.obj order by x.nome), '[]'::jsonb)
    into v_result
    from (
      select e.nome,
        jsonb_build_object(
          'id', e.id::text,
          'criadoEm', coalesce(d.created_at, e.atualizado_em),
          'atualizadoEm', greatest(e.atualizado_em, coalesce(d.updated_at, e.atualizado_em)),
          'atualizadoPor', d.updated_by::text,
          'nome', e.nome,
          'slug', e.slug,
          'dataInicio', coalesce((select min(x) from unnest(e.dias) x)::text, ''),
          'dataFim', coalesce((select max(x) from unnest(e.dias) x)::text, ''),
          'local', coalesce(e.local, ''),
          'cidade', coalesce(e.cidade, ''),
          'fusoHorario', e.fuso,
          'descricao', coalesce(d.descricao, ''),
          'regraReserva', coalesce(d.regra_reserva, ''),
          'regraVagas', coalesce(d.regra_vagas, ''),
          'ativo', e.ativo,
          'locaisCandidatos', coalesce(d.locais_candidatos, '[]'::jsonb)
        ) obj
      from mind.events e
      left join public.mind_admin_event_details d on d.event_id = e.id
      where p_id is null or e.id = p_id
    ) x;

  elsif p_resource = 'sessions' then
    select coalesce(jsonb_agg(x.obj order by x.dia, x.inicio, x.titulo), '[]'::jsonb)
    into v_result
    from (
      select s.dia, s.inicio, s.titulo,
        jsonb_build_object(
          'id', s.id::text,
          'criadoEm', coalesce(ed.created_at, s.atualizado_em),
          'atualizadoEm', greatest(s.atualizado_em, coalesce(ed.updated_at, s.atualizado_em)),
          'atualizadoPor', ed.updated_by::text,
          'status', coalesce(ed.status, 'rascunho'),
          'publicadoEm', ed.published_at,
          'publicadoPor', ed.published_by::text,
          'titulo', s.titulo,
          'descricao', coalesce(s.descricao, ''),
          'dia', s.dia::text,
          'inicio', to_char(s.inicio at time zone coalesce(e.fuso, 'America/Sao_Paulo'), 'HH24:MI'),
          'fim', case when s.fim is null then null else to_char(s.fim at time zone coalesce(e.fuso, 'America/Sao_Paulo'), 'HH24:MI') end,
          'espacoId', s.espaco_id::text,
          'tipo', case when s.tipo = 'em-curadoria' then 'em_curadoria' else coalesce(s.tipo, 'palestra') end,
          'formato', coalesce(s.formato, 'presencial'),
          'trilhas', to_jsonb(coalesce(s.trilhas, '{}'::text[])),
          'temas', coalesce(s.topicos_aprendizado, '[]'::jsonb),
          'palestranteIds', coalesce((
            select jsonb_agg(ss.palestrante_id::text order by sp.nome)
            from mind.session_speakers ss join mind.speakers sp on sp.id = ss.palestrante_id
            where ss.sessao_id = s.id
          ), '[]'::jsonb),
          'quemTexto', coalesce((
            select string_agg(sp.nome, ', ' order by sp.nome)
            from mind.session_speakers ss join mind.speakers sp on sp.id = ss.palestrante_id
            where ss.sessao_id = s.id
          ), ''),
          'necessitaReserva', s.precisa_reserva,
          'vagasTotais', s.vagas_total,
          'vagasDisponiveis', s.vagas_disponiveis,
          'nivel', s.nivel,
          'resultadosEsperados', coalesce(s.resultados, '[]'::jsonb)
        ) obj
      from mind.sessions s
      left join mind.events e on e.id = s.event_id
      left join public.mind_admin_editorial ed on ed.resource = 'sessions' and ed.record_id = s.id
      where p_id is null or s.id = p_id
    ) x;

  elsif p_resource = 'speakers' then
    select coalesce(jsonb_agg(x.obj order by x.nome), '[]'::jsonb)
    into v_result
    from (
      select sp.nome,
        jsonb_build_object(
          'id', sp.id::text,
          'criadoEm', coalesce(ed.created_at, sp.atualizado_em),
          'atualizadoEm', greatest(sp.atualizado_em, coalesce(ed.updated_at, sp.atualizado_em)),
          'atualizadoPor', ed.updated_by::text,
          'status', coalesce(ed.status, 'rascunho'),
          'publicadoEm', ed.published_at,
          'publicadoPor', ed.published_by::text,
          'nome', sp.nome,
          'cargo', coalesce(sp.cargo, ''),
          'organizacao', coalesce(sp.organizacao, ''),
          'biografia', coalesce(sp.bio, ''),
          'foto', coalesce(sp.foto_url, sp.asset_path, ''),
          'temas', to_jsonb(coalesce(sp.temas, '{}'::text[])),
          'destaque', sp.destaque,
          'sessaoIds', coalesce((
            select jsonb_agg(ss.sessao_id::text order by ss.sessao_id)
            from mind.session_speakers ss where ss.palestrante_id = sp.id
          ), '[]'::jsonb)
        ) obj
      from mind.speakers sp
      left join public.mind_admin_editorial ed on ed.resource = 'speakers' and ed.record_id = sp.id
      where p_id is null or sp.id = p_id
    ) x;

  elsif p_resource = 'spaces' then
    select coalesce(jsonb_agg(x.obj order by x.nome), '[]'::jsonb)
    into v_result
    from (
      select l.nome,
        jsonb_build_object(
          'id', l.id::text,
          'criadoEm', l.atualizado_em,
          'atualizadoEm', l.atualizado_em,
          'atualizadoPor', null,
          'nome', l.nome,
          'slug', coalesce(l.slug, ''),
          'tipo', coalesce(l.tipo, 'servico'),
          'aliases', to_jsonb(coalesce(l.aliases, '{}'::text[])),
          'descricao', coalesce(l.descricao, ''),
          'comoChegar', coalesce(l.como_chegar, ''),
          'localPrincipal', coalesce(v.nome, ''),
          'espacoPaiId', l.parent_id::text,
          'andar', coalesce(l.andar, ''),
          'coordenadaX', case when l.coordenadas_mapa->>'x_percent' ~ '^-?[0-9]+([.][0-9]+)?$' then (l.coordenadas_mapa->>'x_percent')::numeric else null end,
          'coordenadaY', case when l.coordenadas_mapa->>'y_percent' ~ '^-?[0-9]+([.][0-9]+)?$' then (l.coordenadas_mapa->>'y_percent')::numeric else null end,
          'acessivel', coalesce((l.acessibilidade->>'acessivel')::boolean, false),
          'observacaoAcessibilidade', coalesce(l.acessibilidade->>'observacao', case when l.acessibilidade->>'verificada' = 'false' then 'Acessibilidade ainda não verificada.' else '' end),
          'ativo', l.ativo
        ) obj
      from mind.locations l
      left join mind.venues v on v.id = l.venue_id
      where p_id is null or l.id = p_id
    ) x;

  elsif p_resource = 'themes' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'codigo', t.codigo,
      'rotulo', case t.codigo
        when 'cultura' then 'Cultura'
        when 'dados_bem_estar' then 'Dados e bem-estar'
        when 'diversidade' then 'Diversidade'
        when 'felicidade' then 'Felicidade'
        when 'futuro_trabalho' then 'Futuro do trabalho'
        when 'lideranca_humana' then 'Liderança humana'
        when 'performance' then 'Performance'
        when 'regulacao' then 'Regulação'
        when 'saude_mental' then 'Saúde mental'
        when 'seguranca_psicologica' then 'Segurança psicológica'
        else initcap(replace(t.codigo, '_', ' ')) end,
      'descricao', ''
    ) order by t.codigo), '[]'::jsonb)
    into v_result
    from (
      select distinct jsonb_array_elements_text(s.topicos_aprendizado) codigo
      from mind.sessions s
    ) t;
  else
    raise exception using errcode = '22023', message = 'recurso_nao_suportado';
  end if;

  return v_result;
end;
$$;

revoke all on function public.mind_admin_read_resource(text, uuid) from public, anon, authenticated;
grant execute on function public.mind_admin_read_resource(text, uuid) to service_role;

