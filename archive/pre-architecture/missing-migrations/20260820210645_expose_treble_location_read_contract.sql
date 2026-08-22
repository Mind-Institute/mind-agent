
create or replace function public.treble_find_location(p_event_slug text, p_query text)
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog, api
as $function$
  select api.treble_find_location(p_event_slug, p_query);
$function$;

revoke all on function public.treble_find_location(text, text) from public;
grant execute on function public.treble_find_location(text, text) to anon, authenticated, service_role;
