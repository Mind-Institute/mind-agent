-- Profissão/ICP de cada pessoa em pessoas.pessoas, com a prioridade da Adriana (24/09/2026):
--   1. o cargo que a pessoa escreveu no credenciamento (relatório consolidado da Yazo), pela regra
--      REGRA_ICP_POR_CARGO.md — sobrescreve qualquer dado antigo, inclusive ICP marcado à mão no HubSpot;
--   2. sem isso, o que o HubSpot tem (a propriedade ICP; senão o cargo do HubSpot pela regra);
--   3. sem HubSpot, o resto do sistema (ICP ou cargo dito em conversa; por último o cargo do cadastro).
-- "Outros" de uma fonte só vale quando nenhuma fonte seguinte tem algo melhor.
-- Quem não é lead (staff, palestrante, professor, parceiro de venda) não tem ICP.
-- O HubSpot passa a ler o ICP daqui (mind_hubspot_perfil_plano) e, quando a fonte é o credenciamento,
-- a escrita sobrescreve cargo e ICP editados lá (forcar = true).

-- 1. casa: três colunas em pessoas.pessoas ----------------------------------------------------------
alter table pessoas.pessoas
  add column if not exists icp text references intelligence.icp(codigo),
  add column if not exists icp_fonte text,
  add column if not exists icp_confianca numeric;

comment on column pessoas.pessoas.icp is
  'ICP da pessoa (código de intelligence.icp). Prioridade: credenciamento > ICP do HubSpot > cargo do HubSpot > conversa > cadastro (Adriana, 24/09/2026; REGRA_ICP_POR_CARGO.md). Nulo para quem não é lead. Mantido por intelligence.perfil_gravar_pessoas.';
comment on column pessoas.pessoas.icp_fonte is
  'De onde veio o ICP: credenciamento, hubspot_icp, hubspot_cargo, conversa, conversa_cargo ou cadastro.';
comment on column pessoas.pessoas.icp_confianca is
  'Confiança da regra (0,70; 0,55 quando o cargo é só um nível). Nulo quando o ICP veio pronto do HubSpot ou da conversa.';

-- 2. quem grava: cargo e ICP por prioridade -----------------------------------------------------------
create or replace function intelligence.perfil_gravar_pessoas(p_gravar boolean default true)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'intelligence', 'pessoas', 'crm', 'credenciamento_summit_2026'
as $function$
declare v_cargo int := 0; v_empresa int := 0; v_icp int := 0;
begin
  create temp table perfil_pessoa_tmp on commit drop as
    with yazo as (
      select r.mind_id, max(nullif(btrim(r."Cargo / Profissão"), '')) as cargo, max(nullif(btrim(r."Empresa"), '')) as empresa
        from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r where r.mind_id is not null group by r.mind_id),
    emp as (
      select intelligence.texto_chave(empresa, true) as chave, mode() within group (order by intelligence.texto_exibir(empresa)) as exibir
        from yazo where empresa is not null group by 1),
    hs as (
      select distinct on (c.mind_id) c.mind_id, nullif(btrim(c.jobtitle), '') as jobtitle,
             nullif(btrim(c.company), '') as company, nullif(btrim(c.icp), '') as icp
        from crm.contato_espelho c where c.mind_id is not null
       order by c.mind_id, (nullif(btrim(c.icp), '') is not null) desc, (nullif(btrim(c.jobtitle), '') is not null) desc,
                c.atualizado_em desc nulls last),
    conv_icp as (
      select distinct on (pm.mind_id) pm.mind_id,
             coalesce(nullif(pm.valor->>'code', ''),
                      (select i.codigo from intelligence.icp i
                        where i.rotulo = pm.valor->>'text' or i.rotulo_legado = pm.valor->>'text' limit 1)) as codigo
        from intelligence.participante_memoria pm
       where pm.chave = 'icp_atual' and pm.status = 'ativa' and pm.origem <> 'regra_perfil'
       order by pm.mind_id, pm.atualizado_em desc),
    conv_cargo as (
      select distinct on (pm.mind_id) pm.mind_id, nullif(btrim(pm.valor->>'text'), '') as cargo
        from intelligence.participante_memoria pm
       where pm.chave = 'cargo_atual' and pm.status = 'ativa' and pm.origem <> 'regra_perfil'
       order by pm.mind_id, pm.atualizado_em desc)
    select p.id as mind_id,
           coalesce(intelligence.texto_exibir(y.cargo), hs.jobtitle, cc.cargo, p.cargo) as cargo,
           e.exibir as empresa_yazo,
           x.codigo as icp, x.fonte as icp_fonte, x.confianca as icp_confianca
      from pessoas.pessoas p
      left join yazo y on y.mind_id = p.id
      left join emp e on e.chave = intelligence.texto_chave(y.empresa, true)
      left join hs on hs.mind_id = p.id
      left join conv_icp ci on ci.mind_id = p.id
      left join conv_cargo cc on cc.mind_id = p.id
      left join lateral (
        select v.codigo, v.fonte,
               case when v.fonte in ('credenciamento', 'hubspot_cargo', 'conversa_cargo', 'cadastro') then
                 case when intelligence.texto_chave(v.cargo) ~ '^(gerente|diretor|diretora|coordenador|coordenadora|analista|gestor|gestora|head|lider|socio|socia|consultor|consultora|executivo|executiva|especialista|supervisor|supervisora|empresario|empresaria)$'
                      then 0.55 else 0.70 end
               end as confianca
          from (values
            (1, case when y.cargo is not null then intelligence.icp_por_cargo(y.cargo, y.empresa) end, 'credenciamento', y.cargo),
            (2, (select i.codigo from intelligence.icp i
                  where i.ativo and (lower(i.hubspot_valor) = lower(hs.icp) or lower(i.rotulo) = lower(hs.icp)) limit 1), 'hubspot_icp', null),
            (3, case when hs.jobtitle is not null then intelligence.icp_por_cargo(hs.jobtitle, hs.company) end, 'hubspot_cargo', hs.jobtitle),
            (4, ci.codigo, 'conversa', null),
            (5, case when cc.cargo is not null then intelligence.icp_por_cargo(cc.cargo, null) end, 'conversa_cargo', cc.cargo),
            (6, case when p.cargo is not null then intelligence.icp_por_cargo(p.cargo, p.empresa) end, 'cadastro', p.cargo)
          ) v(ordem, codigo, fonte, cargo)
         where v.codigo is not null
         order by (v.codigo = 'outros'), v.ordem
         limit 1) x on 'lead' = any(p.relacionamento_mind)
     where p.fundida_em is null;

  if p_gravar then
    update pessoas.pessoas p set cargo = t.cargo, atualizado_em = now()
      from perfil_pessoa_tmp t where t.mind_id = p.id and t.cargo is not null
       and intelligence.texto_chave(p.cargo) is distinct from intelligence.texto_chave(t.cargo);
    get diagnostics v_cargo = row_count;
    update pessoas.pessoas p set empresa = t.empresa_yazo, atualizado_em = now()
      from perfil_pessoa_tmp t where t.mind_id = p.id and t.empresa_yazo is not null
       and intelligence.texto_chave(p.empresa, true) is distinct from intelligence.texto_chave(t.empresa_yazo, true);
    get diagnostics v_empresa = row_count;
    update pessoas.pessoas p set icp = t.icp, icp_fonte = t.icp_fonte, icp_confianca = t.icp_confianca, atualizado_em = now()
      from perfil_pessoa_tmp t where t.mind_id = p.id
       and (p.icp, p.icp_fonte, p.icp_confianca) is distinct from (t.icp, t.icp_fonte, t.icp_confianca);
    get diagnostics v_icp = row_count;
  else
    select count(*) filter (where t.cargo is not null and intelligence.texto_chave(p.cargo) is distinct from intelligence.texto_chave(t.cargo)),
           count(*) filter (where t.empresa_yazo is not null and intelligence.texto_chave(p.empresa, true) is distinct from intelligence.texto_chave(t.empresa_yazo, true)),
           count(*) filter (where (p.icp, p.icp_fonte, p.icp_confianca) is distinct from (t.icp, t.icp_fonte, t.icp_confianca))
      into v_cargo, v_empresa, v_icp from perfil_pessoa_tmp t join pessoas.pessoas p on p.id = t.mind_id;
  end if;
  return jsonb_build_object('cargos_gravados', v_cargo, 'empresas_gravadas', v_empresa, 'icps_gravados', v_icp, 'gravou', p_gravar);
end $function$;

-- 3. a memória segue a mesma ordem, e o credenciamento vence o ICP manual do HubSpot -----------------
do $migra$
declare d text := pg_get_functiondef('intelligence.perfil_projetar(uuid,boolean)'::regprocedure); o text;
begin
  o := d;
  d := replace(d, '-- 1. cargo e empresa por prioridade: credenciamento (Yazo) > conversa > espelho HubSpot > pessoa',
                  '-- 1. cargo e empresa por prioridade (Adriana, 24/09): credenciamento (Yazo) > espelho HubSpot > conversa > pessoa');
  d := replace(d, $x$'conversa', 2$x$, $x$'conversa', 3$x$);
  d := replace(d, $x$'hubspot', 3 from crm.contato_espelho$x$, $x$'hubspot', 2 from crm.contato_espelho$x$);
  d := replace(d, $x$    if v_manual is not null then
      v_icp_acao := 'hubspot_manual_vence';$x$,
                  $x$    -- o cargo do credenciamento sobrescreve qualquer dado antigo, inclusive ICP manual (Adriana, 24/09)
    if v_manual is not null and v_fonte is distinct from 'credenciamento_yazo' then
      v_icp_acao := 'hubspot_manual_vence';$x$);
  if d = o or strpos(d, $x$'hubspot', 2 from$x$) = 0 or strpos(d, $x$'conversa', 3$x$) = 0
     or strpos(d, 'v_fonte is distinct from ''credenciamento_yazo''') = 0 then
    raise exception 'perfil_projetar: trecho esperado não encontrado; nada alterado';
  end if;
  execute d;
end $migra$;

-- 4. a rodada horária também grava pessoas.pessoas ---------------------------------------------------
do $migra$
declare d text := pg_get_functiondef('intelligence.perfil_projetar_todos(boolean)'::regprocedure); o text;
begin
  o := d;
  d := replace(d, $x$  return jsonb_build_object('pessoas', v_pessoas, 'gravou', p_gravar, 'relacionamento', v_rel,$x$,
                  $x$  -- por último, cargo/empresa/ICP em pessoas.pessoas (é de lá que o HubSpot lê o ICP)
  v := v || jsonb_build_object('pessoas_pessoas', intelligence.perfil_gravar_pessoas(p_gravar));
  return jsonb_build_object('pessoas', v_pessoas, 'gravou', p_gravar, 'relacionamento', v_rel,$x$);
  if d = o then raise exception 'perfil_projetar_todos: trecho esperado não encontrado'; end if;
  execute d;
end $migra$;

-- 5. o plano do HubSpot lê o ICP de pessoas.pessoas e marca quando o credenciamento manda ------------
drop function if exists public.mind_hubspot_perfil_plano(timestamptz);
create function public.mind_hubspot_perfil_plano(p_desde timestamp with time zone default null)
returns table(mind_id uuid, hubspot_id text, email text, jobtitle text, company text, icp text, icp_confianca numeric,
              jtbd text[], resumo text, ultimo_escrito jsonb, fontes jsonb, nao_lead boolean, forcar boolean)
language sql stable security definer set search_path to 'pg_catalog', 'public'
as $function$
  with yazo as (
    select r.mind_id, max(nullif(btrim(r."Cargo / Profissão"), '')) as cargo, max(nullif(btrim(r."Empresa"), '')) as empresa
      from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r where r.mind_id is not null group by r.mind_id),
  emp as (
    select intelligence.texto_chave(empresa, true) as chave, mode() within group (order by intelligence.texto_exibir(empresa)) as exibir
      from yazo where empresa is not null group by 1),
  icp as (
    -- o ICP de cada pessoa mora em pessoas.pessoas (prioridade da Adriana, 24/09/2026)
    select p.id as mind_id, i.hubspot_valor, i.rotulo, p.icp_confianca as confianca, p.icp_fonte
      from pessoas.pessoas p
      join intelligence.icp i on i.codigo = p.icp and i.ativo and i.hubspot_opcao and i.hubspot_valor is not null
     where p.fundida_em is null and p.icp is not null),
  jt as (
    select pm.mind_id, array_agg(distinct j.hubspot_valor) as valores
      from intelligence.participante_memoria pm
      join intelligence.jtbd j on j.ativo and j.hubspot_opcao and j.hubspot_valor is not null and j.codigo = pm.valor->>'code'
     where pm.tipo = 'jtbd' and pm.status = 'ativa' and (pm.valido_ate is null or pm.valido_ate > now())
     group by pm.mind_id),
  nl as (
    -- quem não é lead (staff, palestrante, professor, parceiro de venda — pessoas.relacionamento_mind): cargo e
    -- empresa vão; ICP, JTBD e resumo não, e o que estiver no HubSpot a função limpa (nao_lead = true)
    select p.id as mind_id, p.relacionamento_mind from pessoas.pessoas p
     where p.fundida_em is null and not ('lead' = any(p.relacionamento_mind))),
  universo as (select mind_id from yazo union select mind_id from icp union select mind_id from jt union select mind_id from nl),
  mudou as (
    select distinct pm.mind_id from intelligence.participante_memoria pm
     where p_desde is not null and pm.tipo in ('icp', 'jtbd', 'cargo', 'empresa') and pm.atualizado_em >= p_desde
    union
    select p.id from pessoas.pessoas p where p_desde is not null and p.atualizado_em >= p_desde),
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
         coalesce(intelligence.texto_exibir(y.cargo), p.cargo) as jobtitle,
         e.exibir as company,
         case when nl.mind_id is null then icp.hubspot_valor end as icp,
         case when nl.mind_id is null and icp.confianca is not null then round(icp.confianca * 10) end as icp_confianca,
         case when nl.mind_id is null then coalesce(jt.valores, '{}'::text[]) else '{}'::text[] end as jtbd,
         case when nl.mind_id is null then intelligence.perfil_resumo(u.mind_id) end as resumo,
         ult.props as ultimo_escrito,
         jsonb_strip_nulls(jsonb_build_object('cargo_yazo', y.cargo, 'empresa_yazo', y.empresa, 'icp_rotulo', case when nl.mind_id is null then icp.rotulo end,
                                              'icp_fonte', case when nl.mind_id is null then icp.icp_fonte end,
                                              'relacionamento', case when nl.mind_id is not null then to_jsonb(nl.relacionamento_mind) end)) as fontes,
         nl.mind_id is not null as nao_lead,
         y.cargo is not null as forcar
    from universo u
    join pessoas.pessoas p on p.id = u.mind_id and p.fundida_em is null
    left join yazo y on y.mind_id = u.mind_id
    left join emp e on e.chave = intelligence.texto_chave(y.empresa, true)
    left join icp on icp.mind_id = u.mind_id
    left join jt on jt.mind_id = u.mind_id
    left join nl on nl.mind_id = u.mind_id
    left join contato ct on ct.mind_id = u.mind_id
    left join ult on ult.hubspot_id = ct.hubspot_id
   where p_desde is null or exists (select 1 from mudou m where m.mind_id = u.mind_id)
   order by u.mind_id;
$function$;

revoke all on function public.mind_hubspot_perfil_plano(timestamptz) from public, anon, authenticated;
grant execute on function public.mind_hubspot_perfil_plano(timestamptz) to service_role;
