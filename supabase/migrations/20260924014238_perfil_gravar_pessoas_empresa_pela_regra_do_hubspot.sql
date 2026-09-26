-- Dois escritores brigavam por pessoas.pessoas.empresa: a rodada horária do perfil
-- (perfil_projetar_todos → perfil_gravar_pessoas, :36) regravava a grafia da Yazo e desfazia a regra
-- de 24/09 da Adriana (Yazo > e-mail > HubSpot, com o NOME DA COMPANY DO HUBSPOT). Menor mudança:
-- a parte de empresa de perfil_gravar_pessoas passa a delegar para
-- crm.empresa_participantes_summit_2026_gravar (a Yazo continua sendo a fonte nº 1 lá dentro).
-- Cargo e ICP: sem mudança.
create or replace function intelligence.perfil_gravar_pessoas(p_gravar boolean default true)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public', 'intelligence', 'pessoas', 'crm', 'credenciamento_summit_2026'
as $function$
declare v_cargo int := 0; v_empresa int := 0; v_icp int := 0;
begin
  create temp table perfil_pessoa_tmp on commit drop as
    with yazo as (
      select v.mind_id, v.cargo, v.empresa from credenciamento_summit_2026.v_cargo_declarado v),
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
           x.codigo as icp, x.fonte as icp_fonte, x.confianca as icp_confianca
      from pessoas.pessoas p
      left join yazo y on y.mind_id = p.id
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
    -- empresa: regra de 24/09 (Yazo > e-mail > HubSpot; nome da company do HubSpot)
    v_empresa := coalesce((crm.empresa_participantes_summit_2026_gravar(true)->>'a_mudar')::int, 0);
    update pessoas.pessoas p set icp = t.icp, icp_fonte = t.icp_fonte, icp_confianca = t.icp_confianca, atualizado_em = now()
      from perfil_pessoa_tmp t where t.mind_id = p.id
       and (p.icp, p.icp_fonte, p.icp_confianca) is distinct from (t.icp, t.icp_fonte, t.icp_confianca);
    get diagnostics v_icp = row_count;
  else
    select count(*) filter (where t.cargo is not null and intelligence.texto_chave(p.cargo) is distinct from intelligence.texto_chave(t.cargo)),
           count(*) filter (where (p.icp, p.icp_fonte, p.icp_confianca) is distinct from (t.icp, t.icp_fonte, t.icp_confianca))
      into v_cargo, v_icp from perfil_pessoa_tmp t join pessoas.pessoas p on p.id = t.mind_id;
    v_empresa := coalesce((crm.empresa_participantes_summit_2026_gravar(false)->>'a_mudar')::int, 0);
  end if;
  return jsonb_build_object('cargos_gravados', v_cargo, 'empresas_gravadas', v_empresa, 'icps_gravados', v_icp, 'gravou', p_gravar);
end $function$;
