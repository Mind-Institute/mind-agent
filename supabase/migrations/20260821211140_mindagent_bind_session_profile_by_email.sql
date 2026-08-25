
create unique index if not exists people_email_normalized_uidx
  on mind.people ((lower(btrim(email))))
  where email is not null and btrim(email) <> '';

create or replace function public.mindagent_chat_bind_identity(
  p_auth_user_id uuid,
  p_session_id uuid,
  p_conversation_id uuid,
  p_token_hash text,
  p_email text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, mind, concierge
as $function$
declare
  v_session concierge.agent_sessions%rowtype;
  v_person mind.people%rowtype;
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_profile jsonb;
begin
  if length(v_email) < 5
     or length(v_email) > 320
     or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$' then
    return jsonb_build_object('found', false, 'conflict', false, 'reason', 'invalid_email');
  end if;

  select *
  into v_session
  from concierge.agent_sessions
  where id = p_session_id
    and auth_user_id = p_auth_user_id
    and token_hash = p_token_hash
    and expira_em > now()
  for update;

  if not found then
    raise exception using errcode = '28000', message = 'invalid_chat_session';
  end if;

  if not exists (
    select 1
    from concierge.conversas c
    where c.id = p_conversation_id
      and c.dispositivo_id = v_session.dispositivo_id
      and c.encerrada_em is null
  ) then
    raise exception using errcode = '28000', message = 'invalid_chat_conversation';
  end if;

  select *
  into v_person
  from mind.people p
  where lower(btrim(p.email)) = v_email
  limit 1;

  if not found then
    return jsonb_build_object('found', false, 'conflict', false, 'reason', 'not_found');
  end if;

  if v_session.participante_id is not null
     and v_session.participante_id <> v_person.id then
    return jsonb_build_object('found', false, 'conflict', true, 'reason', 'different_participant');
  end if;

  update concierge.agent_sessions
  set participante_id = v_person.id,
      origem_identidade = 'yazo_url',
      confianca = 'baixa',
      expira_em = least(expira_em, now() + interval '12 hours'),
      ultima_atividade = now()
  where id = v_session.id;

  update concierge.conversas
  set participante_id = v_person.id,
      ultima_atividade = now()
  where id = p_conversation_id
    and dispositivo_id = v_session.dispositivo_id;

  select jsonb_build_object(
    'participant_id', v_person.id,
    'name', v_person.nome,
    'role', v_person.cargo,
    'company', v_person.empresa,
    'language', v_person.idioma,
    'interests', coalesce(pc.temas_relevantes, '[]'::jsonb)
  )
  into v_profile
  from (select 1) seed
  left join concierge.participante_contexto pc
    on pc.participante_id = v_person.id;

  return jsonb_build_object(
    'found', true,
    'conflict', false,
    'profile', coalesce(v_profile, '{}'::jsonb),
    'identity_verified', false,
    'identity_source', 'yazo_url',
    'identity_confidence', 'baixa'
  );
end;
$function$;

revoke all on function public.mindagent_chat_bind_identity(uuid, uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.mindagent_chat_bind_identity(uuid, uuid, uuid, text, text)
  to service_role;

create or replace function public.mindagent_chat_get_context(
  p_auth_user_id uuid,
  p_session_id uuid,
  p_conversation_id uuid,
  p_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, mind, concierge
as $function$
declare
  v_session concierge.agent_sessions%rowtype;
  v_conversation concierge.conversas%rowtype;
  v_history jsonb := '[]'::jsonb;
  v_interests jsonb := '[]'::jsonb;
  v_profile jsonb := null;
begin
  select * into v_session
  from concierge.agent_sessions
  where id = p_session_id
    and auth_user_id = p_auth_user_id
    and token_hash = p_token_hash
    and expira_em > now();

  if not found then
    raise exception using errcode = '28000', message = 'invalid_chat_session';
  end if;

  select * into v_conversation
  from concierge.conversas
  where id = p_conversation_id
    and dispositivo_id = v_session.dispositivo_id
    and encerrada_em is null;

  if not found then
    raise exception using errcode = '28000', message = 'invalid_chat_conversation';
  end if;

  update concierge.agent_sessions set ultima_atividade = now() where id = v_session.id;
  update concierge.dispositivos set ultimo_acesso = now() where id = v_session.dispositivo_id;
  update concierge.conversas set ultima_atividade = now() where id = v_conversation.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'role', h.papel,
    'content', h.conteudo
  ) order by h.criado_em), '[]'::jsonb)
  into v_history
  from (
    select papel, conteudo, criado_em
    from concierge.mensagens
    where conversa_id = v_conversation.id
      and papel in ('user', 'assistant')
      and conteudo is not null
    order by criado_em desc
    limit 12
  ) h;

  select coalesce(jsonb_agg(jsonb_build_object(
    'key', i.chave,
    'label', i.rotulo,
    'confidence', i.confianca,
    'occurrences', i.ocorrencias
  ) order by i.ultima_em desc), '[]'::jsonb)
  into v_interests
  from concierge.session_interests i
  where i.agent_session_id = v_session.id;

  if v_session.participante_id is not null then
    select jsonb_build_object(
      'participant_id', p.id,
      'name', p.nome,
      'role', p.cargo,
      'company', p.empresa,
      'language', p.idioma,
      'interests', coalesce(pc.temas_relevantes, '[]'::jsonb)
    )
    into v_profile
    from mind.people p
    left join concierge.participante_contexto pc
      on pc.participante_id = p.id
    where p.id = v_session.participante_id;
  end if;

  return jsonb_build_object(
    'identity_verified', false,
    'identity_source', v_session.origem_identidade,
    'identity_confidence', v_session.confianca,
    'participant_profile', v_profile,
    'history', v_history,
    'interests', v_interests,
    'expires_at', v_session.expira_em
  );
end;
$function$;

revoke all on function public.mindagent_chat_get_context(uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.mindagent_chat_get_context(uuid, uuid, uuid, text)
  to service_role;

