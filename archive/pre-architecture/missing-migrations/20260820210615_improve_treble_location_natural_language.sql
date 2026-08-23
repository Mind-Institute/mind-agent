
update mind.locations
set aliases = (
  select array_agg(distinct x order by x)
  from unnest(coalesce(aliases, '{}'::text[]) || case nome
    when 'Arena Mind' then array['palco mind','arena principal','palco principal']
    when 'Arena Sextante' then array['palco sextante']
    when 'Arena Top Voice' then array['palco top voice','arena linkedin','palco linkedin']
    else '{}'::text[]
  end) as x
)
where nome in ('Arena Mind','Arena Sextante','Arena Top Voice');

create or replace function api.treble_find_location(p_event_slug text, p_query text)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, mind, public
as $function$
with input as (
  select
    lower(trim(left(p_query, 120))) as raw_query,
    coalesce((
      select string_agg(token, ' ' order by ord)
      from regexp_split_to_table(lower(trim(left(p_query, 120))), '[^[:alnum:]]+') with ordinality as t(token, ord)
      where token <> ''
        and token <> all(array[
          'onde','fica','ficam','como','chego','chegar','vou','ir','para','até',
          'o','a','os','as','um','uma','no','na','nos','nas','do','da','dos','das',
          'palco','arena','sala','estande','estandes','local','localização'
        ])
    ), '') as search_query
),
ranked as (
  select
    l.*,
    v.nome as venue_nome,
    p.nome as parent_nome,
    greatest(
      similarity(lower(l.nome), i.raw_query),
      case when length(i.search_query) >= 2 then similarity(lower(l.nome), i.search_query) else 0 end,
      coalesce((
        select max(greatest(
          similarity(lower(a), i.raw_query),
          case when length(i.search_query) >= 2 then similarity(lower(a), i.search_query) else 0 end
        ))
        from unnest(l.aliases) a
      ), 0)
    ) as score
  from mind.locations l
  join mind.events e on e.id = l.event_id
  left join mind.venues v on v.id = l.venue_id
  left join mind.locations p on p.id = l.parent_id
  cross join input i
  where e.slug = p_event_slug
    and e.ativo
    and l.ativo
    and length(trim(p_query)) between 2 and 120
    and (
      lower(l.nome) % i.raw_query
      or lower(l.nome) like '%' || i.raw_query || '%'
      or (length(i.search_query) >= 2 and (
        lower(l.nome) % i.search_query
        or lower(l.nome) like '%' || i.search_query || '%'
      ))
      or exists (
        select 1
        from unnest(l.aliases) a
        where lower(a) % i.raw_query
          or i.raw_query like '%' || lower(a) || '%'
          or (length(i.search_query) >= 2 and (
            lower(a) % i.search_query
            or lower(a) like '%' || i.search_query || '%'
            or i.search_query like '%' || lower(a) || '%'
          ))
      )
    )
  order by score desc, l.nome
  limit 5
)
select coalesce(jsonb_agg(jsonb_build_object(
  'slug', r.slug,
  'name', r.nome,
  'type', r.tipo,
  'venue', r.venue_nome,
  'parent', r.parent_nome,
  'floor', r.andar,
  'description', r.descricao,
  'how_to_get_there', r.como_chegar,
  'accessibility', r.acessibilidade,
  'score', round(r.score::numeric, 3)
) order by r.score desc), '[]'::jsonb)
from ranked r;
$function$;

revoke all on function api.treble_find_location(text, text) from public;
grant execute on function api.treble_find_location(text, text) to anon, authenticated, service_role;
