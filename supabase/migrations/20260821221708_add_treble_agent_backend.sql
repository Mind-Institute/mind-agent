
alter table treble.conversations
  add column if not exists participante_id uuid
  references mind.people(id) on delete set null;

create index if not exists conversations_participante_idx
  on treble.conversations(participante_id);

create index if not exists people_phone_digits_idx
  on mind.people ((regexp_replace(coalesce(telefone, ''), '\D', '', 'g')))
  where telefone is not null and btrim(telefone) <> '';

create table if not exists treble.conversation_interests (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references treble.conversations(id) on delete cascade,
  chave text not null,
  rotulo text not null,
  confianca numeric not null default 0.700,
  evidencia_message_id uuid references treble.messages(id) on delete set null,
  ocorrencias integer not null default 1,
  primeira_em timestamptz not null default now(),
  ultima_em timestamptz not null default now(),
  unique (conversation_id, chave)
);

create index if not exists conversation_interests_last_idx
  on treble.conversation_interests(conversation_id, ultima_em desc);

alter table treble.conversation_interests enable row level security;

create table if not exists treble.agent_events (
  event_key text primary key,
  session_external_id text not null,
  request_id uuid not null,
  status text not null default 'processing'
    check (status in ('processing', 'completed', 'failed')),
  attempts integer not null default 1,
  error_code text,
  criado_em timestamptz not null default now(),
  concluido_em timestamptz
);

create index if not exists agent_events_created_idx
  on treble.agent_events(criado_em desc);

alter table treble.agent_events enable row level security;

create or replace function public.mindagent_treble_claim_event(
  p_event_key text,
  p_session_external_id text,
  p_request_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'treble'
as $function$
declare
  v_claimed boolean;
begin
  if p_event_key is null
     or p_event_key !~ '^[a-f0-9]{64}$'
     or p_session_external_id is null
     or length(btrim(p_session_external_id)) < 1
     or length(p_session_external_id) > 240
     or p_request_id is null then
    raise exception using errcode = '22023', message = 'invalid_treble_event';
  end if;

  insert into treble.agent_events (
    event_key, session_external_id, request_id, status, attempts, criado_em
  ) values (
    p_event_key, btrim(p_session_external_id), p_request_id, 'processing', 1, now()
  )
  on conflict (event_key) do update
    set request_id = excluded.request_id,
        status = 'processing',
        attempts = treble.agent_events.attempts + 1,
        error_code = null,
        concluido_em = null
    where treble.agent_events.status = 'failed'
  returning true into v_claimed;

  return coalesce(v_claimed, false);
end;
$function$;

create or replace function public.mindagent_treble_complete_event(
  p_event_key text,
  p_status text,
  p_error_code text default null
)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'treble'
as $function$
begin
  if p_status not in ('completed', 'failed') then
    raise exception using errcode = '22023', message = 'invalid_treble_event_status';
  end if;

  update treble.agent_events
  set status = p_status,
      error_code = case when p_status = 'failed' then left(coalesce(p_error_code, 'unknown'), 120) else null end,
      concluido_em = now()
  where event_key = p_event_key;

  return found;
end;
$function$;

create or replace function public.mindagent_treble_start(
  p_session_external_id text,
  p_phone_digits text,
  p_phone_hash text,
  p_email text default null,
  p_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'mind', 'concierge', 'treble'
as $function$
declare
  v_session_external_id text := btrim(coalesce(p_session_external_id, ''));
  v_phone_digits text := regexp_replace(coalesce(p_phone_digits, ''), '\D', '', 'g');
  v_phone_hash text := lower(btrim(coalesce(p_phone_hash, '')));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_name text := nullif(left(btrim(coalesce(p_name, '')), 160), '');
  v_person_id uuid;
  v_conversation_id uuid;
  v_bound_person_id uuid;
  v_profile jsonb := null;
begin
  if length(v_session_external_id) < 1 or length(v_session_external_id) > 240 then
    raise exception using errcode = '22023', message = 'invalid_treble_session';
  end if;

  if v_phone_hash <> '' and v_phone_hash !~ '^[a-f0-9]{64}$' then
    raise exception using errcode = '22023', message = 'invalid_phone_hash';
  end if;

  if v_email <> ''
     and (
       length(v_email) > 320
       or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$'
     ) then
    v_email := '';
  end if;

  if v_email <> '' then
    select p.id into v_person_id
    from mind.people p
    where lower(btrim(p.email)) = v_email
    limit 1;
  end if;

  if v_person_id is null and length(v_phone_digits) between 8 and 15 then
    select p.id into v_person_id
    from mind.people p
    where regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g') = v_phone_digits
    limit 1;
  end if;

  insert into treble.conversations as c (
    session_external_id,
    telefone_hash,
    nome_contato,
    participante_id,
    variables,
    iniciada_em,
    ultima_atividade
  ) values (
    v_session_external_id,
    nullif(v_phone_hash, ''),
    v_name,
    v_person_id,
    '{}'::jsonb,
    now(),
    now()
  )
  on conflict (session_external_id) do update
    set telefone_hash = coalesce(c.telefone_hash, excluded.telefone_hash),
        nome_contato = coalesce(excluded.nome_contato, c.nome_contato),
        participante_id = coalesce(c.participante_id, excluded.participante_id),
        ultima_atividade = now()
  returning id, participante_id into v_conversation_id, v_bound_person_id;

  if v_bound_person_id is not null then
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
    where p.id = v_bound_person_id;
  end if;

  return jsonb_build_object(
    'conversation_id', v_conversation_id,
    'participant_id', v_bound_person_id,
    'participant_profile', v_profile,
    'identity_found', v_bound_person_id is not null
  );
end;
$function$;

create or replace function public.mindagent_treble_save_message(
  p_session_external_id text,
  p_role text,
  p_content text,
  p_tool_calls jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'treble'
as $function$
declare
  v_conversation_id uuid;
  v_message_id uuid;
  v_role text;
  v_content text := btrim(coalesce(p_content, ''));
begin
  v_role := case p_role
    when 'user' then 'lead'
    when 'assistant' then 'agente'
    when 'system' then 'sistema'
    else null
  end;

  if v_role is null or length(v_content) < 1 or length(v_content) > 4000 then
    raise exception using errcode = '22023', message = 'invalid_treble_message';
  end if;

  select c.id into v_conversation_id
  from treble.conversations c
  where c.session_external_id = btrim(p_session_external_id)
  limit 1;

  if v_conversation_id is null then
    raise exception using errcode = '22023', message = 'treble_conversation_not_found';
  end if;

  insert into treble.messages (
    conversation_id, papel, conteudo, tool_calls, criado_em
  ) values (
    v_conversation_id, v_role, v_content, p_tool_calls, now()
  )
  returning id into v_message_id;

  update treble.conversations
  set ultima_atividade = now()
  where id = v_conversation_id;

  return v_message_id;
end;
$function$;

create or replace function public.mindagent_treble_save_interests(
  p_session_external_id text,
  p_interests jsonb,
  p_evidence_message_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'mind', 'concierge', 'treble'
as $function$
declare
  v_item jsonb;
  v_conversation_id uuid;
  v_participant_id uuid;
  v_saved integer := 0;
  v_promoted integer := 0;
  v_session_skipped integer := 0;
  v_permanent_skipped integer := 0;
  v_key text;
  v_label text;
  v_confidence numeric;
  v_confirmed boolean;
  v_profile_item jsonb;
  v_interest_exists boolean;
  v_interest_count integer;
begin
  select c.id, c.participante_id
    into v_conversation_id, v_participant_id
  from treble.conversations c
  where c.session_external_id = btrim(p_session_external_id)
  limit 1;

  if v_conversation_id is null then
    raise exception using errcode = '22023', message = 'treble_conversation_not_found';
  end if;

  if p_interests is null or jsonb_typeof(p_interests) <> 'array' then
    return jsonb_build_object('saved', 0, 'promoted', 0);
  end if;

  if jsonb_array_length(p_interests) > 5 then
    raise exception using errcode = '22023', message = 'too_many_interests';
  end if;

  for v_item in select value from jsonb_array_elements(p_interests)
  loop
    v_key := left(lower(regexp_replace(coalesce(v_item->>'key', ''), '[^a-z0-9_\-]+', '_', 'g')), 80);
    v_label := left(btrim(coalesce(v_item->>'label', '')), 120);
    v_confidence := least(1, greatest(0, coalesce((v_item->>'confidence')::numeric, 0.7)));
    v_confirmed := lower(coalesce(v_item->>'confirmed', 'false')) in ('true', '1', 'yes');

    if length(v_key) >= 2 and length(v_label) >= 2 and v_confidence >= 0.70 then
      select exists (
        select 1 from treble.conversation_interests ci
        where ci.conversation_id = v_conversation_id and ci.chave = v_key
      ) into v_interest_exists;

      select count(*) into v_interest_count
      from treble.conversation_interests ci
      where ci.conversation_id = v_conversation_id;

      if v_interest_exists or v_interest_count < 12 then
        insert into treble.conversation_interests (
          conversation_id, chave, rotulo, confianca,
          evidencia_message_id, ocorrencias, primeira_em, ultima_em
        ) values (
          v_conversation_id, v_key, v_label, v_confidence,
          p_evidence_message_id, 1, now(), now()
        )
        on conflict (conversation_id, chave) do update
          set rotulo = excluded.rotulo,
              confianca = greatest(treble.conversation_interests.confianca, excluded.confianca),
              evidencia_message_id = coalesce(excluded.evidencia_message_id, treble.conversation_interests.evidencia_message_id),
              ocorrencias = treble.conversation_interests.ocorrencias + 1,
              ultima_em = now();

        v_saved := v_saved + 1;
      else
        v_session_skipped := v_session_skipped + 1;
      end if;

      if v_confirmed and v_confidence >= 0.85 and v_participant_id is not null then
        perform pg_advisory_xact_lock(hashtextextended('mindagent-interest:' || v_participant_id::text, 0));

        select exists (
          select 1 from concierge.participante_memoria pm
          where pm.participante_id = v_participant_id
            and pm.tipo = 'interesse'
            and pm.chave = v_key
            and pm.status = 'ativa'
        ) into v_interest_exists;

        select count(*) into v_interest_count
        from concierge.participante_memoria pm
        where pm.participante_id = v_participant_id
          and pm.tipo = 'interesse'
          and pm.status = 'ativa';

        if v_interest_exists or v_interest_count < 8 then
          v_profile_item := jsonb_build_object(
            'key', v_key,
            'label', v_label,
            'source', 'treble_confirmado_pelo_usuario',
            'confirmed', true,
            'confidence', v_confidence
          );

          insert into concierge.participante_memoria (
            participante_id, tipo, chave, valor, confianca, origem,
            evidencia_message_id, status, importancia, criado_em, atualizado_em
          ) values (
            v_participant_id, 'interesse', v_key,
            jsonb_build_object(
              'label', v_label,
              'confirmed', true,
              'channel', 'treble',
              'conversation_id', v_conversation_id
            ),
            v_confidence, 'treble_confirmado_pelo_usuario',
            null, 'ativa', v_confidence, now(), now()
          )
          on conflict (participante_id, chave) where status = 'ativa' do update
            set tipo = 'interesse',
                valor = excluded.valor,
                confianca = greatest(concierge.participante_memoria.confianca, excluded.confianca),
                origem = excluded.origem,
                importancia = greatest(coalesce(concierge.participante_memoria.importancia, 0), excluded.importancia),
                atualizado_em = now();

          insert into concierge.participante_contexto as pc (
            participante_id, temas_relevantes, versao, atualizado_em
          ) values (
            v_participant_id, jsonb_build_array(v_profile_item), 1, now()
          )
          on conflict (participante_id) do update
            set temas_relevantes =
              coalesce(
                (
                  select jsonb_agg(existing_item)
                  from jsonb_array_elements(
                    case
                      when jsonb_typeof(pc.temas_relevantes) = 'array' then pc.temas_relevantes
                      else '[]'::jsonb
                    end
                  ) as existing(existing_item)
                  where existing_item->>'key' <> v_key
                ),
                '[]'::jsonb
              ) || jsonb_build_array(v_profile_item),
              versao = pc.versao + 1,
              atualizado_em = now();

          v_promoted := v_promoted + 1;
        else
          v_permanent_skipped := v_permanent_skipped + 1;
        end if;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'saved', v_saved,
    'promoted', v_promoted,
    'session_skipped', v_session_skipped,
    'permanent_skipped', v_permanent_skipped
  );
exception
  when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid_interest_confidence';
end;
$function$;

revoke execute on function public.mindagent_treble_claim_event(text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.mindagent_treble_claim_event(text, text, uuid)
  to service_role;

revoke execute on function public.mindagent_treble_complete_event(text, text, text)
  from public, anon, authenticated;
grant execute on function public.mindagent_treble_complete_event(text, text, text)
  to service_role;

revoke execute on function public.mindagent_treble_start(text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.mindagent_treble_start(text, text, text, text, text)
  to service_role;

revoke execute on function public.mindagent_treble_save_message(text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.mindagent_treble_save_message(text, text, text, jsonb)
  to service_role;

revoke execute on function public.mindagent_treble_save_interests(text, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.mindagent_treble_save_interests(text, jsonb, uuid)
  to service_role;

