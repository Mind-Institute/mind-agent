-- O bloco "mind" da busca do concierge lia mind.organization_content (vazia),
-- enquanto o conteúdo real vive em mind.knowledge_documents — o banco comum que
-- o Treble já consome. Passa a ler o banco comum, respeitando `agents` (quem
-- pode consumir) e `event_id` (NULL = institucional Mind; preenchido = produto).
CREATE OR REPLACE FUNCTION public.mindagent_chat_search(p_event_slug text, p_query text, p_limit integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'api', 'mind'
AS $function$
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
    or lower(translate(p.q, 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')) like '%' || lower(translate(sp.nome, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')) || '%'
    or (
      length(regexp_replace(lower(translate(sp.nome, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')), '^.*[[:space:]]', '')) >= 4
      and lower(translate(p.q, 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')) like '%' || regexp_replace(lower(translate(sp.nome, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')), '^.*[[:space:]]', '') || '%'
    )
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
    'category', x.tipo_conteudo,
    'title', x.titulo,
    'body', x.corpo
  ) order by x.score desc, x.titulo), '[]'::jsonb) as items
  from (
    select k.tipo_conteudo, k.titulo, left(k.corpo, 1500) as corpo,
      ts_rank_cd(
        to_tsvector('portuguese', coalesce(k.tipo_conteudo,'') || ' ' || k.titulo || ' ' || k.corpo),
        plainto_tsquery('portuguese', p_query)
      ) as score
    from mind.knowledge_documents k
    cross join params p
    where k.ativo
      and 'concierge' = any(k.agents)
      and (k.event_id is null or k.event_id = (select id from ev))
      and (
        to_tsvector('portuguese', coalesce(k.tipo_conteudo,'') || ' ' || k.titulo || ' ' || k.corpo)
          @@ plainto_tsquery('portuguese', p_query)
        or p.q ~ '(sobre a mind|o que e a mind|o que é a mind|empresa mind|institucional)'
      )
    order by score desc, k.titulo
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
$function$