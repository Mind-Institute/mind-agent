
create table if not exists concierge.session_interests (
  id uuid primary key default gen_random_uuid(),
  agent_session_id uuid not null references concierge.agent_sessions(id) on delete cascade,
  chave text not null,
  rotulo text not null,
  confianca numeric(4,3) not null default 0.700
    check (confianca >= 0 and confianca <= 1),
  evidencia_message_id uuid references concierge.mensagens(id) on delete set null,
  ocorrencias integer not null default 1 check (ocorrencias > 0),
  primeira_em timestamptz not null default now(),
  ultima_em timestamptz not null default now(),
  unique (agent_session_id, chave)
);

alter table concierge.session_interests enable row level security;
revoke all on table concierge.session_interests from public, anon, authenticated;
grant select, insert, update, delete on table concierge.session_interests to service_role;

create index if not exists session_interests_session_last_idx
  on concierge.session_interests (agent_session_id, ultima_em desc);

create or replace function public.mindagent_chat_start(
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
    dispositivo_id, participante_id, token_hash, origem_identidade,
    confianca, criada_em, ultima_atividade, expira_em
  ) values (
    v_device_id, null, p_token_hash, 'anonima',
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
  p_session_id uuid,
  p_conversation_id uuid,
  p_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, concierge, mind
as $$
declare
  v_session concierge.agent_sessions%rowtype;
  v_conversation concierge.conversas%rowtype;
  v_profile jsonb := null;
  v_context jsonb := '{}'::jsonb;
  v_history jsonb := '[]'::jsonb;
  v_interests jsonb := '[]'::jsonb;
begin
  select * into v_session
  from concierge.agent_sessions
  where id = p_session_id
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

  update concierge.agent_sessions
    set ultima_atividade = now()
  where id = v_session.id;

  update concierge.dispositivos
    set ultimo_acesso = now()
  where id = v_session.dispositivo_id;

  update concierge.conversas
    set ultima_atividade = now()
  where id = v_conversation.id;

  if v_session.participante_id is not null then
    select jsonb_build_object(
      'id', p.id,
      'name', p.nome,
      'role', p.cargo,
      'company', p.empresa,
      'language', p.idioma
    )
    into v_profile
    from mind.people p
    where p.id = v_session.participante_id;

    select jsonb_build_object(
      'professional', c.contexto_profissional,
      'needs', c.necessidades,
      'desired_results', c.resultados_desejados,
      'themes', c.temas_relevantes,
      'preferences', c.preferencias,
      'current_priorities', c.prioridades_atuais,
      'summary', c.resumo_conversa
    )
    into v_context
    from concierge.participante_contexto c
    where c.participante_id = v_session.participante_id;
  end if;

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
    'identity_verified', v_session.participante_id is not null,
    'participant_id', v_session.participante_id,
    'profile', v_profile,
    'participant_context', coalesce(v_context, '{}'::jsonb),
    'history', v_history,
    'interests', v_interests,
    'expires_at', v_session.expira_em
  );
end;
$$;

create or replace function public.mindagent_chat_save_message(
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
    p_conversation_id, v_session.participante_id, p_role, btrim(p_content), p_blocks,
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

  update concierge.conversas
    set ultima_atividade = now()
  where id = p_conversation_id;

  update concierge.agent_sessions
    set ultima_atividade = now()
  where id = p_session_id;

  return jsonb_build_object('id', v_message_id, 'created_at', v_created_at);
end;
$$;

create or replace function public.mindagent_chat_save_interests(
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

create or replace function public.mindagent_chat_search(
  p_event_slug text,
  p_query text,
  p_limit integer default 8
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, api, mind
as $$
with
params as (
  select
    lower(btrim(left(p_query, 500))) as q,
    least(12, greatest(1, coalesce(p_limit, 8))) as lim
),
ev as (
  select e.*
  from mind.events e, params p
  where e.slug = p_event_slug and e.ativo
  limit 1
),
loc as (
  select api.treble_find_location(p_event_slug, p_query) as items
),
session_ranked as (
  select
    s.id,
    s.titulo,
    s.descricao,
    s.dia,
    s.inicio,
    s.fim,
    s.precisa_reserva,
    s.vagas_disponiveis,
    l.nome as local,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', sp.nome,
        'role', sp.cargo,
        'organization', sp.organizacao
      ) order by sp.nome)
      from mind.session_speakers ss
      join mind.speakers sp on sp.id = ss.palestrante_id
      where ss.sessao_id = s.id
    ), '[]'::jsonb) as speakers,
    ts_rank_cd(
      to_tsvector('portuguese',
        coalesce(s.titulo,'') || ' ' || coalesce(s.descricao,'') || ' ' ||
        array_to_string(coalesce(s.trilhas, '{}'::text[]), ' ') || ' ' ||
        coalesce((
          select string_agg(sp.nome || ' ' || coalesce(sp.organizacao,''), ' ')
          from mind.session_speakers ss
          join mind.speakers sp on sp.id = ss.palestrante_id
          where ss.sessao_id = s.id
        ), '')
      ),
      plainto_tsquery('portuguese', p_query)
    ) as score
  from mind.sessions s
  join ev e on e.id = s.event_id
  left join mind.locations l on l.id = s.espaco_id
  cross join params p
  where
    to_tsvector('portuguese',
      coalesce(s.titulo,'') || ' ' || coalesce(s.descricao,'') || ' ' ||
      array_to_string(coalesce(s.trilhas, '{}'::text[]), ' ') || ' ' ||
      coalesce((
        select string_agg(sp.nome || ' ' || coalesce(sp.organizacao,''), ' ')
        from mind.session_speakers ss
        join mind.speakers sp on sp.id = ss.palestrante_id
        where ss.sessao_id = s.id
      ), '')
    ) @@ plainto_tsquery('portuguese', p_query)
    or p.q ~ '(programa|agenda|horario|horário|sessao|sessão|palestra)'
),
session_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.id,
    'title', x.titulo,
    'description', x.descricao,
    'date', x.dia,
    'starts_at', x.inicio,
    'ends_at', x.fim,
    'location', x.local,
    'requires_reservation', x.precisa_reserva,
    'available_places', x.vagas_disponiveis,
    'speakers', x.speakers
  ) order by x.score desc, x.inicio, x.titulo), '[]'::jsonb) as items
  from (
    select * from session_ranked
    order by score desc, inicio, titulo
    limit (select lim from params)
  ) x
),
speaker_ranked as (
  select
    sp.id, sp.nome, sp.cargo, sp.organizacao, sp.bio, sp.temas, sp.destaque,
    ts_rank_cd(
      to_tsvector('portuguese',
        sp.nome || ' ' || coalesce(sp.cargo,'') || ' ' ||
        coalesce(sp.organizacao,'') || ' ' || coalesce(sp.bio,'') || ' ' ||
        array_to_string(coalesce(sp.temas, '{}'::text[]), ' ')
      ),
      plainto_tsquery('portuguese', p_query)
    ) as score
  from mind.speakers sp
  cross join params p
  where exists (
    select 1 from mind.session_speakers ss
    join mind.sessions s on s.id = ss.sessao_id
    join ev e on e.id = s.event_id
    where ss.palestrante_id = sp.id
  )
  and (
    to_tsvector('portuguese',
      sp.nome || ' ' || coalesce(sp.cargo,'') || ' ' ||
      coalesce(sp.organizacao,'') || ' ' || coalesce(sp.bio,'') || ' ' ||
      array_to_string(coalesce(sp.temas, '{}'::text[]), ' ')
    ) @@ plainto_tsquery('portuguese', p_query)
    or p.q ~ '(palestrante|speaker|quem vai falar|quem fala)'
  )
),
speaker_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.id,
    'name', x.nome,
    'role', x.cargo,
    'organization', x.organizacao,
    'bio', x.bio,
    'themes', x.temas
  ) order by x.score desc, x.destaque desc, x.nome), '[]'::jsonb) as items
  from (
    select * from speaker_ranked
    order by score desc, destaque desc, nome
    limit (select lim from params)
  ) x
),
mind_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'category', x.categoria,
    'slug', x.slug,
    'title', x.titulo,
    'body', x.corpo
  ) order by x.score desc, x.titulo), '[]'::jsonb) as items
  from (
    select o.*,
      ts_rank_cd(
        to_tsvector('portuguese', coalesce(o.categoria,'') || ' ' || o.titulo || ' ' || o.corpo),
        plainto_tsquery('portuguese', p_query)
      ) as score
    from mind.organization_content o
    cross join params p
    where o.ativo and o.publico
      and (o.event_id is null or o.event_id = (select id from ev))
      and (o.valido_de is null or o.valido_de <= now())
      and (o.valido_ate is null or o.valido_ate > now())
      and (
        to_tsvector('portuguese', coalesce(o.categoria,'') || ' ' || o.titulo || ' ' || o.corpo)
          @@ plainto_tsquery('portuguese', p_query)
        or p.q ~ '(sobre a mind|o que e a mind|o que é a mind|empresa mind|institucional)'
      )
    order by score desc, o.titulo
    limit (select lim from params)
  ) x
),
exhibitor_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.id,
    'name', x.nome,
    'description', x.descricao,
    'category', x.categoria,
    'location', x.local_nome,
    'website', x.site_url
  ) order by x.score desc, x.nome), '[]'::jsonb) as items
  from (
    select x.*, l.nome as local_nome,
      ts_rank_cd(
        to_tsvector('portuguese', x.nome || ' ' || coalesce(x.descricao,'') || ' ' || coalesce(x.categoria,'')),
        plainto_tsquery('portuguese', p_query)
      ) as score
    from mind.exhibitors x
    join ev e on e.id = x.event_id
    left join mind.locations l on l.id = x.location_id
    cross join params p
    where x.ativo
      and (
        to_tsvector('portuguese', x.nome || ' ' || coalesce(x.descricao,'') || ' ' || coalesce(x.categoria,''))
          @@ plainto_tsquery('portuguese', p_query)
        or p.q ~ '(estande|stand|expositor|patrocinador)'
      )
    order by score desc, x.nome
    limit (select lim from params)
  ) x
),
offer_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', o.codigo,
    'name', o.nome,
    'description', o.descricao,
    'currency', o.moeda,
    'amount', o.valor,
    'payment_terms', o.condicoes_pagamento,
    'checkout_url', o.checkout_url,
    'eligibility', o.elegibilidade
  ) order by o.nome), '[]'::jsonb) as items
  from mind.offers o
  cross join params p
  where o.ativo and o.publico
    and (o.event_id is null or o.event_id = (select id from ev))
    and (o.inicia_em is null or o.inicia_em <= now())
    and (o.encerra_em is null or o.encerra_em > now())
    and p.q ~ '(valor|preço|preco|ingresso|comprar|compra|checkout|pagamento|oferta)'
)
select jsonb_build_object(
  'event', (
    select jsonb_build_object(
      'slug', e.slug,
      'name', e.nome,
      'dates', e.dias,
      'location', e.local,
      'city', e.cidade,
      'timezone', e.fuso
    ) from ev e
  ),
  'locations', (select items from loc),
  'sessions', (select items from session_items),
  'speakers', (select items from speaker_items),
  'mind', (select items from mind_items),
  'exhibitors', (select items from exhibitor_items),
  'offers', (select items from offer_items),
  'official_note', 'Use somente estes dados oficiais. Se algo não estiver presente, informe que ainda não está disponível.'
);
$$;

revoke all on function public.mindagent_chat_start(text,text,text) from public, anon, authenticated;
revoke all on function public.mindagent_chat_get_context(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.mindagent_chat_save_message(uuid,uuid,text,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function public.mindagent_chat_save_interests(uuid,text,jsonb,uuid) from public, anon, authenticated;
revoke all on function public.mindagent_chat_search(text,text,integer) from public, anon, authenticated;

grant execute on function public.mindagent_chat_start(text,text,text) to service_role;
grant execute on function public.mindagent_chat_get_context(uuid,uuid,text) to service_role;
grant execute on function public.mindagent_chat_save_message(uuid,uuid,text,text,text,text,jsonb) to service_role;
grant execute on function public.mindagent_chat_save_interests(uuid,text,jsonb,uuid) to service_role;
grant execute on function public.mindagent_chat_search(text,text,integer) to service_role;
