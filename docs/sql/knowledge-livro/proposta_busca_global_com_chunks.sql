-- Global Knowledge passa a indexar e buscar trechos de texto integral (ecossistema.chunks_conhecimento)
-- além dos insights derivados. Nenhuma tabela, coluna ou função nova: só as três portas que já existiam.
--
--   mind_knowledge_embedding_pending  a fila inclui chunks de fontes full_text; o texto enviado ao embedding
--                                     leva um cabeçalho estrutural (obra — autores (ano) / capítulo › seção › subseção)
--   mind_knowledge_embedding_save     grava o vetor no insight ou no chunk com esse id
--   mind_knowledge_buscar_global      candidatos = insights + chunks autorizados; mesmo ranking híbrido (RRF)
--
-- Autorização continua pré-retrieval: chunk herda as collections da fonte (source_collections) e o acesso
-- do próprio chunk (mind_only / mind_public) é comparado ao acesso máximo do agente.
-- Chunk de fonte que não é full_text nunca entra na fila nem na busca.

create or replace function public.mind_knowledge_embedding_pending(p_limit integer default 100)
returns setof jsonb
language sql
security definer
set search_path to ''
as $function$
  select q.item
  from (
    select jsonb_build_object(
             'id', i.id,
             'texto', i.texto,
             'sourceId', i.source_id,
             'sectionId', i.section_id,
             'insightType', i.insight_type,
             'kind', 'insight'
           ) as item,
           0 as grupo,
           case i.status_validacao when 'human_approved' then 0 when 'machine_reviewed' then 1 else 2 end as prio,
           i.criado_em as criado,
           0 as ordem,
           i.id as id
    from ecossistema.insights_conhecimento i
    join ecossistema.fontes_conhecimento f on f.id = i.source_id
    where f.ativo = true
      and i.status_validacao <> 'rejected'
      and (i.embedding is null or i.stale = true)
    union all
    select jsonb_build_object(
             'id', c.id,
             'texto', f.titulo || ' — ' || array_to_string(f.autores, ', ') || coalesce(' (' || f.ano || ')', '')
                      || E'\n' || concat_ws(' › ', c.capitulo, c.secao, c.subsecao)
                      || E'\n\n' || c.texto,
             'sourceId', c.source_id,
             'sectionId', c.metadata->>'section_id',
             'insightType', null,
             'kind', 'chunk'
           ),
           1,
           0,
           c.criado_em,
           c.ordem,
           c.id
    from ecossistema.chunks_conhecimento c
    join ecossistema.fontes_conhecimento f on f.id = c.source_id
    where f.ativo = true
      and f.modo_ingestao = 'full_text'
      and (c.embedding is null or c.stale = true)
  ) q
  order by q.grupo, q.prio, q.criado, q.ordem, q.id
  limit greatest(1, least(500, p_limit));
$function$;

create or replace function public.mind_knowledge_embedding_save(p_id uuid, p_embedding vector, p_model text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  update ecossistema.insights_conhecimento
  set embedding = p_embedding,
      stale = false,
      embedado_em = now(),
      modelo_embedding = p_model,
      atualizado_em = now()
  where id = p_id;
  if found then
    return;
  end if;

  update ecossistema.chunks_conhecimento
  set embedding = p_embedding,
      stale = false,
      embedado_em = now(),
      modelo_embedding = p_model
  where id = p_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'knowledge_item_not_found';
  end if;
end;
$function$;

create or replace function public.mind_knowledge_buscar_global(
  p_agent_key text,
  p_query text,
  p_query_embedding vector default null::vector,
  p_limit integer default 12
)
returns setof jsonb
language sql
set search_path to ''
as $function$
with authorized as (
  select
    i.id,
    'insight'::text as kind,
    i.source_id,
    i.section_id,
    i.insight_type,
    i.texto,
    i.base_na_fonte,
    i.evidence_status,
    i.causal_status,
    i.populacao,
    i.contexto,
    i.localizador_fonte,
    i.temas,
    i.acesso,
    i.status_validacao,
    i.extraction_confidence,
    i.embedding,
    i.tsv,
    f.titulo as source_title,
    f.autores as source_authors,
    f.ano as source_year,
    f.tipo_fonte as source_type,
    f.evidence_role,
    f.study_design,
    f.evidence_appraisal_status,
    f.methodological_quality,
    f.doi,
    s.titulo as section_title,
    null::jsonb as location,
    max(aka.priority)::int as collection_priority,
    array_agg(distinct ic.collection_key order by ic.collection_key) as collection_keys
  from ecossistema.insights_conhecimento i
  join ecossistema.fontes_conhecimento f
    on f.id = i.source_id and f.ativo = true
  left join ecossistema.secoes_conhecimento s on s.id = i.section_id
  join ecossistema.insight_collections ic on ic.insight_id = i.id
  join agentes.knowledge_access aka
    on aka.knowledge_namespace = 'global'
   and aka.knowledge_key = ic.collection_key
   and aka.agent_key = p_agent_key
   and aka.enabled = true
  where i.status_validacao <> 'rejected'
    and (
      aka.access_max = 'mind_only'
      or (aka.access_max = 'mind_public' and i.acesso = 'mind_public')
    )
  group by i.id, f.id, s.id

  union all

  select
    c.id,
    'chunk'::text,
    c.source_id,
    (c.metadata->>'section_id')::uuid,
    'source_text'::text,
    c.texto,
    'author_text'::text,
    'unassessed'::text,
    'not_applicable'::text,
    null::text,
    null::text,
    concat_ws(', ',
      array_to_string(f.autores, ', ') || coalesce(' (' || f.ano || ')', ''),
      concat_ws(' › ', c.capitulo, c.secao, c.subsecao),
      case
        when c.pagina_inicio is null then 'pp. ' || (c.metadata->'book_pages'->>0) || '–' || (c.metadata->'book_pages'->>1)
        when c.pagina_fim is null or c.pagina_fim = c.pagina_inicio then 'p. ' || c.pagina_inicio
        else 'pp. ' || c.pagina_inicio || '–' || c.pagina_fim
      end),
    c.temas,
    c.acesso,
    null::text,
    null::numeric,
    c.embedding,
    c.tsv,
    f.titulo,
    f.autores,
    f.ano,
    f.tipo_fonte,
    f.evidence_role,
    f.study_design,
    f.evidence_appraisal_status,
    f.methodological_quality,
    f.doi,
    coalesce(c.subsecao, c.secao, c.capitulo),
    jsonb_build_object(
      'ordem', c.ordem,
      'tipoTrecho', c.tipo_trecho,
      'capitulo', c.capitulo,
      'secao', c.secao,
      'subsecao', c.subsecao,
      'paginaInicio', c.pagina_inicio,
      'paginaFim', c.pagina_fim,
      'bookPages', c.metadata->'book_pages',
      'pdfPages', c.metadata->'pdf_pages',
      'chapterSectionId', c.metadata->>'chapter_section_id',
      'textVersion', c.metadata->'text_version',
      'charRange', jsonb_build_array(c.metadata->'char_start', c.metadata->'char_end'),
      'file', c.metadata->'location'
    ),
    max(aka.priority)::int,
    array_agg(distinct sc.collection_key order by sc.collection_key)
  from ecossistema.chunks_conhecimento c
  join ecossistema.fontes_conhecimento f
    on f.id = c.source_id and f.ativo = true and f.modo_ingestao = 'full_text'
  join ecossistema.source_collections sc on sc.source_id = c.source_id
  join agentes.knowledge_access aka
    on aka.knowledge_namespace = 'global'
   and aka.knowledge_key = sc.collection_key
   and aka.agent_key = p_agent_key
   and aka.enabled = true
  where (
      aka.access_max = 'mind_only'
      or (aka.access_max = 'mind_public' and c.acesso = 'mind_public')
    )
  group by c.id, f.id
),
lexical as (
  select
    a.id,
    row_number() over (
      order by ts_rank_cd(a.tsv, websearch_to_tsquery('simple'::regconfig, nullif(trim(p_query), ''))) desc
    )::int as lexical_rank,
    ts_rank_cd(a.tsv, websearch_to_tsquery('simple'::regconfig, nullif(trim(p_query), ''))) as lexical_score
  from authorized a
  where nullif(trim(p_query), '') is not null
    and a.tsv @@ websearch_to_tsquery('simple'::regconfig, nullif(trim(p_query), ''))
  order by lexical_score desc
  limit greatest(40, least(200, p_limit * 8))
),
semantic as (
  select
    a.id,
    row_number() over (order by a.embedding OPERATOR(public.<=>) p_query_embedding)::int as semantic_rank,
    1 - (a.embedding OPERATOR(public.<=>) p_query_embedding) as semantic_score
  from authorized a
  where p_query_embedding is not null and a.embedding is not null
  order by a.embedding OPERATOR(public.<=>) p_query_embedding
  limit greatest(40, least(200, p_limit * 8))
),
candidates as (
  select id from lexical
  union
  select id from semantic
),
scored as (
  select
    a.*,
    l.lexical_rank,
    l.lexical_score,
    sm.semantic_rank,
    sm.semantic_score,
    (
      coalesce(1.0 / (60 + l.lexical_rank), 0)
      + coalesce(1.0 / (60 + sm.semantic_rank), 0)
      + (coalesce(a.collection_priority, 0)::numeric / 100.0) * 0.002
      + case a.status_validacao
          when 'human_approved' then 0.001
          when 'machine_reviewed' then 0.0005
          else 0
        end
    )::double precision as hybrid_score
  from candidates c
  join authorized a on a.id = c.id
  left join lexical l on l.id = c.id
  left join semantic sm on sm.id = c.id
)
select jsonb_build_object(
  'id', x.id,
  'kind', x.kind,
  'texto', x.texto,
  'insightType', x.insight_type,
  'baseNaFonte', x.base_na_fonte,
  'evidenceStatus', x.evidence_status,
  'causalStatus', x.causal_status,
  'populacao', x.populacao,
  'contexto', x.contexto,
  'localizadorFonte', x.localizador_fonte,
  'temas', x.temas,
  'acesso', x.acesso,
  'statusValidacao', x.status_validacao,
  'extractionConfidence', x.extraction_confidence,
  'source', jsonb_build_object(
    'id', x.source_id,
    'title', x.source_title,
    'authors', x.source_authors,
    'year', x.source_year,
    'type', x.source_type,
    'evidenceRole', x.evidence_role,
    'studyDesign', x.study_design,
    'appraisalStatus', x.evidence_appraisal_status,
    'methodologicalQuality', x.methodological_quality,
    'doi', x.doi
  ),
  'section', jsonb_build_object('id', x.section_id, 'title', x.section_title),
  'location', x.location,
  'collections', x.collection_keys,
  'collectionPriority', x.collection_priority,
  'retrieval', jsonb_build_object(
    'lexicalRank', x.lexical_rank,
    'lexicalScore', x.lexical_score,
    'semanticRank', x.semantic_rank,
    'semanticScore', x.semantic_score,
    'hybridScore', x.hybrid_score
  )
)
from scored x
order by x.hybrid_score desc, x.extraction_confidence desc nulls last, x.id
limit greatest(1, least(50, p_limit));
$function$;

-- Portas internas: só service_role (contrato: tests/permissoes_funcoes_contract.sql).
revoke all on function public.mind_knowledge_embedding_pending(integer) from public, anon, authenticated;
revoke all on function public.mind_knowledge_embedding_save(uuid, vector, text) from public, anon, authenticated;
revoke all on function public.mind_knowledge_buscar_global(text, text, vector, integer) from public, anon, authenticated;
grant execute on function public.mind_knowledge_embedding_pending(integer) to service_role;
grant execute on function public.mind_knowledge_embedding_save(uuid, vector, text) to service_role;
grant execute on function public.mind_knowledge_buscar_global(text, text, vector, integer) to service_role;
