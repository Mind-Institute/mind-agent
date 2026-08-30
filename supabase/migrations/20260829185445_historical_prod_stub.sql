-- =========================================================================
-- BASELINE ESTRUTURAL — extraído do catálogo de produção (schema-only).
-- Sem dados. Sem OWNER. Sem ALTER DEFAULT PRIVILEGES (bootstrap da branch).
-- Extensões de bootstrap não são recriadas: só pg_trgm e vector.
-- Em produção esta versão já consta no ledger e o arquivo é ignorado.
-- =========================================================================
SET check_function_bodies = false;
SELECT set_config('search_path', E'"\\$user", public, extensions', false);

DO $mind_role$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mind_agent') THEN
    CREATE ROLE mind_agent NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE
                           NOREPLICATION NOBYPASSRLS;
  END IF;
END
$mind_role$;

DO $mind_role$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
    EXECUTE 'GRANT mind_agent TO postgres';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN
    EXECUTE 'GRANT mind_agent TO authenticator';
  END IF;
END
$mind_role$;

COMMENT ON ROLE mind_agent IS 'Papel do Worker para tudo que é dado de pessoa. NÃO é o service_role: obedece RLS. O Worker faz set role mind_agent + set local mind.person_id a cada transação.';

CREATE SCHEMA IF NOT EXISTS agentes;

CREATE SCHEMA IF NOT EXISTS api;

CREATE SCHEMA IF NOT EXISTS catalogo;

CREATE SCHEMA IF NOT EXISTS concierge;

CREATE SCHEMA IF NOT EXISTS credenciamento_summit_2026;

CREATE SCHEMA IF NOT EXISTS crm;

CREATE SCHEMA IF NOT EXISTS dash;

CREATE SCHEMA IF NOT EXISTS ecossistema;

CREATE SCHEMA IF NOT EXISTS eduzz;

CREATE SCHEMA IF NOT EXISTS engagement;

CREATE SCHEMA IF NOT EXISTS eventos;

CREATE SCHEMA IF NOT EXISTS institute;

CREATE SCHEMA IF NOT EXISTS intelligence;

CREATE SCHEMA IF NOT EXISTS mind;

CREATE SCHEMA IF NOT EXISTS pessoas;

CREATE SCHEMA IF NOT EXISTS platform;

CREATE SCHEMA IF NOT EXISTS public;

CREATE SCHEMA IF NOT EXISTS summit_2026;

CREATE SCHEMA IF NOT EXISTS treble;

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;

CREATE SEQUENCE crm.acessos_id_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;

CREATE SEQUENCE intelligence.acessos_dado_pessoal_id_seq AS bigint START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE;

CREATE OR REPLACE FUNCTION api.changed_since(p_desde timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'public'
AS $function$
  select jsonb_build_object(
    'events',              (select count(*) from summit.events              where atualizado_em > p_desde),
    'sessions',            (select count(*) from summit.sessions            where atualizado_em > p_desde),
    'locations',           (select count(*) from summit.locations           where atualizado_em > p_desde),
    'speakers',            (select count(*) from comum.speakers            where atualizado_em > p_desde),
    'event_rules',         (select count(*) from summit.event_rules         where atualizado_em > p_desde),
    'knowledge_documents', (select count(*) from summit.conhecimento where atualizado_em > p_desde),
    'agora', now());
$function$
;

CREATE OR REPLACE FUNCTION api.contact(p_token text, p_nome text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'public'
AS $function$
  with eu as (select api.quem_sou(p_token) as id)
  select coalesce(jsonb_agg(jsonb_build_object(
           'nome', p.nome, 'empresa', p.empresa, 'cargo', p.cargo)), '[]')
  from engagement.v_pessoa p, eu
  where p.nome ilike '%' || p_nome || '%'
    and exists (select 1 from engagement.contatos c
                where c.estado = 'aceito'
                  and ((c.de = eu.id and c.para = p.id)
                    or (c.para = eu.id and c.de = p.id)));
$function$
;

CREATE OR REPLACE FUNCTION api.event(p_slug text DEFAULT 'mind-summit-2026'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'public'
AS $function$
  select jsonb_build_object('slug', e.slug, 'nome', e.nome, 'dias', e.dias,
                            'local', e.local, 'cidade', e.cidade, 'fuso', e.fuso,
                            'regras', (select coalesce(jsonb_agg(jsonb_build_object(
                                          'chave', r.chave, 'titulo', r.titulo, 'texto', r.texto)), '[]')
                                       from summit.event_rules r
                                       where r.event_id = e.id and r.ativo))
  from summit.events e where e.slug = p_slug and e.ativo;
$function$
;

CREATE OR REPLACE FUNCTION api.knowledge(p_pergunta text, p_embedding vector DEFAULT NULL::vector, p_agent text DEFAULT NULL::text, p_limit integer DEFAULT 6)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'public'
AS $function$
  with permitido as (
    select d.id, d.titulo, d.tipo_conteudo, d.url, f.nome as fonte
    from summit.conhecimento d
    join comum.knowledge_sources f on f.id = d.fonte_id
    where f.ativo and d.ativo
      and (p_agent is null or cardinality(d.agents) = 0 or d.agents @> array[p_agent])
  ),
  por_texto as (
    select c.id, row_number() over (
             order by ts_rank(c.tsv, plainto_tsquery('portuguese', p_pergunta)) desc) as pos
    from summit.conhecimento_chunks c
    join permitido d on d.id = c.doc_id
    where not c.stale
      and c.tsv @@ plainto_tsquery('portuguese', p_pergunta)
    limit p_limit * 4
  ),
  por_vetor as (
    select c.id, row_number() over (order by c.embedding <=> p_embedding) as pos
    from summit.conhecimento_chunks c
    join permitido d on d.id = c.doc_id
    where p_embedding is not null
      and not c.stale
      and c.embedding is not null
    order by c.embedding <=> p_embedding
    limit p_limit * 4
  ),
  fundido as (
    select id, sum(peso) as score from (
      select id, 1.0 / (60 + pos) as peso from por_texto
      union all
      select id, 1.0 / (60 + pos) as peso from por_vetor) u
    group by id
    order by score desc
    limit p_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'texto', c.texto, 'documento', d.titulo, 'fonte', d.fonte,
           'tipo', d.tipo_conteudo, 'url', d.url,
           'score', round(fu.score::numeric, 5)) order by fu.score desc), '[]')
  from fundido fu
  join summit.conhecimento_chunks c on c.id = fu.id
  join permitido d on d.id = c.doc_id;
$function$
;

CREATE OR REPLACE FUNCTION api.me(p_token text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'concierge', 'public'
AS $function$
  select jsonb_build_object(
    'nome', p.nome, 'empresa', p.empresa, 'cargo', p.cargo, 'idioma', p.idioma,
    'ingresso', (select r.ticket_category from summit.registrations r
                 where r.person_id = p.id order by r.criado_em desc limit 1))
  from engagement.v_pessoa p
  where p.id = api.quem_sou(p_token);
$function$
;

CREATE OR REPLACE FUNCTION api.mindagent_bootstrap(p_event_slug text DEFAULT 'mind-summit-2026'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'summit', 'comum', 'engagement', 'intelligence', 'mind'
AS $function$
with ev as (
  select e.* from summit.events e where e.slug=p_event_slug and e.ativo limit 1
)
select jsonb_build_object(
  '_meta',jsonb_build_object(
    'schema_version','1.0',
    'event_slug',p_event_slug,
    'generated_at',now()
  ),
  '_nota','Dados oficiais do Supabase. Informações ausentes não devem ser inventadas.',
  'evento',(select jsonb_build_object(
    'nome',e.nome,
    'dias',e.dias,
    'local',e.local,
    'regra_reserva',(select r.texto from summit.event_rules r where r.ativo and r.chave='reserva_expira' and (r.event_id is null or r.event_id=e.id) order by r.event_id nulls last limit 1),
    'regra_vagas',(select r.texto from summit.event_rules r where r.ativo and r.chave='vagas_limitadas' and (r.event_id is null or r.event_id=e.id) order by r.event_id nulls last limit 1)
  ) from ev e),
  'temas',coalesce((
    select jsonb_agg(jsonb_build_object('codigo',t.codigo,'rotulo',t.rotulo) order by t.rotulo)
    from comum.taxonomy t where t.tipo='tema' and t.ativo
  ),'[]'::jsonb),
  'sessoes',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',coalesce(s.yazo_id,s.id::text),
      'dia',s.dia,
      'inicio',to_char(s.inicio at time zone e.fuso,'HH24:MI'),
      'fim',to_char(s.fim at time zone e.fuso,'HH24:MI'),
      'titulo',s.titulo,
      'descricao',coalesce(s.descricao,''),
      'quem',coalesce((
        select string_agg(sp.nome,'; ' order by sp.nome)
        from summit.session_speakers ss join comum.speakers sp on sp.id=ss.palestrante_id
        where ss.sessao_id=s.id
      ),'Em breve'),
      'espaco',l.nome,
      'formato',coalesce(s.tipo,s.formato,'sessao'),
      'etiqueta',coalesce(tt.rotulo,initcap(coalesce(s.tipo,s.formato,'Sessão'))),
      'trilhas',coalesce(s.trilhas,'{}'::text[]),
      'vaga_limitada',coalesce(s.precisa_reserva,false),
      'online',lower(coalesce(s.formato,'')) in ('remoto','online','virtual'),
      'temas',coalesce(s.topicos_aprendizado,'[]'::jsonb)
    ) order by s.inicio,s.titulo)
    from summit.sessions s
    join ev e on e.id=s.event_id
    left join summit.locations l on l.id=s.espaco_id
    left join comum.taxonomy tt on tt.tipo='tipo_sessao' and tt.codigo=s.tipo and tt.ativo
  ),'[]'::jsonb),
  'pessoas',coalesce((
    select jsonb_agg(jsonb_build_object(
      'nome',sp.nome,
      'credencial',concat_ws(' · ',nullif(sp.cargo,''),nullif(sp.organizacao,'')),
      'resumo',coalesce(sp.bio,''),
      'foto',sp.asset_path,
      'destaque',sp.destaque,
      'na_grade',exists(
        select 1 from summit.session_speakers ss
        join summit.sessions sx on sx.id=ss.sessao_id
        join ev e on e.id=sx.event_id
        where ss.palestrante_id=sp.id
      ),
      'temas',sp.temas
    ) order by sp.destaque desc,sp.nome)
    from comum.speakers sp
    where exists(
      select 1 from summit.session_speakers ss
      join summit.sessions sx on sx.id=ss.sessao_id
      join ev e on e.id=sx.event_id
      where ss.palestrante_id=sp.id
    )
  ),'[]'::jsonb)
);
$function$
;

CREATE OR REPLACE FUNCTION api.my_agenda(p_token text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'sessao', s.titulo, 'dia', s.dia, 'inicio', s.inicio,
           'espaco', l.nome, 'intencao', j.intencao,
           'compareceu', j.compareceu) order by s.dia, s.inicio), '[]')
  from engagement.jornada_sessao j
  join summit.sessions s on s.id = j.sessao_id
  left join summit.locations l on l.id = s.espaco_id
  where j.participante_id = api.quem_sou(p_token);
$function$
;

CREATE OR REPLACE FUNCTION api.my_context(p_token text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'public'
AS $function$
  select jsonb_build_object(
    'necessidades', c.necessidades,
    'resultados_desejados', c.resultados_desejados,
    'temas', c.temas_relevantes,
    'resumo', c.resumo_conversa)
  from intelligence.participante_contexto c
  where c.participante_id = api.quem_sou(p_token);
$function$
;

CREATE OR REPLACE FUNCTION api.my_data(p_token text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'crm', 'public'
AS $function$
  with eu as (select api.quem_sou(p_token) as id)
  select jsonb_build_object(
    'perfil',    (select jsonb_build_object('nome', p.nome, 'email', p.email,
                          'empresa', p.empresa, 'cargo', p.cargo)
                  from engagement.v_pessoa p, eu where p.id = eu.id),
    'memoria',   (select coalesce(jsonb_agg(jsonb_build_object(
                          'chave', m.chave, 'valor', m.valor, 'origem', m.origem)), '[]')
                  from intelligence.participante_memoria m, eu
                  where m.participante_id = eu.id and m.status = 'ativa'),
    'objetivos', (select coalesce(jsonb_agg(o.pergunta_guia), '[]')
                  from intelligence.participante_objetivos o, eu where o.participante_id = eu.id),
    'insights',  (select coalesce(jsonb_agg(f.insight), '[]')
                  from engagement.sessao_feedback f, eu
                  where f.participante_id = eu.id and f.insight is not null),
    'consentimentos', (select coalesce(jsonb_agg(jsonb_build_object(
                          'finalidade', k.finalidade, 'concedido', k.concedido,
                          'em', k.criado_em)), '[]')
                  from crm.consents k, eu where k.participante_id = eu.id));
$function$
;

CREATE OR REPLACE FUNCTION api.quem_sou(p_token text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'extensions', 'public'
AS $function$
  select s.participante_id
  from engagement.agent_sessions s
  where s.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and s.expira_em > now()
    and s.participante_id is not null;
$function$
;

CREATE OR REPLACE FUNCTION api.sessions(p_event text DEFAULT 'mind-summit-2026'::text, p_dia date DEFAULT NULL::date, p_tema text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'public'
AS $function$
  select coalesce(jsonb_agg(x order by x->>'inicio'), '[]') from (
    select jsonb_build_object(
      'id', s.id, 'titulo', s.titulo, 'descricao', s.descricao,
      'dia', s.dia, 'inicio', s.inicio, 'fim', s.fim,
      'tipo', s.tipo, 'formato', s.formato, 'nivel', s.nivel,
      'espaco', l.nome, 'vaga_limitada', s.precisa_reserva,
      'trilhas', s.trilhas, 'topicos', s.topicos_aprendizado,
      'quem', (select coalesce(jsonb_agg(sp.nome), '[]')
               from summit.session_speakers ss
               join comum.speakers sp on sp.id = ss.palestrante_id
               where ss.sessao_id = s.id)) as x
    from summit.sessions s
    left join summit.locations l on l.id = s.espaco_id
    join summit.events e on e.id = s.event_id and e.slug = p_event
    where (p_dia is null or s.dia = p_dia)
      and (p_tema is null or s.topicos_aprendizado ? p_tema)
    order by s.dia, s.inicio
    limit p_limit) t;
$function$
;

CREATE OR REPLACE FUNCTION api.speakers(p_event text DEFAULT 'mind-summit-2026'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'nome', sp.nome, 'cargo', sp.cargo, 'organizacao', sp.organizacao,
           'bio', sp.bio, 'foto', sp.foto_url)), '[]')
  from comum.speakers sp
  where exists (select 1 from summit.session_speakers ss
                join summit.sessions s on s.id = ss.sessao_id
                join summit.events e on e.id = s.event_id and e.slug = p_event
                where ss.palestrante_id = sp.id);
$function$
;

CREATE OR REPLACE FUNCTION api.treble_event_bundle(p_event_slug text DEFAULT 'mind-summit-2026'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'summit', 'comum', 'engagement', 'intelligence', 'mind'
AS $function$
with ev as (
 select e.* from summit.events e where e.slug=p_event_slug and e.ativo limit 1
)
select jsonb_build_object(
 'event',(select jsonb_build_object(
   'slug',e.slug,'name',e.nome,'dates',e.dias,'location',e.local,'city',e.cidade,'timezone',e.fuso
 ) from ev e),
 'venues',coalesce((select jsonb_agg(jsonb_build_object(
   'slug',v.slug,'name',v.nome,'address',v.endereco,'transport',v.transporte,
   'accessibility',v.acessibilidade,'map_url',v.mapa_url
 ) order by v.nome) from summit.venues v join ev e on e.id=v.event_id where v.ativo),'[]'::jsonb),
 'locations',coalesce((select jsonb_agg(jsonb_build_object(
   'slug',l.slug,'name',l.nome,'type',l.tipo,'venue',v.nome,'parent',p.slug,
   'aliases',l.aliases,'description',l.descricao,'floor',l.andar,
   'how_to_get_there',l.como_chegar,'map_coordinates',l.coordenadas_mapa,
   'accessibility',l.acessibilidade
 ) order by l.tipo,l.nome)
 from summit.locations l join ev e on e.id=l.event_id
 left join summit.venues v on v.id=l.venue_id
 left join summit.locations p on p.id=l.parent_id where l.ativo),'[]'::jsonb),
 'program',coalesce((select jsonb_agg(jsonb_build_object(
   'id',s.id,'title',s.titulo,'description',s.descricao,'date',s.dia,
   'starts_at',s.inicio,'ends_at',s.fim,'location_slug',l.slug,'stage',l.nome,
   'type',s.tipo,'tracks',s.trilhas,'requires_reservation',s.precisa_reserva,
   'available_places',s.vagas_disponiveis,
   'speakers',coalesce((select jsonb_agg(jsonb_build_object(
      'name',sp.nome,'role',sp.cargo,'organization',sp.organizacao,'bio',sp.bio,'photo_url',sp.foto_url
    ) order by sp.nome)
    from summit.session_speakers ss join comum.speakers sp on sp.id=ss.palestrante_id
    where ss.sessao_id=s.id),'[]'::jsonb)
 ) order by s.inicio)
 from summit.sessions s join ev e on e.id=s.event_id
 left join summit.locations l on l.id=s.espaco_id),'[]'::jsonb),
 'speakers',coalesce((select jsonb_agg(distinct jsonb_build_object(
   'name',sp.nome,'role',sp.cargo,'organization',sp.organizacao,'bio',sp.bio,'photo_url',sp.foto_url
 ))
 from comum.speakers sp where exists(
   select 1 from summit.session_speakers ss join summit.sessions s on s.id=ss.sessao_id
   join ev e on e.id=s.event_id where ss.palestrante_id=sp.id
 )),'[]'::jsonb),
 'exhibitors',coalesce((select jsonb_agg(jsonb_build_object(
   'slug',x.slug,'name',x.nome,'description',x.descricao,'category',x.categoria,
   'location_slug',l.slug,'location',l.nome,'website_url',x.site_url
 ) order by x.nome)
 from summit.exhibitors x join ev e on e.id=x.event_id
 left join summit.locations l on l.id=x.location_id where x.ativo),'[]'::jsonb),
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
 from summit.offers o
 where o.ativo and o.publico and(o.event_id is null or o.event_id=(select id from ev))
 and(o.inicia_em is null or o.inicia_em<=now()) and(o.encerra_em is null or o.encerra_em>now())),'[]'::jsonb)
);
$function$
;

CREATE OR REPLACE FUNCTION api.treble_find_location(p_event_slug text, p_query text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'summit_2026', 'engagement', 'intelligence', 'mind', 'public'
AS $function$
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
  from summit_2026.locations l
  join summit_2026.events e on e.id = l.event_id
  left join summit_2026.venues v on v.id = l.venue_id
  left join summit_2026.locations p on p.id = l.parent_id
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
$function$
;

CREATE OR REPLACE FUNCTION api.treble_route(p_event_slug text, p_from_slug text, p_to_slug text, p_accessible boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'summit', 'comum', 'engagement', 'intelligence', 'mind'
AS $function$
with ev as(select id from summit.events where slug=p_event_slug and ativo limit 1),
src as(select l.id,l.nome from summit.locations l join ev on ev.id=l.event_id where l.slug=p_from_slug and l.ativo limit 1),
dst as(select l.id,l.nome from summit.locations l join ev on ev.id=l.event_id where l.slug=p_to_slug and l.ativo limit 1),
edge as(
 select r.*,s.nome origem_nome,d.nome destino_nome from summit.route_edges r
 join src s on(r.origem_location_id=s.id or(r.bidirecional and r.destino_location_id=s.id))
 join dst d on(r.destino_location_id=d.id or(r.bidirecional and r.origem_location_id=d.id))
 where r.ativo and(not p_accessible or r.acessivel) limit 1
)
select coalesce((select jsonb_build_object(
 'found',true,'from',origem_nome,'to',destino_nome,'instructions',instrucoes,
 'distance_meters',distancia_metros,'estimated_minutes',minutos_estimados,'accessible',acessivel
) from edge),jsonb_build_object('found',false));
$function$
;

CREATE OR REPLACE FUNCTION concierge.aplicar_evento_jornada()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'public'
AS $function$
declare
  objetiva boolean := new.origem in ('checkin','qr','reserva_usada');
begin
  insert into jornada_sessao (participante_id, sessao_id)
  values (new.participante_id, new.sessao_id)
  on conflict (participante_id, sessao_id) do nothing;

  update jornada_sessao set
    intencao = case new.tipo
                 when 'interesse' then 'interesse'
                 when 'planejou'  then 'planejada'
                 when 'reservou'  then 'reservada'
                 when 'removeu'   then 'removida'
                 else intencao end,
    intencao_forca = coalesce(new.dados->>'forca', intencao_forca,
                       case new.tipo when 'reservou' then 'alta'
                                     when 'planejou' then 'media'
                                     when 'interesse' then 'baixa' end),
    origem_intencao = case when new.tipo in ('interesse','planejou','reservou','removeu')
                           then new.origem else origem_intencao end,
    planejou = planejou or new.tipo in ('planejou','reservou'),
    compareceu = case
        when new.tipo in ('compareceu','nao_compareceu')
             and (confianca_presenca is distinct from 'objetiva' or objetiva)
        then (new.tipo = 'compareceu')
        else compareceu end,
    fonte_presenca = case
        when new.tipo in ('compareceu','nao_compareceu')
             and (confianca_presenca is distinct from 'objetiva' or objetiva)
        then new.origem else fonte_presenca end,
    confianca_presenca = case
        when new.tipo in ('compareceu','nao_compareceu')
             and (confianca_presenca is distinct from 'objetiva' or objetiva)
        then case when objetiva then 'objetiva'
                  when new.origem = 'conversa' then 'declarada'
                  else 'fraca' end
        else confianca_presenca end,
    motivo_ausencia = coalesce(new.dados->>'motivo', motivo_ausencia),
    atualizado_em = now()
  where participante_id = new.participante_id and sessao_id = new.sessao_id;

  return null;
end $function$
;

CREATE OR REPLACE FUNCTION concierge.bump_config_revisao()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'public'
AS $function$
begin
  update config_revisao set revisao = revisao + 1, atualizado_em = now() where id = 1;
  return null;
end $function$
;

CREATE OR REPLACE FUNCTION concierge.resumo_do_dia(p_participante uuid, p_dia date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'engagement', 'intelligence', 'summit', 'comum', 'concierge', 'mind', 'public'
AS $function$
  select jsonb_build_object(
    'objetivo', (
      select jsonb_build_object('pergunta_guia', o.pergunta_guia, 'dor', o.dor_codigo,
                                'decisao_pendente', o.decisao_pendente)
      from participante_objetivos o
      where o.participante_id = p_participante and o.status = 'ativo'
      order by o.definido_em desc limit 1),

    'contexto', (
      select jsonb_build_object('necessidades', c.necessidades,
                                'resultados_desejados', c.resultados_desejados,
                                'temas', c.temas_relevantes)
      from participante_contexto c where c.participante_id = p_participante),

    'planejadas', (
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo,
                                                   'inicio', s.inicio)), '[]')
      from jornada_sessao j join summit.sessions s on s.id = j.sessao_id
      where j.participante_id = p_participante and j.planejou and s.dia = p_dia),

    'assistidas', (
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo,
                                                   'fonte', j.fonte_presenca)), '[]')
      from jornada_sessao j join summit.sessions s on s.id = j.sessao_id
      where j.participante_id = p_participante and j.compareceu and s.dia = p_dia),

    'perdidas', (
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo,
                                                   'motivo', j.motivo_ausencia,
                                                   'frustrada', coalesce(m.demanda_frustrada,false))), '[]')
      from jornada_sessao j
      join summit.sessions s on s.id = j.sessao_id
      left join motivos_ausencia m on m.codigo = j.motivo_ausencia
      where j.participante_id = p_participante and j.compareceu = false and s.dia = p_dia),

    'avaliacoes', (
      select coalesce(jsonb_agg(jsonb_build_object('titulo', s.titulo, 'nota', f.nota,
                                                   'insight', f.insight,
                                                   'aplicar', f.intencao_aplicar)), '[]')
      from sessao_feedback f join summit.sessions s on s.id = f.sessao_id
      where f.participante_id = p_participante and s.dia = p_dia),

    'sugestoes_ja_feitas', (
      select coalesce(jsonb_agg(distinct jsonb_build_object('titulo', s.titulo,
                                                            'porque', r.justificativa,
                                                            'estado', r.estado)), '[]')
      from recomendacoes r left join summit.sessions s on s.id = r.sessao_id
      where r.participante_id = p_participante),

    'problemas_operacionais', (
      select coalesce(jsonb_agg(jsonb_build_object('categoria', e.categoria,
                                                   'severidade', e.severidade)), '[]')
      from evento_feedback e
      where e.participante_id = p_participante and e.criado_em::date = p_dia),

    'amanha_disponiveis', (
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo,
                                                   'inicio', s.inicio, 'espaco', s.espaco_id,
                                                   'topicos', s.topicos_aprendizado)), '[]')
      from summit.sessions s
      where s.dia > p_dia
        and s.id not in (select sessao_id from jornada_sessao
                         where participante_id = p_participante and compareceu))
  );
$function$
;

CREATE OR REPLACE FUNCTION credenciamento_summit_2026.normalizar_contato()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'credenciamento_summit_2026'
AS $function$
begin
  new.telefone_norm := public.telefone_normalizar(new.cellphone);
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION crm.buscar_pessoa(p_email text DEFAULT NULL::text, p_whatsapp text DEFAULT NULL::text, p_agente text DEFAULT 'desconhecido'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'crm', 'summit', 'comum', 'engagement', 'intelligence', 'mind'
AS $function$
declare
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_whats text := nullif(regexp_replace(coalesce(p_whatsapp, ''), '[^0-9]', '', 'g'), '');
  v_pessoa pessoas.pessoas%rowtype;
begin
  if v_whats is not null and length(v_whats) between 10 and 11 then
    v_whats := '55' || v_whats;
  end if;

  if v_email is null and v_whats is null then
    return jsonb_build_object('encontrado', false, 'motivo', 'sem_chave');
  end if;

  select * into v_pessoa from pessoas.pessoas
   where (v_email is not null and email = v_email)
   limit 1;

  if not found then
    select * into v_pessoa from pessoas.pessoas
     where (v_whats is not null and whatsapp = v_whats)
     limit 1;
  end if;

  if not found then
    return jsonb_build_object('encontrado', false, 'motivo', 'nao_cadastrado');
  end if;

  insert into crm.acessos (funcao, pessoa_id, agente)
  values ('crm.buscar_pessoa', v_pessoa.id, coalesce(p_agente, 'desconhecido'));

  return jsonb_build_object(
    'encontrado', true,
    'id', v_pessoa.id,
    'primeiro_nome', v_pessoa.primeiro_nome,
    'sobrenome', v_pessoa.sobrenome,
    'email', v_pessoa.email,
    'whatsapp', v_pessoa.whatsapp,
    'empresa', v_pessoa.empresa,
    'cargo', v_pessoa.cargo,
    'produtos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'codigo', pp.produto_codigo,
        'nome', pr.nome,
        'linha', pr.linha,
        'categoria', pp.categoria,
        'tipo_entrada', pp.tipo_entrada,
        'papel', pp.papel,
        'quantidade', pp.quantidade
      ) order by pr.comeca_em desc nulls last, pr.nome)
      from crm.pessoa_produtos pp
      join mind.produtos pr on pr.codigo = pp.produto_codigo
      where pp.pessoa_id = v_pessoa.id
    ), '[]'::jsonb),
    'dados_de', v_pessoa.sincronizado_em
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.contexto_comercial(p_email text DEFAULT NULL::text, p_whatsapp text DEFAULT NULL::text, p_agente text DEFAULT 'vendas'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'crm', 'catalogo'
AS $function$
declare
  v_base jsonb;
  v_id uuid;
  v_int crm.pessoas_interno%rowtype;
begin
  v_base := crm.buscar_pessoa(p_email, p_whatsapp, p_agente);
  if coalesce((v_base->>'encontrado')::boolean, false) is not true then
    return v_base;
  end if;

  v_id := (v_base->>'id')::uuid;
  select * into v_int from crm.pessoas_interno where pessoa_id = v_id;

  insert into crm.acessos (funcao, pessoa_id, agente)
  values ('crm.contexto_comercial', v_id, coalesce(p_agente, 'vendas'));

  return v_base || jsonb_build_object(
    'interno', jsonb_build_object(
      'origem_primeira', v_int.origem_primeira,
      'origem_ultima', v_int.origem_ultima,
      'utm', jsonb_strip_nulls(jsonb_build_object(
        'source', v_int.utm_source, 'medium', v_int.utm_medium,
        'campaign', v_int.utm_campaign, 'content', v_int.utm_content,
        'term', v_int.utm_term)),
      'dono', jsonb_strip_nulls(jsonb_build_object(
        'id', v_int.dono_id, 'nome', v_int.dono_nome)),
      'status_lead', v_int.status_lead,
      'negocios_associados', v_int.negocios_associados,
      'ultimo_contato_em', v_int.ultimo_contato_em,
      'perfil_cliente', v_int.perfil_cliente,
      'descadastrado_email', coalesce(v_int.descadastrado_email, false),
      'nps', coalesce((
        select jsonb_agg(jsonb_build_object(
          'produto', n.produto_codigo, 'nota', n.nota,
          'comentario', n.comentario, 'em', n.respondido_em))
        from crm.pessoa_nps n where n.pessoa_id = v_id
      ), '[]'::jsonb)
    ),
    'uso_interno', 'Estes sinais orientam tom e argumento. Nunca os repita ao usuario, nem confirme que existem.'
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.normalizar_pessoa()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'crm', 'public'
AS $function$
begin
  new.email := nullif(lower(btrim(coalesce(new.email, ''))), '');
  new.whatsapp := public.telefone_normalizar(new.whatsapp);
  new.atualizado_em := now();
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION crm.registrar_lead(p_email text DEFAULT NULL::text, p_whatsapp text DEFAULT NULL::text, p_primeiro_nome text DEFAULT NULL::text, p_sobrenome text DEFAULT NULL::text, p_empresa text DEFAULT NULL::text, p_cargo text DEFAULT NULL::text, p_agente text DEFAULT 'desconhecido'::text, p_contexto jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'crm'
AS $function$
declare
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_whats text := nullif(regexp_replace(coalesce(p_whatsapp, ''), '[^0-9]', '', 'g'), '');
  v_id uuid;
begin
  if v_whats is not null and length(v_whats) between 10 and 11 then
    v_whats := '55' || v_whats;
  end if;

  if v_email is null and v_whats is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_chave');
  end if;

  insert into crm.leads_capturados
    (email, whatsapp, primeiro_nome, sobrenome, empresa, cargo, agente, contexto)
  values
    (v_email, v_whats, nullif(btrim(coalesce(p_primeiro_nome, '')), ''),
     nullif(btrim(coalesce(p_sobrenome, '')), ''), nullif(btrim(coalesce(p_empresa, '')), ''),
     nullif(btrim(coalesce(p_cargo, '')), ''), coalesce(p_agente, 'desconhecido'),
     coalesce(p_contexto, '{}'::jsonb))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$function$
;

CREATE OR REPLACE FUNCTION ecossistema.palestrantes_slug_bi()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if new.slug is null or new.slug = '' then
    new.slug := ecossistema.slugify(new.nome);
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION ecossistema.slugify(txt text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select trim(both '-' from
    regexp_replace(
      translate(
        lower(coalesce(txt, '')),
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn'
      ),
      '[^a-z0-9]+', '-', 'g'
    )
  );
$function$
;

CREATE OR REPLACE FUNCTION eduzz.normalizar_contato()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'eduzz'
AS $function$
begin
  if tg_table_name = 'ingressos' then
    new.telefone_norm := public.telefone_normalizar(new.telefone);
  else
    -- cliente_fones pode trazer mais de um numero; o primeiro e o de cadastro
    new.cliente_telefone_norm := public.telefone_normalizar(split_part(coalesce(new.cliente_fones,''), ',', 1));
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION intelligence.vertical_da_entrada(p_site text DEFAULT NULL::text, p_url text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'engagement', 'catalogo'
AS $function$
  with s as (
    select nullif(lower(btrim(coalesce(p_site,''))),'') as site,
           nullif(lower(btrim(coalesce(p_url,''))),'')  as url
  ),
  h as (
    select regexp_replace((select url from s), '^https?://([^/]+).*$', '\1') as host
  ),
  m as (
    select p.vertical
    from engagement.origens o
    join catalogo.produtos p on p.codigo = o.produto_codigo
    where o.site is not null
      and (
        o.site = (select site from s)
        or ((select host from h) is not null and (select host from h) like '%' || o.site || '%')
      )
    order by length(o.site) desc
    limit 1
  )
  select (select vertical from m);
$function$
;

CREATE OR REPLACE FUNCTION mind.esquecer_participante(p_participante uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'concierge', 'public'
AS $function$
declare
  v_anonimo uuid;
begin
  insert into participantes (anonimo, nome) values (true, 'Participante removido')
  returning id into v_anonimo;

  delete from participante_contexto where participante_id = p_participante;
  delete from participante_memoria  where participante_id = p_participante;
  delete from mensagens             where participante_id = p_participante;
  delete from conversas             where participante_id = p_participante;
  delete from dossies               where participante_id = p_participante;
  delete from sinais_comerciais     where participante_id = p_participante;

  update jornada_sessao   set participante_id = v_anonimo where participante_id = p_participante;
  update jornada_eventos  set participante_id = v_anonimo where participante_id = p_participante;
  update sessao_feedback  set participante_id = v_anonimo where participante_id = p_participante;
  update evento_feedback  set participante_id = v_anonimo where participante_id = p_participante;
  update nps_summit       set participante_id = v_anonimo where participante_id = p_participante;

  delete from participantes where id = p_participante;
end $function$
;

CREATE OR REPLACE FUNCTION mind.pessoa_atual()
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select nullif(current_setting('mind.person_id', true), '')::uuid;
$function$
;

CREATE OR REPLACE FUNCTION mind.tocar()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'public'
AS $function$
begin
  new.atualizado_em := now();
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION pessoas.resolver_por_telefone(p_tel text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pessoas', 'crm', 'public'
AS $function$
declare
  v_wa  text := public.telefone_normalizar(p_tel);
  v_k   text;
  v_ce  crm.contato_espelho%rowtype;
  v_id  uuid;
begin
  if v_wa is null then return null; end if;
  v_k := right(v_wa, 8);   -- casa pelos 8 finais: imune ao 9 do celular e ao DDI

  select * into v_ce
  from crm.contato_espelho c
  where right(regexp_replace(coalesce(c.phone,''),'\D','','g'),8) = v_k
     or right(regexp_replace(coalesce(c.hs_whatsapp_phone_number,''),'\D','','g'),8) = v_k
  order by (c.email is not null) desc, c.atualizado_em desc nulls last
  limit 1;

  select p.id into v_id
  from pessoas.pessoas p
  where (v_ce.hubspot_id is not null and p.hubspot_id = v_ce.hubspot_id)
     or (v_ce.email is not null and lower(p.email) = lower(v_ce.email))
     or (p.whatsapp = v_wa)
  order by (p.hubspot_id is not null) desc
  limit 1;

  if v_id is null then
    insert into pessoas.pessoas (whatsapp, email, primeiro_nome, sobrenome, empresa, cargo, hubspot_id, origem)
    values (v_wa, v_ce.email, v_ce.firstname, v_ce.lastname, v_ce.company, v_ce.jobtitle, v_ce.hubspot_id, 'bot')
    on conflict (whatsapp) where whatsapp is not null
      do update set atualizado_em = now()
    returning id into v_id;
  else
    update pessoas.pessoas p set
      whatsapp      = coalesce(p.whatsapp, v_wa),
      email         = coalesce(p.email, v_ce.email),
      primeiro_nome = coalesce(p.primeiro_nome, v_ce.firstname),
      sobrenome     = coalesce(p.sobrenome, v_ce.lastname),
      empresa       = coalesce(p.empresa, v_ce.company),
      cargo         = coalesce(p.cargo, v_ce.jobtitle),
      hubspot_id    = coalesce(p.hubspot_id, v_ce.hubspot_id),
      atualizado_em = now()
    where p.id = v_id;
  end if;

  return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.analise_config()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence'
AS $function$
  select jsonb_object_agg(chave, valor) from intelligence.config
  where chave in ('analise_token', 'openai_model');
$function$
;

CREATE OR REPLACE FUNCTION public.analise_gravar(p_conversa_id uuid, p_analisador text, p_funcao text, p_vertical text, p_dados jsonb, p_modelo text DEFAULT NULL::text, p_prompt_versao integer DEFAULT 1)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence', 'engagement', 'pessoas'
AS $function$
declare v_part uuid; v_ult_id uuid; v_ult_ts timestamptz; v_analise uuid;
begin
  select participante_id into v_part from engagement.conversas where id = p_conversa_id;
  select id, criado_em into v_ult_id, v_ult_ts
    from engagement.mensagens where conversa_id = p_conversa_id
    order by criado_em desc, id desc limit 1;

  insert into intelligence.analise_conversa
    (conversa_id, participante_id, analisador, funcao, vertical, dados, modelo, prompt_versao,
     ultima_mensagem_analisada_id, conversa_atualizada_ate, analisado_em, atualizado_em)
  values (p_conversa_id, v_part, p_analisador, p_funcao, nullif(p_vertical,''),
          coalesce(p_dados,'{}'::jsonb), nullif(p_modelo,''), coalesce(p_prompt_versao,1),
          v_ult_id, v_ult_ts, now(), now())
  on conflict (conversa_id, analisador) do update set
    participante_id              = excluded.participante_id,
    funcao                       = excluded.funcao,
    vertical                     = excluded.vertical,
    dados                        = excluded.dados,
    modelo                       = excluded.modelo,
    prompt_versao                = excluded.prompt_versao,
    ultima_mensagem_analisada_id = excluded.ultima_mensagem_analisada_id,
    conversa_atualizada_ate      = excluded.conversa_atualizada_ate,
    analisado_em                 = now(),
    atualizado_em                = now()
  returning id into v_analise;

  begin
    perform public.analise_projetar_memoria(
      v_part, p_analisador, p_dados->'customer_memory', v_analise);
  exception when others then
    raise warning 'projecao_memoria falhou: %', sqlerrm;
  end;

  -- continuidade comercial (Silence Engine): nunca derruba a gravacao da analise
  begin
    perform public.silence_sync_from_analysis(v_analise);
  exception when others then
    raise warning 'silence_sync falhou: %', sqlerrm;
  end;
end $function$
;

CREATE OR REPLACE FUNCTION public.analise_montar_contexto(p_conversa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence', 'engagement', 'pessoas', 'crm'
AS $function$
declare
  c         engagement.conversas%rowtype;
  v_hub     text;
  v_vars    jsonb;
  v_cta     text;
  v_origem  jsonb;
  v_sessao  jsonb;
  v_crm_atr jsonb;
  v_atr     jsonb;
  v_ctx     jsonb;
begin
  select * into c from engagement.conversas where id = p_conversa_id;
  if not found then return null; end if;

  select hubspot_id into v_hub from pessoas.pessoas where id = c.participante_id;

  v_vars := case
    when jsonb_typeof(c.variables) = 'array' then (
      select coalesce(jsonb_object_agg(v->>'key', v->>'value')
             filter (where nullif(v->>'key','') is not null
                       and nullif(v->>'value','') is not null), '{}'::jsonb)
      from jsonb_array_elements(c.variables) v)
    when jsonb_typeof(c.variables) = 'object' then c.variables
    else '{}'::jsonb end;

  v_cta := nullif(trim(coalesce(
             v_vars->>'hubspot_opcao_selecionada_treble',
             v_vars->>'opcao_selecionada', '')), '');

  select to_jsonb(o) - 'atualizado_em' - 'hubspot' into v_origem
    from engagement.origens o where o.codigo = c.origem_codigo;

  -- 2) sessão de UTM do site (quando a conversa carrega o token)
  select jsonb_strip_nulls(to_jsonb(u) - 'token' - 'criado_em' - 'usado_em') into v_sessao
    from engagement.utm_sessoes u where u.token = c.utm_token;

  -- 3) atribuição que o HubSpot já conhece da pessoa
  select jsonb_strip_nulls(to_jsonb(x)) into v_crm_atr from (
    select utm_source, utm_medium, utm_campaign, utm_content, utm_term,
           msclkid, li_fat_id,
           hs_analytics_source, hs_analytics_source_data_1, hs_analytics_source_data_2,
           hs_analytics_first_url, hs_analytics_first_referrer, hs_analytics_first_timestamp,
           hs_latest_source, hs_latest_source_data_1, hs_latest_source_timestamp,
           hs_analytics_last_url, hs_analytics_last_referrer,
           first_conversion_event_name, first_conversion_date,
           hs_analytics_first_touch_converting_campaign,
           hs_analytics_last_touch_converting_campaign
    from crm.contato_espelho where hubspot_id = v_hub limit 1) x;

  v_atr := jsonb_strip_nulls(jsonb_build_object(
    'utm_conversa',   c.utm,
    'utm_token',      c.utm_token,
    'sessao_do_site', nullif(coalesce(v_sessao,'{}'::jsonb), '{}'::jsonb),
    'hubspot',        nullif(coalesce(v_crm_atr,'{}'::jsonb), '{}'::jsonb)
  ));

  v_ctx := jsonb_strip_nulls(jsonb_build_object(
    'canal',          c.canal,
    'agente',         c.agente,
    'origem_codigo',  c.origem_codigo,
    'origem',         v_origem,
    'produto_codigo', c.produto_codigo,
    'entry_action',   v_cta,
    'atribuicao',     nullif(coalesce(v_atr,'{}'::jsonb), '{}'::jsonb),
    'audience',       c.audience,
    'stage',          c.stage,
    'iniciada_em',    c.iniciada_em,
    'encerrada_em',   c.encerrada_em,
    'variables',      nullif(v_vars, '{}'::jsonb)
  ));

  return jsonb_build_object(
    'conversation_context', v_ctx,
    'conversa_id', p_conversa_id,
    'transcrito', coalesce((
       select jsonb_agg(jsonb_build_object('papel', m.papel, 'conteudo', m.conteudo)
                        order by m.criado_em)
       from engagement.mensagens m
       where m.conversa_id = p_conversa_id and m.conteudo is not null), '[]'::jsonb),
    'pessoa', (select to_jsonb(x) from (
       select primeiro_nome, sobrenome, email, empresa, cargo
       from pessoas.pessoas where id = c.participante_id) x),
    'crm', (select to_jsonb(y) from (
       select lead_tier, lead_icp, hs_lead_status, produto_de_interesse, motivo_do_lead__perdido,
              company, total_de_ingressos_comprados_lifetime, num_associated_deals, total_revenue
       from crm.contato_espelho where hubspot_id = v_hub limit 1) y)
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.analise_pendentes(p_limite integer DEFAULT 20)
 RETURNS TABLE(conversa_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'intelligence', 'engagement'
AS $function$
  with conv as (
    select c.id,
           (select max(m.criado_em) from engagement.mensagens m where m.conversa_id = c.id) as ult_msg
    from engagement.conversas c
    where c.agente in ('treble','treble-inbound-agent')
      and exists (select 1 from engagement.mensagens m2 where m2.conversa_id = c.id and m2.papel = 'lead')
  )
  select conv.id
  from conv
  where not exists (
    select 1 from intelligence.analise_conversa a
    where a.conversa_id = conv.id
      and a.conversa_atualizada_ate >= conv.ult_msg)
  order by conv.id
  limit greatest(1, p_limite);
$function$
;

CREATE OR REPLACE FUNCTION public.analise_projetar_memoria(p_participante uuid, p_analisador text, p_memorias jsonb, p_analise_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence'
AS $function$
declare
  mem jsonb; v_cat text; v_texto text; v_scope text; v_conf text;
  v_tipo text; v_chave text; v_valor jsonb; v_num numeric; v_status text;
  v_exist intelligence.participante_memoria%rowtype; v_novo uuid; v_n int := 0;
begin
  if p_participante is null or jsonb_typeof(p_memorias) <> 'array' then return 0; end if;

  for mem in select * from jsonb_array_elements(p_memorias)
  loop
    begin
      v_cat   := lower(nullif(trim(coalesce(mem->>'category','')),''));
      v_texto := nullif(trim(coalesce(mem->>'value','')),'');
      v_scope := lower(coalesce(nullif(trim(coalesce(mem->>'scope','')),''), 'opportunity'));
      v_conf  := lower(coalesce(nullif(trim(coalesce(mem->>'confidence','')),''), 'low'));

      continue when v_texto is null or v_cat is null or v_cat like '%|%';

      v_tipo := case v_cat
        when 'identity' then 'identidade'      when 'role' then 'cargo'
        when 'company' then 'empresa'          when 'goal' then 'objetivo'
        when 'interest' then 'interesse'       when 'preference' then 'preferencia'
        when 'constraint' then 'restricao'     when 'commercial_preference' then 'preferencia_comercial'
        when 'stakeholder' then 'stakeholder'  when 'delegation' then 'delegacao'
        when 'sponsorship' then 'patrocinio'   when 'logistics' then 'logistica'
        else 'outro' end;

      v_chave := case v_tipo
        when 'identidade' then 'identidade'
        when 'cargo'      then 'cargo_atual'
        when 'empresa'    then 'empresa_atual'
        else v_tipo || ':' || public.mind_slug(v_texto) end;

      v_valor := jsonb_build_object('text', v_texto, 'scope', v_scope);
      v_num   := case v_conf when 'high' then 0.90 when 'medium' then 0.70 else 0.50 end;
      v_status := case when v_scope = 'stable' and v_conf = 'high' then 'ativa' else 'proposta' end;

      select * into v_exist from intelligence.participante_memoria pm
       where pm.participante_id = p_participante and pm.chave = v_chave
         and pm.status in ('ativa','proposta')
       order by (pm.status = 'ativa') desc, pm.atualizado_em desc nulls last
       limit 1;

      if found then
        if v_exist.valor->>'text' is not distinct from v_texto then
          update intelligence.participante_memoria
             set confianca           = greatest(coalesce(confianca, 0), v_num),
                 status              = case when status = 'ativa' or v_status = 'ativa'
                                            then 'ativa' else status end,
                 analise_conversa_id = coalesce(p_analise_id, analise_conversa_id),
                 atualizado_em       = now()
           where id = v_exist.id;
        elsif v_chave in ('identidade','cargo_atual','empresa_atual') then
          insert into intelligence.participante_memoria
            (participante_id, tipo, chave, valor, confianca, origem, status,
             evidencia_message_id, analise_conversa_id)
          values (p_participante, v_tipo, v_chave, v_valor, v_num, p_analisador, v_status,
                  null, p_analise_id)
          returning id into v_novo;
          update intelligence.participante_memoria
             set status = 'substituida', substituida_por = v_novo, atualizado_em = now()
           where id = v_exist.id;
          v_n := v_n + 1;
        end if;
      else
        insert into intelligence.participante_memoria
          (participante_id, tipo, chave, valor, confianca, origem, status,
           evidencia_message_id, analise_conversa_id)
        values (p_participante, v_tipo, v_chave, v_valor, v_num, p_analisador, v_status,
                null, p_analise_id);
        v_n := v_n + 1;
      end if;
    exception when others then
      raise warning 'projecao_memoria falhou p/ item: %', sqlerrm;
    end;
  end loop;

  return v_n;
end $function$
;

CREATE OR REPLACE FUNCTION public.analise_prompt(p_chave text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'agentes'
AS $function$
  select jsonb_build_object('conteudo', conteudo, 'versao', versao)
  from agentes.prompts
  where chave = p_chave and ativo is true and length(trim(conteudo)) > 0
  limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.espelho_config()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence'
AS $function$
  select jsonb_object_agg(chave, valor)
    from intelligence.config
   where chave like 'vendas_espelho_%' or chave like 'hubpost_espelho_%';
$function$
;

CREATE OR REPLACE FUNCTION public.espelho_estado_set(p_fonte text, p_status text, p_total_origem integer DEFAULT NULL::integer, p_lidos integer DEFAULT NULL::integer, p_gravados integer DEFAULT NULL::integer, p_erro text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.espelho_estado set
    status             = p_status,
    total_na_origem    = coalesce(p_total_origem, total_na_origem),
    registros_lidos    = coalesce(p_lidos,    case when p_status = 'rodando' then 0 else registros_lidos end),
    registros_gravados = coalesce(p_gravados, case when p_status = 'rodando' then 0 else registros_gravados end),
    erro               = p_erro,
    iniciado_em        = case when p_status = 'rodando' then now() else iniciado_em end,
    concluido_em       = case when p_status in ('ok','erro') then now() else concluido_em end,
    atualizado_em      = now()
  where fonte = p_fonte;
$function$
;

CREATE OR REPLACE FUNCTION public.espelho_gravar(p_fonte text, p_linhas jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'eduzz', 'credenciamento_summit_2026', 'pessoas', 'engagement'
AS $function$
declare v_n integer := 0;
begin
  if p_linhas is null or jsonb_array_length(p_linhas) = 0 then
    return 0;
  end if;

  -- --- Eduzz: bilheteria e vendas (nomes de coluna diferem da origem) -------
  if p_fonte = 'blinket' then
    delete from eduzz.ingressos
     where uuid in (select l->>'uuid' from jsonb_array_elements(p_linhas) l);
    insert into eduzz.ingressos
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::eduzz.ingressos,
        (l - 'e_mail' - 'e_mail_comprador' - 'criado_em' - 'atualizado_em')
        || jsonb_build_object(
             'email',                l->>'e_mail',
             'email_comprador',      l->>'e_mail_comprador',
             'origem_criado_em',     l->>'criado_em',
             'origem_atualizado_em', l->>'atualizado_em',
             'sincronizado_em',      now())) r
     where l->>'uuid' is not null;

  elsif p_fonte = 'vendas' then
    delete from eduzz.vendas
     where linha_origem in (select (l->>'linha_origem')::integer from jsonb_array_elements(p_linhas) l
                             where l->>'linha_origem' is not null);
    insert into eduzz.vendas
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::eduzz.vendas,
        (l - 'cliente_e_mail' - 'importado_em')
        || jsonb_build_object(
             'cliente_email',       l->>'cliente_e_mail',
             'origem_importado_em', l->>'importado_em',
             'sincronizado_em',     now())) r
     where l->>'linha_origem' is not null;

  -- --- daqui pra baixo os nomes batem: so injeta o carimbo -------------------
  elsif p_fonte = 'produtos' then
    delete from eduzz.produtos
     where eduzz_product_id in (select l->>'eduzz_product_id' from jsonb_array_elements(p_linhas) l);
    insert into eduzz.produtos
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::eduzz.produtos,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'eduzz_product_id' is not null;

  elsif p_fonte = 'produto_catalogo' then
    delete from eduzz.produto_catalogo
     where id in (select (l->>'id')::uuid from jsonb_array_elements(p_linhas) l where l->>'id' is not null);
    insert into eduzz.produto_catalogo
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::eduzz.produto_catalogo,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'id' is not null;

  elsif p_fonte = 'hubspot_stage_config' then
    delete from eduzz.hubspot_stage_config h
     where exists (select 1 from jsonb_array_elements(p_linhas) l
                    where l->>'hubspot_pipeline_id' = h.hubspot_pipeline_id
                      and l->>'evento_eduzz'        = h.evento_eduzz);
    insert into eduzz.hubspot_stage_config
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::eduzz.hubspot_stage_config,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'hubspot_pipeline_id' is not null and l->>'evento_eduzz' is not null;

  -- --- Credenciamento Summit 2026 -------------------------------------------
  elsif p_fonte = 'cred_participantes' then
    delete from credenciamento_summit_2026.participantes
     where id in (select (l->>'id')::uuid from jsonb_array_elements(p_linhas) l where l->>'id' is not null);
    insert into credenciamento_summit_2026.participantes
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::credenciamento_summit_2026.participantes,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'id' is not null;

  elsif p_fonte = 'cred_yazo_fila' then
    delete from credenciamento_summit_2026.yazo_envio_fila
     where id in (select (l->>'id')::uuid from jsonb_array_elements(p_linhas) l where l->>'id' is not null);
    insert into credenciamento_summit_2026.yazo_envio_fila
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::credenciamento_summit_2026.yazo_envio_fila,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'id' is not null;

  elsif p_fonte = 'cred_yazo_espelho' then
    delete from credenciamento_summit_2026.yazo_espelho
     where yazo_id in (select (l->>'yazo_id')::bigint from jsonb_array_elements(p_linhas) l
                        where l->>'yazo_id' is not null);
    insert into credenciamento_summit_2026.yazo_espelho
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::credenciamento_summit_2026.yazo_espelho,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'yazo_id' is not null;

  elsif p_fonte = 'cred_yazo_sync_state' then
    delete from credenciamento_summit_2026.yazo_sync_state
     where id in (select (l->>'id')::integer from jsonb_array_elements(p_linhas) l where l->>'id' is not null);
    insert into credenciamento_summit_2026.yazo_sync_state
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::credenciamento_summit_2026.yazo_sync_state,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'id' is not null;

  else
    raise exception 'fonte desconhecida: %', p_fonte;
  end if;

  get diagnostics v_n = row_count;
  return v_n;
end $function$
;

CREATE OR REPLACE FUNCTION public.mind_admin_dashboard_counts()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'sessions', (select count(*) from summit.sessions),
    'speakers', (select count(*) from comum.speakers),
    'spaces', (select count(*) from summit.locations where ativo),
    'booths', (select count(*) from summit.exhibitors where ativo),
    'active_offers', (select count(*) from summit.offers where ativo),
    'documents', (select count(*) from summit.conhecimento where ativo),
    'documents_pending', (
      select count(*)
      from summit.conhecimento d
      where d.ativo
        and (
          not exists (select 1 from summit.conhecimento_chunks c where c.doc_id = d.id)
          or exists (
            select 1 from summit.conhecimento_chunks c
            where c.doc_id = d.id and (c.stale or c.embedding is null)
          )
        )
    ),
    'unanswered', (
      select count(*)
      from intelligence.perguntas_feitas
      where not respondida and not recusada
    ),
    'conversations_24h', (
      select count(*)
      from engagement.conversas
      where ultima_atividade >= now() - interval '24 hours'
    ),
    'sessions_without_space', (
      select count(*) from summit.sessions where espaco_id is null
    ),
    'sessions_without_speaker', (
      select count(*)
      from summit.sessions s
      where not exists (
        select 1 from summit.session_speakers ss where ss.sessao_id = s.id
      )
    ),
    'spaces_without_directions', (
      select count(*)
      from summit.locations
      where ativo and nullif(btrim(como_chegar), '') is null
    ),
    'stages_without_alias', (
      select count(*)
      from summit.locations
      where ativo
        and lower(tipo) in ('palco','arena')
        and coalesce(cardinality(aliases), 0) = 0
    ),
    'offers_without_checkout', (
      select count(*)
      from summit.offers
      where ativo and nullif(btrim(checkout_url), '') is null
    ),
    'generated_at', now()
  );
$function$
;

CREATE OR REPLACE FUNCTION public.mind_admin_mutate_resource(p_action text, p_resource text, p_id uuid, p_payload jsonb, p_expected_updated_at text, p_actor_id uuid, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'auth'
AS $function$
declare
  v_role text;
  v_before jsonb;
  v_after jsonb;
  v_id uuid := p_id;
  v_event_id uuid;
  v_venue_id uuid;
  v_timezone text;
  v_day date;
  v_start timestamptz;
  v_end timestamptz;
  v_label text;
  v_status text;
begin
  select role into v_role
  from public.mind_admin_users
  where user_id = p_actor_id and active;

  if v_role is null then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;

  if p_action = 'criar' and v_role not in ('administrador','editor') then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  elsif p_action = 'atualizar' and v_role not in ('administrador','editor','aprovador') then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  elsif p_action in ('publicar','arquivar') and v_role not in ('administrador','aprovador') then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  elsif p_action not in ('criar','atualizar','publicar','arquivar') then
    raise exception using errcode = '22023', message = 'admin_validation:acao_invalida';
  end if;

  if p_action <> 'criar' then
    if v_id is null then
      raise exception using errcode = '22023', message = 'admin_validation:id_obrigatorio';
    end if;
    v_before := public.mind_admin_read_resource(p_resource, v_id)->0;
    if v_before is null then
      raise exception using errcode = 'P0002', message = 'admin_not_found';
    end if;
    if p_expected_updated_at is null or btrim(p_expected_updated_at) = '' then
      raise exception using errcode = '22023', message = 'admin_validation:versao_obrigatoria';
    end if;
    if (v_before->>'atualizadoEm')::timestamptz <> p_expected_updated_at::timestamptz then
      raise exception using errcode = '40001', message = 'admin_conflict';
    end if;
  end if;

  select id, fuso into v_event_id, v_timezone
  from summit.events
  order by ativo desc, atualizado_em desc
  limit 1;
  if v_event_id is null then
    raise exception using errcode = 'P0002', message = 'admin_not_found:evento_padrao';
  end if;

  if p_resource = 'event' then
    if p_action <> 'atualizar' then
      raise exception using errcode = '22023', message = 'admin_validation:acao_nao_suportada';
    end if;
    if nullif(btrim(p_payload->>'nome'), '') is null
       or nullif(btrim(p_payload->>'slug'), '') is null
       or nullif(btrim(p_payload->>'dataInicio'), '') is null
       or nullif(btrim(p_payload->>'dataFim'), '') is null then
      raise exception using errcode = '22023', message = 'admin_validation:campos_obrigatorios';
    end if;
    update summit.events set
      nome = p_payload->>'nome',
      slug = p_payload->>'slug',
      dias = case when p_payload->>'dataInicio' = p_payload->>'dataFim'
        then array[(p_payload->>'dataInicio')::date]
        else array[(p_payload->>'dataInicio')::date, (p_payload->>'dataFim')::date] end,
      local = p_payload->>'local',
      cidade = p_payload->>'cidade',
      fuso = p_payload->>'fusoHorario',
      ativo = coalesce((p_payload->>'ativo')::boolean, ativo),
      atualizado_em = clock_timestamp()
    where id = v_id;

    insert into public.mind_admin_event_details (
      event_id, descricao, regra_reserva, regra_vagas, updated_by, updated_at
    ) values (
      v_id, coalesce(p_payload->>'descricao',''), coalesce(p_payload->>'regraReserva',''),
      coalesce(p_payload->>'regraVagas',''), p_actor_id, clock_timestamp()
    ) on conflict (event_id) do update set
      descricao = excluded.descricao,
      regra_reserva = excluded.regra_reserva,
      regra_vagas = excluded.regra_vagas,
      updated_by = excluded.updated_by,
      updated_at = excluded.updated_at;

    insert into summit.event_rules (chave,titulo,texto,aplica_em,prioridade,ativo,atualizado_em,event_id)
    values
      ('admin-regra-reserva','Regras de reserva',coalesce(p_payload->>'regraReserva',''),array['reserva'],0,true,clock_timestamp(),v_id),
      ('admin-regra-vagas','Regras de vagas',coalesce(p_payload->>'regraVagas',''),array['vagas'],0,true,clock_timestamp(),v_id)
    on conflict (chave) do update set texto=excluded.texto, ativo=true, atualizado_em=excluded.atualizado_em, event_id=excluded.event_id;

  elsif p_resource = 'sessions' then
    if p_action = 'criar' then
      v_id := gen_random_uuid();
      v_day := (p_payload->>'dia')::date;
      v_start := ((p_payload->>'dia') || ' ' || (p_payload->>'inicio'))::timestamp at time zone v_timezone;
      v_end := case when coalesce(p_payload->>'fim','') = '' then null
        else ((p_payload->>'dia') || ' ' || (p_payload->>'fim'))::timestamp at time zone v_timezone end;
      insert into summit.sessions (
        id,titulo,descricao,dia,inicio,fim,espaco_id,tipo,formato,trilhas,precisa_reserva,
        vagas_total,vagas_disponiveis,topicos_aprendizado,resultados,nivel,event_id,atualizado_em
      ) values (
        v_id,p_payload->>'titulo',coalesce(p_payload->>'descricao',''),v_day,v_start,v_end,
        nullif(p_payload->>'espacoId','')::uuid,
        case when p_payload->>'tipo'='em_curadoria' then 'em-curadoria' else p_payload->>'tipo' end,
        p_payload->>'formato',array(select jsonb_array_elements_text(coalesce(p_payload->'trilhas','[]'::jsonb))),
        coalesce((p_payload->>'necessitaReserva')::boolean,false),
        nullif(p_payload->>'vagasTotais','')::integer,nullif(p_payload->>'vagasDisponiveis','')::integer,
        coalesce(p_payload->'temas','[]'::jsonb),coalesce(p_payload->'resultadosEsperados','[]'::jsonb),
        nullif(p_payload->>'nivel',''),v_event_id,clock_timestamp()
      );
      v_status := coalesce(p_payload->>'status','rascunho');
      insert into public.mind_admin_editorial(resource,record_id,status,updated_by,updated_at)
      values('sessions',v_id,v_status,p_actor_id,clock_timestamp());
    elsif p_action = 'atualizar' then
      v_day := coalesce(nullif(p_payload->>'dia','')::date,(v_before->>'dia')::date);
      v_start := (v_day::text || ' ' || coalesce(nullif(p_payload->>'inicio',''),v_before->>'inicio'))::timestamp at time zone v_timezone;
      v_end := case when p_payload ? 'fim' and coalesce(p_payload->>'fim','') = '' then null
        else (v_day::text || ' ' || coalesce(nullif(p_payload->>'fim',''),v_before->>'fim'))::timestamp at time zone v_timezone end;
      update summit.sessions set
        titulo=coalesce(p_payload->>'titulo',titulo), descricao=coalesce(p_payload->>'descricao',descricao),
        dia=v_day,inicio=v_start,fim=v_end,
        espaco_id=case when p_payload ? 'espacoId' then nullif(p_payload->>'espacoId','')::uuid else espaco_id end,
        tipo=case when p_payload ? 'tipo' then case when p_payload->>'tipo'='em_curadoria' then 'em-curadoria' else p_payload->>'tipo' end else tipo end,
        formato=coalesce(p_payload->>'formato',formato),
        trilhas=case when p_payload ? 'trilhas' then array(select jsonb_array_elements_text(p_payload->'trilhas')) else trilhas end,
        precisa_reserva=case when p_payload ? 'necessitaReserva' then (p_payload->>'necessitaReserva')::boolean else precisa_reserva end,
        vagas_total=case when p_payload ? 'vagasTotais' then nullif(p_payload->>'vagasTotais','')::integer else vagas_total end,
        vagas_disponiveis=case when p_payload ? 'vagasDisponiveis' then nullif(p_payload->>'vagasDisponiveis','')::integer else vagas_disponiveis end,
        topicos_aprendizado=case when p_payload ? 'temas' then p_payload->'temas' else topicos_aprendizado end,
        resultados=case when p_payload ? 'resultadosEsperados' then p_payload->'resultadosEsperados' else resultados end,
        nivel=case when p_payload ? 'nivel' then nullif(p_payload->>'nivel','') else nivel end,
        atualizado_em=clock_timestamp()
      where id=v_id;
      insert into public.mind_admin_editorial(resource,record_id,status,updated_by,updated_at)
      values('sessions',v_id,coalesce(p_payload->>'status',v_before->>'status'),p_actor_id,clock_timestamp())
      on conflict(resource,record_id) do update set status=excluded.status,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
    elsif p_action in ('publicar','arquivar') then
      update public.mind_admin_editorial set
        status=case when p_action='publicar' then 'publicado' else 'arquivado' end,
        published_at=case when p_action='publicar' then clock_timestamp() else published_at end,
        published_by=case when p_action='publicar' then p_actor_id else published_by end,
        updated_by=p_actor_id,updated_at=clock_timestamp()
      where resource='sessions' and record_id=v_id;
    end if;

    if p_action in ('criar','atualizar') and p_payload ? 'palestranteIds' then
      delete from summit.session_speakers where sessao_id=v_id;
      insert into summit.session_speakers(sessao_id,palestrante_id)
      select v_id, value::uuid from jsonb_array_elements_text(p_payload->'palestranteIds') value;
    end if;

  elsif p_resource = 'speakers' then
    if p_action = 'criar' then
      v_id := gen_random_uuid();
      insert into comum.speakers(id,nome,cargo,organizacao,bio,foto_url,destaque,temas,atualizado_em)
      values(v_id,p_payload->>'nome',coalesce(p_payload->>'cargo',''),coalesce(p_payload->>'organizacao',''),
        coalesce(p_payload->>'biografia',''),nullif(p_payload->>'foto',''),coalesce((p_payload->>'destaque')::boolean,false),
        array(select jsonb_array_elements_text(coalesce(p_payload->'temas','[]'::jsonb))),clock_timestamp());
      insert into public.mind_admin_editorial(resource,record_id,status,updated_by,updated_at)
      values('speakers',v_id,coalesce(p_payload->>'status','rascunho'),p_actor_id,clock_timestamp());
    elsif p_action = 'atualizar' then
      update comum.speakers set
        nome=coalesce(p_payload->>'nome',nome),cargo=coalesce(p_payload->>'cargo',cargo),
        organizacao=coalesce(p_payload->>'organizacao',organizacao),bio=coalesce(p_payload->>'biografia',bio),
        foto_url=case when p_payload ? 'foto' then nullif(p_payload->>'foto','') else foto_url end,
        destaque=case when p_payload ? 'destaque' then (p_payload->>'destaque')::boolean else destaque end,
        temas=case when p_payload ? 'temas' then array(select jsonb_array_elements_text(p_payload->'temas')) else temas end,
        atualizado_em=clock_timestamp()
      where id=v_id;
      insert into public.mind_admin_editorial(resource,record_id,status,updated_by,updated_at)
      values('speakers',v_id,coalesce(p_payload->>'status',v_before->>'status'),p_actor_id,clock_timestamp())
      on conflict(resource,record_id) do update set status=excluded.status,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
    elsif p_action in ('publicar','arquivar') then
      update public.mind_admin_editorial set
        status=case when p_action='publicar' then 'publicado' else 'arquivado' end,
        published_at=case when p_action='publicar' then clock_timestamp() else published_at end,
        published_by=case when p_action='publicar' then p_actor_id else published_by end,
        updated_by=p_actor_id,updated_at=clock_timestamp()
      where resource='speakers' and record_id=v_id;
    end if;

  elsif p_resource = 'spaces' then
    if p_action = 'criar' then
      v_id := gen_random_uuid();
      select id into v_venue_id from summit.venues where event_id=v_event_id order by ativo desc limit 1;
      insert into summit.locations(id,nome,slug,tipo,aliases,descricao,como_chegar,event_id,venue_id,parent_id,andar,coordenadas_mapa,acessibilidade,ativo,atualizado_em)
      values(v_id,p_payload->>'nome',p_payload->>'slug',p_payload->>'tipo',
        array(select jsonb_array_elements_text(coalesce(p_payload->'aliases','[]'::jsonb))),coalesce(p_payload->>'descricao',''),
        coalesce(p_payload->>'comoChegar',''),v_event_id,v_venue_id,nullif(p_payload->>'espacoPaiId','')::uuid,
        nullif(p_payload->>'andar',''),jsonb_build_object('x_percent',p_payload->'coordenadaX','y_percent',p_payload->'coordenadaY'),
        jsonb_build_object('acessivel',coalesce((p_payload->>'acessivel')::boolean,false),'observacao',coalesce(p_payload->>'observacaoAcessibilidade',''),'verificada',true),
        coalesce((p_payload->>'ativo')::boolean,true),clock_timestamp());
    elsif p_action = 'atualizar' then
      update summit.locations set
        nome=coalesce(p_payload->>'nome',nome),slug=coalesce(p_payload->>'slug',slug),tipo=coalesce(p_payload->>'tipo',tipo),
        aliases=case when p_payload ? 'aliases' then array(select jsonb_array_elements_text(p_payload->'aliases')) else aliases end,
        descricao=coalesce(p_payload->>'descricao',descricao),como_chegar=coalesce(p_payload->>'comoChegar',como_chegar),
        parent_id=case when p_payload ? 'espacoPaiId' then nullif(p_payload->>'espacoPaiId','')::uuid else parent_id end,
        andar=case when p_payload ? 'andar' then nullif(p_payload->>'andar','') else andar end,
        coordenadas_mapa=case when p_payload ? 'coordenadaX' or p_payload ? 'coordenadaY' then
          jsonb_build_object('x_percent',p_payload->'coordenadaX','y_percent',p_payload->'coordenadaY') else coordenadas_mapa end,
        acessibilidade=case when p_payload ? 'acessivel' or p_payload ? 'observacaoAcessibilidade' then
          jsonb_build_object('acessivel',coalesce((p_payload->>'acessivel')::boolean,false),'observacao',coalesce(p_payload->>'observacaoAcessibilidade',''),'verificada',true)
          else acessibilidade end,
        ativo=case when p_payload ? 'ativo' then (p_payload->>'ativo')::boolean else ativo end,
        atualizado_em=clock_timestamp()
      where id=v_id;
    elsif p_action = 'arquivar' then
      update summit.locations set ativo=false,atualizado_em=clock_timestamp() where id=v_id;
    else
      raise exception using errcode='22023',message='admin_validation:acao_nao_suportada';
    end if;
  else
    raise exception using errcode='22023',message='admin_validation:recurso_nao_suportado';
  end if;

  v_after := public.mind_admin_read_resource(p_resource,v_id)->0;
  if v_after is null then
    raise exception using errcode='P0002',message='admin_not_found';
  end if;
  v_label := coalesce(v_after->>'titulo',v_after->>'nome',v_id::text);

  insert into public.mind_admin_audit(
    actor_user_id,action,resource,record_id,record_label,before_data,after_data,request_id
  ) values (
    p_actor_id,p_action,p_resource,v_id::text,v_label,v_before,v_after,p_request_id
  );

  return v_after;
exception
  when invalid_text_representation or datetime_field_overflow or check_violation or not_null_violation or foreign_key_violation then
    raise exception using errcode='22023',message='admin_validation:dados_invalidos';
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_admin_read_resource(p_resource text, p_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'summit', 'comum', 'engagement', 'intelligence', 'mind'
AS $function$
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
      from summit.events e
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
            from summit.session_speakers ss join comum.speakers sp on sp.id = ss.palestrante_id
            where ss.sessao_id = s.id
          ), '[]'::jsonb),
          'quemTexto', coalesce((
            select string_agg(sp.nome, ', ' order by sp.nome)
            from summit.session_speakers ss join comum.speakers sp on sp.id = ss.palestrante_id
            where ss.sessao_id = s.id
          ), ''),
          'necessitaReserva', s.precisa_reserva,
          'vagasTotais', s.vagas_total,
          'vagasDisponiveis', s.vagas_disponiveis,
          'nivel', s.nivel,
          'resultadosEsperados', coalesce(s.resultados, '[]'::jsonb)
        ) obj
      from summit.sessions s
      left join summit.events e on e.id = s.event_id
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
            from summit.session_speakers ss where ss.palestrante_id = sp.id
          ), '[]'::jsonb)
        ) obj
      from comum.speakers sp
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
      from summit.locations l
      left join summit.venues v on v.id = l.venue_id
      where p_id is null or l.id = p_id
    ) x;

  elsif p_resource = 'themes' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.codigo,
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
      from summit.sessions s
    ) t;
  else
    raise exception using errcode = '22023', message = 'recurso_nao_suportado';
  end if;

  return v_result;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_agent_context(p_conversa_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
with
conversa as (
  select c.id, c.participante_id, c.canal, c.origem_codigo, c.produto_codigo, c.variables
    from engagement.conversas c
   where c.id = p_conversa_id
),
pessoa as (
  select cv.participante_id as pessoa_id from conversa cv where cv.participante_id is not null
),

-- Cada coletor uma vez.
coletores as (
  select p.pessoa_id,
         public.mind_pessoa_fatos(p.pessoa_id)     as person,
         public.mind_crm_fatos(p.pessoa_id)        as crm,
         public.mind_crm_comercial(p.pessoa_id)    as commercial,
         public.mind_engagement_fatos(p.pessoa_id) as engajamento
    from pessoa p
),

-- ENTRY. So fato da entrada atual. `variables` nunca sai cru: dele se extrai apenas a CTA.
-- A normalizacao das duas formas possiveis (array de {key,value} vindo do session.close,
-- objeto quando o agente escreve) e a mesma ja provada em analise_montar_contexto.
vars as (
  select case
           when jsonb_typeof(cv.variables) = 'array' then (
             select coalesce(jsonb_object_agg(v->>'key', v->>'value')
                      filter (where nullif(v->>'key','') is not null
                                and nullif(v->>'value','') is not null),
                    '{}'::jsonb)
               from jsonb_array_elements(cv.variables) v)
           when jsonb_typeof(cv.variables) = 'object' then cv.variables
           else '{}'::jsonb
         end as j
    from conversa cv
),
entrada as (
  select jsonb_build_object(
           'canal',          cv.canal,
           'origem_codigo',  cv.origem_codigo,
           'origem',         (select jsonb_build_object(
                                       'site',         o.site,
                                       'botao_rotulo', o.botao_rotulo,
                                       'descricao',    o.descricao)
                                from engagement.origens o
                               where o.codigo = cv.origem_codigo),
           'produto_codigo', cv.produto_codigo,
           'entry_action',   nullif(btrim(coalesce(
                               (select j->>'hubspot_opcao_selecionada_treble' from vars),
                               (select j->>'opcao_selecionada'                from vars),
                               '')), '')
         ) as j
    from conversa cv
),

-- A conversa atual sai de dentro do proprio coletor, na linguagem dele. As demais mantem
-- a ordem deterministica do coletor (iniciada_em, id) — WITH ORDINALITY preserva o array.
conversas_do_coletor as (
  select c.valor, c.ord
    from coletores k,
         lateral jsonb_array_elements(k.engajamento->'conversas') with ordinality c(valor, ord)
),
atual as (
  select c.valor as j from conversas_do_coletor c
   where (c.valor->>'conversa_id')::uuid = p_conversa_id
   limit 1
),
anteriores as (
  select coalesce(jsonb_agg(c.valor order by c.ord), '[]'::jsonb) as j
    from conversas_do_coletor c
   where (c.valor->>'conversa_id')::uuid is distinct from p_conversa_id
)

select case
  when p_conversa_id is null then
    jsonb_build_object('ok', false, 'motivo', 'sem_conversa')
  when not exists (select 1 from conversa) then
    jsonb_build_object('ok', false, 'motivo', 'conversa_nao_encontrada', 'conversa_id', p_conversa_id)
  when not exists (select 1 from pessoa) then
    jsonb_build_object('ok', false, 'motivo', 'conversa_sem_pessoa', 'conversa_id', p_conversa_id)
  else
    jsonb_build_object(
      'ok',           true,
      'pessoa_id',    (select pessoa_id from coletores),
      'conversa_id',  p_conversa_id,
      'person',       (select person     from coletores),
      'crm',          (select crm        from coletores),
      'commercial',   (select commercial from coletores),
      'entry',        (select j from entrada),
      'conversation', (select j from atual),
      -- historico factual pessoa-wide inteiro, nao contador: as outras conversas vem
      -- completas, com suas mensagens. Engagement factual nao e Memory.
      'engagement',   jsonb_build_object(
                        'resumo',               (select engajamento->'resumo' from coletores),
                        'conversas_anteriores', (select j from anteriores),
                        'meta',                 (select engajamento->'meta'   from coletores)))
end
$function$
;

CREATE OR REPLACE FUNCTION public.mind_calendario(p_produto text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'treble'
AS $function$
  with alvo as (
    select p.* from mind.produtos p
    where p.codigo = coalesce(
      nullif(p_produto,''),
      (select valor from treble.config where chave = 'produto_padrao'))
  ), hoje as (
    select (now() at time zone 'America/Sao_Paulo')::date as d
  ), calc as (
    select a.codigo, a.nome, a.linha, a.vende, a.comeca_em, a.encerra_em, h.d as hoje,
           (a.comeca_em - h.d) as dias_ate_comecar,
           case
             when a.comeca_em is null then 'sem_data'
             when h.d > a.encerra_em then 'encerrado'
             when h.d >= a.comeca_em then 'acontecendo'
             when (a.comeca_em - h.d) <= 7 then 'semana_do_evento'
             else 'venda'
           end as fase
    from alvo a cross join hoje h
  )
  select case when (select count(*) from calc) = 0 then null else (
    select jsonb_build_object(
      'produto', c.codigo,
      'nome', c.nome,
      'hoje', to_char(c.hoje, 'DD/MM/YYYY'),
      'comeca_em', to_char(c.comeca_em, 'DD/MM/YYYY'),
      'encerra_em', to_char(c.encerra_em, 'DD/MM/YYYY'),
      'dias_ate_comecar', c.dias_ate_comecar,
      'fase', c.fase,
      'pode_vender', c.vende and c.fase in ('venda','semana_do_evento','acontecendo'),
      'o_que_fazer', case c.fase
        when 'venda' then 'Faltam ' || c.dias_ate_comecar || ' dias para o evento. Modo venda normal.'
        when 'semana_do_evento' then 'E a semana do evento: faltam ' || c.dias_ate_comecar ||
             ' dias. Ainda vende, mas ja responda tambem duvidas de quem vai (credenciamento, local, horario).'
        when 'acontecendo' then 'O evento esta ACONTECENDO hoje. A prioridade e atendimento de quem esta la: credenciamento, salas, horarios. Venda so se a pessoa pedir.'
        when 'encerrado' then 'O evento JA ACONTECEU. NAO tente vender ingresso dele em hipotese nenhuma. Quem chega falando dele agora quer atendimento: certificado, gravacoes, nota fiscal, material. Se a pessoa quiser comprar, fale da proxima edicao se houver uma em proxima_edicao; se nao houver, diga com honestidade que as datas ainda nao foram anunciadas e ofereca avisar.'
        else 'Produto sem data cadastrada: nao afirme prazo nenhum.' end,
      'proxima_edicao', (
        select jsonb_build_object('codigo', p2.codigo, 'nome', p2.nome,
                                  'comeca_em', to_char(p2.comeca_em, 'DD/MM/YYYY'))
        from mind.produtos p2
        where p2.linha = c.linha and p2.ativo and p2.codigo <> c.codigo
          and p2.comeca_em > c.hoje
        order by p2.comeca_em limit 1))
    from calc c) end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_checkout_url(p_url text, p_utm jsonb DEFAULT NULL::jsonb, p_origem text DEFAULT NULL::text, p_conversa text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'summit', 'comum', 'engagement', 'intelligence', 'mind'
AS $function$
  select p_url
      || case when position('?' in p_url) > 0 then '&' else '?' end
      -- UTM original intacta: quem pagou pelo clique continua levando o credito.
      || 'utm_source='   || public.mind_urlencode(coalesce(nullif(p_utm->>'utm_source',''),
                              (select o.site from engagement.origens o where o.codigo = p_origem), 'mind'))
      || '&utm_medium='  || public.mind_urlencode(coalesce(nullif(p_utm->>'utm_medium',''), 'chatbot'))
      || '&utm_campaign='|| public.mind_urlencode(coalesce(nullif(p_utm->>'utm_campaign',''), 'mind-summit-2026'))
      || '&utm_content=' || public.mind_urlencode(coalesce(nullif(p_utm->>'utm_content',''),
                              nullif(p_origem,''), 'sem_origem'))
      || case when nullif(p_utm->>'utm_term','') is null then ''
              else '&utm_term=' || public.mind_urlencode(p_utm->>'utm_term') end
      -- Identificadores de clique de midia: sem eles o Google e a Meta nao
      -- fecham a conversao com o clique que a gerou.
      || case when nullif(p_utm->>'gclid','') is null then ''
              else '&gclid=' || public.mind_urlencode(p_utm->>'gclid') end
      || case when nullif(p_utm->>'fbclid','') is null then ''
              else '&fbclid=' || public.mind_urlencode(p_utm->>'fbclid') end
      -- Camada do bot: nao disputa com a UTM de midia.
      || '&mind_canal=chatbot'
      || case when nullif(p_origem,'') is null then ''
              else '&mind_origem=' || public.mind_urlencode(p_origem) end
      || case when nullif(p_conversa,'') is null then ''
              else '&mind_conversa=' || public.mind_urlencode(p_conversa) end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_conflito_registrar(p_pessoa uuid, p_tipo text, p_motivo text, p_outra uuid DEFAULT NULL::uuid, p_evidencia jsonb DEFAULT NULL::jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement'
AS $function$
begin
  if p_pessoa is null then return false; end if;
  if p_outra is not null and p_outra = p_pessoa then return false; end if;
  if p_tipo not in ('conflito_identidade','contato_crm_de_outra_pessoa','suspeita_sobre_merge') then
    raise exception using errcode='22023', message='tipo_de_pendencia_invalido';
  end if;

  insert into engagement.identidade_fusoes
    (participante_id, participante_origem, tipo, motivo, status, identificador)
  values (p_pessoa, p_outra, p_tipo, p_motivo, 'pendente', p_evidencia)
  on conflict do nothing;
  return true;
end $function$
;

CREATE OR REPLACE FUNCTION public.mind_conteudo(p_produto text DEFAULT NULL::text, p_tipo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'treble'
AS $function$
  with alvo as (
    select coalesce(nullif(p_produto,''),
                    (select valor from treble.config where chave = 'produto_padrao')) as codigo
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'titulo', k.titulo,
           'texto', left(k.corpo, 1500),
           'tipo', k.tipo_conteudo,
           'sobre', coalesce(k.produto_codigo, 'universal')) order by k.titulo), '[]'::jsonb)
  from summit.conhecimento k, alvo a
  where k.ativo
    and (k.produto_codigo is null
         or k.produto_codigo = a.codigo
         or k.produto_codigo = 'mind')
    and (p_tipo is null or k.tipo_conteudo = p_tipo);
$function$
;

CREATE OR REPLACE FUNCTION public.mind_conversa_estado(p_conversa_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
  select jsonb_build_object(
    'historico', coalesce((
      select jsonb_agg(jsonb_build_object('papel', m.papel, 'conteudo', m.conteudo)
                       order by m.criado_em)
      from (select papel, conteudo, criado_em from engagement.mensagens
             where conversa_id = p_conversa_id order by criado_em desc limit 12) m), '[]'::jsonb),
    'turnos_do_agente', (select count(*) from engagement.mensagens
                          where conversa_id = p_conversa_id and papel = 'agente'),
    'perfil', (select jsonb_strip_nulls(jsonb_build_object(
                 'pessoa_id', p.id, 'primeiro_nome', p.primeiro_nome, 'sobrenome', p.sobrenome,
                 'email', p.email, 'whatsapp', p.whatsapp, 'empresa', p.empresa, 'cargo', p.cargo))
               from engagement.conversas c join pessoas.pessoas p on p.id = c.participante_id
              where c.id = p_conversa_id));
$function$
;

CREATE OR REPLACE FUNCTION public.mind_crm_comercial(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'crm', 'catalogo', 'engagement', 'pessoas'
AS $function$
declare
  v_contatos    text[];
  v_consolidado jsonb := '[]'::jsonb;
  v_produtos    jsonb := '[]'::jsonb;
  v_sem_mapping integer := 0;
  v_codigos     text[] := array[]::text[];
  v_lead        jsonb := '[]'::jsonb;
  v_negociacoes jsonb := '[]'::jsonb;
  v_sem_espelho jsonb := '[]'::jsonb;
  v_fontes      text[] := array['crm.contato_espelho','crm.pipeline_leads_inbound',
                                'crm.vendas_historicas_mind_summit']::text[];
  v_relevantes  jsonb := '[]'::jsonb;
  v_superados   jsonb := '[]'::jsonb;
  v_refunds     jsonb := '[]'::jsonb;
  v_sync        jsonb;
  r             record;
  v_linhas      jsonb;
begin
  -- IDENTIDADE: so por engagement.identidades. Nunca pessoas.hubspot_id, nunca o pessoa_id
  -- legado das tabelas de CRM -- foi por ali que veio o overmerge por telefone corporativo.
  select array_agg(distinct i.identificador) into v_contatos
    from engagement.identidades i
   where i.pessoa_id = p_pessoa_id and i.canal = 'hubspot'
     and nullif(btrim(i.identificador), '') is not null;
  v_contatos := coalesce(v_contatos, array[]::text[]);

  v_sync := public.mind_crm_sync_frescor();

  if array_length(v_contatos, 1) is null then
    return jsonb_build_object('ok', true, 'pessoa_id', p_pessoa_id,
      'contato_consolidado','[]'::jsonb,'produtos','[]'::jsonb,
      'lead_atual','[]'::jsonb,'negociacoes','[]'::jsonb,
      'sinais_transacionais', jsonb_build_object(
        'relevantes','[]'::jsonb,'superados','[]'::jsonb,'refunds','[]'::jsonb),
      'meta', jsonb_build_object(
        'contatos_hubspot_considerados','[]'::jsonb,'sem_contato_hubspot',true,
        'fontes_lidas','[]'::jsonb,'pipelines_sem_espelho','[]'::jsonb,
        'evidencias_sem_mapping',0,'sync',v_sync));
  end if;

  -- 1. A REALIDADE DO CONTATO primeiro. Familia de propriedade comercial por nome --
  --    nao por mapa_produtos (que nao pode filtrar o que existe) e nao dump das ~170.
  -- 2. mapa_produtos so ENRIQUECE com o codigo canonico; sem mapping o fato continua la.
  with bruto as (
    select e.hubspot_id, kv.key as propriedade, btrim(tok) as valor
      from crm.contato_espelho e
      cross join lateral jsonb_each_text(coalesce(e.propriedades,'{}'::jsonb)) kv
      cross join lateral unnest(string_to_array(kv.value,';')) tok
     where e.hubspot_id = any(v_contatos)
       and btrim(coalesce(kv.value,'')) <> '' and btrim(tok) <> ''
       and (kv.key ~ '^(summit__|summit_papel|ingressos_comprados__|formacao__|certificacao_|journey__)'
            or kv.key in ('total_de_ingressos_comprados_lifetime','total_de_formacoes_no_instituto'))
  ),
  com_produto as (
    select b.hubspot_id, b.propriedade, b.valor,
           (select m.produto_codigo from crm.mapa_produtos m
             where m.propriedade = b.propriedade
               and (m.valor_origem = '*' or lower(m.valor_origem) = lower(b.valor))
             limit 1) as produto_codigo
      from bruto b
  )
  select coalesce(jsonb_agg(distinct jsonb_strip_nulls(jsonb_build_object(
           'hubspot_contact_id', c.hubspot_id,'propriedade', c.propriedade,
           'valor', c.valor,'produto_codigo', c.produto_codigo))),'[]'::jsonb),
         count(*) filter (where c.produto_codigo is null)
    into v_consolidado, v_sem_mapping from com_produto c;

  select coalesce(jsonb_agg(x.item order by x.produto_codigo),'[]'::jsonb),
         coalesce(array_agg(x.produto_codigo), array[]::text[])
    into v_produtos, v_codigos
    from (select ev.produto_codigo,
                 jsonb_build_object('produto_codigo', ev.produto_codigo,'nome', p.nome,
                   'vertical', p.vertical,
                   'evidencias', jsonb_agg(jsonb_build_object(
                     'hubspot_contact_id', ev.item ->> 'hubspot_contact_id',
                     'propriedade', ev.item ->> 'propriedade',
                     'valor', ev.item ->> 'valor'))) as item
            from (select el as item, el ->> 'produto_codigo' as produto_codigo
                    from jsonb_array_elements(v_consolidado) el
                   where el ->> 'produto_codigo' is not null) ev
            left join catalogo.produtos p on p.codigo = ev.produto_codigo
           group by ev.produto_codigo, p.nome, p.vertical) x;

  -- Lead Inbound: universal, sempre consultado, por hs_primary_contact_id
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'hubspot_lead_id', l.hubspot_lead_id,'hs_pipeline', l.hs_pipeline,
           'hs_pipeline_stage', l.hs_pipeline_stage,'hs_lead_label', l.hs_lead_label,
           'hs_lead_type', l.hs_lead_type,'hs_lead_source', l.hs_lead_source,
           'hs_primary_contact_id', l.hs_primary_contact_id,
           'hs_primary_company_id', l.hs_primary_company_id,
           'hs_associated_company_name', l.hs_associated_company_name,
           'nome_da_empresa', l.nome_da_empresa,'hubspot_owner_id', l.hubspot_owner_id,
           'hs_lead_associated_deals_count', l.hs_lead_associated_deals_count,
           'hs_lead_pipeline_value', l.hs_lead_pipeline_value,
           'hs_lead_closed_won_deals_amount', l.hs_lead_closed_won_deals_amount,
           'motivo_de_lead_perdido', l.motivo_de_lead_perdido,
           'hs_lead_disqualification_reason', l.hs_lead_disqualification_reason,
           'hs_lead_disqualification_note', l.hs_lead_disqualification_note,
           'hs_lead_is_open', coalesce(l.propriedades ->> 'hs_lead_is_open',
                                       l.propriedades ->> 'hs_lead_is_open_v2'),
           'hs_v2_date_entered_current_stage', l.hs_v2_date_entered_current_stage,
           'hs_createdate', l.hs_createdate,'hs_lastmodifieddate', l.hs_lastmodifieddate))
         order by l.hs_lastmodifieddate desc nulls last),'[]'::jsonb)
    into v_lead from crm.pipeline_leads_inbound l
   where l.hs_primary_contact_id = any(v_contatos);

  -- Negociacoes: produto -> pipelines_hubspot -> crm.sync_estado -> tabela. Sem hardcode.
  -- O identificador do SQL dinamico vem SEMPRE de crm.sync_estado, quotado com %I.
  for r in
    select p.codigo, p.vertical, pl.pipeline_id, s.tabela_destino, s.pipeline_nome
      from catalogo.produtos p
      cross join lateral unnest(coalesce(p.pipelines_hubspot, array[]::text[])) pl(pipeline_id)
      left join crm.sync_estado s on s.pipeline_id = pl.pipeline_id
     where p.ativo and p.vende order by p.codigo, pl.pipeline_id
  loop
    if r.tabela_destino is null then
      v_sem_espelho := v_sem_espelho || jsonb_build_object(
        'produto_codigo', r.codigo,'pipeline_id', r.pipeline_id,
        'motivo','sem linha em crm.sync_estado');
      continue;
    end if;

    execute format(
      'select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from crm.%I t
        where exists (select 1 from jsonb_array_elements_text(
                        coalesce(t.propriedades -> ''_contatos'', ''[]''::jsonb)) c(hid)
                       where c.hid = any($1))', r.tabela_destino)
      into v_linhas using v_contatos;

    v_fontes := array_append(v_fontes, 'crm.' || r.tabela_destino);

    select v_negociacoes || coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'produto_codigo', r.codigo,'vertical', r.vertical,
             'pipeline_id', r.pipeline_id,'pipeline_nome', r.pipeline_nome,
             'hubspot_deal_id', d ->> 'hubspot_deal_id','dealname', d ->> 'dealname',
             'dealstage', d ->> 'dealstage','hs_is_closed', d ->> 'hs_is_closed',
             'hs_is_closed_lost', d ->> 'hs_is_closed_lost','amount', d ->> 'amount',
             'quantidade_ingressos', d ->> 'quantidade_ingressos','produto', d ->> 'produto',
             'temperatura', d ->> 'temperatura','lead_b2c_ou_b2b', d ->> 'lead_b2c_ou_b2b',
             'origem_do_lead', d ->> 'origem_do_lead','hubspot_owner_id', d ->> 'hubspot_owner_id',
             'createdate', d ->> 'createdate',
             'entrou_no_estagio_em', d ->> 'hs_v2_date_entered_current_stage',
             'hs_lastmodifieddate', d ->> 'hs_lastmodifieddate',
             'contatos_hubspot', d -> 'propriedades' -> '_contatos'))),'[]'::jsonb)
      into v_negociacoes from jsonb_array_elements(v_linhas) d;
  end loop;

  -- Sinais transacionais. Papel LIMITADO: nao reconstroi historico de compra (isso e do
  -- contato). superado_por_conversao usa o consolidado do CONTATO como juiz.
  with hist as (
    select distinct on (h.hubspot_deal_id)
           h.hubspot_deal_id, h.dealname, h.situacao, h.summit_year, h.produto_codigo,
           h.amount_in_home_currency, h.status_de_pagamento, h.data_da_compra, h.cupom_utilizado
      from crm.vendas_historicas_mind_summit h
      join lateral jsonb_array_elements_text(
             coalesce(h.propriedades -> '_contatos','[]'::jsonb)) c(hid) on true
     where c.hid = any(v_contatos)
  ),
  f as (
    select hist.*,
           case hist.situacao
             when 'carrinho_abandonado'  then 'carrinho_abandonado'
             when 'aberto'               then 'fatura_aberta'
             when 'aberto_status_aberto' then 'fatura_aberta'
             when 'pendente_a_confirmar' then 'pendencia' end as tipo,
           (hist.produto_codigo is not null and hist.produto_codigo = any(v_codigos)) as superado
      from hist
  )
  select
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'tipo', f.tipo,'produto_codigo', f.produto_codigo,
      'hubspot_deal_id', f.hubspot_deal_id,'dealname', f.dealname,
      'situacao_origem', f.situacao,'summit_year', f.summit_year,
      'valor_total_da_venda', f.amount_in_home_currency,
      'status_de_pagamento', f.status_de_pagamento,'data_da_compra', f.data_da_compra,
      'cupom_utilizado', f.cupom_utilizado,
      'superado_por_conversao', false))) filter (where f.tipo is not null and not f.superado),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'tipo', f.tipo,'produto_codigo', f.produto_codigo,
      'hubspot_deal_id', f.hubspot_deal_id,'dealname', f.dealname,
      'situacao_origem', f.situacao,'summit_year', f.summit_year,
      'superado_por_conversao', true,
      'superado_por','consolidado do contato ja registra este produto')))
      filter (where f.tipo is not null and f.superado),'[]'::jsonb)
    into v_relevantes, v_superados from f;

  -- Refund: evidencia transacional que NAO pode ser ignorada so porque o contato ainda mostra
  -- o produto -- ha refunds que ainda nao atualizam as propriedades consolidadas.
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'hubspot_deal_id', h.hubspot_deal_id,'dealname', h.dealname,
           'produto_codigo', h.produto_codigo,'summit_year', h.summit_year,
           'valor_reembolsado', h.valor_reembolsado,'data_reembolso', h.data_reembolso,
           'situacao_origem', h.situacao,
           'aviso','refund pode nao ter sido refletido nas propriedades consolidadas do contato'))),'[]'::jsonb)
    into v_refunds
    from (select distinct on (h.hubspot_deal_id)
                 h.hubspot_deal_id, h.dealname, h.produto_codigo, h.summit_year,
                 h.valor_reembolsado, h.data_reembolso, h.situacao
            from crm.vendas_historicas_mind_summit h
            join lateral jsonb_array_elements_text(
                   coalesce(h.propriedades -> '_contatos','[]'::jsonb)) c(hid) on true
           where c.hid = any(v_contatos)
             and lower(coalesce(h.houve_reembolso,'')) in ('sim','true','yes')) h;

  return jsonb_build_object(
    'ok', true,'pessoa_id', p_pessoa_id,
    'contato_consolidado', v_consolidado,'produtos', v_produtos,
    'lead_atual', v_lead,'negociacoes', v_negociacoes,
    'sinais_transacionais', jsonb_build_object(
      'relevantes', v_relevantes,'superados', v_superados,'refunds', v_refunds),
    'meta', jsonb_build_object(
      'contatos_hubspot_considerados', to_jsonb(v_contatos),
      'sem_contato_hubspot', false,'fontes_lidas', to_jsonb(v_fontes),
      'pipelines_sem_espelho', v_sem_espelho,
      'evidencias_sem_mapping', v_sem_mapping,'sync', v_sync));
end $function$
;

CREATE OR REPLACE FUNCTION public.mind_crm_fatos(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'crm'
AS $function$
declare
  v_contatos jsonb := '[]'::jsonb;
  v_sync     jsonb;
  v_pend     jsonb;
  v_espelho  timestamptz;
  v_n        int := 0;
begin
  if p_pessoa_id is null then
    return jsonb_build_object('ok', false, 'motivo','sem_pessoa');
  end if;

  select coalesce(jsonb_agg(c.fato order by c.ordem desc nulls last), '[]'::jsonb), count(*)
    into v_contatos, v_n
  from (
    select
      e.atualizado_em as ordem,
      jsonb_strip_nulls(jsonb_build_object(
        'hubspot_id', e.hubspot_id,
        'nome',       nullif(btrim(coalesce(e.firstname,'')||' '||coalesce(e.lastname,'')),''),
        'primeiro_nome', nullif(btrim(coalesce(e.firstname,'')),''),
        'sobrenome',  nullif(btrim(coalesce(e.lastname,'')),''),
        'email',      nullif(btrim(coalesce(e.email,'')),''),
        'telefones',  nullif(jsonb_strip_nulls(jsonb_build_object(
                        'phone',    nullif(btrim(coalesce(e.phone,'')),''),
                        'whatsapp', nullif(btrim(coalesce(e.hs_whatsapp_phone_number,'')),''))), '{}'::jsonb),
        'cargo',      nullif(btrim(coalesce(e.jobtitle,'')),''),
        'empresa',    nullif(btrim(coalesce(e.company,'')),''),
        'linkedin',   nullif(btrim(coalesce(e.hs_linkedin_url,'')),''),
        'dominio_email', nullif(btrim(coalesce(e.hs_email_domain,'')),''),

        'qualificacao', nullif(jsonb_strip_nulls(jsonb_build_object(
          'lead_icp',       nullif(btrim(coalesce(e.lead_icp,'')),''),
          'lead_tier',      nullif(btrim(coalesce(e.lead_tier,'')),''),
          'icp',            nullif(btrim(coalesce(e.icp,'')),''),
          'icp_confianca',  e.icp_confianca,
          'lifecyclestage', nullif(btrim(coalesce(e.lifecyclestage,'')),''),
          'hs_lead_status', nullif(btrim(coalesce(e.hs_lead_status,'')),''),
          'etapa_do_lead',  nullif(btrim(coalesce(e.etapa_do_lead__atualizar,'')),''),
          'motivo_lead_perdido', nullif(btrim(coalesce(e.motivo_do_lead__perdido,'')),''),
          'origem_do_lead', nullif(btrim(coalesce(e.origem_do_lead,'')),''),
          'owner_hubspot_id', nullif(btrim(coalesce(e.hubspot_owner_id,'')),''))), '{}'::jsonb),

        'summit', nullif(jsonb_strip_nulls(jsonb_build_object(
          'participacao_anual',        nullif(btrim(coalesce(e.summit__participacao_anual,'')),''),
          'total_de_summits',          e.total_de_summits_participados,
          'participou_de_mais_de_um',  nullif(btrim(coalesce(e.participou_de_mais_de_um_summit,'')),''),
          'categoria_do_ingresso',     nullif(btrim(coalesce(e.summit__categoria_do_ingresso,'')),''),
          'categoria_2025',            nullif(btrim(coalesce(e.summit__categoria_2025,'')),''),
          'categoria_2026',            nullif(btrim(coalesce(e.summit__categoria_2026,'')),''),
          'tipo_entrada',              nullif(btrim(coalesce(e.tipo_de_entrada,'')),''),
          'tipo_entrada_2025',         nullif(btrim(coalesce(e.summit__tipo_entrada_2025,'')),''),
          'tipo_entrada_2026',         nullif(btrim(coalesce(e.summit__tipo_entrada_2026,'')),''),
          'papel_2025',                nullif(btrim(coalesce(e.summit_papel_2025,'')),''),
          'papel_2026',                nullif(btrim(coalesce(e.summit__papel_2026,'')),''),
          'cortesia_anos',             nullif(btrim(coalesce(e.summit__cortesia_anos,'')),''),
          'patrocinio_anos',           nullif(btrim(coalesce(e.summit__patrocinio_anos,'')),''),
          'status_summit_2026',        nullif(btrim(coalesce(e.status_summit_2026,'')),''))), '{}'::jsonb),

        'atribuicao', nullif(jsonb_strip_nulls(jsonb_build_object(
          'utm_source',   nullif(btrim(coalesce(e.utm_source,'')),''),
          'utm_medium',   nullif(btrim(coalesce(e.utm_medium,'')),''),
          'utm_campaign', nullif(btrim(coalesce(e.utm_campaign,'')),''),
          'utm_content',  nullif(btrim(coalesce(e.utm_content,'')),''),
          'utm_term',     nullif(btrim(coalesce(e.utm_term,'')),''),
          'origem_primeira',        nullif(btrim(coalesce(e.hs_analytics_source,'')),''),
          'origem_primeira_detalhe',nullif(btrim(coalesce(e.hs_analytics_source_data_1,'')),''),
          'origem_ultima',          nullif(btrim(coalesce(e.hs_latest_source,'')),''),
          'origem_ultima_detalhe',  nullif(btrim(coalesce(e.hs_latest_source_data_1,'')),''),
          'origem_ultima_em',       e.hs_latest_source_timestamp,
          'primeira_url',           nullif(btrim(coalesce(e.hs_analytics_first_url,'')),''),
          'primeiro_referrer',      nullif(btrim(coalesce(e.hs_analytics_first_referrer,'')),''),
          'primeira_visita_em',     e.hs_analytics_first_timestamp,
          'ultima_url',             nullif(btrim(coalesce(e.hs_analytics_last_url,'')),''),
          'primeira_conversao',     nullif(btrim(coalesce(e.first_conversion_event_name,'')),''),
          'primeira_conversao_em',  e.first_conversion_date)), '{}'::jsonb),

        'atualizado_em',   e.atualizado_em,
        'sincronizado_em', e.sincronizado_em
      )) as fato
    from engagement.identidades i
    join crm.contato_espelho e on e.hubspot_id = i.identificador
    where i.pessoa_id = p_pessoa_id and i.canal = 'hubspot'
  ) c;

  select jsonb_strip_nulls(jsonb_build_object(
           'fonte', s.fonte, 'status', s.status,
           'concluido_em', s.concluido_em, 'carga_completa_em', s.carga_completa_em,
           'registros_gravados', s.registros_gravados))
    into v_sync
  from crm.sync_estado s where s.fonte = 'hubspot_contatos';

  select max(e.sincronizado_em) into v_espelho from crm.contato_espelho e;

  select jsonb_build_object(
           'aberta', count(*) > 0,
           'tipos', coalesce(jsonb_agg(distinct f.tipo), '[]'::jsonb))
    into v_pend
  from engagement.identidade_fusoes f
  where f.status = 'pendente'
    and (f.participante_id = p_pessoa_id or f.participante_origem = p_pessoa_id);

  return jsonb_build_object(
    'ok', true,
    'pessoa_id', p_pessoa_id,
    'contatos', v_contatos,
    'meta', jsonb_build_object(
      'contatos_encontrados', v_n,
      'pendencia_identidade', v_pend,
      'sync_hubspot_contatos', v_sync,
      'espelho_ultimo_sincronizado_em', v_espelho));
end $function$
;

CREATE OR REPLACE FUNCTION public.mind_crm_sync_frescor()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'crm'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'fonte', s.fonte, 'pipeline_nome', s.pipeline_nome,
           'tabela_destino', s.tabela_destino, 'status', s.status,
           'iniciado_em', s.iniciado_em, 'concluido_em', s.concluido_em,
           'marca_dagua', s.marca_dagua, 'erro', s.erro) order by s.fonte), '[]'::jsonb)
    from crm.sync_estado s;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_crm_vincular_pessoa(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'crm'
AS $function$
declare
  v_hub    text[];
  v_mail   text[];
  v_tel10  text[];
  v_tel_ok text[] := array[]::text[];   -- telefones que identificam 1 contato so
  t        text;
  v_n      int;
  v_hubs   text[];
  v_amb    jsonb := '[]'::jsonb;        -- evidencia dos telefones ambiguos
  c        record;
  v_r      jsonb;
  v_vinc   int := 0;
  v_ja     int := 0;
  v_conf   int := 0;
  v_ident  int := 0;
  v_lista  jsonb := '[]'::jsonb;
begin
  if p_pessoa_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa');
  end if;

  select array_agg(i.identificador) filter (where i.canal = 'hubspot'),
         array_agg(i.identificador) filter (where i.canal = 'email'),
         array_agg(right(i.identificador, 10)) filter
           (where i.canal in ('whatsapp','telefone') and length(i.identificador) >= 10)
    into v_hub, v_mail, v_tel10
  from engagement.identidades i
  where i.pessoa_id = p_pessoa_id;

  -- ---------- telefone: so entra se for inequivoco ----------
  if v_tel10 is not null then
    foreach t in array v_tel10 loop
      select count(*), array_agg(e.hubspot_id)
        into v_n, v_hubs
        from crm.contato_espelho e
       where (length(regexp_replace(coalesce(e.phone,''), '\D','','g')) >= 10
              and right(regexp_replace(coalesce(e.phone,''), '\D','','g'), 10) = t)
          or (length(regexp_replace(coalesce(e.hs_whatsapp_phone_number,''), '\D','','g')) >= 10
              and right(regexp_replace(coalesce(e.hs_whatsapp_phone_number,''), '\D','','g'), 10) = t);

      if v_n = 1 then
        v_tel_ok := v_tel_ok || t;
      elsif v_n > 1 then
        -- numero compartilhado (central, corporativo, delegacao). Nao decide
        -- identidade sozinho; vira pendencia para revisao humana.
        v_amb := v_amb || jsonb_build_array(jsonb_build_object(
          'telefone', t, 'contatos', v_n, 'hubspot_ids', to_jsonb(v_hubs)));
      end if;
    end loop;

    if jsonb_array_length(v_amb) > 0 then
      perform public.mind_conflito_registrar(
        p_pessoa_id, 'suspeita_sobre_merge',
        'telefone compartilhado por varios contatos do CRM; nao vincula por telefone',
        null,
        jsonb_build_object('telefones_ambiguos', v_amb));
    end if;
  end if;

  if v_hub is null and v_mail is null and coalesce(array_length(v_tel_ok,1),0) = 0 then
    return jsonb_build_object('ok', true, 'motivo', 'sem_identificador_utilizavel',
      'telefones_ambiguos', v_amb, 'contatos', '[]'::jsonb);
  end if;

  for c in
    select e.id, e.hubspot_id, e.pessoa_id,
           case
             when v_hub  is not null and e.hubspot_id = any(v_hub) then 'hubspot_id'
             when v_mail is not null and lower(btrim(coalesce(e.email,''))) = any(v_mail) then 'email'
             else 'telefone'
           end as via
      from crm.contato_espelho e
     where (v_hub  is not null and e.hubspot_id = any(v_hub))
        or (v_mail is not null and lower(btrim(coalesce(e.email,''))) = any(v_mail))
        or (coalesce(array_length(v_tel_ok,1),0) > 0
            and ((length(regexp_replace(coalesce(e.phone,''), '\D','','g')) >= 10
                  and right(regexp_replace(coalesce(e.phone,''), '\D','','g'), 10) = any(v_tel_ok))
              or (length(regexp_replace(coalesce(e.hs_whatsapp_phone_number,''), '\D','','g')) >= 10
                  and right(regexp_replace(coalesce(e.hs_whatsapp_phone_number,''), '\D','','g'), 10) = any(v_tel_ok))))
  loop
    if c.pessoa_id = p_pessoa_id then
      v_ja := v_ja + 1;

    elsif c.pessoa_id is null then
      update crm.contato_espelho set pessoa_id = p_pessoa_id, atualizado_em = now()
       where id = c.id;
      v_vinc := v_vinc + 1;

    else
      perform public.mind_conflito_registrar(
        p_pessoa_id, 'contato_crm_de_outra_pessoa',
        'contato do CRM ja pertence a outra pessoa', c.pessoa_id,
        jsonb_build_object('hubspot_id', c.hubspot_id, 'contato_espelho_id', c.id, 'via', c.via));
      v_conf := v_conf + 1;
      v_lista := v_lista || jsonb_build_array(jsonb_build_object(
        'hubspot_id', c.hubspot_id, 'situacao', 'conflito', 'via', c.via, 'dono', c.pessoa_id));
      continue;
    end if;

    if nullif(btrim(coalesce(c.hubspot_id,'')),'') is not null then
      v_r := public.mind_identidade_resolver(
        jsonb_build_object('hubspot_id', c.hubspot_id), null, 'hubspot', p_pessoa_id);
      if jsonb_array_length(coalesce(v_r->'identidades','[]'::jsonb)) > 0 then
        v_ident := v_ident + 1;
      end if;
    end if;

    v_lista := v_lista || jsonb_build_array(jsonb_build_object(
      'hubspot_id', c.hubspot_id, 'via', c.via,
      'situacao', case when c.pessoa_id is null then 'vinculado' else 'ja_ligado' end));
  end loop;

  return jsonb_build_object(
    'ok', true, 'pessoa_id', p_pessoa_id,
    'contatos_vinculados', v_vinc, 'contatos_ja_ligados', v_ja,
    'conflitos', v_conf, 'identidades_hubspot_novas', v_ident,
    'telefones_ambiguos', v_amb, 'contatos', v_lista);
end $function$
;

CREATE OR REPLACE FUNCTION public.mind_engagement_fatos(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
  with conversa as (
    select c.id, c.canal, c.agente, c.origem_codigo, c.produto_codigo,
           c.iniciada_em, c.ultima_atividade, c.encerrada_em
      from engagement.conversas c
     where c.participante_id = p_pessoa_id
  ),
  mensagem as (
    select m.conversa_id, m.id, m.papel, m.conteudo, m.blocos, m.origem, m.criado_em
      from engagement.mensagens m
     where m.conversa_id in (select id from conversa)
  ),
  conversa_com_mensagens as (
    select cv.*,
           coalesce((
             select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                      'mensagem_id', ms.id,
                      'papel',       ms.papel,
                      'conteudo',    ms.conteudo,
                      'blocos',      ms.blocos,
                      'origem',      ms.origem,
                      'criado_em',   ms.criado_em))
                    order by ms.criado_em, ms.id)
               from mensagem ms where ms.conversa_id = cv.id), '[]'::jsonb) as mensagens
      from conversa cv
  )
  select jsonb_build_object(
    'ok', true,
    'pessoa_id', p_pessoa_id,
    'resumo', jsonb_build_object(
      'conversas_total',       (select count(*) from conversa),
      'mensagens_total',       (select count(*) from mensagem),
      'canais',                coalesce((select jsonb_agg(distinct canal) from conversa
                                          where canal is not null), '[]'::jsonb),
      'primeira_interacao_em', (select min(x) from (
                                  select min(iniciada_em) x from conversa
                                  union all select min(criado_em) from mensagem) a),
      'ultima_interacao_em',   (select max(x) from (
                                  select max(greatest(iniciada_em, ultima_atividade, encerrada_em)) x
                                    from conversa
                                  union all select max(criado_em) from mensagem) b)),
    'conversas', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               'conversa_id',      cm.id,
               'canal',            cm.canal,
               'agente',           cm.agente,
               'origem_codigo',    cm.origem_codigo,
               'produto_codigo',   cm.produto_codigo,
               'iniciada_em',      cm.iniciada_em,
               'ultima_atividade', cm.ultima_atividade,
               'encerrada_em',     cm.encerrada_em,
               'mensagens',        cm.mensagens))
             order by cm.iniciada_em nulls last, cm.id)
        from conversa_com_mensagens cm), '[]'::jsonb),
    'meta', jsonb_build_object(
      'autoria_individual_treble_disponivel', false));
$function$
;

CREATE OR REPLACE FUNCTION public.mind_espelho_carga_inicial()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'crm', 'cron'
AS $function$
declare v_faltando int;
begin
  select count(*) into v_faltando
    from crm.sync_estado where carga_completa_em is null;

  if v_faltando = 0 then
    perform cron.unschedule('hubspot-espelho-carga-inicial');
    return;
  end if;

  perform public.mind_espelho_disparar();
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_espelho_disparar()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'platform', 'net'
AS $function$
declare
  v_base text;
  v_key text;
begin
  select base_url, config->>'anon_key' into v_base, v_key
    from platform.integracoes where codigo = 'supabase_functions' and ativo;

  if v_base is null or v_key is null then
    raise exception 'integracao supabase_functions sem base_url ou anon_key';
  end if;

  return net.http_post(
    url := v_base || '/hubspot-sync',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
    body := '{}'::jsonb,
    timeout_milliseconds := 150000);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_espelho_gravar(p_fonte text, p_registros jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'crm'
AS $function$
declare
  v_tabela text;
  v_chave  text;
  v_cols   text[];
  v_lista  text;
  v_sets   text;
  v_n      int;
begin
  if jsonb_typeof(p_registros) <> 'array' then
    raise exception 'p_registros precisa ser array';
  end if;
  v_n := jsonb_array_length(p_registros);
  if v_n = 0 then
    return jsonb_build_object('gravados', 0);
  end if;

  select tabela_destino, chave_destino into v_tabela, v_chave
    from crm.sync_estado where fonte = p_fonte;

  if v_tabela is null then
    raise exception 'fonte sem tabela_destino em crm.sync_estado: %', p_fonte;
  end if;

  -- So as colunas que EXISTEM na tabela E vieram no lote. O que nao veio fica
  -- como esta: sincronizacao nao apaga o que ela nao viu.
  select array_agg(distinct k order by k) into v_cols
  from jsonb_array_elements(p_registros) r,
       jsonb_object_keys(r) k
  where k in (
    select column_name from information_schema.columns
     where table_schema = 'crm' and table_name = v_tabela
       and column_name not in ('id', 'pessoa_id', 'produto_codigo', 'criado_em')
  );

  if v_cols is null or array_length(v_cols, 1) is null then
    raise exception 'lote nao trouxe nenhuma coluna conhecida de crm.%', v_tabela;
  end if;
  if not (v_chave = any(v_cols)) then
    raise exception 'lote sem a chave %', v_chave;
  end if;

  select string_agg(quote_ident(c), ', ' order by c) into v_lista from unnest(v_cols) c;
  select string_agg(format('%I = excluded.%I', c, c), ', ' order by c) into v_sets
    from unnest(v_cols) c where c <> v_chave;

  execute format(
    'insert into crm.%I (%s) select %s from jsonb_populate_recordset(null::crm.%I, $1)
      on conflict (%I) do update set %s, sincronizado_em = now(), atualizado_em = now()',
    v_tabela, v_lista, v_lista, v_tabela, v_chave, v_sets
  ) using p_registros;

  return jsonb_build_object('gravados', v_n, 'tabela', v_tabela, 'colunas', array_length(v_cols, 1));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_espelho_ligar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'crm', 'pessoas', 'engagement', 'catalogo'
AS $function$
declare
  v_contatos int := 0; v_conflitos int := 0;
  v_neg int := 0; v_hist int := 0; v_prod int := 0; v_tmp int := 0;
  r record; v_res jsonb;
begin
  for r in
    select distinct i.pessoa_id from engagement.identidades i
     where i.canal in ('hubspot','email','whatsapp','telefone')
  loop
    v_res := public.mind_crm_vincular_pessoa(r.pessoa_id);
    v_contatos  := v_contatos  + coalesce((v_res->>'contatos_vinculados')::int, 0);
    v_conflitos := v_conflitos + coalesce((v_res->>'conflitos')::int, 0);
  end loop;

  -- legado conhecido, preservado como estava (nao e escopo desta correcao)
  with casado as (
    select n.id as neg_id, min(e.pessoa_id::text)::uuid as pessoa_id
    from crm.pipeline_de_vendas_summit n
    join lateral jsonb_array_elements_text(coalesce(n.propriedades->'_contatos', '[]'::jsonb)) c(hid) on true
    join crm.contato_espelho e on e.hubspot_id = c.hid and e.pessoa_id is not null
    where n.pessoa_id is null
    group by n.id having count(distinct e.pessoa_id) = 1
  )
  update crm.pipeline_de_vendas_summit n set pessoa_id = c.pessoa_id, atualizado_em = now()
  from casado c where n.id = c.neg_id;
  get diagnostics v_neg = row_count;

  with casado as (
    select n.id as neg_id, min(e.pessoa_id::text)::uuid as pessoa_id
    from crm.vendas_historicas_mind_summit n
    join lateral jsonb_array_elements_text(coalesce(n.propriedades->'_contatos', '[]'::jsonb)) c(hid) on true
    join crm.contato_espelho e on e.hubspot_id = c.hid and e.pessoa_id is not null
    where n.pessoa_id is null
    group by n.id having count(distinct e.pessoa_id) = 1
  )
  update crm.vendas_historicas_mind_summit n set pessoa_id = c.pessoa_id, atualizado_em = now()
  from casado c where n.id = c.neg_id;
  get diagnostics v_hist = row_count;

  -- (o bloco que ligava crm.empenho_summit_2026.pessoa_id foi removido de proposito --
  --  identidade do Empenho se resolve por engagement.identidades, no momento da leitura)

  -- produto por pipeline: logica nova, preservada. Vale qualquer pipeline do array do catalogo.
  update crm.pipeline_de_vendas_summit n
     set produto_codigo = p.codigo, atualizado_em = now()
    from catalogo.produtos p
   where n.produto_codigo is null and n.pipeline = any(p.pipelines_hubspot);
  get diagnostics v_prod = row_count;

  update crm.empenho_summit_2026 n
     set produto_codigo = p.codigo, atualizado_em = now()
    from catalogo.produtos p
   where n.produto_codigo is null and n.pipeline = any(p.pipelines_hubspot);
  get diagnostics v_tmp = row_count;
  v_prod := v_prod + v_tmp;

  update crm.vendas_historicas_mind_summit n
     set produto_codigo = p.codigo, atualizado_em = now()
    from catalogo.produtos p
   where n.produto_codigo is null
     and p.codigo = 'mind-summit-' || regexp_replace(coalesce(n.summit_year, ''), '\D', '', 'g');
  get diagnostics v_tmp = row_count;
  v_prod := v_prod + v_tmp;

  -- contrato anterior restaurado: sem `empenho_ligados`
  return jsonb_build_object(
    'contatos_ligados', v_contatos, 'contatos_em_conflito', v_conflitos,
    'negocios_ligados', v_neg, 'historicos_ligados', v_hist, 'produtos_ligados', v_prod);
end $function$
;

CREATE OR REPLACE FUNCTION public.mind_foto_url(p_asset_path text, p_fallback text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when nullif(p_asset_path,'') is null then p_fallback
    when exists (select 1 from storage.objects o
                  where o.bucket_id = 'mind-assets' and o.name = p_asset_path)
      then 'https://ymnmotgglsrxmjmonwjz.supabase.co/storage/v1/object/public/mind-assets/' || p_asset_path
    else p_fallback
  end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_identidade_resolver(p_identificadores jsonb, p_nome text DEFAULT NULL::text, p_canal text DEFAULT NULL::text, p_pessoa_ancora uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  v_ids       jsonb := public.mind_identificadores_normalizar(p_identificadores);
  v_item      jsonb;
  v_achados   jsonb := '[]'::jsonb;
  v_pessoa    uuid;
  v_outro     uuid;
  v_criada    boolean := false;
  v_conflito  jsonb := null;
  v_nome      text := nullif(left(btrim(coalesce(p_nome,'')),160),'');
  v_primeiro  text;
  v_sobrenome text;
  v_tel       text;
  v_mail      text;
  v_dono      uuid;
  v_vinculadas jsonb := '[]'::jsonb;
begin
  if jsonb_array_length(v_ids) = 0 then
    return jsonb_build_object('pessoa_id', p_pessoa_ancora, 'criada', false,
      'motivo','sem_identificador_deterministico', 'conflito', null,
      'ancorada', p_pessoa_ancora is not null, 'identidades', '[]'::jsonb);
  end if;

  for v_item in select * from jsonb_array_elements(v_ids) loop
    select i.pessoa_id into v_outro
      from engagement.identidades i
     where i.canal = v_item->>'canal' and i.identificador = v_item->>'identificador'
     limit 1;
    if v_outro is not null then
      v_achados := v_achados || jsonb_build_array(jsonb_build_object(
        'pessoa_id', v_outro, 'forca', (v_item->>'forca')::int, 'canal', v_item->>'canal'));
    end if;
  end loop;

  if p_pessoa_ancora is not null then
    v_pessoa := p_pessoa_ancora;          -- a conversa manda
  else
    select a.pessoa_id into v_pessoa
      from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text)
      join pessoas.pessoas p on p.id = a.pessoa_id
     order by a.forca desc, (a.canal = p_canal) desc, p.criado_em asc
     limit 1;
  end if;

  if exists (select 1 from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text)
              where v_pessoa is not null and a.pessoa_id <> v_pessoa) then
    v_conflito := jsonb_build_object('pessoa_escolhida', v_pessoa,
                                     'ancorada', p_pessoa_ancora is not null,
                                     'evidencias', v_achados);
    for v_outro in
      select distinct a.pessoa_id
        from jsonb_to_recordset(v_achados) as a(pessoa_id uuid, forca int, canal text)
       where a.pessoa_id <> v_pessoa
    loop
      perform public.mind_conflito_registrar(
        v_pessoa, 'conflito_identidade',
        case when p_pessoa_ancora is not null
             then 'evidencia nova aponta para outra pessoa; conversa ancorada permanece'
             else 'identificadores da mesma entrada apontam para pessoas diferentes' end,
        v_outro, v_ids);
    end loop;
  end if;

  if v_pessoa is null then
    v_primeiro  := nullif(split_part(coalesce(v_nome,''), ' ', 1), '');
    v_sobrenome := nullif(btrim(substr(coalesce(v_nome,''), coalesce(length(v_primeiro),0) + 2)), '');
    v_tel  := (select x->>'identificador' from jsonb_array_elements(v_ids) x where x->>'canal'='whatsapp' limit 1);
    v_mail := (select x->>'identificador' from jsonb_array_elements(v_ids) x where x->>'canal'='email'    limit 1);

    if v_mail is not null and exists (select 1 from pessoas.pessoas p where lower(p.email) = v_mail)
      then v_mail := null; end if;
    if v_tel is not null and exists (select 1 from pessoas.pessoas p where p.whatsapp = v_tel)
      then v_tel := null; end if;

    insert into pessoas.pessoas (primeiro_nome, sobrenome, whatsapp, email, origem)
    values (v_primeiro, v_sobrenome, v_tel, v_mail, 'bot')
    returning id into v_pessoa;
    v_criada := true;
  elsif v_nome is not null then
    update pessoas.pessoas
       set primeiro_nome = nullif(split_part(v_nome,' ',1),''), atualizado_em = now()
     where id = v_pessoa and primeiro_nome is null;
  end if;

  for v_item in select * from jsonb_array_elements(v_ids) loop
    select i.pessoa_id into v_dono
      from engagement.identidades i
     where i.canal = v_item->>'canal' and i.identificador = v_item->>'identificador';
    if v_dono is null then
      insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
      values (v_pessoa, v_item->>'canal', v_item->>'identificador',
              (v_item->>'verificado')::boolean, v_item->>'confianca')
      on conflict (canal, identificador) do nothing;
      v_vinculadas := v_vinculadas || jsonb_build_array(v_item);

      if v_item->>'canal' = 'email' then
        update pessoas.pessoas p set email = v_item->>'identificador', atualizado_em = now()
         where p.id = v_pessoa and p.email is null
           and not exists (select 1 from pessoas.pessoas q where lower(q.email) = v_item->>'identificador');
      elsif v_item->>'canal' = 'whatsapp' then
        update pessoas.pessoas p set whatsapp = v_item->>'identificador', atualizado_em = now()
         where p.id = v_pessoa and p.whatsapp is null
           and not exists (select 1 from pessoas.pessoas q where q.whatsapp = v_item->>'identificador');
      elsif v_item->>'canal' = 'hubspot' then
        update pessoas.pessoas p set hubspot_id = v_item->>'identificador', atualizado_em = now()
         where p.id = v_pessoa and p.hubspot_id is null
           and not exists (select 1 from pessoas.pessoas q where q.hubspot_id = v_item->>'identificador');
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'pessoa_id', v_pessoa, 'criada', v_criada, 'conflito', v_conflito,
    'ancorada', p_pessoa_ancora is not null, 'identidades', v_vinculadas);
end $function$
;

CREATE OR REPLACE FUNCTION public.mind_identificadores_normalizar(p_ids jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare
  v_out  jsonb := '[]'::jsonb;
  v_tel  text;
  v_mail text;
  v_txt  text;
begin
  p_ids := coalesce(p_ids, '{}'::jsonb);

  -- telefone/whatsapp: uma unica forma canonica no sistema inteiro
  v_tel := public.telefone_normalizar(
             coalesce(p_ids->>'whatsapp', p_ids->>'telefone', p_ids->>'phone'));
  if v_tel is not null then
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'canal','whatsapp','identificador',v_tel,'forca',3,'verificado',true,'confianca','alta'));
  end if;

  v_mail := lower(btrim(coalesce(p_ids->>'email','')));
  if v_mail <> '' and v_mail ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$'
     and length(v_mail) <= 320 then
    -- e-mail e evidencia mais fraca: a pessoa pode digitar o de um terceiro
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'canal','email','identificador',v_mail,'forca',2,'verificado',false,'confianca','media'));
  end if;

  v_txt := btrim(coalesce(p_ids->>'auth_user_id',''));
  if v_txt ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    -- identidade autenticada: a evidencia mais forte que existe
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'canal','auth_user','identificador',v_txt,'forca',4,'verificado',true,'confianca','alta'));
  end if;

  v_txt := btrim(coalesce(p_ids->>'hubspot_id',''));
  if v_txt <> '' and v_txt ~ '^[0-9]+$' then
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'canal','hubspot','identificador',v_txt,'forca',3,'verificado',true,'confianca','alta'));
  end if;

  return v_out;
end $function$
;

CREATE OR REPLACE FUNCTION public.mind_inbound(p_evento jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'crm'
AS $function$
declare
  conv   engagement.conversas;
  v_msg  jsonb := jsonb_build_object('mensagem_id', null, 'duplicada', false);
  v_ident jsonb := jsonb_build_object('pessoa_id', null, 'criada', false, 'conflito', null);
  m      jsonb := coalesce(p_evento->'mensagem','{}'::jsonb);
  v_pessoa uuid;
  v_erro text := null;
  v_crm  jsonb := null;
begin
  conv := public.mind_conversa_resolver(p_evento);

  if m ? 'conteudo' or m ? 'blocos' then
    v_msg := public.mind_mensagem_registrar(
      conv.id, coalesce(m->>'papel','lead'), m->>'conteudo',
      coalesce(m->>'id_externo', m->>'client_message_id', m->>'external_message_id'),
      m->'blocos', coalesce(p_evento->>'agente', conv.canal));
  end if;

  begin
    v_ident := public.mind_identidade_resolver(
      coalesce(p_evento->'identificadores','{}'::jsonb),
      p_evento->>'nome', conv.canal, conv.participante_id);
  exception when others then
    v_erro := sqlerrm;
  end;

  v_pessoa := coalesce(conv.participante_id, nullif(v_ident->>'pessoa_id','')::uuid);

  if v_pessoa is not null then
    update engagement.conversas set participante_id = v_pessoa
     where id = conv.id and participante_id is null;
    update engagement.mensagens set participante_id = v_pessoa
     where conversa_id = conv.id and participante_id is null;
    conv.participante_id := v_pessoa;

    if coalesce((v_ident->>'criada')::boolean, false)
       or jsonb_array_length(coalesce(v_ident->'identidades','[]'::jsonb)) > 0 then
      begin
        v_crm := public.mind_crm_vincular_pessoa(v_pessoa);
      exception when others then
        v_crm := jsonb_build_object('ok', false, 'erro', sqlerrm);
      end;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'canal', conv.canal, 'conversa_id', conv.id,
    'sessao_externa', conv.session_external_id,
    'mensagem_id', v_msg->'mensagem_id',
    'mensagem_duplicada', coalesce((v_msg->>'duplicada')::boolean, false),
    'pessoa_id', v_pessoa,
    'pessoa_criada', coalesce((v_ident->>'criada')::boolean, false),
    'pessoa_ancorada', coalesce((v_ident->>'ancorada')::boolean, false),
    'identidades_novas', v_ident->'identidades',
    'conflito_identidade', v_ident->'conflito',
    'identidade_erro', v_erro,
    'crm', v_crm,
    'origem_codigo', conv.origem_codigo, 'produto_codigo', conv.produto_codigo,
    'utm', conv.utm, 'nome_contato', conv.nome_contato,
    'audience', conv.audience, 'stage', conv.stage, 'variables', conv.variables);
end $function$
;

CREATE OR REPLACE FUNCTION public.mind_materiais_para(p_canal text DEFAULT 'whatsapp_treble'::text, p_audiencia text DEFAULT 'desconhecido'::text, p_icp text DEFAULT NULL::text, p_origem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'summit', 'comum', 'engagement', 'intelligence', 'mind'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'titulo', m.titulo, 'tipo', m.tipo,
           'sobre_o_que_e', m.conteudo_resumo,
           'quando_usar', m.quando_usar,
           'objecoes_que_quebra', m.objecoes_que_quebra,
           'link', public.mind_material_link(m.url, m.codigo, m.utm_campaign, p_canal, p_origem)
         ) order by m.ordem), '[]'::jsonb)
  from comum.materiais m
  where m.ativo and m.status = 'pronto' and m.url is not null
    and (coalesce(p_audiencia,'desconhecido') = any(m.audiencias))
    and (cardinality(m.icp) = 0 or p_icp is null or p_icp = any(m.icp));
$function$
;

CREATE OR REPLACE FUNCTION public.mind_material_link(p_url text, p_codigo text, p_utm_campaign text, p_canal text, p_origem text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'summit', 'comum', 'engagement', 'intelligence', 'mind'
AS $function$
  select p_url
      || case when position('?' in p_url) > 0 then '&' else '?' end
      || 'utm_source=' || public.mind_urlencode(coalesce(
           (select o.site from engagement.origens o where o.codigo = p_origem), 'mind'))
      || '&utm_medium=' || case p_canal
            when 'whatsapp_treble' then 'chatbot'
            when 'site_concierge'  then 'chatbot_concierge'
            else public.mind_urlencode(p_canal) end
      || '&utm_campaign=' || public.mind_urlencode(coalesce(nullif(p_utm_campaign,''), p_codigo))
      || '&utm_content=' || public.mind_urlencode(coalesce(nullif(p_origem,''), 'sem_origem'));
$function$
;

CREATE OR REPLACE FUNCTION public.mind_mensagem_registrar(p_conversa_id uuid, p_papel text, p_conteudo text, p_id_externo text DEFAULT NULL::text, p_blocos jsonb DEFAULT NULL::jsonb, p_origem text DEFAULT 'conversa'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement'
AS $function$
declare
  v_papel text := case lower(btrim(coalesce(p_papel,'lead')))
                    when 'user' then 'lead' when 'assistant' then 'agente'
                    when 'system' then 'sistema' else lower(btrim(coalesce(p_papel,'lead'))) end;
  v_txt   text := nullif(btrim(coalesce(p_conteudo,'')),'');
  v_ext   text := nullif(left(btrim(coalesce(p_id_externo,'')),160),'');
  v_pes   uuid;
  v_id    uuid;
  v_dup   boolean := false;
begin
  if v_papel not in ('lead','agente','sistema') then
    raise exception using errcode='22023', message='papel_invalido';
  end if;
  if v_txt is null and p_blocos is null then
    return jsonb_build_object('mensagem_id', null, 'duplicada', false, 'vazia', true);
  end if;

  select participante_id into v_pes from engagement.conversas where id = p_conversa_id;

  insert into engagement.mensagens
    (conversa_id, participante_id, papel, conteudo, blocos, client_msg_id, origem)
  values (p_conversa_id, v_pes, v_papel, left(v_txt, 8000), p_blocos, v_ext,
          coalesce(p_origem,'conversa'))
  on conflict (conversa_id, client_msg_id) where client_msg_id is not null do nothing
  returning id into v_id;

  if v_id is null and v_ext is not null then
    select m.id into v_id from engagement.mensagens m
     where m.conversa_id = p_conversa_id and m.client_msg_id = v_ext;
    v_dup := v_id is not null;
  end if;

  update engagement.conversas set ultima_atividade = now() where id = p_conversa_id;
  return jsonb_build_object('mensagem_id', v_id, 'duplicada', v_dup, 'papel', v_papel);
end $function$
;

CREATE OR REPLACE FUNCTION public.mind_nome_bate(p_nome text, p_sobrenome text, q_nome text, q_sobrenome text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  with a as (select public.mind_nome_simples(nullif(trim(concat_ws(' ',p_nome,p_sobrenome)),'')) c,
                    public.mind_nome_simples(nullif(trim(coalesce(p_nome,'')),'')) p),
       b as (select public.mind_nome_simples(nullif(trim(concat_ws(' ',q_nome,q_sobrenome)),'')) c,
                    public.mind_nome_simples(nullif(trim(coalesce(q_nome,'')),'')) p)
  select case
    when (select c from a) is null or (select c from b) is null then null
    when (select c from a) = (select c from b) then true
    -- sobrenome acrescentado: um comeca com o outro E o primeiro nome e o mesmo
    when (select p from a) is not distinct from (select p from b)
         and ((select c from a) like (select c from b) || '%'
           or (select c from b) like (select c from a) || '%') then true
    else false
  end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_nome_conflita(p_nome text, p_sobrenome text, q_nome text, q_sobrenome text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  with a as (select public.mind_nome_simples(nullif(trim(concat_ws(' ',p_nome,p_sobrenome)),'')) c),
       b as (select public.mind_nome_simples(nullif(trim(concat_ws(' ',q_nome,q_sobrenome)),'')) c)
  select case
    -- sem nome de um dos lados: nao da para vetar
    when (select c from a) is null or (select c from b) is null then false
    when (select c from a) = (select c from b) then false
    -- apelido/abreviacao: um contido no outro nao conflita (Rafa/Rafael)
    when (select c from a) like '%'||(select c from b)||'%'
      or (select c from b) like '%'||(select c from a)||'%' then false
    -- conflita so quando nao compartilham NADA
    else similarity((select c from a), (select c from b)) = 0
  end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_nome_simples(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select nullif(regexp_replace(
           lower(translate(coalesce(p,''),
             'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
             'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')),
           '[^a-z0-9]+', '', 'g'), '');
$function$
;

CREATE OR REPLACE FUNCTION public.mind_origem(p_codigo text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'summit', 'comum', 'engagement', 'intelligence', 'mind'
AS $function$
  select case when p_codigo is null then null else (
    select jsonb_build_object(
      'codigo', o.codigo,
      'site', o.site,
      'botao', o.botao_rotulo,
      'descricao', o.descricao,
      'mensagem_abertura', o.mensagem_abertura,
      'mensagem_encerramento', o.mensagem_encerramento,
      'mensagem_descadastro', o.mensagem_descadastro,
      'hubspot', o.hubspot,
      'audiencia_sugerida', o.audiencia_sugerida)
    from engagement.origens o
    where o.codigo = p_codigo and o.ativo
  ) end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_pendencia_resolver(p_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement'
AS $function$
declare v_antes text;
begin
  if p_status not in ('fundido','descartado') then
    raise exception using errcode='22023', message='status_de_resolucao_invalido';
  end if;

  select status into v_antes from engagement.identidade_fusoes where id = p_id;
  if v_antes is null then
    return jsonb_build_object('ok', false, 'motivo','pendencia_inexistente');
  end if;
  if v_antes <> 'pendente' then
    return jsonb_build_object('ok', false, 'motivo','ja_resolvida', 'status', v_antes);
  end if;

  -- NAO executa merge: so registra a decisao. Fundir contatos e outra etapa.
  update engagement.identidade_fusoes
     set status = p_status, resolvido_em = now()
   where id = p_id;

  return jsonb_build_object('ok', true, 'id', p_id, 'status', p_status);
end $function$
;

CREATE OR REPLACE FUNCTION public.mind_pendencias_listar(p_status text DEFAULT 'pendente'::text, p_tipo text DEFAULT NULL::text, p_limite integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, tipo text, status text, motivo text, pessoa_id uuid, pessoa text, pessoa_origem_id uuid, pessoa_origem text, evidencia jsonb, criado_em timestamp with time zone, resolvido_em timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
  select f.id, f.tipo, f.status, f.motivo,
         f.participante_id,
         nullif(btrim(coalesce(a.primeiro_nome,'')||' '||coalesce(a.sobrenome,'')),''),
         f.participante_origem,
         nullif(btrim(coalesce(b.primeiro_nome,'')||' '||coalesce(b.sobrenome,'')),''),
         f.identificador, f.criado_em, f.resolvido_em
    from engagement.identidade_fusoes f
    left join pessoas.pessoas a on a.id = f.participante_id
    left join pessoas.pessoas b on b.id = f.participante_origem
   where (p_status is null or f.status = p_status)
     and (p_tipo   is null or f.tipo   = p_tipo)
   order by f.criado_em desc
   limit greatest(coalesce(p_limite,50), 1) offset greatest(coalesce(p_offset,0), 0);
$function$
;

CREATE OR REPLACE FUNCTION public.mind_pessoa_completar(p_pessoa_id uuid, p_sobrenome text DEFAULT NULL::text, p_empresa text DEFAULT NULL::text, p_cargo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pessoas'
AS $function$
begin
  if p_pessoa_id is null then return null; end if;

  update pessoas.pessoas set
    sobrenome     = coalesce(sobrenome, nullif(left(trim(coalesce(p_sobrenome,'')),120),'')),
    empresa       = coalesce(empresa,   nullif(left(trim(coalesce(p_empresa,'')),160),'')),
    cargo         = coalesce(cargo,     nullif(left(trim(coalesce(p_cargo,'')),120),'')),
    atualizado_em = now()
  where id = p_pessoa_id;

  return (select jsonb_build_object('perfil', jsonb_strip_nulls(jsonb_build_object(
            'pessoa_id', p.id, 'primeiro_nome', p.primeiro_nome, 'sobrenome', p.sobrenome,
            'email', p.email, 'whatsapp', p.whatsapp, 'empresa', p.empresa, 'cargo', p.cargo)))
          from pessoas.pessoas p where p.id = p_pessoa_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.mind_pessoa_fatos(p_pessoa_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pessoas', 'engagement', 'crm'
AS $function$
with
alvo as (
  select p.id, p.primeiro_nome, p.sobrenome, p.empresa, p.cargo
    from pessoas.pessoas p
   where p.id = p_pessoa_id
),

-- Identidades HubSpot da pessoa. distinct porque o mesmo hubspot_id pode ter
-- mais de uma linha de identidade; um contato conta uma vez.
ident_hs as (
  select distinct i.identificador as hubspot_id
    from engagement.identidades i
   where i.pessoa_id = p_pessoa_id
     and i.canal = 'hubspot'
),
crm_contatos as (
  select c.hubspot_id, c.firstname, c.lastname, c.company, c.jobtitle
    from ident_hs h
    join crm.contato_espelho c on c.hubspot_id = h.hubspot_id
),

campos(campo) as (values ('primeiro_nome'), ('sobrenome'), ('empresa'), ('cargo')),

-- Valores brutos com proveniencia. ord_fonte 0 = pessoas.pessoas, 1 = CRM.
bruto as (
  select 'primeiro_nome'::text as campo, a.primeiro_nome as valor, 0 as ord_fonte, null::text as hubspot_id from alvo a
  union all select 'sobrenome',     a.sobrenome, 0, null::text from alvo a
  union all select 'empresa',       a.empresa,   0, null::text from alvo a
  union all select 'cargo',         a.cargo,     0, null::text from alvo a
  union all select 'primeiro_nome', c.firstname, 1, c.hubspot_id from crm_contatos c
  union all select 'sobrenome',     c.lastname,  1, c.hubspot_id from crm_contatos c
  union all select 'empresa',       c.company,   1, c.hubspot_id from crm_contatos c
  union all select 'cargo',         c.jobtitle,  1, c.hubspot_id from crm_contatos c
),

-- Normalizacao. `valor` e a representacao devolvida (preserva o case da fonte,
-- limpa espaco); `chave` e a forma de COMPARACAO: trim + espacos consecutivos +
-- case. Nada de acento, similaridade ou semantica.
limpo as (
  select b.campo,
         btrim(regexp_replace(b.valor, '\s+', ' ', 'g'))        as valor,
         lower(btrim(regexp_replace(b.valor, '\s+', ' ', 'g'))) as chave,
         b.ord_fonte, b.hubspot_id
    from bruto b
   where nullif(btrim(coalesce(b.valor, '')), '') is not null
),

-- Um grupo por fato distinto. A grafia devolvida prefere pessoas.pessoas quando
-- ela pertence ao grupo; senao, o contato CRM de menor hubspot_id. E so
-- representacao textual: nao significa precedencia factual.
grupos as (
  select l.campo, l.chave,
         (array_agg(l.valor order by l.ord_fonte, l.hubspot_id, l.valor))[1] as representacao
    from limpo l
   group by l.campo, l.chave
),

fontes_dedup as (
  select distinct l.campo, l.chave, l.ord_fonte, l.hubspot_id from limpo l
),
fontes_json as (
  select f.campo, f.chave,
         jsonb_agg(
           case when f.ord_fonte = 0
                then jsonb_build_object('tipo', 'pessoa')
                else jsonb_build_object('tipo', 'crm', 'hubspot_id', f.hubspot_id)
           end
           order by f.ord_fonte, f.hubspot_id) as fontes
    from fontes_dedup f
   group by f.campo, f.chave
),

perfil as (
  select jsonb_object_agg(
           k.campo,
           case when (select count(*) from grupos g where g.campo = k.campo) = 1
                then to_jsonb((select g.representacao from grupos g where g.campo = k.campo))
                else 'null'::jsonb
           end) as j
    from campos k
),

valores_json as (
  select g.campo,
         jsonb_agg(jsonb_build_object('valor', g.representacao, 'fontes', fj.fontes)
                   order by g.chave) as valores
    from grupos g
    join fontes_json fj on fj.campo = g.campo and fj.chave = g.chave
   group by g.campo
),
conflitos as (
  select coalesce(
           jsonb_agg(jsonb_build_object('campo', v.campo, 'valores', v.valores) order by v.campo),
           '[]'::jsonb) as j
    from valores_json v
   where (select count(*) from grupos g where g.campo = v.campo) >= 2
),

identificadores as (
  select coalesce(
           jsonb_agg(jsonb_build_object(
             'canal',         i.canal,
             'identificador', i.identificador,
             'verificado',    i.verificado,
             'confianca',     i.confianca)
           order by i.canal, i.identificador),
           '[]'::jsonb) as j
    from engagement.identidades i
   where i.pessoa_id = p_pessoa_id
),

-- Pendencia e FATO, nao efeito: nao remove dado, nao troca pessoa_id, nao funde
-- e nao desempata perfil. Fica registrada para quem consome depois.
pendencia as (
  select count(*) > 0 as aberta,
         coalesce(jsonb_agg(distinct f.tipo order by f.tipo), '[]'::jsonb) as tipos
    from engagement.identidade_fusoes f
   where f.status = 'pendente'
     and (f.participante_id = p_pessoa_id or f.participante_origem = p_pessoa_id)
),

meta as (
  select jsonb_build_object(
    'pendencia_identidade', jsonb_build_object('aberta', pd.aberta, 'tipos', pd.tipos),
    'contatos_hubspot_considerados', (select count(*) from crm_contatos),
    -- identidade hubspot que nao tem espelho nao e silenciada nem inventada:
    -- vira contagem, e nunca conflito de perfil.
    'identidades_hubspot_sem_espelho', (
      select count(*) from ident_hs h
       where not exists (select 1 from crm.contato_espelho c where c.hubspot_id = h.hubspot_id))
  ) as j
  from pendencia pd
)

select case
  when p_pessoa_id is null then
    jsonb_build_object('ok', false, 'motivo', 'sem_pessoa')
  when not exists (select 1 from alvo) then
    jsonb_build_object('ok', false, 'motivo', 'pessoa_nao_encontrada', 'pessoa_id', p_pessoa_id)
  else
    jsonb_build_object(
      'ok',               true,
      'pessoa_id',        p_pessoa_id,
      'perfil',           (select j from perfil),
      'identificadores',  (select j from identificadores),
      'conflitos_perfil', (select j from conflitos),
      'meta',             (select j from meta))
end
$function$
;

CREATE OR REPLACE FUNCTION public.mind_precos_por_volume()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'summit_2026', 'engagement', 'intelligence', 'mind'
AS $function$
  with tiers as (
    select (t->>'min')::int as min_ingressos,
           (t->>'off')::numeric as off,
           t->>'label' as faixa
    from summit_2026.commercial_rules r,
         lateral jsonb_array_elements(r.config->'tiers') t
    where r.chave = 'desconto_por_volume' and r.ativo
      and (t->>'off')::numeric > 0
  ), ofertas as (
    select o.codigo, o.nome, o.valor
    from summit_2026.offers o
    where o.ativo and o.publico and o.valor is not null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'faixa', t.faixa,
           'a_partir_de_ingressos', t.min_ingressos,
           'desconto_percentual', round(t.off * 100),
           'experiencia', o.nome,
           'valor_cheio_por_ingresso', o.valor,
           'valor_por_ingresso_com_desconto', round(o.valor * (1 - t.off)),
           'economia_por_ingresso', round(o.valor * t.off),
           'parcelamento_com_desconto', '12x de R$ ' || round(o.valor * (1 - t.off) / 12)
         ) order by t.min_ingressos, o.valor), '[]'::jsonb)
  from tiers t cross join ofertas o;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_rota_capacidade(p_rota text, p_canal text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'agentes'
AS $function$
with entrada as (
  select nullif(btrim(p_rota), '')  as rota,
         nullif(btrim(p_canal), '') as canal
),
-- Taxonomia canonica do Router. Fechada. `ja_comprou` e `desconhecido` nao sao rotas.
rota_valida as (
  select e.rota
    from entrada e
   where e.rota in ('summit_b2c','summit_b2b','institute','dash',
                    'cliente_suporte','concierge_summit')
),
-- Canais canonicos vivos. Sem alias: 'web' nao e canal.
canal_valido as (
  select e.canal
    from entrada e
   where e.canal in ('whatsapp','mindagent-web')
),
-- PLAYBOOK — lido do sistema, nunca fixo aqui. Disponivel so quando a linha
-- existe, esta ativa e tem conteudo: um playbook vazio nao ensina nada.
playbook as (
  select exists (
    select 1 from agentes.prompts pr, entrada e
     where pr.chave = 'playbook_' || e.rota
       and pr.ativo
       and btrim(coalesce(pr.conteudo, '')) <> ''
  ) as tem
),
-- KIT — transitorio, ver cabecalho. O criterio e ACESSIBILIDADE AO RUNTIME
-- ATUAL, nao existencia do dado. Estado real hoje:
--
--   summit_b2c        TEM. treble_agent_context entrega evento e ofertas ativas
--                     e publicas, com preco, condicoes e checkout — que e o que
--                     o playbook_summit_b2c precisa.
--   concierge_summit  TEM. sessions, locations, speakers, exhibitors e
--                     event_rules do summit_2026, alcancaveis pelo
--                     mindagent_chat_search que o proprio canal chama.
--   summit_b2b        NAO TEM. desconto_por_volume existe e esta ativo em
--                     summit_2026.commercial_rules, mas treble_agent_context nao
--                     o entrega, e o playbook exige o bloco `precos_por_volume`
--                     dentro de DADOS_OFICIAIS. Dado existe; kit nao chega.
--   cliente_suporte   NAO TEM. Sem base de politica de suporte, sem consulta de
--                     pedido exposta ao agente, e `suporte.chamado` aponta para
--                     um schema inexistente.
--   institute, dash   NAO TEM. Nenhum dado, nenhum executor.
kit as (
  select (select rota from rota_valida) in
         ('summit_b2c','concierge_summit') as tem
),
-- CANAL — "este runtime executa esta rota autonomamente?". Nao e "este canal
-- alcanca um humano": essa e a pergunta do Passo 14.
--
--   whatsapp        treble-inbound-agent, que compoe playbook por
--                   treble_agent_prompt: as tres rotas comerciais e de
--                   atendimento. Nao faz concierge — sua pilha inteira e venda.
--   mindagent-web   mindagent-chat, concierge de Summit por construcao, com
--                   instrucoes fixas no codigo que dizem explicitamente que ele
--                   nao vende, nao compra e nao altera dados.
canal_executa as (
  select case (select canal from canal_valido)
           when 'whatsapp'      then (select rota from rota_valida)
                                     in ('summit_b2c','summit_b2b','cliente_suporte')
           when 'mindagent-web' then (select rota from rota_valida)
                                     in ('concierge_summit')
         end as tem
),
-- PRECEDENCIA FECHADA: missing_playbook > missing_kit > canal_incompativel.
-- Um unico reason, nunca uma lista. A ordem nao e arbitraria — ela vai do que
-- falta mais fundo para o que falta mais na ponta, e o primeiro e o unico que
-- uma pessoa destrava escrevendo um texto.
avaliado as (
  select case
           when not (select tem from playbook)      then 'missing_playbook'
           when not (select tem from kit)           then 'missing_kit'
           when not (select tem from canal_executa) then 'canal_incompativel'
         end as reason
)
select case
  when (select count(*) from rota_valida)  = 0 then jsonb_build_object('ok', false, 'motivo', 'rota_invalida')
  when (select count(*) from canal_valido) = 0 then jsonb_build_object('ok', false, 'motivo', 'canal_invalido')
  else jsonb_build_object(
    'ok',    true,
    'rota',  (select rota  from rota_valida),
    'canal', (select canal from canal_valido),
    'pode_executar', (select reason from avaliado) is null,
    -- needs_human e NECESSIDADE, nao mecanismo: "isto nao pode ser concluido
    -- sozinho e precisa de gente". Nao afirma que existe humano alcancavel
    -- neste canal — inclusive em mindagent-web, onde nao ha. Como a
    -- intervencao acontece e o Passo 14.
    'needs_human',   (select reason from avaliado) is not null,
    'reason',        (select reason from avaliado))
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_slug(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select left(
    trim(both '_' from
      regexp_replace(
        translate(lower(coalesce(p_texto,'')),
                  'áàâãäéèêëíìîïóòôõöúùûüçñ',
                  'aaaaaeeeeiiiiooooouuuucn'),
        '[^a-z0-9]+', '_', 'g')),
    60);
$function$
;

CREATE OR REPLACE FUNCTION public.mind_sync_abrir(p_fonte text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'crm', 'platform'
AS $function$
declare
  s crm.sync_estado;
  cfg jsonb;
begin
  select * into s from crm.sync_estado where fonte = p_fonte;
  if not found then
    raise exception 'fonte desconhecida: %', p_fonte;
  end if;

  select config into cfg from platform.integracoes where codigo = 'hubspot' and ativo;

  update crm.sync_estado
     set status = 'rodando', iniciado_em = now(), erro = null
   where fonte = p_fonte;

  return jsonb_build_object(
    'marca_dagua', s.marca_dagua,
    'cursor', s.cursor,
    'carga_completa_em', s.carga_completa_em,
    'tabela_destino', s.tabela_destino,
    'chave_destino', s.chave_destino,
    'config', coalesce(cfg, '{}'::jsonb));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_sync_marcar(p_fonte text, p_marca timestamp with time zone DEFAULT NULL::timestamp with time zone, p_lidos integer DEFAULT NULL::integer, p_gravados integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_erro text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'crm'
AS $function$
  update crm.sync_estado
     set marca_dagua       = coalesce(p_marca, marca_dagua),
         registros_lidos   = coalesce(p_lidos, registros_lidos),
         registros_gravados= coalesce(p_gravados, registros_gravados),
         status            = coalesce(p_status, status),
         erro              = p_erro,
         concluido_em      = case when p_status = 'ocioso' then now() else concluido_em end
   where fonte = p_fonte;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_sync_marcar(p_fonte text, p_marca timestamp with time zone DEFAULT NULL::timestamp with time zone, p_lidos integer DEFAULT NULL::integer, p_gravados integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_erro text DEFAULT NULL::text, p_cursor text DEFAULT NULL::text, p_completou boolean DEFAULT false)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'crm'
AS $function$
  update crm.sync_estado
     set marca_dagua       = coalesce(p_marca, marca_dagua),
         registros_lidos   = coalesce(p_lidos, registros_lidos),
         registros_gravados= coalesce(p_gravados, registros_gravados),
         status            = coalesce(p_status, status),
         erro              = p_erro,
         -- cursor nulo so e apagado quando a varredura completa termina; no meio
         -- do caminho, nulo significa "nao mexe".
         cursor            = case when p_completou then null else coalesce(p_cursor, cursor) end,
         carga_completa_em = case when p_completou then now() else carga_completa_em end,
         concluido_em      = case when p_status = 'ocioso' then now() else concluido_em end
   where fonte = p_fonte;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_turno_registrar(p_conversa_id uuid, p_resposta text, p_estado jsonb DEFAULT '{}'::jsonb, p_meta jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement'
AS $function$
declare v_msg jsonb;
begin
  v_msg := public.mind_mensagem_registrar(p_conversa_id, 'agente', p_resposta,
             p_meta->>'request_id', p_meta, 'agente');

  update engagement.conversas set
    audience  = coalesce(nullif(p_estado->>'audience',''), audience),
    stage     = coalesce(nullif(p_estado->>'stage',''), stage),
    variables = coalesce(variables,'{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
      'intent',          nullif(p_estado->>'intent',''),
      'ticket_interest', nullif(p_estado->>'ticket_interest',''),
      'objection',       nullif(p_estado->>'objection',''),
      'needs_human',     (p_estado->>'needs_human')::boolean,
      'checkout_sent',   (coalesce((variables->>'checkout_sent')::boolean,false)
                          or coalesce((p_estado->>'checkout_sent')::boolean,false)),
      'desfecho',        nullif(p_estado->>'desfecho',''))),
    encerrada_em = case when nullif(p_estado->>'desfecho','') is not null then now() else encerrada_em end,
    ultima_atividade = now()
  where id = p_conversa_id;

  return v_msg;
end $function$
;

CREATE OR REPLACE FUNCTION public.mind_urlencode(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select coalesce(string_agg(
    case when c ~ '^[A-Za-z0-9_.~-]$' then c
         else (select string_agg('%' || upper(substring(x.h from i for 2)), '')
                 from (select encode(convert_to(c, 'UTF8'), 'hex') as h) x,
                      generate_series(1, length(x.h), 2) as i)
    end, '' order by n), '')
  from unnest(string_to_array(p, null)) with ordinality as u(c, n);
$function$
;

CREATE OR REPLACE FUNCTION public.mind_utm_registrar(p_dados jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'summit', 'comum', 'engagement', 'intelligence', 'mind'
AS $function$
declare
  t text;
  tentativa int := 0;
begin
  loop
    t := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
    exit when not exists (select 1 from engagement.utm_sessoes where token = t);
    tentativa := tentativa + 1;
    if tentativa > 20 then raise exception 'nao foi possivel gerar token'; end if;
  end loop;

  insert into engagement.utm_sessoes (
    token, site, origem_codigo, utm_source, utm_medium, utm_campaign,
    utm_content, utm_term, gclid, fbclid, referrer, landing_url)
  values (
    t,
    left(nullif(trim(p_dados->>'site'),''), 40),
    (select o.codigo from engagement.origens o
      where o.codigo = nullif(trim(p_dados->>'origem'),'') and o.ativo),
    left(nullif(trim(p_dados->>'utm_source'),''), 120),
    left(nullif(trim(p_dados->>'utm_medium'),''), 120),
    left(nullif(trim(p_dados->>'utm_campaign'),''), 200),
    left(nullif(trim(p_dados->>'utm_content'),''), 200),
    left(nullif(trim(p_dados->>'utm_term'),''), 200),
    left(nullif(trim(p_dados->>'gclid'),''), 200),
    left(nullif(trim(p_dados->>'fbclid'),''), 200),
    left(nullif(trim(p_dados->>'referrer'),''), 500),
    left(nullif(trim(p_dados->>'landing_url'),''), 500));

  return t;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_virada_de_lote()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'summit_2026', 'ecossistema', 'engagement', 'intelligence', 'mind', 'treble'
AS $function$
  with janela as (
    select coalesce((select valor::int from treble.config where chave = 'janela_urgencia_dias'), 7) as dias
  ), atual as (
    select o.elegibilidade->>'categoria' as categoria, o.valor, o.encerra_em
    from summit_2026.offers o
    where o.ativo and o.publico and o.encerra_em is not null
      and not (o.elegibilidade ? 'grupo')
  ), fim as (
    select min(encerra_em) as encerra_em from atual
  ), conta as (
    select f.encerra_em,
           (f.encerra_em at time zone 'America/Sao_Paulo') as fim_sp,
           ((f.encerra_em at time zone 'America/Sao_Paulo')::date
            - (now() at time zone 'America/Sao_Paulo')::date) as dias_restantes,
           j.dias as janela_dias
    from fim f cross join janela j
  )
  select case when (select encerra_em from conta) is null then null else
    jsonb_build_object(
      'ultimo_dia_do_lote_atual', to_char((select fim_sp from conta), 'DD/MM/YYYY'),
      'dia_da_semana', (select case extract(isodow from fim_sp)
          when 1 then 'segunda-feira' when 2 then 'terca-feira' when 3 then 'quarta-feira'
          when 4 then 'quinta-feira'  when 5 then 'sexta-feira' when 6 then 'sabado'
          else 'domingo' end from conta),
      'dias_restantes', (select dias_restantes from conta),
      'janela_de_comunicacao_dias', (select janela_dias from conta),
      'pode_usar_como_urgencia',
        (select dias_restantes <= janela_dias and dias_restantes >= 0 from conta)
    ) end;
$function$
;

CREATE OR REPLACE FUNCTION public.mindagent_bootstrap(p_event_slug text DEFAULT 'mind-summit-2026'::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'api'
AS $function$
  select api.mindagent_bootstrap(p_event_slug);
$function$
;

CREATE OR REPLACE FUNCTION public.mindagent_chat_bind_identity(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text, p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare v_sess engagement.agent_sessions%rowtype; v_res jsonb; v_pessoa uuid; v_ancora uuid;
begin
  select * into v_sess from engagement.agent_sessions
   where id = p_session_id and auth_user_id = p_auth_user_id
     and token_hash = p_token_hash and expira_em > now() for update;
  if not found then raise exception using errcode='28000', message='invalid_chat_session'; end if;

  select participante_id into v_ancora from engagement.conversas
   where id = p_conversation_id and dispositivo_id = v_sess.dispositivo_id;

  v_res := public.mind_identidade_resolver(
    jsonb_build_object('email', p_email, 'auth_user_id', p_auth_user_id::text),
    null, 'mindagent-web', v_ancora);

  v_pessoa := coalesce(v_ancora, nullif(v_res->>'pessoa_id','')::uuid);
  if v_pessoa is not null then
    update engagement.agent_sessions set participante_id = v_pessoa, ultima_atividade = now()
     where id = v_sess.id;
    update engagement.conversas set participante_id = coalesce(participante_id, v_pessoa),
           ultima_atividade = now()
     where id = p_conversation_id and dispositivo_id = v_sess.dispositivo_id;
    update engagement.mensagens set participante_id = v_pessoa
     where conversa_id = p_conversation_id and participante_id is null;
  end if;

  return v_res || jsonb_build_object(
    'pessoa_id', v_pessoa,
    'found', v_pessoa is not null,
    'conflict', (v_res->'conflito') is not null and v_res->>'conflito' <> 'null',
    'profile', coalesce((public.mind_conversa_estado(p_conversation_id))->'perfil','{}'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.mindagent_chat_get_context(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'summit', 'comum', 'mind', 'engagement', 'intelligence', 'concierge'
AS $function$
declare
  v_session engagement.agent_sessions%rowtype;
  v_conversation engagement.conversas%rowtype;
  v_history jsonb := '[]'::jsonb;
  v_interests jsonb := '[]'::jsonb;
  v_profile jsonb := null;
begin
  select * into v_session
  from engagement.agent_sessions
  where id = p_session_id
    and auth_user_id = p_auth_user_id
    and token_hash = p_token_hash
    and expira_em > now();

  if not found then
    raise exception using errcode = '28000', message = 'invalid_chat_session';
  end if;

  select * into v_conversation
  from engagement.conversas
  where id = p_conversation_id
    and dispositivo_id = v_session.dispositivo_id
    and encerrada_em is null;

  if not found then
    raise exception using errcode = '28000', message = 'invalid_chat_conversation';
  end if;

  update engagement.agent_sessions set ultima_atividade = now() where id = v_session.id;
  update engagement.dispositivos set ultimo_acesso = now() where id = v_session.dispositivo_id;
  update engagement.conversas set ultima_atividade = now() where id = v_conversation.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'role', h.papel,
    'content', h.conteudo
  ) order by h.criado_em), '[]'::jsonb)
  into v_history
  from (
    select papel, conteudo, criado_em
    from engagement.mensagens
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
  from engagement.session_interests i
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
    from engagement.v_pessoa p
    left join intelligence.participante_contexto pc
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
$function$
;

CREATE OR REPLACE FUNCTION public.mindagent_chat_save_interests(p_auth_user_id uuid, p_session_id uuid, p_token_hash text, p_interests jsonb, p_evidence_message_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'engagement', 'intelligence', 'summit', 'comum', 'concierge'
AS $function$
declare
  v_item jsonb;
  v_saved integer := 0;
  v_promoted integer := 0;
  v_session_skipped integer := 0;
  v_permanent_skipped integer := 0;
  v_key text;
  v_label text;
  v_confidence numeric;
  v_confirmed boolean;
  v_participant_id uuid;
  v_profile_item jsonb;
  v_interest_exists boolean;
  v_interest_count integer;
begin
  select s.participante_id
    into v_participant_id
  from engagement.agent_sessions s
  where s.id = p_session_id
    and s.auth_user_id = p_auth_user_id
    and s.token_hash = p_token_hash
    and s.expira_em > now();

  if not found then
    raise exception using errcode = '28000', message = 'invalid_chat_session';
  end if;

  if p_interests is null or jsonb_typeof(p_interests) <> 'array' then
    return jsonb_build_object(
      'saved', 0,
      'promoted', 0,
      'session_skipped', 0,
      'permanent_skipped', 0
    );
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
        select 1
        from engagement.session_interests si
        where si.agent_session_id = p_session_id
          and si.chave = v_key
      ) into v_interest_exists;

      select count(*)
        into v_interest_count
      from engagement.session_interests si
      where si.agent_session_id = p_session_id;

      if v_interest_exists or v_interest_count < 12 then
        insert into engagement.session_interests (
          agent_session_id, chave, rotulo, confianca,
          evidencia_message_id, ocorrencias, primeira_em, ultima_em
        ) values (
          p_session_id, v_key, v_label, v_confidence,
          p_evidence_message_id, 1, now(), now()
        )
        on conflict (agent_session_id, chave) do update
          set rotulo = excluded.rotulo,
              confianca = greatest(engagement.session_interests.confianca, excluded.confianca),
              evidencia_message_id = coalesce(excluded.evidencia_message_id, engagement.session_interests.evidencia_message_id),
              ocorrencias = engagement.session_interests.ocorrencias + 1,
              ultima_em = now();

        v_saved := v_saved + 1;
      else
        v_session_skipped := v_session_skipped + 1;
      end if;

      if v_confirmed and v_confidence >= 0.85 and v_participant_id is not null then
        perform pg_advisory_xact_lock(hashtextextended('mindagent-interest:' || v_participant_id::text, 0));

        select exists (
          select 1
          from intelligence.participante_memoria pm
          where pm.participante_id = v_participant_id
            and pm.tipo = 'interesse'
            and pm.chave = v_key
            and pm.status = 'ativa'
        ) into v_interest_exists;

        select count(*)
          into v_interest_count
        from intelligence.participante_memoria pm
        where pm.participante_id = v_participant_id
          and pm.tipo = 'interesse'
          and pm.status = 'ativa';

        if v_interest_exists or v_interest_count < 8 then
          v_profile_item := jsonb_build_object(
            'key', v_key,
            'label', v_label,
            'source', 'confirmado_pelo_usuario',
            'confirmed', true,
            'confidence', v_confidence
          );

          insert into intelligence.participante_memoria (
            participante_id, tipo, chave, valor, confianca, origem,
            evidencia_message_id, status, importancia, criado_em, atualizado_em
          ) values (
            v_participant_id, 'interesse', v_key,
            jsonb_build_object('label', v_label, 'confirmed', true),
            v_confidence, 'confirmado_pelo_usuario',
            p_evidence_message_id, 'ativa', v_confidence, now(), now()
          )
          on conflict (participante_id, chave) where status = 'ativa' do update
            set tipo = 'interesse',
                valor = excluded.valor,
                confianca = greatest(intelligence.participante_memoria.confianca, excluded.confianca),
                origem = 'confirmado_pelo_usuario',
                evidencia_message_id = coalesce(excluded.evidencia_message_id, intelligence.participante_memoria.evidencia_message_id),
                importancia = greatest(coalesce(intelligence.participante_memoria.importancia, 0), excluded.importancia),
                atualizado_em = now();

          insert into intelligence.participante_contexto as pc (
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
$function$
;

CREATE OR REPLACE FUNCTION public.mindagent_chat_save_message(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text, p_role text, p_content text, p_client_message_id text, p_blocks jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement'
AS $function$
declare v_sess engagement.agent_sessions%rowtype; v_msg jsonb;
begin
  select * into v_sess from engagement.agent_sessions
   where id = p_session_id and auth_user_id = p_auth_user_id
     and token_hash = p_token_hash and expira_em > now();
  if not found then raise exception using errcode='28000', message='invalid_chat_session'; end if;

  if not exists (select 1 from engagement.conversas c
                  where c.id = p_conversation_id and c.dispositivo_id = v_sess.dispositivo_id
                    and c.encerrada_em is null) then
    raise exception using errcode='28000', message='invalid_chat_conversation';
  end if;

  v_msg := public.mind_mensagem_registrar(p_conversation_id, p_role, p_content,
                                          p_client_message_id, p_blocks, 'mindagent-chat');
  update engagement.agent_sessions set ultima_atividade = now() where id = p_session_id;
  return v_msg;
end $function$
;

CREATE OR REPLACE FUNCTION public.mindagent_chat_search(p_event_slug text, p_query text, p_limit integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'summit_2026', 'ecossistema', 'engagement', 'intelligence', 'mind'
AS $function$
with
params as (
  select
    lower(btrim(left(p_query, 500))) as q,
    least(12, greatest(1, coalesce(p_limit, 8))) as lim,
    nullif((select string_agg(lexeme, ' | ')
              from unnest(to_tsvector('portuguese', left(p_query, 500)))), '')::tsquery as q_or,
    0.1 * least(2, greatest(1, (select count(*)
              from unnest(to_tsvector('portuguese', left(p_query, 500)))))) as piso
),
ev as (
  select e.* from summit_2026.events e, params p
  where e.slug = p_event_slug and e.ativo limit 1
),
loc as (
  select api.treble_find_location(p_event_slug, p_query) as items
),
-- Texto de busca da sessao, montado uma vez. O alias estrutural entra aqui.
sessao_texto as (
  select s.id, s.titulo, s.descricao, s.dia, s.inicio, s.fim,
         s.precisa_reserva, s.vagas_disponiveis, s.event_id, s.espaco_id,
         to_tsvector('portuguese',
           coalesce(s.titulo,'') || ' ' || coalesce(s.descricao,'') || ' ' ||
           array_to_string(coalesce(s.trilhas, '{}'::text[]), ' ') || ' ' ||
           case when s.precisa_reserva then 'precisa reserva ' else '' end ||
           coalesce((
             select string_agg(sp.nome || ' ' || coalesce(sp.instituicao,''), ' ')
             from summit_2026.session_speakers ss
             join ecossistema.palestrantes_especialistas sp on sp.id = ss.speaker_id
             where ss.sessao_id = s.id), '')
         ) as tsv
  from summit_2026.sessions s
),
session_ranked as (
  select
    st.id, st.titulo, st.descricao, st.dia, st.inicio, st.fim,
    st.precisa_reserva, st.vagas_disponiveis,
    l.nome as local,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', sp.nome, 'role', sp.cargo_curto, 'organization', sp.instituicao
      ) order by sp.nome)
      from summit_2026.session_speakers ss
      join ecossistema.palestrantes_especialistas sp on sp.id = ss.speaker_id
      where ss.sessao_id = st.id), '[]'::jsonb) as speakers,
    ts_rank_cd(st.tsv, p.q_or) as score
  from sessao_texto st
  join ev e on e.id = st.event_id
  left join summit_2026.locations l on l.id = st.espaco_id
  cross join params p
  where p.q ~ '(programa|agenda|horario|horário|sessao|sessão|palestra)'
     or (p.q_or is not null and ts_rank_cd(st.tsv, p.q_or) >= p.piso)
),
session_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.id, 'title', x.titulo, 'description', x.descricao,
    'date', x.dia, 'starts_at', x.inicio, 'ends_at', x.fim,
    'location', x.local, 'requires_reservation', x.precisa_reserva,
    'available_places', x.vagas_disponiveis, 'speakers', x.speakers
  ) order by x.score desc, x.inicio, x.titulo), '[]'::jsonb) as items
  from (select * from session_ranked order by score desc, inicio, titulo
        limit (select lim from params)) x
),
-- Palestrante casa por IDENTIDADE, nao por prosa: nome, cargo e instituicao.
palestrante_texto as (
  select sp.id, sp.nome, sp.cargo_curto, sp.instituicao, sp.quem_e,
         to_tsvector('portuguese',
           sp.nome || ' ' || coalesce(sp.cargo_curto,'') || ' ' || coalesce(sp.instituicao,'')) as tsv
  from ecossistema.palestrantes_especialistas sp
),
speaker_ranked as (
  select pt.id, pt.nome, pt.cargo_curto, pt.instituicao, pt.quem_e,
         ts_rank_cd(pt.tsv, p.q_or) as score
  from palestrante_texto pt
  cross join params p
  where exists (
    select 1 from summit_2026.session_speakers ss
    join summit_2026.sessions s on s.id = ss.sessao_id
    join ev e on e.id = s.event_id
    where ss.speaker_id = pt.id)
  and (
    (p.q_or is not null and ts_rank_cd(pt.tsv, p.q_or) >= p.piso)
    -- Nome proprio escrito na pergunta identifica a pessoa mesmo sem cobrir
    -- dois lexemas.
    or lower(translate(p.q, 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')) like '%' || lower(translate(pt.nome, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')) || '%'
    or (
      length(regexp_replace(lower(translate(pt.nome, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')), '^.*[[:space:]]', '')) >= 4
      and lower(translate(p.q, 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')) like '%' || regexp_replace(lower(translate(pt.nome, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')), '^.*[[:space:]]', '') || '%'
    )
    or p.q ~ '(palestrante|speaker|quem vai falar|quem fala)'
  )
),
speaker_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.id, 'name', x.nome, 'role', x.cargo_curto,
    'organization', x.instituicao, 'bio', x.quem_e, 'themes', '[]'::jsonb
  ) order by x.score desc, x.nome), '[]'::jsonb) as items
  from (select * from speaker_ranked order by score desc, nome
        limit (select lim from params)) x
),
mind_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'category', x.tipo_conteudo, 'title', x.titulo, 'body', x.corpo
  ) order by x.score desc, x.titulo), '[]'::jsonb) as items
  from (
    select k.tipo_conteudo, k.titulo, left(k.corpo, 1500) as corpo,
      ts_rank_cd(to_tsvector('portuguese',
        coalesce(k.tipo_conteudo,'') || ' ' || k.titulo || ' ' || k.corpo), p.q_or) as score
    from summit_2026.knowledge_documents k
    cross join params p
    where k.ativo
      and 'concierge' = any(k.agents)
      and (k.event_id is null or k.event_id = (select id from ev))
      and (k.valido_de is null or k.valido_de <= now())
      and (k.valido_ate is null or k.valido_ate > now())
      and (
        (p.q_or is not null and ts_rank_cd(to_tsvector('portuguese',
          coalesce(k.tipo_conteudo,'') || ' ' || k.titulo || ' ' || k.corpo), p.q_or) >= p.piso)
        or p.q ~ '(sobre a mind|o que e a mind|o que é a mind|empresa mind|institucional)'
      )
    order by score desc, k.titulo
    limit (select lim from params)
  ) x
),
exhibitor_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.id, 'name', x.nome, 'description', x.descricao,
    'category', x.categoria, 'location', x.local_nome, 'website', x.site_url
  ) order by x.score desc, x.nome), '[]'::jsonb) as items
  from (
    select x.*, l.nome as local_nome,
      ts_rank_cd(to_tsvector('portuguese',
        x.nome || ' ' || coalesce(x.descricao,'') || ' ' || coalesce(x.categoria,'')), p.q_or) as score
    from summit_2026.exhibitors x
    join ev e on e.id = x.event_id
    left join summit_2026.locations l on l.id = x.location_id
    cross join params p
    where x.ativo
      and (
        (p.q_or is not null and ts_rank_cd(to_tsvector('portuguese',
          x.nome || ' ' || coalesce(x.descricao,'') || ' ' || coalesce(x.categoria,'')), p.q_or) >= p.piso)
        or p.q ~ '(estande|stand|expositor|patrocinador)'
      )
    order by score desc, x.nome
    limit (select lim from params)
  ) x
),
-- OFERTAS: ranqueadas contra a pergunta; nomear o produto basta. Piso 0.1 aqui
-- porque sao 3 linhas de texto curto, onde exigir dois lexemas seria exigencia
-- que o proprio registro nao tem como satisfazer. Gatilho de listagem mantido.
offer_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'code', x.codigo, 'name', x.nome, 'description', x.descricao,
    'currency', x.moeda, 'amount', x.valor,
    'payment_terms', x.condicoes_pagamento, 'checkout_url', x.checkout_url,
    'eligibility', x.elegibilidade
  ) order by x.score desc, x.valor), '[]'::jsonb) as items
  from (
    select o.*,
      ts_rank_cd(to_tsvector('portuguese',
        o.codigo || ' ' || o.nome || ' ' || coalesce(o.descricao,'')), p.q_or) as score
    from summit_2026.offers o
    cross join params p
    where o.ativo and o.publico
      and (o.event_id is null or o.event_id = (select id from ev))
      and (o.inicia_em is null or o.inicia_em <= now())
      and (o.encerra_em is null or o.encerra_em > now())
      and (
        (p.q_or is not null and ts_rank_cd(to_tsvector('portuguese',
          o.codigo || ' ' || o.nome || ' ' || coalesce(o.descricao,'')), p.q_or) >= 0.1)
        or p.q ~ '(valor|preço|preco|ingresso|comprar|compra|checkout|pagamento|oferta)'
      )
  ) x
)
select jsonb_build_object(
  'event', (select jsonb_build_object(
      'slug', e.slug, 'name', e.nome, 'dates', e.dias,
      'location', e.local, 'city', e.cidade, 'timezone', e.fuso) from ev e),
  'locations', (select items from loc),
  'sessions', (select items from session_items),
  'speakers', (select items from speaker_items),
  'mind', (select items from mind_items),
  'exhibitors', (select items from exhibitor_items),
  'offers', (select items from offer_items),
  'official_note', 'Use somente estes dados oficiais. Se algo não estiver presente, informe que ainda não está disponível.'
);
$function$
;

CREATE OR REPLACE FUNCTION public.mindagent_chat_start(p_auth_user_id uuid, p_device_key text, p_user_agent text DEFAULT NULL::text, p_token_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'auth'
AS $function$
declare
  v_session uuid; v_out jsonb; v_disp uuid;
  v_expira timestamptz := now() + interval '24 hours';
begin
  if p_auth_user_id is null or not exists (select 1 from auth.users where id = p_auth_user_id) then
    raise exception using errcode='28000', message='invalid_auth_user';
  end if;
  if p_device_key is null or length(btrim(p_device_key)) < 8 or length(p_device_key) > 160 then
    raise exception using errcode='22023', message='invalid_device_key';
  end if;
  if p_token_hash is null or p_token_hash !~ '^[a-f0-9]{64}$' then
    raise exception using errcode='22023', message='invalid_token_hash';
  end if;

  -- o core resolve conversa + identidade (auth_user e a evidencia mais forte)
  v_out := public.mind_inbound(jsonb_build_object(
    'canal','mindagent-web', 'agente','mindagent-chat',
    'user_agent', p_user_agent,
    'identificadores', jsonb_build_object(
      'auth_user_id', p_auth_user_id::text, 'dispositivo', btrim(p_device_key))));

  select dispositivo_id into v_disp from engagement.conversas
   where id = (v_out->>'conversa_id')::uuid;

  insert into engagement.agent_sessions
    (dispositivo_id, participante_id, auth_user_id, token_hash, origem_identidade,
     confianca, expira_em)
  values (v_disp, nullif(v_out->>'pessoa_id','')::uuid, p_auth_user_id, p_token_hash,
          'supabase_auth', 'alta', v_expira)
  returning id into v_session;

  return jsonb_build_object(
    'session_id', v_session,
    'conversation_id', v_out->'conversa_id',
    'participant_id',  v_out->'pessoa_id',
    'expires_at', v_expira,
    'identity_verified', true);
end $function$
;

CREATE OR REPLACE FUNCTION public.mindagent_sync_offers(p_vigente integer, p_lotes jsonb, p_tiers jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'summit_2026', 'engagement', 'intelligence', 'mind'
AS $function$
declare
  ev uuid;
  n_upserts integer := 0;
begin
  select id into ev from summit_2026.events limit 1;
  if ev is null then
    raise exception 'nenhum evento cadastrado em summit_2026.events';
  end if;

  with lotes as (
    select (l->>'numero')::int as numero,
           nullif(l->>'inicio','')::timestamptz as inicio,
           nullif(l->>'fim','')::timestamptz as fim,
           l->'precos' as precos
    from jsonb_array_elements(p_lotes) l
  ), linhas as (
    select lo.numero, lo.inicio, lo.fim, s.slug, (lo.precos->>s.slug)::numeric as preco
    from lotes lo
    cross join (values ('mind'),('vip'),('prime')) as s(slug)
    where lo.precos ? s.slug
  ), ins as (
    insert into summit_2026.offers as o
      (event_id, codigo, nome, descricao, moeda, valor, condicoes_pagamento,
       checkout_url, elegibilidade, publico, ativo, inicia_em, encerra_em)
    select ev,
      li.slug || '-lote-' || li.numero,
      case li.slug when 'mind' then 'Experiência Mind'
                   when 'vip' then 'Experiência VIP'
                   else 'Experiência Prime' end || ' — Lote ' || li.numero,
      case when li.numero = p_vigente then 'Lote vigente' end,
      'BRL', li.preco,
      '12x de R$ ' || round(li.preco / 12),
      case li.slug when 'mind' then 'https://sun.eduzz.com/89AQDKYGWD'
                   when 'vip' then 'https://sun.eduzz.com/40Q3EKPK0B'
                   else 'https://sun.eduzz.com/E05XKB2KWX' end,
      jsonb_build_object('categoria', li.slug, 'lote', li.numero,
                         'fonte', 'mind-summit-propostas'),
      li.numero = p_vigente,
      li.numero = p_vigente,
      li.inicio, li.fim
    from linhas li
    on conflict (event_id, codigo) do update set
      valor = excluded.valor,
      condicoes_pagamento = excluded.condicoes_pagamento,
      checkout_url = excluded.checkout_url,
      descricao = excluded.descricao,
      elegibilidade = o.elegibilidade || excluded.elegibilidade,
      publico = excluded.publico,
      ativo = excluded.ativo,
      inicia_em = excluded.inicia_em,
      encerra_em = excluded.encerra_em,
      atualizado_em = now()
    returning 1
  ) select count(*) into n_upserts from ins;

  update summit_2026.offers
     set ativo = false, publico = false, atualizado_em = now()
   where event_id = ev and elegibilidade ? 'grupo' and (ativo or publico);

  -- Só os tiers vêm da fonte de preços. 'acao' e 'nota' são política
  -- comercial (item 10) e ficam preservados entre sincronizações.
  update summit_2026.commercial_rules
     set config = config || jsonb_build_object('tiers', p_tiers),
         atualizado_em = now()
   where chave = 'desconto_por_volume';

  return jsonb_build_object('vigente', p_vigente, 'ofertas_sincronizadas', n_upserts);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mindagent_treble_claim_event(p_event_key text, p_session_external_id text, p_request_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'treble'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.mindagent_treble_complete_event(p_event_key text, p_status text, p_error_code text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'treble'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.normalizar_telefone_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  new.telefone := public.telefone_normalizar(new.telefone);
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pessoa_vincular_hubspot(p_pessoa_id uuid, p_hubspot_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'crm'
AS $function$
declare v_hub text := nullif(btrim(coalesce(p_hubspot_id,'')),''); v_ident jsonb;
begin
  if p_pessoa_id is null or v_hub is null then
    return jsonb_build_object('ok', false, 'motivo','parametro_ausente');
  end if;
  v_ident := public.mind_identidade_resolver(
    jsonb_build_object('hubspot_id', v_hub), null, 'hubspot', p_pessoa_id);
  return jsonb_build_object('ok', true, 'identidade', v_ident,
                            'crm', public.mind_crm_vincular_pessoa(p_pessoa_id));
end $function$
;

CREATE OR REPLACE FUNCTION public.silence_calcular_next_review(p_conversa_id uuid, p_dados jsonb, p_followup_count integer DEFAULT 0, p_last_followup_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_action text DEFAULT NULL::text, p_piso timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_cfg      jsonb;
  v_acao     text := upper(coalesce(p_action,''));
  v_compra   text;
  v_declarou boolean;
  v_optout   text;
  v_status   text := lower(coalesce(p_dados->>'continuation_status',''));
  v_ancora   timestamptz;
  v_due      timestamptz;
  v_openloop text;
  v_handoff  text := lower(coalesce(p_dados#>>'{ownership,handoff_status}',''));
  v_chave    text;
  v_lista    jsonb;
  v_min      integer;
  v_next     timestamptz;
  v_policy   text;
  v_fc       integer := greatest(coalesce(p_followup_count,0), 0);
  v_adiado   boolean := false;
begin
  select c.valor into v_cfg from intelligence.config c where c.chave = 'silence_timing_v1';
  if v_cfg is null then
    return jsonb_build_object('erro','config silence_timing_v1 ausente');
  end if;

  v_ancora := case when v_fc > 0
                   then coalesce(p_last_followup_at, public.silence_ultimo_evento(p_conversa_id))
                   else public.silence_ultimo_evento(p_conversa_id) end;

  v_compra := public.silence_compra_summit_2026(p_conversa_id);
  v_declarou := lower(coalesce(p_dados#>>'{transaction,purchase_status}','')) = 'purchased'
             or lower(coalesce(p_dados->>'purchase_status','')) = 'purchased';
  v_optout := public.summit_motivo_exclusao(p_conversa_id);
  v_openloop := nullif(btrim(coalesce(p_dados->>'open_loop','')), '');
  if lower(coalesce(v_openloop,'')) in ('none','null','n/a','nenhum') then v_openloop := null; end if;

  -- ---------------- PRECEDENCIA (secao 7 do playbook) ----------------
  if v_compra = 'purchased' or v_declarou then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','none',
      'continuation_status','stopped',
      'reason_code', case when v_compra = 'purchased' then 'purchase_confirmed_crm'
                          else 'purchase_declared' end,
      'prova_de_compra', v_compra = 'purchased',
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  if v_optout is not null then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','none',
      'continuation_status','stopped','reason_code','opt_out','motivo_opt_out', v_optout,
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  if v_acao = 'STOP' or (v_acao = '' and v_status = 'stopped') then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','none',
      'continuation_status','stopped','reason_code', coalesce(nullif(p_dados->>'reason_code',''),'stopped'),
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  if v_acao = 'DORMANT' or (v_acao = '' and v_status = 'dormant') then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','event_trigger_only',
      'continuation_status','dormant','reason_code','followup_exhausted',
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  if v_acao = 'ESCALATE' and (v_handoff in ('done','accepted','assigned','in_progress')
                              or nullif(btrim(coalesce(p_dados#>>'{ownership,human_owner}','')),'') is not null) then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','event_trigger_only',
      'continuation_status','scheduled_pause','reason_code','handoff_owned',
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  -- 3. sem open loop real: silencio nao autoriza follow-up
  if v_openloop is null then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','event_trigger_only',
      'continuation_status','silence','reason_code','no_legitimate_recontact_reason',
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  if v_ancora is null then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','event_trigger_only',
      'continuation_status','silence','reason_code','sem_ancora_temporal',
      'timing_key', null, 'anchor_at', null, 'purchase_status', v_compra);
  end if;

  -- minutos da matriz (sempre calculados: viram o passo do piso quando preciso)
  v_chave := public.silence_chave_timing(p_dados, v_fc > 0);
  if v_fc = 0 then
    v_min := (v_cfg#>>array['primeira_reavaliacao_min', v_chave])::integer;
  else
    v_lista := v_cfg#>array['apos_followup_min', v_chave];
    if v_lista is null or v_fc > jsonb_array_length(v_lista) then
      return jsonb_build_object('next_review_at', null, 'next_review_policy','event_trigger_only',
        'continuation_status','dormant','reason_code','followup_exhausted',
        'timing_key', v_chave, 'anchor_at', v_ancora, 'purchase_status', v_compra);
    end if;
    v_min := (v_lista->>(v_fc - 1))::integer;
  end if;

  -- 2. compromisso explicito prevalece sobre o timer (se ainda nao venceu)
  v_due := public.silence_ts(p_dados#>>'{commitment,due}');
  if v_due is not null and v_due > v_ancora and (p_piso is null or v_due > p_piso) then
    return jsonb_build_object('next_review_at', v_due, 'next_review_policy','commitment_due',
      'continuation_status','commitment_pending','reason_code','commitment_due',
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  -- 4. matriz deterministica
  v_next   := v_ancora + make_interval(mins => v_min);
  v_policy := 'timing_matrix';

  -- PISO: numa reavaliacao o proximo passo nunca fica no passado.
  if p_piso is not null and v_next <= p_piso then
    v_next   := p_piso + make_interval(mins => v_min);
    v_adiado := true;
  end if;

  return jsonb_build_object(
    'next_review_at',      v_next,
    'next_review_policy',  v_policy,
    'continuation_status', case when v_fc = 0 then 'silence' else 'followup_due' end,
    'reason_code',         coalesce(nullif(p_dados->>'reason_code',''), 'timing_matrix'),
    'timing_key',          v_chave,
    'timing_minutos',      v_min,
    'anchor_at',           v_ancora,
    'ancorado_no_piso',    v_adiado,
    'compromisso_vencido', (v_due is not null and (v_due <= v_ancora or (p_piso is not null and v_due <= p_piso))),
    'purchase_status',     v_compra);
end $function$
;

CREATE OR REPLACE FUNCTION public.silence_chave_timing(p_dados jsonb, p_pos_followup boolean)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  with v as (
    select lower(coalesce(p_dados->>'updated_purchase_intent',      p_dados->>'purchase_intent',      '')) as pi,
           lower(coalesce(p_dados->>'updated_conversion_risk',      p_dados->>'conversion_risk',      '')) as cr,
           lower(coalesce(p_dados->>'updated_commercial_priority',  p_dados->>'commercial_priority',  '')) as cp
  )
  select case
    -- CRITICAL = compra em andamento bloqueada ou risco imediato (secao 7 do playbook).
    -- Na 1a reavaliacao risco critico tambem entra; depois do follow-up so a prioridade.
    when v.cp = 'critical' then 'critical'
    when not p_pos_followup and v.cr = 'critical' then 'critical'
    when v.pi = 'very_high' then 'very_high'
    when v.pi = 'high'      then 'high'
    when v.pi = 'medium'    then 'medium'
    else 'low'
  end from v;
$function$
;

CREATE OR REPLACE FUNCTION public.silence_claim_pendentes(p_limite integer DEFAULT 10)
 RETURNS TABLE(conversa_id uuid, analise_conversa_id uuid, continuation_status text, next_review_at timestamp with time zone, next_review_policy text, followup_count integer, last_followup_at timestamp with time zone, ultimo_evento_em timestamp with time zone, dados jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence', 'engagement'
AS $function$
declare v_lock integer; v_cfg jsonb;
begin
  select c.valor into v_cfg from intelligence.config c where c.chave = 'silence_timing_v1';
  v_lock := coalesce((v_cfg->>'lock_minutos')::int, 10);

  return query
  with alvo as (
    select cc.conversa_id
      from intelligence.continuidade_comercial cc
     where cc.next_review_at is not null
       and cc.next_review_at <= now()
       and (cc.processing_until is null or cc.processing_until < now())
       and cc.continuation_status not in ('stopped','dormant')
     order by cc.next_review_at asc
     limit greatest(coalesce(p_limite,10), 1)
     for update skip locked
  ), travado as (
    update intelligence.continuidade_comercial c
       set processing_until = now() + make_interval(mins => v_lock)
      from alvo a
     where c.conversa_id = a.conversa_id
     returning c.*
  )
  select t.conversa_id, t.analise_conversa_id, t.continuation_status,
         t.next_review_at, t.next_review_policy, t.followup_count, t.last_followup_at,
         public.silence_ultimo_evento(t.conversa_id),
         (select ac.dados from intelligence.analise_conversa ac where ac.id = t.analise_conversa_id)
    from travado t;
end $function$
;

CREATE OR REPLACE FUNCTION public.silence_compra_summit_2026(p_conversa_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_hs        text;
  v_no_espelho boolean;
  v_anual     text;
begin
  select p.hubspot_id into v_hs
    from engagement.conversas c
    join pessoas.pessoas p on p.id = c.participante_id
   where c.id = p_conversa_id;

  if v_hs is null or btrim(v_hs) = '' then
    return 'unknown';           -- sem identidade nao da pra afirmar nada
  end if;

  -- 1) deal pago de 2026
  if exists (
    select 1
      from crm.negocio_contatos nc
      join crm.vendas_historicas_mind_summit nh on nh.hubspot_deal_id = nc.hubspot_deal_id
     where nc.contato_hubspot_id = v_hs
       and nh.status_de_pagamento = 'Pago'
       and nh.summit_year = '2026'
  ) then
    return 'purchased';
  end if;

  -- 2) espelho do contato: participacao anual marcada em 2026
  select true, e.summit__participacao_anual
    into v_no_espelho, v_anual
    from crm.contato_espelho e
   where e.hubspot_id = v_hs
   limit 1;

  if coalesce(v_anual,'') like '%2026%' then
    return 'purchased';
  end if;

  -- 3) o espelho conhece a pessoa e nao ha compra -> afirmacao legitima
  if coalesce(v_no_espelho, false) then
    return 'not_purchased';
  end if;

  return 'unknown';
end $function$
;

CREATE OR REPLACE FUNCTION public.silence_liberar_lock(p_conversa_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence'
AS $function$
  update intelligence.continuidade_comercial
     set processing_until = null, atualizado_em = now()
   where conversa_id = p_conversa_id;
$function$
;

CREATE OR REPLACE FUNCTION public.silence_montar_contexto(p_conversa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'intelligence', 'engagement', 'pessoas', 'crm'
AS $function$
declare
  v_base   jsonb;
  cc       record;
  v_dados  jsonb;
  v_ult    timestamptz;
begin
  v_base := public.analise_montar_contexto(p_conversa_id);
  select * into cc from intelligence.continuidade_comercial where conversa_id = p_conversa_id;
  select coalesce(ac.dados,'{}'::jsonb) into v_dados
    from intelligence.analise_conversa ac where ac.id = cc.analise_conversa_id;
  v_ult := public.silence_ultimo_evento(p_conversa_id);

  return jsonb_strip_nulls(v_base || jsonb_build_object(
    'continuidade', jsonb_build_object(
      'continuation_status', cc.continuation_status,
      'next_review_at',      cc.next_review_at,
      'next_review_policy',  cc.next_review_policy,
      'followup_count',      cc.followup_count,
      'last_followup_at',    cc.last_followup_at,
      'ultimo_evento_em',    v_ult,
      'silencio_horas',      round(extract(epoch from (now() - v_ult)) / 3600.0, 1),
      'agora',               now(),
      'purchase_status',     public.silence_compra_summit_2026(p_conversa_id),
      'motivo_exclusao',     public.summit_motivo_exclusao(p_conversa_id)
    ),
    'estado_comercial', jsonb_build_object(
      'buyer_state',        v_dados->>'buyer_state',
      'purchase_intent',    v_dados->>'purchase_intent',
      'conversion_risk',    v_dados->>'conversion_risk',
      'commercial_priority',v_dados->>'commercial_priority',
      'product_state',      v_dados->>'product_state',
      'primary_barrier',    v_dados->>'primary_barrier',
      'barrier_detail',     v_dados->>'barrier_detail',
      'response_target',    v_dados->>'response_target',
      'followup_anchor',    v_dados->>'followup_anchor',
      'open_loop',          v_dados->>'open_loop',
      'expected_next_event',v_dados->>'expected_next_event',
      'commitment',         v_dados->'commitment',
      'transaction',        v_dados->'transaction',
      'ownership',          v_dados->'ownership',
      'commercial_signals', v_dados->'commercial_signals',
      'selected_product_or_offer',  v_dados->>'selected_product_or_offer',
      'preferred_product_or_offer', v_dados->>'preferred_product_or_offer',
      'conversation_summary',       v_dados->>'conversation_summary'
    ),
    'ultima_fala_lead',   (select jsonb_build_object('conteudo', m.conteudo, 'em', m.criado_em)
                             from engagement.mensagens m
                            where m.conversa_id = p_conversa_id and m.papel = 'lead'
                            order by m.criado_em desc limit 1),
    'ultima_fala_agente', (select jsonb_build_object('conteudo', m.conteudo, 'em', m.criado_em)
                             from engagement.mensagens m
                            where m.conversa_id = p_conversa_id and m.papel <> 'lead'
                            order by m.criado_em desc limit 1)
  ));
end $function$
;

CREATE OR REPLACE FUNCTION public.silence_registrar_decisao(p_conversa_id uuid, p_decisao jsonb, p_followup_enviado boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence', 'engagement', 'pessoas', 'crm'
AS $function$
declare
  cc         record;
  v_analise  jsonb;
  v_dados    jsonb;
  v_dec      jsonb := coalesce(p_decisao,'{}'::jsonb);
  v_comm     jsonb;
  v_due_orig timestamptz;
  v_due_ia   timestamptz;
  v_recusado boolean := false;
  v_fc       integer;
  v_lfa      timestamptz;
  v_acao     text := upper(coalesce(p_decisao->>'action',''));
  v_calc     jsonb;
begin
  select * into cc from intelligence.continuidade_comercial where conversa_id = p_conversa_id;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'conversa_sem_continuidade');
  end if;

  select coalesce(ac.dados,'{}'::jsonb) into v_analise
    from intelligence.analise_conversa ac where ac.id = cc.analise_conversa_id;
  v_analise := coalesce(v_analise,'{}'::jsonb);

  v_comm     := coalesce(v_analise->'commitment','{}'::jsonb);
  v_due_orig := public.silence_ts(v_analise#>>'{commitment,due}');
  v_due_ia   := public.silence_ts(v_dec->>'commitment_due');

  if nullif(btrim(coalesce(v_dec->>'commitment_object','')),'') is not null then
    v_comm := v_comm || jsonb_build_object('object', v_dec->>'commitment_object');
  end if;

  -- so aceita data da reavaliacao se a conversa ja tinha data (o lead pode ter remarcado)
  if v_due_ia is not null and v_due_orig is not null then
    v_comm := v_comm || jsonb_build_object('due', to_char(v_due_ia,'YYYY-MM-DD"T"HH24:MI:SSOF'));
  elsif v_due_ia is not null then
    v_recusado := true;                       -- data inventada: nao entra no relogio
    v_comm := v_comm - 'due';
  end if;

  v_dados := v_analise || v_dec || jsonb_build_object('commitment', v_comm);
  -- commitment_due achatado da IA nao pode vazar para o calculo por outro caminho
  v_dados := v_dados - 'commitment_due';
  if not (v_dec ? 'open_loop') then
    v_dados := v_dados || jsonb_build_object('open_loop', v_analise->>'open_loop');
  end if;

  v_fc  := coalesce(cc.followup_count, 0);
  v_lfa := cc.last_followup_at;
  if p_followup_enviado then
    v_fc := v_fc + 1;
    v_lfa := now();
  end if;

  v_calc := public.silence_calcular_next_review(p_conversa_id, v_dados, v_fc, v_lfa, v_acao, now())
            || jsonb_build_object('commitment_due_recusado', v_recusado,
                                  'commitment_due_proposto_pela_ia', v_dec->>'commitment_due');

  update intelligence.continuidade_comercial set
    continuation_status = coalesce(v_calc->>'continuation_status', continuation_status),
    next_review_at      = public.silence_ts(v_calc->>'next_review_at'),
    next_review_policy  = v_calc->>'next_review_policy',
    followup_count      = v_fc,
    last_followup_at    = v_lfa,
    last_decision       = jsonb_build_object('origem','reavaliacao','em', now(),
                                             'decisao', v_dec, 'calculo', v_calc),
    processing_until    = null,
    atualizado_em       = now()
  where conversa_id = p_conversa_id;

  return jsonb_build_object('ok', true, 'action', v_acao,
                            'followup_enviado', p_followup_enviado,
                            'commitment_due_recusado', v_recusado, 'calculo', v_calc);
end $function$
;

CREATE OR REPLACE FUNCTION public.silence_sync_from_analysis(p_analise_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence', 'engagement', 'pessoas', 'crm'
AS $function$
declare
  a          record;
  v_fc       integer := 0;
  v_lfa      timestamptz;
  v_resetou  boolean := false;
  v_calc     jsonb;
begin
  select ac.id, ac.conversa_id, ac.dados, ac.funcao
    into a
    from intelligence.analise_conversa ac
   where ac.id = p_analise_id;

  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'analise_inexistente');
  end if;

  if coalesce(a.funcao,'') <> 'comercial' then
    return jsonb_build_object('ok', true, 'ignorado', 'funcao_nao_comercial');
  end if;

  select cc.followup_count, cc.last_followup_at into v_fc, v_lfa
    from intelligence.continuidade_comercial cc where cc.conversa_id = a.conversa_id;
  v_fc := coalesce(v_fc, 0);

  -- lead voltou a falar depois do ultimo follow-up -> ciclo de silencio recomeca (secao 24)
  if v_lfa is not null and exists (
    select 1 from engagement.mensagens m
     where m.conversa_id = a.conversa_id and m.papel = 'lead' and m.criado_em > v_lfa
  ) then
    v_fc := 0; v_lfa := null; v_resetou := true;
  end if;

  -- sem piso: a analise pode concluir que a revisao ja venceu (backfill / conversa antiga)
  v_calc := public.silence_calcular_next_review(a.conversa_id, a.dados, v_fc, v_lfa,
                                                null::text, null::timestamptz);

  insert into intelligence.continuidade_comercial as cc
    (conversa_id, analise_conversa_id, continuation_status, next_review_at, next_review_policy,
     followup_count, last_followup_at, last_decision, processing_until, atualizado_em)
  values (a.conversa_id, a.id,
     v_calc->>'continuation_status',
     public.silence_ts(v_calc->>'next_review_at'),
     v_calc->>'next_review_policy',
     v_fc, v_lfa,
     jsonb_build_object('origem','analise','em', now(), 'calculo', v_calc),
     null, now())
  on conflict (conversa_id) do update set
     analise_conversa_id = excluded.analise_conversa_id,
     continuation_status = excluded.continuation_status,
     next_review_at      = excluded.next_review_at,
     next_review_policy  = excluded.next_review_policy,
     followup_count      = excluded.followup_count,
     last_followup_at    = excluded.last_followup_at,
     last_decision       = excluded.last_decision,
     processing_until    = null,
     atualizado_em       = now();

  return jsonb_build_object('ok', true, 'conversa_id', a.conversa_id,
                            'reset_por_resposta', v_resetou, 'calculo', v_calc);
end $function$
;

CREATE OR REPLACE FUNCTION public.silence_ts(p_texto text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
begin
  if p_texto is null or btrim(p_texto) = '' then return null; end if;
  return p_texto::timestamptz;
exception when others then
  return null;  -- a IA nao inventa timestamp; texto nao-data simplesmente nao vale
end $function$
;

CREATE OR REPLACE FUNCTION public.silence_ultimo_evento(p_conversa_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(
    (select max(m.criado_em) from engagement.mensagens m where m.conversa_id = p_conversa_id),
    (select coalesce(c.encerrada_em, c.ultima_atividade, c.iniciada_em)
       from engagement.conversas c where c.id = p_conversa_id)
  );
$function$
;

CREATE OR REPLACE FUNCTION public.summit_contato_criar_pendentes(p_limit integer DEFAULT 50)
 RETURNS TABLE(pessoa_id uuid, telefone text, primeiro_nome text, sobrenome text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
  select distinct on (p.id) p.id, p.whatsapp,
         coalesce(nullif(trim(p.primeiro_nome),''), nullif(trim(c.nome_contato),'')),
         nullif(trim(p.sobrenome),'')
  from engagement.conversas c
  join pessoas.pessoas p on p.id = c.participante_id
  where c.agente in ('treble','treble-inbound-agent')
    and public.summit_motivo_exclusao(c.id) is not null
    and p.hubspot_id is null
    and p.whatsapp is not null
  order by p.id, c.ultima_atividade desc nulls last
  limit greatest(1, p_limit);
$function$
;

CREATE OR REPLACE FUNCTION public.summit_motivo_exclusao(p_conversa_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement'
AS $function$
  select case
    when lower(coalesce(public.treble_cta_da_conversa(p_conversa_id),'')) = 'já comprei meu ingresso'
      then 'declarou compra ("Já comprei meu ingresso") sem participacao_anual 2026'
    when lower(coalesce(public.treble_cta_da_conversa(p_conversa_id),'')) = 'descadastrar'
      then 'opt-out (CTA "Descadastrar")'
    when exists (select 1 from engagement.mensagens m
                  where m.conversa_id = p_conversa_id and m.papel = 'lead'
                    and lower(trim(coalesce(m.conteudo,''))) in ('sair','descadastrar'))
      then 'opt-out (mensagem "sair"/"descadastrar")'
    else null end;
$function$
;

CREATE OR REPLACE FUNCTION public.summit_status_confirmar(p_pares jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'crm'
AS $function$
  insert into crm.status_summit_hs (hubspot_id, valor, motivo, escrito_em)
  select x->>'contato_id', x->>'valor',
         coalesce(nullif(x->>'motivo',''), 'exclusao de disparo'), now()
  from jsonb_array_elements(p_pares) x
  where nullif(x->>'contato_id','') is not null
  on conflict (hubspot_id) do update
    set valor = excluded.valor, motivo = excluded.motivo, escrito_em = now();
$function$
;

CREATE OR REPLACE FUNCTION public.summit_status_pendentes(p_limit integer DEFAULT 100)
 RETURNS TABLE(contato_id text, valor text, motivo text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'crm'
AS $function$
  select distinct on (p.hubspot_id) p.hubspot_id, 'Não engajou'::text,
         public.summit_motivo_exclusao(c.id)
  from engagement.conversas c
  join pessoas.pessoas p            on p.id = c.participante_id and p.hubspot_id is not null
  left join crm.contato_espelho ce  on ce.hubspot_id = p.hubspot_id
  where c.agente in ('treble','treble-inbound-agent')
    and public.summit_motivo_exclusao(c.id) is not null
    and not (string_to_array(coalesce(ce.summit__participacao_anual,''), ';') @> array['2026'])
    and coalesce(ce.status_summit_2026,'') is distinct from 'Não engajou'
    and not exists (select 1 from crm.status_summit_hs s
                     where s.hubspot_id = p.hubspot_id and s.valor = 'Não engajou')
  order by p.hubspot_id, c.ultima_atividade desc nulls last
  limit greatest(1, p_limit);
$function$
;

CREATE OR REPLACE FUNCTION public.telefone_normalizar(p_tel text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare d text; ddd text; resto text;
begin
  d := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
  d := ltrim(d, '0');
  if d = '' then return null; end if;

  -- número nacional (sem DDI): 10-11 dígitos -> vira BR
  if length(d) between 10 and 11 then d := '55' || d; end if;

  -- não-BR: devolve só os dígitos, sem inventar nada
  if left(d,2) <> '55' then
    return case when length(d) between 8 and 15 then d else null end;
  end if;

  if length(d) < 12 then return null; end if;
  ddd   := substr(d,3,2);
  resto := substr(d,5);
  if ddd !~ '^[1-9][0-9]$' then return null; end if;

  -- celular sem o 9 -> insere
  if length(resto) = 8 and left(resto,1) between '6' and '9' then
    resto := '9' || resto;
  end if;

  if length(resto) not in (8,9) then return null; end if;
  return '55' || ddd || resto;
end $function$
;

CREATE OR REPLACE FUNCTION public.treble_agent_config()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'treble'
AS $function$ select coalesce(jsonb_object_agg(chave, valor), '{}'::jsonb) from treble.config $function$
;

CREATE OR REPLACE FUNCTION public.treble_agent_context(p_audience text DEFAULT 'desconhecido'::text, p_origem text DEFAULT NULL::text, p_utm jsonb DEFAULT NULL::jsonb, p_conversa text DEFAULT NULL::text, p_produto text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'summit_2026'
AS $function$
  select jsonb_build_object(
    'evento', (
      select jsonb_build_object(
        'nome', e.nome, 'dias', e.dias, 'local', e.local, 'cidade', e.cidade)
      from summit_2026.events e
      where e.ativo
      order by e.atualizado_em desc
      limit 1),
    'ofertas_vigentes', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'codigo', o.codigo, 'nome', o.nome, 'valor', o.valor,
        'condicoes_pagamento', o.condicoes_pagamento,
        'checkout_url', o.checkout_url,
        'lote_termina_em', o.encerra_em)
        order by o.valor), '[]'::jsonb)
      from summit_2026.offers o
      where o.ativo and o.publico)
  );
$function$
;

CREATE OR REPLACE FUNCTION public.treble_agent_context_base()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'summit_2026', 'ecossistema', 'engagement', 'intelligence', 'mind', 'treble'
AS $function$
select jsonb_build_object(
  'evento', (select to_jsonb(e) - 'id' from summit_2026.events e limit 1),
  'experiencias_o_que_inclui', (
    select coalesce(jsonb_agg(jsonb_build_object('titulo', k.titulo, 'texto', left(k.corpo, 1500))), '[]'::jsonb)
    from summit_2026.knowledge_documents k
    where k.tipo_conteudo = 'ingresso' and k.aprovado_treble and k.ativo
      and (k.valido_de is null or k.valido_de <= now())
      and (k.valido_ate is null or k.valido_ate > now())),
  'faq', (
    select coalesce(jsonb_agg(jsonb_build_object('titulo', k.titulo, 'texto', left(k.corpo, 1200))), '[]'::jsonb)
    from summit_2026.knowledge_documents k
    where k.tipo_conteudo = 'faq' and k.aprovado_treble and k.ativo
      and (k.valido_de is null or k.valido_de <= now())
      and (k.valido_ate is null or k.valido_ate > now())),
  'conteudo_aprovado', (
    select coalesce(jsonb_agg(jsonb_build_object('titulo', k.titulo, 'texto', left(k.corpo, 1200))), '[]'::jsonb)
    from summit_2026.knowledge_documents k
    where k.tipo_conteudo not in ('ingresso','faq') and k.aprovado_treble and k.ativo
      and (k.valido_de is null or k.valido_de <= now())
      and (k.valido_ate is null or k.valido_ate > now())),
  'visao_geral', case when (select valor from treble.config where chave='bloco_visao_geral') = 'true'
    then jsonb_build_object(
      'numeros', jsonb_build_object(
        'sessoes', (select count(*) from summit_2026.sessions),
        'palestrantes', (select count(*) from ecossistema.palestrantes_especialistas), 'dias', 2),
      'trilhas', (select coalesce(jsonb_agg(distinct t.trilha), '[]'::jsonb)
                  from summit_2026.sessions s, unnest(s.trilhas) as t(trilha)),
      'palestrantes_destaque', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'nome', d.nome, 'cargo', d.cargo, 'organizacao', d.organizacao)), '[]'::jsonb)
        from (select nome, cargo_curto as cargo, instituicao as organizacao
                from ecossistema.palestrantes_especialistas order by nome limit 12) d),
      'publico_e_dores', '[]'::jsonb)
    else '"bloco desligado"'::jsonb end,
  'ofertas_vigentes', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'codigo', o.codigo, 'nome', o.nome, 'valor', o.valor,
      'condicoes_pagamento', o.condicoes_pagamento, 'checkout_url', o.checkout_url,
      'lote_termina_em', o.encerra_em,
      'procura', o.procura, 'procura_nota', o.procura_nota)), '[]'::jsonb)
    from summit_2026.offers o where o.ativo and o.publico),
  'virada_de_lote', public.mind_virada_de_lote(),
  'proximo_lote', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'codigo', o.codigo, 'valor', o.valor, 'comeca_em', o.inicia_em)), '[]'::jsonb)
    from summit_2026.offers o
    where not o.ativo and o.inicia_em is not null and o.inicia_em > now()
      and o.inicia_em = (select min(i.inicia_em) from summit_2026.offers i
                          where i.inicia_em > now() and not (i.elegibilidade ? 'grupo'))
      and not (o.elegibilidade ? 'grupo')),
  'regras_comerciais', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'chave', r.chave, 'descricao', r.descricao, 'config', r.config)), '[]'::jsonb)
    from summit_2026.commercial_rules r where r.ativo),
  'politicas', case when (select valor from treble.config where chave='bloco_politicas') = 'true'
    then (select coalesce(jsonb_agg(jsonb_build_object('titulo', p.titulo, 'texto', p.texto)), '[]'::jsonb)
          from mind.policies p where p.ativo)
    else '"bloco desligado"'::jsonb end
)
$function$
;

CREATE OR REPLACE FUNCTION public.treble_agent_identificar(p_session_external_id text, p_email text DEFAULT NULL::text, p_nome text DEFAULT NULL::text, p_sobrenome text DEFAULT NULL::text, p_mesma_pessoa boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  v_conv engagement.conversas;
  v_res  jsonb;
  v_pessoa uuid;
begin
  select * into v_conv from engagement.conversas
   where canal='whatsapp' and session_external_id = btrim(p_session_external_id);
  if not found then
    return jsonb_build_object('pessoa_encontrada', false, 'motivo','conversa_inexistente');
  end if;

  v_res := public.mind_identidade_resolver(
    jsonb_strip_nulls(jsonb_build_object('email', p_email, 'whatsapp', v_conv.telefone)),
    coalesce(p_nome, v_conv.nome_contato), 'whatsapp', v_conv.participante_id);

  v_pessoa := coalesce(v_conv.participante_id, nullif(v_res->>'pessoa_id','')::uuid);
  if v_pessoa is not null then
    update engagement.conversas set participante_id = v_pessoa
     where id = v_conv.id and participante_id is null;
    update engagement.mensagens set participante_id = v_pessoa
     where conversa_id = v_conv.id and participante_id is null;
  end if;

  return v_res || public.mind_conversa_estado(v_conv.id) || jsonb_build_object(
    'pessoa_id',         v_pessoa,
    'pessoa_encontrada', v_pessoa is not null,
    'participante_id',   v_pessoa,
    'criou',             coalesce((v_res->>'criada')::boolean,false),
    'precisa_fundir',    (v_res->'conflito') is not null and v_res->>'conflito' <> 'null');
end $function$
;

CREATE OR REPLACE FUNCTION public.treble_agent_prompt(p_audience text DEFAULT 'desconhecido'::text)
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'agentes'
AS $function$
  select string_agg(conteudo, E'\n\n' order by ordem)
  from (
    -- identidade, dados e limites (vale sempre)
    select conteudo, 1 as ordem from agentes.prompts
     where chave in ('base','playbook_router') and ativo
    union all
    select conteudo, 2 from agentes.prompts where chave = 'tom_de_voz' and ativo
    union all
    -- motor de decisão comercial (só quando há intenção comercial)
    select conteudo, 3 from agentes.prompts
     where chave = 'sales_decision_engine' and ativo
       and coalesce(p_audience,'desconhecido') in ('b2c','b2b','desconhecido')
    union all
    -- playbook da audiência: aceita 'playbook_x' e 'playbook_summit_x'
    select conteudo, 4 from agentes.prompts
     where chave in ('playbook_' || coalesce(nullif(p_audience,''), 'desconhecido'),
                     'playbook_summit_' || coalesce(nullif(p_audience,''), 'desconhecido'))
       and ativo
    union all
    select conteudo, 5 from agentes.prompts
     where chave = 'objecoes' and ativo
       and coalesce(p_audience,'desconhecido') in ('b2c','desconhecido','b2b')
  ) partes;
$function$
;

CREATE OR REPLACE FUNCTION public.treble_agent_resposta_repetida(p_conversation_id uuid, p_mensagem text, p_janela_segundos integer DEFAULT 90)
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement'
AS $function$
  select a.conteudo
    from engagement.mensagens l
    join lateral (
      select m.conteudo
        from engagement.mensagens m
       where m.conversa_id = l.conversa_id
         and m.papel = 'agente'
         and m.criado_em >= l.criado_em
       order by m.criado_em
       limit 1
    ) a on true
   where l.conversa_id = p_conversation_id
     and l.papel = 'lead'
     and l.conteudo = p_mensagem
     and l.criado_em > now() - make_interval(secs => p_janela_segundos)
   order by l.criado_em desc
   limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.treble_agent_start(p_session_external_id text, p_contact jsonb DEFAULT '{}'::jsonb, p_origem text DEFAULT NULL::text, p_utm_token text DEFAULT NULL::text, p_mensagem jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'treble'
AS $function$
declare
  v_in    jsonb;
  v_out   jsonb;
  v_est   jsonb;
  v_conv  engagement.conversas;
begin
  if p_session_external_id is null or length(p_session_external_id) < 3 then
    raise exception using errcode='22023', message='session_external_id invalido';
  end if;

  v_in := jsonb_build_object(
    'canal','whatsapp',
    'agente','treble-inbound-agent',
    'sessao_externa', p_session_external_id,
    'nome', p_contact->>'nome',
    'identificadores', jsonb_strip_nulls(jsonb_build_object(
      'whatsapp',      coalesce(p_contact->>'whatsapp', p_contact->>'telefone'),
      'email',         p_contact->>'email',
      'telefone_hash', p_contact->>'telefone_hash')),
    'origem', jsonb_strip_nulls(jsonb_build_object(
      'origem_codigo', p_origem, 'utm_token', p_utm_token)),
    'mensagem', p_mensagem);

  v_out := public.mind_inbound(v_in);
  select * into v_conv from engagement.conversas where id = (v_out->>'conversa_id')::uuid;

  -- particularidade REAL do canal: o cliente falou => janela de 24h reaberta
  if v_conv.telefone is not null then
    perform public.treble_status_marcar(v_conv.telefone, 'aberta', now(), v_conv.session_external_id);
  end if;

  v_est := public.mind_conversa_estado(v_conv.id);

  return v_out || v_est || jsonb_build_object(
    'conversation_id',  v_conv.id,
    'pessoa_encontrada',(v_out->>'pessoa_id') is not null,
    'participante_id',  v_out->'pessoa_id',
    'needs_human',      coalesce((v_conv.variables->>'needs_human')::boolean, false));
end $function$
;

CREATE OR REPLACE FUNCTION public.treble_agent_token()
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'treble'
AS $function$ select valor from treble.config where chave = 'webhook_token' $function$
;

CREATE OR REPLACE FUNCTION public.treble_cta_da_conversa(p_conversa_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'engagement'
AS $function$
  select nullif(trim(v->>'value'),'')
  from engagement.conversas c
  cross join lateral jsonb_array_elements(
    case when jsonb_typeof(c.variables)='array' then c.variables else '[]'::jsonb end) v
  where c.id = p_conversa_id
    and v->>'key' in ('hubspot_opcao_selecionada_treble','opcao_selecionada')
  limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.treble_evento_gravar(p_payload jsonb, p_tipo text DEFAULT NULL::text, p_direcao text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text, p_ocorreu_em timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement'
AS $function$
declare v_id uuid;
begin
  insert into engagement.treble_eventos (tipo, direcao, telefone, ocorreu_em, payload)
  values (
    nullif(trim(coalesce(p_tipo,'')),''),
    nullif(trim(coalesce(p_direcao,'')),''),
    nullif(regexp_replace(coalesce(p_telefone,''), '\D', '', 'g'), ''),
    p_ocorreu_em,
    coalesce(p_payload, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.treble_find_location(p_event_slug text, p_query text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'api'
AS $function$
  select api.treble_find_location(p_event_slug, p_query);
$function$
;

CREATE OR REPLACE FUNCTION public.treble_materiais(p_audience text DEFAULT 'desconhecido'::text, p_origem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'summit', 'comum', 'engagement', 'intelligence', 'mind'
AS $function$ select public.mind_materiais_para('whatsapp_treble', p_audience, null, p_origem) $function$
;

CREATE OR REPLACE FUNCTION public.treble_momento()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'agora', to_char(now() at time zone 'America/Sao_Paulo', 'TMDay, DD/MM HH24:MI'),
    'fim_de_semana', extract(isodow from now() at time zone 'America/Sao_Paulo') in (6,7),
    'fora_do_horario_comum', (
      extract(isodow from now() at time zone 'America/Sao_Paulo') in (6,7)
      or (now() at time zone 'America/Sao_Paulo')::time < '09:00'
      or (now() at time zone 'America/Sao_Paulo')::time >= '19:00'
    ),
    'nota', 'Sinal de contexto, não regra: o time às vezes atende à noite e no fim de semana. Transfira pela necessidade, nunca pelo horário. Se transferir em momento de resposta mais lenta, seja honesto sobre isso sem prometer prazo.'
  );
$function$
;

CREATE OR REPLACE FUNCTION public.treble_origem_da_cta(p_cta text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case lower(trim(coalesce(p_cta,'')))
           when 'quero saber mais'          then 'summit_exit_popup'
           when 'garantir meu ingresso'     then 'summit_garantir_ingresso'
           when 'informação sobre o evento' then 'summit_info_evento'
           when 'informacao sobre o evento' then 'summit_info_evento'
           when 'ver condições'             then 'delegacoes_condicoes_wpp'
           when 'ver condicoes'             then 'delegacoes_condicoes_wpp'
           else null end;
$function$
;

CREATE OR REPLACE FUNCTION public.treble_poll_sincronizado(p_poll_id text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'treble'
AS $function$
  update treble.polls set sincronizado_em = now() where poll_id = p_poll_id;
$function$
;

CREATE OR REPLACE FUNCTION public.treble_sessao_backfill(p_poll_id text, p_sessions jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare s jsonb; v_tel text; v_ext text; v_ini timestamptz; v_fim timestamptz; n int := 0;
begin
  for s in select * from jsonb_array_elements(coalesce(p_sessions,'[]'::jsonb)) loop
    v_ext := s->>'id';
    if v_ext is null then continue; end if;
    v_tel := nullif(regexp_replace(
      coalesce(s#>>'{user,country_code}','') || coalesce(s#>>'{user,cellphone}',''), '\D','','g'), '');
    v_ini := nullif(s->>'created_at','')::timestamptz;
    v_fim := nullif(s->>'finished_at','')::timestamptz;

    insert into engagement.conversas
      (canal, agente, session_external_id, telefone, produto_codigo, iniciada_em, ultima_atividade, encerrada_em)
    values ('whatsapp','treble', v_ext, v_tel, p_poll_id, coalesce(v_ini, now()),
            coalesce(v_fim, v_ini, now()), v_fim)
    on conflict (canal, session_external_id) where session_external_id is not null do update
      set telefone         = coalesce(conversas.telefone, excluded.telefone),
          produto_codigo   = coalesce(conversas.produto_codigo, excluded.produto_codigo),
          encerrada_em     = coalesce(conversas.encerrada_em, excluded.encerrada_em),
          ultima_atividade = greatest(conversas.ultima_atividade, excluded.ultima_atividade);

    if v_tel is not null then
      perform public.treble_status_marcar(v_tel,
        case when v_fim is null then 'aberta' else 'fechada' end, coalesce(v_fim, v_ini), v_ext);
    end if;
    n := n + 1;
  end loop;
  return n;
end $function$
;

CREATE OR REPLACE FUNCTION public.treble_sessao_encerrada_gravar(p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  v_ext    text := p_payload#>>'{session,external_id}';
  v_tel    text := nullif(regexp_replace(
      coalesce(p_payload#>>'{user,country_code}','') || coalesce(p_payload#>>'{user,cellphone}',''),
      '\D','','g'), '');
  v_fechou timestamptz := nullif(p_payload#>>'{session,closed_at}','')::timestamptz;
  v_ultima_user timestamptz := (
      select max(nullif(x->>'created_at','')::timestamptz)
        from jsonb_array_elements(coalesce(p_payload->'messages','[]'::jsonb)) x
       where x->>'sender' = 'user');
  v_keys jsonb := coalesce(p_payload->'user_session_keys','[]'::jsonb);
  v_nome   text := (select e->>'value' from jsonb_array_elements(v_keys) e
                     where lower(e->>'key') in ('name','nome','first_name','primeiro_nome') limit 1);
  v_cta    text := (select e->>'value' from jsonb_array_elements(v_keys) e
                     where e->>'key' in ('hubspot_opcao_selecionada_treble','opcao_selecionada') limit 1);
  v_origem text := public.treble_origem_da_cta(v_cta);
  v_prod   text := (select o.produto_codigo from engagement.origens o where o.codigo = v_origem);
  v_conv uuid; v_ancora uuid;
  r record;
  v_papel text; v_tipo text; v_texto text; v_blocos jsonb; v_criado timestamptz; v_cid text;
  v_res jsonb; v_pessoa uuid;
begin
  if v_ext is null then return null; end if;

  insert into engagement.conversas
    (canal, agente, session_external_id, nome_contato, telefone, variables, encerrada_em,
     ultima_atividade, origem_codigo, produto_codigo)
  values ('whatsapp', 'treble', v_ext, nullif(trim(coalesce(v_nome,'')),''), v_tel,
          v_keys, v_fechou, coalesce(v_ultima_user, v_fechou, now()), v_origem, v_prod)
  on conflict (canal, session_external_id) where session_external_id is not null do update
    set encerrada_em     = coalesce(conversas.encerrada_em, excluded.encerrada_em),
        nome_contato     = coalesce(conversas.nome_contato, excluded.nome_contato),
        telefone         = coalesce(conversas.telefone, excluded.telefone),
        variables        = coalesce(conversas.variables, excluded.variables),
        origem_codigo    = coalesce(conversas.origem_codigo, excluded.origem_codigo),
        produto_codigo   = coalesce(conversas.produto_codigo, excluded.produto_codigo),
        ultima_atividade = greatest(conversas.ultima_atividade, excluded.ultima_atividade)
  returning id, participante_id into v_conv, v_ancora;

  for r in
    select m as msg, ord
      from jsonb_array_elements(coalesce(p_payload->'messages','[]'::jsonb)) with ordinality t(m, ord)
  loop
    v_papel  := case when r.msg->>'sender' = 'user' then 'lead' else 'agente' end;
    v_tipo   := r.msg->>'type';
    v_criado := coalesce(nullif(r.msg->>'created_at','')::timestamptz, now());
    v_cid    := 'treble-close:' || r.ord;

    if v_tipo = 'hsm' then
      v_texto  := nullif(btrim(r.msg#>>'{hsm,message}'), '');
      v_blocos := jsonb_build_object('tipo', 'hsm');
    elsif v_tipo in ('image','audio','document','video') then
      v_texto  := nullif(btrim(r.msg->v_tipo->>'caption'), '');
      v_blocos := jsonb_strip_nulls(jsonb_build_object(
                    'tipo', v_tipo, 'url', nullif(btrim(r.msg->v_tipo->>'url'), '')));
    elsif v_tipo = 'text' then
      v_texto  := nullif(btrim(r.msg#>>'{text,message}'), '');
      v_blocos := null;
    else
      -- tipo que ainda nao vimos: preserva o rotulo em vez de descartar a mensagem
      v_texto  := nullif(btrim(r.msg#>>'{text,message}'), '');
      v_blocos := jsonb_build_object('tipo', coalesce(v_tipo, 'desconhecido'));
    end if;

    -- 1) esta posicao deste close ja foi importada
    if exists (select 1 from engagement.mensagens x
                where x.conversa_id = v_conv and x.client_msg_id = v_cid) then
      continue;
    end if;

    -- 2) a mesma mensagem ja foi capturada AO VIVO pelo runtime (linha que nao veio deste close).
    --    So vale quando ha texto para comparar; mensagens deste mesmo payload sao excluidas da
    --    comparacao para que nunca suprimam umas as outras.
    if v_texto is not null and exists (
      select 1 from engagement.mensagens x
       where x.conversa_id = v_conv
         and coalesce(x.client_msg_id, '') not like 'treble-close:%'
         and x.papel = v_papel
         and x.conteudo is not distinct from v_texto
         and x.criado_em between v_criado - interval '15 minutes'
                             and v_criado + interval '15 minutes')
    then
      continue;
    end if;

    -- 2b) MESMO ARQUIVO ja capturado AO VIVO. O item de audio do close nao tem texto, entao
    --     a regra (2) nunca o alcanca. Aqui a identidade e o proprio arquivo: igualdade exata
    --     de URL, sem janela de tempo.
    if v_tipo = 'audio' and v_blocos->>'url' is not null and exists (
      select 1 from engagement.mensagens x
       where x.conversa_id = v_conv
         and coalesce(x.client_msg_id, '') not like 'treble-close:%'
         and x.papel = v_papel
         and x.blocos->>'tipo' = 'audio'
         and x.blocos->>'url'  = v_blocos->>'url')
    then
      continue;
    end if;

    insert into engagement.mensagens
      (conversa_id, participante_id, papel, conteudo, blocos, origem, client_msg_id, criado_em)
    values (v_conv, v_ancora, v_papel, v_texto, v_blocos, 'treble', v_cid, v_criado)
    on conflict (conversa_id, client_msg_id) where client_msg_id is not null do nothing;
  end loop;

  if v_tel is not null then
    perform public.treble_status_marcar(v_tel, 'x', coalesce(v_ultima_user, v_fechou), v_ext);
    v_res := public.mind_identidade_resolver(
      jsonb_build_object('whatsapp', v_tel), v_nome, 'whatsapp', v_ancora);
    v_pessoa := coalesce(v_ancora, nullif(v_res->>'pessoa_id','')::uuid);
    update engagement.conversas set participante_id = v_pessoa
     where id = v_conv and participante_id is null;
    update engagement.mensagens set participante_id = v_pessoa
     where conversa_id = v_conv and participante_id is null;
  end if;

  return v_conv;
end $function$
;

CREATE OR REPLACE FUNCTION public.treble_status_ciclo()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'treble'
AS $function$
declare v_polls jsonb;
begin
  -- todas as campanhas, as mais "atrasadas" primeiro (rodizio dentro do orcamento)
  select jsonb_agg(poll_id order by sincronizado_em asc nulls first) into v_polls from treble.polls;

  if v_polls is not null then
    perform net.http_post(
      url := 'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/treble-sessoes-sync',
      headers := jsonb_build_object('Content-Type','application/json'),
      body := jsonb_build_object('poll_ids', v_polls),
      timeout_milliseconds := 55000);
  end if;

  perform public.treble_status_recompute();

  perform net.http_post(
    url := 'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/treble-status-hubspot',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('teste', false),
    timeout_milliseconds := 55000);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.treble_status_confirmar(p_pares jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'treble'
AS $function$
declare r jsonb; n int := 0;
begin
  for r in select * from jsonb_array_elements(coalesce(p_pares,'[]'::jsonb))
  loop
    insert into treble.status_hs_leads (lead_id, valor, escrito_em)
    values (r->>'lead_id', r->>'valor', now())
    on conflict (lead_id) do update set valor = excluded.valor, escrito_em = now();
    n := n + 1;
  end loop;
  return n;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.treble_status_confirmar_contato(p_pares jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'treble'
AS $function$
declare r jsonb; n int := 0;
begin
  for r in select * from jsonb_array_elements(coalesce(p_pares,'[]'::jsonb))
  loop
    insert into treble.status_hs_contatos (contato_id, valor, escrito_em)
    values (r->>'contato_id', r->>'valor', now())
    on conflict (contato_id) do update set valor = excluded.valor, escrito_em = now();
    n := n + 1;
  end loop;
  return n;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.treble_status_marcar(p_telefone text, p_status text, p_quando timestamp with time zone DEFAULT NULL::timestamp with time zone, p_session_external_id text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'treble'
AS $function$
declare
  v_tel text := nullif(regexp_replace(coalesce(p_telefone,''), '\D', '', 'g'), '');
  v_m   timestamptz := coalesce(p_quando, now());
  v_atual timestamptz;
  v_status text;
begin
  if v_tel is null then return; end if;
  if length(v_tel) between 10 and 11 then v_tel := '55' || v_tel; end if;  -- BR sem DDI
  select momento into v_atual from treble.status_da_conversa where telefone = v_tel;
  if v_atual is not null and v_m < v_atual then return; end if;
  v_status := case when v_m > now() - interval '24 hours' then 'aberta' else 'fechada' end;
  insert into treble.status_da_conversa (telefone, status, momento, aberta_em, fechada_em, session_external_id)
  values (v_tel, v_status, v_m,
          case when v_status='aberta'  then v_m end,
          case when v_status='fechada' then v_m end,
          p_session_external_id)
  on conflict (telefone) do update set
    status              = v_status,
    momento             = v_m,
    aberta_em           = case when v_status='aberta'  then v_m else status_da_conversa.aberta_em end,
    fechada_em          = case when v_status='fechada' then v_m else status_da_conversa.fechada_em end,
    session_external_id = coalesce(excluded.session_external_id, status_da_conversa.session_external_id),
    atualizado_em       = now();
end;
$function$
;

CREATE OR REPLACE FUNCTION public.treble_status_pendentes(p_limit integer DEFAULT 100)
 RETURNS TABLE(lead_id text, valor text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'treble', 'crm'
AS $function$
  select distinct on (l.hubspot_lead_id)
    l.hubspot_lead_id,
    case when s.status='aberta' then 'conversa_aberta' else 'conversa_fechada' end
  from treble.status_da_conversa s
  join crm.contato_espelho c
    on right(regexp_replace(coalesce(c.hs_whatsapp_phone_number, c.phone),'\D','','g'),10) = right(s.telefone,10)
  join crm.pipeline_leads_inbound l on l.hs_primary_contact_id = c.hubspot_id
  left join treble.status_hs_leads h on h.lead_id = l.hubspot_lead_id
  where h.valor is distinct from (case when s.status='aberta' then 'conversa_aberta' else 'conversa_fechada' end)
  order by l.hubspot_lead_id, s.momento desc nulls last
  limit p_limit;
$function$
;

CREATE OR REPLACE FUNCTION public.treble_status_pendentes_contato(p_limit integer DEFAULT 100)
 RETURNS TABLE(contato_id text, valor text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'treble', 'crm'
AS $function$
  select distinct on (c.hubspot_id)
    c.hubspot_id,
    case when s.status='aberta' then 'treble_aberta' else 'treble_fechada' end
  from treble.status_da_conversa s
  join crm.contato_espelho c
    on right(regexp_replace(coalesce(c.hs_whatsapp_phone_number, c.phone),'\D','','g'),10) = right(s.telefone,10)
  left join treble.status_hs_contatos h on h.contato_id = c.hubspot_id
  where c.hubspot_id is not null
    and h.valor is distinct from (case when s.status='aberta' then 'treble_aberta' else 'treble_fechada' end)
  order by c.hubspot_id, s.momento desc nulls last
  limit p_limit;
$function$
;

CREATE OR REPLACE FUNCTION public.treble_status_recompute()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'treble'
AS $function$
declare n integer;
begin
  with novo as (
    select telefone, momento,
           case when momento > now() - interval '24 hours' then 'aberta' else 'fechada' end as st
    from treble.status_da_conversa
  )
  update treble.status_da_conversa s
    set status        = novo.st,
        fechada_em    = case when novo.st='fechada' and s.fechada_em is null then s.momento else s.fechada_em end,
        atualizado_em = now()
  from novo
  where novo.telefone = s.telefone and s.status is distinct from novo.st;
  get diagnostics n = row_count;
  return n;
end;
$function$
;

CREATE TABLE agentes.kit_blocos (
  rota text NOT NULL,
  bloco text NOT NULL,
  provider text NOT NULL,
  secao text NOT NULL,
  obrigatorio boolean DEFAULT false NOT NULL,
  ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE agentes.prompts (
  chave text NOT NULL,
  titulo text NOT NULL,
  conteudo text NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  versao integer DEFAULT 1 NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  produto_codigo text
);

CREATE TABLE catalogo.produtos (
  codigo text NOT NULL,
  nome text NOT NULL,
  tipo text DEFAULT 'evento'::text NOT NULL,
  vertical text,
  descricao_curta text,
  vende boolean DEFAULT true NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  comeca_em date,
  encerra_em date,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  schema_dados text,
  descricao text,
  periodo text,
  pipelines_hubspot text[]
);

CREATE TABLE concierge.ciclo_estado (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  objetivo_id uuid,
  etapa text DEFAULT 'entender'::text NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE concierge.config (
  chave text NOT NULL,
  valor jsonb NOT NULL,
  descricao text,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_por text
);

CREATE TABLE concierge.config_auditoria (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  tabela text NOT NULL,
  registro_id text,
  acao text NOT NULL,
  antes jsonb,
  depois jsonb,
  autor text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE concierge.config_revisao (
  id integer DEFAULT 1 NOT NULL,
  revisao bigint DEFAULT 1 NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE concierge.feature_flags (
  chave text NOT NULL,
  ativo boolean DEFAULT false NOT NULL,
  publico jsonb DEFAULT '{}'::jsonb NOT NULL,
  descricao text
);

CREATE TABLE concierge.ferramenta_chamadas (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  mensagem_id uuid,
  participante_id uuid,
  ferramenta text NOT NULL,
  entrada jsonb,
  saida jsonb,
  status text NOT NULL,
  http_status integer,
  latencia_ms integer,
  erro text,
  idempotency_key text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE concierge.ferramentas (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  nome text NOT NULL,
  descricao text NOT NULL,
  json_schema jsonb NOT NULL,
  tipo_exec text NOT NULL,
  destino text,
  timeout_ms integer DEFAULT 6000 NOT NULL,
  retries integer DEFAULT 1 NOT NULL,
  escrita boolean DEFAULT false NOT NULL,
  requer_confirmacao boolean DEFAULT false NOT NULL,
  trilhas text[] DEFAULT '{}'::text[] NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  versao integer DEFAULT 1 NOT NULL
);

CREATE TABLE concierge.integracao_logs (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid,
  integracao text NOT NULL,
  metodo text,
  endpoint text,
  payload jsonb,
  resposta jsonb,
  http_status integer,
  latencia_ms integer,
  erro text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE concierge.proativo_fila (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  regra_id uuid NOT NULL,
  agendado_para timestamp with time zone NOT NULL,
  estado text DEFAULT 'agendado'::text NOT NULL,
  motivo text,
  canal text DEFAULT 'app'::text NOT NULL,
  payload jsonb DEFAULT '{}'::jsonb NOT NULL,
  chave_dedupe text,
  enviado_em timestamp with time zone,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE concierge.prompts (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  nome text NOT NULL,
  versao integer NOT NULL,
  conteudo text NOT NULL,
  ativo boolean DEFAULT false NOT NULL,
  notas text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  criado_por text
);

CREATE TABLE concierge.regras_proativas (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  nome text NOT NULL,
  gatilho text NOT NULL,
  condicao jsonb DEFAULT '{}'::jsonb NOT NULL,
  template_chave text NOT NULL,
  antecedencia_min integer,
  publico jsonb DEFAULT '{}'::jsonb NOT NULL,
  canal text DEFAULT 'app'::text NOT NULL,
  prioridade integer DEFAULT 5 NOT NULL,
  cooldown_horas integer DEFAULT 6 NOT NULL,
  limite_dia integer DEFAULT 2 NOT NULL,
  janela_silenciosa jsonb DEFAULT '{}'::jsonb NOT NULL,
  ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE concierge.templates (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  chave text NOT NULL,
  idioma text DEFAULT 'pt-BR'::text NOT NULL,
  canal text DEFAULT 'app'::text NOT NULL,
  texto text NOT NULL,
  variaveis text[] DEFAULT '{}'::text[] NOT NULL,
  ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE concierge.tutorial_passos (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  chave text NOT NULL,
  titulo text NOT NULL,
  tela text NOT NULL,
  alvo text NOT NULL,
  onde text NOT NULL,
  resumo text NOT NULL,
  ordem integer DEFAULT 0 NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  aviso_chave text
);

CREATE TABLE credenciamento_summit_2026.participantes (
  id uuid NOT NULL,
  name text,
  email text,
  cellphone text,
  telefone_norm text,
  cpf text,
  ticket_type text,
  ticket_name text,
  ticket_origin text,
  sponsor_company text,
  invoice_or_sale_number text,
  ticket_number text,
  batch text,
  buyer_name text,
  buyer_email text,
  buyer_company text,
  buyer_cnpj text,
  buyer_cpf text,
  uuid text,
  status text,
  revogado_em timestamp with time zone,
  motivo_revogacao text,
  criado_em timestamp with time zone,
  atualizado_em timestamp with time zone,
  yazo_sync_status text,
  yazo_sync_error text,
  yazo_last_synced_at timestamp with time zone,
  yazo_user_id bigint,
  yazo_payload_hash text,
  external_id text,
  credenciamento_sync_status text,
  credenciamento_sync_error text,
  credenciamento_last_synced_at timestamp with time zone,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE credenciamento_summit_2026.yazo_envio_fila (
  id uuid NOT NULL,
  participant_id uuid,
  req_id bigint,
  operacao text,
  payload jsonb,
  criado_em timestamp with time zone,
  processado_em timestamp with time zone,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE credenciamento_summit_2026.yazo_espelho (
  yazo_id bigint NOT NULL,
  name text,
  email text,
  external_id text,
  attributes jsonb,
  registration_completed boolean,
  access_type text,
  yazo_updated_at timestamp with time zone,
  visto_em timestamp with time zone,
  sumiu_em timestamp with time zone,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE credenciamento_summit_2026.yazo_sync_state (
  id integer NOT NULL,
  pendentes jsonb,
  ultimo_fire timestamp with time zone,
  ultimo_load timestamp with time zone,
  ultimo_resultado jsonb,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE crm.acessos (
  id bigint DEFAULT nextval('crm.acessos_id_seq'::regclass) NOT NULL,
  funcao text NOT NULL,
  pessoa_id uuid,
  agente text NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE crm.consents (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  finalidade text NOT NULL,
  concedido boolean NOT NULL,
  politica_chave text NOT NULL,
  politica_versao integer NOT NULL,
  texto_exibido text NOT NULL,
  origem text NOT NULL,
  mensagem_id uuid,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  revogado_em timestamp with time zone
);

CREATE TABLE crm.contato_espelho (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  hubspot_id text NOT NULL,
  pessoa_id uuid,
  firstname text,
  lastname text,
  email text,
  phone text,
  hs_whatsapp_phone_number text,
  company text,
  jobtitle text,
  hs_linkedin_url text,
  hs_email_domain text,
  lifecyclestage text,
  hs_lead_status text,
  hubspot_owner_id text,
  lead_icp text,
  icp text,
  lead_tier text,
  produto_de_interesse text,
  intent_signals text,
  motivo_do_lead__perdido text,
  utm_campaign text,
  utm_source text,
  utm_medium text,
  utm_content text,
  utm_term text,
  msclkid text,
  li_fat_id text,
  first_conversion_date timestamp with time zone,
  first_conversion_event_name text,
  hs_analytics_source text,
  hs_analytics_source_data_1 text,
  hs_analytics_source_data_2 text,
  hs_latest_source text,
  hs_latest_source_data_1 text,
  hs_latest_source_data_2 text,
  hs_latest_source_timestamp timestamp with time zone,
  hs_analytics_first_referrer text,
  hs_analytics_first_url text,
  hs_analytics_first_timestamp timestamp with time zone,
  hs_analytics_first_visit_timestamp timestamp with time zone,
  hs_analytics_first_touch_converting_campaign text,
  hs_analytics_last_referrer text,
  hs_analytics_last_url text,
  hs_analytics_last_timestamp timestamp with time zone,
  hs_analytics_last_visit_timestamp timestamp with time zone,
  hs_analytics_last_touch_converting_campaign text,
  hs_analytics_average_page_views numeric,
  hs_analytics_num_page_views numeric,
  hs_analytics_num_visits numeric,
  hs_analytics_num_event_completions numeric,
  hs_analytics_revenue numeric,
  status_summit_2026 text,
  summit__categoria_do_ingresso text,
  summit__categoria_2025 text,
  summit__categoria_2026 text,
  summit__categoria_do_ingresso_2027 text,
  summit__tipo_entrada_2025 text,
  summit__tipo_entrada_2026 text,
  tipo_de_entrada text,
  summit_papel_2025 text,
  summit__papel_2026 text,
  summit__participacao_anual text,
  summit__cortesia_anos text,
  summit__patrocinio_anos text,
  participou_de_mais_de_um_summit text,
  total_de_summits_participados numeric,
  ingressos_comprados__2023 numeric,
  ingressos_comprados__2024 numeric,
  ingressos_comprados__2025 numeric,
  ingressos_comprados__2026 numeric,
  total_de_ingressos_comprados_lifetime numeric,
  comprou_ingressos_adicionais text,
  formacao__produtos_comprados text,
  total_de_formacoes_no_instituto numeric,
  concluiu_as_3_formacoes text,
  projeto_integrador_concluido text,
  formacao_1__status text,
  formacao_1__progresso numeric,
  formacao_1__ultimo_acesso date,
  formacao_1__enps numeric,
  formacao_2__status text,
  formacao_2__progresso__clonado numeric,
  formacao_2__ultimo_acesso date,
  formacao_2__enps numeric,
  formacao_3__status text,
  formacao_3__progresso numeric,
  formacao_3__ultimo_acesso date,
  formacao_3__enps numeric,
  certificacao_lideranca_positiva_comprada text,
  certificacao_lideranca_positiva_elegivel text,
  certificacao_avancada__progresso numeric,
  certificado_lideranca_positiva__enps numeric,
  num_associated_deals numeric,
  total_revenue numeric,
  recent_deal_amount numeric,
  recent_deal_close_date timestamp with time zone,
  first_deal_created_date timestamp with time zone,
  closedate timestamp with time zone,
  days_to_close numeric,
  hs_buying_role text,
  notes_last_contacted timestamp with time zone,
  notes_next_activity_date timestamp with time zone,
  notes_last_updated timestamp with time zone,
  num_contacted_notes numeric,
  num_notes numeric,
  message text,
  hs_last_sales_activity_timestamp timestamp with time zone,
  hs_sales_email_last_opened timestamp with time zone,
  hs_sales_email_last_clicked timestamp with time zone,
  hs_sales_email_last_replied timestamp with time zone,
  hs_sequences_is_enrolled boolean,
  engagements_last_meeting_booked timestamp with time zone,
  engagements_last_meeting_booked_campaign text,
  engagements_last_meeting_booked_medium text,
  engagements_last_meeting_booked_source text,
  hs_feedback_last_nps_rating text,
  hs_feedback_last_nps_follow_up text,
  hs_feedback_last_ces_survey_rating numeric,
  hs_feedback_last_ces_survey_follow_up text,
  hs_feedback_last_ces_survey_date timestamp with time zone,
  hs_feedback_last_survey_date timestamp with time zone,
  hs_content_membership_status text,
  hs_content_membership_notes text,
  hs_emailconfirmationstatus text,
  hs_email_bad_address boolean,
  hs_email_optout boolean,
  hs_email_quarantined boolean,
  hs_email_quarantined_reason text,
  hs_email_customer_quarantined_reason text,
  hs_quarantined_emails text,
  hs_email_hard_bounce_reason_enum text,
  hs_legal_basis text,
  hs_email_optout_1701138329 text,
  hs_email_optout_1701138330 text,
  hs_email_optout_1702074925 text,
  hs_email_optout_3137279076 text,
  hs_email_type text,
  hs_email_delivered numeric,
  hs_email_bounce numeric,
  hs_email_open numeric,
  hs_email_click numeric,
  hs_email_replied numeric,
  hs_email_sends_since_last_engagement numeric,
  hs_email_first_send_date timestamp with time zone,
  hs_email_first_open_date timestamp with time zone,
  hs_email_first_click_date timestamp with time zone,
  hs_email_first_reply_date timestamp with time zone,
  hs_email_last_send_date timestamp with time zone,
  hs_email_last_open_date timestamp with time zone,
  hs_email_last_click_date timestamp with time zone,
  hs_email_last_reply_date timestamp with time zone,
  hs_email_last_email_name text,
  propriedades jsonb DEFAULT '{}'::jsonb NOT NULL,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  icp_confianca numeric,
  origem_do_lead text,
  etapa_do_lead__atualizar text
);

CREATE TABLE crm.empenho_summit_2026 (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  hubspot_deal_id text NOT NULL,
  pessoa_id uuid,
  produto_codigo text,
  dealname text,
  amount numeric,
  dealstage text,
  hubspot_owner_id text,
  pipeline text,
  hs_is_closed boolean,
  hs_is_closed_lost boolean,
  hs_deal_stage_probability numeric,
  hs_forecast_amount numeric,
  quantidade_ingressos numeric,
  produto text,
  temperatura text,
  lead_b2c_ou_b2b text,
  origem_do_lead text,
  createdate timestamp with time zone,
  hs_v2_date_entered_current_stage timestamp with time zone,
  hubspot_owner_assigneddate timestamp with time zone,
  notes_last_updated timestamp with time zone,
  num_notes numeric,
  num_associated_contacts numeric,
  hs_updated_by_user_id numeric,
  hs_lastmodifieddate timestamp with time zone,
  propriedades jsonb DEFAULT '{}'::jsonb NOT NULL,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE crm.leads_capturados (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  firstname text,
  lastname text,
  email text,
  phone text,
  company text,
  perfil_d_cliente text,
  botao_selecionado_no_site text,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_term text,
  utm_content text,
  fbclid text,
  gclid text,
  msclkid text,
  li_fat_id text,
  estado text DEFAULT 'pendente'::text NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  enviado_em timestamp with time zone
);

CREATE TABLE crm.mapa_produtos (
  propriedade text NOT NULL,
  valor_origem text NOT NULL,
  produto_codigo text NOT NULL
);

CREATE TABLE crm.pessoa_nps (
  pessoa_id uuid NOT NULL,
  produto_codigo text NOT NULL,
  nota smallint,
  comentario text,
  respondido_em timestamp with time zone,
  fonte text
);

CREATE TABLE crm.pessoa_produtos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  pessoa_id uuid NOT NULL,
  produto_codigo text NOT NULL,
  categoria text,
  tipo_entrada text,
  papel text,
  quantidade integer,
  sincronizado_em timestamp with time zone,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE crm.pessoas_interno (
  pessoa_id uuid NOT NULL,
  origem_primeira text,
  origem_ultima text,
  primeira_url text,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_content text,
  utm_term text,
  dono_id text,
  dono_nome text,
  status_lead text,
  negocios_associados integer,
  ultimo_contato_em timestamp with time zone,
  perfil_cliente text,
  descadastrado_email boolean DEFAULT false NOT NULL,
  sincronizado_em timestamp with time zone,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE crm.pipeline_de_vendas_summit (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  hubspot_deal_id text NOT NULL,
  pessoa_id uuid,
  produto_codigo text,
  dealname text,
  amount numeric,
  dealstage text,
  hubspot_owner_id text,
  pipeline text,
  hs_is_closed boolean,
  hs_is_closed_lost boolean,
  hs_deal_stage_probability numeric,
  hs_forecast_amount numeric,
  quantidade_ingressos numeric,
  produto text,
  temperatura text,
  lead_b2c_ou_b2b text,
  origem_do_lead text,
  createdate timestamp with time zone,
  hs_v2_date_entered_current_stage timestamp with time zone,
  hubspot_owner_assigneddate timestamp with time zone,
  notes_last_updated timestamp with time zone,
  num_notes numeric,
  num_associated_contacts numeric,
  hs_updated_by_user_id numeric,
  hs_lastmodifieddate timestamp with time zone,
  propriedades jsonb DEFAULT '{}'::jsonb NOT NULL,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE crm.pipeline_leads_inbound (
  hubspot_lead_id text NOT NULL,
  pessoa_id uuid,
  hs_lead_name text,
  hs_pipeline text,
  hs_pipeline_stage text,
  hs_lead_label text,
  hs_lead_type text,
  hs_lead_source text,
  hs_primary_contact_id text,
  hs_primary_company_id text,
  hs_associated_company_name text,
  nome_da_empresa text,
  hubspot_owner_id text,
  hs_lead_associated_deals_count numeric,
  hs_lead_pipeline_value numeric,
  hs_lead_closed_won_deals_amount numeric,
  motivo_de_lead_perdido text,
  hs_v2_date_entered_current_stage timestamp with time zone,
  hs_createdate timestamp with time zone,
  hs_lastmodifieddate timestamp with time zone,
  propriedades jsonb,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL,
  hs_lead_disqualification_reason text,
  hs_lead_disqualification_note text
);

CREATE TABLE crm.status_summit_hs (
  hubspot_id text NOT NULL,
  valor text NOT NULL,
  motivo text,
  escrito_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE crm.sync_estado (
  fonte text NOT NULL,
  marca_dagua timestamp with time zone,
  iniciado_em timestamp with time zone,
  concluido_em timestamp with time zone,
  status text DEFAULT 'ocioso'::text NOT NULL,
  registros_lidos integer DEFAULT 0 NOT NULL,
  registros_gravados integer DEFAULT 0 NOT NULL,
  ignorados jsonb DEFAULT '[]'::jsonb NOT NULL,
  erro text,
  tabela_destino text,
  chave_destino text,
  cursor text,
  carga_completa_em timestamp with time zone,
  pipeline_id text,
  pipeline_nome text
);

CREATE TABLE crm.vendas_historicas_mind_summit (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  hubspot_deal_id text NOT NULL,
  pessoa_id uuid,
  produto_codigo text,
  dealname text,
  produto text,
  summit_year text,
  summit_categoria text,
  summit_lote text,
  quantidade_ingressos numeric,
  tipo_de_acesso text,
  tipo_de_venda text,
  modalidade_comercial text,
  amount_in_home_currency numeric,
  valor_com_juros numeric,
  valor_do_desconto numeric,
  cupom_utilizado text,
  numero_parcelas numeric,
  metodo_pagamento text,
  bandeira_cartao text,
  status_de_pagamento text,
  data_da_compra date,
  data_do_pagamento date,
  houve_reembolso text,
  valor_reembolsado numeric,
  data_reembolso date,
  houve_upgrade text,
  pipeline text,
  hs_is_closed boolean,
  hs_closed_won_count numeric,
  hs_is_closed_count numeric,
  hs_deal_stage_probability numeric,
  num_associated_contacts numeric,
  id_da_compra text,
  mind_deal_id text,
  eduzz_product_id text,
  hs_analytics_source text,
  hs_analytics_source_data_1 text,
  hs_analytics_source_data_2 text,
  hs_analytics_latest_source text,
  hs_analytics_latest_source_data_1 text,
  hs_analytics_latest_source_data_2 text,
  hs_analytics_latest_source_timestamp timestamp with time zone,
  hs_lastmodifieddate timestamp with time zone,
  propriedades jsonb DEFAULT '{}'::jsonb NOT NULL,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  situacao text
);

CREATE TABLE dash.knowledge_chunks (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  doc_id uuid NOT NULL,
  ordem integer NOT NULL,
  texto text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  embedding vector(1536),
  tsv tsvector GENERATED ALWAYS AS (to_tsvector('portuguese'::regconfig, texto)) STORED,
  stale boolean DEFAULT true NOT NULL,
  embedado_em timestamp with time zone,
  modelo_embedding text,
  indice text DEFAULT 'principal'::text NOT NULL
);

CREATE TABLE dash.knowledge_documents (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  fonte_id uuid NOT NULL,
  titulo text NOT NULL,
  corpo text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  hash text NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  tipo_conteudo text,
  problema text,
  resultado_desejado text,
  autor text,
  url text,
  ativo boolean DEFAULT true NOT NULL,
  agents text[] DEFAULT '{}'::text[] NOT NULL,
  atualizado_em_fonte timestamp with time zone,
  aprovado_treble boolean DEFAULT false NOT NULL,
  produto_codigo text,
  event_id uuid,
  valido_de timestamp with time zone,
  valido_ate timestamp with time zone,
  cluster text NOT NULL,
  audiencia text DEFAULT 'publico'::text NOT NULL
);

CREATE TABLE ecossistema.palestrantes_especialistas (
  id bigint GENERATED ALWAYS AS IDENTITY (SEQUENCE NAME ecossistema.palestrantes_especialistas_id_seq START WITH 1 INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 NO CYCLE),
  nome text NOT NULL,
  cargo_curto text,
  instituicao text,
  quem_e text,
  formacao_e_posicao text,
  principais_contribuicoes text,
  conceitos_chave_explicados text,
  por_que_o_conteudo_e_importante text,
  o_que_posso_esperar_ouvir_e_aprender text,
  dores_e_problemas_que_ajuda_a_compreender text,
  relevancia_para_os_icps_do_mind text,
  principais_livros text,
  principais_papers text,
  limites_e_cuidados_cientificos text,
  fontes_gerais text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  slug text,
  aliases text
);

CREATE TABLE eduzz.hubspot_stage_config (
  hubspot_pipeline_id text NOT NULL,
  evento_eduzz text NOT NULL,
  dealstage_id text,
  dealstage_label text,
  updated_at timestamp with time zone,
  updated_by uuid,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE eduzz.ingressos (
  uuid text NOT NULL,
  event_id text,
  evento_titulo text,
  n_ingresso text,
  participante text,
  cpf_cnpj text,
  telefone text,
  telefone_norm text,
  email text,
  cod_participante text,
  cod_comprador text,
  nome_comprador text,
  email_comprador text,
  documento_comprador text,
  fatura text,
  valor_da_venda text,
  valor_do_item text,
  cupom text,
  valor_do_cupom text,
  lote text,
  nome_do_lote text,
  descricao text,
  status text,
  check_in text,
  data_de_pagamento text,
  marcadores text,
  origem_criado_em timestamp with time zone,
  origem_atualizado_em timestamp with time zone,
  sumiu_do_blinket_em timestamp with time zone,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE eduzz.produto_catalogo (
  id uuid NOT NULL,
  eduzz_product_id text,
  tipo_de_produto text,
  produto_nome_interno text,
  summit_year integer,
  summit_categoria text,
  summit_lote text,
  modalidade_comercial text,
  tipo_de_acesso text,
  motivo_concessao text,
  origem_do_acesso text,
  houve_upgrade boolean,
  categoria_anterior text,
  elemento_adicional_oferta text,
  mapped_at timestamp with time zone,
  mapped_by uuid,
  updated_at timestamp with time zone,
  tipo_de_venda text,
  institute_tipo_produto text,
  institute_nome_produto text,
  institute_turma text,
  is_combo boolean,
  hubspot_pipeline_id text,
  preco_unitario numeric(10,2),
  liberado_para_funil boolean,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE eduzz.produtos (
  eduzz_product_id text NOT NULL,
  name text,
  description text,
  producer_id text,
  type text,
  status text,
  payment_type text,
  price_value numeric(12,2),
  payment_currency text,
  author text,
  image_url text,
  eduzz_created_at timestamp with time zone,
  eduzz_updated_at timestamp with time zone,
  is_variacao boolean,
  last_synced_at timestamp with time zone,
  arquivado boolean,
  arquivado_em timestamp with time zone,
  arquivado_por uuid,
  arquivado_motivo text,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE eduzz.vendas (
  linha_origem integer NOT NULL,
  fatura text,
  status text,
  metodo_de_pagamento text,
  forma_de_pagamento text,
  n_parcelas text,
  moeda text,
  contrato text,
  parcelamento_sem_limites text,
  data_de_criacao text,
  data_de_vencimento text,
  data_de_pagamento text,
  data_de_credito text,
  data_de_solicitacao_de_reembolso text,
  data_de_reembolso text,
  tipo_de_reembolso text,
  sku text,
  id_do_produto text,
  produto text,
  quantidade text,
  cupom text,
  valor_do_cupom text,
  valor_inicial_da_venda text,
  valor_total_da_venda text,
  valor_faturado_documento_fiscal text,
  valor_inicial_do_item text,
  valor_total_do_item text,
  valor_reembolsado text,
  valor_de_frete text,
  liquidacao_do_parcelamento text,
  taxa_eduzz text,
  taxa_alumy text,
  outros text,
  ganho_liquido text,
  tipo_parceiro text,
  parceiro text,
  recebeu_doc_fiscal text,
  cliente_nome text,
  cliente_email text,
  cliente_fones text,
  cliente_telefone_norm text,
  cliente_tipo_documento text,
  cliente_documento text,
  endereco text,
  numero text,
  complemento text,
  bairro text,
  cep text,
  cidade text,
  ibge text,
  uf text,
  utm_source text,
  utm_campaign text,
  utm_medium text,
  utm_content text,
  utm_term text,
  url_boleto text,
  nome_da_oferta text,
  produto_mapeado text,
  modalidade_venda_mapeada text,
  lote_mapeado text,
  origem_importado_em timestamp with time zone,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE engagement.agent_sessions (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  dispositivo_id uuid NOT NULL,
  participante_id uuid,
  token_hash text NOT NULL,
  origem_identidade text NOT NULL,
  confianca text DEFAULT 'media'::text NOT NULL,
  criada_em timestamp with time zone DEFAULT now() NOT NULL,
  ultima_atividade timestamp with time zone DEFAULT now() NOT NULL,
  expira_em timestamp with time zone NOT NULL,
  auth_user_id uuid
);

CREATE TABLE engagement.agente_eventos (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid,
  conversa_id uuid,
  tipo text NOT NULL,
  intencao text,
  dados jsonb DEFAULT '{}'::jsonb NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE engagement.avaliacao_execucoes (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  avaliacao_id uuid NOT NULL,
  provedor text NOT NULL,
  modelo text NOT NULL,
  resposta text,
  passou boolean,
  notas text,
  custo_usd numeric(10,6),
  latencia_ms integer,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE engagement.avaliacoes (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  caso text NOT NULL,
  categoria text NOT NULL,
  pergunta text NOT NULL,
  contexto jsonb DEFAULT '{}'::jsonb NOT NULL,
  espera jsonb DEFAULT '{}'::jsonb NOT NULL,
  ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE engagement.contatos (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  de uuid NOT NULL,
  para uuid NOT NULL,
  estado text DEFAULT 'pendente'::text NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  respondido_em timestamp with time zone
);

CREATE TABLE engagement.conversas (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid,
  dispositivo_id uuid,
  canal text DEFAULT 'app'::text NOT NULL,
  iniciada_em timestamp with time zone DEFAULT now() NOT NULL,
  ultima_atividade timestamp with time zone DEFAULT now() NOT NULL,
  encerrada_em timestamp with time zone,
  agente text,
  session_external_id text,
  nome_contato text,
  telefone text,
  telefone_hash text,
  origem_codigo text,
  utm_token text,
  utm jsonb,
  produto_codigo text,
  audience text,
  stage text,
  variables jsonb
);

CREATE TABLE engagement.data_requests (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  tipo text NOT NULL,
  detalhe text,
  estado text DEFAULT 'aberta'::text NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atendido_em timestamp with time zone,
  observacao text
);

CREATE TABLE engagement.dispositivos (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  chave text NOT NULL,
  user_agent text,
  primeiro_acesso timestamp with time zone DEFAULT now() NOT NULL,
  ultimo_acesso timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE engagement.evento_feedback (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid,
  categoria text NOT NULL,
  sentimento text NOT NULL,
  severidade integer DEFAULT 1 NOT NULL,
  comentario text,
  local text,
  mensagem_id uuid,
  tratado boolean DEFAULT false NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE engagement.feedbacks (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid,
  tipo text NOT NULL,
  valor text,
  contexto jsonb DEFAULT '{}'::jsonb NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE engagement.identidade_fusoes (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  participante_origem uuid,
  motivo text NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  status text DEFAULT 'pendente'::text NOT NULL,
  identificador jsonb,
  resolvido_em timestamp with time zone,
  tipo text DEFAULT 'conflito_identidade'::text NOT NULL
);

CREATE TABLE engagement.identidades (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  pessoa_id uuid NOT NULL,
  canal text NOT NULL,
  identificador text NOT NULL,
  verificado boolean DEFAULT false NOT NULL,
  confianca text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE engagement.jornada_eventos (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  sessao_id uuid NOT NULL,
  tipo text NOT NULL,
  origem text NOT NULL,
  dados jsonb DEFAULT '{}'::jsonb NOT NULL,
  mensagem_id uuid,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE engagement.jornada_sessao (
  participante_id uuid NOT NULL,
  sessao_id uuid NOT NULL,
  intencao text,
  intencao_forca text,
  origem_intencao text,
  planejou boolean DEFAULT false NOT NULL,
  compareceu boolean,
  fonte_presenca text,
  confianca_presenca text,
  motivo_ausencia text,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE engagement.mensagens (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  conversa_id uuid NOT NULL,
  participante_id uuid,
  papel text NOT NULL,
  conteudo text,
  blocos jsonb,
  client_msg_id text,
  origem text DEFAULT 'conversa'::text NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE engagement.nps (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  nota integer NOT NULL,
  comentario text,
  retrato jsonb DEFAULT '{}'::jsonb NOT NULL,
  conversa_id uuid,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  event_id uuid
);

CREATE TABLE engagement.origens (
  codigo text NOT NULL,
  site text NOT NULL,
  botao_rotulo text,
  descricao text,
  mensagem_abertura text,
  hubspot_campo text,
  hubspot_valor text,
  audiencia_sugerida text,
  ativo boolean DEFAULT true NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  hubspot jsonb,
  mensagem_encerramento text,
  mensagem_descadastro text,
  produto_codigo text
);

CREATE TABLE engagement.pessoa_perfil (
  pessoa_id uuid NOT NULL,
  idioma text,
  anonimo boolean DEFAULT false NOT NULL
);

CREATE TABLE engagement.sessao_feedback (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  sessao_id uuid NOT NULL,
  objetivo_id uuid,
  nota integer,
  relevancia text,
  insight text,
  intencao_aplicar text,
  o_que_faltou text,
  comentario text,
  conversa_id uuid,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE engagement.session_interests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  agent_session_id uuid NOT NULL,
  chave text NOT NULL,
  rotulo text NOT NULL,
  confianca numeric(4,3) DEFAULT 0.700 NOT NULL,
  evidencia_message_id uuid,
  ocorrencias integer DEFAULT 1 NOT NULL,
  primeira_em timestamp with time zone DEFAULT now() NOT NULL,
  ultima_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE engagement.treble_eventos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  tipo text,
  direcao text,
  telefone text,
  ocorreu_em timestamp with time zone,
  payload jsonb NOT NULL,
  recebido_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE engagement.utm_sessoes (
  token text NOT NULL,
  site text,
  origem_codigo text,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_content text,
  utm_term text,
  gclid text,
  fbclid text,
  referrer text,
  landing_url text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  usado_em timestamp with time zone
);

CREATE TABLE engagement.verificacoes_email (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  email text NOT NULL,
  dispositivo_id uuid,
  codigo_hash text NOT NULL,
  tentativas integer DEFAULT 0 NOT NULL,
  expira_em timestamp with time zone NOT NULL,
  verificado_em timestamp with time zone,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE eventos.knowledge_chunks (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  doc_id uuid NOT NULL,
  ordem integer NOT NULL,
  texto text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  embedding vector(1536),
  tsv tsvector GENERATED ALWAYS AS (to_tsvector('portuguese'::regconfig, texto)) STORED,
  stale boolean DEFAULT true NOT NULL,
  embedado_em timestamp with time zone,
  modelo_embedding text,
  indice text DEFAULT 'principal'::text NOT NULL
);

CREATE TABLE eventos.knowledge_documents (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  fonte_id uuid NOT NULL,
  titulo text NOT NULL,
  corpo text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  hash text NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  tipo_conteudo text,
  problema text,
  resultado_desejado text,
  autor text,
  url text,
  ativo boolean DEFAULT true NOT NULL,
  agents text[] DEFAULT '{}'::text[] NOT NULL,
  atualizado_em_fonte timestamp with time zone,
  aprovado_treble boolean DEFAULT false NOT NULL,
  produto_codigo text,
  event_id uuid,
  valido_de timestamp with time zone,
  valido_ate timestamp with time zone,
  cluster text NOT NULL,
  audiencia text DEFAULT 'publico'::text NOT NULL
);

CREATE TABLE institute.knowledge_chunks (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  doc_id uuid NOT NULL,
  ordem integer NOT NULL,
  texto text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  embedding vector(1536),
  tsv tsvector GENERATED ALWAYS AS (to_tsvector('portuguese'::regconfig, texto)) STORED,
  stale boolean DEFAULT true NOT NULL,
  embedado_em timestamp with time zone,
  modelo_embedding text,
  indice text DEFAULT 'principal'::text NOT NULL
);

CREATE TABLE institute.knowledge_documents (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  fonte_id uuid NOT NULL,
  titulo text NOT NULL,
  corpo text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  hash text NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  tipo_conteudo text,
  problema text,
  resultado_desejado text,
  autor text,
  url text,
  ativo boolean DEFAULT true NOT NULL,
  agents text[] DEFAULT '{}'::text[] NOT NULL,
  atualizado_em_fonte timestamp with time zone,
  aprovado_treble boolean DEFAULT false NOT NULL,
  produto_codigo text,
  event_id uuid,
  valido_de timestamp with time zone,
  valido_ate timestamp with time zone,
  cluster text NOT NULL,
  audiencia text DEFAULT 'publico'::text NOT NULL
);

CREATE TABLE intelligence.acessos_dado_pessoal (
  id bigint DEFAULT nextval('intelligence.acessos_dado_pessoal_id_seq'::regclass) NOT NULL,
  quem uuid,
  funcao text NOT NULL,
  sobre uuid,
  agente text DEFAULT 'concierge'::text NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE intelligence.analise_conversa (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  conversa_id uuid NOT NULL,
  participante_id uuid,
  analisador text NOT NULL,
  funcao text NOT NULL,
  vertical text,
  dados jsonb NOT NULL,
  modelo text,
  prompt_versao integer NOT NULL,
  ultima_mensagem_analisada_id uuid,
  conversa_atualizada_ate timestamp with time zone,
  analisado_em timestamp with time zone DEFAULT now() NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE intelligence.config (
  chave text NOT NULL,
  valor text NOT NULL
);

CREATE TABLE intelligence.continuidade_comercial (
  conversa_id uuid NOT NULL,
  analise_conversa_id uuid,
  continuation_status text NOT NULL,
  next_review_at timestamp with time zone,
  next_review_policy text,
  followup_count integer DEFAULT 0 NOT NULL,
  last_followup_at timestamp with time zone,
  last_decision jsonb,
  processing_until timestamp with time zone,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE intelligence.dossies (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  dia date NOT NULL,
  camada text NOT NULL,
  titulo text NOT NULL,
  corpo text NOT NULL,
  dados jsonb DEFAULT '{}'::jsonb NOT NULL,
  modelo text,
  gerado_em timestamp with time zone DEFAULT now() NOT NULL,
  entregue_em timestamp with time zone
);

CREATE TABLE intelligence.intencoes (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  nome text NOT NULL,
  padroes text[] DEFAULT '{}'::text[] NOT NULL,
  rota text DEFAULT 'llm'::text NOT NULL,
  ferramenta text,
  effort text DEFAULT 'medium'::text NOT NULL,
  exige_ferramenta boolean DEFAULT false NOT NULL,
  ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE intelligence.memoria_bloqueios (
  chave text NOT NULL,
  sujeito text NOT NULL,
  motivo text NOT NULL,
  exemplo_bloqueado text,
  exemplo_liberado text,
  ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE intelligence.memoria_regras (
  chave text NOT NULL,
  tipo text NOT NULL,
  pode_inferir boolean DEFAULT false NOT NULL,
  confianca_minima numeric(3,2) DEFAULT 0.80 NOT NULL,
  ttl_dias integer,
  descricao text,
  ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE intelligence.participante_contexto (
  participante_id uuid NOT NULL,
  contexto_profissional jsonb DEFAULT '{}'::jsonb NOT NULL,
  necessidades jsonb DEFAULT '[]'::jsonb NOT NULL,
  resultados_desejados jsonb DEFAULT '[]'::jsonb NOT NULL,
  temas_relevantes jsonb DEFAULT '[]'::jsonb NOT NULL,
  preferencias jsonb DEFAULT '{}'::jsonb NOT NULL,
  prioridades_atuais jsonb DEFAULT '[]'::jsonb NOT NULL,
  resumo_conversa text,
  contexto_comercial jsonb DEFAULT '{}'::jsonb NOT NULL,
  versao integer DEFAULT 1 NOT NULL,
  reconstruido_em timestamp with time zone,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE intelligence.participante_memoria (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  tipo text NOT NULL,
  chave text NOT NULL,
  valor jsonb NOT NULL,
  confianca numeric(3,2) DEFAULT 0.50 NOT NULL,
  origem text NOT NULL,
  evidencia_message_id uuid,
  status text DEFAULT 'proposta'::text NOT NULL,
  valido_ate timestamp with time zone,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  importancia numeric(3,2) DEFAULT 0.50,
  substituida_por uuid,
  analise_conversa_id uuid
);

CREATE TABLE intelligence.participante_objetivos (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  pergunta_guia text NOT NULL,
  dor_codigo text,
  area_codigo text,
  decisao_pendente text,
  prazo text,
  status text DEFAULT 'ativo'::text NOT NULL,
  definido_em timestamp with time zone DEFAULT now() NOT NULL,
  revisado_em timestamp with time zone,
  evidencia_message_id uuid
);

CREATE TABLE intelligence.perguntas_feitas (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  chave text NOT NULL,
  conversa_id uuid,
  respondida boolean DEFAULT false NOT NULL,
  recusada boolean DEFAULT false NOT NULL,
  feita_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE intelligence.recomendacoes (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  objetivo_id uuid,
  tipo text DEFAULT 'sessao'::text NOT NULL,
  sessao_id uuid,
  referencia text,
  justificativa text NOT NULL,
  origem text DEFAULT 'agente'::text NOT NULL,
  estado text DEFAULT 'oferecida'::text NOT NULL,
  mensagem_id uuid,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE intelligence.sinais_comerciais (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  participante_id uuid NOT NULL,
  area_codigo text,
  produto_codigo text,
  forca text NOT NULL,
  evidencia_texto text NOT NULL,
  mensagem_id uuid,
  contato_solicitado boolean DEFAULT false NOT NULL,
  consentimento_em timestamp with time zone,
  canal_preferido text,
  status text DEFAULT 'novo'::text NOT NULL,
  observacao text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  vertical text
);

CREATE TABLE mind.organization_content (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  event_id uuid,
  categoria text NOT NULL,
  slug text NOT NULL,
  titulo text NOT NULL,
  corpo text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  publico boolean DEFAULT true NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  valido_de timestamp with time zone,
  valido_ate timestamp with time zone,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE mind.policies (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  chave text NOT NULL,
  versao integer NOT NULL,
  titulo text NOT NULL,
  texto text NOT NULL,
  ativo boolean DEFAULT false NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  produto_codigo text
);

CREATE TABLE pessoas.pessoas (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  email text,
  whatsapp text,
  primeiro_nome text,
  sobrenome text,
  empresa text,
  cargo text,
  hubspot_id text,
  origem text DEFAULT 'hubspot'::text NOT NULL,
  sincronizado_em timestamp with time zone,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE platform.embeddings_config (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  provedor text NOT NULL,
  modelo text NOT NULL,
  dimensao integer NOT NULL,
  indice text DEFAULT 'principal'::text NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE platform.integracoes (
  codigo text NOT NULL,
  rotulo text NOT NULL,
  base_url text,
  secret_ref text,
  config jsonb DEFAULT '{}'::jsonb NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE platform.llm_calls (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  mensagem_id uuid,
  modelo text NOT NULL,
  effort text,
  tokens_entrada integer,
  tokens_saida integer,
  tokens_cache_read integer,
  tokens_cache_write integer,
  custo_usd numeric(10,6),
  latencia_ms integer,
  stop_reason text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  agent text DEFAULT 'concierge'::text NOT NULL
);

CREATE TABLE platform.llm_models (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  provedor text NOT NULL,
  modelo_id text NOT NULL,
  papel text NOT NULL,
  contexto_tokens integer,
  custo_entrada_mtok numeric(10,4),
  custo_saida_mtok numeric(10,4),
  capacidades jsonb DEFAULT '{}'::jsonb NOT NULL,
  ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE platform.llm_providers (
  codigo text NOT NULL,
  rotulo text NOT NULL,
  secret_ref text NOT NULL,
  base_url text,
  capacidades jsonb DEFAULT '{}'::jsonb NOT NULL,
  ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE platform.llm_routes (
  rota text NOT NULL,
  papel text NOT NULL,
  papel_fallback text,
  effort text,
  max_tokens integer DEFAULT 16000 NOT NULL,
  stream boolean DEFAULT true NOT NULL,
  cache_prompt boolean DEFAULT true NOT NULL,
  ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE public.espelho_estado (
  fonte text NOT NULL,
  projeto_origem text NOT NULL,
  destino text NOT NULL,
  status text DEFAULT 'nunca'::text NOT NULL,
  total_na_origem integer,
  registros_lidos integer DEFAULT 0 NOT NULL,
  registros_gravados integer DEFAULT 0 NOT NULL,
  erro text,
  iniciado_em timestamp with time zone,
  concluido_em timestamp with time zone,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.mind_admin_audit (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  actor_user_id uuid,
  action text NOT NULL,
  resource text NOT NULL,
  record_id text NOT NULL,
  record_label text,
  before_data jsonb,
  after_data jsonb,
  occurred_at timestamp with time zone DEFAULT now() NOT NULL,
  request_id uuid NOT NULL
);

CREATE TABLE public.mind_admin_editorial (
  resource text NOT NULL,
  record_id uuid NOT NULL,
  status text DEFAULT 'rascunho'::text NOT NULL,
  published_at timestamp with time zone,
  published_by uuid,
  updated_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.mind_admin_event_details (
  event_id uuid NOT NULL,
  descricao text DEFAULT ''::text NOT NULL,
  regra_reserva text DEFAULT ''::text NOT NULL,
  regra_vagas text DEFAULT ''::text NOT NULL,
  locais_candidatos jsonb DEFAULT '[]'::jsonb NOT NULL,
  updated_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.mind_admin_users (
  user_id uuid NOT NULL,
  display_name text,
  role text NOT NULL,
  active boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE summit_2026.commercial_rules (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  chave text NOT NULL,
  descricao text,
  config jsonb DEFAULT '{}'::jsonb NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  produto_codigo text
);

CREATE TABLE summit_2026.coupons (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  event_id uuid,
  codigo text NOT NULL,
  descricao text,
  tipo text NOT NULL,
  valor numeric NOT NULL,
  offer_codigo text,
  ativo boolean DEFAULT false NOT NULL,
  valido_de timestamp with time zone,
  valido_ate timestamp with time zone,
  max_usos integer,
  condicoes jsonb DEFAULT '{}'::jsonb NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE summit_2026.event_rules (
  chave text NOT NULL,
  titulo text NOT NULL,
  texto text NOT NULL,
  aplica_em text[] DEFAULT '{}'::text[] NOT NULL,
  prioridade integer DEFAULT 5 NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  event_id uuid
);

CREATE TABLE summit_2026.events (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  slug text NOT NULL,
  nome text NOT NULL,
  dias date[] DEFAULT '{}'::date[] NOT NULL,
  local text,
  cidade text,
  fuso text DEFAULT 'America/Sao_Paulo'::text NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  produto_codigo text
);

CREATE TABLE summit_2026.exhibitors (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  event_id uuid NOT NULL,
  location_id uuid,
  slug text NOT NULL,
  nome text NOT NULL,
  descricao text,
  categoria text,
  site_url text,
  contato jsonb DEFAULT '{}'::jsonb NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE summit_2026.experiencias (
  chave text NOT NULL,
  nome text NOT NULL,
  ordem smallint NOT NULL,
  inclusoes jsonb NOT NULL,
  sincronizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE summit_2026.knowledge_chunks (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  doc_id uuid NOT NULL,
  ordem integer NOT NULL,
  texto text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  embedding vector(1536),
  tsv tsvector GENERATED ALWAYS AS (to_tsvector('portuguese'::regconfig, texto)) STORED,
  stale boolean DEFAULT true NOT NULL,
  embedado_em timestamp with time zone,
  modelo_embedding text,
  indice text DEFAULT 'principal'::text NOT NULL
);

CREATE TABLE summit_2026.knowledge_documents (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  fonte_id uuid NOT NULL,
  titulo text NOT NULL,
  corpo text NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  hash text NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  tipo_conteudo text,
  problema text,
  resultado_desejado text,
  autor text,
  url text,
  ativo boolean DEFAULT true NOT NULL,
  agents text[] DEFAULT '{}'::text[] NOT NULL,
  atualizado_em_fonte timestamp with time zone,
  aprovado_treble boolean DEFAULT false NOT NULL,
  produto_codigo text,
  event_id uuid,
  valido_de timestamp with time zone,
  valido_ate timestamp with time zone,
  cluster text NOT NULL,
  audiencia text DEFAULT 'publico'::text NOT NULL
);

CREATE TABLE summit_2026.locations (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  yazo_id text,
  nome text NOT NULL,
  tipo text,
  como_chegar text,
  sincronizado_em timestamp with time zone,
  event_id uuid,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  venue_id uuid,
  parent_id uuid,
  slug text,
  aliases text[] DEFAULT '{}'::text[] NOT NULL,
  descricao text,
  andar text,
  coordenadas_mapa jsonb DEFAULT '{}'::jsonb NOT NULL,
  acessibilidade jsonb DEFAULT '{}'::jsonb NOT NULL,
  ativo boolean DEFAULT true NOT NULL
);

CREATE TABLE summit_2026.offers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  event_id uuid,
  codigo text NOT NULL,
  nome text NOT NULL,
  descricao text,
  moeda character(3) DEFAULT 'BRL'::bpchar NOT NULL,
  valor numeric(12,2),
  condicoes_pagamento text,
  checkout_url text,
  elegibilidade jsonb DEFAULT '{}'::jsonb NOT NULL,
  publico boolean DEFAULT true NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  inicia_em timestamp with time zone,
  encerra_em timestamp with time zone,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  procura text DEFAULT 'normal'::text NOT NULL,
  procura_nota text
);

CREATE TABLE summit_2026.registrations (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  person_id uuid NOT NULL,
  event_id uuid NOT NULL,
  ticket_category text,
  external_ref text,
  status text DEFAULT 'ativa'::text NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE summit_2026.route_edges (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  event_id uuid NOT NULL,
  origem_location_id uuid NOT NULL,
  destino_location_id uuid NOT NULL,
  instrucoes text NOT NULL,
  distancia_metros integer,
  minutos_estimados integer,
  acessivel boolean DEFAULT true NOT NULL,
  bidirecional boolean DEFAULT true NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE summit_2026.session_speakers (
  sessao_id uuid NOT NULL,
  palestrante_id uuid NOT NULL,
  papel text DEFAULT 'palestrante'::text NOT NULL,
  speaker_id bigint
);

CREATE TABLE summit_2026.sessions (
  id uuid DEFAULT uuid_generate_v4() NOT NULL,
  yazo_id text,
  titulo text NOT NULL,
  descricao text,
  dia date NOT NULL,
  inicio timestamp with time zone NOT NULL,
  fim timestamp with time zone,
  espaco_id uuid,
  tipo text,
  trilhas text[] DEFAULT '{}'::text[] NOT NULL,
  precisa_reserva boolean DEFAULT false NOT NULL,
  vagas_total integer,
  vagas_disponiveis integer,
  sincronizado_em timestamp with time zone,
  topicos_aprendizado jsonb DEFAULT '[]'::jsonb NOT NULL,
  resultados jsonb DEFAULT '[]'::jsonb NOT NULL,
  nivel text,
  formato text,
  event_id uuid,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  ingressos text[] DEFAULT '{}'::text[] NOT NULL,
  duracao_min integer
);

CREATE TABLE summit_2026.venues (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  event_id uuid NOT NULL,
  slug text NOT NULL,
  nome text NOT NULL,
  endereco jsonb DEFAULT '{}'::jsonb NOT NULL,
  transporte text,
  acessibilidade text,
  mapa_url text,
  ativo boolean DEFAULT true NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE treble.config (
  chave text NOT NULL,
  valor text NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE treble.polls (
  poll_id text NOT NULL,
  nome text,
  tipo text,
  users_snapshot integer,
  taxa_resposta_snapshot numeric,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  sincronizado_em timestamp with time zone
);

CREATE TABLE treble.status_da_conversa (
  telefone text NOT NULL,
  status text NOT NULL,
  aberta_em timestamp with time zone,
  fechada_em timestamp with time zone,
  session_external_id text,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
  momento timestamp with time zone
);

CREATE TABLE treble.status_hs_contatos (
  contato_id text NOT NULL,
  valor text NOT NULL,
  escrito_em timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE treble.status_hs_leads (
  lead_id text NOT NULL,
  valor text NOT NULL,
  escrito_em timestamp with time zone DEFAULT now() NOT NULL
);

ALTER SEQUENCE crm.acessos_id_seq OWNED BY crm.acessos.id;

ALTER SEQUENCE intelligence.acessos_dado_pessoal_id_seq OWNED BY intelligence.acessos_dado_pessoal.id;

CREATE OR REPLACE FUNCTION public.mind_conversa_resolver(p_evento jsonb)
 RETURNS engagement.conversas
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas'
AS $function$
declare
  conv    engagement.conversas;
  u       engagement.utm_sessoes;
  v_canal text := nullif(btrim(coalesce(p_evento->>'canal','')),'');
  v_sess  text := nullif(btrim(coalesce(p_evento->>'sessao_externa','')),'');
  v_conv  uuid := nullif(p_evento->>'conversa_id','')::uuid;
  v_disp  uuid;
  v_orig  text;
  o       jsonb := coalesce(p_evento->'origem','{}'::jsonb);
begin
  if v_canal is null then
    raise exception using errcode='22023', message='canal_obrigatorio';
  end if;

  -- conversa explicita (web/app ja tem a sessao aberta)
  if v_conv is not null then
    select * into conv from engagement.conversas where id = v_conv;
    if not found then raise exception using errcode='22023', message='conversa_inexistente'; end if;
    update engagement.conversas set ultima_atividade = now() where id = conv.id;
    return conv;
  end if;

  -- dispositivo e contexto do canal, NAO identidade da pessoa
  if nullif(btrim(coalesce(p_evento#>>'{identificadores,dispositivo}','')),'') is not null then
    insert into engagement.dispositivos (chave, user_agent, ultimo_acesso)
    values (btrim(p_evento#>>'{identificadores,dispositivo}'),
            left(p_evento->>'user_agent', 500), now())
    on conflict (chave) do update set ultimo_acesso = now(),
      user_agent = coalesce(excluded.user_agent, engagement.dispositivos.user_agent)
    returning id into v_disp;
  end if;

  select * into u from engagement.utm_sessoes
   where token = nullif(btrim(coalesce(o->>'utm_token','')),'');

  v_orig := coalesce(
    (select x.codigo from engagement.origens x
      where x.codigo = nullif(btrim(coalesce(o->>'origem_codigo','')),'') and x.ativo),
    u.origem_codigo);

  if v_sess is null then
    -- canal sem id de sessao externa: cada entrada abre conversa nova
    insert into engagement.conversas
      (canal, agente, dispositivo_id, nome_contato, telefone, origem_codigo, utm_token, produto_codigo)
    values (v_canal, nullif(btrim(coalesce(p_evento->>'agente','')),''), v_disp,
            nullif(btrim(coalesce(p_evento->>'nome','')),''),
            public.telefone_normalizar(p_evento#>>'{identificadores,whatsapp}'),
            v_orig, u.token,
            coalesce(nullif(btrim(coalesce(o->>'produto_codigo','')),''),
                     (select x.produto_codigo from engagement.origens x where x.codigo = v_orig)))
    returning * into conv;
  else
    insert into engagement.conversas
      (canal, agente, session_external_id, dispositivo_id, nome_contato, telefone,
       telefone_hash, origem_codigo, utm_token, utm, produto_codigo)
    values (v_canal, nullif(btrim(coalesce(p_evento->>'agente','')),''), v_sess, v_disp,
            nullif(btrim(coalesce(p_evento->>'nome','')),''),
            public.telefone_normalizar(p_evento#>>'{identificadores,whatsapp}'),
            nullif(btrim(coalesce(p_evento#>>'{identificadores,telefone_hash}','')),''),
            v_orig, u.token,
            case when u.token is null then null else jsonb_strip_nulls(jsonb_build_object(
              'utm_source', u.utm_source, 'utm_medium', u.utm_medium,
              'utm_campaign', u.utm_campaign, 'utm_content', u.utm_content,
              'utm_term', u.utm_term, 'gclid', u.gclid, 'fbclid', u.fbclid,
              'site', u.site, 'referrer', u.referrer, 'landing_url', u.landing_url)) end,
            coalesce(nullif(btrim(coalesce(o->>'produto_codigo','')),''),
                     (select x.produto_codigo from engagement.origens x where x.codigo = v_orig)))
    on conflict (canal, session_external_id) where session_external_id is not null do update
      set ultima_atividade = now(),
          agente        = coalesce(conversas.agente,        excluded.agente),
          nome_contato  = coalesce(conversas.nome_contato,  excluded.nome_contato),
          telefone      = coalesce(conversas.telefone,      excluded.telefone),
          telefone_hash = coalesce(conversas.telefone_hash, excluded.telefone_hash),
          origem_codigo = coalesce(conversas.origem_codigo, excluded.origem_codigo),
          utm_token     = coalesce(conversas.utm_token,     excluded.utm_token),
          utm           = coalesce(conversas.utm,           excluded.utm),
          produto_codigo= coalesce(conversas.produto_codigo,excluded.produto_codigo)
    returning * into conv;
  end if;

  if u.token is not null then
    update engagement.utm_sessoes set usado_em = coalesce(usado_em, now()) where token = u.token;
  end if;
  return conv;
end $function$
;

ALTER TABLE agentes.kit_blocos ADD CONSTRAINT kit_blocos_pkey PRIMARY KEY (rota, bloco);

ALTER TABLE agentes.kit_blocos ADD CONSTRAINT kit_blocos_rota_canonica CHECK (rota = ANY (ARRAY['summit_b2c'::text, 'summit_b2b'::text, 'institute'::text, 'dash'::text, 'cliente_suporte'::text, 'concierge_summit'::text]));

ALTER TABLE agentes.kit_blocos ADD CONSTRAINT kit_blocos_secao_valida CHECK (secao = ANY (ARRAY['structured'::text, 'knowledge'::text, 'tools'::text]));

ALTER TABLE agentes.prompts ADD CONSTRAINT prompts_pkey PRIMARY KEY (chave);

ALTER TABLE catalogo.produtos ADD CONSTRAINT produtos_pkey PRIMARY KEY (codigo);

ALTER TABLE catalogo.produtos ADD CONSTRAINT produtos_tipo_check CHECK (tipo = ANY (ARRAY['empresa'::text, 'evento'::text, 'formacao'::text, 'assinatura'::text, 'conteudo'::text, 'outro'::text]));

ALTER TABLE catalogo.produtos ADD CONSTRAINT produtos_vertical_check CHECK (vertical = ANY (ARRAY['summit'::text, 'institute'::text, 'eventos'::text, 'dash'::text, 'outro'::text]));

ALTER TABLE concierge.ciclo_estado ADD CONSTRAINT ciclo_estado_participante_id_objetivo_id_key UNIQUE (participante_id, objetivo_id);

ALTER TABLE concierge.ciclo_estado ADD CONSTRAINT ciclo_estado_pkey PRIMARY KEY (id);

ALTER TABLE concierge.config ADD CONSTRAINT config_pkey PRIMARY KEY (chave);

ALTER TABLE concierge.config_auditoria ADD CONSTRAINT config_auditoria_pkey PRIMARY KEY (id);

ALTER TABLE concierge.config_revisao ADD CONSTRAINT config_revisao_id_check CHECK (id = 1);

ALTER TABLE concierge.config_revisao ADD CONSTRAINT config_revisao_pkey PRIMARY KEY (id);

ALTER TABLE concierge.feature_flags ADD CONSTRAINT feature_flags_pkey PRIMARY KEY (chave);

ALTER TABLE concierge.ferramenta_chamadas ADD CONSTRAINT ferramenta_chamadas_pkey PRIMARY KEY (id);

ALTER TABLE concierge.ferramentas ADD CONSTRAINT ferramentas_nome_key UNIQUE (nome);

ALTER TABLE concierge.ferramentas ADD CONSTRAINT ferramentas_pkey PRIMARY KEY (id);

ALTER TABLE concierge.integracao_logs ADD CONSTRAINT integracao_logs_pkey PRIMARY KEY (id);

ALTER TABLE concierge.proativo_fila ADD CONSTRAINT proativo_fila_pkey PRIMARY KEY (id);

ALTER TABLE concierge.prompts ADD CONSTRAINT prompts_nome_versao_key UNIQUE (nome, versao);

ALTER TABLE concierge.prompts ADD CONSTRAINT prompts_pkey PRIMARY KEY (id);

ALTER TABLE concierge.regras_proativas ADD CONSTRAINT regras_proativas_nome_key UNIQUE (nome);

ALTER TABLE concierge.regras_proativas ADD CONSTRAINT regras_proativas_pkey PRIMARY KEY (id);

ALTER TABLE concierge.templates ADD CONSTRAINT templates_chave_idioma_canal_key UNIQUE (chave, idioma, canal);

ALTER TABLE concierge.templates ADD CONSTRAINT templates_pkey PRIMARY KEY (id);

ALTER TABLE concierge.tutorial_passos ADD CONSTRAINT tutorial_passos_chave_key UNIQUE (chave);

ALTER TABLE concierge.tutorial_passos ADD CONSTRAINT tutorial_passos_pkey PRIMARY KEY (id);

ALTER TABLE credenciamento_summit_2026.participantes ADD CONSTRAINT participantes_pkey PRIMARY KEY (id);

ALTER TABLE credenciamento_summit_2026.yazo_envio_fila ADD CONSTRAINT yazo_envio_fila_pkey PRIMARY KEY (id);

ALTER TABLE credenciamento_summit_2026.yazo_espelho ADD CONSTRAINT yazo_espelho_pkey PRIMARY KEY (yazo_id);

ALTER TABLE credenciamento_summit_2026.yazo_sync_state ADD CONSTRAINT yazo_sync_state_pkey PRIMARY KEY (id);

ALTER TABLE crm.acessos ADD CONSTRAINT acessos_pkey PRIMARY KEY (id);

ALTER TABLE crm.consents ADD CONSTRAINT consentimentos_pkey PRIMARY KEY (id);

ALTER TABLE crm.contato_espelho ADD CONSTRAINT contato_espelho_hubspot_id_key UNIQUE (hubspot_id);

ALTER TABLE crm.contato_espelho ADD CONSTRAINT contato_espelho_pkey PRIMARY KEY (id);

ALTER TABLE crm.empenho_summit_2026 ADD CONSTRAINT pipeline_empenho_summit_2026_hubspot_deal_id_key UNIQUE (hubspot_deal_id);

ALTER TABLE crm.empenho_summit_2026 ADD CONSTRAINT pipeline_empenho_summit_2026_pkey PRIMARY KEY (id);

ALTER TABLE crm.leads_capturados ADD CONSTRAINT leads_capturados_estado_check CHECK (estado = ANY (ARRAY['pendente'::text, 'enviado'::text]));

ALTER TABLE crm.leads_capturados ADD CONSTRAINT leads_capturados_pkey PRIMARY KEY (id);

ALTER TABLE crm.mapa_produtos ADD CONSTRAINT mapa_produtos_pkey PRIMARY KEY (propriedade, valor_origem);

ALTER TABLE crm.pessoa_nps ADD CONSTRAINT pessoa_nps_nota_check CHECK (nota >= 0 AND nota <= 10);

ALTER TABLE crm.pessoa_nps ADD CONSTRAINT pessoa_nps_pkey PRIMARY KEY (pessoa_id, produto_codigo);

ALTER TABLE crm.pessoa_produtos ADD CONSTRAINT pessoa_produtos_pessoa_id_produto_codigo_key UNIQUE (pessoa_id, produto_codigo);

ALTER TABLE crm.pessoa_produtos ADD CONSTRAINT pessoa_produtos_pkey PRIMARY KEY (id);

ALTER TABLE crm.pessoa_produtos ADD CONSTRAINT pessoa_produtos_quantidade_check CHECK (quantidade IS NULL OR quantidade >= 0);

ALTER TABLE crm.pessoas_interno ADD CONSTRAINT pessoas_interno_pkey PRIMARY KEY (pessoa_id);

ALTER TABLE crm.pipeline_de_vendas_summit ADD CONSTRAINT pipeline_summit_leads_captados_hubspot_deal_id_key UNIQUE (hubspot_deal_id);

ALTER TABLE crm.pipeline_de_vendas_summit ADD CONSTRAINT pipeline_summit_leads_captados_pkey PRIMARY KEY (id);

ALTER TABLE crm.pipeline_leads_inbound ADD CONSTRAINT pipeline_leads_inbound_pkey PRIMARY KEY (hubspot_lead_id);

ALTER TABLE crm.status_summit_hs ADD CONSTRAINT status_summit_hs_pkey PRIMARY KEY (hubspot_id);

ALTER TABLE crm.sync_estado ADD CONSTRAINT sync_estado_pkey PRIMARY KEY (fonte);

ALTER TABLE crm.sync_estado ADD CONSTRAINT sync_estado_status_check CHECK (status = ANY (ARRAY['ocioso'::text, 'rodando'::text, 'parcial'::text, 'concluido'::text, 'erro'::text]));

ALTER TABLE crm.vendas_historicas_mind_summit ADD CONSTRAINT negocios_historicos_hubspot_deal_id_key UNIQUE (hubspot_deal_id);

ALTER TABLE crm.vendas_historicas_mind_summit ADD CONSTRAINT negocios_historicos_pkey PRIMARY KEY (id);

ALTER TABLE dash.knowledge_chunks ADD CONSTRAINT knowledge_chunks_pkey PRIMARY KEY (id);

ALTER TABLE dash.knowledge_documents ADD CONSTRAINT knowledge_documents_audiencia_check CHECK (audiencia = ANY (ARRAY['publico'::text, 'interno'::text]));

ALTER TABLE dash.knowledge_documents ADD CONSTRAINT knowledge_documents_cluster_evento CHECK ((cluster = 'produto'::text) = (event_id IS NOT NULL));

ALTER TABLE dash.knowledge_documents ADD CONSTRAINT knowledge_documents_cluster_valido CHECK (cluster = ANY (ARRAY['empresa'::text, 'produto'::text, 'ciencia'::text, 'clientes'::text]));

ALTER TABLE dash.knowledge_documents ADD CONSTRAINT knowledge_documents_pkey PRIMARY KEY (id);

ALTER TABLE ecossistema.palestrantes_especialistas ADD CONSTRAINT palestrantes_especialistas_pkey PRIMARY KEY (id);

ALTER TABLE eduzz.hubspot_stage_config ADD CONSTRAINT hubspot_stage_config_pkey PRIMARY KEY (hubspot_pipeline_id, evento_eduzz);

ALTER TABLE eduzz.ingressos ADD CONSTRAINT ingressos_pkey PRIMARY KEY (uuid);

ALTER TABLE eduzz.produto_catalogo ADD CONSTRAINT produto_catalogo_pkey PRIMARY KEY (id);

ALTER TABLE eduzz.produtos ADD CONSTRAINT produtos_pkey PRIMARY KEY (eduzz_product_id);

ALTER TABLE eduzz.vendas ADD CONSTRAINT vendas_pkey PRIMARY KEY (linha_origem);

ALTER TABLE engagement.agent_sessions ADD CONSTRAINT sessoes_pkey PRIMARY KEY (id);

ALTER TABLE engagement.agente_eventos ADD CONSTRAINT agente_eventos_pkey PRIMARY KEY (id);

ALTER TABLE engagement.avaliacao_execucoes ADD CONSTRAINT avaliacao_execucoes_pkey PRIMARY KEY (id);

ALTER TABLE engagement.avaliacoes ADD CONSTRAINT avaliacoes_caso_key UNIQUE (caso);

ALTER TABLE engagement.avaliacoes ADD CONSTRAINT avaliacoes_pkey PRIMARY KEY (id);

ALTER TABLE engagement.contatos ADD CONSTRAINT contatos_de_para_key UNIQUE (de, para);

ALTER TABLE engagement.contatos ADD CONSTRAINT contatos_pkey PRIMARY KEY (id);

ALTER TABLE engagement.conversas ADD CONSTRAINT conversas_pkey PRIMARY KEY (id);

ALTER TABLE engagement.data_requests ADD CONSTRAINT solicitacoes_titular_pkey PRIMARY KEY (id);

ALTER TABLE engagement.dispositivos ADD CONSTRAINT dispositivos_chave_key UNIQUE (chave);

ALTER TABLE engagement.dispositivos ADD CONSTRAINT dispositivos_pkey PRIMARY KEY (id);

ALTER TABLE engagement.evento_feedback ADD CONSTRAINT evento_feedback_pkey PRIMARY KEY (id);

ALTER TABLE engagement.evento_feedback ADD CONSTRAINT evento_feedback_severidade_check CHECK (severidade >= 1 AND severidade <= 5);

ALTER TABLE engagement.feedbacks ADD CONSTRAINT feedbacks_pkey PRIMARY KEY (id);

ALTER TABLE engagement.identidade_fusoes ADD CONSTRAINT identidade_fusoes_pkey PRIMARY KEY (id);

ALTER TABLE engagement.identidade_fusoes ADD CONSTRAINT identidade_fusoes_status_ck CHECK (status = ANY (ARRAY['pendente'::text, 'fundido'::text, 'descartado'::text]));

ALTER TABLE engagement.identidade_fusoes ADD CONSTRAINT identidade_fusoes_tipo_ck CHECK (tipo = ANY (ARRAY['conflito_identidade'::text, 'contato_crm_de_outra_pessoa'::text, 'suspeita_sobre_merge'::text]));

ALTER TABLE engagement.identidades ADD CONSTRAINT identidades_canal_ck CHECK (canal = ANY (ARRAY['whatsapp'::text, 'email'::text, 'telefone'::text, 'auth_user'::text, 'hubspot'::text, 'dispositivo'::text, 'sessao_externa'::text, 'yazo'::text, 'eduzz'::text, 'treble_session'::text]));

ALTER TABLE engagement.identidades ADD CONSTRAINT identidades_pkey PRIMARY KEY (id);

ALTER TABLE engagement.identidades ADD CONSTRAINT identidades_unica UNIQUE (canal, identificador);

ALTER TABLE engagement.jornada_eventos ADD CONSTRAINT jornada_eventos_pkey PRIMARY KEY (id);

ALTER TABLE engagement.jornada_sessao ADD CONSTRAINT jornada_sessao_pkey PRIMARY KEY (participante_id, sessao_id);

ALTER TABLE engagement.mensagens ADD CONSTRAINT mensagens_papel_ck CHECK (papel = ANY (ARRAY['lead'::text, 'agente'::text, 'sistema'::text]));

ALTER TABLE engagement.mensagens ADD CONSTRAINT mensagens_pkey PRIMARY KEY (id);

ALTER TABLE engagement.nps ADD CONSTRAINT nps_summit_nota_check CHECK (nota >= 0 AND nota <= 10);

ALTER TABLE engagement.nps ADD CONSTRAINT nps_summit_participante_id_key UNIQUE (participante_id);

ALTER TABLE engagement.nps ADD CONSTRAINT nps_summit_pkey PRIMARY KEY (id);

ALTER TABLE engagement.origens ADD CONSTRAINT origens_audiencia_sugerida_check CHECK (audiencia_sugerida = ANY (ARRAY['b2c'::text, 'b2b'::text, 'cliente_suporte'::text, 'ja_comprou'::text, 'desconhecido'::text]));

ALTER TABLE engagement.origens ADD CONSTRAINT origens_pkey PRIMARY KEY (codigo);

ALTER TABLE engagement.origens ADD CONSTRAINT origens_site_check CHECK (site = ANY (ARRAY['mindsummit'::text, 'institute'::text, 'dash'::text, 'outro'::text]));

ALTER TABLE engagement.pessoa_perfil ADD CONSTRAINT pessoa_perfil_pkey PRIMARY KEY (pessoa_id);

ALTER TABLE engagement.sessao_feedback ADD CONSTRAINT sessao_feedback_nota_check CHECK (nota >= 0 AND nota <= 10);

ALTER TABLE engagement.sessao_feedback ADD CONSTRAINT sessao_feedback_participante_id_sessao_id_key UNIQUE (participante_id, sessao_id);

ALTER TABLE engagement.sessao_feedback ADD CONSTRAINT sessao_feedback_pkey PRIMARY KEY (id);

ALTER TABLE engagement.session_interests ADD CONSTRAINT session_interests_agent_session_id_chave_key UNIQUE (agent_session_id, chave);

ALTER TABLE engagement.session_interests ADD CONSTRAINT session_interests_confianca_check CHECK (confianca >= 0::numeric AND confianca <= 1::numeric);

ALTER TABLE engagement.session_interests ADD CONSTRAINT session_interests_ocorrencias_check CHECK (ocorrencias > 0);

ALTER TABLE engagement.session_interests ADD CONSTRAINT session_interests_pkey PRIMARY KEY (id);

ALTER TABLE engagement.treble_eventos ADD CONSTRAINT treble_eventos_pkey PRIMARY KEY (id);

ALTER TABLE engagement.utm_sessoes ADD CONSTRAINT utm_sessoes_pkey PRIMARY KEY (token);

ALTER TABLE engagement.verificacoes_email ADD CONSTRAINT verificacoes_email_pkey PRIMARY KEY (id);

ALTER TABLE eventos.knowledge_chunks ADD CONSTRAINT knowledge_chunks_pkey PRIMARY KEY (id);

ALTER TABLE eventos.knowledge_documents ADD CONSTRAINT knowledge_documents_audiencia_check CHECK (audiencia = ANY (ARRAY['publico'::text, 'interno'::text]));

ALTER TABLE eventos.knowledge_documents ADD CONSTRAINT knowledge_documents_cluster_evento CHECK ((cluster = 'produto'::text) = (event_id IS NOT NULL));

ALTER TABLE eventos.knowledge_documents ADD CONSTRAINT knowledge_documents_cluster_valido CHECK (cluster = ANY (ARRAY['empresa'::text, 'produto'::text, 'ciencia'::text, 'clientes'::text]));

ALTER TABLE eventos.knowledge_documents ADD CONSTRAINT knowledge_documents_pkey PRIMARY KEY (id);

ALTER TABLE institute.knowledge_chunks ADD CONSTRAINT knowledge_chunks_pkey PRIMARY KEY (id);

ALTER TABLE institute.knowledge_documents ADD CONSTRAINT knowledge_documents_audiencia_check CHECK (audiencia = ANY (ARRAY['publico'::text, 'interno'::text]));

ALTER TABLE institute.knowledge_documents ADD CONSTRAINT knowledge_documents_cluster_evento CHECK ((cluster = 'produto'::text) = (event_id IS NOT NULL));

ALTER TABLE institute.knowledge_documents ADD CONSTRAINT knowledge_documents_cluster_valido CHECK (cluster = ANY (ARRAY['empresa'::text, 'produto'::text, 'ciencia'::text, 'clientes'::text]));

ALTER TABLE institute.knowledge_documents ADD CONSTRAINT knowledge_documents_pkey PRIMARY KEY (id);

ALTER TABLE intelligence.acessos_dado_pessoal ADD CONSTRAINT acessos_dado_pessoal_pkey PRIMARY KEY (id);

ALTER TABLE intelligence.analise_conversa ADD CONSTRAINT analise_conversa_conversa_id_analisador_key UNIQUE (conversa_id, analisador);

ALTER TABLE intelligence.analise_conversa ADD CONSTRAINT analise_conversa_pkey PRIMARY KEY (id);

ALTER TABLE intelligence.config ADD CONSTRAINT config_pkey PRIMARY KEY (chave);

ALTER TABLE intelligence.continuidade_comercial ADD CONSTRAINT continuidade_comercial_pkey PRIMARY KEY (conversa_id);

ALTER TABLE intelligence.continuidade_comercial ADD CONSTRAINT continuidade_policy_check CHECK (next_review_policy IS NULL OR (next_review_policy = ANY (ARRAY['commitment_due'::text, 'timing_matrix'::text, 'event_trigger_only'::text, 'none'::text])));

ALTER TABLE intelligence.continuidade_comercial ADD CONSTRAINT continuidade_status_check CHECK (continuation_status = ANY (ARRAY['active'::text, 'silence'::text, 'scheduled_pause'::text, 'commitment_pending'::text, 'followup_due'::text, 'dormant'::text, 'stopped'::text]));

ALTER TABLE intelligence.dossies ADD CONSTRAINT dossies_participante_id_dia_camada_key UNIQUE (participante_id, dia, camada);

ALTER TABLE intelligence.dossies ADD CONSTRAINT dossies_pkey PRIMARY KEY (id);

ALTER TABLE intelligence.intencoes ADD CONSTRAINT intencoes_nome_key UNIQUE (nome);

ALTER TABLE intelligence.intencoes ADD CONSTRAINT intencoes_pkey PRIMARY KEY (id);

ALTER TABLE intelligence.memoria_bloqueios ADD CONSTRAINT memoria_bloqueios_pkey PRIMARY KEY (chave);

ALTER TABLE intelligence.memoria_regras ADD CONSTRAINT memoria_regras_pkey PRIMARY KEY (chave);

ALTER TABLE intelligence.participante_contexto ADD CONSTRAINT participante_contexto_pkey PRIMARY KEY (participante_id);

ALTER TABLE intelligence.participante_memoria ADD CONSTRAINT participante_memoria_pkey PRIMARY KEY (id);

ALTER TABLE intelligence.participante_memoria ADD CONSTRAINT participante_memoria_status_check CHECK (status = ANY (ARRAY['proposta'::text, 'ativa'::text, 'substituida'::text, 'rejeitada'::text, 'expirada'::text]));

ALTER TABLE intelligence.participante_objetivos ADD CONSTRAINT participante_objetivos_pkey PRIMARY KEY (id);

ALTER TABLE intelligence.perguntas_feitas ADD CONSTRAINT perguntas_feitas_participante_id_chave_key UNIQUE (participante_id, chave);

ALTER TABLE intelligence.perguntas_feitas ADD CONSTRAINT perguntas_feitas_pkey PRIMARY KEY (id);

ALTER TABLE intelligence.recomendacoes ADD CONSTRAINT recomendacoes_pkey PRIMARY KEY (id);

ALTER TABLE intelligence.sinais_comerciais ADD CONSTRAINT sinais_comerciais_pkey PRIMARY KEY (id);

ALTER TABLE intelligence.sinais_comerciais ADD CONSTRAINT sinais_comerciais_vertical_check CHECK (vertical = ANY (ARRAY['summit'::text, 'institute'::text, 'eventos'::text, 'dash'::text, 'outro'::text]));

ALTER TABLE mind.organization_content ADD CONSTRAINT organization_content_categoria_check CHECK (categoria = ANY (ARRAY['sobre'::text, 'missao'::text, 'historia'::text, 'produto'::text, 'faq'::text, 'politica'::text, 'contato'::text, 'acessibilidade'::text, 'transporte'::text]));

ALTER TABLE mind.organization_content ADD CONSTRAINT organization_content_check CHECK (valido_ate IS NULL OR valido_de IS NULL OR valido_ate > valido_de);

ALTER TABLE mind.organization_content ADD CONSTRAINT organization_content_event_id_slug_key UNIQUE (event_id, slug);

ALTER TABLE mind.organization_content ADD CONSTRAINT organization_content_metadata_check CHECK (jsonb_typeof(metadata) = 'object'::text);

ALTER TABLE mind.organization_content ADD CONSTRAINT organization_content_pkey PRIMARY KEY (id);

ALTER TABLE mind.policies ADD CONSTRAINT politicas_chave_versao_key UNIQUE (chave, versao);

ALTER TABLE mind.policies ADD CONSTRAINT politicas_pkey PRIMARY KEY (id);

ALTER TABLE pessoas.pessoas ADD CONSTRAINT pessoas_email_key UNIQUE (email);

ALTER TABLE pessoas.pessoas ADD CONSTRAINT pessoas_hubspot_id_key UNIQUE (hubspot_id);

ALTER TABLE pessoas.pessoas ADD CONSTRAINT pessoas_origem_check CHECK (origem = ANY (ARRAY['hubspot'::text, 'bot'::text, 'manual'::text]));

ALTER TABLE pessoas.pessoas ADD CONSTRAINT pessoas_pkey PRIMARY KEY (id);

ALTER TABLE platform.embeddings_config ADD CONSTRAINT embeddings_config_indice_key UNIQUE (indice);

ALTER TABLE platform.embeddings_config ADD CONSTRAINT embeddings_config_pkey PRIMARY KEY (id);

ALTER TABLE platform.integracoes ADD CONSTRAINT integracoes_pkey PRIMARY KEY (codigo);

ALTER TABLE platform.llm_calls ADD CONSTRAINT llm_chamadas_pkey PRIMARY KEY (id);

ALTER TABLE platform.llm_models ADD CONSTRAINT llm_modelos_pkey PRIMARY KEY (id);

ALTER TABLE platform.llm_models ADD CONSTRAINT llm_modelos_provedor_modelo_id_key UNIQUE (provedor, modelo_id);

ALTER TABLE platform.llm_providers ADD CONSTRAINT llm_provedores_pkey PRIMARY KEY (codigo);

ALTER TABLE platform.llm_routes ADD CONSTRAINT llm_rotas_pkey PRIMARY KEY (rota);

ALTER TABLE public.espelho_estado ADD CONSTRAINT espelho_estado_pkey PRIMARY KEY (fonte);

ALTER TABLE public.espelho_estado ADD CONSTRAINT espelho_estado_status_check CHECK (status = ANY (ARRAY['nunca'::text, 'rodando'::text, 'ok'::text, 'erro'::text]));

ALTER TABLE public.mind_admin_audit ADD CONSTRAINT mind_admin_audit_action_check CHECK (action = ANY (ARRAY['criar'::text, 'atualizar'::text, 'publicar'::text, 'arquivar'::text, 'reindexar'::text, 'login'::text]));

ALTER TABLE public.mind_admin_audit ADD CONSTRAINT mind_admin_audit_pkey PRIMARY KEY (id);

ALTER TABLE public.mind_admin_editorial ADD CONSTRAINT mind_admin_editorial_pkey PRIMARY KEY (resource, record_id);

ALTER TABLE public.mind_admin_editorial ADD CONSTRAINT mind_admin_editorial_resource_check CHECK (resource = ANY (ARRAY['sessions'::text, 'speakers'::text]));

ALTER TABLE public.mind_admin_editorial ADD CONSTRAINT mind_admin_editorial_status_check CHECK (status = ANY (ARRAY['rascunho'::text, 'em_revisao'::text, 'publicado'::text, 'arquivado'::text]));

ALTER TABLE public.mind_admin_event_details ADD CONSTRAINT mind_admin_event_details_locais_candidatos_check CHECK (jsonb_typeof(locais_candidatos) = 'array'::text);

ALTER TABLE public.mind_admin_event_details ADD CONSTRAINT mind_admin_event_details_pkey PRIMARY KEY (event_id);

ALTER TABLE public.mind_admin_users ADD CONSTRAINT mind_admin_users_pkey PRIMARY KEY (user_id);

ALTER TABLE public.mind_admin_users ADD CONSTRAINT mind_admin_users_role_check CHECK (role = ANY (ARRAY['administrador'::text, 'editor'::text, 'aprovador'::text, 'atendimento'::text, 'analista'::text]));

ALTER TABLE summit_2026.commercial_rules ADD CONSTRAINT commercial_rules_chave_key UNIQUE (chave);

ALTER TABLE summit_2026.commercial_rules ADD CONSTRAINT commercial_rules_pkey PRIMARY KEY (id);

ALTER TABLE summit_2026.coupons ADD CONSTRAINT coupons_codigo_key UNIQUE (codigo);

ALTER TABLE summit_2026.coupons ADD CONSTRAINT coupons_pkey PRIMARY KEY (id);

ALTER TABLE summit_2026.coupons ADD CONSTRAINT coupons_tipo_check CHECK (tipo = ANY (ARRAY['percentual'::text, 'valor_fixo'::text]));

ALTER TABLE summit_2026.coupons ADD CONSTRAINT coupons_valor_check CHECK (valor > 0::numeric);

ALTER TABLE summit_2026.event_rules ADD CONSTRAINT regras_evento_pkey PRIMARY KEY (chave);

ALTER TABLE summit_2026.events ADD CONSTRAINT events_pkey PRIMARY KEY (id);

ALTER TABLE summit_2026.events ADD CONSTRAINT events_slug_key UNIQUE (slug);

ALTER TABLE summit_2026.exhibitors ADD CONSTRAINT exhibitors_contato_check CHECK (jsonb_typeof(contato) = 'object'::text);

ALTER TABLE summit_2026.exhibitors ADD CONSTRAINT exhibitors_event_id_slug_key UNIQUE (event_id, slug);

ALTER TABLE summit_2026.exhibitors ADD CONSTRAINT exhibitors_metadata_check CHECK (jsonb_typeof(metadata) = 'object'::text);

ALTER TABLE summit_2026.exhibitors ADD CONSTRAINT exhibitors_pkey PRIMARY KEY (id);

ALTER TABLE summit_2026.experiencias ADD CONSTRAINT experiencias_pkey PRIMARY KEY (chave);

ALTER TABLE summit_2026.knowledge_chunks ADD CONSTRAINT knowledge_chunks_pkey PRIMARY KEY (id);

ALTER TABLE summit_2026.knowledge_documents ADD CONSTRAINT knowledge_documents_audiencia_check CHECK (audiencia = ANY (ARRAY['publico'::text, 'interno'::text]));

ALTER TABLE summit_2026.knowledge_documents ADD CONSTRAINT knowledge_documents_cluster_evento CHECK ((cluster = 'produto'::text) = (event_id IS NOT NULL));

ALTER TABLE summit_2026.knowledge_documents ADD CONSTRAINT knowledge_documents_cluster_valido CHECK (cluster = ANY (ARRAY['empresa'::text, 'produto'::text, 'ciencia'::text, 'clientes'::text]));

ALTER TABLE summit_2026.knowledge_documents ADD CONSTRAINT knowledge_documents_pkey PRIMARY KEY (id);

ALTER TABLE summit_2026.locations ADD CONSTRAINT agenda_espacos_pkey PRIMARY KEY (id);

ALTER TABLE summit_2026.locations ADD CONSTRAINT agenda_espacos_yazo_id_key UNIQUE (yazo_id);

ALTER TABLE summit_2026.offers ADD CONSTRAINT offers_check CHECK (encerra_em IS NULL OR inicia_em IS NULL OR encerra_em > inicia_em);

ALTER TABLE summit_2026.offers ADD CONSTRAINT offers_elegibilidade_check CHECK (jsonb_typeof(elegibilidade) = 'object'::text);

ALTER TABLE summit_2026.offers ADD CONSTRAINT offers_event_id_codigo_key UNIQUE (event_id, codigo);

ALTER TABLE summit_2026.offers ADD CONSTRAINT offers_pkey PRIMARY KEY (id);

ALTER TABLE summit_2026.offers ADD CONSTRAINT offers_procura_check CHECK (procura = ANY (ARRAY['normal'::text, 'alta'::text, 'ultimas_vagas'::text]));

ALTER TABLE summit_2026.offers ADD CONSTRAINT offers_valor_check CHECK (valor IS NULL OR valor >= 0::numeric);

ALTER TABLE summit_2026.registrations ADD CONSTRAINT registrations_person_id_event_id_key UNIQUE (person_id, event_id);

ALTER TABLE summit_2026.registrations ADD CONSTRAINT registrations_pkey PRIMARY KEY (id);

ALTER TABLE summit_2026.route_edges ADD CONSTRAINT route_edges_check CHECK (origem_location_id <> destino_location_id);

ALTER TABLE summit_2026.route_edges ADD CONSTRAINT route_edges_distancia_metros_check CHECK (distancia_metros IS NULL OR distancia_metros >= 0);

ALTER TABLE summit_2026.route_edges ADD CONSTRAINT route_edges_event_id_origem_location_id_destino_location_id_key UNIQUE (event_id, origem_location_id, destino_location_id);

ALTER TABLE summit_2026.route_edges ADD CONSTRAINT route_edges_metadata_check CHECK (jsonb_typeof(metadata) = 'object'::text);

ALTER TABLE summit_2026.route_edges ADD CONSTRAINT route_edges_minutos_estimados_check CHECK (minutos_estimados IS NULL OR minutos_estimados >= 0);

ALTER TABLE summit_2026.route_edges ADD CONSTRAINT route_edges_pkey PRIMARY KEY (id);

ALTER TABLE summit_2026.session_speakers ADD CONSTRAINT agenda_sessao_palestrantes_pkey PRIMARY KEY (sessao_id, palestrante_id);

ALTER TABLE summit_2026.session_speakers ADD CONSTRAINT session_speakers_papel_check CHECK (papel = ANY (ARRAY['palestrante'::text, 'mediacao'::text, 'apresentacao'::text, 'convidado'::text]));

ALTER TABLE summit_2026.sessions ADD CONSTRAINT agenda_sessoes_pkey PRIMARY KEY (id);

ALTER TABLE summit_2026.sessions ADD CONSTRAINT agenda_sessoes_yazo_id_key UNIQUE (yazo_id);

ALTER TABLE summit_2026.venues ADD CONSTRAINT venues_endereco_check CHECK (jsonb_typeof(endereco) = 'object'::text);

ALTER TABLE summit_2026.venues ADD CONSTRAINT venues_event_id_slug_key UNIQUE (event_id, slug);

ALTER TABLE summit_2026.venues ADD CONSTRAINT venues_pkey PRIMARY KEY (id);

ALTER TABLE treble.config ADD CONSTRAINT config_pkey PRIMARY KEY (chave);

ALTER TABLE treble.polls ADD CONSTRAINT polls_pkey PRIMARY KEY (poll_id);

ALTER TABLE treble.status_da_conversa ADD CONSTRAINT status_da_conversa_pkey PRIMARY KEY (telefone);

ALTER TABLE treble.status_hs_contatos ADD CONSTRAINT status_hs_contatos_pkey PRIMARY KEY (contato_id);

ALTER TABLE treble.status_hs_leads ADD CONSTRAINT status_hs_leads_pkey PRIMARY KEY (lead_id);

CREATE INDEX ciclo_estado_objetivo_id_idx ON concierge.ciclo_estado USING btree (objetivo_id);

CREATE UNIQUE INDEX ferramenta_chamadas_idempotency_key_idx ON concierge.ferramenta_chamadas USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);

CREATE INDEX ferramenta_chamadas_mensagem_id_idx ON concierge.ferramenta_chamadas USING btree (mensagem_id);

CREATE INDEX ferramenta_chamadas_participante_id_idx ON concierge.ferramenta_chamadas USING btree (participante_id);

CREATE INDEX integracao_logs_integracao_criado_em_idx ON concierge.integracao_logs USING btree (integracao, criado_em DESC);

CREATE INDEX integracao_logs_participante_id_idx ON concierge.integracao_logs USING btree (participante_id);

CREATE UNIQUE INDEX proativo_fila_chave_dedupe_idx ON concierge.proativo_fila USING btree (chave_dedupe) WHERE (chave_dedupe IS NOT NULL);

CREATE INDEX proativo_fila_estado_agendado_para_idx ON concierge.proativo_fila USING btree (estado, agendado_para);

CREATE INDEX proativo_fila_participante_id_idx ON concierge.proativo_fila USING btree (participante_id);

CREATE INDEX proativo_fila_regra_id_idx ON concierge.proativo_fila USING btree (regra_id);

CREATE UNIQUE INDEX prompts_nome_idx ON concierge.prompts USING btree (nome) WHERE ativo;

CREATE INDEX tutorial_passos_aviso_chave_idx ON concierge.tutorial_passos USING btree (aviso_chave);

CREATE INDEX cred_part_cpf_idx ON credenciamento_summit_2026.participantes USING btree (cpf) WHERE (cpf IS NOT NULL);

CREATE INDEX cred_part_email_idx ON credenciamento_summit_2026.participantes USING btree (lower(email)) WHERE (email IS NOT NULL);

CREATE INDEX cred_part_origem_idx ON credenciamento_summit_2026.participantes USING btree (ticket_origin, ticket_type);

CREATE INDEX cred_part_status_idx ON credenciamento_summit_2026.participantes USING btree (status);

CREATE INDEX cred_part_tel_idx ON credenciamento_summit_2026.participantes USING btree (telefone_norm) WHERE (telefone_norm IS NOT NULL);

CREATE INDEX cred_fila_part_idx ON credenciamento_summit_2026.yazo_envio_fila USING btree (participant_id) WHERE (participant_id IS NOT NULL);

CREATE INDEX cred_fila_pend_idx ON credenciamento_summit_2026.yazo_envio_fila USING btree (criado_em) WHERE (processado_em IS NULL);

CREATE INDEX cred_yazo_email_idx ON credenciamento_summit_2026.yazo_espelho USING btree (lower(email)) WHERE (email IS NOT NULL);

CREATE INDEX crm_acessos_pessoa_idx ON crm.acessos USING btree (pessoa_id, criado_em DESC);

CREATE INDEX consentimentos_participante_id_finalidade_criado_em_idx ON crm.consents USING btree (participante_id, finalidade, criado_em DESC);

CREATE INDEX consents_mensagem_id_idx ON crm.consents USING btree (mensagem_id);

CREATE INDEX contato_espelho_email_idx ON crm.contato_espelho USING btree (lower(email));

CREATE INDEX contato_espelho_pessoa_idx ON crm.contato_espelho USING btree (pessoa_id);

CREATE INDEX contato_espelho_phone_idx ON crm.contato_espelho USING btree (phone);

CREATE INDEX contato_espelho_props_idx ON crm.contato_espelho USING gin (propriedades jsonb_path_ops);

CREATE INDEX idx_ce_phone10 ON crm.contato_espelho USING btree ("right"(regexp_replace(COALESCE(phone, ''::text), '\D'::text, ''::text, 'g'::text), 10));

CREATE INDEX idx_ce_wa10 ON crm.contato_espelho USING btree ("right"(regexp_replace(COALESCE(hs_whatsapp_phone_number, ''::text), '\D'::text, ''::text, 'g'::text), 10));

CREATE INDEX pipeline_empenho_summit_2026_pessoa_id_idx ON crm.empenho_summit_2026 USING btree (pessoa_id) WHERE (hs_is_closed IS NOT TRUE);

CREATE INDEX pipeline_empenho_summit_2026_pessoa_id_pipeline_idx ON crm.empenho_summit_2026 USING btree (pessoa_id, pipeline);

CREATE INDEX pipeline_empenho_summit_2026_propriedades_idx ON crm.empenho_summit_2026 USING gin (propriedades jsonb_path_ops);

CREATE INDEX pessoa_produtos_pessoa_idx ON crm.pessoa_produtos USING btree (pessoa_id);

CREATE INDEX pessoa_produtos_produto_idx ON crm.pessoa_produtos USING btree (produto_codigo);

CREATE INDEX pessoas_interno_dono_idx ON crm.pessoas_interno USING btree (dono_id) WHERE (dono_id IS NOT NULL);

CREATE INDEX pipeline_summit_leads_abertos_idx ON crm.pipeline_de_vendas_summit USING btree (pessoa_id) WHERE (hs_is_closed IS NOT TRUE);

CREATE INDEX pipeline_summit_leads_pessoa_pipeline_idx ON crm.pipeline_de_vendas_summit USING btree (pessoa_id, pipeline);

CREATE INDEX pipeline_summit_leads_props_idx ON crm.pipeline_de_vendas_summit USING gin (propriedades jsonb_path_ops);

CREATE INDEX pipeline_leads_inbound_contato_idx ON crm.pipeline_leads_inbound USING btree (hs_primary_contact_id);

CREATE INDEX pipeline_leads_inbound_estagio_idx ON crm.pipeline_leads_inbound USING btree (hs_pipeline_stage);

CREATE INDEX negocios_hist_ano_idx ON crm.vendas_historicas_mind_summit USING btree (pessoa_id, summit_year);

CREATE INDEX negocios_hist_pessoa_idx ON crm.vendas_historicas_mind_summit USING btree (pessoa_id);

CREATE INDEX negocios_hist_props_idx ON crm.vendas_historicas_mind_summit USING gin (propriedades jsonb_path_ops);

CREATE INDEX knowledge_chunks_doc_id_ordem_idx ON dash.knowledge_chunks USING btree (doc_id, ordem);

CREATE INDEX knowledge_chunks_embedding_idx ON dash.knowledge_chunks USING hnsw (embedding vector_cosine_ops) WITH (m='16', ef_construction='64');

CREATE INDEX knowledge_chunks_indice_idx ON dash.knowledge_chunks USING btree (indice) WHERE (NOT stale);

CREATE INDEX knowledge_chunks_tsv_idx ON dash.knowledge_chunks USING gin (tsv);

CREATE INDEX knowledge_documents_agents_idx ON dash.knowledge_documents USING gin (agents);

CREATE INDEX knowledge_documents_atualizado_em_idx ON dash.knowledge_documents USING btree (atualizado_em DESC);

CREATE INDEX knowledge_documents_event_id_idx ON dash.knowledge_documents USING btree (event_id) WHERE ativo;

CREATE INDEX knowledge_documents_fonte_id_idx ON dash.knowledge_documents USING btree (fonte_id);

CREATE INDEX knowledge_documents_problema_idx ON dash.knowledge_documents USING btree (problema);

CREATE INDEX knowledge_documents_produto_codigo_idx ON dash.knowledge_documents USING btree (produto_codigo) WHERE ativo;

CREATE UNIQUE INDEX palestrantes_nome_uidx ON ecossistema.palestrantes_especialistas USING btree (lower(btrim(nome)));

CREATE UNIQUE INDEX palestrantes_slug_uidx ON ecossistema.palestrantes_especialistas USING btree (slug);

CREATE INDEX ingressos_comprador_idx ON eduzz.ingressos USING btree (lower(email_comprador)) WHERE (email_comprador IS NOT NULL);

CREATE INDEX ingressos_email_idx ON eduzz.ingressos USING btree (lower(email)) WHERE (email IS NOT NULL);

CREATE INDEX ingressos_evento_idx ON eduzz.ingressos USING btree (evento_titulo, status);

CREATE INDEX ingressos_fatura_idx ON eduzz.ingressos USING btree (fatura) WHERE (fatura IS NOT NULL);

CREATE INDEX ingressos_tel_idx ON eduzz.ingressos USING btree (telefone_norm) WHERE (telefone_norm IS NOT NULL);

CREATE INDEX produto_catalogo_acesso_idx ON eduzz.produto_catalogo USING btree (tipo_de_acesso, tipo_de_venda);

CREATE INDEX produto_catalogo_eduzz_idx ON eduzz.produto_catalogo USING btree (eduzz_product_id) WHERE (eduzz_product_id IS NOT NULL);

CREATE INDEX produto_catalogo_summit_idx ON eduzz.produto_catalogo USING btree (summit_year, summit_categoria);

CREATE INDEX vendas_email_idx ON eduzz.vendas USING btree (lower(cliente_email)) WHERE (cliente_email IS NOT NULL);

CREATE INDEX vendas_fatura_idx ON eduzz.vendas USING btree (fatura) WHERE (fatura IS NOT NULL);

CREATE INDEX vendas_produto_idx ON eduzz.vendas USING btree (produto);

CREATE INDEX vendas_status_idx ON eduzz.vendas USING btree (status);

CREATE INDEX vendas_tel_idx ON eduzz.vendas USING btree (cliente_telefone_norm) WHERE (cliente_telefone_norm IS NOT NULL);

CREATE INDEX agent_sessions_auth_user_activity_idx ON engagement.agent_sessions USING btree (auth_user_id, ultima_atividade DESC);

CREATE INDEX sessoes_dispositivo_id_ultima_atividade_idx ON engagement.agent_sessions USING btree (dispositivo_id, ultima_atividade DESC);

CREATE INDEX sessoes_participante_id_idx ON engagement.agent_sessions USING btree (participante_id);

CREATE INDEX agente_eventos_conversa_id_idx ON engagement.agente_eventos USING btree (conversa_id);

CREATE INDEX agente_eventos_participante_id_idx ON engagement.agente_eventos USING btree (participante_id);

CREATE INDEX agente_eventos_tipo_criado_em_idx ON engagement.agente_eventos USING btree (tipo, criado_em DESC);

CREATE INDEX avaliacao_execucoes_avaliacao_id_idx ON engagement.avaliacao_execucoes USING btree (avaliacao_id);

CREATE INDEX avaliacao_execucoes_modelo_criado_em_idx ON engagement.avaliacao_execucoes USING btree (modelo, criado_em DESC);

CREATE INDEX contatos_de_idx ON engagement.contatos USING btree (de);

CREATE INDEX contatos_para_idx ON engagement.contatos USING btree (para);

CREATE UNIQUE INDEX conversas_canal_sessao_uk ON engagement.conversas USING btree (canal, session_external_id) WHERE (session_external_id IS NOT NULL);

CREATE INDEX conversas_dispositivo_id_idx ON engagement.conversas USING btree (dispositivo_id);

CREATE INDEX conversas_participante_id_ultima_atividade_idx ON engagement.conversas USING btree (participante_id, ultima_atividade DESC);

CREATE INDEX data_requests_participante_id_idx ON engagement.data_requests USING btree (participante_id);

CREATE INDEX solicitacoes_titular_estado_criado_em_idx ON engagement.data_requests USING btree (estado, criado_em);

CREATE INDEX evento_feedback_mensagem_id_idx ON engagement.evento_feedback USING btree (mensagem_id);

CREATE INDEX evento_feedback_participante_id_idx ON engagement.evento_feedback USING btree (participante_id);

CREATE INDEX evento_feedback_severidade_tratado_criado_em_idx ON engagement.evento_feedback USING btree (severidade DESC, tratado, criado_em DESC);

CREATE INDEX feedbacks_participante_id_idx ON engagement.feedbacks USING btree (participante_id);

CREATE UNIQUE INDEX identidade_fusoes_par_pendente_uk ON engagement.identidade_fusoes USING btree (LEAST(participante_id, participante_origem), GREATEST(participante_id, participante_origem), tipo) WHERE ((status = 'pendente'::text) AND (participante_origem IS NOT NULL));

CREATE INDEX identidade_fusoes_participante_id_idx ON engagement.identidade_fusoes USING btree (participante_id);

CREATE INDEX identidade_fusoes_participante_origem_idx ON engagement.identidade_fusoes USING btree (participante_origem);

CREATE UNIQUE INDEX identidade_fusoes_pessoa_pendente_uk ON engagement.identidade_fusoes USING btree (participante_id, tipo) WHERE ((status = 'pendente'::text) AND (participante_origem IS NULL));

CREATE INDEX identidade_fusoes_status_tipo_idx ON engagement.identidade_fusoes USING btree (status, tipo, criado_em DESC);

CREATE INDEX identidades_pessoa_ix ON engagement.identidades USING btree (pessoa_id);

CREATE INDEX jornada_eventos_mensagem_id_idx ON engagement.jornada_eventos USING btree (mensagem_id);

CREATE INDEX jornada_eventos_participante_id_criado_em_idx ON engagement.jornada_eventos USING btree (participante_id, criado_em);

CREATE INDEX jornada_eventos_sessao_id_tipo_idx ON engagement.jornada_eventos USING btree (sessao_id, tipo);

CREATE INDEX jornada_sessao_motivo_ausencia_idx ON engagement.jornada_sessao USING btree (motivo_ausencia);

CREATE INDEX jornada_sessao_participante_id_planejou_idx ON engagement.jornada_sessao USING btree (participante_id, planejou);

CREATE INDEX jornada_sessao_sessao_id_compareceu_idx ON engagement.jornada_sessao USING btree (sessao_id, compareceu);

CREATE UNIQUE INDEX mensagens_conversa_client_msg_uk ON engagement.mensagens USING btree (conversa_id, client_msg_id) WHERE (client_msg_id IS NOT NULL);

CREATE INDEX mensagens_conversa_id_criado_em_idx ON engagement.mensagens USING btree (conversa_id, criado_em);

CREATE INDEX mensagens_participante_id_idx ON engagement.mensagens USING btree (participante_id);

CREATE INDEX nps_conversa_id_idx ON engagement.nps USING btree (conversa_id);

CREATE INDEX nps_event_id_idx ON engagement.nps USING btree (event_id);

CREATE INDEX sessao_feedback_conversa_id_idx ON engagement.sessao_feedback USING btree (conversa_id);

CREATE INDEX sessao_feedback_objetivo_id_idx ON engagement.sessao_feedback USING btree (objetivo_id);

CREATE INDEX sessao_feedback_sessao_id_nota_idx ON engagement.sessao_feedback USING btree (sessao_id, nota);

CREATE INDEX session_interests_evidence_message_idx ON engagement.session_interests USING btree (evidencia_message_id);

CREATE INDEX session_interests_session_last_idx ON engagement.session_interests USING btree (agent_session_id, ultima_em DESC);

CREATE INDEX treble_eventos_recebido_idx ON engagement.treble_eventos USING btree (recebido_em DESC);

CREATE INDEX treble_eventos_tel_idx ON engagement.treble_eventos USING btree (telefone, ocorreu_em DESC);

CREATE INDEX utm_sessoes_criado_idx ON engagement.utm_sessoes USING btree (criado_em DESC);

CREATE INDEX verificacoes_email_dispositivo_id_idx ON engagement.verificacoes_email USING btree (dispositivo_id);

CREATE INDEX verificacoes_email_email_criado_em_idx ON engagement.verificacoes_email USING btree (email, criado_em DESC);

CREATE INDEX knowledge_chunks_doc_id_ordem_idx ON eventos.knowledge_chunks USING btree (doc_id, ordem);

CREATE INDEX knowledge_chunks_embedding_idx ON eventos.knowledge_chunks USING hnsw (embedding vector_cosine_ops) WITH (m='16', ef_construction='64');

CREATE INDEX knowledge_chunks_indice_idx ON eventos.knowledge_chunks USING btree (indice) WHERE (NOT stale);

CREATE INDEX knowledge_chunks_tsv_idx ON eventos.knowledge_chunks USING gin (tsv);

CREATE INDEX knowledge_documents_agents_idx ON eventos.knowledge_documents USING gin (agents);

CREATE INDEX knowledge_documents_atualizado_em_idx ON eventos.knowledge_documents USING btree (atualizado_em DESC);

CREATE INDEX knowledge_documents_event_id_idx ON eventos.knowledge_documents USING btree (event_id) WHERE ativo;

CREATE INDEX knowledge_documents_fonte_id_idx ON eventos.knowledge_documents USING btree (fonte_id);

CREATE INDEX knowledge_documents_problema_idx ON eventos.knowledge_documents USING btree (problema);

CREATE INDEX knowledge_documents_produto_codigo_idx ON eventos.knowledge_documents USING btree (produto_codigo) WHERE ativo;

CREATE INDEX knowledge_chunks_doc_id_ordem_idx ON institute.knowledge_chunks USING btree (doc_id, ordem);

CREATE INDEX knowledge_chunks_embedding_idx ON institute.knowledge_chunks USING hnsw (embedding vector_cosine_ops) WITH (m='16', ef_construction='64');

CREATE INDEX knowledge_chunks_indice_idx ON institute.knowledge_chunks USING btree (indice) WHERE (NOT stale);

CREATE INDEX knowledge_chunks_tsv_idx ON institute.knowledge_chunks USING gin (tsv);

CREATE INDEX knowledge_documents_agents_idx ON institute.knowledge_documents USING gin (agents);

CREATE INDEX knowledge_documents_atualizado_em_idx ON institute.knowledge_documents USING btree (atualizado_em DESC);

CREATE INDEX knowledge_documents_event_id_idx ON institute.knowledge_documents USING btree (event_id) WHERE ativo;

CREATE INDEX knowledge_documents_fonte_id_idx ON institute.knowledge_documents USING btree (fonte_id);

CREATE INDEX knowledge_documents_problema_idx ON institute.knowledge_documents USING btree (problema);

CREATE INDEX knowledge_documents_produto_codigo_idx ON institute.knowledge_documents USING btree (produto_codigo) WHERE ativo;

CREATE INDEX acessos_dado_pessoal_quem_criado_em_idx ON intelligence.acessos_dado_pessoal USING btree (quem, criado_em DESC);

CREATE INDEX acessos_sobre_outro ON intelligence.acessos_dado_pessoal USING btree (sobre, criado_em DESC) WHERE (sobre IS DISTINCT FROM quem);

CREATE INDEX analise_conversa_analisador_idx ON intelligence.analise_conversa USING btree (analisador);

CREATE INDEX analise_conversa_conversa_id_idx ON intelligence.analise_conversa USING btree (conversa_id);

CREATE INDEX analise_conversa_participante_id_idx ON intelligence.analise_conversa USING btree (participante_id);

CREATE INDEX continuidade_fila_idx ON intelligence.continuidade_comercial USING btree (next_review_at) WHERE (next_review_at IS NOT NULL);

CREATE INDEX intencoes_ferramenta_idx ON intelligence.intencoes USING btree (ferramenta);

CREATE INDEX participante_memoria_analise_conversa_id_idx ON intelligence.participante_memoria USING btree (analise_conversa_id);

CREATE INDEX participante_memoria_evidencia_message_id_idx ON intelligence.participante_memoria USING btree (evidencia_message_id);

CREATE UNIQUE INDEX participante_memoria_participante_id_chave_idx ON intelligence.participante_memoria USING btree (participante_id, chave) WHERE (status = 'ativa'::text);

CREATE INDEX participante_memoria_participante_id_status_idx ON intelligence.participante_memoria USING btree (participante_id, status);

CREATE INDEX participante_memoria_substituida_por_idx ON intelligence.participante_memoria USING btree (substituida_por);

CREATE INDEX participante_objetivos_dor_codigo_idx ON intelligence.participante_objetivos USING btree (dor_codigo);

CREATE INDEX participante_objetivos_evidencia_message_id_idx ON intelligence.participante_objetivos USING btree (evidencia_message_id);

CREATE INDEX participante_objetivos_participante_id_status_idx ON intelligence.participante_objetivos USING btree (participante_id, status);

CREATE INDEX perguntas_feitas_conversa_id_idx ON intelligence.perguntas_feitas USING btree (conversa_id);

CREATE INDEX recomendacoes_mensagem_id_idx ON intelligence.recomendacoes USING btree (mensagem_id);

CREATE INDEX recomendacoes_objetivo_id_idx ON intelligence.recomendacoes USING btree (objetivo_id);

CREATE INDEX recomendacoes_participante_id_estado_idx ON intelligence.recomendacoes USING btree (participante_id, estado);

CREATE INDEX recomendacoes_sessao_id_idx ON intelligence.recomendacoes USING btree (sessao_id);

CREATE INDEX sinais_comerciais_area_codigo_idx ON intelligence.sinais_comerciais USING btree (area_codigo);

CREATE INDEX sinais_comerciais_forca_status_criado_em_idx ON intelligence.sinais_comerciais USING btree (forca, status, criado_em DESC);

CREATE INDEX sinais_comerciais_mensagem_id_idx ON intelligence.sinais_comerciais USING btree (mensagem_id);

CREATE INDEX sinais_comerciais_participante_id_idx ON intelligence.sinais_comerciais USING btree (participante_id);

CREATE UNIQUE INDEX organization_content_global_slug_uq ON mind.organization_content USING btree (slug) WHERE (event_id IS NULL);

CREATE INDEX organization_content_lookup_idx ON mind.organization_content USING btree (event_id, categoria, ativo, publico);

CREATE UNIQUE INDEX politicas_chave_idx ON mind.policies USING btree (chave) WHERE ativo;

CREATE INDEX idx_pessoas_email ON pessoas.pessoas USING btree (lower(email)) WHERE (email IS NOT NULL);

CREATE INDEX idx_pessoas_hubspot ON pessoas.pessoas USING btree (hubspot_id) WHERE (hubspot_id IS NOT NULL);

CREATE INDEX pessoas_empresa_idx ON pessoas.pessoas USING btree (lower(empresa)) WHERE (empresa IS NOT NULL);

CREATE INDEX pessoas_whatsapp_idx ON pessoas.pessoas USING btree (whatsapp) WHERE (whatsapp IS NOT NULL);

CREATE UNIQUE INDEX uq_pessoas_whatsapp ON pessoas.pessoas USING btree (whatsapp) WHERE (whatsapp IS NOT NULL);

CREATE INDEX llm_calls_mensagem_id_idx ON platform.llm_calls USING btree (mensagem_id);

CREATE UNIQUE INDEX llm_modelos_papel_idx ON platform.llm_models USING btree (papel) WHERE ativo;

CREATE INDEX mind_admin_audit_actor_idx ON public.mind_admin_audit USING btree (actor_user_id, occurred_at DESC);

CREATE INDEX mind_admin_audit_occurred_at_idx ON public.mind_admin_audit USING btree (occurred_at DESC);

CREATE INDEX event_rules_atualizado_em ON summit_2026.event_rules USING btree (atualizado_em DESC);

CREATE INDEX event_rules_event_id_idx ON summit_2026.event_rules USING btree (event_id);

CREATE INDEX events_atualizado_em ON summit_2026.events USING btree (atualizado_em DESC);

CREATE INDEX exhibitors_event_location_idx ON summit_2026.exhibitors USING btree (event_id, location_id, ativo);

CREATE INDEX exhibitors_nome_trgm_idx ON summit_2026.exhibitors USING gin (nome gin_trgm_ops);

CREATE INDEX knowledge_chunks_doc_id_ordem_idx ON summit_2026.knowledge_chunks USING btree (doc_id, ordem);

CREATE INDEX knowledge_chunks_embedding_idx ON summit_2026.knowledge_chunks USING hnsw (embedding vector_cosine_ops) WITH (m='16', ef_construction='64');

CREATE INDEX knowledge_chunks_indice_idx ON summit_2026.knowledge_chunks USING btree (indice) WHERE (NOT stale);

CREATE INDEX knowledge_chunks_tsv_idx ON summit_2026.knowledge_chunks USING gin (tsv);

CREATE INDEX knowledge_documents_agents_idx ON summit_2026.knowledge_documents USING gin (agents);

CREATE INDEX knowledge_documents_atualizado_em_idx ON summit_2026.knowledge_documents USING btree (atualizado_em DESC);

CREATE INDEX knowledge_documents_event_id_idx ON summit_2026.knowledge_documents USING btree (event_id) WHERE ativo;

CREATE INDEX knowledge_documents_fonte_id_idx ON summit_2026.knowledge_documents USING btree (fonte_id);

CREATE INDEX knowledge_documents_problema_idx ON summit_2026.knowledge_documents USING btree (problema);

CREATE INDEX knowledge_documents_produto_codigo_idx ON summit_2026.knowledge_documents USING btree (produto_codigo) WHERE ativo;

CREATE INDEX locations_atualizado_em ON summit_2026.locations USING btree (atualizado_em DESC);

CREATE INDEX locations_event_id_idx ON summit_2026.locations USING btree (event_id);

CREATE UNIQUE INDEX locations_event_slug_uq ON summit_2026.locations USING btree (event_id, slug) WHERE (slug IS NOT NULL);

CREATE INDEX locations_event_tipo_idx ON summit_2026.locations USING btree (event_id, tipo, ativo);

CREATE INDEX locations_nome_trgm_idx ON summit_2026.locations USING gin (nome gin_trgm_ops);

CREATE INDEX locations_parent_idx ON summit_2026.locations USING btree (parent_id);

CREATE INDEX locations_venue_idx ON summit_2026.locations USING btree (venue_id);

CREATE INDEX offers_ativas_idx ON summit_2026.offers USING btree (event_id, ativo, inicia_em, encerra_em);

CREATE UNIQUE INDEX offers_global_codigo_uq ON summit_2026.offers USING btree (codigo) WHERE (event_id IS NULL);

CREATE INDEX registrations_event_id_idx ON summit_2026.registrations USING btree (event_id);

CREATE INDEX route_edges_destino_idx ON summit_2026.route_edges USING btree (event_id, destino_location_id, ativo);

CREATE INDEX route_edges_origem_idx ON summit_2026.route_edges USING btree (event_id, origem_location_id, ativo);

CREATE INDEX session_speakers_palestrante_id_idx ON summit_2026.session_speakers USING btree (palestrante_id);

CREATE INDEX session_speakers_speaker_id_idx ON summit_2026.session_speakers USING btree (speaker_id);

CREATE INDEX agenda_sessoes_dia_inicio_idx ON summit_2026.sessions USING btree (dia, inicio);

CREATE INDEX agenda_sessoes_trilhas_idx ON summit_2026.sessions USING gin (trilhas);

CREATE INDEX idx_sessoes_topicos ON summit_2026.sessions USING gin (topicos_aprendizado);

CREATE INDEX sessions_atualizado_em ON summit_2026.sessions USING btree (atualizado_em DESC);

CREATE INDEX sessions_dia_inicio ON summit_2026.sessions USING btree (dia, inicio);

CREATE INDEX sessions_espaco_id_idx ON summit_2026.sessions USING btree (espaco_id);

CREATE INDEX sessions_event_dia_inicio ON summit_2026.sessions USING btree (event_id, dia, inicio);

CREATE INDEX sessions_event_id_idx ON summit_2026.sessions USING btree (event_id);

CREATE OR REPLACE VIEW concierge.v_aderencia_por_area WITH (security_invoker=on) AS  SELECT s.titulo,
    mem.valor #>> '{}'::text[] AS area,
    count(*) AS compareceram
   FROM engagement.jornada_sessao j
     JOIN summit_2026.sessions s ON s.id = j.sessao_id
     JOIN intelligence.participante_memoria mem ON mem.participante_id = j.participante_id AND mem.chave = 'area_profissional'::text AND mem.status = 'ativa'::text
  WHERE j.compareceu
  GROUP BY s.titulo, mem.valor
  ORDER BY s.titulo, (count(*)) DESC;

CREATE OR REPLACE VIEW concierge.v_operacao_agora WITH (security_invoker=on) AS  SELECT categoria,
    severidade,
    count(*) AS ocorrencias,
    max(criado_em) AS ultima
   FROM engagement.evento_feedback
  WHERE tratado = false AND criado_em > (now() - '03:00:00'::interval)
  GROUP BY categoria, severidade
  ORDER BY severidade DESC, (count(*)) DESC;

CREATE OR REPLACE VIEW concierge.v_sessoes_avaliadas WITH (security_invoker=on) AS  SELECT s.id,
    s.titulo,
    s.dia,
    count(f.*) AS respostas,
    round(avg(f.nota), 1) AS nota_media
   FROM summit_2026.sessions s
     LEFT JOIN engagement.sessao_feedback f ON f.sessao_id = s.id
  GROUP BY s.id, s.titulo, s.dia
  ORDER BY s.dia, s.inicio;

CREATE OR REPLACE VIEW credenciamento_summit_2026.v_participantes AS  SELECT p.id,
    p.name,
    p.email,
    p.cellphone,
    p.telefone_norm,
    p.cpf,
    p.ticket_type,
    p.ticket_name,
    p.ticket_origin,
    p.sponsor_company,
    p.invoice_or_sale_number,
    p.ticket_number,
    p.batch,
    p.buyer_name,
    p.buyer_email,
    p.buyer_company,
    p.buyer_cnpj,
    p.buyer_cpf,
    p.uuid,
    p.status,
    p.revogado_em,
    p.motivo_revogacao,
    p.criado_em,
    p.atualizado_em,
    p.yazo_sync_status,
    p.yazo_sync_error,
    p.yazo_last_synced_at,
    p.yazo_user_id,
    p.yazo_payload_hash,
    p.external_id,
    p.credenciamento_sync_status,
    p.credenciamento_sync_error,
    p.credenciamento_last_synced_at,
    p.sincronizado_em,
    r.pessoa_id,
    r.criterio AS pessoa_criterio
   FROM credenciamento_summit_2026.participantes p
     LEFT JOIN LATERAL ( SELECT c.pessoa_id,
            c.criterio
           FROM ( SELECT d.pessoa_id,
                    'email'::text AS criterio,
                    1 AS prio
                   FROM engagement.identidades d
                  WHERE d.canal = 'email'::text AND p.email IS NOT NULL AND lower(d.identificador) = lower(p.email)
                UNION ALL
                 SELECT DISTINCT t.pessoa_id,
                    'telefone'::text AS text,
                    2
                   FROM engagement.identidades t
                  WHERE t.canal = 'whatsapp'::text AND p.telefone_norm IS NOT NULL AND t.identificador = p.telefone_norm AND (( SELECT count(DISTINCT u.pessoa_id) AS count
                           FROM engagement.identidades u
                          WHERE u.canal = 'whatsapp'::text AND u.identificador = p.telefone_norm)) = 1) c
          ORDER BY c.prio
         LIMIT 1) r ON true;

CREATE OR REPLACE VIEW crm.negocio_contatos AS  SELECT n.hubspot_deal_id,
    c.value AS contato_hubspot_id,
    n.pipeline,
    'historico'::text AS origem
   FROM crm.vendas_historicas_mind_summit n,
    LATERAL jsonb_array_elements_text(n.propriedades -> '_contatos'::text) c(value)
  WHERE n.propriedades ? '_contatos'::text
UNION ALL
 SELECT p.hubspot_deal_id,
    c.value AS contato_hubspot_id,
    p.pipeline,
    'summit_leads'::text AS origem
   FROM crm.pipeline_de_vendas_summit p,
    LATERAL jsonb_array_elements_text(p.propriedades -> '_contatos'::text) c(value)
  WHERE p.propriedades ? '_contatos'::text;

CREATE OR REPLACE VIEW eduzz.v_ingressos AS  SELECT i.uuid,
    i.event_id,
    i.evento_titulo,
    i.n_ingresso,
    i.participante,
    i.cpf_cnpj,
    i.telefone,
    i.telefone_norm,
    i.email,
    i.cod_participante,
    i.cod_comprador,
    i.nome_comprador,
    i.email_comprador,
    i.documento_comprador,
    i.fatura,
    i.valor_da_venda,
    i.valor_do_item,
    i.cupom,
    i.valor_do_cupom,
    i.lote,
    i.nome_do_lote,
    i.descricao,
    i.status,
    i.check_in,
    i.data_de_pagamento,
    i.marcadores,
    i.origem_criado_em,
    i.origem_atualizado_em,
    i.sumiu_do_blinket_em,
    i.sincronizado_em,
    r.pessoa_id,
    r.criterio AS pessoa_criterio
   FROM eduzz.ingressos i
     LEFT JOIN LATERAL ( SELECT c.pessoa_id,
            c.criterio
           FROM ( SELECT d.pessoa_id,
                    'email'::text AS criterio,
                    1 AS prio
                   FROM engagement.identidades d
                  WHERE d.canal = 'email'::text AND i.email IS NOT NULL AND lower(d.identificador) = lower(i.email)
                UNION ALL
                 SELECT DISTINCT t.pessoa_id,
                    'telefone'::text AS text,
                    2
                   FROM engagement.identidades t
                  WHERE t.canal = 'whatsapp'::text AND i.telefone_norm IS NOT NULL AND t.identificador = i.telefone_norm AND (( SELECT count(DISTINCT u.pessoa_id) AS count
                           FROM engagement.identidades u
                          WHERE u.canal = 'whatsapp'::text AND u.identificador = i.telefone_norm)) = 1) c
          ORDER BY c.prio
         LIMIT 1) r ON true;

CREATE OR REPLACE VIEW eduzz.v_vendas AS  SELECT v.linha_origem,
    v.fatura,
    v.status,
    v.metodo_de_pagamento,
    v.forma_de_pagamento,
    v.n_parcelas,
    v.moeda,
    v.contrato,
    v.parcelamento_sem_limites,
    v.data_de_criacao,
    v.data_de_vencimento,
    v.data_de_pagamento,
    v.data_de_credito,
    v.data_de_solicitacao_de_reembolso,
    v.data_de_reembolso,
    v.tipo_de_reembolso,
    v.sku,
    v.id_do_produto,
    v.produto,
    v.quantidade,
    v.cupom,
    v.valor_do_cupom,
    v.valor_inicial_da_venda,
    v.valor_total_da_venda,
    v.valor_faturado_documento_fiscal,
    v.valor_inicial_do_item,
    v.valor_total_do_item,
    v.valor_reembolsado,
    v.valor_de_frete,
    v.liquidacao_do_parcelamento,
    v.taxa_eduzz,
    v.taxa_alumy,
    v.outros,
    v.ganho_liquido,
    v.tipo_parceiro,
    v.parceiro,
    v.recebeu_doc_fiscal,
    v.cliente_nome,
    v.cliente_email,
    v.cliente_fones,
    v.cliente_telefone_norm,
    v.cliente_tipo_documento,
    v.cliente_documento,
    v.endereco,
    v.numero,
    v.complemento,
    v.bairro,
    v.cep,
    v.cidade,
    v.ibge,
    v.uf,
    v.utm_source,
    v.utm_campaign,
    v.utm_medium,
    v.utm_content,
    v.utm_term,
    v.url_boleto,
    v.nome_da_oferta,
    v.produto_mapeado,
    v.modalidade_venda_mapeada,
    v.lote_mapeado,
    v.origem_importado_em,
    v.sincronizado_em,
    r.pessoa_id,
    r.criterio AS pessoa_criterio
   FROM eduzz.vendas v
     LEFT JOIN LATERAL ( SELECT c.pessoa_id,
            c.criterio
           FROM ( SELECT d.pessoa_id,
                    'email'::text AS criterio,
                    1 AS prio
                   FROM engagement.identidades d
                  WHERE d.canal = 'email'::text AND v.cliente_email IS NOT NULL AND lower(d.identificador) = lower(v.cliente_email)
                UNION ALL
                 SELECT DISTINCT t.pessoa_id,
                    'telefone'::text AS text,
                    2
                   FROM engagement.identidades t
                  WHERE t.canal = 'whatsapp'::text AND v.cliente_telefone_norm IS NOT NULL AND t.identificador = v.cliente_telefone_norm AND (( SELECT count(DISTINCT u.pessoa_id) AS count
                           FROM engagement.identidades u
                          WHERE u.canal = 'whatsapp'::text AND u.identificador = v.cliente_telefone_norm)) = 1) c
          ORDER BY c.prio
         LIMIT 1) r ON true;

CREATE OR REPLACE VIEW engagement.janela_24h AS  WITH ult AS (
         SELECT mensagens.conversa_id,
            max(mensagens.criado_em) FILTER (WHERE mensagens.papel = 'lead'::text) AS ultima_do_lead
           FROM engagement.mensagens
          GROUP BY mensagens.conversa_id
        )
 SELECT c.id AS conversa_id,
    c.session_external_id,
    c.telefone,
    c.nome_contato,
    COALESCE(u.ultima_do_lead, c.ultima_atividade) AS base_da_janela,
    c.encerrada_em,
        CASE
            WHEN c.encerrada_em IS NOT NULL THEN 'fechada'::text
            WHEN COALESCE(u.ultima_do_lead, c.ultima_atividade) < (now() - '24:00:00'::interval) THEN 'fechada'::text
            ELSE 'aberta'::text
        END AS janela,
        CASE
            WHEN c.encerrada_em IS NULL THEN GREATEST('00:00:00'::interval, COALESCE(u.ultima_do_lead, c.ultima_atividade) + '24:00:00'::interval - now())
            ELSE NULL::interval
        END AS falta_pra_fechar
   FROM engagement.conversas c
     LEFT JOIN ult u ON u.conversa_id = c.id
  WHERE c.canal = 'whatsapp'::text;

CREATE OR REPLACE VIEW engagement.v_pessoa AS  SELECT p.id,
    ( SELECT i.identificador
           FROM engagement.identidades i
          WHERE i.pessoa_id = p.id AND i.canal = 'yazo'::text
         LIMIT 1) AS yazo_id,
    NULLIF(btrim(concat_ws(' '::text, p.primeiro_nome, p.sobrenome)), ''::text) AS nome,
    p.email,
    p.whatsapp AS telefone,
    p.empresa,
    p.cargo,
    f.idioma,
    COALESCE(f.anonimo, false) AS anonimo,
    p.sincronizado_em,
    p.criado_em,
    p.atualizado_em
   FROM pessoas.pessoas p
     LEFT JOIN engagement.pessoa_perfil f ON f.pessoa_id = p.id;

CREATE OR REPLACE VIEW mind.produtos AS  SELECT codigo,
    nome,
    tipo,
    vertical AS linha,
    descricao_curta,
    vende,
    ativo,
    comeca_em,
    encerra_em,
    atualizado_em,
    schema_dados,
    descricao,
    periodo
   FROM catalogo.produtos;

CREATE OR REPLACE VIEW concierge.v_funil_valor AS  SELECT ( SELECT count(*) AS count
           FROM engagement.v_pessoa
          WHERE NOT v_pessoa.anonimo) AS participantes,
    ( SELECT count(DISTINCT o.participante_id) AS count
           FROM intelligence.participante_objetivos o
          WHERE o.status = 'ativo'::text) AS com_objetivo,
    ( SELECT count(DISTINCT r.participante_id) AS count
           FROM intelligence.recomendacoes r) AS receberam_recomendacao,
    ( SELECT count(DISTINCT r.participante_id) AS count
           FROM intelligence.recomendacoes r
          WHERE r.estado = ANY (ARRAY['aceita'::text, 'agendada'::text, 'compareceu'::text])) AS aceitaram,
    ( SELECT count(DISTINCT f.participante_id) AS count
           FROM engagement.sessao_feedback f) AS avaliaram,
    ( SELECT count(DISTINCT s.participante_id) AS count
           FROM intelligence.sinais_comerciais s
          WHERE s.forca = ANY (ARRAY['media'::text, 'alta'::text])) AS com_sinal_comercial;

ALTER TABLE agentes.prompts ADD CONSTRAINT prompts_produto_codigo_fkey FOREIGN KEY (produto_codigo) REFERENCES catalogo.produtos(codigo);

ALTER TABLE concierge.ciclo_estado ADD CONSTRAINT ciclo_estado_objetivo_id_fkey FOREIGN KEY (objetivo_id) REFERENCES intelligence.participante_objetivos(id) ON DELETE CASCADE;

ALTER TABLE concierge.ciclo_estado ADD CONSTRAINT ciclo_estado_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE concierge.ferramenta_chamadas ADD CONSTRAINT ferramenta_chamadas_mensagem_id_fkey FOREIGN KEY (mensagem_id) REFERENCES engagement.mensagens(id) ON DELETE SET NULL;

ALTER TABLE concierge.ferramenta_chamadas ADD CONSTRAINT ferramenta_chamadas_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE concierge.integracao_logs ADD CONSTRAINT integracao_logs_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE SET NULL;

ALTER TABLE concierge.proativo_fila ADD CONSTRAINT proativo_fila_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE concierge.proativo_fila ADD CONSTRAINT proativo_fila_regra_id_fkey FOREIGN KEY (regra_id) REFERENCES concierge.regras_proativas(id) ON DELETE CASCADE;

ALTER TABLE concierge.tutorial_passos ADD CONSTRAINT tutorial_passos_aviso_chave_fkey FOREIGN KEY (aviso_chave) REFERENCES summit_2026.event_rules(chave);

ALTER TABLE crm.acessos ADD CONSTRAINT acessos_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES pessoas.pessoas(id) ON DELETE SET NULL;

ALTER TABLE crm.consents ADD CONSTRAINT consentimentos_mensagem_id_fkey FOREIGN KEY (mensagem_id) REFERENCES engagement.mensagens(id) ON DELETE SET NULL;

ALTER TABLE crm.consents ADD CONSTRAINT consentimentos_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE crm.contato_espelho ADD CONSTRAINT contato_espelho_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE crm.mapa_produtos ADD CONSTRAINT mapa_produtos_produto_codigo_fkey FOREIGN KEY (produto_codigo) REFERENCES catalogo.produtos(codigo);

ALTER TABLE crm.pessoa_nps ADD CONSTRAINT pessoa_nps_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE crm.pessoa_nps ADD CONSTRAINT pessoa_nps_produto_codigo_fkey FOREIGN KEY (produto_codigo) REFERENCES catalogo.produtos(codigo);

ALTER TABLE crm.pessoa_produtos ADD CONSTRAINT pessoa_produtos_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE crm.pessoa_produtos ADD CONSTRAINT pessoa_produtos_produto_codigo_fkey FOREIGN KEY (produto_codigo) REFERENCES catalogo.produtos(codigo);

ALTER TABLE crm.pessoas_interno ADD CONSTRAINT pessoas_interno_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE crm.pipeline_de_vendas_summit ADD CONSTRAINT pipeline_summit_leads_captados_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES pessoas.pessoas(id) ON DELETE SET NULL;

ALTER TABLE crm.pipeline_de_vendas_summit ADD CONSTRAINT pipeline_summit_leads_captados_produto_codigo_fkey FOREIGN KEY (produto_codigo) REFERENCES catalogo.produtos(codigo);

ALTER TABLE crm.vendas_historicas_mind_summit ADD CONSTRAINT negocios_historicos_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES pessoas.pessoas(id) ON DELETE SET NULL;

ALTER TABLE crm.vendas_historicas_mind_summit ADD CONSTRAINT negocios_historicos_produto_codigo_fkey FOREIGN KEY (produto_codigo) REFERENCES catalogo.produtos(codigo);

ALTER TABLE dash.knowledge_chunks ADD CONSTRAINT knowledge_chunks_doc_fk FOREIGN KEY (doc_id) REFERENCES dash.knowledge_documents(id) ON DELETE CASCADE;

ALTER TABLE engagement.agent_sessions ADD CONSTRAINT agent_sessions_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE engagement.agent_sessions ADD CONSTRAINT sessoes_dispositivo_id_fkey FOREIGN KEY (dispositivo_id) REFERENCES engagement.dispositivos(id) ON DELETE CASCADE;

ALTER TABLE engagement.agent_sessions ADD CONSTRAINT sessoes_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE SET NULL;

ALTER TABLE engagement.agente_eventos ADD CONSTRAINT agente_eventos_conversa_id_fkey FOREIGN KEY (conversa_id) REFERENCES engagement.conversas(id) ON DELETE CASCADE;

ALTER TABLE engagement.agente_eventos ADD CONSTRAINT agente_eventos_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.avaliacao_execucoes ADD CONSTRAINT avaliacao_execucoes_avaliacao_id_fkey FOREIGN KEY (avaliacao_id) REFERENCES engagement.avaliacoes(id) ON DELETE CASCADE;

ALTER TABLE engagement.contatos ADD CONSTRAINT contatos_de_fkey FOREIGN KEY (de) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.contatos ADD CONSTRAINT contatos_para_fkey FOREIGN KEY (para) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.conversas ADD CONSTRAINT conversas_dispositivo_id_fkey FOREIGN KEY (dispositivo_id) REFERENCES engagement.dispositivos(id) ON DELETE SET NULL;

ALTER TABLE engagement.conversas ADD CONSTRAINT conversas_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.data_requests ADD CONSTRAINT solicitacoes_titular_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.evento_feedback ADD CONSTRAINT evento_feedback_mensagem_id_fkey FOREIGN KEY (mensagem_id) REFERENCES engagement.mensagens(id) ON DELETE SET NULL;

ALTER TABLE engagement.evento_feedback ADD CONSTRAINT evento_feedback_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE SET NULL;

ALTER TABLE engagement.feedbacks ADD CONSTRAINT feedbacks_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.identidade_fusoes ADD CONSTRAINT identidade_fusoes_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.identidade_fusoes ADD CONSTRAINT identidade_fusoes_participante_origem_fkey FOREIGN KEY (participante_origem) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.identidades ADD CONSTRAINT identidades_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.jornada_eventos ADD CONSTRAINT jornada_eventos_mensagem_id_fkey FOREIGN KEY (mensagem_id) REFERENCES engagement.mensagens(id) ON DELETE SET NULL;

ALTER TABLE engagement.jornada_eventos ADD CONSTRAINT jornada_eventos_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.jornada_eventos ADD CONSTRAINT jornada_eventos_sessao_id_fkey FOREIGN KEY (sessao_id) REFERENCES summit_2026.sessions(id) ON DELETE CASCADE;

ALTER TABLE engagement.jornada_sessao ADD CONSTRAINT jornada_sessao_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.jornada_sessao ADD CONSTRAINT jornada_sessao_sessao_id_fkey FOREIGN KEY (sessao_id) REFERENCES summit_2026.sessions(id) ON DELETE CASCADE;

ALTER TABLE engagement.mensagens ADD CONSTRAINT mensagens_conversa_id_fkey FOREIGN KEY (conversa_id) REFERENCES engagement.conversas(id) ON DELETE CASCADE;

ALTER TABLE engagement.mensagens ADD CONSTRAINT mensagens_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.nps ADD CONSTRAINT nps_event_id_fkey FOREIGN KEY (event_id) REFERENCES summit_2026.events(id);

ALTER TABLE engagement.nps ADD CONSTRAINT nps_summit_conversa_id_fkey FOREIGN KEY (conversa_id) REFERENCES engagement.conversas(id) ON DELETE SET NULL;

ALTER TABLE engagement.nps ADD CONSTRAINT nps_summit_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.origens ADD CONSTRAINT origens_produto_codigo_fkey FOREIGN KEY (produto_codigo) REFERENCES catalogo.produtos(codigo);

ALTER TABLE engagement.pessoa_perfil ADD CONSTRAINT pessoa_perfil_pessoa_id_fkey FOREIGN KEY (pessoa_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.sessao_feedback ADD CONSTRAINT sessao_feedback_conversa_id_fkey FOREIGN KEY (conversa_id) REFERENCES engagement.conversas(id) ON DELETE SET NULL;

ALTER TABLE engagement.sessao_feedback ADD CONSTRAINT sessao_feedback_objetivo_id_fkey FOREIGN KEY (objetivo_id) REFERENCES intelligence.participante_objetivos(id) ON DELETE SET NULL;

ALTER TABLE engagement.sessao_feedback ADD CONSTRAINT sessao_feedback_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE engagement.sessao_feedback ADD CONSTRAINT sessao_feedback_sessao_id_fkey FOREIGN KEY (sessao_id) REFERENCES summit_2026.sessions(id) ON DELETE CASCADE;

ALTER TABLE engagement.session_interests ADD CONSTRAINT session_interests_agent_session_id_fkey FOREIGN KEY (agent_session_id) REFERENCES engagement.agent_sessions(id) ON DELETE CASCADE;

ALTER TABLE engagement.session_interests ADD CONSTRAINT session_interests_evidencia_message_id_fkey FOREIGN KEY (evidencia_message_id) REFERENCES engagement.mensagens(id) ON DELETE SET NULL;

ALTER TABLE engagement.utm_sessoes ADD CONSTRAINT utm_sessoes_origem_codigo_fkey FOREIGN KEY (origem_codigo) REFERENCES engagement.origens(codigo);

ALTER TABLE engagement.verificacoes_email ADD CONSTRAINT verificacoes_email_dispositivo_id_fkey FOREIGN KEY (dispositivo_id) REFERENCES engagement.dispositivos(id) ON DELETE CASCADE;

ALTER TABLE eventos.knowledge_chunks ADD CONSTRAINT knowledge_chunks_doc_fk FOREIGN KEY (doc_id) REFERENCES eventos.knowledge_documents(id) ON DELETE CASCADE;

ALTER TABLE institute.knowledge_chunks ADD CONSTRAINT knowledge_chunks_doc_fk FOREIGN KEY (doc_id) REFERENCES institute.knowledge_documents(id) ON DELETE CASCADE;

ALTER TABLE intelligence.acessos_dado_pessoal ADD CONSTRAINT acessos_dado_pessoal_quem_fkey FOREIGN KEY (quem) REFERENCES pessoas.pessoas(id) ON DELETE SET NULL;

ALTER TABLE intelligence.acessos_dado_pessoal ADD CONSTRAINT acessos_dado_pessoal_sobre_fkey FOREIGN KEY (sobre) REFERENCES pessoas.pessoas(id) ON DELETE SET NULL;

ALTER TABLE intelligence.analise_conversa ADD CONSTRAINT analise_conversa_conversa_id_fkey FOREIGN KEY (conversa_id) REFERENCES engagement.conversas(id) ON DELETE CASCADE;

ALTER TABLE intelligence.analise_conversa ADD CONSTRAINT analise_conversa_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id);

ALTER TABLE intelligence.continuidade_comercial ADD CONSTRAINT continuidade_comercial_analise_conversa_id_fkey FOREIGN KEY (analise_conversa_id) REFERENCES intelligence.analise_conversa(id) ON DELETE SET NULL;

ALTER TABLE intelligence.continuidade_comercial ADD CONSTRAINT continuidade_comercial_conversa_id_fkey FOREIGN KEY (conversa_id) REFERENCES engagement.conversas(id) ON DELETE CASCADE;

ALTER TABLE intelligence.dossies ADD CONSTRAINT dossies_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE intelligence.intencoes ADD CONSTRAINT intencoes_ferramenta_fkey FOREIGN KEY (ferramenta) REFERENCES concierge.ferramentas(nome);

ALTER TABLE intelligence.participante_contexto ADD CONSTRAINT participante_contexto_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE intelligence.participante_memoria ADD CONSTRAINT participante_memoria_analise_conversa_id_fkey FOREIGN KEY (analise_conversa_id) REFERENCES intelligence.analise_conversa(id) ON DELETE SET NULL;

ALTER TABLE intelligence.participante_memoria ADD CONSTRAINT participante_memoria_evidencia_message_id_fkey FOREIGN KEY (evidencia_message_id) REFERENCES engagement.mensagens(id) ON DELETE SET NULL;

ALTER TABLE intelligence.participante_memoria ADD CONSTRAINT participante_memoria_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE intelligence.participante_memoria ADD CONSTRAINT participante_memoria_substituida_por_fkey FOREIGN KEY (substituida_por) REFERENCES intelligence.participante_memoria(id);

ALTER TABLE intelligence.participante_objetivos ADD CONSTRAINT participante_objetivos_evidencia_message_id_fkey FOREIGN KEY (evidencia_message_id) REFERENCES engagement.mensagens(id) ON DELETE SET NULL;

ALTER TABLE intelligence.participante_objetivos ADD CONSTRAINT participante_objetivos_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE intelligence.perguntas_feitas ADD CONSTRAINT perguntas_feitas_conversa_id_fkey FOREIGN KEY (conversa_id) REFERENCES engagement.conversas(id) ON DELETE SET NULL;

ALTER TABLE intelligence.perguntas_feitas ADD CONSTRAINT perguntas_feitas_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE intelligence.recomendacoes ADD CONSTRAINT recomendacoes_mensagem_id_fkey FOREIGN KEY (mensagem_id) REFERENCES engagement.mensagens(id) ON DELETE SET NULL;

ALTER TABLE intelligence.recomendacoes ADD CONSTRAINT recomendacoes_objetivo_id_fkey FOREIGN KEY (objetivo_id) REFERENCES intelligence.participante_objetivos(id) ON DELETE SET NULL;

ALTER TABLE intelligence.recomendacoes ADD CONSTRAINT recomendacoes_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE intelligence.recomendacoes ADD CONSTRAINT recomendacoes_sessao_id_fkey FOREIGN KEY (sessao_id) REFERENCES summit_2026.sessions(id) ON DELETE CASCADE;

ALTER TABLE intelligence.sinais_comerciais ADD CONSTRAINT sinais_comerciais_mensagem_id_fkey FOREIGN KEY (mensagem_id) REFERENCES engagement.mensagens(id) ON DELETE SET NULL;

ALTER TABLE intelligence.sinais_comerciais ADD CONSTRAINT sinais_comerciais_participante_id_fkey FOREIGN KEY (participante_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE mind.organization_content ADD CONSTRAINT organization_content_event_id_fkey FOREIGN KEY (event_id) REFERENCES summit_2026.events(id) ON DELETE CASCADE;

ALTER TABLE mind.policies ADD CONSTRAINT policies_produto_codigo_fkey FOREIGN KEY (produto_codigo) REFERENCES catalogo.produtos(codigo);

ALTER TABLE platform.llm_calls ADD CONSTRAINT llm_chamadas_mensagem_id_fkey FOREIGN KEY (mensagem_id) REFERENCES engagement.mensagens(id) ON DELETE SET NULL;

ALTER TABLE platform.llm_models ADD CONSTRAINT llm_modelos_provedor_fkey FOREIGN KEY (provedor) REFERENCES platform.llm_providers(codigo) ON DELETE CASCADE;

ALTER TABLE public.mind_admin_audit ADD CONSTRAINT mind_admin_audit_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.mind_admin_editorial ADD CONSTRAINT mind_admin_editorial_published_by_fkey FOREIGN KEY (published_by) REFERENCES auth.users(id);

ALTER TABLE public.mind_admin_editorial ADD CONSTRAINT mind_admin_editorial_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);

ALTER TABLE public.mind_admin_event_details ADD CONSTRAINT mind_admin_event_details_event_id_fkey FOREIGN KEY (event_id) REFERENCES summit_2026.events(id) ON DELETE CASCADE;

ALTER TABLE public.mind_admin_event_details ADD CONSTRAINT mind_admin_event_details_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);

ALTER TABLE public.mind_admin_users ADD CONSTRAINT mind_admin_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE summit_2026.commercial_rules ADD CONSTRAINT commercial_rules_produto_codigo_fkey FOREIGN KEY (produto_codigo) REFERENCES catalogo.produtos(codigo);

ALTER TABLE summit_2026.coupons ADD CONSTRAINT coupons_event_id_fkey FOREIGN KEY (event_id) REFERENCES summit_2026.events(id);

ALTER TABLE summit_2026.event_rules ADD CONSTRAINT event_rules_event_id_fkey FOREIGN KEY (event_id) REFERENCES summit_2026.events(id);

ALTER TABLE summit_2026.events ADD CONSTRAINT events_produto_codigo_fkey FOREIGN KEY (produto_codigo) REFERENCES catalogo.produtos(codigo);

ALTER TABLE summit_2026.exhibitors ADD CONSTRAINT exhibitors_event_id_fkey FOREIGN KEY (event_id) REFERENCES summit_2026.events(id) ON DELETE CASCADE;

ALTER TABLE summit_2026.exhibitors ADD CONSTRAINT exhibitors_location_id_fkey FOREIGN KEY (location_id) REFERENCES summit_2026.locations(id) ON DELETE SET NULL;

ALTER TABLE summit_2026.knowledge_chunks ADD CONSTRAINT knowledge_chunks_doc_fk FOREIGN KEY (doc_id) REFERENCES summit_2026.knowledge_documents(id) ON DELETE CASCADE;

ALTER TABLE summit_2026.locations ADD CONSTRAINT locations_event_id_fkey FOREIGN KEY (event_id) REFERENCES summit_2026.events(id);

ALTER TABLE summit_2026.locations ADD CONSTRAINT locations_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES summit_2026.locations(id) ON DELETE SET NULL;

ALTER TABLE summit_2026.locations ADD CONSTRAINT locations_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES summit_2026.venues(id) ON DELETE SET NULL;

ALTER TABLE summit_2026.offers ADD CONSTRAINT offers_event_id_fkey FOREIGN KEY (event_id) REFERENCES summit_2026.events(id) ON DELETE CASCADE;

ALTER TABLE summit_2026.registrations ADD CONSTRAINT registrations_event_id_fkey FOREIGN KEY (event_id) REFERENCES summit_2026.events(id) ON DELETE CASCADE;

ALTER TABLE summit_2026.registrations ADD CONSTRAINT registrations_person_id_fkey FOREIGN KEY (person_id) REFERENCES pessoas.pessoas(id) ON DELETE CASCADE;

ALTER TABLE summit_2026.route_edges ADD CONSTRAINT route_edges_destino_location_id_fkey FOREIGN KEY (destino_location_id) REFERENCES summit_2026.locations(id) ON DELETE CASCADE;

ALTER TABLE summit_2026.route_edges ADD CONSTRAINT route_edges_event_id_fkey FOREIGN KEY (event_id) REFERENCES summit_2026.events(id) ON DELETE CASCADE;

ALTER TABLE summit_2026.route_edges ADD CONSTRAINT route_edges_origem_location_id_fkey FOREIGN KEY (origem_location_id) REFERENCES summit_2026.locations(id) ON DELETE CASCADE;

ALTER TABLE summit_2026.session_speakers ADD CONSTRAINT agenda_sessao_palestrantes_sessao_id_fkey FOREIGN KEY (sessao_id) REFERENCES summit_2026.sessions(id) ON DELETE CASCADE;

ALTER TABLE summit_2026.session_speakers ADD CONSTRAINT session_speakers_speaker_id_fkey FOREIGN KEY (speaker_id) REFERENCES ecossistema.palestrantes_especialistas(id) ON DELETE SET NULL;

ALTER TABLE summit_2026.sessions ADD CONSTRAINT agenda_sessoes_espaco_id_fkey FOREIGN KEY (espaco_id) REFERENCES summit_2026.locations(id) ON DELETE SET NULL;

ALTER TABLE summit_2026.sessions ADD CONSTRAINT sessions_event_id_fkey FOREIGN KEY (event_id) REFERENCES summit_2026.events(id);

ALTER TABLE summit_2026.venues ADD CONSTRAINT venues_event_id_fkey FOREIGN KEY (event_id) REFERENCES summit_2026.events(id) ON DELETE CASCADE;

CREATE TRIGGER t_config_rev AFTER INSERT OR DELETE OR UPDATE ON concierge.config FOR EACH STATEMENT EXECUTE FUNCTION concierge.bump_config_revisao();

CREATE TRIGGER t_flags_rev AFTER INSERT OR DELETE OR UPDATE ON concierge.feature_flags FOR EACH STATEMENT EXECUTE FUNCTION concierge.bump_config_revisao();

CREATE TRIGGER t_ferramentas_rev AFTER INSERT OR DELETE OR UPDATE ON concierge.ferramentas FOR EACH STATEMENT EXECUTE FUNCTION concierge.bump_config_revisao();

CREATE TRIGGER t_prompts_rev AFTER INSERT OR DELETE OR UPDATE ON concierge.prompts FOR EACH STATEMENT EXECUTE FUNCTION concierge.bump_config_revisao();

CREATE TRIGGER t_templates_rev AFTER INSERT OR DELETE OR UPDATE ON concierge.templates FOR EACH STATEMENT EXECUTE FUNCTION concierge.bump_config_revisao();

CREATE TRIGGER participantes_normalizar BEFORE INSERT OR UPDATE ON credenciamento_summit_2026.participantes FOR EACH ROW EXECUTE FUNCTION credenciamento_summit_2026.normalizar_contato();

CREATE TRIGGER trg_palestrantes_slug BEFORE INSERT OR UPDATE ON ecossistema.palestrantes_especialistas FOR EACH ROW EXECUTE FUNCTION ecossistema.palestrantes_slug_bi();

CREATE TRIGGER ingressos_normalizar BEFORE INSERT OR UPDATE ON eduzz.ingressos FOR EACH ROW EXECUTE FUNCTION eduzz.normalizar_contato();

CREATE TRIGGER vendas_normalizar BEFORE INSERT OR UPDATE ON eduzz.vendas FOR EACH ROW EXECUTE FUNCTION eduzz.normalizar_contato();

CREATE TRIGGER conversas_normalizar_telefone BEFORE INSERT OR UPDATE OF telefone ON engagement.conversas FOR EACH ROW EXECUTE FUNCTION normalizar_telefone_trigger();

CREATE TRIGGER t_jornada AFTER INSERT ON engagement.jornada_eventos FOR EACH ROW EXECUTE FUNCTION concierge.aplicar_evento_jornada();

CREATE TRIGGER t_intencoes_rev AFTER INSERT OR DELETE OR UPDATE ON intelligence.intencoes FOR EACH STATEMENT EXECUTE FUNCTION concierge.bump_config_revisao();

CREATE TRIGGER pessoas_normalizar BEFORE INSERT OR UPDATE ON pessoas.pessoas FOR EACH ROW EXECUTE FUNCTION crm.normalizar_pessoa();

CREATE TRIGGER t_touch BEFORE UPDATE ON summit_2026.event_rules FOR EACH ROW EXECUTE FUNCTION mind.tocar();

CREATE TRIGGER t_touch BEFORE UPDATE ON summit_2026.events FOR EACH ROW EXECUTE FUNCTION mind.tocar();

CREATE TRIGGER t_touch BEFORE UPDATE ON summit_2026.locations FOR EACH ROW EXECUTE FUNCTION mind.tocar();

CREATE TRIGGER t_touch BEFORE UPDATE ON summit_2026.sessions FOR EACH ROW EXECUTE FUNCTION mind.tocar();

CREATE TRIGGER status_normalizar_telefone BEFORE INSERT OR UPDATE OF telefone ON treble.status_da_conversa FOR EACH ROW EXECUTE FUNCTION normalizar_telefone_trigger();

ALTER TABLE agentes.kit_blocos ENABLE ROW LEVEL SECURITY;

ALTER TABLE agentes.prompts ENABLE ROW LEVEL SECURITY;

ALTER TABLE concierge.ciclo_estado ENABLE ROW LEVEL SECURITY;

ALTER TABLE concierge.config ENABLE ROW LEVEL SECURITY;

ALTER TABLE concierge.config_auditoria ENABLE ROW LEVEL SECURITY;

ALTER TABLE concierge.config_revisao ENABLE ROW LEVEL SECURITY;

ALTER TABLE concierge.feature_flags ENABLE ROW LEVEL SECURITY;

ALTER TABLE concierge.ferramenta_chamadas ENABLE ROW LEVEL SECURITY;

ALTER TABLE concierge.ferramentas ENABLE ROW LEVEL SECURITY;

ALTER TABLE concierge.integracao_logs ENABLE ROW LEVEL SECURITY;

ALTER TABLE concierge.proativo_fila ENABLE ROW LEVEL SECURITY;

ALTER TABLE concierge.prompts ENABLE ROW LEVEL SECURITY;

ALTER TABLE concierge.regras_proativas ENABLE ROW LEVEL SECURITY;

ALTER TABLE concierge.templates ENABLE ROW LEVEL SECURITY;

ALTER TABLE concierge.tutorial_passos ENABLE ROW LEVEL SECURITY;

ALTER TABLE credenciamento_summit_2026.participantes ENABLE ROW LEVEL SECURITY;

ALTER TABLE credenciamento_summit_2026.yazo_envio_fila ENABLE ROW LEVEL SECURITY;

ALTER TABLE credenciamento_summit_2026.yazo_espelho ENABLE ROW LEVEL SECURITY;

ALTER TABLE credenciamento_summit_2026.yazo_sync_state ENABLE ROW LEVEL SECURITY;

ALTER TABLE crm.acessos ENABLE ROW LEVEL SECURITY;

ALTER TABLE crm.consents ENABLE ROW LEVEL SECURITY;

ALTER TABLE crm.mapa_produtos ENABLE ROW LEVEL SECURITY;

ALTER TABLE crm.pessoa_nps ENABLE ROW LEVEL SECURITY;

ALTER TABLE crm.pessoa_produtos ENABLE ROW LEVEL SECURITY;

ALTER TABLE crm.pessoas_interno ENABLE ROW LEVEL SECURITY;

ALTER TABLE crm.sync_estado ENABLE ROW LEVEL SECURITY;

ALTER TABLE eduzz.hubspot_stage_config ENABLE ROW LEVEL SECURITY;

ALTER TABLE eduzz.ingressos ENABLE ROW LEVEL SECURITY;

ALTER TABLE eduzz.produto_catalogo ENABLE ROW LEVEL SECURITY;

ALTER TABLE eduzz.produtos ENABLE ROW LEVEL SECURITY;

ALTER TABLE eduzz.vendas ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.agent_sessions ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.agente_eventos ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.avaliacao_execucoes ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.avaliacoes ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.contatos ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.conversas ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.data_requests ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.dispositivos ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.evento_feedback ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.feedbacks ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.identidade_fusoes ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.jornada_eventos ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.jornada_sessao ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.mensagens ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.nps ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.origens ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.sessao_feedback ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.session_interests ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.utm_sessoes ENABLE ROW LEVEL SECURITY;

ALTER TABLE engagement.verificacoes_email ENABLE ROW LEVEL SECURITY;

ALTER TABLE intelligence.acessos_dado_pessoal ENABLE ROW LEVEL SECURITY;

ALTER TABLE intelligence.dossies ENABLE ROW LEVEL SECURITY;

ALTER TABLE intelligence.intencoes ENABLE ROW LEVEL SECURITY;

ALTER TABLE intelligence.memoria_bloqueios ENABLE ROW LEVEL SECURITY;

ALTER TABLE intelligence.memoria_regras ENABLE ROW LEVEL SECURITY;

ALTER TABLE intelligence.participante_contexto ENABLE ROW LEVEL SECURITY;

ALTER TABLE intelligence.participante_memoria ENABLE ROW LEVEL SECURITY;

ALTER TABLE intelligence.participante_objetivos ENABLE ROW LEVEL SECURITY;

ALTER TABLE intelligence.perguntas_feitas ENABLE ROW LEVEL SECURITY;

ALTER TABLE intelligence.recomendacoes ENABLE ROW LEVEL SECURITY;

ALTER TABLE intelligence.sinais_comerciais ENABLE ROW LEVEL SECURITY;

ALTER TABLE mind.organization_content ENABLE ROW LEVEL SECURITY;

ALTER TABLE mind.policies ENABLE ROW LEVEL SECURITY;

ALTER TABLE pessoas.pessoas ENABLE ROW LEVEL SECURITY;

ALTER TABLE platform.embeddings_config ENABLE ROW LEVEL SECURITY;

ALTER TABLE platform.llm_calls ENABLE ROW LEVEL SECURITY;

ALTER TABLE platform.llm_models ENABLE ROW LEVEL SECURITY;

ALTER TABLE platform.llm_providers ENABLE ROW LEVEL SECURITY;

ALTER TABLE platform.llm_routes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.espelho_estado ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.mind_admin_audit ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.mind_admin_editorial ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.mind_admin_event_details ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.mind_admin_users ENABLE ROW LEVEL SECURITY;

ALTER TABLE summit_2026.commercial_rules ENABLE ROW LEVEL SECURITY;

ALTER TABLE summit_2026.coupons ENABLE ROW LEVEL SECURITY;

ALTER TABLE summit_2026.event_rules ENABLE ROW LEVEL SECURITY;

ALTER TABLE summit_2026.events ENABLE ROW LEVEL SECURITY;

ALTER TABLE summit_2026.exhibitors ENABLE ROW LEVEL SECURITY;

ALTER TABLE summit_2026.locations ENABLE ROW LEVEL SECURITY;

ALTER TABLE summit_2026.offers ENABLE ROW LEVEL SECURITY;

ALTER TABLE summit_2026.registrations ENABLE ROW LEVEL SECURITY;

ALTER TABLE summit_2026.route_edges ENABLE ROW LEVEL SECURITY;

ALTER TABLE summit_2026.session_speakers ENABLE ROW LEVEL SECURITY;

ALTER TABLE summit_2026.sessions ENABLE ROW LEVEL SECURITY;

ALTER TABLE summit_2026.venues ENABLE ROW LEVEL SECURITY;

ALTER TABLE treble.config ENABLE ROW LEVEL SECURITY;

CREATE POLICY so_eu ON crm.consents AS PERMISSIVE FOR ALL TO mind_agent USING ((participante_id = mind.pessoa_atual())) WITH CHECK ((participante_id = mind.pessoa_atual()));

CREATE POLICY so_meus ON engagement.contatos AS PERMISSIVE FOR SELECT TO mind_agent USING (((de = mind.pessoa_atual()) OR (para = mind.pessoa_atual())));

CREATE POLICY so_eu ON engagement.conversas AS PERMISSIVE FOR ALL TO mind_agent USING ((participante_id = mind.pessoa_atual())) WITH CHECK ((participante_id = mind.pessoa_atual()));

CREATE POLICY so_eu ON engagement.data_requests AS PERMISSIVE FOR ALL TO mind_agent USING ((participante_id = mind.pessoa_atual())) WITH CHECK ((participante_id = mind.pessoa_atual()));

CREATE POLICY so_eu ON engagement.jornada_eventos AS PERMISSIVE FOR ALL TO mind_agent USING ((participante_id = mind.pessoa_atual())) WITH CHECK ((participante_id = mind.pessoa_atual()));

CREATE POLICY so_eu ON engagement.jornada_sessao AS PERMISSIVE FOR ALL TO mind_agent USING ((participante_id = mind.pessoa_atual())) WITH CHECK ((participante_id = mind.pessoa_atual()));

CREATE POLICY so_eu ON engagement.mensagens AS PERMISSIVE FOR ALL TO mind_agent USING ((participante_id = mind.pessoa_atual())) WITH CHECK ((participante_id = mind.pessoa_atual()));

CREATE POLICY so_eu ON engagement.nps AS PERMISSIVE FOR ALL TO mind_agent USING ((participante_id = mind.pessoa_atual())) WITH CHECK ((participante_id = mind.pessoa_atual()));

CREATE POLICY so_eu ON engagement.sessao_feedback AS PERMISSIVE FOR ALL TO mind_agent USING ((participante_id = mind.pessoa_atual())) WITH CHECK ((participante_id = mind.pessoa_atual()));

CREATE POLICY so_eu ON intelligence.dossies AS PERMISSIVE FOR ALL TO mind_agent USING ((participante_id = mind.pessoa_atual())) WITH CHECK ((participante_id = mind.pessoa_atual()));

CREATE POLICY so_eu ON intelligence.participante_contexto AS PERMISSIVE FOR ALL TO mind_agent USING ((participante_id = mind.pessoa_atual())) WITH CHECK ((participante_id = mind.pessoa_atual()));

CREATE POLICY so_eu ON intelligence.participante_memoria AS PERMISSIVE FOR ALL TO mind_agent USING ((participante_id = mind.pessoa_atual())) WITH CHECK ((participante_id = mind.pessoa_atual()));

CREATE POLICY so_eu ON intelligence.participante_objetivos AS PERMISSIVE FOR ALL TO mind_agent USING ((participante_id = mind.pessoa_atual())) WITH CHECK ((participante_id = mind.pessoa_atual()));

CREATE POLICY so_eu ON intelligence.recomendacoes AS PERMISSIVE FOR ALL TO mind_agent USING ((participante_id = mind.pessoa_atual())) WITH CHECK ((participante_id = mind.pessoa_atual()));

CREATE POLICY leitura_publica ON mind.policies AS PERMISSIVE FOR SELECT TO mind_agent USING (true);

CREATE POLICY leitura_publica ON summit_2026.event_rules AS PERMISSIVE FOR SELECT TO mind_agent USING (true);

CREATE POLICY leitura_publica ON summit_2026.events AS PERMISSIVE FOR SELECT TO mind_agent USING (true);

CREATE POLICY leitura_publica ON summit_2026.locations AS PERMISSIVE FOR SELECT TO mind_agent USING (true);

CREATE POLICY so_eu ON summit_2026.registrations AS PERMISSIVE FOR ALL TO mind_agent USING ((person_id = mind.pessoa_atual())) WITH CHECK ((person_id = mind.pessoa_atual()));

CREATE POLICY leitura_publica ON summit_2026.session_speakers AS PERMISSIVE FOR SELECT TO mind_agent USING (true);

CREATE POLICY leitura_publica ON summit_2026.sessions AS PERMISSIVE FOR SELECT TO mind_agent USING (true);

REVOKE ALL ON SCHEMA api FROM PUBLIC;

REVOKE ALL ON SCHEMA concierge FROM PUBLIC;

REVOKE ALL ON SCHEMA credenciamento_summit_2026 FROM PUBLIC;

REVOKE ALL ON SCHEMA dash FROM PUBLIC;

REVOKE ALL ON SCHEMA ecossistema FROM PUBLIC;

REVOKE ALL ON SCHEMA eduzz FROM PUBLIC;

REVOKE ALL ON SCHEMA engagement FROM PUBLIC;

REVOKE ALL ON SCHEMA eventos FROM PUBLIC;

REVOKE ALL ON SCHEMA institute FROM PUBLIC;

REVOKE ALL ON SCHEMA intelligence FROM PUBLIC;

REVOKE ALL ON SCHEMA mind FROM PUBLIC;

REVOKE ALL ON SCHEMA platform FROM PUBLIC;

REVOKE ALL ON SCHEMA summit_2026 FROM PUBLIC;

REVOKE ALL ON FUNCTION api.mindagent_bootstrap(p_event_slug text) FROM PUBLIC;

REVOKE ALL ON FUNCTION api.treble_event_bundle(p_event_slug text) FROM PUBLIC;

REVOKE ALL ON FUNCTION api.treble_find_location(p_event_slug text, p_query text) FROM PUBLIC;

REVOKE ALL ON FUNCTION api.treble_route(p_event_slug text, p_from_slug text, p_to_slug text, p_accessible boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION crm.buscar_pessoa(p_email text, p_whatsapp text, p_agente text) FROM PUBLIC;

REVOKE ALL ON FUNCTION crm.contexto_comercial(p_email text, p_whatsapp text, p_agente text) FROM PUBLIC;

REVOKE ALL ON FUNCTION crm.registrar_lead(p_email text, p_whatsapp text, p_primeiro_nome text, p_sobrenome text, p_empresa text, p_cargo text, p_agente text, p_contexto jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION mind.esquecer_participante(p_participante uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.espelho_config() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.espelho_estado_set(p_fonte text, p_status text, p_total_origem integer, p_lidos integer, p_gravados integer, p_erro text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.espelho_gravar(p_fonte text, p_linhas jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_admin_dashboard_counts() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_admin_mutate_resource(p_action text, p_resource text, p_id uuid, p_payload jsonb, p_expected_updated_at text, p_actor_id uuid, p_request_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_admin_read_resource(p_resource text, p_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_agent_context(p_conversa_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_calendario(p_produto text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_checkout_url(p_url text, p_utm jsonb, p_origem text, p_conversa text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_conflito_registrar(p_pessoa uuid, p_tipo text, p_motivo text, p_outra uuid, p_evidencia jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_conteudo(p_produto text, p_tipo text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_conversa_estado(p_conversa_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_conversa_resolver(p_evento jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_crm_comercial(p_pessoa_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_crm_fatos(p_pessoa_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_crm_sync_frescor() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_crm_vincular_pessoa(p_pessoa_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_engagement_fatos(p_pessoa_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_espelho_carga_inicial() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_espelho_disparar() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_espelho_gravar(p_fonte text, p_registros jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_espelho_ligar() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_identidade_resolver(p_identificadores jsonb, p_nome text, p_canal text, p_pessoa_ancora uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_identificadores_normalizar(p_ids jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_inbound(p_evento jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_materiais_para(p_canal text, p_audiencia text, p_icp text, p_origem text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_material_link(p_url text, p_codigo text, p_utm_campaign text, p_canal text, p_origem text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_mensagem_registrar(p_conversa_id uuid, p_papel text, p_conteudo text, p_id_externo text, p_blocos jsonb, p_origem text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_nome_bate(p_nome text, p_sobrenome text, q_nome text, q_sobrenome text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_nome_conflita(p_nome text, p_sobrenome text, q_nome text, q_sobrenome text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_pendencia_resolver(p_id uuid, p_status text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_pendencias_listar(p_status text, p_tipo text, p_limite integer, p_offset integer) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_pessoa_completar(p_pessoa_id uuid, p_sobrenome text, p_empresa text, p_cargo text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_pessoa_fatos(p_pessoa_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_precos_por_volume() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_rota_capacidade(p_rota text, p_canal text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_sync_abrir(p_fonte text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_sync_marcar(p_fonte text, p_marca timestamp with time zone, p_lidos integer, p_gravados integer, p_status text, p_erro text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_sync_marcar(p_fonte text, p_marca timestamp with time zone, p_lidos integer, p_gravados integer, p_status text, p_erro text, p_cursor text, p_completou boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_turno_registrar(p_conversa_id uuid, p_resposta text, p_estado jsonb, p_meta jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mind_virada_de_lote() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mindagent_bootstrap(p_event_slug text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mindagent_chat_bind_identity(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text, p_email text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mindagent_chat_get_context(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mindagent_chat_save_interests(p_auth_user_id uuid, p_session_id uuid, p_token_hash text, p_interests jsonb, p_evidence_message_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mindagent_chat_save_message(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text, p_role text, p_content text, p_client_message_id text, p_blocks jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mindagent_chat_search(p_event_slug text, p_query text, p_limit integer) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mindagent_chat_start(p_auth_user_id uuid, p_device_key text, p_user_agent text, p_token_hash text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mindagent_sync_offers(p_vigente integer, p_lotes jsonb, p_tiers jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mindagent_treble_claim_event(p_event_key text, p_session_external_id text, p_request_id uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.mindagent_treble_complete_event(p_event_key text, p_status text, p_error_code text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.pessoa_vincular_hubspot(p_pessoa_id uuid, p_hubspot_id text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.treble_agent_config() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.treble_agent_context(p_audience text, p_origem text, p_utm jsonb, p_conversa text, p_produto text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.treble_agent_context_base() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.treble_agent_identificar(p_session_external_id text, p_email text, p_nome text, p_sobrenome text, p_mesma_pessoa boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.treble_agent_prompt(p_audience text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.treble_agent_resposta_repetida(p_conversation_id uuid, p_mensagem text, p_janela_segundos integer) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.treble_agent_start(p_session_external_id text, p_contact jsonb, p_origem text, p_utm_token text, p_mensagem jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.treble_agent_token() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.treble_find_location(p_event_slug text, p_query text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.treble_materiais(p_audience text, p_origem text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.treble_momento() FROM PUBLIC;

REVOKE ALL ON FUNCTION public.treble_sessao_backfill(p_poll_id text, p_sessions jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.treble_sessao_encerrada_gravar(p_payload jsonb) FROM PUBLIC;

REVOKE ALL ON SCHEMA agentes FROM anon, authenticated;

REVOKE ALL ON SCHEMA api FROM anon, authenticated;

REVOKE ALL ON SCHEMA catalogo FROM anon, authenticated;

REVOKE ALL ON SCHEMA concierge FROM anon, authenticated;

REVOKE ALL ON SCHEMA credenciamento_summit_2026 FROM anon, authenticated;

REVOKE ALL ON SCHEMA crm FROM anon, authenticated;

REVOKE ALL ON SCHEMA dash FROM anon, authenticated;

REVOKE ALL ON SCHEMA ecossistema FROM anon, authenticated;

REVOKE ALL ON SCHEMA eduzz FROM anon, authenticated;

REVOKE ALL ON SCHEMA engagement FROM anon, authenticated;

REVOKE ALL ON SCHEMA eventos FROM anon, authenticated;

REVOKE ALL ON SCHEMA institute FROM anon, authenticated;

REVOKE ALL ON SCHEMA intelligence FROM anon, authenticated;

REVOKE ALL ON SCHEMA mind FROM anon, authenticated;

REVOKE ALL ON SCHEMA pessoas FROM anon, authenticated;

REVOKE ALL ON SCHEMA platform FROM anon, authenticated;

REVOKE ALL ON SCHEMA public FROM anon, authenticated;

REVOKE ALL ON SCHEMA summit_2026 FROM anon, authenticated;

REVOKE ALL ON SCHEMA treble FROM anon, authenticated;

REVOKE ALL ON TABLE agentes.kit_blocos FROM anon, authenticated;

REVOKE ALL ON TABLE agentes.prompts FROM anon, authenticated;

REVOKE ALL ON TABLE catalogo.produtos FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.ciclo_estado FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.config FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.config_auditoria FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.config_revisao FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.feature_flags FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.ferramenta_chamadas FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.ferramentas FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.integracao_logs FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.proativo_fila FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.prompts FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.regras_proativas FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.templates FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.tutorial_passos FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.v_aderencia_por_area FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.v_funil_valor FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.v_operacao_agora FROM anon, authenticated;

REVOKE ALL ON TABLE concierge.v_sessoes_avaliadas FROM anon, authenticated;

REVOKE ALL ON TABLE credenciamento_summit_2026.participantes FROM anon, authenticated;

REVOKE ALL ON TABLE credenciamento_summit_2026.v_participantes FROM anon, authenticated;

REVOKE ALL ON TABLE credenciamento_summit_2026.yazo_envio_fila FROM anon, authenticated;

REVOKE ALL ON TABLE credenciamento_summit_2026.yazo_espelho FROM anon, authenticated;

REVOKE ALL ON TABLE credenciamento_summit_2026.yazo_sync_state FROM anon, authenticated;

REVOKE ALL ON TABLE crm.acessos FROM anon, authenticated;

REVOKE ALL ON SEQUENCE crm.acessos_id_seq FROM anon, authenticated;

REVOKE ALL ON TABLE crm.consents FROM anon, authenticated;

REVOKE ALL ON TABLE crm.contato_espelho FROM anon, authenticated;

REVOKE ALL ON TABLE crm.empenho_summit_2026 FROM anon, authenticated;

REVOKE ALL ON TABLE crm.leads_capturados FROM anon, authenticated;

REVOKE ALL ON TABLE crm.mapa_produtos FROM anon, authenticated;

REVOKE ALL ON TABLE crm.negocio_contatos FROM anon, authenticated;

REVOKE ALL ON TABLE crm.pessoa_nps FROM anon, authenticated;

REVOKE ALL ON TABLE crm.pessoa_produtos FROM anon, authenticated;

REVOKE ALL ON TABLE crm.pessoas_interno FROM anon, authenticated;

REVOKE ALL ON TABLE crm.pipeline_de_vendas_summit FROM anon, authenticated;

REVOKE ALL ON TABLE crm.pipeline_leads_inbound FROM anon, authenticated;

REVOKE ALL ON TABLE crm.status_summit_hs FROM anon, authenticated;

REVOKE ALL ON TABLE crm.sync_estado FROM anon, authenticated;

REVOKE ALL ON TABLE crm.vendas_historicas_mind_summit FROM anon, authenticated;

REVOKE ALL ON TABLE dash.knowledge_chunks FROM anon, authenticated;

REVOKE ALL ON TABLE dash.knowledge_documents FROM anon, authenticated;

REVOKE ALL ON TABLE ecossistema.palestrantes_especialistas FROM anon, authenticated;

REVOKE ALL ON SEQUENCE ecossistema.palestrantes_especialistas_id_seq FROM anon, authenticated;

REVOKE ALL ON TABLE eduzz.hubspot_stage_config FROM anon, authenticated;

REVOKE ALL ON TABLE eduzz.ingressos FROM anon, authenticated;

REVOKE ALL ON TABLE eduzz.produto_catalogo FROM anon, authenticated;

REVOKE ALL ON TABLE eduzz.produtos FROM anon, authenticated;

REVOKE ALL ON TABLE eduzz.v_ingressos FROM anon, authenticated;

REVOKE ALL ON TABLE eduzz.v_vendas FROM anon, authenticated;

REVOKE ALL ON TABLE eduzz.vendas FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.agent_sessions FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.agente_eventos FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.avaliacao_execucoes FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.avaliacoes FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.contatos FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.conversas FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.data_requests FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.dispositivos FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.evento_feedback FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.feedbacks FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.identidade_fusoes FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.identidades FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.janela_24h FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.jornada_eventos FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.jornada_sessao FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.mensagens FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.nps FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.origens FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.pessoa_perfil FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.sessao_feedback FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.session_interests FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.treble_eventos FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.utm_sessoes FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.v_pessoa FROM anon, authenticated;

REVOKE ALL ON TABLE engagement.verificacoes_email FROM anon, authenticated;

REVOKE ALL ON TABLE eventos.knowledge_chunks FROM anon, authenticated;

REVOKE ALL ON TABLE eventos.knowledge_documents FROM anon, authenticated;

REVOKE ALL ON TABLE institute.knowledge_chunks FROM anon, authenticated;

REVOKE ALL ON TABLE institute.knowledge_documents FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.acessos_dado_pessoal FROM anon, authenticated;

REVOKE ALL ON SEQUENCE intelligence.acessos_dado_pessoal_id_seq FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.analise_conversa FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.config FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.continuidade_comercial FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.dossies FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.intencoes FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.memoria_bloqueios FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.memoria_regras FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.participante_contexto FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.participante_memoria FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.participante_objetivos FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.perguntas_feitas FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.recomendacoes FROM anon, authenticated;

REVOKE ALL ON TABLE intelligence.sinais_comerciais FROM anon, authenticated;

REVOKE ALL ON TABLE mind.organization_content FROM anon, authenticated;

REVOKE ALL ON TABLE mind.policies FROM anon, authenticated;

REVOKE ALL ON TABLE mind.produtos FROM anon, authenticated;

REVOKE ALL ON TABLE pessoas.pessoas FROM anon, authenticated;

REVOKE ALL ON TABLE platform.embeddings_config FROM anon, authenticated;

REVOKE ALL ON TABLE platform.integracoes FROM anon, authenticated;

REVOKE ALL ON TABLE platform.llm_calls FROM anon, authenticated;

REVOKE ALL ON TABLE platform.llm_models FROM anon, authenticated;

REVOKE ALL ON TABLE platform.llm_providers FROM anon, authenticated;

REVOKE ALL ON TABLE platform.llm_routes FROM anon, authenticated;

REVOKE ALL ON TABLE public.espelho_estado FROM anon, authenticated;

REVOKE ALL ON TABLE public.mind_admin_audit FROM anon, authenticated;

REVOKE ALL ON TABLE public.mind_admin_editorial FROM anon, authenticated;

REVOKE ALL ON TABLE public.mind_admin_event_details FROM anon, authenticated;

REVOKE ALL ON TABLE public.mind_admin_users FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.commercial_rules FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.coupons FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.event_rules FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.events FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.exhibitors FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.experiencias FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.knowledge_chunks FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.knowledge_documents FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.locations FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.offers FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.registrations FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.route_edges FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.session_speakers FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.sessions FROM anon, authenticated;

REVOKE ALL ON TABLE summit_2026.venues FROM anon, authenticated;

REVOKE ALL ON TABLE treble.config FROM anon, authenticated;

REVOKE ALL ON TABLE treble.polls FROM anon, authenticated;

REVOKE ALL ON TABLE treble.status_da_conversa FROM anon, authenticated;

REVOKE ALL ON TABLE treble.status_hs_contatos FROM anon, authenticated;

REVOKE ALL ON TABLE treble.status_hs_leads FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.changed_since(p_desde timestamp with time zone) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.contact(p_token text, p_nome text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.event(p_slug text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.knowledge(p_pergunta text, p_embedding vector, p_agent text, p_limit integer) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.me(p_token text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.mindagent_bootstrap(p_event_slug text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.my_agenda(p_token text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.my_context(p_token text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.my_data(p_token text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.quem_sou(p_token text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.sessions(p_event text, p_dia date, p_tema text, p_limit integer) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.speakers(p_event text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.treble_event_bundle(p_event_slug text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.treble_find_location(p_event_slug text, p_query text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION api.treble_route(p_event_slug text, p_from_slug text, p_to_slug text, p_accessible boolean) FROM anon, authenticated;

REVOKE ALL ON FUNCTION concierge.aplicar_evento_jornada() FROM anon, authenticated;

REVOKE ALL ON FUNCTION concierge.bump_config_revisao() FROM anon, authenticated;

REVOKE ALL ON FUNCTION concierge.resumo_do_dia(p_participante uuid, p_dia date) FROM anon, authenticated;

REVOKE ALL ON FUNCTION credenciamento_summit_2026.normalizar_contato() FROM anon, authenticated;

REVOKE ALL ON FUNCTION crm.buscar_pessoa(p_email text, p_whatsapp text, p_agente text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION crm.contexto_comercial(p_email text, p_whatsapp text, p_agente text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION crm.normalizar_pessoa() FROM anon, authenticated;

REVOKE ALL ON FUNCTION crm.registrar_lead(p_email text, p_whatsapp text, p_primeiro_nome text, p_sobrenome text, p_empresa text, p_cargo text, p_agente text, p_contexto jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION ecossistema.palestrantes_slug_bi() FROM anon, authenticated;

REVOKE ALL ON FUNCTION ecossistema.slugify(txt text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION eduzz.normalizar_contato() FROM anon, authenticated;

REVOKE ALL ON FUNCTION intelligence.vertical_da_entrada(p_site text, p_url text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION mind.esquecer_participante(p_participante uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION mind.pessoa_atual() FROM anon, authenticated;

REVOKE ALL ON FUNCTION mind.tocar() FROM anon, authenticated;

REVOKE ALL ON FUNCTION pessoas.resolver_por_telefone(p_tel text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.analise_config() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.analise_gravar(p_conversa_id uuid, p_analisador text, p_funcao text, p_vertical text, p_dados jsonb, p_modelo text, p_prompt_versao integer) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.analise_montar_contexto(p_conversa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.analise_pendentes(p_limite integer) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.analise_projetar_memoria(p_participante uuid, p_analisador text, p_memorias jsonb, p_analise_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.analise_prompt(p_chave text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.espelho_config() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.espelho_estado_set(p_fonte text, p_status text, p_total_origem integer, p_lidos integer, p_gravados integer, p_erro text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.espelho_gravar(p_fonte text, p_linhas jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_admin_dashboard_counts() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_admin_mutate_resource(p_action text, p_resource text, p_id uuid, p_payload jsonb, p_expected_updated_at text, p_actor_id uuid, p_request_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_admin_read_resource(p_resource text, p_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_agent_context(p_conversa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_calendario(p_produto text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_checkout_url(p_url text, p_utm jsonb, p_origem text, p_conversa text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_conflito_registrar(p_pessoa uuid, p_tipo text, p_motivo text, p_outra uuid, p_evidencia jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_conteudo(p_produto text, p_tipo text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_conversa_estado(p_conversa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_conversa_resolver(p_evento jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_crm_comercial(p_pessoa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_crm_fatos(p_pessoa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_crm_sync_frescor() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_crm_vincular_pessoa(p_pessoa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_engagement_fatos(p_pessoa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_espelho_carga_inicial() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_espelho_disparar() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_espelho_gravar(p_fonte text, p_registros jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_espelho_ligar() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_foto_url(p_asset_path text, p_fallback text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_identidade_resolver(p_identificadores jsonb, p_nome text, p_canal text, p_pessoa_ancora uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_identificadores_normalizar(p_ids jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_inbound(p_evento jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_materiais_para(p_canal text, p_audiencia text, p_icp text, p_origem text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_material_link(p_url text, p_codigo text, p_utm_campaign text, p_canal text, p_origem text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_mensagem_registrar(p_conversa_id uuid, p_papel text, p_conteudo text, p_id_externo text, p_blocos jsonb, p_origem text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_nome_bate(p_nome text, p_sobrenome text, q_nome text, q_sobrenome text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_nome_conflita(p_nome text, p_sobrenome text, q_nome text, q_sobrenome text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_nome_simples(p text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_origem(p_codigo text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_pendencia_resolver(p_id uuid, p_status text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_pendencias_listar(p_status text, p_tipo text, p_limite integer, p_offset integer) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_pessoa_completar(p_pessoa_id uuid, p_sobrenome text, p_empresa text, p_cargo text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_pessoa_fatos(p_pessoa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_precos_por_volume() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_rota_capacidade(p_rota text, p_canal text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_slug(p_texto text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_sync_abrir(p_fonte text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_sync_marcar(p_fonte text, p_marca timestamp with time zone, p_lidos integer, p_gravados integer, p_status text, p_erro text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_sync_marcar(p_fonte text, p_marca timestamp with time zone, p_lidos integer, p_gravados integer, p_status text, p_erro text, p_cursor text, p_completou boolean) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_turno_registrar(p_conversa_id uuid, p_resposta text, p_estado jsonb, p_meta jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_urlencode(p text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_utm_registrar(p_dados jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mind_virada_de_lote() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mindagent_bootstrap(p_event_slug text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mindagent_chat_bind_identity(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text, p_email text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mindagent_chat_get_context(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mindagent_chat_save_interests(p_auth_user_id uuid, p_session_id uuid, p_token_hash text, p_interests jsonb, p_evidence_message_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mindagent_chat_save_message(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text, p_role text, p_content text, p_client_message_id text, p_blocks jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mindagent_chat_search(p_event_slug text, p_query text, p_limit integer) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mindagent_chat_start(p_auth_user_id uuid, p_device_key text, p_user_agent text, p_token_hash text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mindagent_sync_offers(p_vigente integer, p_lotes jsonb, p_tiers jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mindagent_treble_claim_event(p_event_key text, p_session_external_id text, p_request_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.mindagent_treble_complete_event(p_event_key text, p_status text, p_error_code text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.normalizar_telefone_trigger() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.pessoa_vincular_hubspot(p_pessoa_id uuid, p_hubspot_id text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.silence_calcular_next_review(p_conversa_id uuid, p_dados jsonb, p_followup_count integer, p_last_followup_at timestamp with time zone, p_action text, p_piso timestamp with time zone) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.silence_chave_timing(p_dados jsonb, p_pos_followup boolean) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.silence_claim_pendentes(p_limite integer) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.silence_compra_summit_2026(p_conversa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.silence_liberar_lock(p_conversa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.silence_montar_contexto(p_conversa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.silence_registrar_decisao(p_conversa_id uuid, p_decisao jsonb, p_followup_enviado boolean) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.silence_sync_from_analysis(p_analise_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.silence_ts(p_texto text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.silence_ultimo_evento(p_conversa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.summit_contato_criar_pendentes(p_limit integer) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.summit_motivo_exclusao(p_conversa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.summit_status_confirmar(p_pares jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.summit_status_pendentes(p_limit integer) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.telefone_normalizar(p_tel text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_agent_config() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_agent_context(p_audience text, p_origem text, p_utm jsonb, p_conversa text, p_produto text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_agent_context_base() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_agent_identificar(p_session_external_id text, p_email text, p_nome text, p_sobrenome text, p_mesma_pessoa boolean) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_agent_prompt(p_audience text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_agent_resposta_repetida(p_conversation_id uuid, p_mensagem text, p_janela_segundos integer) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_agent_start(p_session_external_id text, p_contact jsonb, p_origem text, p_utm_token text, p_mensagem jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_agent_token() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_cta_da_conversa(p_conversa_id uuid) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_evento_gravar(p_payload jsonb, p_tipo text, p_direcao text, p_telefone text, p_ocorreu_em timestamp with time zone) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_find_location(p_event_slug text, p_query text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_materiais(p_audience text, p_origem text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_momento() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_origem_da_cta(p_cta text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_poll_sincronizado(p_poll_id text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_sessao_backfill(p_poll_id text, p_sessions jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_sessao_encerrada_gravar(p_payload jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_status_ciclo() FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_status_confirmar(p_pares jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_status_confirmar_contato(p_pares jsonb) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_status_marcar(p_telefone text, p_status text, p_quando timestamp with time zone, p_session_external_id text) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_status_pendentes(p_limit integer) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_status_pendentes_contato(p_limit integer) FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.treble_status_recompute() FROM anon, authenticated;

GRANT USAGE ON SCHEMA api TO anon;

GRANT USAGE ON SCHEMA api TO authenticated;

GRANT USAGE ON SCHEMA api TO mind_agent;

GRANT CREATE, USAGE ON SCHEMA api TO postgres;

GRANT USAGE ON SCHEMA api TO service_role;

GRANT USAGE ON SCHEMA concierge TO mind_agent;

GRANT CREATE, USAGE ON SCHEMA concierge TO postgres;

GRANT CREATE, USAGE ON SCHEMA credenciamento_summit_2026 TO postgres;

GRANT USAGE ON SCHEMA credenciamento_summit_2026 TO service_role;

GRANT USAGE ON SCHEMA dash TO mind_agent;

GRANT CREATE, USAGE ON SCHEMA dash TO postgres;

GRANT USAGE ON SCHEMA ecossistema TO mind_agent;

GRANT CREATE, USAGE ON SCHEMA ecossistema TO postgres;

GRANT CREATE, USAGE ON SCHEMA eduzz TO postgres;

GRANT USAGE ON SCHEMA eduzz TO service_role;

GRANT USAGE ON SCHEMA engagement TO mind_agent;

GRANT CREATE, USAGE ON SCHEMA engagement TO postgres;

GRANT USAGE ON SCHEMA eventos TO mind_agent;

GRANT CREATE, USAGE ON SCHEMA eventos TO postgres;

GRANT USAGE ON SCHEMA institute TO mind_agent;

GRANT CREATE, USAGE ON SCHEMA institute TO postgres;

GRANT USAGE ON SCHEMA intelligence TO mind_agent;

GRANT CREATE, USAGE ON SCHEMA intelligence TO postgres;

GRANT USAGE ON SCHEMA mind TO mind_agent;

GRANT CREATE, USAGE ON SCHEMA mind TO postgres;

GRANT CREATE, USAGE ON SCHEMA platform TO postgres;

GRANT USAGE ON SCHEMA public TO PUBLIC;

GRANT CREATE, USAGE ON SCHEMA public TO pg_database_owner;

GRANT USAGE ON SCHEMA public TO postgres;

GRANT USAGE ON SCHEMA public TO service_role;

GRANT USAGE ON SCHEMA summit_2026 TO mind_agent;

GRANT CREATE, USAGE ON SCHEMA summit_2026 TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE agentes.kit_blocos TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.ciclo_estado TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.ciclo_estado TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.config TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.config TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.config_auditoria TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.config_auditoria TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.config_revisao TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.config_revisao TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.feature_flags TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.feature_flags TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.ferramenta_chamadas TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.ferramenta_chamadas TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.ferramentas TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.ferramentas TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.integracao_logs TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.integracao_logs TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.proativo_fila TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.proativo_fila TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.prompts TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.prompts TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.regras_proativas TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.regras_proativas TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.templates TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.templates TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.tutorial_passos TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.tutorial_passos TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.v_aderencia_por_area TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.v_aderencia_por_area TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.v_operacao_agora TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.v_operacao_agora TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.v_sessoes_avaliadas TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE concierge.v_sessoes_avaliadas TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE credenciamento_summit_2026.participantes TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE credenciamento_summit_2026.participantes TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE credenciamento_summit_2026.v_participantes TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE credenciamento_summit_2026.v_participantes TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE credenciamento_summit_2026.yazo_envio_fila TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE credenciamento_summit_2026.yazo_envio_fila TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE credenciamento_summit_2026.yazo_espelho TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE credenciamento_summit_2026.yazo_espelho TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE credenciamento_summit_2026.yazo_sync_state TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE credenciamento_summit_2026.yazo_sync_state TO service_role;

GRANT INSERT, SELECT, UPDATE ON TABLE crm.consents TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE crm.consents TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE crm.consents TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE dash.knowledge_chunks TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE dash.knowledge_chunks TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE dash.knowledge_documents TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE dash.knowledge_documents TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE eduzz.hubspot_stage_config TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE eduzz.hubspot_stage_config TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE eduzz.ingressos TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE eduzz.ingressos TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE eduzz.produto_catalogo TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE eduzz.produto_catalogo TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE eduzz.produtos TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE eduzz.produtos TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE eduzz.v_ingressos TO postgres;

GRANT SELECT ON TABLE eduzz.v_ingressos TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE eduzz.v_vendas TO postgres;

GRANT SELECT ON TABLE eduzz.v_vendas TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE eduzz.vendas TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE eduzz.vendas TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.agent_sessions TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.agent_sessions TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.agent_sessions TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.agente_eventos TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.agente_eventos TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.agente_eventos TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.avaliacao_execucoes TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.avaliacao_execucoes TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.avaliacoes TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.avaliacoes TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.contatos TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.contatos TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.conversas TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.conversas TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.conversas TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.data_requests TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.data_requests TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.data_requests TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.dispositivos TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.dispositivos TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.dispositivos TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.evento_feedback TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.evento_feedback TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.evento_feedback TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.feedbacks TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.feedbacks TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.feedbacks TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.identidade_fusoes TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.identidade_fusoes TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.identidade_fusoes TO service_role;

GRANT SELECT ON TABLE engagement.identidades TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.identidades TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.jornada_eventos TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.jornada_eventos TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.jornada_eventos TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.jornada_sessao TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.jornada_sessao TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.jornada_sessao TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.mensagens TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.mensagens TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.mensagens TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.nps TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.nps TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.nps TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.origens TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.origens TO postgres;

GRANT SELECT ON TABLE engagement.pessoa_perfil TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.pessoa_perfil TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.sessao_feedback TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.sessao_feedback TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.sessao_feedback TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.session_interests TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.session_interests TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.session_interests TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.utm_sessoes TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.utm_sessoes TO postgres;

GRANT SELECT ON TABLE engagement.v_pessoa TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.v_pessoa TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE engagement.verificacoes_email TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.verificacoes_email TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE engagement.verificacoes_email TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE eventos.knowledge_chunks TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE eventos.knowledge_chunks TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE eventos.knowledge_documents TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE eventos.knowledge_documents TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE institute.knowledge_chunks TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE institute.knowledge_chunks TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE institute.knowledge_documents TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE institute.knowledge_documents TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE intelligence.acessos_dado_pessoal TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.acessos_dado_pessoal TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE intelligence.dossies TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.dossies TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.dossies TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.intencoes TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.intencoes TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE intelligence.memoria_bloqueios TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.memoria_bloqueios TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.memoria_bloqueios TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE intelligence.memoria_regras TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.memoria_regras TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.memoria_regras TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE intelligence.participante_contexto TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.participante_contexto TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.participante_contexto TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE intelligence.participante_memoria TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.participante_memoria TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.participante_memoria TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE intelligence.participante_objetivos TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.participante_objetivos TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.participante_objetivos TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE intelligence.perguntas_feitas TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.perguntas_feitas TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.perguntas_feitas TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE intelligence.recomendacoes TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.recomendacoes TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.recomendacoes TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE intelligence.sinais_comerciais TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.sinais_comerciais TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE intelligence.sinais_comerciais TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE mind.organization_content TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE mind.organization_content TO service_role;

GRANT SELECT ON TABLE mind.policies TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE mind.policies TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE mind.policies TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE pessoas.pessoas TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE platform.embeddings_config TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE platform.embeddings_config TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE platform.integracoes TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE platform.llm_calls TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE platform.llm_calls TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE platform.llm_models TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE platform.llm_models TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE platform.llm_providers TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE platform.llm_providers TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE platform.llm_routes TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE platform.llm_routes TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.espelho_estado TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.espelho_estado TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.mind_admin_audit TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.mind_admin_audit TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.mind_admin_editorial TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.mind_admin_editorial TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.mind_admin_event_details TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.mind_admin_event_details TO service_role;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.mind_admin_users TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE public.mind_admin_users TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.commercial_rules TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.commercial_rules TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.coupons TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.coupons TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.event_rules TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.event_rules TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.event_rules TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.events TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.events TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.exhibitors TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.exhibitors TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.exhibitors TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.knowledge_chunks TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.knowledge_chunks TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.knowledge_documents TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.knowledge_documents TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.locations TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.locations TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.locations TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.offers TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.offers TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.offers TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.registrations TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.registrations TO postgres;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.route_edges TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.route_edges TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.route_edges TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.session_speakers TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.session_speakers TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.session_speakers TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.sessions TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.sessions TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.sessions TO service_role;

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE summit_2026.venues TO mind_agent;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.venues TO postgres;

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE summit_2026.venues TO service_role;

GRANT EXECUTE ON FUNCTION api.changed_since(p_desde timestamp with time zone) TO PUBLIC;

GRANT EXECUTE ON FUNCTION api.changed_since(p_desde timestamp with time zone) TO mind_agent;

GRANT EXECUTE ON FUNCTION api.changed_since(p_desde timestamp with time zone) TO postgres;

GRANT EXECUTE ON FUNCTION api.event(p_slug text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION api.event(p_slug text) TO mind_agent;

GRANT EXECUTE ON FUNCTION api.event(p_slug text) TO postgres;

GRANT EXECUTE ON FUNCTION api.knowledge(p_pergunta text, p_embedding vector, p_agent text, p_limit integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION api.knowledge(p_pergunta text, p_embedding vector, p_agent text, p_limit integer) TO mind_agent;

GRANT EXECUTE ON FUNCTION api.knowledge(p_pergunta text, p_embedding vector, p_agent text, p_limit integer) TO postgres;

GRANT EXECUTE ON FUNCTION api.me(p_token text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION api.me(p_token text) TO mind_agent;

GRANT EXECUTE ON FUNCTION api.me(p_token text) TO postgres;

GRANT EXECUTE ON FUNCTION api.mindagent_bootstrap(p_event_slug text) TO anon;

GRANT EXECUTE ON FUNCTION api.mindagent_bootstrap(p_event_slug text) TO authenticated;

GRANT EXECUTE ON FUNCTION api.mindagent_bootstrap(p_event_slug text) TO postgres;

GRANT EXECUTE ON FUNCTION api.mindagent_bootstrap(p_event_slug text) TO service_role;

GRANT EXECUTE ON FUNCTION api.my_agenda(p_token text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION api.my_agenda(p_token text) TO mind_agent;

GRANT EXECUTE ON FUNCTION api.my_agenda(p_token text) TO postgres;

GRANT EXECUTE ON FUNCTION api.my_context(p_token text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION api.my_context(p_token text) TO mind_agent;

GRANT EXECUTE ON FUNCTION api.my_context(p_token text) TO postgres;

GRANT EXECUTE ON FUNCTION api.my_data(p_token text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION api.my_data(p_token text) TO mind_agent;

GRANT EXECUTE ON FUNCTION api.my_data(p_token text) TO postgres;

GRANT EXECUTE ON FUNCTION api.quem_sou(p_token text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION api.quem_sou(p_token text) TO mind_agent;

GRANT EXECUTE ON FUNCTION api.quem_sou(p_token text) TO postgres;

GRANT EXECUTE ON FUNCTION api.sessions(p_event text, p_dia date, p_tema text, p_limit integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION api.sessions(p_event text, p_dia date, p_tema text, p_limit integer) TO mind_agent;

GRANT EXECUTE ON FUNCTION api.sessions(p_event text, p_dia date, p_tema text, p_limit integer) TO postgres;

GRANT EXECUTE ON FUNCTION api.speakers(p_event text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION api.speakers(p_event text) TO mind_agent;

GRANT EXECUTE ON FUNCTION api.speakers(p_event text) TO postgres;

GRANT EXECUTE ON FUNCTION api.treble_event_bundle(p_event_slug text) TO anon;

GRANT EXECUTE ON FUNCTION api.treble_event_bundle(p_event_slug text) TO authenticated;

GRANT EXECUTE ON FUNCTION api.treble_event_bundle(p_event_slug text) TO postgres;

GRANT EXECUTE ON FUNCTION api.treble_event_bundle(p_event_slug text) TO service_role;

GRANT EXECUTE ON FUNCTION api.treble_find_location(p_event_slug text, p_query text) TO anon;

GRANT EXECUTE ON FUNCTION api.treble_find_location(p_event_slug text, p_query text) TO authenticated;

GRANT EXECUTE ON FUNCTION api.treble_find_location(p_event_slug text, p_query text) TO postgres;

GRANT EXECUTE ON FUNCTION api.treble_find_location(p_event_slug text, p_query text) TO service_role;

GRANT EXECUTE ON FUNCTION api.treble_route(p_event_slug text, p_from_slug text, p_to_slug text, p_accessible boolean) TO anon;

GRANT EXECUTE ON FUNCTION api.treble_route(p_event_slug text, p_from_slug text, p_to_slug text, p_accessible boolean) TO authenticated;

GRANT EXECUTE ON FUNCTION api.treble_route(p_event_slug text, p_from_slug text, p_to_slug text, p_accessible boolean) TO postgres;

GRANT EXECUTE ON FUNCTION api.treble_route(p_event_slug text, p_from_slug text, p_to_slug text, p_accessible boolean) TO service_role;

GRANT EXECUTE ON FUNCTION concierge.aplicar_evento_jornada() TO PUBLIC;

GRANT EXECUTE ON FUNCTION concierge.aplicar_evento_jornada() TO postgres;

GRANT EXECUTE ON FUNCTION concierge.aplicar_evento_jornada() TO service_role;

GRANT EXECUTE ON FUNCTION concierge.bump_config_revisao() TO PUBLIC;

GRANT EXECUTE ON FUNCTION concierge.bump_config_revisao() TO postgres;

GRANT EXECUTE ON FUNCTION concierge.bump_config_revisao() TO service_role;

GRANT EXECUTE ON FUNCTION concierge.resumo_do_dia(p_participante uuid, p_dia date) TO PUBLIC;

GRANT EXECUTE ON FUNCTION concierge.resumo_do_dia(p_participante uuid, p_dia date) TO postgres;

GRANT EXECUTE ON FUNCTION concierge.resumo_do_dia(p_participante uuid, p_dia date) TO service_role;

GRANT EXECUTE ON FUNCTION crm.buscar_pessoa(p_email text, p_whatsapp text, p_agente text) TO postgres;

GRANT EXECUTE ON FUNCTION crm.contexto_comercial(p_email text, p_whatsapp text, p_agente text) TO postgres;

GRANT EXECUTE ON FUNCTION crm.registrar_lead(p_email text, p_whatsapp text, p_primeiro_nome text, p_sobrenome text, p_empresa text, p_cargo text, p_agente text, p_contexto jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION mind.esquecer_participante(p_participante uuid) TO postgres;

GRANT EXECUTE ON FUNCTION mind.esquecer_participante(p_participante uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.analise_config() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.analise_config() TO postgres;

GRANT EXECUTE ON FUNCTION public.analise_config() TO service_role;

GRANT EXECUTE ON FUNCTION public.analise_gravar(p_conversa_id uuid, p_analisador text, p_funcao text, p_vertical text, p_dados jsonb, p_modelo text, p_prompt_versao integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.analise_gravar(p_conversa_id uuid, p_analisador text, p_funcao text, p_vertical text, p_dados jsonb, p_modelo text, p_prompt_versao integer) TO postgres;

GRANT EXECUTE ON FUNCTION public.analise_gravar(p_conversa_id uuid, p_analisador text, p_funcao text, p_vertical text, p_dados jsonb, p_modelo text, p_prompt_versao integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.analise_montar_contexto(p_conversa_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.analise_montar_contexto(p_conversa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.analise_montar_contexto(p_conversa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.analise_pendentes(p_limite integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.analise_pendentes(p_limite integer) TO postgres;

GRANT EXECUTE ON FUNCTION public.analise_pendentes(p_limite integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.analise_projetar_memoria(p_participante uuid, p_analisador text, p_memorias jsonb, p_analise_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.analise_projetar_memoria(p_participante uuid, p_analisador text, p_memorias jsonb, p_analise_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.analise_projetar_memoria(p_participante uuid, p_analisador text, p_memorias jsonb, p_analise_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.analise_prompt(p_chave text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.analise_prompt(p_chave text) TO postgres;

GRANT EXECUTE ON FUNCTION public.analise_prompt(p_chave text) TO service_role;

GRANT EXECUTE ON FUNCTION public.espelho_config() TO postgres;

GRANT EXECUTE ON FUNCTION public.espelho_config() TO service_role;

GRANT EXECUTE ON FUNCTION public.espelho_estado_set(p_fonte text, p_status text, p_total_origem integer, p_lidos integer, p_gravados integer, p_erro text) TO postgres;

GRANT EXECUTE ON FUNCTION public.espelho_estado_set(p_fonte text, p_status text, p_total_origem integer, p_lidos integer, p_gravados integer, p_erro text) TO service_role;

GRANT EXECUTE ON FUNCTION public.espelho_gravar(p_fonte text, p_linhas jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.espelho_gravar(p_fonte text, p_linhas jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_admin_dashboard_counts() TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_admin_dashboard_counts() TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_admin_mutate_resource(p_action text, p_resource text, p_id uuid, p_payload jsonb, p_expected_updated_at text, p_actor_id uuid, p_request_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_admin_mutate_resource(p_action text, p_resource text, p_id uuid, p_payload jsonb, p_expected_updated_at text, p_actor_id uuid, p_request_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_admin_read_resource(p_resource text, p_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_admin_read_resource(p_resource text, p_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_agent_context(p_conversa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_agent_context(p_conversa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_calendario(p_produto text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_calendario(p_produto text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_checkout_url(p_url text, p_utm jsonb, p_origem text, p_conversa text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_checkout_url(p_url text, p_utm jsonb, p_origem text, p_conversa text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_conflito_registrar(p_pessoa uuid, p_tipo text, p_motivo text, p_outra uuid, p_evidencia jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_conflito_registrar(p_pessoa uuid, p_tipo text, p_motivo text, p_outra uuid, p_evidencia jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_conteudo(p_produto text, p_tipo text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_conteudo(p_produto text, p_tipo text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_conversa_estado(p_conversa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_conversa_estado(p_conversa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_conversa_resolver(p_evento jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_conversa_resolver(p_evento jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_crm_comercial(p_pessoa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_crm_comercial(p_pessoa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_crm_fatos(p_pessoa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_crm_fatos(p_pessoa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_crm_sync_frescor() TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_crm_sync_frescor() TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_crm_vincular_pessoa(p_pessoa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_crm_vincular_pessoa(p_pessoa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_engagement_fatos(p_pessoa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_engagement_fatos(p_pessoa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_espelho_carga_inicial() TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_espelho_carga_inicial() TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_espelho_disparar() TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_espelho_disparar() TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_espelho_gravar(p_fonte text, p_registros jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_espelho_gravar(p_fonte text, p_registros jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_espelho_ligar() TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_espelho_ligar() TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_foto_url(p_asset_path text, p_fallback text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.mind_foto_url(p_asset_path text, p_fallback text) TO anon;

GRANT EXECUTE ON FUNCTION public.mind_foto_url(p_asset_path text, p_fallback text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.mind_foto_url(p_asset_path text, p_fallback text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_foto_url(p_asset_path text, p_fallback text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_identidade_resolver(p_identificadores jsonb, p_nome text, p_canal text, p_pessoa_ancora uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_identidade_resolver(p_identificadores jsonb, p_nome text, p_canal text, p_pessoa_ancora uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_identificadores_normalizar(p_ids jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_identificadores_normalizar(p_ids jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_inbound(p_evento jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_inbound(p_evento jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_materiais_para(p_canal text, p_audiencia text, p_icp text, p_origem text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_materiais_para(p_canal text, p_audiencia text, p_icp text, p_origem text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_material_link(p_url text, p_codigo text, p_utm_campaign text, p_canal text, p_origem text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_material_link(p_url text, p_codigo text, p_utm_campaign text, p_canal text, p_origem text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_mensagem_registrar(p_conversa_id uuid, p_papel text, p_conteudo text, p_id_externo text, p_blocos jsonb, p_origem text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_mensagem_registrar(p_conversa_id uuid, p_papel text, p_conteudo text, p_id_externo text, p_blocos jsonb, p_origem text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_nome_bate(p_nome text, p_sobrenome text, q_nome text, q_sobrenome text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_nome_bate(p_nome text, p_sobrenome text, q_nome text, q_sobrenome text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_nome_conflita(p_nome text, p_sobrenome text, q_nome text, q_sobrenome text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_nome_conflita(p_nome text, p_sobrenome text, q_nome text, q_sobrenome text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_nome_simples(p text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.mind_nome_simples(p text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_nome_simples(p text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_origem(p_codigo text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.mind_origem(p_codigo text) TO anon;

GRANT EXECUTE ON FUNCTION public.mind_origem(p_codigo text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.mind_origem(p_codigo text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_origem(p_codigo text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_pendencia_resolver(p_id uuid, p_status text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_pendencia_resolver(p_id uuid, p_status text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_pendencias_listar(p_status text, p_tipo text, p_limite integer, p_offset integer) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_pendencias_listar(p_status text, p_tipo text, p_limite integer, p_offset integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_pessoa_completar(p_pessoa_id uuid, p_sobrenome text, p_empresa text, p_cargo text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_pessoa_completar(p_pessoa_id uuid, p_sobrenome text, p_empresa text, p_cargo text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_pessoa_fatos(p_pessoa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_pessoa_fatos(p_pessoa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_precos_por_volume() TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_precos_por_volume() TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_rota_capacidade(p_rota text, p_canal text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_rota_capacidade(p_rota text, p_canal text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_slug(p_texto text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.mind_slug(p_texto text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_slug(p_texto text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_sync_abrir(p_fonte text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_sync_abrir(p_fonte text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_sync_marcar(p_fonte text, p_marca timestamp with time zone, p_lidos integer, p_gravados integer, p_status text, p_erro text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_sync_marcar(p_fonte text, p_marca timestamp with time zone, p_lidos integer, p_gravados integer, p_status text, p_erro text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_sync_marcar(p_fonte text, p_marca timestamp with time zone, p_lidos integer, p_gravados integer, p_status text, p_erro text, p_cursor text, p_completou boolean) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_sync_marcar(p_fonte text, p_marca timestamp with time zone, p_lidos integer, p_gravados integer, p_status text, p_erro text, p_cursor text, p_completou boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_turno_registrar(p_conversa_id uuid, p_resposta text, p_estado jsonb, p_meta jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_turno_registrar(p_conversa_id uuid, p_resposta text, p_estado jsonb, p_meta jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_urlencode(p text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.mind_urlencode(p text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_urlencode(p text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_utm_registrar(p_dados jsonb) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.mind_utm_registrar(p_dados jsonb) TO anon;

GRANT EXECUTE ON FUNCTION public.mind_utm_registrar(p_dados jsonb) TO authenticated;

GRANT EXECUTE ON FUNCTION public.mind_utm_registrar(p_dados jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_utm_registrar(p_dados jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.mind_virada_de_lote() TO postgres;

GRANT EXECUTE ON FUNCTION public.mind_virada_de_lote() TO service_role;

GRANT EXECUTE ON FUNCTION public.mindagent_bootstrap(p_event_slug text) TO anon;

GRANT EXECUTE ON FUNCTION public.mindagent_bootstrap(p_event_slug text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.mindagent_bootstrap(p_event_slug text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mindagent_bootstrap(p_event_slug text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mindagent_chat_bind_identity(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text, p_email text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mindagent_chat_bind_identity(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text, p_email text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mindagent_chat_get_context(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mindagent_chat_get_context(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mindagent_chat_save_interests(p_auth_user_id uuid, p_session_id uuid, p_token_hash text, p_interests jsonb, p_evidence_message_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.mindagent_chat_save_interests(p_auth_user_id uuid, p_session_id uuid, p_token_hash text, p_interests jsonb, p_evidence_message_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.mindagent_chat_save_message(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text, p_role text, p_content text, p_client_message_id text, p_blocks jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.mindagent_chat_save_message(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text, p_role text, p_content text, p_client_message_id text, p_blocks jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.mindagent_chat_search(p_event_slug text, p_query text, p_limit integer) TO postgres;

GRANT EXECUTE ON FUNCTION public.mindagent_chat_search(p_event_slug text, p_query text, p_limit integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.mindagent_chat_start(p_auth_user_id uuid, p_device_key text, p_user_agent text, p_token_hash text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mindagent_chat_start(p_auth_user_id uuid, p_device_key text, p_user_agent text, p_token_hash text) TO service_role;

GRANT EXECUTE ON FUNCTION public.mindagent_sync_offers(p_vigente integer, p_lotes jsonb, p_tiers jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.mindagent_sync_offers(p_vigente integer, p_lotes jsonb, p_tiers jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.mindagent_treble_claim_event(p_event_key text, p_session_external_id text, p_request_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.mindagent_treble_claim_event(p_event_key text, p_session_external_id text, p_request_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.mindagent_treble_complete_event(p_event_key text, p_status text, p_error_code text) TO postgres;

GRANT EXECUTE ON FUNCTION public.mindagent_treble_complete_event(p_event_key text, p_status text, p_error_code text) TO service_role;

GRANT EXECUTE ON FUNCTION public.normalizar_telefone_trigger() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.normalizar_telefone_trigger() TO postgres;

GRANT EXECUTE ON FUNCTION public.normalizar_telefone_trigger() TO service_role;

GRANT EXECUTE ON FUNCTION public.pessoa_vincular_hubspot(p_pessoa_id uuid, p_hubspot_id text) TO postgres;

GRANT EXECUTE ON FUNCTION public.pessoa_vincular_hubspot(p_pessoa_id uuid, p_hubspot_id text) TO service_role;

GRANT EXECUTE ON FUNCTION public.silence_calcular_next_review(p_conversa_id uuid, p_dados jsonb, p_followup_count integer, p_last_followup_at timestamp with time zone, p_action text, p_piso timestamp with time zone) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.silence_calcular_next_review(p_conversa_id uuid, p_dados jsonb, p_followup_count integer, p_last_followup_at timestamp with time zone, p_action text, p_piso timestamp with time zone) TO postgres;

GRANT EXECUTE ON FUNCTION public.silence_calcular_next_review(p_conversa_id uuid, p_dados jsonb, p_followup_count integer, p_last_followup_at timestamp with time zone, p_action text, p_piso timestamp with time zone) TO service_role;

GRANT EXECUTE ON FUNCTION public.silence_chave_timing(p_dados jsonb, p_pos_followup boolean) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.silence_chave_timing(p_dados jsonb, p_pos_followup boolean) TO postgres;

GRANT EXECUTE ON FUNCTION public.silence_chave_timing(p_dados jsonb, p_pos_followup boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.silence_claim_pendentes(p_limite integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.silence_claim_pendentes(p_limite integer) TO postgres;

GRANT EXECUTE ON FUNCTION public.silence_claim_pendentes(p_limite integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.silence_compra_summit_2026(p_conversa_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.silence_compra_summit_2026(p_conversa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.silence_compra_summit_2026(p_conversa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.silence_liberar_lock(p_conversa_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.silence_liberar_lock(p_conversa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.silence_liberar_lock(p_conversa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.silence_montar_contexto(p_conversa_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.silence_montar_contexto(p_conversa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.silence_montar_contexto(p_conversa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.silence_registrar_decisao(p_conversa_id uuid, p_decisao jsonb, p_followup_enviado boolean) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.silence_registrar_decisao(p_conversa_id uuid, p_decisao jsonb, p_followup_enviado boolean) TO postgres;

GRANT EXECUTE ON FUNCTION public.silence_registrar_decisao(p_conversa_id uuid, p_decisao jsonb, p_followup_enviado boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.silence_sync_from_analysis(p_analise_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.silence_sync_from_analysis(p_analise_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.silence_sync_from_analysis(p_analise_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.silence_ts(p_texto text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.silence_ts(p_texto text) TO postgres;

GRANT EXECUTE ON FUNCTION public.silence_ts(p_texto text) TO service_role;

GRANT EXECUTE ON FUNCTION public.silence_ultimo_evento(p_conversa_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.silence_ultimo_evento(p_conversa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.silence_ultimo_evento(p_conversa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.summit_contato_criar_pendentes(p_limit integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.summit_contato_criar_pendentes(p_limit integer) TO postgres;

GRANT EXECUTE ON FUNCTION public.summit_contato_criar_pendentes(p_limit integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.summit_motivo_exclusao(p_conversa_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.summit_motivo_exclusao(p_conversa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.summit_motivo_exclusao(p_conversa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.summit_status_confirmar(p_pares jsonb) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.summit_status_confirmar(p_pares jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.summit_status_confirmar(p_pares jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.summit_status_pendentes(p_limit integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.summit_status_pendentes(p_limit integer) TO postgres;

GRANT EXECUTE ON FUNCTION public.summit_status_pendentes(p_limit integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.telefone_normalizar(p_tel text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.telefone_normalizar(p_tel text) TO postgres;

GRANT EXECUTE ON FUNCTION public.telefone_normalizar(p_tel text) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_agent_config() TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_agent_config() TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_agent_context(p_audience text, p_origem text, p_utm jsonb, p_conversa text, p_produto text) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_agent_context(p_audience text, p_origem text, p_utm jsonb, p_conversa text, p_produto text) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_agent_context_base() TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_agent_context_base() TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_agent_identificar(p_session_external_id text, p_email text, p_nome text, p_sobrenome text, p_mesma_pessoa boolean) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_agent_identificar(p_session_external_id text, p_email text, p_nome text, p_sobrenome text, p_mesma_pessoa boolean) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_agent_prompt(p_audience text) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_agent_prompt(p_audience text) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_agent_resposta_repetida(p_conversation_id uuid, p_mensagem text, p_janela_segundos integer) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_agent_resposta_repetida(p_conversation_id uuid, p_mensagem text, p_janela_segundos integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_agent_start(p_session_external_id text, p_contact jsonb, p_origem text, p_utm_token text, p_mensagem jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_agent_start(p_session_external_id text, p_contact jsonb, p_origem text, p_utm_token text, p_mensagem jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_agent_token() TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_agent_token() TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_cta_da_conversa(p_conversa_id uuid) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.treble_cta_da_conversa(p_conversa_id uuid) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_cta_da_conversa(p_conversa_id uuid) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_evento_gravar(p_payload jsonb, p_tipo text, p_direcao text, p_telefone text, p_ocorreu_em timestamp with time zone) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.treble_evento_gravar(p_payload jsonb, p_tipo text, p_direcao text, p_telefone text, p_ocorreu_em timestamp with time zone) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_evento_gravar(p_payload jsonb, p_tipo text, p_direcao text, p_telefone text, p_ocorreu_em timestamp with time zone) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_find_location(p_event_slug text, p_query text) TO anon;

GRANT EXECUTE ON FUNCTION public.treble_find_location(p_event_slug text, p_query text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.treble_find_location(p_event_slug text, p_query text) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_find_location(p_event_slug text, p_query text) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_materiais(p_audience text, p_origem text) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_materiais(p_audience text, p_origem text) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_momento() TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_momento() TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_origem_da_cta(p_cta text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.treble_origem_da_cta(p_cta text) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_origem_da_cta(p_cta text) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_poll_sincronizado(p_poll_id text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.treble_poll_sincronizado(p_poll_id text) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_poll_sincronizado(p_poll_id text) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_sessao_backfill(p_poll_id text, p_sessions jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_sessao_backfill(p_poll_id text, p_sessions jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_sessao_encerrada_gravar(p_payload jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_sessao_encerrada_gravar(p_payload jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_status_ciclo() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.treble_status_ciclo() TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_status_ciclo() TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_status_confirmar(p_pares jsonb) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.treble_status_confirmar(p_pares jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_status_confirmar(p_pares jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_status_confirmar_contato(p_pares jsonb) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.treble_status_confirmar_contato(p_pares jsonb) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_status_confirmar_contato(p_pares jsonb) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_status_marcar(p_telefone text, p_status text, p_quando timestamp with time zone, p_session_external_id text) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.treble_status_marcar(p_telefone text, p_status text, p_quando timestamp with time zone, p_session_external_id text) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_status_marcar(p_telefone text, p_status text, p_quando timestamp with time zone, p_session_external_id text) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_status_pendentes(p_limit integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.treble_status_pendentes(p_limit integer) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_status_pendentes(p_limit integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_status_pendentes_contato(p_limit integer) TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.treble_status_pendentes_contato(p_limit integer) TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_status_pendentes_contato(p_limit integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.treble_status_recompute() TO PUBLIC;

GRANT EXECUTE ON FUNCTION public.treble_status_recompute() TO postgres;

GRANT EXECUTE ON FUNCTION public.treble_status_recompute() TO service_role;

COMMENT ON SCHEMA agentes IS 'Cérebro compartilhado dos agentes do Mind: como falam (tom de voz) e como agem (playbooks, base, objeções). Usado por qualquer agente; nenhum é dono. treble/concierge guardam só o runtime da própria ferramenta.';

COMMENT ON SCHEMA api IS 'Mind Intelligence API. Preço, lote e cupom NÃO estão aqui: vivem em mind-summit-propostas, que serve o site em tempo real. Quando entrarem, entram como função desta API — nunca como cópia de tabela.';

COMMENT ON SCHEMA catalogo IS 'Registro de produtos do Mind, na raiz e fora das verticais. Todos os agentes consultam aqui para identificar um produto e descobrir onde estao seus dados.';

COMMENT ON SCHEMA concierge IS 'O agente do Mind Summit. Comportamento, memória e jornada — nada aqui é verdade institucional.';

COMMENT ON SCHEMA credenciamento_summit_2026 IS 'Espelho de leitura do credenciamento do Summit 2026 (projeto mind-summit-vendas-dashboard). A senha de credenciamento NAO e espelhada -- fica so na origem.';

COMMENT ON SCHEMA crm IS 'Pessoas e o relacionamento com elas: consentimento, pedidos de LGPD, enriquecimento. Atravessa produtos — a pessoa nao pertence a um evento.';

COMMENT ON SCHEMA dash IS 'Mind Dash.';

COMMENT ON SCHEMA ecossistema IS 'O que os produtos reusam: palestrantes, taxonomia, materiais, conhecimento institucional.';

COMMENT ON SCHEMA eduzz IS 'Espelho de leitura da Eduzz (ingressos Blinket + vendas), copiado do projeto mind-summit-vendas-dashboard. Fonte da verdade e a Eduzz; o dono do sync e o Vendas.';

COMMENT ON SCHEMA engagement IS 'O que aconteceu com a pessoa: conversas, mensagens, presencas, identidades de canal, atribuicao, feedback.';

COMMENT ON SCHEMA eventos IS 'Eventos fora do Summit, inclusive os fechados de captacao de lead.';

COMMENT ON SCHEMA institute IS 'Mind Institute: formacoes e Journey. Turma e linha.';

COMMENT ON SCHEMA intelligence IS 'O que a gente infere sobre a pessoa: memoria, objetivos, preferencias, sinais. Declarado x inferido fica explicito aqui.';

COMMENT ON SCHEMA mind IS 'A EMPRESA Mind: posicionamento e politicas. O que e de produto mora na casa do produto (ver catalogo.produtos.schema_dados).';

COMMENT ON SCHEMA pessoas IS 'Registro canônico de identidade das pessoas do Mind Intelligence: o pino que engagement/intelligence apontam. hubspot_id liga ao espelho do HubSpot.';

COMMENT ON SCHEMA platform IS 'Infra compartilhada de agentes: provedores de LLM, embeddings, custo.';

COMMENT ON SCHEMA public IS 'standard public schema';

COMMENT ON SCHEMA summit_2026 IS 'Mind Summit. Edicao e linha, escopada por event_id.';

COMMENT ON SCHEMA treble IS 'Runtime do agente inbound de vendas no WhatsApp (Treble): conversas, mensagens e sinais. Acesso somente via service role das Edge Functions.';

COMMENT ON TABLE agentes.kit_blocos IS 'Registry de composição do kit por rota: qual bloco entra, qual provider o serve e em que seção. Provider é config textual, resolvida em runtime; a tabela não depende da existência da função.';

COMMENT ON TABLE agentes.prompts IS 'Blocos do prompt, um por linha (chave): base + tom_de_voz + playbook_<audience> + objecoes. Compostos por turno em public.treble_agent_prompt. Trocar comportamento é UPDATE, não deploy.';

COMMENT ON TABLE catalogo.produtos IS 'Um registro por produto do Mind. Fonte unica do vocabulario de produto: CRM, conhecimento e agentes referenciam estes codigos.';

COMMENT ON TABLE credenciamento_summit_2026.participantes IS 'A coluna `password` da origem NAO e trazida de proposito: o corte e feito na propria porta de leitura do projeto de origem, entao o valor nem cruza a rede.';

COMMENT ON VIEW credenciamento_summit_2026.v_participantes IS 'Participantes credenciados com a pessoa do Mind resolvida por juncao. pessoa_criterio diz por que casou (email = forte; telefone = so quando unico).';

COMMENT ON TABLE credenciamento_summit_2026.yazo_sync_state IS 'Estado do sync Yazo NA ORIGEM. Aqui e so leitura -- serve pra saber se o credenciamento de la esta rodando, nao pra controlar nada daqui.';

COMMENT ON TABLE crm.acessos IS 'Trilha de quem consultou dado individual do espelho de CRM: qual função, sobre quem, por qual agente.';

COMMENT ON TABLE crm.consents IS 'Consentimento por finalidade, com a versao da politica e o texto exibido — e o que prova depois o que a pessoa aceitou.';

COMMENT ON TABLE crm.empenho_summit_2026 IS 'HubSpot, objeto Deal, pipeline "Empenho Summit 2026". Compra publica por empenho (SSP, SEPLAG, Unesp, TCU, Petrobras...). O estagio "Gerar Ingresso (vendedor cadastra na Eduzz)" e onde um ingresso nasce SEM venda direta na Eduzz.';

COMMENT ON TABLE crm.leads_capturados IS 'Landing dos leads do formulário do site: campos do formulário (nomes do HubSpot) + rastreamento de campanha + estado. pendente -> enviado quando o lead casa no espelho do HubSpot; enviados podem ser limpos depois.';

COMMENT ON TABLE crm.mapa_produtos IS 'Traduz propriedade+valor do contato HubSpot para codigo canonico de catalogo.produtos. valor_origem = ''*'' significa "qualquer valor nao vazio serve" (usado nas categorias do Summit). Multi-select do HubSpot vem separado por '';'' e e o consumidor que separa os tokens -- nao criar linha por combinacao.';

COMMENT ON VIEW crm.negocio_contatos IS 'Relacao deal<->contato derivada de propriedades->_contatos (array de hubspot contact ids), dos pipelines espelhados. View: sem copia, sempre em sincronia com o espelho.';

COMMENT ON TABLE crm.pessoa_nps IS 'NPS por pessoa e por produto. Sem fonte conectada ainda: o campo de NPS do HubSpot esta vazio em toda a base.';

COMMENT ON TABLE crm.pessoa_produtos IS 'O que cada pessoa já adquiriu, um registro por produto do catálogo mind.produtos. Conversável: a pessoa pode perguntar sobre a própria compra.';

COMMENT ON TABLE crm.pessoas_interno IS 'Sinais internos por pessoa: origem, dono, estagio comercial, engajamento. Orienta o tom e o argumento dos agentes; nunca e recitado ao usuario final.';

COMMENT ON TABLE crm.pipeline_de_vendas_summit IS 'HubSpot, objeto Deal, pipeline "Pipeline de vendas - Summit" (917379159). Guarda NEGOCIOS, nao leads -- o nome antigo (pipeline_summit_leads_captados) dizia o contrario.';

COMMENT ON TABLE crm.pipeline_leads_inbound IS 'HubSpot, objeto LEAD (nao Deal), pipeline "Pipeline leads Inbound" (918902366).';

COMMENT ON TABLE crm.status_summit_hs IS 'Trava de idempotência do write-back de status_summit_2026 (só reescreve quando muda). Nunca contém participacao_anual: esse campo jamais é escrito pelo sistema.';

COMMENT ON TABLE crm.sync_estado IS 'Marca d''agua e resultado da ultima sincronizacao por fonte. A carga inicial e a primeira rodada: mesma logica, marca d''agua vazia.';

COMMENT ON TABLE crm.vendas_historicas_mind_summit IS 'HubSpot, objeto Deal, pipeline "Vendas Históricas Mind Summit" (default).';

COMMENT ON TABLE ecossistema.palestrantes_especialistas IS 'Palestrantes e especialistas do ecossistema Mind. Comum a todos os produtos: a mesma pessoa palestra no Summit e pode dar aula no Institute.';

COMMENT ON VIEW eduzz.v_ingressos IS 'Ingressos do Blinket com a pessoa do Mind resolvida por juncao. pessoa_criterio diz por que casou (email = forte; telefone = so quando unico). Nunca cria pessoa nem identidade.';

COMMENT ON VIEW eduzz.v_vendas IS 'Vendas da Eduzz com a pessoa do Mind resolvida por juncao, mesma regra da v_ingressos.';

COMMENT ON TABLE engagement.identidades IS 'Resolve telefone, session_external_id do Treble, e-mail do HubSpot, id da Eduzz e dispositivo_id do site para UMA pessoa em crm.pessoas.';

COMMENT ON VIEW engagement.janela_24h IS 'Janela de 24h do WhatsApp por conversa: aberta x fechada (+ quanto falta). fechada = Treble avisou (encerrada_em) ou ultima msg do lead > 24h.';

COMMENT ON TABLE engagement.origens IS 'Botoes de entrada por site. Fonte unica do utm_source, do campo oculto do HubSpot e da mensagem de abertura do bot.';

COMMENT ON TABLE engagement.treble_eventos IS 'Eventos crus da Treble via webhook (mensagem recebida/entrega/leitura). Fonte da janela de 24h do WhatsApp: por telefone, a ultima RECEBIDA reinicia a janela. Payload inteiro guardado; colunas ajustam quando o 1o evento real chegar.';

COMMENT ON TABLE engagement.utm_sessoes IS 'Ponte de atribuicao site -> WhatsApp. O site registra a UTM e recebe um token curto, que viaja no texto pre-preenchido do wa.me.';

COMMENT ON VIEW engagement.v_pessoa IS 'A pessoa achatada para quem precisa de nome inteiro, telefone e idioma numa linha so. A verdade mora em crm.pessoas; idioma e anonimo em engagement.pessoa_perfil; yazo_id em engagement.identidades.';

COMMENT ON TABLE intelligence.continuidade_comercial IS 'Estado do Silence & Continuation Engine por conversa. REVIEW != FOLLOW-UP: next_review_at diz quando REAVALIAR, não quando mandar mensagem. O relógio é do código; a IA decide a ação.';

COMMENT ON VIEW mind.produtos IS 'Compatibilidade: o catalogo agora vive em catalogo.produtos. Prefira o novo caminho.';

COMMENT ON TABLE pessoas.pessoas IS 'Espelho de leitura das pessoas do HubSpot, para todos os agentes. Fonte da verdade é o HubSpot; escrita local só pelo sincronizador. Campos internos ficam em crm.pessoas_interno.';

COMMENT ON TABLE platform.integracoes IS 'Como o Mind Intelligence fala com sistemas de fora. secret_ref e o NOME da variavel nos secrets do Supabase -- o valor nunca entra no banco. config guarda o que nao e segredo (id de portal, chave publica, guid de formulario).';

COMMENT ON TABLE public.espelho_estado IS 'Uma linha por fonte espelhada de outro projeto Supabase. Quem orquestra e a edge `eduzz-espelho-sync`; a porta do outro lado e sempre `espelho_para_mind` (so leitura).';

COMMENT ON TABLE public.mind_admin_audit IS 'Append-only audit trail for authenticated administrative actions.';

COMMENT ON TABLE public.mind_admin_editorial IS 'Editorial workflow sidecar for Mind Agent admin resources.';

COMMENT ON TABLE public.mind_admin_event_details IS 'Admin-only event fields not present in the operational event table.';

COMMENT ON TABLE public.mind_admin_users IS 'Backend authorization source for the Mind Agent administration panel.';

COMMENT ON TABLE summit_2026.commercial_rules IS 'Regras que o agente CONSULTA antes de agir (código decide, prompt fala). config é o contrato legível por máquina de cada regra.';

COMMENT ON TABLE summit_2026.coupons IS 'Cupons que o agente pode validar. offer_codigo nulo = vale para qualquer categoria; ativo=false por default para cupom nunca nascer válido por acidente.';

COMMENT ON TABLE summit_2026.experiencias IS 'Experiências do Mind Summit 2026 e suas inclusões. Cadeia de verdade: design/Mind Summit 2026 VF Mobile.dc.html = SOURCE congelada; Mind-Institute/mindsummit2026/src/data/compare.json = mirror estruturado vivo; esta tabela = mirror local do mind-agent.';

COMMENT ON TABLE treble.config IS 'Configuração do agente (ex.: token do webhook). Só service role.';

COMMENT ON TABLE treble.polls IS 'Catalogo de polls (fluxos) da Treble. poll_id = id do fluxo (usado na API). tipo inbound/outbound. users/taxa = snapshot do print de 25/08 (referencia, muda). Fonte: Adriana.';

COMMENT ON TABLE treble.status_da_conversa IS 'Status da janela de 24h por usuario (telefone): aberta x fechada. Fonte: eventos da Treble (session.close=fechada; mensagem recebida=aberta). Checar antes de disparar.';

COMMENT ON TABLE treble.status_hs_contatos IS 'Trava/idempotencia do write-back de status_conversa_treble no Contato do HubSpot.';

COMMENT ON TABLE treble.status_hs_leads IS 'Trava/idempotencia do write-back: ultimo valor de status_conversa escrito em cada Lead do HubSpot.';

COMMENT ON COLUMN agentes.kit_blocos.rota IS 'Uma das seis rotas canônicas do router universal.';

COMMENT ON COLUMN agentes.kit_blocos.bloco IS 'Nome do bloco dentro da seção do kit.';

COMMENT ON COLUMN agentes.kit_blocos.provider IS 'Nome qualificado da função que serve o bloco. Config textual — pode ainda não existir.';

COMMENT ON COLUMN agentes.kit_blocos.obrigatorio IS 'Bloco obrigatório: sua ausência é falha de montagem do kit, não omissão silenciosa.';

COMMENT ON COLUMN catalogo.produtos.tipo IS 'empresa = o Mind em si, nao um produto vendavel. Os demais sao produtos.';

COMMENT ON COLUMN catalogo.produtos.vertical IS 'Vertical (frente) do produto: summit, institute, eventos, dash, outro. A entrada/site carrega a vertical; o produto especifico so se conhece na conversa/deal.';

COMMENT ON COLUMN catalogo.produtos.schema_dados IS 'Esquema onde vivem os dados e o conhecimento deste produto. Vazio = ainda nao existe base propria.';

COMMENT ON COLUMN catalogo.produtos.periodo IS 'Quando o produto aconteceu ou acontece, em texto legivel. Ex.: "outubro de 2025".';

COMMENT ON COLUMN catalogo.produtos.pipelines_hubspot IS 'IDs dos pipelines de Deal do HubSpot onde sao geridas negociacoes CORRENTES deste produto. Nao entra aqui: o Pipeline Leads Inbound (918902366), que e universal e nao pertence a produto nenhum; nem o pipeline historico (default); nem pipeline que exista no HubSpot mas nao seja gestao corrente confirmada deste produto.';

COMMENT ON COLUMN credenciamento_summit_2026.participantes.ticket_type IS 'Mind | VIP | Prime | SEM MAPA. "SEM MAPA" = produto que ainda nao foi mapeado em `credenciamento_produtos_mapa` na origem.';

COMMENT ON COLUMN credenciamento_summit_2026.participantes.ticket_origin IS 'Pago | Cortesia | Convidado institucional | Staff. Vocabulario DIFERENTE do `eduzz.produto_catalogo.tipo_de_acesso` (que usa Pago | Cortesia | Patrocinio) -- os dois descrevem a mesma coisa com palavras diferentes. Reconciliar e decisao da Adriana.';

COMMENT ON COLUMN crm.contato_espelho.propriedades IS 'O registro cru do contato no HubSpot, inteiro. Consulta: propriedades->>''lead_score_summit_26''. As colunas tipadas ao lado sao as que os agentes usam de verdade -- estas aqui existem para nada se perder e nada quebrar.';

COMMENT ON COLUMN crm.contato_espelho.icp_confianca IS 'Confiança da classificação ICP (0 a 10).';

COMMENT ON COLUMN crm.contato_espelho.etapa_do_lead__atualizar IS 'Etapa do lead no contato. Opções: Novo lead, Lead em contato, Lead qualificado (rótulo "Comprou ingresso"), Em negociação, Lead perdido. É a que a Treble já escreve hoje.';

COMMENT ON COLUMN crm.empenho_summit_2026.propriedades IS 'O registro cru do negocio no HubSpot, inteiro. Mesma regra do contato.';

COMMENT ON COLUMN crm.pessoa_produtos.produto_codigo IS 'Referência ao catálogo mind.produtos. Produto ausente do catálogo bloqueia a carga de propósito: melhor falhar alto que inventar vocabulário.';

COMMENT ON COLUMN crm.pessoas_interno.origem_primeira IS 'Origem original do contato no HubSpot (100% preenchida). Versao confiavel do "onde a pessoa chegou primeiro".';

COMMENT ON COLUMN crm.pessoas_interno.utm_source IS 'Detalhe de campanha do primeiro contato. Preenchido em ~8% da base: serve para enriquecer um caso, nao para medir a base.';

COMMENT ON COLUMN crm.pessoas_interno.descadastrado_email IS 'Pessoa pediu para nao receber e-mail. Sinal de consentimento: respeitar antes de qualquer abordagem.';

COMMENT ON COLUMN crm.pipeline_de_vendas_summit.propriedades IS 'O registro cru do negocio no HubSpot, inteiro. Mesma regra do contato.';

COMMENT ON COLUMN crm.sync_estado.ignorados IS 'O que a rodada nao conseguiu gravar e por que. Silenciar isso faria a base parecer completa quando nao esta.';

COMMENT ON COLUMN crm.sync_estado.tabela_destino IS 'Em qual tabela de crm o espelho dessa fonte e gravado. Fica aqui, e nao dentro da funcao, para que renomear a tabela seja UPDATE e nao deploy.';

COMMENT ON COLUMN crm.sync_estado.cursor IS 'Cursor da listagem do HubSpot durante a carga inicial. Nulo depois que ela termina -- dai em diante quem manda e a marca dagua.';

COMMENT ON COLUMN crm.sync_estado.carga_completa_em IS 'Quando a carga inicial varreu tudo. Enquanto for nulo, a fonte ainda esta se enchendo e a marca dagua NAO e confiavel.';

COMMENT ON COLUMN crm.sync_estado.pipeline_nome IS 'Rotulo do pipeline EXATAMENTE como aparece no HubSpot. E a fonte de verdade do nome; o nome da tabela e so um identificador Postgres derivado dele.';

COMMENT ON COLUMN crm.vendas_historicas_mind_summit.propriedades IS 'O registro cru do negocio no HubSpot, inteiro. Mesma regra do contato.';

COMMENT ON COLUMN crm.vendas_historicas_mind_summit.situacao IS 'Situacao real do deal: fechado | fantasma (aberto duplicado de um ja pago) | carrinho_abandonado (checkout R$0/hash) | aberto_status_aberto (Eduzz Aberto, R$>0, a revisar) | pendente_a_confirmar (Pendente, R$>0) | aberto. Fonte: classificacao derivada; regra da Adriana.';

COMMENT ON COLUMN dash.knowledge_chunks.modelo_embedding IS 'Qual modelo gerou este vetor. Misturar modelos no mesmo índice produz busca silenciosamente errada.';

COMMENT ON COLUMN dash.knowledge_documents.agents IS 'Quais agentes podem recuperar este documento. Vazio = todos. Não é permissão, é relevância: material fora de escopo no contexto piora a resposta mesmo sem vazar nada.';

COMMENT ON COLUMN dash.knowledge_documents.aprovado_treble IS 'Curadoria do bot do WhatsApp: só documentos aprovados entram no contexto do agente Treble. O concierge do site NÃO é afetado por esta coluna.';

COMMENT ON COLUMN dash.knowledge_documents.produto_codigo IS 'NULL = vale para qualquer produto. Preenchido = so entra no contexto quando o agente estiver falando desse produto.';

COMMENT ON COLUMN dash.knowledge_documents.event_id IS 'NULL = conteúdo institucional do Mind (permanente); preenchido = conteúdo do produto/evento, sai de cena junto com ele.';

COMMENT ON COLUMN dash.knowledge_documents.valido_ate IS 'Instante em que o conteúdo sai de circulação para os agentes (ex.: fim das vendas). NULL = sem prazo.';

COMMENT ON COLUMN dash.knowledge_documents.cluster IS 'empresa = Mind institucional; produto = por produto (exige event_id); ciencia = base científica compartilhada; clientes = ICPs/segmentos e leads (interno).';

COMMENT ON COLUMN dash.knowledge_documents.audiencia IS 'publico = o bot pode dizer isso ao usuário; interno = só orienta tom e argumento, nunca é recitado.';

COMMENT ON COLUMN ecossistema.palestrantes_especialistas.aliases IS 'Outras formas do nome da mesma pessoa (ex.: nome de solteira, nome acadêmico), para desambiguação e matching. Texto livre.';

COMMENT ON COLUMN eduzz.ingressos.sumiu_do_blinket_em IS 'Preenchido na origem quando o ingresso deixou de aparecer no Blinket. Nao apagamos a linha.';

COMMENT ON COLUMN eduzz.produto_catalogo.tipo_de_acesso IS 'Pago | Cortesia | Patrocinio -- como a pessoa chegou ao ingresso.';

COMMENT ON COLUMN eduzz.produto_catalogo.motivo_concessao IS 'So para acesso concedido: Convidado | Parceria | Palestrante | Imprensa | Outro.';

COMMENT ON COLUMN eduzz.produto_catalogo.origem_do_acesso IS 'Quem bancou: "Mind" quando e da casa, ou o nome do patrocinador (Beiersdorf, Vale...).';

COMMENT ON COLUMN eduzz.produto_catalogo.tipo_de_venda IS 'Eduzz | Direta | Nao e venda -- por onde o dinheiro entrou (ou se nao entrou).';

COMMENT ON COLUMN engagement.conversas.agente IS 'Qual agente originou/conduz esta conversa (ex.: treble-inbound-agent). Prepara para multiplos agentes.';

COMMENT ON COLUMN engagement.origens.mensagem_abertura IS 'O que o bot fala primeiro quando a pessoa chega por este botão. Vazio = abertura padrão do playbook de descoberta.';

COMMENT ON COLUMN engagement.origens.audiencia_sugerida IS 'Palpite inicial de audiência a partir do botão (ex.: botão "para minha empresa" → b2b). É palpite: a conversa pode corrigir.';

COMMENT ON COLUMN engagement.origens.hubspot IS 'Campos ocultos do formulario do HubSpot para este botao: {propriedade: valor}. perfil_d_cliente ja existe no portal; a propriedade de Intencao ainda precisa ser confirmada ou criada.';

COMMENT ON COLUMN eventos.knowledge_chunks.modelo_embedding IS 'Qual modelo gerou este vetor. Misturar modelos no mesmo índice produz busca silenciosamente errada.';

COMMENT ON COLUMN eventos.knowledge_documents.agents IS 'Quais agentes podem recuperar este documento. Vazio = todos. Não é permissão, é relevância: material fora de escopo no contexto piora a resposta mesmo sem vazar nada.';

COMMENT ON COLUMN eventos.knowledge_documents.aprovado_treble IS 'Curadoria do bot do WhatsApp: só documentos aprovados entram no contexto do agente Treble. O concierge do site NÃO é afetado por esta coluna.';

COMMENT ON COLUMN eventos.knowledge_documents.produto_codigo IS 'NULL = vale para qualquer produto. Preenchido = so entra no contexto quando o agente estiver falando desse produto.';

COMMENT ON COLUMN eventos.knowledge_documents.event_id IS 'NULL = conteúdo institucional do Mind (permanente); preenchido = conteúdo do produto/evento, sai de cena junto com ele.';

COMMENT ON COLUMN eventos.knowledge_documents.valido_ate IS 'Instante em que o conteúdo sai de circulação para os agentes (ex.: fim das vendas). NULL = sem prazo.';

COMMENT ON COLUMN eventos.knowledge_documents.cluster IS 'empresa = Mind institucional; produto = por produto (exige event_id); ciencia = base científica compartilhada; clientes = ICPs/segmentos e leads (interno).';

COMMENT ON COLUMN eventos.knowledge_documents.audiencia IS 'publico = o bot pode dizer isso ao usuário; interno = só orienta tom e argumento, nunca é recitado.';

COMMENT ON COLUMN institute.knowledge_chunks.modelo_embedding IS 'Qual modelo gerou este vetor. Misturar modelos no mesmo índice produz busca silenciosamente errada.';

COMMENT ON COLUMN institute.knowledge_documents.agents IS 'Quais agentes podem recuperar este documento. Vazio = todos. Não é permissão, é relevância: material fora de escopo no contexto piora a resposta mesmo sem vazar nada.';

COMMENT ON COLUMN institute.knowledge_documents.aprovado_treble IS 'Curadoria do bot do WhatsApp: só documentos aprovados entram no contexto do agente Treble. O concierge do site NÃO é afetado por esta coluna.';

COMMENT ON COLUMN institute.knowledge_documents.produto_codigo IS 'NULL = vale para qualquer produto. Preenchido = so entra no contexto quando o agente estiver falando desse produto.';

COMMENT ON COLUMN institute.knowledge_documents.event_id IS 'NULL = conteúdo institucional do Mind (permanente); preenchido = conteúdo do produto/evento, sai de cena junto com ele.';

COMMENT ON COLUMN institute.knowledge_documents.valido_ate IS 'Instante em que o conteúdo sai de circulação para os agentes (ex.: fim das vendas). NULL = sem prazo.';

COMMENT ON COLUMN institute.knowledge_documents.cluster IS 'empresa = Mind institucional; produto = por produto (exige event_id); ciencia = base científica compartilhada; clientes = ICPs/segmentos e leads (interno).';

COMMENT ON COLUMN institute.knowledge_documents.audiencia IS 'publico = o bot pode dizer isso ao usuário; interno = só orienta tom e argumento, nunca é recitado.';

COMMENT ON COLUMN intelligence.continuidade_comercial.last_decision IS 'Último output completo do Silence Engine (action, reason_code, message_required, message_brief...).';

COMMENT ON COLUMN intelligence.participante_memoria.analise_conversa_id IS 'Qual análise de conversa originou esta memória (rastreabilidade). NULL quando não veio de uma análise.';

COMMENT ON COLUMN intelligence.sinais_comerciais.vertical IS 'Vertical de onde a pessoa veio (summit/institute/eventos/dash), derivada da origem/first_url. Diferente de produto_codigo (produto especifico, preenchido so quando conhecido).';

COMMENT ON COLUMN pessoas.pessoas.email IS 'Chave principal, sempre normalizada em minúsculas pelo gatilho.';

COMMENT ON COLUMN pessoas.pessoas.whatsapp IS 'Chave alternativa em E.164 (só dígitos com DDI). Cobre quem não tem e-mail no CRM.';

COMMENT ON COLUMN platform.integracoes.secret_ref IS 'Nome da variavel de ambiente que a Edge Function le. Nunca o valor.';

COMMENT ON COLUMN platform.integracoes.config IS 'Config nao secreta. Public Key da Eduzz e id de portal do HubSpot moram aqui: sao identificadores, nao credenciais.';

COMMENT ON COLUMN public.mind_admin_users.role IS 'Server-side role. Never derive authorization from auth.users.raw_user_meta_data.';

COMMENT ON COLUMN summit_2026.experiencias.chave IS 'Identificador estável da experiência (mind, vip, prime).';

COMMENT ON COLUMN summit_2026.experiencias.ordem IS 'Ordem de apresentação, do mais básico ao mais completo.';

COMMENT ON COLUMN summit_2026.experiencias.inclusoes IS 'Comparativo do que a experiência inclui, em grupos de itens com valor. Copy espelhada da SOURCE; o agrupamento é estrutural.';

COMMENT ON COLUMN summit_2026.experiencias.sincronizado_em IS 'Quando este mirror local foi alinhado com a SOURCE.';

COMMENT ON COLUMN summit_2026.knowledge_chunks.modelo_embedding IS 'Qual modelo gerou este vetor. Misturar modelos no mesmo índice produz busca silenciosamente errada.';

COMMENT ON COLUMN summit_2026.knowledge_documents.agents IS 'Quais agentes podem recuperar este documento. Vazio = todos. Não é permissão, é relevância: material fora de escopo no contexto piora a resposta mesmo sem vazar nada.';

COMMENT ON COLUMN summit_2026.knowledge_documents.aprovado_treble IS 'Curadoria do bot do WhatsApp: só documentos aprovados entram no contexto do agente Treble. O concierge do site NÃO é afetado por esta coluna.';

COMMENT ON COLUMN summit_2026.knowledge_documents.produto_codigo IS 'NULL = vale para qualquer produto. Preenchido = so entra no contexto quando o agente estiver falando desse produto.';

COMMENT ON COLUMN summit_2026.knowledge_documents.event_id IS 'NULL = conteúdo institucional do Mind (permanente); preenchido = conteúdo do produto/evento, sai de cena junto com ele.';

COMMENT ON COLUMN summit_2026.knowledge_documents.valido_ate IS 'Instante em que o conteúdo sai de circulação para os agentes (ex.: fim das vendas). NULL = sem prazo.';

COMMENT ON COLUMN summit_2026.knowledge_documents.cluster IS 'empresa = Mind institucional; produto = por produto (exige event_id); ciencia = base científica compartilhada; clientes = ICPs/segmentos e leads (interno).';

COMMENT ON COLUMN summit_2026.knowledge_documents.audiencia IS 'publico = o bot pode dizer isso ao usuário; interno = só orienta tom e argumento, nunca é recitado.';

COMMENT ON COLUMN summit_2026.offers.procura IS 'Nivel de procura desta categoria. So o agente pode citar escassez quando este campo disser que ela existe — nunca por deducao.';

COMMENT ON COLUMN summit_2026.registrations.ticket_category IS 'O catálogo de categorias vive em mind-summit-propostas.ticket_categories. Aqui é referência, não cópia.';

COMMENT ON COLUMN summit_2026.session_speakers.papel IS 'Papel nesta sessao especifica. Quem media um painel palestra em outro.';

COMMENT ON COLUMN summit_2026.sessions.ingressos IS 'Quais experiencias dao acesso a esta sessao. E o que permite ao agente dizer "esse workshop e VIP e Prime".';

COMMENT ON FUNCTION api.changed_since(p_desde timestamp with time zone) IS 'O que mudou desde X. É o que permite um agente cachear sem que dois agentes respondam coisas diferentes sobre o mesmo fato.';

COMMENT ON FUNCTION api.contact(p_token text, p_nome text) IS 'Devolve APENAS pessoas que já aceitaram contato com quem está perguntando, e apenas o que o app já mostra. Nunca memória, conversa ou interesse de outra pessoa — isso não existe como consulta possível nesta API.';

COMMENT ON FUNCTION api.knowledge(p_pergunta text, p_embedding vector, p_agent text, p_limit integer) IS 'Busca híbrida no conhecimento do Mind. Sem embedding, degrada para texto e continua respondendo — a assinatura não muda quando o embedding entrar.';

COMMENT ON FUNCTION api.quem_sou(p_token text) IS 'Resolve a pessoa a partir do token de sessão. É a única forma de a API saber de quem é o dado — nenhuma outra função aceita id de participante.';

COMMENT ON FUNCTION api.sessions(p_event text, p_dia date, p_tema text, p_limit integer) IS 'Devolve a grade inteira num jsonb só. Correto na escala de um evento (dezenas de sessões); a partir de alguns milhares de linhas, isto precisa virar paginado. Está dito aqui para ninguém descobrir em produção.';

COMMENT ON FUNCTION crm.buscar_pessoa(p_email text, p_whatsapp text, p_agente text) IS 'Busca uma pessoa por e-mail ou WhatsApp e devolve apenas campos conversáveis, registrando o acesso. Única via de leitura do espelho pelos bots.';

COMMENT ON FUNCTION crm.contexto_comercial(p_email text, p_whatsapp text, p_agente text) IS 'Contexto completo para agentes comerciais: conversavel + sinais internos. Bots de atendimento devem usar crm.buscar_pessoa, que nao alcanca o interno.';

COMMENT ON FUNCTION crm.registrar_lead(p_email text, p_whatsapp text, p_primeiro_nome text, p_sobrenome text, p_empresa text, p_cargo text, p_agente text, p_contexto jsonb) IS 'Enfileira um lead coletado por um bot para envio ao HubSpot. Não escreve no espelho — o HubSpot devolve a pessoa no próximo sync.';

COMMENT ON FUNCTION intelligence.vertical_da_entrada(p_site text, p_url text) IS 'De qual frente (vertical) a pessoa veio: prioriza engagement.origens.site; senao deriva do host do first_url via catalogo.vertical_dominios. Retorna null quando desconhecido (nao chuta).';

COMMENT ON FUNCTION mind.pessoa_atual() IS 'Quem está falando nesta transação. O Worker declara com `set local mind.person_id`. É `set local` de propósito: não vaza entre requisições que dividem conexão no pool.';

COMMENT ON FUNCTION public.mind_admin_dashboard_counts() IS 'Service-role-only aggregate for the Mind Agent admin dashboard.';

COMMENT ON FUNCTION public.mind_agent_context(p_conversa_id uuid) IS 'Passo 8 — AGENT_CONTEXT universal. A conversa e a unica ancora: a pessoa vem de engagement.conversas.participante_id, nunca por parametro. Compoe integralmente mind_pessoa_fatos, mind_crm_fatos, mind_crm_comercial e mind_engagement_fatos, mais o entry factual da entrada atual. conversation e a conversa atual na linguagem do coletor; engagement preserva o historico pessoa-wide completo. Conhecimento de produto pertence ao Kit da rota, depois do Router. Memory entra no Passo 15.';

COMMENT ON FUNCTION public.mind_calendario(p_produto text) IS 'Onde estamos no calendario DESTE produto: fase, dias que faltam e o que o agente deve fazer. Depois do evento, venda vira atendimento.';

COMMENT ON FUNCTION public.mind_conflito_registrar(p_pessoa uuid, p_tipo text, p_motivo text, p_outra uuid, p_evidencia jsonb) IS 'Unico escritor de engagement.identidade_fusoes. Idempotente por (par,tipo) ou (pessoa,tipo) enquanto pendente.';

COMMENT ON FUNCTION public.mind_conteudo(p_produto text, p_tipo text) IS 'Conteudo visivel para quem fala DESTE produto: o do produto + o institucional (produto mind) + o universal (NULL). Nunca o de outro produto.';

COMMENT ON FUNCTION public.mind_crm_comercial(p_pessoa_id uuid) IS 'PASSO 5A -- o que comercialmente sabemos desta pessoa no HubSpot agora. Nao decide, nao pontua, nao recomenda, nao escreve. O CONTATO e a fonte da verdade do historico consolidado; crm.mapa_produtos so enriquece com o codigo canonico e NUNCA filtra. Identidade so por engagement.identidades (canal=hubspot). Pipeline vem de catalogo.produtos.pipelines_hubspot e a tabela de crm.sync_estado -- sem hardcode.';

COMMENT ON FUNCTION public.mind_crm_fatos(p_pessoa_id uuid) IS 'Coletor factual de CRM por pessoa. Resolve contatos SO por engagement.identidades (canal=hubspot); nunca por pessoas.hubspot_id. Sem deals, sem compras, sem score.';

COMMENT ON FUNCTION public.mind_crm_vincular_pessoa(p_pessoa_id uuid) IS 'Ponte canonica Pessoa Mind <-> contatos HubSpot. Unico caminho que escreve crm.contato_espelho.pessoa_id. Multiplos contatos por pessoa sao mantidos; nunca funde, nunca sobrescreve dono.';

COMMENT ON FUNCTION public.mind_engagement_fatos(p_pessoa_id uuid) IS 'PASSO 6 -- historico factual de interacao da pessoa, pessoa-wide e atravessando canais. Nao decide, nao infere intencao, nao pontua, nao executa LLM, nao le CRM nem Intelligence derivada. papel=agente significa lado Mind, nao autoria individual.';

COMMENT ON FUNCTION public.mind_espelho_gravar(p_fonte text, p_registros jsonb) IS 'Grava um lote do HubSpot no espelho. A funcao descobre sozinha quais chaves do registro sao colunas tipadas -- coluna nova passa a ser preenchida sem mudar codigo. O registro inteiro ja vem em propriedades. Nao apaga coluna que o lote nao trouxe.';

COMMENT ON FUNCTION public.mind_espelho_ligar() IS 'Amarra o espelho do HubSpot na identidade canonica: contato -> crm.pessoas por e-mail e depois WhatsApp, negocio -> pessoa pelo contato associado (so quando ha um so), negocio -> produto pelo ponteiro do catalogo. Nunca cria pessoa e nunca sobrescreve o que ja esta ligado.';

COMMENT ON FUNCTION public.mind_foto_url(p_asset_path text, p_fallback text) IS 'URL publica da foto no bucket mind-assets, com fallback para foto_url enquanto o arquivo nao subiu.';

COMMENT ON FUNCTION public.mind_inbound(p_evento jsonb) IS 'Contrato universal de entrada dos agentes do Mind. ENTRADA -> PERSISTIR INTERACAO -> RESOLVER IDENTIDADE -> pessoas.pessoas. Canal e adaptador; nao ha regra de Treble aqui. Nao chama IA, router nem CRM.';

COMMENT ON FUNCTION public.mind_nome_bate(p_nome text, p_sobrenome text, q_nome text, q_sobrenome text) IS 'O nome sempre tem que bater. Tolera apenas sobrenome acrescentado. Devolve null quando um dos lados nao tem nome.';

COMMENT ON FUNCTION public.mind_nome_conflita(p_nome text, p_sobrenome text, q_nome text, q_sobrenome text) IS 'O nome NAO confirma identidade -- apelido pontua menos que pessoa diferente. Ele so VETA quando os nomes nao compartilham nada (Joao contra Maria). Contido no outro (Rafa/Rafael) nao conflita.';

COMMENT ON FUNCTION public.mind_pessoa_completar(p_pessoa_id uuid, p_sobrenome text, p_empresa text, p_cargo text) IS 'Completa perfil (sobrenome/empresa/cargo). NAO tem autoridade de identidade: e-mail, whatsapp, auth e hubspot passam so por mind_identidade_resolver.';

COMMENT ON FUNCTION public.mind_pessoa_fatos(p_pessoa_id uuid) IS 'Passo 7 — visao factual e deterministica da pessoa. Le pessoas.pessoas, engagement.identidades, engagement.identidade_fusoes e crm.contato_espelho (sempre pelo caminho canonico pessoa -> identidades canal=hubspot -> contato_espelho.hubspot_id). Campo com valores divergentes fica nulo e vai para conflitos_perfil com proveniencia: nao escolhe vencedor. Fatos da pessoa apenas; estado da oportunidade nao pertence aqui.';

COMMENT ON FUNCTION public.mind_precos_por_volume() IS 'Tabela de precos por volume ja calculada (offers x tiers). Entra no contexto oficial para o agente citar valor de grupo sem fazer conta.';

COMMENT ON FUNCTION public.mind_rota_capacidade(p_rota text, p_canal text) IS 'Passo 11 — Capability Gate. Recebe a rota ja decidida pelo Router e diz se o canal atual consegue executa-la. Registry por convencao (playbook_<rota> em agentes.prompts); kit significa capacidade ACESSIVEL AO RUNTIME ATUAL, nao existencia do dado na base. Matriz de kit e de canal no corpo, transitorias ate o Kit Loader do Passo 12B. needs_human significa que a necessidade exige gente, nao que haja humano alcancavel.';

COMMENT ON FUNCTION public.mind_sync_abrir(p_fonte text) IS 'Abre uma corrida de sincronizacao: devolve a marca dagua, a tabela de destino e a config da integracao, e marca a fonte como rodando.';

COMMENT ON FUNCTION public.mind_sync_marcar(p_fonte text, p_marca timestamp with time zone, p_lidos integer, p_gravados integer, p_status text, p_erro text) IS 'Registra o progresso de uma corrida. Chamada por pagina -- a marca dagua so anda depois de gravar.';

COMMENT ON FUNCTION public.mind_utm_registrar(p_dados jsonb) IS 'O site chama com as UTMs da URL e recebe um token curto para embutir no link do WhatsApp. So escreve; nunca devolve dado de ninguem.';

COMMENT ON FUNCTION public.mind_virada_de_lote() IS 'Contagem ate a virada do lote, derivada de summit.offers. NAO devolve o quanto o preco sobe -- decisao da Adriana em 23/08/2026: nenhum agente deve saber nem falar disso. A janela vem de treble.config.janela_urgencia_dias, que ainda esta no lugar errado: e condicao comercial do Summit, nao config do Treble.';

COMMENT ON FUNCTION public.mindagent_sync_offers(p_vigente integer, p_lotes jsonb, p_tiers jsonb) IS 'Upsert de mind.offers a partir do payload da fonte de preços (mind-summit-propostas). Chamada só pela Edge Function mindagent-sync-precos (service role).';

COMMENT ON FUNCTION public.telefone_normalizar(p_tel text) IS 'Normalização canônica de telefone (E.164 BR sem +). Use SEMPRE esta função: é ela que garante o 9 do celular e evita o HubSpot recusar o número.';

COMMENT ON FUNCTION public.treble_agent_context(p_audience text, p_origem text, p_utm jsonb, p_conversa text, p_produto text) IS 'Contexto minimo e real do agente do Treble: evento (summit_2026.events) + ofertas vigentes (summit_2026.offers, com preco e checkout). Versao simples, sem depender das funcoes do modelo antigo; ampliar conforme as ferramentas do agente forem construidas.';

COMMENT ON FUNCTION public.treble_agent_identificar(p_session_external_id text, p_email text, p_nome text, p_sobrenome text, p_mesma_pessoa boolean) IS 'APELIDO de mind_identificar_pessoa. Existe so para nao quebrar o que ja esta no ar. Nao usar em codigo novo.';

COMMENT ON FUNCTION public.treble_agent_resposta_repetida(p_conversation_id uuid, p_mensagem text, p_janela_segundos integer) IS 'Devolve a resposta já dada para a mesma fala do lead dentro da janela (deduplicação de webhook duplicado do Treble).';

COMMENT ON FUNCTION public.treble_agent_start(p_session_external_id text, p_contact jsonb, p_origem text, p_utm_token text, p_mensagem jsonb) IS 'Adaptador do Treble para o contrato universal (mind_inbound). Passe p_mensagem para a fala do lead ser persistida ANTES de qualquer IA.';

COMMENT ON FUNCTION public.treble_evento_gravar(p_payload jsonb, p_tipo text, p_direcao text, p_telefone text, p_ocorreu_em timestamp with time zone) IS 'Grava um evento cru da Treble (webhook) em engagement.treble_eventos. Chamada pela edge treble-webhook.';

COMMENT ON FUNCTION public.treble_momento() IS 'Sinal de contexto temporal para o agente calibrar expectativa no handoff. Nunca deve ser usado como portão para bloquear transferência.';

COMMENT ON FUNCTION public.treble_sessao_encerrada_gravar(p_payload jsonb) IS 'Grava a conversa do evento session.close da Treble em engagement (conversa + transcript em mensagens; encerrada_em = closed_at). Chamada pela edge treble-webhook.';

COMMENT ON INDEX dash.knowledge_chunks_embedding_idx IS 'HNSW, não ivfflat: este índice nasce vazio. ivfflat treinado em tabela vazia recupera errado sem dar erro.';

COMMENT ON INDEX eventos.knowledge_chunks_embedding_idx IS 'HNSW, não ivfflat: este índice nasce vazio. ivfflat treinado em tabela vazia recupera errado sem dar erro.';

COMMENT ON INDEX institute.knowledge_chunks_embedding_idx IS 'HNSW, não ivfflat: este índice nasce vazio. ivfflat treinado em tabela vazia recupera errado sem dar erro.';

COMMENT ON INDEX intelligence.acessos_sobre_outro IS 'Índice parcial só de acessos em que alguém olhou dado que não é o próprio. Em operação normal, esta lista é VAZIA — se encher, é incidente.';

COMMENT ON INDEX summit_2026.knowledge_chunks_embedding_idx IS 'HNSW, não ivfflat: este índice nasce vazio. ivfflat treinado em tabela vazia recupera errado sem dar erro.';

RESET search_path;
-- fim do baseline estrutural.