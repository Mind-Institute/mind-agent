-- Business Consulting Knowledge no painel (pedido da Adriana, 24/10/2026).
--
-- O conhecimento que o agente consultor interno vai usar para aconselhar a Adriana e o time
-- está sendo ingerido pelo ChatGPT em `business_strategy` (livros de business → objetos de
-- conhecimento com citação de página e relações). Esta função só LÊ essa casa para a tela
-- "Business Consulting Knowledge": nada é escrito, e o schema continua fora da API pública
-- (não entra em pgrst.db_schemas). Mesmo padrão das `mind_admin_read_*`: só service_role
-- executa, e quem chama é a mindagent-home depois de validar a sessão de administrador.
--
--   p_objeto_id null → livros com progresso, a árvore de seções, todos os objetos (sem o payload),
--                      as relações (só as pontas e o tipo, para a tela abrir a árvore) e totais;
--   p_objeto_id      → o objeto completo, onde ele aparece no livro e as relações dele.

create or replace function public.mind_admin_read_business_consulting(p_objeto_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select case when p_objeto_id is null then
    jsonb_build_object(
      'livros', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', s.id, 'titulo', s.title, 'autores', to_jsonb(s.authors), 'tipo', s.source_type,
          'ano', s.publication_year, 'acesso', s.access_scope, 'status', s.validation_status,
          'paginas', (s.metadata->>'source_pdf_pages')::int,
          'secoes', (select count(*) from business_strategy.source_sections x where x.source_id = s.id),
          'secoes_processadas', (select count(*) from business_strategy.source_sections x
                                 where x.source_id = s.id and x.processing_status = 'processed'),
          'objetos', (select count(*) from business_strategy.knowledge_objects o where o.source_id = s.id),
          'criado_em', s.created_at, 'atualizado_em', s.updated_at
        ) order by s.created_at)
        from business_strategy.sources s), '[]'::jsonb),
      'objetos', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', o.id, 'livro_id', o.source_id, 'familia', o.family, 'tipo', o.object_type,
          'nome', o.name, 'resumo', o.summary, 'escopo', o.scope, 'topicos', to_jsonb(o.topics),
          'confianca', o.extraction_confidence, 'status', o.validation_status,
          'capitulo', sec.title, 'secao_id', o.canonical_section_id
        ) order by o.family, o.name)
        from business_strategy.knowledge_objects o
        left join business_strategy.source_sections sec on sec.id = o.canonical_section_id), '[]'::jsonb),
      'secoes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', x.id, 'livro_id', x.source_id, 'pai_id', x.parent_section_id, 'tipo', x.section_type,
          'numero', x.section_number, 'titulo', x.title, 'ordem', x.section_order,
          'pagina_inicio', x.page_start, 'pagina_fim', x.page_end
        ) order by x.section_order nulls last, x.page_start nulls last)
        from business_strategy.source_sections x), '[]'::jsonb),
      'relacoes', coalesce((
        select jsonb_agg(jsonb_build_object('de', r.from_object_id, 'para', r.to_object_id, 'tipo', r.relationship_type))
        from business_strategy.object_relationships r), '[]'::jsonb),
      'totais', jsonb_build_object(
        'livros', (select count(*) from business_strategy.sources),
        'objetos', (select count(*) from business_strategy.knowledge_objects),
        'citacoes', (select count(*) from business_strategy.object_groundings),
        'relacoes', (select count(*) from business_strategy.object_relationships))
    )
  else (
    select jsonb_build_object(
      'objeto', jsonb_build_object(
        'id', o.id, 'livro_id', o.source_id, 'livro', s.title, 'familia', o.family, 'tipo', o.object_type,
        'nome', o.name, 'aliases', to_jsonb(o.aliases), 'resumo', o.summary, 'escopo', o.scope,
        'condicoes', o.conditions, 'limitacoes', o.limitations, 'status_epistemico', o.epistemic_status,
        'portabilidade', o.portability, 'dominios', to_jsonb(o.domain_scope),
        'niveis', to_jsonb(o.level_of_application), 'topicos', to_jsonb(o.topics),
        'detalhes', o.structured_payload, 'confianca', o.extraction_confidence,
        'status', o.validation_status, 'capitulo', sec.title),
      'citacoes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'papel', g.grounding_role, 'localizador', g.locator, 'pagina_inicio', g.page_start,
          'pagina_fim', g.page_end, 'resumo', g.grounding_summary, 'capitulo', gs.title
        ) order by g.page_start nulls last)
        from business_strategy.object_groundings g
        left join business_strategy.source_sections gs on gs.id = g.section_id
        where g.object_id = o.id), '[]'::jsonb),
      'relacoes', coalesce((
        select jsonb_agg(r.item order by r.direcao, r.tipo)
        from (
          select 'saida' as direcao, rel.relationship_type as tipo, jsonb_build_object(
              'direcao', 'saida', 'tipo', rel.relationship_type, 'outro_id', alvo.id,
              'outro_nome', alvo.name, 'resumo', rel.relationship_summary, 'confianca', rel.confidence) as item
            from business_strategy.object_relationships rel
            join business_strategy.knowledge_objects alvo on alvo.id = rel.to_object_id
            where rel.from_object_id = o.id
          union all
          select 'entrada', rel.relationship_type, jsonb_build_object(
              'direcao', 'entrada', 'tipo', rel.relationship_type, 'outro_id', origem.id,
              'outro_nome', origem.name, 'resumo', rel.relationship_summary, 'confianca', rel.confidence)
            from business_strategy.object_relationships rel
            join business_strategy.knowledge_objects origem on origem.id = rel.from_object_id
            where rel.to_object_id = o.id
        ) r), '[]'::jsonb)
    )
    from business_strategy.knowledge_objects o
    join business_strategy.sources s on s.id = o.source_id
    left join business_strategy.source_sections sec on sec.id = o.canonical_section_id
    where o.id = p_objeto_id
  ) end;
$$;

revoke all on function public.mind_admin_read_business_consulting(uuid) from public, anon, authenticated;
grant execute on function public.mind_admin_read_business_consulting(uuid) to service_role;

comment on function public.mind_admin_read_business_consulting(uuid) is
  'Leitura do painel (Business Consulting Knowledge) sobre business_strategy. Só service_role; quem chama é a mindagent-home.';
