-- Conserto da máscara das conversas reais (mesmo dia): a análise é JSON e a
-- máscara em texto podia mexer em número fora de aspas e quebrar o JSON; agora
-- ela anda pelo JSON e só toca em valores de texto. O padrão de telefone passa a
-- exigir 10 dígitos ou mais (um telefone brasileiro), para não apagar datas.

set lock_timeout = '10s';

create or replace function public.mind_admin_mascarar_contato(p_texto text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(
           regexp_replace(coalesce(p_texto, ''),
             '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}', '[e-mail]', 'g'),
           '\+?(?:\d[ .()-]*){9,}\d', '[telefone]', 'g');
$$;

create or replace function public.mind_admin_mascarar_jsonb(p jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case jsonb_typeof(p)
    when 'string' then to_jsonb(public.mind_admin_mascarar_contato(p #>> '{}'))
    when 'object' then coalesce((select jsonb_object_agg(e.k, public.mind_admin_mascarar_jsonb(e.v)) from jsonb_each(p) e(k, v)), '{}'::jsonb)
    when 'array'  then coalesce((select jsonb_agg(public.mind_admin_mascarar_jsonb(e.v) order by e.o) from jsonb_array_elements(p) with ordinality e(v, o)), '[]'::jsonb)
    else p end;
$$;
revoke all on function public.mind_admin_mascarar_jsonb(jsonb) from public, anon, authenticated;
grant execute on function public.mind_admin_mascarar_jsonb(jsonb) to service_role;

create or replace function public.mind_admin_read_agent_conversations(p_id text default null)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with conv as (
    select c.id, c.canal, c.agente, c.iniciada_em, c.ultima_atividade, c.mind_id, c.nome_contato,
           coalesce((c.variables->>'teste')::boolean, false) as teste
      from engagement.conversas c
     where (p_id is null
            and c.ultima_atividade > now() - interval '90 days'
            and c.agente in ('mindagent-chat', 'mindagent-playground', 'treble-inbound-agent'))
        or c.id::text = p_id
  ),
  msgs as (
    select m.conversa_id, m.papel, m.conteudo, m.criado_em, m.blocos,
           coalesce(m.blocos->>'rota_aplicada', m.blocos->>'rota') as rota
      from engagement.mensagens m
      join conv on conv.id = m.conversa_id
     where m.papel in ('lead', 'agente')
  ),
  agg as (
    select conversa_id,
           count(*) as n,
           count(*) filter (where papel = 'agente') as n_agente,
           coalesce(array_agg(distinct rota) filter (where papel = 'agente' and rota is not null), '{}') as rotas,
           (array_agg(rota order by criado_em desc) filter (where papel = 'agente' and rota is not null))[1] as rota
      from msgs
     group by conversa_id
  ),
  skills as (
    select m.conversa_id, array_agg(distinct f->>'nome') as skills
      from msgs m,
           jsonb_array_elements(case when jsonb_typeof(m.blocos->'ferramentas') = 'array'
                                     then m.blocos->'ferramentas' else '[]'::jsonb end) f
     where m.papel = 'agente' and f->>'nome' is not null
     group by m.conversa_id
  ),
  analises as (
    select a.conversa_id,
           array_agg(distinct a.analisador) as analisadores,
           jsonb_agg(jsonb_build_object(
             'analisador', a.analisador, 'analisadoEm', a.analisado_em, 'modelo', a.modelo,
             'dados', public.mind_admin_mascarar_jsonb(a.dados))
             order by a.analisado_em desc) as lista
      from intelligence.analise_conversa a
      join conv on conv.id = a.conversa_id
     group by a.conversa_id
  )
  select jsonb_build_object(
    'id', conv.id,
    'canal', conv.canal,
    'agente', conv.agente,
    'teste', conv.teste,
    'rota', agg.rota,
    'rotas', to_jsonb(agg.rotas),
    'primeiroNome', nullif(split_part(coalesce(p.primeiro_nome, conv.nome_contato, ''), ' ', 1), ''),
    'iniciadaEm', conv.iniciada_em,
    'ultimaAtividade', conv.ultima_atividade,
    'mensagens', agg.n,
    'skills', to_jsonb(coalesce(sk.skills, '{}')),
    'analisadores', to_jsonb(coalesce(an.analisadores, '{}')),
    'falas', case when p_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
               'papel', m.papel,
               'texto', public.mind_admin_mascarar_contato(m.conteudo),
               'criadoEm', m.criado_em,
               'rota', m.rota,
               'modelo', m.blocos->>'model',
               'duracaoMs', case when m.blocos->>'duration_ms' ~ '^\d+(\.\d+)?$'
                                 then (m.blocos->>'duration_ms')::numeric end,
               'ferramentas', case when jsonb_typeof(m.blocos->'ferramentas') = 'array'
                                   then m.blocos->'ferramentas' else '[]'::jsonb end)
             order by m.criado_em)
        from msgs m where m.conversa_id = conv.id), '[]'::jsonb) end,
    'analises', case when p_id is null then '[]'::jsonb else coalesce(an.lista, '[]'::jsonb) end)
  from conv
  join agg on agg.conversa_id = conv.id and agg.n_agente > 0
  left join pessoas.pessoas p on p.id = conv.mind_id
  left join skills sk on sk.conversa_id = conv.id
  left join analises an on an.conversa_id = conv.id
  order by conv.ultima_atividade desc
  limit case when p_id is null then 300 else 1 end;
$$;
