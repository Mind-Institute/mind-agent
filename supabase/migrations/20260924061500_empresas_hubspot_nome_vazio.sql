-- Empresas que o próprio HubSpot cria sem nome (Adriana, 24/09/2026 — passo 6 do enriquecimento).
--
-- O HubSpot cria company automaticamente pelo domínio do e-mail do contato (origem CRM_SETTING), sem
-- nome e com o domínio exato do e-mail — inclusive subdomínio e typo (br.gestamp.com,
-- aambulanciasmban.com.br). Criar outra company pelo plano duplicaria. Em vez disso:
--   1) a empresa de pessoas.empresas (origem 'dominio', ainda sem hubspot_company_id) passa a apontar
--      para a company sem nome à qual o contato já está associado (ou que tem o mesmo domínio), quando
--      há exatamente uma e nenhuma outra empresa já aponta para ela;
--   2) no plano, 'atualizar' preenche também o NOME quando ele está vazio no HubSpot e, só nesse caso
--      (company automática), corrige o domínio para o da empresa. Company com nome continua intocada.

create or replace function pessoas.empresas_hubspot_plano()
returns jsonb language sql stable security definer
set search_path to 'pg_catalog', 'public', 'pessoas', 'crm'
as $function$
  with base as (
    select e.*,
           (select c.hubspot_company_id from crm.empresa_espelho c
             where e.dominio is not null and lower(regexp_replace(c.domain, '^www\.', '')) = lower(e.dominio)
             order by c.num_associated_contacts desc nulls last limit 1) hs_mesmo_dominio
      from pessoas.empresas e where e.hubspot_pendente),
  plano as (
    -- já existe no HubSpot pelo domínio: não cria (evita duplicata); fica para revisão
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
             'name', case when nullif(btrim(c.name), '') is null then b.nome end,
             'domain', case when nullif(btrim(c.name), '') is null and b.dominio is not null
                             and lower(coalesce(c.domain, '')) <> lower(b.dominio) then b.dominio end,
             'numberofemployees', case when c.numberofemployees is null then b.funcionarios::text end,
             'city', case when nullif(c.city, '') is null then b.cidade end,
             'state', case when nullif(c.state, '') is null then b.uf end,
             'country', case when nullif(c.country, '') is null then b.pais end))
      from base b join crm.empresa_espelho c on c.hubspot_company_id = b.hubspot_company_id)
  select jsonb_build_object(
    'resumo', (select jsonb_object_agg(acao, n) from (select acao, count(*) n from plano where acao <> 'atualizar' or props <> '{}'::jsonb group by 1) x),
    'itens', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'acao', acao, 'hubspot_company_id', hubspot_company_id, 'props', props))
                         from plano where acao <> 'atualizar' or props <> '{}'::jsonb), '[]'::jsonb));
$function$;

-- 1) ligar à company automática (sem nome)
with cand as (
  select e.id eid, c.hubspot_company_id hs
    from pessoas.empresas e
    join pessoas.pessoas p on p.empresa_id = e.id and p.fundida_em is null
    join crm.contato_espelho ct on ct.hubspot_id::text = p.hubspot_id::text
    join crm.empresa_espelho c on c.hubspot_company_id = ct.propriedades->>'associatedcompanyid'
   where e.hubspot_company_id is null and e.origem = 'dominio' and nullif(btrim(c.name), '') is null
  union
  select e.id, c.hubspot_company_id
    from pessoas.empresas e
    join crm.empresa_espelho c on lower(regexp_replace(c.domain, '^www\.', '')) = lower(e.dominio)
   where e.hubspot_company_id is null and e.origem = 'dominio' and nullif(btrim(c.name), '') is null),
unico as (
  select eid, min(hs) hs from cand group by eid having count(distinct hs) = 1),
livre as (
  select u.* from unico u
   where (select count(*) from unico u2 where u2.hs = u.hs) = 1
     and not exists (select 1 from pessoas.empresas o where o.hubspot_company_id = u.hs))
update pessoas.empresas e
   set hubspot_company_id = l.hs, hubspot_pendente = true, atualizado_em = now()
  from livre l
 where e.id = l.eid;
