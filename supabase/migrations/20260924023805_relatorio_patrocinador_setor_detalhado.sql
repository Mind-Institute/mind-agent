-- Estado consolidado (24/09/2026) do write-back de pessoas.empresas para o HubSpot e do setor detalhado.
-- Ledger desta etapa: 023002, 023110, 023138, 023304, 023507, 023805.
--
-- Write-back (aprovação da Adriana: "Criar agora só as que têm domínio corporativo ou porte confirmado, e
-- atualizar as 69 existentes"): Edge Function hubspot-empresas-writeback lê pessoas.empresas_hubspot_plano().
--   criar     = empresa nova, nome de empresa (não "Psicóloga", "Sem Empresa"…) e domínio que combina com o
--               nome (ou porte confirmado sem domínio);
--   atualizar = company existente: só preenche campo vazio (funcionários, cidade, UF, país);
--   revisar / revisar_mesmo_dominio = nunca grava (o domínio já é de uma company do HubSpot → alias).
-- Execução de 24/09 02:36 UTC: 98 criadas, 59 atualizadas, 103 contatos associados, 0 falhas
-- (auditoria em mind_admin_audit, resource 'pessoas_empresas_hubspot').

create or replace function pessoas.empresa_nome_de_empresa(p_nome text)
 returns boolean language sql immutable as $$
  select intelligence.texto_chave(p_nome, true) is not null
     and intelligence.texto_chave(p_nome) !~ '^(sem empresa|nenhuma?|psicolog[oa]|psicologa clinica|empreendedor[a]?|profissional liberal|consultor[a]?|autonom[oa]|coach|terapeuta|pmsp|mei|freelancer?|estrategia|consultoria|people|rh|desenvolvimento humano|particular|independente)$'
$$;

create or replace function pessoas.empresa_dominio_combina(p_nome text, p_dominio text)
 returns boolean language sql immutable as $$
  with x as (
    select replace(intelligence.texto_chave(p_nome, true), ' ', '') nk,
           split_part(intelligence.texto_chave(p_nome, true), ' ', 1) t1,
           regexp_replace(split_part(regexp_replace(lower(p_dominio), '^(www\d?\.)', ''), '.', 1), '[^a-z0-9]', '', 'g') dr)
  select p_dominio is not null
     and p_dominio !~* '(negocio\.site|blogspot|wixsite|wordpress|linktr|instagram|facebook|godaddysites|tinyurl)'
     and not (lower(p_dominio) ~ '\.[a-z]{2}$' and lower(p_dominio) !~ '\.(br|co|io|us|vc|ai)$')
     and length(dr) >= 3
     and (nk like '%' || dr || '%' or dr like '%' || nk || '%' or (length(t1) >= 4 and dr like '%' || t1 || '%'))
  from x
$$;

create or replace function pessoas.empresas_hubspot_plano()
 returns jsonb language sql stable security definer
 set search_path to 'pg_catalog', 'public', 'pessoas', 'crm'
as $$
  with base as (
    select e.*,
           (select c.hubspot_company_id from crm.empresa_espelho c
             where e.dominio is not null and lower(regexp_replace(c.domain, '^www\.', '')) = lower(e.dominio)
             order by c.num_associated_contacts desc nulls last limit 1) hs_mesmo_dominio
      from pessoas.empresas e where e.hubspot_pendente),
  plano as (
    select b.id, 'revisar_mesmo_dominio' acao, b.hs_mesmo_dominio hubspot_company_id, jsonb_build_object('name', b.nome, 'domain', b.dominio) props
      from base b where b.hubspot_company_id is null and b.hs_mesmo_dominio is not null
    union all
    select b.id,
           case when pessoas.empresa_nome_de_empresa(b.nome)
                 and (pessoas.empresa_dominio_combina(b.nome, b.dominio) or (b.dominio is null and b.funcionarios is not null))
                then 'criar' else 'revisar' end,
           null,
           jsonb_strip_nulls(jsonb_build_object(
             'name', b.nome,
             'domain', case when pessoas.empresa_dominio_combina(b.nome, b.dominio) then b.dominio end,
             'numberofemployees', b.funcionarios::text,
             'city', b.cidade, 'state', b.uf, 'country', b.pais))
      from base b where b.hubspot_company_id is null and b.hs_mesmo_dominio is null
       and (b.dominio is not null or b.funcionarios is not null)
    union all
    select b.id, 'atualizar', b.hubspot_company_id,
           jsonb_strip_nulls(jsonb_build_object(
             'numberofemployees', case when c.numberofemployees is null then b.funcionarios::text end,
             'city', case when nullif(c.city, '') is null then b.cidade end,
             'state', case when nullif(c.state, '') is null then b.uf end,
             'country', case when nullif(c.country, '') is null then b.pais end))
      from base b join crm.empresa_espelho c on c.hubspot_company_id = b.hubspot_company_id)
  select jsonb_build_object(
    'resumo', (select jsonb_object_agg(acao, n) from (select acao, count(*) n from plano where acao <> 'atualizar' or props <> '{}'::jsonb group by 1) x),
    'itens', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'acao', acao, 'hubspot_company_id', hubspot_company_id, 'props', props))
                         from plano where acao <> 'atualizar' or props <> '{}'::jsonb), '[]'::jsonb));
$$;

create or replace function pessoas.empresas_hubspot_registrar(p_resultados jsonb)
 returns jsonb language plpgsql security definer
 set search_path to 'pg_catalog', 'public', 'pessoas'
as $$
declare v_n int;
begin
  update pessoas.empresas e set
         hubspot_company_id = coalesce(e.hubspot_company_id, r->>'hubspot_company_id'),
         hubspot_pendente = false, hubspot_sincronizado_em = now(), atualizado_em = now()
    from jsonb_array_elements(p_resultados) r
   where e.id = (r->>'id')::uuid and (r->>'ok')::boolean;
  get diagnostics v_n = row_count;
  insert into public.mind_admin_audit (action, resource, record_id, record_label, after_data, request_id)
  values ('atualizar', 'pessoas_empresas_hubspot', to_char(now(), 'YYYYMMDDHH24MISSMS'),
          'Write-back de pessoas.empresas para o HubSpot', p_resultados, gen_random_uuid());
  return jsonb_build_object('registradas', v_n);
end $$;

create or replace function pessoas.empresas_hubspot_contatos(p_empresa_ids uuid[])
 returns jsonb language sql stable security definer
 set search_path to 'pg_catalog', 'public', 'pessoas', 'crm'
as $$
  select coalesce(jsonb_agg(jsonb_build_object('empresa_id', p.empresa_id, 'contato', p.hubspot_id)), '[]'::jsonb)
    from pessoas.pessoas p
    join crm.contato_espelho c on c.hubspot_id::text = p.hubspot_id::text
   where p.empresa_id = any(p_empresa_ids) and p.hubspot_id is not null and p.fundida_em is null
     and nullif(c.propriedades->>'associatedcompanyid', '') is null;
$$;

create or replace function public.mind_empresas_hubspot_plano()
 returns jsonb language sql stable security definer set search_path to 'pg_catalog', 'public'
as $$ select pessoas.empresas_hubspot_plano() $$;
create or replace function public.mind_empresas_hubspot_contatos(p_empresa_ids uuid[])
 returns jsonb language sql stable security definer set search_path to 'pg_catalog', 'public'
as $$ select pessoas.empresas_hubspot_contatos(p_empresa_ids) $$;
create or replace function public.mind_empresas_hubspot_registrar(p_resultados jsonb)
 returns jsonb language sql security definer set search_path to 'pg_catalog', 'public'
as $$ select pessoas.empresas_hubspot_registrar(p_resultados) $$;
create or replace function public.mind_empresas_hubspot_disparar(p_executar boolean default false)
 returns bigint language plpgsql security definer set search_path to 'public', 'platform', 'net'
as $$
declare v_base text; v_key text;
begin
  select base_url, config->>'anon_key' into v_base, v_key from platform.integracoes where codigo = 'supabase_functions' and ativo;
  if v_base is null or v_key is null then raise exception 'integracao supabase_functions sem base_url ou anon_key'; end if;
  return net.http_post(url := v_base || '/hubspot-empresas-writeback',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
    body := jsonb_build_object('executar', p_executar), timeout_milliseconds := 150000);
end $$;

revoke all on function pessoas.empresas_hubspot_plano() from public, anon, authenticated;
revoke all on function pessoas.empresas_hubspot_registrar(jsonb) from public, anon, authenticated;
revoke all on function pessoas.empresas_hubspot_contatos(uuid[]) from public, anon, authenticated;
revoke all on function public.mind_empresas_hubspot_plano() from public, anon, authenticated;
revoke all on function public.mind_empresas_hubspot_contatos(uuid[]) from public, anon, authenticated;
revoke all on function public.mind_empresas_hubspot_registrar(jsonb) from public, anon, authenticated;
revoke all on function public.mind_empresas_hubspot_disparar(boolean) from public, anon, authenticated;
grant execute on function public.mind_empresas_hubspot_plano() to service_role;
grant execute on function public.mind_empresas_hubspot_contatos(uuid[]) to service_role;
grant execute on function public.mind_empresas_hubspot_registrar(jsonb) to service_role;

-- Setor: HubSpot vence a Lusha; "Consultoria e serviços empresariais" aberta em cinco (pedido de 24/09).
-- intelligence.setor_macro_hubspot / setor_macro_lusha: mesmas listas de 20260924021415, separadas por fonte.
create or replace function intelligence.setor_macro(p_hubspot text, p_lusha text)
 returns text language sql immutable as $$
  select coalesce(intelligence.setor_macro_hubspot(p_hubspot), intelligence.setor_macro_lusha(p_lusha))
$$;

create or replace function intelligence.setor_detalhe(p_hubspot text, p_lusha text, p_empresa text)
 returns text language sql immutable as $$
  with x as (select intelligence.setor_macro(p_hubspot, p_lusha) m, coalesce(intelligence.texto_chave(p_empresa), '') n)
  select case
    when m is null then null
    when m = 'Consultoria e serviços empresariais' and n ~ '\m(prefeitura|secretaria|governo|ministerio|tribunal|defensoria|pmsp)' then 'Setor público'
    when m = 'Consultoria e serviços empresariais' and p_hubspot is null and n ~ '(psicolog|psiquiat|saude|terapi|clinica|bem estar|mental|medic)' then 'Saúde e bem-estar'
    when m <> 'Consultoria e serviços empresariais' then m
    when p_hubspot in ('LEGAL_SERVICES','LAW_PRACTICE','ACCOUNTING') or n ~ '(advogad|advocacia|juridic|contab|auditor)' then 'Consultoria · jurídico e contábil'
    when p_hubspot in ('MARKETING_AND_ADVERTISING','PUBLIC_RELATIONS_AND_COMMUNICATIONS','MARKET_RESEARCH','DESIGN','GRAPHIC_DESIGN','EVENTS_SERVICES') or n ~ '(marketing|\mmkt|comunica|propaganda|publicidade|agencia|eventos|design)' then 'Consultoria · marketing, comunicação e eventos'
    when p_hubspot in ('HUMAN_RESOURCES','PROFESSIONAL_TRAINING_COACHING','STAFFING_AND_RECRUITING','OUTSOURCING_OFFSHORING')
      or n ~ '(\mrh\M|recursos humanos|pessoas|people|talent|treinament|desenvolvimento humano|\mdho\M|coach|mentor|carreira|lideranca|educacao corporativa|capacitac|humaniz|\mhuman)' then 'Consultoria · RH, treinamento e desenvolvimento humano'
    when p_hubspot = 'MANAGEMENT_CONSULTING' or n ~ '(consult|advisory|assessoria|gestao|estrateg|negocios)' then 'Consultoria · gestão e estratégia'
    else 'Consultoria · outros serviços empresariais' end
  from x
$$;

-- a base do relatório usa o setor detalhado
do $$
declare d text;
begin
  d := pg_get_viewdef('intelligence.v_relatorio_patrocinador_audiencia'::regclass, true);
  if position('setor_macro(e.industry, la.setor) AS setor' in d) > 0 then
    d := replace(d, 'setor_macro(e.industry, la.setor) AS setor', 'setor_detalhe(e.industry, la.setor, p.empresa) AS setor');
    execute 'create or replace view intelligence.v_relatorio_patrocinador_audiencia as ' || d;
  end if;
end $$;
