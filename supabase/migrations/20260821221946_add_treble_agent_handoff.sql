
create or replace function public.mindagent_treble_mark_handoff(
  p_session_external_id text,
  p_reason text default null
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'treble'
as $function$
begin
  update treble.conversations
  set needs_human = true,
      variables = coalesce(variables, '{}'::jsonb) || jsonb_build_object(
        'handoff_reason', left(coalesce(p_reason, 'solicitado_pelo_usuario'), 120),
        'handoff_requested_at', now()
      ),
      ultima_atividade = now()
  where session_external_id = btrim(p_session_external_id);

  return found;
end;
$function$;

revoke execute on function public.mindagent_treble_mark_handoff(text, text)
  from public, anon, authenticated;
grant execute on function public.mindagent_treble_mark_handoff(text, text)
  to service_role;

