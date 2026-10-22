-- Busca e leitura do conhecimento: conserto, rota de conteúdo, trava pela matriz e trecho.
-- Aprovado pela Adriana em 22/10/2026 (D7, itens D/P3/P4/P5 da proposta).
--
-- 1) CONSERTO. mind_intelligence_buscar_contextual e mind_intelligence_ler_contextual
--    juntavam summit_2026/institute/dash com `d.*`. Quando summit_2026.knowledge_documents
--    ganhou sessao_id, transcrito e slides (27–29/09), toda chamada passou a falhar com
--    "each UNION query must have the same number of columns": os agentes no ar ficaram
--    sem buscar_intelligence e ler_intelligence. Agora as colunas são explícitas.
-- 2) ROTA. mia_summit_2026 (MIA Summit 2026) lê o conhecimento do Summit, como as outras rotas do Summit.
-- 3) TRAVA. Transcrição e slides do Summit só aparecem para o agente que tem
--    "Conteúdo do Summit" (business/summit_content) ligado em Agent Intelligence
--    (agentes.knowledge_access). Os demais documentos seguem a regra de antes.
-- 4) TRECHO. Para transcrição e slides, a busca devolve o trecho (id origem:doc:ordem) e a
--    leitura entrega esse trecho e os vizinhos, com sessão, palestrantes e minuto, sem o
--    link interno do Drive. Antes a leitura entregava só o começo do documento.
-- 5) FATIAMENTO. Transcrição: parágrafos agrupados em ~3.000 caracteres, cortando nos
--    marcadores [hh:mm:ss], com cabeçalho "Transcrição · sessão · palestrantes · [início–fim]".
--    Slides: blocos de ~3.000 caracteres com cabeçalho. O resto continua como estava.
--    Trecho que deixar de existir numa nova fatiada fica vazio (não é apagado).
-- 6) LIGAR. As 55 transcrições e os 37 slides passam a ativo e público (liberadas pela
--    Adriana em 22/10). aprovado_treble continua falso: nada vai para o WhatsApp.

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
           d.produto_codigo,d.valido_de,d.valido_ate
      from summit_2026.knowledge_documents d
     where coalesce(p_rota,'') in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte','mia_summit_2026')
    union all
    select 'institute',d.id,d.titulo,d.tipo_conteudo,d.ativo,d.agents,d.aprovado_treble,
           d.produto_codigo,d.valido_de,d.valido_ate
      from institute.knowledge_documents d where p_rota='institute'
    union all
    select 'dash',d.id,d.titulo,d.tipo_conteudo,d.ativo,d.agents,d.aprovado_treble,
           d.produto_codigo,d.valido_de,d.valido_ate
      from dash.knowledge_documents d where p_rota='dash'
  ), conteudo_liberado as (
    select exists (
      select 1 from agentes.knowledge_access ka
       where ka.agent_key = p_rota
         and ka.knowledge_namespace = 'business'
         and ka.knowledge_key = 'summit_content'
         and ka.enabled) liberado
  ), permitidos as (
    select d.* from docs d cross join conteudo_liberado cl
    where d.ativo
      and (d.valido_de is null or d.valido_de<=now())
      and (d.valido_ate is null or d.valido_ate>now())
      and (d.produto_codigo is null or p_produto_codigo is null or d.produto_codigo=p_produto_codigo)
      and (coalesce(p_canal,'')<>'whatsapp' or d.aprovado_treble)
      and (coalesce(p_canal,'')='whatsapp' or cardinality(d.agents)=0 or 'concierge'=any(d.agents))
      and (d.origem <> 'summit_2026'
           or coalesce(d.tipo_conteudo,'') not in ('transcricao','slides')
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
    select origem,id,doc_id,sum(score) score
    from (
      select origem,id,doc_id,1.0/(60+pos) score from texto
      union all
      select origem,id,doc_id,1.0/(60+pos) score from vetor
    ) x group by origem,id,doc_id
  ), conhecimento as (
    select distinct on (d.origem,d.id)
      jsonb_build_object(
        'tipo','conhecimento',
        'id',d.origem || ':' || d.id::text
             || case when d.origem='summit_2026' and coalesce(d.tipo_conteudo,'') in ('transcricao','slides')
                     then ':' || c.ordem::text else '' end,
        'titulo',d.titulo,
        'resumo',left(c.texto,case when coalesce(d.tipo_conteudo,'') in ('transcricao','slides') then 320 else 220 end),
        'fonte',d.origem,
        'score',round(f.score::numeric,6)) candidato,
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
    'como_usar','Leia o candidato relevante com ler_intelligence. Resultado vazio não autoriza completar de memória.'
  );
$function$
;

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
               d.cluster,d.audiencia
          from summit_2026.knowledge_documents d
        union all
        select 'institute',d.id,d.titulo,d.corpo,d.tipo_conteudo,d.problema,d.resultado_desejado,
               d.autor,d.url,d.ativo,d.agents,d.aprovado_treble,d.produto_codigo,d.valido_de,d.valido_ate,
               d.cluster,d.audiencia
          from institute.knowledge_documents d
        union all
        select 'dash',d.id,d.titulo,d.corpo,d.tipo_conteudo,d.problema,d.resultado_desejado,
               d.autor,d.url,d.ativo,d.agents,d.aprovado_treble,d.produto_codigo,d.valido_de,d.valido_ate,
               d.cluster,d.audiencia
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
        select d.origem='summit_2026' and coalesce(d.tipo_conteudo,'') in ('transcricao','slides') trecho) t
      where d.ativo
        and (d.valido_de is null or d.valido_de<=now())
        and (d.valido_ate is null or d.valido_ate>now())
        and (d.produto_codigo is null or p_produto_codigo is null or d.produto_codigo=p_produto_codigo)
        and (coalesce(p_canal,'')<>'whatsapp' or d.aprovado_treble)
        and (coalesce(p_canal,'')='whatsapp' or cardinality(d.agents)=0 or 'concierge'=any(d.agents))
        and (not t.trecho or cl.liberado)
        and (
          (p_rota in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte','mia_summit_2026') and d.origem='summit_2026')
          or (p_rota='institute' and d.origem='institute')
          or (p_rota='dash' and d.origem='dash')
        )
      limit 1
    )
    else null end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_knowledge_preparar_chunks(p_schema text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_count integer;
  v_trechos integer := 0;
begin
  if p_schema not in ('summit_2026','institute','dash') then
    raise exception 'schema de knowledge não permitido';
  end if;

  execute format(
    'create unique index if not exists %I on %I.knowledge_chunks(doc_id,ordem,indice)',
    'knowledge_chunks_doc_ordem_indice_uidx', p_schema);
  execute format(
    'create index if not exists %I on %I.knowledge_chunks(stale desc,ordem,id) where embedding is null or stale or modelo_embedding is distinct from %L',
    'knowledge_chunks_embedding_pendente_idx',p_schema,'text-embedding-3-small');

  -- Caminho geral, igual ao de antes, exceto transcrição e slides do Summit.
  execute format($sql$
    insert into %I.knowledge_chunks
      (doc_id,ordem,texto,metadata,embedding,stale,embedado_em,modelo_embedding,indice)
    select d.id, g.ordem,
           substring(d.corpo from 1 + ((g.ordem-1)*3500) for 4000),
           jsonb_build_object('document_hash',d.hash,'titulo',d.titulo),
           null, true, null, null, 'principal'
    from %I.knowledge_documents d
    cross join lateral generate_series(
      1, greatest(1,ceil(length(coalesce(d.corpo,'')) / 3500.0)::int)
    ) g(ordem)
    where d.ativo and btrim(coalesce(d.corpo,''))<>''
      and (%L <> 'summit_2026' or coalesce(d.tipo_conteudo,'') not in ('transcricao','slides'))
    on conflict (doc_id,ordem,indice) do update
    set texto=excluded.texto,
        metadata=excluded.metadata,
        embedding=case
          when %I.knowledge_chunks.metadata->>'document_hash'
               is distinct from excluded.metadata->>'document_hash' then null
          else %I.knowledge_chunks.embedding end,
        stale=case
          when %I.knowledge_chunks.metadata->>'document_hash'
               is distinct from excluded.metadata->>'document_hash' then true
          else %I.knowledge_chunks.stale end,
        embedado_em=case
          when %I.knowledge_chunks.metadata->>'document_hash'
               is distinct from excluded.metadata->>'document_hash' then null
          else %I.knowledge_chunks.embedado_em end,
        modelo_embedding=case
          when %I.knowledge_chunks.metadata->>'document_hash'
               is distinct from excluded.metadata->>'document_hash' then null
          else %I.knowledge_chunks.modelo_embedding end
  $sql$,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema,p_schema);

  get diagnostics v_count=row_count;

  if p_schema = 'summit_2026' then
    with docs as (
      select d.id, d.hash, d.titulo, d.tipo_conteudo tipo, d.corpo, d.sessao_id,
             coalesce(nullif(btrim(s.titulo),''), d.titulo) sessao,
             coalesce(nullif(btrim(d.metadata->'cabecalho'->>'Palestrantes'),''),
                      nullif(btrim(d.metadata->>'speaker'),''),
                      (select string_agg(pe.nome, ', ' order by pe.nome)
                         from summit_2026.session_speakers ss
                         join ecossistema.palestrantes_especialistas pe on pe.id = ss.speaker_id
                        where ss.sessao_id = d.sessao_id)) palestrantes
        from summit_2026.knowledge_documents d
        left join summit_2026.sessions s on s.id = d.sessao_id
       where d.ativo and d.tipo_conteudo in ('transcricao','slides')
         and btrim(coalesce(d.corpo,'')) <> ''
    ), pedacos as (
      select d.id doc_id, p.ord, q.n, substr(p.txt, 1 + (q.n-1)*3000, 3000) txt
        from docs d
        cross join lateral regexp_split_to_table(d.corpo, E'\n\\s*\n') with ordinality p(txt, ord)
        cross join lateral generate_series(1, greatest(1, ceil(length(p.txt)/3000.0)::int)) q(n)
       where btrim(p.txt) <> ''
    ), acumulado as (
      select doc_id, ord, n, txt,
             coalesce(sum(length(txt)+2) over (partition by doc_id order by ord, n
                      rows between unbounded preceding and 1 preceding), 0) antes
        from pedacos
    ), grupos as (
      select doc_id, (antes / 3000)::int grp,
             string_agg(btrim(txt), E'\n\n' order by ord, n) corpo,
             (array_agg(substring(txt from '^\s*\[(\d{2}:\d{2}:\d{2})\]') order by ord, n)
                filter (where txt ~ '^\s*\[\d{2}:\d{2}:\d{2}\]'))[1] inicio,
             (array_agg(substring(txt from '^\s*\[(\d{2}:\d{2}:\d{2})\]') order by ord desc, n desc)
                filter (where txt ~ '^\s*\[\d{2}:\d{2}:\d{2}\]'))[1] fim
        from acumulado
       group by doc_id, (antes / 3000)::int
    ), trechos as (
      select g.*, dense_rank() over (partition by g.doc_id order by g.grp)::int ordem from grupos g
    ), finais as (
      select t.doc_id, t.ordem, t.inicio, t.fim, d.hash, d.titulo, d.sessao_id, d.tipo, d.palestrantes,
             case when d.tipo = 'transcricao'
               then concat_ws(' · ', 'Transcrição', d.sessao, d.palestrantes,
                      case when t.inicio is not null then
                        '[' || t.inicio || case when t.fim is distinct from t.inicio then '–' || t.fim else '' end || ']'
                      end)
               else concat_ws(' · ', 'Slides', d.sessao, d.palestrantes, 'parte ' || t.ordem)
             end || E'\n\n' || t.corpo texto
        from trechos t join docs d on d.id = t.doc_id
    ), gravados as (
      insert into summit_2026.knowledge_chunks
        (doc_id,ordem,texto,metadata,embedding,stale,embedado_em,modelo_embedding,indice)
      select f.doc_id, f.ordem, f.texto,
             jsonb_strip_nulls(jsonb_build_object(
               'document_hash', f.hash, 'titulo', f.titulo, 'tipo', f.tipo,
               'sessao_id', f.sessao_id, 'palestrantes', f.palestrantes,
               'inicio', f.inicio, 'fim', f.fim)),
             null, true, null, null, 'principal'
        from finais f
      on conflict (doc_id,ordem,indice) do update
      set texto=excluded.texto,
          metadata=excluded.metadata,
          embedding=case when summit_2026.knowledge_chunks.texto is distinct from excluded.texto
                         then null else summit_2026.knowledge_chunks.embedding end,
          stale=case when summit_2026.knowledge_chunks.texto is distinct from excluded.texto
                     then true else summit_2026.knowledge_chunks.stale end,
          embedado_em=case when summit_2026.knowledge_chunks.texto is distinct from excluded.texto
                           then null else summit_2026.knowledge_chunks.embedado_em end,
          modelo_embedding=case when summit_2026.knowledge_chunks.texto is distinct from excluded.texto
                                then null else summit_2026.knowledge_chunks.modelo_embedding end
      returning 1
    ), esvaziados as (
      -- Um documento que encolheu não deixa trecho antigo achável: o trecho que deixou de
      -- existir fica vazio (sem texto, sem embedding), sem apagar a linha.
      update summit_2026.knowledge_chunks c
         set texto = '', embedding = null, stale = true, embedado_em = null, modelo_embedding = null,
             metadata = c.metadata || jsonb_build_object('trecho_removido', true)
        from (select doc_id, max(ordem) ultimo from finais group by doc_id) u
       where c.doc_id = u.doc_id and c.indice = 'principal' and c.ordem > u.ultimo and c.texto <> ''
      returning 1
    )
    select count(*) into v_trechos from gravados;
  end if;

  return v_count + v_trechos;
end;
$function$
;

revoke all on function public.mind_intelligence_buscar_contextual(text, integer, text, text, text, vector) from public, anon, authenticated;
revoke all on function public.mind_intelligence_ler_contextual(text, text, text, text, text, integer) from public, anon, authenticated;
revoke all on function public.mind_knowledge_preparar_chunks(text) from public, anon, authenticated;
grant execute on function public.mind_intelligence_buscar_contextual(text, integer, text, text, text, vector) to service_role;
grant execute on function public.mind_intelligence_ler_contextual(text, text, text, text, text, integer) to service_role;
grant execute on function public.mind_knowledge_preparar_chunks(text) to service_role;

update summit_2026.knowledge_documents
   set ativo = true, audiencia = 'publico', atualizado_em = now()
 where tipo_conteudo in ('transcricao','slides')
   and sessao_id is not null
   and not ativo;

select public.mind_knowledge_preparar_chunks('summit_2026');
