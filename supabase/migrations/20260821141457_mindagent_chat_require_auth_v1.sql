
alter table concierge.agent_sessions
  add column if not exists auth_user_id uuid references auth.users(id) on delete cascade;

create index if not exists agent_sessions_auth_user_activity_idx
  on concierge.agent_sessions (auth_user_id, ultima_atividade desc);

drop function if exists public.mindagent_chat_start(text,text,text);
drop function if exists public.mindagent_chat_get_context(uuid,uuid,text);
drop function if exists public.mindagent_chat_save_message(uuid,uuid,text,text,text,text,jsonb);
drop function if exists public.mindagent_chat_save_interests(uuid,text,jsonb,uuid);

create or replace function public.mindagent_chat_start(
  p_auth_user_id uuid,
  p_device_key text,
  p_user_agent text,
  p_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, concierge
as $$
declare
  v_device_id uuid;
  v_session_id uuid;
  v_conversation_id uuid;
  v_expires_at timestamptz := now() + interval '24 hours';
begin
  if p_auth_user_id is null or not exists (select 1 from auth.users where id = p_auth_user_id) then
    raise exception using errcode = '28000', message = 'invalid_auth_user';
  end if;
  if p_device_key is null or length(btrim(p_device_key)) < 8 or length(p_device_key) > 160 then
    raise exception using errcode = '22023', message = 'invalid_device_key';
  end if;
  if p_token_hash is null or p_token_hash !~ '^[a-f0-9]{64}$' then
    raise exception using errcode = '22023', message = 'invalid_token_hash';
  end if;

  insert into concierge.dispositivos (chave, user_agent, ultimo_acesso)
  values (btrim(p_device_key), left(p_user_agent, 500), now())
  on conflict (chave) do update
    set user_agent = coalesce(excluded.user_agent, concierge.dispositivos.user_agent),
        ultimo_acesso = now()
  returning id into v_device_id;

  insert into concierge.agent_sessions (
    dispositivo_id, participante_id, auth_user_id, token_hash, origem_identidade,
    confianca, criada_em, ultima_atividade, expira_em
  ) values (
    v_device_id, null, p_auth_user_id, p_token_hash, 'supabase_anonymous_auth',
    'baixa', now(), now(), v_expires_at
  )
  returning id into v_session_id;

  insert into concierge.conversas (
    participante_id, dispositivo_id, canal, iniciada_em, ultima_atividade
  ) values (
    null, v_device_id, 'mindagent-web', now(), now()
  )
  returning id into v_conversation_id;

  return jsonb_build_object(
    'session_id', v_session_id,
    'conversation_id', v_conversation_id,
    'expires_at', v_expires_at,
    'identity_verified', false
  );
end;
$$;

create or replace function public.mindagent_chat_get_context(
  p_auth_user_id uuid,
  p_session_id uuid,
  p_conversation_id uuid,
  p_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, concierge
as $$
declare
  v_session concierge.agent_sessions%rowtype;
  v_conversation concierge.conversas%rowtype;
  v_history jsonb := '[]'::jsonb;
  v_interests jsonb := '[]'::jsonb;
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

  return jsonb_build_object(
    'identity_verified', false,
    'history', v_history,
    'interests', v_interests,
    'expires_at', v_session.expira_em
  );
end;
$$;

create or replace function public.mindagent_chat_save_message(
  p_auth_user_id uuid,
  p_session_id uuid,
  p_conversation_id uuid,
  p_token_hash text,
  p_role text,
  p_content text,
  p_client_message_id text,
  p_blocks jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, concierge
as $$
declare
  v_session concierge.agent_sessions%rowtype;
  v_message_id uuid;
  v_created_at timestamptz;
begin
  if p_role not in ('user', 'assistant') then
    raise exception using errcode = '22023', message = 'invalid_message_role';
  end if;
  if p_content is null or length(btrim(p_content)) < 1 or length(p_content) > 6000 then
    raise exception using errcode = '22023', message = 'invalid_message_content';
  end if;
  if p_client_message_id is null or length(p_client_message_id) > 160 then
    raise exception using errcode = '22023', message = 'invalid_client_message_id';
  end if;

  select * into v_session
  from concierge.agent_sessions
  where id = p_session_id
    and auth_user_id = p_auth_user_id
    and token_hash = p_token_hash
    and expira_em > now();

  if not found then
    raise exception using errcode = '28000', message = 'invalid_chat_session';
  end if;

  if not exists (
    select 1 from concierge.conversas c
    where c.id = p_conversation_id
      and c.dispositivo_id = v_session.dispositivo_id
      and c.encerrada_em is null
  ) then
    raise exception using errcode = '28000', message = 'invalid_chat_conversation';
  end if;

  insert into concierge.mensagens (
    conversa_id, participante_id, papel, conteudo, blocos,
    client_msg_id, origem, criado_em
  ) values (
    p_conversation_id, null, p_role, btrim(p_content), p_blocks,
    p_client_message_id, 'mindagent-chat', now()
  )
  on conflict (client_msg_id) do nothing
  returning id, criado_em into v_message_id, v_created_at;

  if v_message_id is null then
    select id, criado_em into v_message_id, v_created_at
    from concierge.mensagens
    where client_msg_id = p_client_message_id
      and conversa_id = p_conversation_id
      and papel = p_role;

    if v_message_id is null then
      raise exception using errcode = '23505', message = 'client_message_id_conflict';
    end if;
  end if;

  update concierge.conversas set ultima_atividade = now() where id = p_conversation_id;
  update concierge.agent_sessions set ultima_atividade = now() where id = p_session_id;

  return jsonb_build_object('id', v_message_id, 'created_at', v_created_at);
end;
$$;

create or replace function public.mindagent_chat_save_interests(
  p_auth_user_id uuid,
  p_session_id uuid,
  p_token_hash text,
  p_interests jsonb,
  p_evidence_message_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, concierge
as $$
declare
  v_item jsonb;
  v_count integer := 0;
  v_key text;
  v_label text;
  v_confidence numeric;
begin
  if not exists (
    select 1 from concierge.agent_sessions s
    where s.id = p_session_id
      and s.auth_user_id = p_auth_user_id
      and s.token_hash = p_token_hash
      and s.expira_em > now()
  ) then
    raise exception using errcode = '28000', message = 'invalid_chat_session';
  end if;

  if p_interests is null or jsonb_typeof(p_interests) <> 'array' then
    return jsonb_build_object('saved', 0);
  end if;
  if jsonb_array_length(p_interests) > 5 then
    raise exception using errcode = '22023', message = 'too_many_interests';
  end if;

  for v_item in select value from jsonb_array_elements(p_interests)
  loop
    v_key := left(lower(regexp_replace(coalesce(v_item->>'key', ''), '[^a-z0-9_\-]+', '_', 'g')), 80);
    v_label := left(btrim(coalesce(v_item->>'label', '')), 120);
    v_confidence := least(1, greatest(0, coalesce((v_item->>'confidence')::numeric, 0.7)));

    if length(v_key) >= 2 and length(v_label) >= 2 and v_confidence >= 0.65 then
      insert into concierge.session_interests (
        agent_session_id, chave, rotulo, confianca,
        evidencia_message_id, ocorrencias, primeira_em, ultima_em
      ) values (
        p_session_id, v_key, v_label, v_confidence,
        p_evidence_message_id, 1, now(), now()
      )
      on conflict (agent_session_id, chave) do update
        set rotulo = excluded.rotulo,
            confianca = greatest(concierge.session_interests.confianca, excluded.confianca),
            evidencia_message_id = coalesce(excluded.evidencia_message_id, concierge.session_interests.evidencia_message_id),
            ocorrencias = concierge.session_interests.ocorrencias + 1,
            ultima_em = now();
      v_count := v_count + 1;
    end if;
  end loop;

  return jsonb_build_object('saved', v_count);
exception
  when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid_interest_confidence';
end;
$$;

revoke all on function public.mindagent_chat_start(uuid,text,text,text) from public, anon, authenticated;
revoke all on function public.mindagent_chat_get_context(uuid,uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.mindagent_chat_save_message(uuid,uuid,uuid,text,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function public.mindagent_chat_save_interests(uuid,uuid,text,jsonb,uuid) from public, anon, authenticated;

grant execute on function public.mindagent_chat_start(uuid,text,text,text) to service_role;
grant execute on function public.mindagent_chat_get_context(uuid,uuid,uuid,text) to service_role;
grant execute on function public.mindagent_chat_save_message(uuid,uuid,uuid,text,text,text,text,jsonb) to service_role;
grant execute on function public.mindagent_chat_save_interests(uuid,uuid,text,jsonb,uuid) to service_role;

