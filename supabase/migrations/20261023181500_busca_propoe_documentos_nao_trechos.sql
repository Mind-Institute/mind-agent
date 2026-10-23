-- A BUSCA PROPÕE DOCUMENTOS, NÃO TRECHOS (Adriana, 23/10/2026 — mesma aprovação da migration
-- 20261023174500, que não bastou sozinha).
--
-- Medido depois dela, rota da MIA, "liderança": os 24 melhores TRECHOS eram 20 de transcrições,
-- 1 ficha e nenhum mapa — então o bônus de categoria não tinha em quem agir. Olhando por
-- DOCUMENTO (o melhor trecho de cada um), o mapa temático de liderança está na posição 18 e
-- entram 2 mapas e 3 fichas nos 24 primeiros. Como a etapa `conhecimento` já reduz a um candidato
-- por documento, escolher por documento desde o início só alarga o funil: nenhuma resposta perde
-- trecho, e os panoramas passam a disputar. O braço por significado (embedding) ganha a mesma
-- regra, pelo mesmo motivo. O restante do corpo é idêntico ao da migration anterior.

create or replace function public.mind_intelligence_buscar_contextual(
  p_necessidade text,
  p_limite integer default 6,
  p_rota text default null,
  p_canal text default null,
  p_produto_codigo text default null,
  p_embedding vector default null
) returns jsonb
language sql stable security definer
set search_path to ''
as $function$
  with cfg as (
    select least(10,greatest(1,coalesce(p_limite,6))) n,
           plainto_tsquery('portuguese',coalesce(btrim(p_necessidade),'')) q,
           (select nullif(string_agg(quote_literal(l.lexeme),' | '),'')::tsquery
              from unnest(to_tsvector('portuguese',coalesce(btrim(p_necessidade),''))) l
             where l.lexeme not in ('event','mind','summit','2026')) q_qualquer
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
  ), texto_todos as (
    -- Um candidato por DOCUMENTO (o melhor trecho dele), e só então os n*4 melhores.
    select m.origem,m.id,m.doc_id,
           row_number() over(order by m.r desc) pos
    from (
      select distinct on (c.origem,c.doc_id) c.origem,c.id,c.doc_id,ts_rank_cd(c.tsv,cfg.q) r
      from chunks c join permitidos d on d.origem=c.origem and d.id=c.doc_id cross join cfg
      where c.tsv@@cfg.q
      order by c.origem,c.doc_id,ts_rank_cd(c.tsv,cfg.q) desc
    ) m
    order by pos limit (select n*4 from cfg)
  ), texto_qualquer as (
    -- Segunda chance: só quando nenhum trecho tem todos os termos juntos.
    select m.origem,m.id,m.doc_id,
           row_number() over(order by m.r desc) pos
    from (
      select distinct on (c.origem,c.doc_id) c.origem,c.id,c.doc_id,ts_rank_cd(c.tsv,cfg.q_qualquer) r
      from chunks c join permitidos d on d.origem=c.origem and d.id=c.doc_id cross join cfg
      where cfg.q_qualquer is not null and c.tsv@@cfg.q_qualquer
        and not exists (select 1 from texto_todos)
      order by c.origem,c.doc_id,ts_rank_cd(c.tsv,cfg.q_qualquer) desc
    ) m
    order by pos limit (select n*4 from cfg)
  ), texto as (
    select origem,id,doc_id,pos from texto_todos
    union all
    select origem,id,doc_id,pos from texto_qualquer
  ), vetor as (
    -- Idem por significado: o trecho mais próximo de cada documento, depois os n*4 melhores.
    select m.origem,m.id,m.doc_id,
           row_number() over(order by m.dist) pos
    from (
      select distinct on (c.origem,c.doc_id) c.origem,c.id,c.doc_id,
             (c.embedding OPERATOR(public.<=>) p_embedding) dist
      from chunks c join permitidos d on d.origem=c.origem and d.id=c.doc_id cross join cfg
      where p_embedding is not null and c.embedding is not null and not c.stale
        and c.modelo_embedding='text-embedding-3-small'
      order by c.origem,c.doc_id,(c.embedding OPERATOR(public.<=>) p_embedding)
    ) m
    order by pos limit (select n*4 from cfg)
  ), fundido as (
    select x.origem,x.id,x.doc_id,
           sum(x.score)
             * case d.peso when 'principal' then 1.25 when 'complementar' then 0.85 else 1.0 end
             * case when x.origem='summit_2026' and d.tipo_conteudo='mapa_tematico' then 1.3
                    when x.origem='summit_2026' and d.tipo_conteudo='ficha_sessao' then 1.2
                    else 1.0 end score
    from (
      select origem,id,doc_id,1.0/(60+pos) score from texto
      union all
      select origem,id,doc_id,1.0/(60+pos) score from vetor
    ) x join permitidos d on d.origem=x.origem and d.id=x.doc_id
    group by x.origem,x.id,x.doc_id,d.peso,d.tipo_conteudo
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
