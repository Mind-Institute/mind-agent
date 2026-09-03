-- O BOOTSTRAP DO APP VOLTA A LER O SCHEMA QUE EXISTE.
--
-- `api.mindagent_bootstrap` é a única porta pela qual o App carrega evento, temas, sessões e
-- palestrantes (`data-service.js` → Edge `mindagent-bootstrap` → esta função). Desde a faxina
-- de 22/08 ela lia `summit.*` e `comum.*`, que não existem mais: `relation "summit.events"
-- does not exist` → PostgREST 404 → Edge 503 em todo carregamento, e o App preso no
-- `dados/summit.json` de 28/08 (53 das 77 sessões). Com a taxonomia e a curadoria de
-- palestrantes de volta ao banco (migration anterior), agora dá para reapontar sem
-- regressão — o gate #26 pedia exatamente isso, "não pela metade".
--
-- MESMO CONTRATO DE SAÍDA, mais dois campos aditivos:
--   * `sessoes[].tipo`   — o tipo verdadeiro da sessão (alumni-talk, autografos, ...);
--   * `sessoes[].formato` continua sendo o BALDE que o App filtra (palestra, painel,
--     masterclass, workshop, experiencia): alumni talks e a entrevista entram como palestra;
--     abertura, autógrafos, lançamentos, credenciamento, intervalos, almoços e "em curadoria"
--     entram como experiência, como o JSON de 28/08 já fazia;
--   * `etiqueta` = rótulo da taxonomia + sufixo do ingresso (" Prime" / " VIP"), a mesma
--     convenção do site e do JSON ("Masterclass Prime", "Workshop VIP", "Autógrafos Prime");
--   * `trilhas` = `ingressos` da sessão (quem pode entrar) — o mesmo significado de antes;
--   * `sessoes[].id` = `site_session_id`, a chave estável do site;
--   * `pessoas[]` sai de `ecossistema.palestrantes_especialistas` + `speaker_profiles`; sem
--     perfil curado, credencial vem de cargo · instituição, o resumo é a primeira frase de
--     `quem_e` (ou os primeiros 240 caracteres, cortados em palavra) e os temas são os
--     das sessões da pessoa — derivados, nunca inventados. Sem cargo e instituição no
--     banco, a credencial fica vazia: o App já rotula a pessoa como Palestrante.
create or replace function api.mindagent_bootstrap(p_event_slug text default 'mind-summit-2026')
returns jsonb
language sql
stable security definer
set search_path to 'pg_catalog', 'summit_2026', 'ecossistema', 'engagement', 'intelligence'
as $function$
with ev as (
  select e.* from summit_2026.events e where e.slug = p_event_slug and e.ativo limit 1
),
tema as (
  select t.codigo, t.rotulo, t.ordem from ecossistema.taxonomy t where t.tipo = 'tema' and t.ativo
),
rotulo_tipo as (
  select t.codigo, t.rotulo from ecossistema.taxonomy t where t.tipo = 'tipo_sessao' and t.ativo
),
sessao as (
  select s.*, e.fuso, l.nome as espaco_nome,
         case when s.tipo in ('palestra','painel','masterclass','workshop') then s.tipo
              when s.tipo in ('alumni-talk','entrevista') then 'palestra'
              else 'experiencia' end as formato_app,
         case when s.ingressos = array['prime']::text[] then ' Prime'
              when s.ingressos is not null and not ('mind' = any(s.ingressos)) and 'vip' = any(s.ingressos) then ' VIP'
              else '' end as sufixo_ingresso,
         case when jsonb_typeof(s.topicos_aprendizado) = 'array' then s.topicos_aprendizado else '[]'::jsonb end as temas_sessao
  from summit_2026.sessions s
  join ev e on e.id = s.event_id
  left join summit_2026.locations l on l.id = s.espaco_id
),
palestrante as (
  select p.id, p.nome, p.cargo_curto, p.instituicao, p.quem_e,
         pr.credencial, pr.resumo, pr.foto, coalesce(pr.destaque, false) as destaque,
         pr.temas as temas_curados
  from ecossistema.palestrantes_especialistas p
  left join summit_2026.speaker_profiles pr on pr.speaker_id = p.id
  where exists (select 1 from summit_2026.session_speakers ss join sessao sx on sx.id = ss.sessao_id
                 where ss.speaker_id = p.id)
)
select jsonb_build_object(
  '_meta', jsonb_build_object('schema_version', '1.1', 'event_slug', p_event_slug, 'generated_at', now()),
  '_nota', 'Dados oficiais do Supabase. Informações ausentes não devem ser inventadas.',
  'evento', (select jsonb_build_object(
    'nome', e.nome,
    'dias', to_jsonb(e.dias),
    'local', e.local,
    'regra_reserva', (select r.texto from summit_2026.event_rules r
                       where r.ativo and r.chave = 'reserva_expira' and (r.event_id is null or r.event_id = e.id)
                       order by r.event_id nulls last limit 1),
    'regra_vagas', (select r.texto from summit_2026.event_rules r
                     where r.ativo and r.chave = 'vagas_limitadas' and (r.event_id is null or r.event_id = e.id)
                     order by r.event_id nulls last limit 1)
  ) from ev e),
  'temas', coalesce((
    select jsonb_agg(jsonb_build_object('codigo', t.codigo, 'rotulo', t.rotulo) order by t.ordem, t.rotulo)
    from tema t), '[]'::jsonb),
  'sessoes', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', coalesce(s.site_session_id, s.yazo_id, s.id::text),
      'dia', s.dia,
      'inicio', to_char(s.inicio at time zone s.fuso, 'HH24:MI'),
      'fim', to_char(s.fim at time zone s.fuso, 'HH24:MI'),
      'titulo', s.titulo,
      'descricao', coalesce(s.descricao, ''),
      'quem', coalesce((
        select string_agg(p.nome, '; ' order by p.nome)
        from summit_2026.session_speakers ss
        join ecossistema.palestrantes_especialistas p on p.id = ss.speaker_id
        where ss.sessao_id = s.id), 'Em breve'),
      'espaco', s.espaco_nome,
      'tipo', s.tipo,
      'formato', s.formato_app,
      'etiqueta', coalesce((select rt.rotulo from rotulo_tipo rt where rt.codigo = s.tipo),
                           initcap(coalesce(s.tipo, 'Sessão'))) || s.sufixo_ingresso,
      'trilhas', to_jsonb(coalesce(s.ingressos, '{}'::text[])),
      'vaga_limitada', coalesce(s.precisa_reserva, false),
      'online', lower(coalesce(s.formato, '')) in ('remoto', 'online', 'virtual'),
      'temas', s.temas_sessao
    ) order by s.dia, s.inicio, s.titulo)
    from sessao s), '[]'::jsonb),
  'pessoas', coalesce((
    select jsonb_agg(jsonb_build_object(
      'nome', p.nome,
      'credencial', coalesce(nullif(p.credencial, ''),
                             concat_ws(' · ', nullif(p.cargo_curto, ''), nullif(p.instituicao, ''))),
      'resumo', coalesce(nullif(p.resumo, ''),
                         substring(p.quem_e from '^.{20,255}?[.!?](?=\s|$)'),
                         nullif(regexp_replace(left(coalesce(p.quem_e, ''), 240), '\s+\S*$', ''), '') || '…',
                         ''),
      'foto', p.foto,
      'destaque', p.destaque,
      'na_grade', true,
      'temas', coalesce(p.temas_curados, (
        select coalesce(jsonb_agg(distinct t), '[]'::jsonb)
        from summit_2026.session_speakers ss
        join sessao sx on sx.id = ss.sessao_id,
        jsonb_array_elements(sx.temas_sessao) t
        where ss.speaker_id = p.id))
    ) order by p.destaque desc, p.nome)
    from palestrante p), '[]'::jsonb)
);
$function$;

-- A Edge chama com a chave pública: anon precisa continuar podendo executar.
revoke all on function api.mindagent_bootstrap(text) from public;
grant execute on function api.mindagent_bootstrap(text) to anon, authenticated, service_role;
