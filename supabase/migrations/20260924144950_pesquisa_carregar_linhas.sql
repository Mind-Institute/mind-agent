create or replace function public.mind_pesquisa_carregar(p_pesquisa text, p_linhas jsonb)
returns jsonb language sql security definer set search_path to 'public'
as $$
  select public.mind_pesquisa_carregar(p_pesquisa,
    (select after_data->'cabecalho' from public.mind_admin_audit where resource = 'pesquisa_cabecalho' and record_id = p_pesquisa order by occurred_at desc limit 1),
    p_linhas)
$$;
-- Conferência: assinatura de cada resposta (valores na ordem do cabeçalho, vazio para ausente), para comparar com a planilha.
create or replace function public.mind_pesquisa_assinaturas(p_pesquisa text)
returns table(ref text, assinatura text) language sql stable security definer set search_path to 'public', 'engagement'
as $$
  with h as (select e.x, e.o from public.mind_admin_audit a, jsonb_array_elements_text(a.after_data->'cabecalho') with ordinality e(x, o)
              where a.resource = 'pesquisa_cabecalho' and a.record_id = p_pesquisa
                and a.occurred_at = (select max(occurred_at) from public.mind_admin_audit where resource = 'pesquisa_cabecalho' and record_id = p_pesquisa)),
  r as (select regexp_replace(resposta_ref, '^linha ', '') ref, respostas from engagement.pesquisa_summit_2024 where p_pesquisa = '2024'
        union all select regexp_replace(resposta_ref, '^linha ', ''), respostas from engagement.pesquisa_summit_2025 where p_pesquisa = '2025'
        union all select resposta_ref, respostas from engagement.pesquisa_interesse_2025 where p_pesquisa = 'interesse_2025')
  select r.ref, md5(string_agg(coalesce(r.respostas->>h.x, ''), chr(31) order by h.o)) from r cross join h group by r.ref
$$;
revoke all on function public.mind_pesquisa_carregar(text, jsonb) from public, anon, authenticated;
revoke all on function public.mind_pesquisa_assinaturas(text) from public, anon, authenticated;
