-- =====================================================================================
-- Guarda de "última escrita" no HubSpot, resumo da inteligência e plano com recorte por data
-- 23/09/2026 — antes de qualquer automático (BACKLOG §21.1; docs/PERFIL_ICP_JTBD.md §4.2, §4.5).
--   1. mind_hubspot_perfil_registrar: a Edge Function registra em mind_admin_audit o que escreveu
--      por contato; o plano devolve isso em ultimo_escrito, e a regra passa a ser "só sobrescreve
--      vazio ou o que o Mind escreveu por último" — edição humana no HubSpot nunca é desfeita.
--   2. Semente: o que foi escrito hoje (execucao-7561…7565) = valores do plano de então.
--   3. intelligence.perfil_resumo: resumo por regra (sem IA) para a propriedade
--      mind_resumo_inteligencia do HubSpot.
--   4. mind_hubspot_perfil_plano(p_desde): mesma RPC, com resumo, ultimo_escrito e recorte por
--      data (quem teve memória alterada desde p_desde) para o cron horário.
-- =====================================================================================

create or replace function public.mind_hubspot_perfil_registrar(p_itens jsonb, p_rotulo text default null)
returns integer language plpgsql security definer
set search_path to 'pg_catalog', 'public'
as $fn$
declare n int := 0; it jsonb;
begin
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' then return 0; end if;
  for it in select * from jsonb_array_elements(p_itens) loop
    continue when nullif(it->>'hubspot_id', '') is null;
    insert into public.mind_admin_audit (actor_user_id, action, resource, record_id, record_label, before_data, after_data, request_id)
    values (null, 'atualizar', 'hubspot_contato', it->>'hubspot_id', coalesce(p_rotulo, 'hubspot-perfil-writeback'),
            jsonb_strip_nulls(jsonb_build_object('mind_id', it->'mind_id', 'antes', it->'antes')),
            jsonb_strip_nulls(jsonb_build_object('mind_id', it->'mind_id', 'propriedades', it->'propriedades')),
            gen_random_uuid());
    n := n + 1;
  end loop;
  return n;
end $fn$;
revoke execute on function public.mind_hubspot_perfil_registrar(jsonb, text) from public, anon, authenticated;
grant execute on function public.mind_hubspot_perfil_registrar(jsonb, text) to service_role;
comment on function public.mind_hubspot_perfil_registrar(jsonb, text) is 'Registra em mind_admin_audit (resource hubspot_contato) o que hubspot-perfil-writeback escreveu em cada contato: é a memória de "última escrita" que impede o automático de desfazer edição humana no HubSpot.';

create index if not exists mind_admin_audit_hubspot_contato_idx
  on public.mind_admin_audit (record_id, occurred_at desc) where resource = 'hubspot_contato';

-- semente: a escrita inicial de hoje (a memória não mudou desde então, logo o plano de agora = o que foi escrito)
insert into public.mind_admin_audit (actor_user_id, action, resource, record_id, record_label, before_data, after_data, request_id)
select null, 'atualizar', 'hubspot_contato', p.hubspot_id,
       'semente 23/09/2026: escrita inicial do perfil (execucao-7561…7565)',
       jsonb_build_object('mind_id', p.mind_id),
       jsonb_build_object('mind_id', p.mind_id, 'propriedades', jsonb_strip_nulls(jsonb_build_object(
         'jobtitle', p.jobtitle, 'company', p.company, 'icp', p.icp,
         'icp_confianca', case when p.icp_confianca is not null then p.icp_confianca::text end,
         'jtbd', case when cardinality(p.jtbd) > 0 then array_to_string(p.jtbd, ';') end))),
       gen_random_uuid()
  from public.mind_hubspot_perfil_plano() p
 where p.hubspot_id is not null
   and not exists (select 1 from public.mind_admin_audit a where a.resource = 'hubspot_contato' and a.record_id = p.hubspot_id);

-- resumo da inteligência, por regra (sem IA): o que o Mind sabe da pessoa, em texto para o HubSpot
create or replace function intelligence.perfil_resumo(p_mind uuid)
returns text language plpgsql stable security definer
set search_path to 'pg_catalog', 'public', 'intelligence', 'pessoas', 'catalogo'
as $fn$
declare
  v_cargo text; v_empresa text; v_icp text; v_icp_fonte text; v_icp_origem text;
  v_jobs text; v_hip text; v_obj text; v_prod text; v_quando text; v_fit text; v_atualizado timestamptz;
begin
  select nullif(btrim(p.cargo), ''), nullif(btrim(p.empresa), '') into v_cargo, v_empresa
    from pessoas.pessoas p where p.id = p_mind and p.fundida_em is null;
  if not found then return null; end if;
  v_cargo := coalesce((select pm.valor->>'text' from intelligence.participante_memoria pm
                        where pm.mind_id = p_mind and pm.chave = 'cargo_atual' and pm.status = 'ativa' order by pm.atualizado_em desc limit 1), v_cargo);
  v_empresa := coalesce((select pm.valor->>'text' from intelligence.participante_memoria pm
                          where pm.mind_id = p_mind and pm.chave = 'empresa_atual' and pm.status = 'ativa' order by pm.atualizado_em desc limit 1), v_empresa);

  select i.rotulo, pm.valor->>'evidence_kind', pm.origem into v_icp, v_icp_fonte, v_icp_origem
    from intelligence.participante_memoria pm
    join intelligence.icp i on i.ativo and (i.rotulo = pm.valor->>'text' or i.rotulo_legado = pm.valor->>'text' or i.codigo = pm.valor->>'code')
   where pm.mind_id = p_mind and pm.chave = 'icp_atual' and pm.status = 'ativa'
   order by pm.atualizado_em desc limit 1;

  select string_agg(t.linha, '; ' order by t.conf desc, t.ordem) into v_jobs from (
    select j.rotulo || ' (' || round(pm.confianca * 100) || '%' ||
           coalesce(': ' || x.ev, case when pm.origem <> 'regra_perfil' then ': disse em conversa' else '' end) || ')' as linha,
           pm.confianca as conf, j.ordem
      from intelligence.participante_memoria pm
      join intelligence.jtbd j on j.codigo = pm.valor->>'code' and j.nivel = 'mind' and j.ativo
      cross join lateral (
        select string_agg(distinct case e->>'tipo'
                 when 'checkin' then 'foi à sessão' when 'reserva' then 'reservou sessão'
                 when 'interesse' then 'declarou na jornada do app' when 'conversa' then 'disse em conversa'
                 when 'contexto' then 'pelo perfil' when 'analise_produto' then 'produto citado em conversa'
                 when 'memoria_patrocinio' then 'sinal de patrocínio' when 'analise_patrocinio' then 'patrocínio em conversa'
                 when 'memoria_texto' then 'disse em conversa'
                 else e->>'tipo' end, ', ')
          from jsonb_array_elements(case when jsonb_typeof(pm.valor->'evidencias') = 'array' then pm.valor->'evidencias' else '[]'::jsonb end) e) x(ev)
     where pm.mind_id = p_mind and pm.tipo = 'jtbd' and pm.status = 'ativa'
     order by pm.confianca desc, j.ordem limit 5) t;

  select string_agg(j.rotulo, '; ' order by pm.confianca desc, j.ordem) into v_hip
    from (select pm2.* from intelligence.participante_memoria pm2
           where pm2.mind_id = p_mind and pm2.tipo = 'jtbd' and pm2.status = 'proposta'
           order by pm2.confianca desc limit 3) pm
    join intelligence.jtbd j on j.codigo = pm.valor->>'code' and j.nivel = 'mind' and j.ativo;

  select nullif(btrim(coalesce(ac.dados->>'objective', ac.dados->>'buyer_objective')), ''),
         nullif(btrim(ac.dados->>'preferred_product_or_offer'), ''),
         to_char(coalesce(ac.analisado_em, ac.criado_em) at time zone 'America/Sao_Paulo', 'DD/MM/YYYY')
    into v_obj, v_prod, v_quando
    from intelligence.analise_conversa ac where ac.mind_id = p_mind
   order by coalesce(ac.analisado_em, ac.criado_em) desc nulls last limit 1;
  -- nada de saúde pessoal no CRM (regra de sensibilidade da taxonomia)
  if v_obj is not null and v_obj ~* '(burnout|ansied|depress|p[âa]nico|medic|rem[ée]dio|diagn|terap|psiquiat|doen[çc]a|afastament|luto|suic)' then v_obj := null; end if;
  v_obj := left(v_obj, 160);

  select string_agg(distinct pr.nome, ', ') into v_fit
    from (select j.produtos from intelligence.participante_memoria pm
            join intelligence.jtbd j on j.codigo = pm.valor->>'code' and j.nivel = 'mind' and j.ativo
           where pm.mind_id = p_mind and pm.tipo = 'jtbd' and pm.status = 'ativa'
           order by pm.confianca desc, j.ordem limit 2) t
    cross join lateral unnest(t.produtos) pc
    join catalogo.produtos pr on pr.codigo = pc and pr.ativo;

  select max(pm.atualizado_em) into v_atualizado from intelligence.participante_memoria pm
   where pm.mind_id = p_mind and pm.tipo in ('icp', 'jtbd', 'cargo', 'empresa') and pm.status in ('ativa', 'proposta');

  if v_cargo is null and v_icp is null and v_jobs is null then return null; end if;

  return concat_ws(E'\n',
    'Perfil: ' || coalesce(v_cargo, 'cargo não informado') || coalesce(' · ' || v_empresa, ''),
    'ICP: ' || coalesce(v_icp || ' (' || case
        when v_icp_fonte = 'cargo_credenciamento_yazo' then 'pelo cargo informado no credenciamento'
        when v_icp_fonte = 'cargo_conversa' then 'pelo cargo dito em conversa'
        when v_icp_fonte = 'cargo_hubspot' then 'pelo cargo do HubSpot'
        when v_icp_fonte = 'cargo_pessoa' then 'pelo cargo cadastrado'
        when v_icp_origem like 'analise_%' then 'observado em conversa'
        else 'regra' end || ')', 'não classificado'),
    case when v_jobs is not null then 'Jobs observados: ' || v_jobs end,
    case when v_hip is not null then 'Hipóteses a confirmar: ' || v_hip end,
    case when v_obj is not null or v_prod is not null then
      'Última conversa' || coalesce(' (' || v_quando || ')', '') || ': ' ||
      concat_ws(' · ', v_obj, case when v_prod is not null then 'produto citado: ' || v_prod end) end,
    case when v_fit is not null then 'Produtos com fit: ' || v_fit end,
    'Atualizado pelo Mind (regra, sem IA) em ' || to_char(coalesce(v_atualizado, now()) at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') || '.');
end $fn$;
comment on function intelligence.perfil_resumo(uuid) is 'Resumo em texto do que o Mind sabe da pessoa (cargo/empresa, ICP e por quê, jobs com evidência, hipóteses, última conversa sem saúde pessoal, produtos com fit), para a propriedade mind_resumo_inteligencia do HubSpot. Regra, sem IA; muda só quando a memória muda.';

-- plano v2: recorte por data + resumo + última escrita
drop function if exists public.mind_hubspot_perfil_plano();
create or replace function public.mind_hubspot_perfil_plano(p_desde timestamptz default null)
returns table (mind_id uuid, hubspot_id text, email text, jobtitle text, company text, icp text, icp_confianca numeric, jtbd text[], resumo text, ultimo_escrito jsonb, fontes jsonb)
language sql stable security definer
set search_path to 'pg_catalog', 'public'
as $fn$
  with yazo as (
    select r.mind_id, max(nullif(btrim(r."Cargo / Profissão"), '')) as cargo, max(nullif(btrim(r."Empresa"), '')) as empresa
      from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r where r.mind_id is not null group by r.mind_id),
  emp as (
    select intelligence.texto_chave(empresa, true) as chave, mode() within group (order by intelligence.texto_exibir(empresa)) as exibir
      from yazo where empresa is not null group by 1),
  icp as (
    select distinct on (pm.mind_id) pm.mind_id, i.hubspot_valor, i.rotulo, pm.confianca
      from intelligence.participante_memoria pm
      join intelligence.icp i on i.ativo and i.hubspot_opcao and i.hubspot_valor is not null
       and (i.rotulo = pm.valor->>'text' or i.rotulo_legado = pm.valor->>'text' or i.codigo = pm.valor->>'code')
     where pm.tipo = 'icp' and pm.chave = 'icp_atual' and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
     order by pm.mind_id, pm.atualizado_em desc),
  jt as (
    select pm.mind_id, array_agg(distinct j.hubspot_valor) as valores
      from intelligence.participante_memoria pm
      join intelligence.jtbd j on j.ativo and j.hubspot_opcao and j.hubspot_valor is not null and j.codigo = pm.valor->>'code'
     where pm.tipo = 'jtbd' and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
     group by pm.mind_id),
  universo as (select mind_id from yazo union select mind_id from icp union select mind_id from jt),
  mudou as (
    select distinct pm.mind_id from intelligence.participante_memoria pm
     where p_desde is not null and pm.tipo in ('icp', 'jtbd', 'cargo', 'empresa') and pm.atualizado_em >= p_desde),
  contato as (
    select distinct on (c.mind_id) c.mind_id, c.hubspot_id, lower(btrim(c.email)) as email
      from crm.contato_espelho c where c.mind_id is not null order by c.mind_id, c.atualizado_em desc nulls last),
  ult as (
    select distinct on (a.record_id) a.record_id as hubspot_id, a.after_data->'propriedades' as props
      from public.mind_admin_audit a where a.resource = 'hubspot_contato'
     order by a.record_id, a.occurred_at desc)
  select u.mind_id, ct.hubspot_id,
         coalesce(ct.email,
                  (select i.identificador from engagement.identidades i where i.mind_id = u.mind_id and i.canal = 'email' order by i.criado_em limit 1),
                  lower(p.email)) as email,
         intelligence.texto_exibir(y.cargo) as jobtitle,
         e.exibir as company,
         icp.hubspot_valor as icp,
         case when icp.confianca is not null then round(icp.confianca * 10) end as icp_confianca,
         coalesce(jt.valores, '{}'::text[]) as jtbd,
         intelligence.perfil_resumo(u.mind_id) as resumo,
         ult.props as ultimo_escrito,
         jsonb_strip_nulls(jsonb_build_object('cargo_yazo', y.cargo, 'empresa_yazo', y.empresa, 'icp_rotulo', icp.rotulo)) as fontes
    from universo u
    join pessoas.pessoas p on p.id = u.mind_id and p.fundida_em is null
    left join yazo y on y.mind_id = u.mind_id
    left join emp e on e.chave = intelligence.texto_chave(y.empresa, true)
    left join icp on icp.mind_id = u.mind_id
    left join jt on jt.mind_id = u.mind_id
    left join contato ct on ct.mind_id = u.mind_id
    left join ult on ult.hubspot_id = ct.hubspot_id
   where p_desde is null or exists (select 1 from mudou m where m.mind_id = u.mind_id)
   order by u.mind_id;
$fn$;
revoke execute on function public.mind_hubspot_perfil_plano(timestamptz) from public, anon, authenticated;
grant execute on function public.mind_hubspot_perfil_plano(timestamptz) to service_role;
comment on function public.mind_hubspot_perfil_plano(timestamptz) is 'Plano do write-back de perfil para o HubSpot (jobtitle, company, icp + icp_confianca, jtbd, resumo) com ultimo_escrito (o que o Mind escreveu por último no contato) e recorte por data (p_desde: só quem teve memória alterada). Lido por hubspot-perfil-writeback com service_role.';
