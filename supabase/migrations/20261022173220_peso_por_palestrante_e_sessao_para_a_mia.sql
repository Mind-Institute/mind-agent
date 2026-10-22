-- Peso por palestrante e por sessão para a MIA Summit 2026 (Adriana, 22/10/2026):
-- "quando alguém pedir um resumo, qual peso dar a qual palestrante". Três níveis, editáveis no painel.
-- Sugestão inicial por regra (ela confirma ou altera no painel):
--   palestrante: destaque → principal; só alumni-talk/lançamento/autógrafos → complementar; resto → relevante
--   sessão: abertura e masterclass → principal; qualquer palestrante principal → principal;
--           palestra/painel/workshop/entrevista → relevante; alumni-talk/lançamento/experiência → complementar;
--           almoço/intervalo/credenciamento/autógrafos → complementar
-- Colunas em casas existentes (sem tabela nova). A busca pondera o score pelo peso efetivo do documento
-- (o maior entre o da sessão e o dos palestrantes) e devolve o peso em cada candidato.

alter table ecossistema.palestrantes_especialistas
  add column if not exists peso_mia text not null default 'relevante';
alter table ecossistema.palestrantes_especialistas
  drop constraint if exists palestrantes_especialistas_peso_mia_check;
alter table ecossistema.palestrantes_especialistas
  add constraint palestrantes_especialistas_peso_mia_check check (peso_mia in ('principal','relevante','complementar'));
comment on column ecossistema.palestrantes_especialistas.peso_mia is
  'Peso do palestrante para a MIA Summit 2026 (principal/relevante/complementar). Editável no painel; sugestão inicial por regra em 22/10/2026.';

alter table summit_2026.sessions
  add column if not exists peso_mia text not null default 'relevante';
alter table summit_2026.sessions
  drop constraint if exists sessions_peso_mia_check;
alter table summit_2026.sessions
  add constraint sessions_peso_mia_check check (peso_mia in ('principal','relevante','complementar'));
comment on column summit_2026.sessions.peso_mia is
  'Peso da sessão para a MIA Summit 2026 (principal/relevante/complementar). Editável no painel; sugestão inicial por regra em 22/10/2026.';

-- Sugestão inicial (só onde ainda está no default, para nunca sobrescrever uma escolha da Adriana).
update ecossistema.palestrantes_especialistas p
   set peso_mia = case
     when p.destaque then 'principal'
     when exists (select 1 from summit_2026.session_speakers ss join summit_2026.sessions s on s.id = ss.sessao_id
                   where ss.speaker_id = p.id and s.tipo in ('abertura','palestra','painel','workshop','masterclass','entrevista'))
          then 'relevante'
     when exists (select 1 from summit_2026.session_speakers ss where ss.speaker_id = p.id) then 'complementar'
     else 'relevante' end
 where p.peso_mia = 'relevante';

update summit_2026.sessions s
   set peso_mia = case
     when s.tipo in ('abertura','masterclass') then 'principal'
     when exists (select 1 from summit_2026.session_speakers ss join ecossistema.palestrantes_especialistas p on p.id = ss.speaker_id
                   where ss.sessao_id = s.id and p.peso_mia = 'principal') then 'principal'
     when s.tipo in ('palestra','painel','workshop','entrevista') then 'relevante'
     else 'complementar' end
 where s.peso_mia = 'relevante';

-- Peso efetivo de um documento do Summit: o maior entre o da sessão e o dos palestrantes dela.
create or replace function public.mind_summit_peso_sessao(p_sessao_id uuid)
 returns text
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  with n as (
    select greatest(
      coalesce((select case s.peso_mia when 'principal' then 3 when 'relevante' then 2 else 1 end
                  from summit_2026.sessions s where s.id = p_sessao_id), 2),
      coalesce((select max(case p.peso_mia when 'principal' then 3 when 'relevante' then 2 else 1 end)
                  from summit_2026.session_speakers ss
                  join ecossistema.palestrantes_especialistas p on p.id = ss.speaker_id
                 where ss.sessao_id = p_sessao_id), 0)) v
  )
  select case v when 3 then 'principal' when 2 then 'relevante' else 'complementar' end from n;
$function$;
revoke all on function public.mind_summit_peso_sessao(uuid) from public, anon, authenticated;
grant execute on function public.mind_summit_peso_sessao(uuid) to service_role;

-- Busca: pondera pelo peso e devolve o peso no candidato. Fichas de sessão e mapa temático (derivados da
-- transcrição) obedecem ao mesmo gate `summit_content` que a transcrição.
CREATE OR REPLACE FUNCTION public.mind_intelligence_buscar_contextual(p_necessidade text, p_limite integer DEFAULT 6, p_rota text DEFAULT NULL::text, p_canal text DEFAULT NULL::text, p_produto_codigo text DEFAULT NULL::text, p_embedding vector DEFAULT NULL::vector)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with cfg as (
    select least(10,greatest(1,coalesce(p_limite,6))) n,
           plainto_tsquery('portuguese',coalesce(btrim(p_necessidade),'')) q
  ), docs as (
    select 'summit_2026' origem,d.id,d.titulo,d.tipo_conteudo,d.ativo,d.agents,d.aprovado_treble,
           d.produto_codigo,d.valido_de,d.valido_ate,d.sessao_id
      from summit_2026.knowledge_documents d
     where coalesce(p_rota,'') in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte','mia_summit_2026')
    union all
    select 'institute',d.id,d.titulo,d.tipo_conteudo,d.ativo,d.agents,d.aprovado_treble,
           d.produto_codigo,d.valido_de,d.valido_ate,null::uuid
      from institute.knowledge_documents d where p_rota='institute'
    union all
    select 'dash',d.id,d.titulo,d.tipo_conteudo,d.ativo,d.agents,d.aprovado_treble,
           d.produto_codigo,d.valido_de,d.valido_ate,null::uuid
      from dash.knowledge_documents d where p_rota='dash'
  ), conteudo_liberado as (
    select exists (
      select 1 from agentes.knowledge_access ka
       where ka.agent_key = p_rota
         and ka.knowledge_namespace = 'business'
         and ka.knowledge_key = 'summit_content'
         and ka.enabled) liberado
  ), permitidos as (
    select d.*,
           case when d.origem='summit_2026' and d.sessao_id is not null
                then public.mind_summit_peso_sessao(d.sessao_id) end peso
      from docs d cross join conteudo_liberado cl
    where d.ativo
      and (d.valido_de is null or d.valido_de<=now())
      and (d.valido_ate is null or d.valido_ate>now())
      and (d.produto_codigo is null or p_produto_codigo is null or d.produto_codigo=p_produto_codigo)
      and (coalesce(p_canal,'')<>'whatsapp' or d.aprovado_treble)
      and (coalesce(p_canal,'')='whatsapp' or cardinality(d.agents)=0 or 'concierge'=any(d.agents))
      and (d.origem <> 'summit_2026'
           or coalesce(d.tipo_conteudo,'') not in ('transcricao','slides','ficha_sessao','mapa_tematico')
           or cl.liberado)
  ), chunks as (
    select 'summit_2026' origem,c.* from summit_2026.knowledge_chunks c
    union all select 'institute',c.* from institute.knowledge_chunks c
    union all select 'dash',c.* from dash.knowledge_chunks c
  ), texto as (
    select c.origem,c.id,c.doc_id,
           row_number() over(order by ts_rank_cd(c.tsv,cfg.q) desc) pos
    from chunks c join permitidos d on d.origem=c.origem and d.id=c.doc_id cross join cfg
    where c.tsv@@cfg.q
    order by pos limit (select n*4 from cfg)
  ), vetor as (
    select c.origem,c.id,c.doc_id,
           row_number() over(order by c.embedding OPERATOR(public.<=>) p_embedding) pos
    from chunks c join permitidos d on d.origem=c.origem and d.id=c.doc_id cross join cfg
    where p_embedding is not null and c.embedding is not null and not c.stale
      and c.modelo_embedding='text-embedding-3-small'
    order by pos limit (select n*4 from cfg)
  ), fundido as (
    select x.origem,x.id,x.doc_id,
           sum(x.score) * case d.peso when 'principal' then 1.25 when 'complementar' then 0.85 else 1.0 end score
    from (
      select origem,id,doc_id,1.0/(60+pos) score from texto
      union all
      select origem,id,doc_id,1.0/(60+pos) score from vetor
    ) x join permitidos d on d.origem=x.origem and d.id=x.doc_id
    group by x.origem,x.id,x.doc_id,d.peso
  ), conhecimento as (
    select distinct on (d.origem,d.id)
      jsonb_strip_nulls(jsonb_build_object(
        'tipo','conhecimento',
        'id',d.origem || ':' || d.id::text
             || case when d.origem='summit_2026' and coalesce(d.tipo_conteudo,'') in ('transcricao','slides')
                     then ':' || c.ordem::text else '' end,
        'titulo',d.titulo,
        'categoria',case when d.origem='summit_2026' then d.tipo_conteudo end,
        'peso',d.peso,
        'resumo',left(c.texto,case when coalesce(d.tipo_conteudo,'') in ('transcricao','slides','ficha_sessao') then 320 else 220 end),
        'fonte',d.origem,
        'score',round(f.score::numeric,6))) candidato,
      f.score
    from fundido f
    join chunks c on c.origem=f.origem and c.id=f.id
    join permitidos d on d.origem=f.origem and d.id=f.doc_id
    order by d.origem,d.id,f.score desc
  ), busca_evento as (
    select case when coalesce(p_rota,'') in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte','mia_summit_2026')
      then public.mindagent_chat_search('mind-summit-2026',p_necessidade,(select n from cfg))
      else '{}'::jsonb end j
  ), foco as (
    select nullif(string_agg(quote_literal(l.lexeme),' | '),'')::tsquery q
    from unnest(to_tsvector('portuguese',coalesce(btrim(p_necessidade),''))) l
    where l.lexeme not in ('event','mind','summit')
  ), locais as (
    select jsonb_build_object('tipo','local','id',l.id::text,'titulo',l.nome,
      'resumo',nullif(concat_ws(' · ',nullif(l.tipo,''),nullif(l.andar,''),nullif(l.descricao,''),
        nullif(l.como_chegar,''),
        case when cardinality(l.aliases)>0 then 'também chamado: '||array_to_string(l.aliases,', ') end),'')) candidato,
      (0.02+ts_rank_cd(to_tsvector('portuguese',l.nome||' '||coalesce(l.slug,'')||' '||
        coalesce(array_to_string(l.aliases,' '),'')||' '||coalesce(l.descricao,'')||' '||coalesce(l.como_chegar,'')),f.q))::double precision score
    from summit_2026.locations l
    join summit_2026.events e on e.id=l.event_id and e.slug='mind-summit-2026' and e.ativo
    cross join foco f
    where coalesce(p_rota,'') in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte','mia_summit_2026')
      and f.q is not null and l.ativo
      and to_tsvector('portuguese',l.nome||' '||coalesce(l.slug,'')||' '||
        coalesce(array_to_string(l.aliases,' '),'')||' '||coalesce(l.descricao,'')||' '||coalesce(l.como_chegar,''))@@f.q
    order by score desc limit 2
  ), outros as (
    select jsonb_build_object('tipo','palestrante','id',e->>'id','titulo',e->>'name',
      'resumo',nullif(concat_ws(' · ',nullif(e->>'role',''),nullif(e->>'organization','')),'')) candidato,
      0.01::double precision score
    from busca_evento,lateral jsonb_array_elements(coalesce(j->'speakers','[]'::jsonb)) e
    union all
    select jsonb_build_object('tipo','sessao','id',e->>'id','titulo',e->>'title',
      'resumo',nullif(concat_ws(' · ',nullif(e->>'type',''),nullif(e->>'starts_at_local',''),nullif(e->>'location','')),'')),
      0.01::double precision
    from busca_evento,lateral jsonb_array_elements(coalesce(j->'sessions','[]'::jsonb)) e
  ), todos as (
    select candidato,score from conhecimento
    union all select candidato,score from outros
    union all select candidato,score from locais
  )
  select jsonb_build_object(
    'necessidade',p_necessidade,
    'escopo',jsonb_build_object('rota',p_rota,'canal',p_canal,'produto_codigo',p_produto_codigo),
    'motor',case when p_embedding is null then 'lexical' else 'hibrido' end,
    'candidatos',coalesce((select jsonb_agg(candidato order by score desc,candidato->>'titulo')
      from (select * from todos order by score desc limit (select n from cfg)) z),'[]'::jsonb),
    'total',coalesce((select count(*) from (select * from todos limit (select n from cfg)) z),0),
    'como_usar','Leia o candidato relevante com ler_intelligence. Resultado vazio não autoriza completar de memória. Em "categoria": ficha_sessao é a nota de uma sessão inteira (boa para panoramas); transcricao é a fala literal (boa para citar). "peso" (principal/relevante/complementar) é a importância que a curadoria dá à sessão e aos palestrantes.'
  );
$function$;

-- Leitura: o mesmo gate para ficha e mapa, e o peso no cabeçalho do que é do Summit.
CREATE OR REPLACE FUNCTION public.mind_intelligence_ler_contextual(p_tipo text, p_id text, p_rota text DEFAULT NULL::text, p_canal text DEFAULT NULL::text, p_produto_codigo text DEFAULT NULL::text, p_corte integer DEFAULT 1200)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case lower(coalesce(p_tipo,''))
    when 'palestrante' then public.mind_intelligence_ler('palestrante',p_id,p_corte)
    when 'sessao' then public.mind_intelligence_ler('sessao',p_id,p_corte)
    when 'conhecimento' then (
      with alvo as (
        select case when p_id like '%:%' then split_part(p_id,':',1) else 'summit_2026' end origem,
               case when p_id like '%:%' then split_part(p_id,':',2) else p_id end id,
               case when split_part(p_id,':',3) ~ '^[0-9]{1,5}$' then split_part(p_id,':',3)::int end ordem
      ), docs as (
        select 'summit_2026' origem,d.id,d.titulo,d.corpo,d.tipo_conteudo,d.problema,d.resultado_desejado,
               d.autor,d.url,d.ativo,d.agents,d.aprovado_treble,d.produto_codigo,d.valido_de,d.valido_ate,
               d.cluster,d.audiencia,d.sessao_id
          from summit_2026.knowledge_documents d
        union all
        select 'institute',d.id,d.titulo,d.corpo,d.tipo_conteudo,d.problema,d.resultado_desejado,
               d.autor,d.url,d.ativo,d.agents,d.aprovado_treble,d.produto_codigo,d.valido_de,d.valido_ate,
               d.cluster,d.audiencia,null::uuid
          from institute.knowledge_documents d
        union all
        select 'dash',d.id,d.titulo,d.corpo,d.tipo_conteudo,d.problema,d.resultado_desejado,
               d.autor,d.url,d.ativo,d.agents,d.aprovado_treble,d.produto_codigo,d.valido_de,d.valido_ate,
               d.cluster,d.audiencia,null::uuid
          from dash.knowledge_documents d
      ), conteudo_liberado as (
        select exists (
          select 1 from agentes.knowledge_access ka
           where ka.agent_key = p_rota
             and ka.knowledge_namespace = 'business'
             and ka.knowledge_key = 'summit_content'
             and ka.enabled) liberado
      )
      select jsonb_strip_nulls(jsonb_build_object(
        'tipo','conhecimento',
        'id',d.origem || ':' || d.id::text || case when t.trecho then ':' || coalesce(a.ordem,1)::text else '' end,
        'titulo',d.titulo,'categoria',d.tipo_conteudo,'problema',d.problema,
        'resultado_desejado',d.resultado_desejado,'audiencia',d.audiencia,
        'cluster',d.cluster,
        'peso',case when d.origem='summit_2026' and d.sessao_id is not null then public.mind_summit_peso_sessao(d.sessao_id) end,
        'corpo',case when t.trecho then coalesce((
                    select left(string_agg(c.texto, E'\n\n' order by c.ordem), 12000)
                      from summit_2026.knowledge_chunks c
                     where c.doc_id = d.id and c.indice = 'principal'
                       and c.ordem between coalesce(a.ordem,1) - 1 and coalesce(a.ordem,1) + 1),
                    public.mind_txt_corta(d.corpo,greatest(200,least(4000,coalesce(p_corte,1200)))*3))
                  else public.mind_txt_corta(d.corpo,greatest(200,least(4000,coalesce(p_corte,1200)))*3) end,
        'autor',d.autor,
        'url',case when t.trecho then null else d.url end,
        'produto_codigo',d.produto_codigo))
      from docs d join alvo a on a.origem=d.origem and d.id::text=a.id
      cross join conteudo_liberado cl
      cross join lateral (
        select d.origem='summit_2026' and coalesce(d.tipo_conteudo,'') in ('transcricao','slides') trecho,
               d.origem='summit_2026' and coalesce(d.tipo_conteudo,'') in ('transcricao','slides','ficha_sessao','mapa_tematico') derivado) t
      where d.ativo
        and (d.valido_de is null or d.valido_de<=now())
        and (d.valido_ate is null or d.valido_ate>now())
        and (d.produto_codigo is null or p_produto_codigo is null or d.produto_codigo=p_produto_codigo)
        and (coalesce(p_canal,'')<>'whatsapp' or d.aprovado_treble)
        and (coalesce(p_canal,'')='whatsapp' or cardinality(d.agents)=0 or 'concierge'=any(d.agents))
        and (not t.derivado or cl.liberado)
        and (
          (p_rota in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte','mia_summit_2026') and d.origem='summit_2026')
          or (p_rota='institute' and d.origem='institute')
          or (p_rota='dash' and d.origem='dash')
        )
      limit 1
    )
    else null end;
$function$;

-- Painel: leitura e edição dos pesos (só administrador escreve).
create or replace function public.mind_admin_read_summit_pesos(p_id text default null)
 returns setof jsonb
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  select jsonb_build_object(
    'id', 'palestrante:' || p.id::text,
    'tipo', 'palestrante',
    'nome', p.nome,
    'detalhe', nullif(concat_ws(' · ', nullif(p.cargo_curto,''), nullif(p.instituicao,'')), ''),
    'destaque', p.destaque,
    'fichaCurada', nullif(btrim(coalesce(p.relevancia_para_os_icps_do_mind,'')),'') is not null,
    'peso', p.peso_mia,
    'sessoes', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'titulo', s.titulo, 'tipo', s.tipo) order by s.inicio)
                           from summit_2026.session_speakers ss join summit_2026.sessions s on s.id = ss.sessao_id
                          where ss.speaker_id = p.id), '[]'::jsonb),
    'atualizadoEm', p.atualizado_em)
  from ecossistema.palestrantes_especialistas p
  where p_id is null or 'palestrante:' || p.id::text = p_id
  union all
  select jsonb_build_object(
    'id', 'sessao:' || s.id::text,
    'tipo', 'sessao',
    'nome', s.titulo,
    'detalhe', concat_ws(' · ', s.tipo, to_char(s.dia, 'DD/MM'), to_char(s.inicio at time zone 'America/Sao_Paulo', 'HH24:MI')),
    'tipoSessao', s.tipo,
    'temTranscricao', exists (select 1 from summit_2026.knowledge_documents d where d.sessao_id = s.id and d.tipo_conteudo = 'transcricao' and d.ativo),
    'peso', s.peso_mia,
    'pesoEfetivo', public.mind_summit_peso_sessao(s.id),
    'palestrantes', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'nome', p.nome, 'peso', p.peso_mia) order by p.nome)
                                from summit_2026.session_speakers ss join ecossistema.palestrantes_especialistas p on p.id = ss.speaker_id
                               where ss.sessao_id = s.id), '[]'::jsonb),
    'atualizadoEm', s.atualizado_em)
  from summit_2026.sessions s
  where p_id is null or 'sessao:' || s.id::text = p_id;
$function$;
revoke all on function public.mind_admin_read_summit_pesos(text) from public, anon, authenticated;
grant execute on function public.mind_admin_read_summit_pesos(text) to service_role;

create or replace function public.mind_admin_update_summit_peso(p_id text, p_peso text, p_ator uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_role text;
  v_tipo text := split_part(p_id, ':', 1);
  v_chave text := split_part(p_id, ':', 2);
  v_n int;
begin
  select a.role into v_role from public.mind_admin_users a where a.user_id = p_ator and a.active;
  if v_role is distinct from 'administrador' then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;
  if p_peso not in ('principal','relevante','complementar') then
    raise exception using errcode = '22023', message = 'admin_validation:peso';
  end if;
  if v_tipo = 'palestrante' and v_chave ~ '^[0-9]{1,12}$' then
    update ecossistema.palestrantes_especialistas set peso_mia = p_peso, atualizado_em = now() where id = v_chave::bigint;
  elsif v_tipo = 'sessao' and v_chave ~* '^[0-9a-f-]{36}$' then
    update summit_2026.sessions set peso_mia = p_peso, atualizado_em = now() where id = v_chave::uuid;
  else
    raise exception using errcode = '22023', message = 'admin_validation:id';
  end if;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception using errcode = 'P0002', message = 'admin_not_found';
  end if;
  return (select x from public.mind_admin_read_summit_pesos(p_id) x limit 1);
end;
$function$;
revoke all on function public.mind_admin_update_summit_peso(text, text, uuid) from public, anon, authenticated;
grant execute on function public.mind_admin_update_summit_peso(text, text, uuid) to service_role;
