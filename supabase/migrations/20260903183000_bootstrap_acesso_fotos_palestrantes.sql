-- Contrato canônico de acesso e identidade visual do app Summit 2026.

begin;

-- Corrige o contrato público do bootstrap sem trocar seus nomes de campos:
-- `trilhas` passa a refletir a categoria canônica do ingresso (`sessions.ingressos`).
-- Fotos e destaques pertencem à identidade canônica do palestrante, não a participantes.

alter table ecossistema.palestrantes_especialistas
  add column if not exists foto_asset text,
  add column if not exists destaque boolean not null default false;

alter table ecossistema.palestrantes_especialistas
  drop constraint if exists palestrantes_especialistas_foto_asset_formato;

alter table ecossistema.palestrantes_especialistas
  add constraint palestrantes_especialistas_foto_asset_formato
  check (foto_asset is null or foto_asset ~ '^palestrantes/[a-z0-9-]+[.]webp$');

comment on column ecossistema.palestrantes_especialistas.foto_asset is
  'Caminho relativo ao diretório assets do app; identidade visual canônica do palestrante.';
comment on column ecossistema.palestrantes_especialistas.destaque is
  'Indica palestrante de destaque editorial no app.';

with seed(slug, foto_asset, destaque) as (
  values
    ('adriana-drulla','palestrantes/adriana.webp',false),
    ('alana-anijar','palestrantes/alana.webp',false),
    ('amy-edmondson','palestrantes/amy.webp',true),
    ('ana-bogus','palestrantes/ana-bogus.webp',false),
    ('ana-claudia-quintana-arantes','palestrantes/ana-claudia.webp',false),
    ('ana-mocny','palestrantes/ana-mocny.webp',false),
    ('arthur-guerra-de-andrade','palestrantes/arthur.webp',false),
    ('caito-maia','palestrantes/caito.webp',false),
    ('carla-tieppo','palestrantes/carla.webp',false),
    ('christina-maslach','palestrantes/christina.webp',true),
    ('cirlene-luiza-zimmermann','palestrantes/cirlene.webp',false),
    ('daiana-garbin','palestrantes/daiana.webp',false),
    ('daniel-martins-de-barros','palestrantes/daniel.webp',false),
    ('deepika-chopra','palestrantes/deepika.webp',false),
    ('edna-goldoni','palestrantes/edna.webp',false),
    ('esabela-cruz','palestrantes/esabela.webp',false),
    ('fernanda-catena','palestrantes/fernanda.webp',false),
    ('gustavo-locatelli','palestrantes/gustavo.webp',false),
    ('igor-gomes-menezes','palestrantes/igor.webp',false),
    ('irene-reis','palestrantes/irene.webp',false),
    ('ivana-moreira','palestrantes/ivana.webp',false),
    ('izabella-camargo','palestrantes/izabella.webp',false),
    ('jan-emmanuel-de-neve','palestrantes/deneve.webp',true),
    ('joao-yosef-torres','palestrantes/joao.webp',false),
    ('lailson-lima','palestrantes/lailson.webp',false),
    ('marcio-atalla','palestrantes/marcio.webp',false),
    ('maryana-com-y','palestrantes/maryanna.webp',false),
    ('mauricio-giamellaro','palestrantes/mauricio.webp',false),
    ('mauro-muller','palestrantes/mauro.webp',false),
    ('michael-e-long','palestrantes/michael.webp',false),
    ('michelle-schneider','palestrantes/michelle.webp',false),
    ('oscar-de-bos','palestrantes/oscar.webp',false),
    ('paul-goldsmith','palestrantes/paul.webp',false),
    ('paula-benevides','palestrantes/paula.webp',false),
    ('renata-rivetti','palestrantes/renata.webp',false),
    ('sonja-lyubomirsky','palestrantes/sonja.webp',true),
    ('tamara-myles','palestrantes/tamara.webp',false),
    ('veruska-galvao','palestrantes/veruska.webp',false),
    ('yuri-trafane','palestrantes/yuri.webp',false)
)
update ecossistema.palestrantes_especialistas sp
set foto_asset = coalesce(sp.foto_asset, seed.foto_asset),
    destaque = sp.destaque or seed.destaque,
    atualizado_em = now()
from seed
where sp.slug = seed.slug
  and (
    sp.foto_asset is null
    or (seed.destaque and not sp.destaque)
  );

create or replace function api.mindagent_bootstrap(p_event_slug text default 'mind-summit-2026'::text)
returns jsonb
language sql
stable security definer
set search_path to 'pg_catalog', 'summit_2026', 'ecossistema', 'concierge'
as $function$
with ev as (
  select e.* from summit_2026.events e
  where e.slug=p_event_slug and e.ativo
  limit 1
), cfg as (
  select coalesce(c.valor,'{}'::jsonb) v
  from concierge.config c where c.chave='home'
), temas_da_grade as (
  select t.codigo,
    case t.codigo
      when 'seguranca_psicologica' then 'Segurança psicológica'
      when 'dados_bem_estar' then 'Dados e ROI do bem-estar'
      when 'regulacao' then 'NR-1 e riscos psicossociais'
      when 'lideranca_humana' then 'Liderança'
      when 'cultura' then 'Cultura organizacional'
      when 'saude_mental' then 'Saúde mental'
      when 'performance' then 'Performance sustentável'
      when 'diversidade' then 'Diversidade e inclusão'
      when 'felicidade' then 'Felicidade e propósito'
      when 'futuro_trabalho' then 'Futuro do trabalho'
      else initcap(replace(t.codigo,'_',' '))
    end rotulo
  from (
    select distinct jsonb_array_elements_text(coalesce(s.topicos_aprendizado,'[]'::jsonb)) codigo
    from summit_2026.sessions s join ev e on e.id=s.event_id
  ) t
)
select jsonb_build_object(
  '_meta',jsonb_build_object('schema_version','1.0','event_slug',p_event_slug,'generated_at',now()),
  '_nota','Dados oficiais do Supabase. Informações ausentes não devem ser inventadas.',
  'evento',(select jsonb_build_object(
    'nome',e.nome,'dias',e.dias,'local',e.local,
    'regra_reserva',(select r.texto from summit_2026.event_rules r
      where r.ativo and r.chave='reserva_expira' and (r.event_id is null or r.event_id=e.id)
      order by r.event_id nulls last limit 1),
    'regra_vagas',(select r.texto from summit_2026.event_rules r
      where r.ativo and r.chave='vagas_limitadas' and (r.event_id is null or r.event_id=e.id)
      order by r.event_id nulls last limit 1)
  ) from ev e),
  'temas',coalesce((select jsonb_agg(jsonb_build_object('codigo',codigo,'rotulo',rotulo) order by rotulo)
    from temas_da_grade),'[]'::jsonb),
  'sessoes',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',coalesce(s.yazo_id,s.id::text),
      'dia',s.dia,
      'inicio',to_char(s.inicio at time zone e.fuso,'HH24:MI'),
      'fim',to_char(s.fim at time zone e.fuso,'HH24:MI'),
      'titulo',s.titulo,
      'descricao',coalesce(s.descricao,''),
      'quem',coalesce((select string_agg(sp.nome,'; ' order by sp.nome)
        from summit_2026.session_speakers ss
        join ecossistema.palestrantes_especialistas sp on sp.id=ss.speaker_id
        where ss.sessao_id=s.id),'Em breve'),
      'espaco',l.nome,
      'formato',coalesce(s.tipo,s.formato,'sessao'),
      'etiqueta',initcap(replace(coalesce(s.tipo,s.formato,'sessão'),'-',' ')),
      'trilhas',coalesce(s.ingressos,'{}'::text[]),
      'vaga_limitada',coalesce(s.precisa_reserva,false),
      'online',lower(coalesce(s.formato,'')) in ('remoto','online','virtual'),
      'temas',coalesce(s.topicos_aprendizado,'[]'::jsonb)
    ) order by s.inicio,s.titulo)
    from summit_2026.sessions s
    join ev e on e.id=s.event_id
    left join summit_2026.locations l on l.id=s.espaco_id
  ),'[]'::jsonb),
  'pessoas',coalesce((
    select jsonb_agg(jsonb_build_object(
      'nome',sp.nome,
      'credencial',concat_ws(' · ',nullif(sp.cargo_curto,''),nullif(sp.instituicao,'')),
      'resumo',coalesce(sp.quem_e,''),
      'foto',sp.foto_asset,
      'destaque',sp.destaque,
      'na_grade',true,
      'temas',coalesce((select jsonb_agg(distinct t)
        from summit_2026.session_speakers ss2
        join summit_2026.sessions sx2 on sx2.id=ss2.sessao_id
        join ev e2 on e2.id=sx2.event_id
        cross join lateral jsonb_array_elements_text(coalesce(sx2.topicos_aprendizado,'[]'::jsonb)) t
        where ss2.speaker_id=sp.id),'[]'::jsonb)
    ) order by sp.nome)
    from ecossistema.palestrantes_especialistas sp
    where exists (
      select 1 from summit_2026.session_speakers ss
      join summit_2026.sessions sx on sx.id=ss.sessao_id
      join ev e on e.id=sx.event_id
      where ss.speaker_id=sp.id
    )
  ),'[]'::jsonb),
  'avisos',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',coalesce(a.chave,a.id::text),
      'icone',a.icone,
      'em',to_char(a.disparo_em at time zone coalesce((select fuso from ev),'America/Sao_Paulo'),'YYYY-MM-DD"T"HH24:MI'),
      'situacao',a.situacao,
      'titulo',a.titulo,
      'resumo',a.subtitulo,
      'mensagem',a.descricao,
      'verNoApp',a.ver_no_app,
      'botaoVerNoApp',a.botao_ver_no_app
    ) order by a.disparo_em desc nulls last)
    from concierge.avisos a
    where (a.situacao='no-ar' or (a.situacao='agendado' and a.disparo_em<=now()))
      and (a.event_id is null or a.event_id=(select id from ev))
  ),'[]'::jsonb),
  'home',coalesce((
    select jsonb_build_object(
      'momento',case when v->>'modo'='programado' then coalesce((
        select troca->>'momento'
        from jsonb_array_elements(coalesce(v->'trocas','[]'::jsonb)) troca
        where coalesce((troca->>'arquivada')::boolean,false) is false
          and replace(troca->>'quando','T',' ')::timestamp
            at time zone coalesce((select fuso from ev),'America/Sao_Paulo')<=now()
        order by troca->>'quando' desc limit 1
      ),v->>'momento','antes') else coalesce(v->>'momento','antes') end,
      'modo',coalesce(v->>'modo','manual'))
    from cfg
  ),jsonb_build_object('momento','antes','modo','manual'))
);
$function$;

revoke all on function api.mindagent_bootstrap(text) from public;
grant execute on function api.mindagent_bootstrap(text) to anon,authenticated,service_role;

create or replace function public.mindagent_bootstrap(p_event_slug text default 'mind-summit-2026'::text)
returns jsonb
language sql
stable security invoker
set search_path to 'pg_catalog','api'
as $function$
  select api.mindagent_bootstrap(p_event_slug);
$function$;

revoke all on function public.mindagent_bootstrap(text) from public;
grant execute on function public.mindagent_bootstrap(text) to anon,authenticated,service_role;

do $verify$
declare
  v_seeded integer;
  v_highlights integer;
  v_expected_photos integer;
  v_delivered_photos integer;
  v_access_mismatches integer;
begin
  select count(*) into v_seeded
  from ecossistema.palestrantes_especialistas
  where foto_asset is not null;

  if v_seeded < 39 then
    raise exception 'Esperava ao menos 39 fotos canônicas, encontrei %', v_seeded;
  end if;

  select count(*) into v_highlights
  from ecossistema.palestrantes_especialistas
  where slug in ('amy-edmondson','christina-maslach','jan-emmanuel-de-neve','sonja-lyubomirsky')
    and destaque;

  if v_highlights <> 4 then
    raise exception 'Destaques canônicos incompletos: % de 4', v_highlights;
  end if;

  select count(distinct sp.id) into v_expected_photos
  from ecossistema.palestrantes_especialistas sp
  join summit_2026.session_speakers ss on ss.speaker_id=sp.id
  join summit_2026.sessions s on s.id=ss.sessao_id
  join summit_2026.events e on e.id=s.event_id
  where e.slug='mind-summit-2026' and e.ativo and sp.foto_asset is not null;

  select count(*) into v_delivered_photos
  from jsonb_array_elements(api.mindagent_bootstrap('mind-summit-2026')->'pessoas') p
  where nullif(p->>'foto','') is not null;

  if v_delivered_photos <> v_expected_photos then
    raise exception 'Bootstrap entregou % fotos; esperado %', v_delivered_photos, v_expected_photos;
  end if;

  select count(*) into v_access_mismatches
  from jsonb_array_elements(api.mindagent_bootstrap('mind-summit-2026')->'sessoes') payload
  join summit_2026.sessions s
    on coalesce(s.yazo_id,s.id::text)=payload->>'id'
  join summit_2026.events e on e.id=s.event_id
  where e.slug='mind-summit-2026' and e.ativo
    and payload->'trilhas' is distinct from to_jsonb(coalesce(s.ingressos,'{}'::text[]));

  if v_access_mismatches <> 0 then
    raise exception 'Bootstrap possui % divergências de acesso', v_access_mismatches;
  end if;
end
$verify$;

commit;
