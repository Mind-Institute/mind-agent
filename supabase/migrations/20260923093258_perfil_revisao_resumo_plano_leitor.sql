-- =====================================================================================
-- Revisão dos leitores do perfil (23/09/2026, depois da crítica — docs/PERFIL_ICP_JTBD.md §6):
--  - perfil_resumo: "Produtos com fit" só do job mais forte; hipóteses rotuladas como não confirmadas;
--  - mind_hubspot_perfil_plano: staff do Mind e palestrantes não recebem icp/jtbd/resumo (cargo e
--    empresa continuam); "Outros" continua sendo opção (é da Adriana);
--  - mind_customer_intelligence (o que o Agent lê): jobs_observed com fonte (rule/conversation) e
--    tipos de evidência, ordenados por confiança, no máximo 5; "Outros" não é classificação positiva.
-- =====================================================================================

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

  -- produtos: só os do job mais forte (ativo), não o catálogo inteiro
  select string_agg(distinct pr.nome, ', ') into v_fit
    from (select j.produtos from intelligence.participante_memoria pm
            join intelligence.jtbd j on j.codigo = pm.valor->>'code' and j.nivel = 'mind' and j.ativo
           where pm.mind_id = p_mind and pm.tipo = 'jtbd' and pm.status = 'ativa'
           order by pm.confianca desc, j.ordem limit 1) t
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
    case when v_hip is not null then 'Hipóteses (não confirmadas): ' || v_hip end,
    case when v_obj is not null or v_prod is not null then
      'Última conversa' || coalesce(' (' || v_quando || ')', '') || ': ' ||
      concat_ws(' · ', v_obj, case when v_prod is not null then 'produto citado: ' || v_prod end) end,
    case when v_fit is not null then 'Produtos com fit (pelo job mais forte): ' || v_fit end,
    'Atualizado pelo Mind (regra, sem IA) em ' || to_char(coalesce(v_atualizado, now()) at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI') || '.');
end $fn$;
comment on function intelligence.perfil_resumo(uuid) is 'Resumo em texto do que o Mind sabe da pessoa (cargo/empresa, ICP e por quê, jobs ativos com evidência, hipóteses não confirmadas, última conversa sem saúde pessoal, produtos com fit do job mais forte), para a propriedade mind_resumo_inteligencia do HubSpot. Regra, sem IA; muda só quando a memória muda.';

-- plano v3: staff e palestrantes ficam fora de icp/jtbd/resumo
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
  fora as (
    -- gente da casa e palestrantes não são ICP: cargo e empresa vão, perfil comercial não
    select distinct c.mind_id from credenciamento_summit_2026.controle_de_inscritos_e_presenca c
     where c.mind_id is not null and (coalesce(c.staff_mind, false) or coalesce(c.palestrante, false))),
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
         case when f.mind_id is null then icp.hubspot_valor end as icp,
         case when f.mind_id is null and icp.confianca is not null then round(icp.confianca * 10) end as icp_confianca,
         case when f.mind_id is null then coalesce(jt.valores, '{}'::text[]) else '{}'::text[] end as jtbd,
         case when f.mind_id is null then intelligence.perfil_resumo(u.mind_id) end as resumo,
         ult.props as ultimo_escrito,
         jsonb_strip_nulls(jsonb_build_object('cargo_yazo', y.cargo, 'empresa_yazo', y.empresa, 'icp_rotulo', case when f.mind_id is null then icp.rotulo end,
                                              'fora_do_icp', case when f.mind_id is not null then 'staff_ou_palestrante' end)) as fontes
    from universo u
    join pessoas.pessoas p on p.id = u.mind_id and p.fundida_em is null
    left join yazo y on y.mind_id = u.mind_id
    left join emp e on e.chave = intelligence.texto_chave(y.empresa, true)
    left join icp on icp.mind_id = u.mind_id
    left join jt on jt.mind_id = u.mind_id
    left join fora f on f.mind_id = u.mind_id
    left join contato ct on ct.mind_id = u.mind_id
    left join ult on ult.hubspot_id = ct.hubspot_id
   where p_desde is null or exists (select 1 from mudou m where m.mind_id = u.mind_id)
   order by u.mind_id;
$fn$;
revoke execute on function public.mind_hubspot_perfil_plano(timestamptz) from public, anon, authenticated;
grant execute on function public.mind_hubspot_perfil_plano(timestamptz) to service_role;
comment on function public.mind_hubspot_perfil_plano(timestamptz) is 'Plano do write-back de perfil para o HubSpot (jobtitle, company, icp + icp_confianca, jtbd, resumo) com ultimo_escrito (o que o Mind escreveu por último no contato) e recorte por data (p_desde: só quem teve memória alterada). Staff do Mind e palestrantes só levam cargo/empresa. Lido por hubspot-perfil-writeback com service_role.';

-- leitor do Agent
create or replace function public.mind_customer_intelligence(p_pessoa_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public', 'pessoas', 'engagement', 'intelligence', 'crm'
as $function$
declare
  v_role text; v_company text; v_role_mem text; v_company_mem text; v_hubspot text;
  v_icp_mem text; v_icp_conf numeric; v_icp_updated timestamptz; v_crm_icp text; v_icp_code text;
  v_jobs jsonb := '[]'::jsonb;
  v_goals jsonb := '[]'::jsonb;
  v_interests jsonb := '[]'::jsonb;
  v_preferences jsonb := '[]'::jsonb;
  v_constraints jsonb := '[]'::jsonb;
  v_stakeholders jsonb := '[]'::jsonb;
  v_delegations jsonb := '[]'::jsonb;
  v_icp jsonb := null;
begin
  if p_pessoa_id is null then return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa'); end if;

  select p.cargo, p.empresa, p.hubspot_id into v_role, v_company, v_hubspot
  from pessoas.pessoas p where p.id = p_pessoa_id;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'pessoa_nao_encontrada'); end if;

  select pm.valor->>'text' into v_role_mem from intelligence.participante_memoria pm
  where pm.mind_id = p_pessoa_id and pm.tipo = 'cargo' and pm.chave = 'cargo_atual'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
  order by pm.atualizado_em desc limit 1;

  select pm.valor->>'text' into v_company_mem from intelligence.participante_memoria pm
  where pm.mind_id = p_pessoa_id and pm.tipo = 'empresa' and pm.chave = 'empresa_atual'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
  order by pm.atualizado_em desc limit 1;

  v_role := coalesce(nullif(v_role_mem,''), nullif(v_role,''));
  v_company := coalesce(nullif(v_company_mem,''), nullif(v_company,''));

  -- rótulo canônico vem do catálogo intelligence.icp (aceita o texto atual, o legado ou o código);
  -- "Outros" não é classificação positiva: para o Agent, equivale a não classificado
  select i.rotulo, pm.confianca, pm.atualizado_em, i.codigo into v_icp_mem, v_icp_conf, v_icp_updated, v_icp_code
  from intelligence.participante_memoria pm
  join intelligence.icp i on i.ativo and i.codigo <> 'outros' and (i.rotulo = pm.valor->>'text' or i.rotulo_legado = pm.valor->>'text' or i.codigo = pm.valor->>'code')
  where pm.mind_id = p_pessoa_id and pm.tipo = 'icp' and pm.chave = 'icp_atual'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
  order by pm.atualizado_em desc limit 1;

  if v_icp_mem is null then
    select ic.rotulo, ic.codigo into v_crm_icp, v_icp_code from crm.contato_espelho e
    join intelligence.icp ic on ic.ativo and ic.codigo <> 'outros' and (ic.hubspot_valor = e.icp or ic.rotulo = e.icp)
    where e.hubspot_id = coalesce(
      (select i.identificador from engagement.identidades i
        where i.mind_id = p_pessoa_id and i.canal = 'hubspot'
        order by i.criado_em desc nulls last limit 1), v_hubspot)
    order by e.atualizado_em desc nulls last limit 1;
  end if;

  if v_icp_mem is not null then
    v_icp := jsonb_build_object('value', v_icp_mem, 'code', v_icp_code, 'confidence', v_icp_conf,
                                'source', 'memory', 'last_seen_at', v_icp_updated);
  elsif v_crm_icp is not null then
    v_icp := jsonb_build_object('value', v_crm_icp, 'code', v_icp_code, 'confidence', null, 'source', 'crm');
  end if;

  -- jobs: os 5 mais fortes, com a fonte (regra × conversa) e os tipos de evidência, para o Agent
  -- distinguir "disse em conversa" de "sentou numa sessão"
  select coalesce(jsonb_agg(t.obj order by t.conf desc, t.quando desc), '[]'::jsonb) into v_jobs from (
    select jsonb_strip_nulls(jsonb_build_object(
        'code', pm.valor->>'code', 'label', pm.valor->>'text', 'context', pm.valor->>'context',
        'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em,
        'source', case when pm.origem = 'regra_perfil' then 'rule' else 'conversation' end,
        'evidence', (select string_agg(distinct e->>'tipo', ',')
                       from jsonb_array_elements(case when jsonb_typeof(pm.valor->'evidencias') = 'array' then pm.valor->'evidencias' else '[]'::jsonb end) e))) as obj,
        pm.confianca as conf, pm.atualizado_em as quando
    from intelligence.participante_memoria pm
    where pm.mind_id = p_pessoa_id and pm.tipo = 'jtbd' and pm.status = 'ativa'
      and (pm.valido_ate is null or pm.valido_ate > now())
      and exists (select 1 from intelligence.jtbd j where j.ativo and j.codigo = pm.valor->>'code')
    order by pm.confianca desc, pm.atualizado_em desc limit 5) t;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_goals
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'objetivo'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_interests
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'interesse'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_preferences
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'preferencia'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_constraints
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'restricao'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_stakeholders
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'stakeholder'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'value', pm.valor->>'text', 'confidence', pm.confianca, 'scope', pm.valor->>'scope', 'last_seen_at', pm.atualizado_em))
      order by pm.atualizado_em desc), '[]'::jsonb) into v_delegations
  from intelligence.participante_memoria pm where pm.mind_id = p_pessoa_id and pm.tipo = 'delegacao'
    and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now());

  return jsonb_build_object(
    'ok', true, 'pessoa_id', p_pessoa_id,
    'professional_context', jsonb_strip_nulls(jsonb_build_object('role', v_role, 'company', v_company, 'icp', v_icp)),
    'jobs_observed', v_jobs, 'goals', v_goals, 'interests', v_interests,
    'preferences', v_preferences, 'constraints', v_constraints,
    'decision_context', jsonb_build_object('stakeholders', v_stakeholders, 'delegations', v_delegations,
                                           'relevant_constraints', v_constraints));
end
$function$;
comment on function public.mind_customer_intelligence(uuid) is 'O que o Agent sabe da pessoa: contexto profissional (cargo, empresa, ICP canônico do catálogo — "Outros" conta como não classificado), até 5 jobs ativos por confiança com fonte (rule/conversation) e tipos de evidência, objetivos, interesses, preferências, restrições e contexto de decisão. Só leitura.';
