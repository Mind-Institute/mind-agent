-- O painel de Knowledge e Agent Intelligence respondia 503 em quase todas as telas.
-- Estas nove funções nasceram SECURITY INVOKER, mas o service_role (quem as chama,
-- pela mindagent-knowledge) não tem USAGE em agentes, ecossistema e intelligence:
-- "permission denied for schema agentes". As outras 21 funções do painel são
-- SECURITY DEFINER; estas passam a ser também. search_path continua vazio e a
-- execução continua só do service_role. Aprovado pela Adriana em 22/10/2026 (D7).

alter function public.mind_admin_read_agent_intelligence_access(text) security definer;
alter function public.mind_admin_upsert_agent_intelligence_access(text, text, text, boolean, smallint, text, text, timestamptz) security definer;
alter function public.mind_admin_read_agent_knowledge_access(text) security definer;
alter function public.mind_admin_upsert_agent_knowledge_access(text, text, boolean, smallint, text, timestamptz) security definer;
alter function public.mind_admin_read_business_intelligence(uuid) security definer;
alter function public.mind_admin_read_customer_intelligence(uuid) security definer;
alter function public.mind_admin_read_knowledge_assets(uuid) security definer;
alter function public.mind_admin_read_knowledge_collections(text) security definer;
alter function public.mind_knowledge_buscar_global(text, text, vector, integer) security definer;

revoke all on function public.mind_admin_read_agent_intelligence_access(text) from public, anon, authenticated;
revoke all on function public.mind_admin_upsert_agent_intelligence_access(text, text, text, boolean, smallint, text, text, timestamptz) from public, anon, authenticated;
revoke all on function public.mind_admin_read_agent_knowledge_access(text) from public, anon, authenticated;
revoke all on function public.mind_admin_upsert_agent_knowledge_access(text, text, boolean, smallint, text, timestamptz) from public, anon, authenticated;
revoke all on function public.mind_admin_read_business_intelligence(uuid) from public, anon, authenticated;
revoke all on function public.mind_admin_read_customer_intelligence(uuid) from public, anon, authenticated;
revoke all on function public.mind_admin_read_knowledge_assets(uuid) from public, anon, authenticated;
revoke all on function public.mind_admin_read_knowledge_collections(text) from public, anon, authenticated;
revoke all on function public.mind_knowledge_buscar_global(text, text, vector, integer) from public, anon, authenticated;

grant execute on function public.mind_admin_read_agent_intelligence_access(text) to service_role;
grant execute on function public.mind_admin_upsert_agent_intelligence_access(text, text, text, boolean, smallint, text, text, timestamptz) to service_role;
grant execute on function public.mind_admin_read_agent_knowledge_access(text) to service_role;
grant execute on function public.mind_admin_upsert_agent_knowledge_access(text, text, boolean, smallint, text, timestamptz) to service_role;
grant execute on function public.mind_admin_read_business_intelligence(uuid) to service_role;
grant execute on function public.mind_admin_read_customer_intelligence(uuid) to service_role;
grant execute on function public.mind_admin_read_knowledge_assets(uuid) to service_role;
grant execute on function public.mind_admin_read_knowledge_collections(text) to service_role;
grant execute on function public.mind_knowledge_buscar_global(text, text, vector, integer) to service_role;
