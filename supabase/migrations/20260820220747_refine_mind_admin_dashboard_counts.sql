create or replace function public.mind_admin_dashboard_counts()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select jsonb_build_object(
    'sessions', (select count(*) from mind.sessions),
    'speakers', (select count(*) from mind.speakers),
    'spaces', (select count(*) from mind.locations where ativo),
    'booths', (select count(*) from mind.exhibitors where ativo),
    'active_offers', (select count(*) from mind.offers where ativo),
    'documents', (select count(*) from mind.knowledge_documents where ativo),
    'documents_pending', (
      select count(*)
      from mind.knowledge_documents d
      where d.ativo
        and (
          not exists (select 1 from mind.knowledge_chunks c where c.doc_id = d.id)
          or exists (
            select 1 from mind.knowledge_chunks c
            where c.doc_id = d.id and (c.stale or c.embedding is null)
          )
        )
    ),
    'unanswered', (
      select count(*)
      from concierge.perguntas_feitas
      where not respondida and not recusada
    ),
    'conversations_24h', (
      select count(*)
      from concierge.conversas
      where ultima_atividade >= now() - interval '24 hours'
    ),
    'sessions_without_space', (
      select count(*) from mind.sessions where espaco_id is null
    ),
    'sessions_without_speaker', (
      select count(*)
      from mind.sessions s
      where not exists (
        select 1 from mind.session_speakers ss where ss.sessao_id = s.id
      )
    ),
    'spaces_without_directions', (
      select count(*)
      from mind.locations
      where ativo and nullif(btrim(como_chegar), '') is null
    ),
    'stages_without_alias', (
      select count(*)
      from mind.locations
      where ativo
        and lower(tipo) in ('palco','arena')
        and coalesce(cardinality(aliases), 0) = 0
    ),
    'offers_without_checkout', (
      select count(*)
      from mind.offers
      where ativo and nullif(btrim(checkout_url), '') is null
    ),
    'generated_at', now()
  );
$function$;

revoke all on function public.mind_admin_dashboard_counts() from public, anon, authenticated;
grant execute on function public.mind_admin_dashboard_counts() to service_role;
