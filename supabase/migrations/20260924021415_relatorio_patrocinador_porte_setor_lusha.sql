-- Porte e setor da Lusha entram na base do relatório de patrocinadores (24/09/2026).
-- Regra de aceite da Lusha: domínio bateu; ou, na busca por nome, nome compatível e sede no Brasil.
-- Setor: HubSpot e Lusha usam taxonomias diferentes → um setor macro em português, igual para os dois.

create or replace function intelligence.setor_macro(p_hubspot text, p_lusha text)
 returns text language sql immutable as $$
  select case
    when p_hubspot in ('BANKING','FINANCIAL_SERVICES','CAPITAL_MARKETS','INSURANCE','INVESTMENT_MANAGEMENT','INVESTMENT_BANKING','VENTURE_CAPITAL_PRIVATE_EQUITY') or p_lusha = 'Finance' then 'Serviços financeiros e seguros'
    when p_hubspot in ('COMPUTER_SOFTWARE','INFORMATION_TECHNOLOGY_AND_SERVICES','INTERNET','COMPUTER_HARDWARE','COMPUTER_NETWORKING','COMPUTER_NETWORK_SECURITY','INFORMATION_SERVICES','SEMICONDUCTORS') or p_lusha = 'Technology, Information & Media' then 'Tecnologia'
    when p_hubspot in ('TELECOMMUNICATIONS','WIRELESS') or p_lusha = 'Telecommunications' then 'Telecom'
    when p_hubspot in ('FOOD_BEVERAGES','FOOD_PRODUCTION','CONSUMER_GOODS','COSMETICS','APPAREL_FASHION','WINE_AND_SPIRITS','CONSUMER_ELECTRONICS','TOBACCO','DAIRY','LUXURY_GOODS_JEWELRY','SPORTING_GOODS','TEXTILES','FURNITURE') or p_lusha = 'Consumer Goods' then 'Bens de consumo'
    when p_hubspot in ('RETAIL','SUPERMARKETS','WHOLESALE','IMPORT_AND_EXPORT') or p_lusha = 'Retail & Wholesale Trade' then 'Varejo e atacado'
    when p_hubspot in ('PHARMACEUTICALS','BIOTECHNOLOGY') or p_lusha = 'Pharmaceuticals' then 'Farmacêutico'
    when p_hubspot in ('HOSPITAL_HEALTH_CARE','MEDICAL_DEVICES','HEALTH_WELLNESS_AND_FITNESS','MENTAL_HEALTH_CARE','ALTERNATIVE_MEDICINE','INDIVIDUAL_FAMILY_SERVICES') or p_lusha = 'Healthcare' then 'Saúde e bem-estar'
    when p_hubspot in ('EDUCATION_MANAGEMENT','HIGHER_EDUCATION','E_LEARNING','PRIMARY_SECONDARY_EDUCATION','RESEARCH') or p_lusha = 'Education' then 'Educação e pesquisa'
    when p_hubspot in ('MANAGEMENT_CONSULTING','HUMAN_RESOURCES','PROFESSIONAL_TRAINING_COACHING','STAFFING_AND_RECRUITING','OUTSOURCING_OFFSHORING','MARKETING_AND_ADVERTISING','PUBLIC_RELATIONS_AND_COMMUNICATIONS','LEGAL_SERVICES','LAW_PRACTICE','ACCOUNTING','MARKET_RESEARCH','DESIGN','GRAPHIC_DESIGN','EVENTS_SERVICES','FACILITIES_SERVICES','SECURITY_AND_INVESTIGATIONS','BUSINESS_SUPPLIES_AND_EQUIPMENT')
      or p_lusha = 'Business Services' then 'Consultoria e serviços empresariais'
    when p_hubspot in ('OIL_ENERGY','UTILITIES','RENEWABLES_ENVIRONMENT','ENVIRONMENTAL_SERVICES') or p_lusha in ('Utilities','Oil, Gas & Mining','Energy') then 'Energia e utilities'
    when p_hubspot = 'MINING_METALS' then 'Mineração e metais'
    when p_hubspot in ('CHEMICALS','AUTOMOTIVE','MACHINERY','MECHANICAL_OR_INDUSTRIAL_ENGINEERING','ELECTRICAL_ELECTRONIC_MANUFACTURING','PACKAGING_AND_CONTAINERS','BUILDING_MATERIALS','PAPER_FOREST_PRODUCTS','INDUSTRIAL_AUTOMATION','PLASTICS','GLASS_CERAMICS_CONCRETE','RAILROAD_MANUFACTURE','SHIPBUILDING','AVIATION_AEROSPACE','DEFENSE_SPACE')
      or p_lusha = 'Manufacturing' then 'Indústria'
    when p_hubspot in ('CONSTRUCTION','CIVIL_ENGINEERING','REAL_ESTATE','COMMERCIAL_REAL_ESTATE') or p_lusha in ('Construction','Real Estate') then 'Construção e imobiliário'
    when p_hubspot in ('LOGISTICS_AND_SUPPLY_CHAIN','TRANSPORTATION_TRUCKING_RAILROAD','AIRLINES_AVIATION','MARITIME') or p_lusha = 'Transportation & Logistics' then 'Transporte e logística'
    when p_hubspot in ('FARMING','RANCHING','FISHERY') or p_lusha = 'Farming, Ranching, Forestry' then 'Agronegócio'
    when p_hubspot in ('GOVERNMENT_ADMINISTRATION','GOVERNMENT_RELATIONS','JUDICIARY','LAW_ENFORCEMENT','PUBLIC_SAFETY','INTERNATIONAL_TRADE_AND_DEVELOPMENT') or p_lusha = 'Government' then 'Setor público'
    when p_hubspot in ('NON_PROFIT_ORGANIZATION_MANAGEMENT','CIVIC_SOCIAL_ORGANIZATION','RELIGIOUS_INSTITUTIONS','MUSEUMS_AND_INSTITUTIONS') or p_lusha = 'Community & Nonprofit Organizations' then 'Terceiro setor'
    when p_hubspot in ('BROADCAST_MEDIA','ONLINE_MEDIA','PUBLISHING','NEWSPAPERS','MEDIA_PRODUCTION','ANIMATION','ENTERTAINMENT') or p_lusha = 'Entertainment' then 'Mídia e entretenimento'
    when p_hubspot in ('CONSUMER_SERVICES','HOSPITALITY','RESTAURANTS','LEISURE_TRAVEL_TOURISM','SPORTS','RECREATIONAL_FACILITIES_AND_SERVICES') or p_lusha in ('Hospitality','Consumer Services') then 'Serviços ao consumidor e hospitalidade'
    when coalesce(p_hubspot, p_lusha) is null then null
    else 'Outros'
  end
$$;

create or replace view crm.v_empresa_lusha_aceita as
select l.*,
       coalesce(l.funcionarios, l.faixa_max) funcionarios_usado
  from crm.empresa_lusha l
 where l.lusha_id is not null
   and (
     (l.dominio_busca is not null and nullif(regexp_replace(lower(l.lusha_dominio), '^(https?://)?(www\.)?', ''), '') is not null
       and (regexp_replace(lower(l.lusha_dominio), '^(https?://)?(www\.)?', '') = l.dominio_busca
            or l.dominio_busca like '%.' || regexp_replace(lower(l.lusha_dominio), '^(https?://)?(www\.)?', '')
            or regexp_replace(lower(l.lusha_dominio), '^(https?://)?(www\.)?', '') like '%.' || l.dominio_busca))
     or (l.pais = 'Brazil'
       and (similarity(intelligence.texto_chave(l.lusha_nome, true), intelligence.texto_chave(l.nome_busca, true)) >= 0.5
            or (' ' || intelligence.texto_chave(l.lusha_nome, true) || ' ') like ('% ' || intelligence.texto_chave(l.nome_busca, true) || ' %')
            or (' ' || intelligence.texto_chave(l.nome_busca, true) || ' ') like ('% ' || intelligence.texto_chave(l.lusha_nome, true) || ' %')))
   );
comment on view crm.v_empresa_lusha_aceita is
  'Resultados da Lusha aceitos: domínio bateu, ou (busca por nome) nome compatível e sede no Brasil.';
revoke all on crm.v_empresa_lusha_aceita from public, anon, authenticated;

create or replace view intelligence.v_relatorio_patrocinador_audiencia as
with ctrl as (
  select public.mind_pessoa_canonica(c.mind_id) mind_id,
         bool_or(c.presenca_16_09 = 'sim') dia_16,
         bool_or(c.presenca_17_09 = 'sim') dia_17,
         (array_agg(c.categoria order by case c.categoria when 'Camarote' then 1 when 'Prime' then 2 when 'VIP' then 3 else 4 end))[1] ingresso,
         bool_or(c.palestrante) palestrante, bool_or(c.staff_mind) staff
    from credenciamento_summit_2026.controle_de_inscritos_e_presenca c
   where c.valido_no_mind = 'sim' and c.mind_id is not null
   group by 1),
yz as (
  select public.mind_pessoa_canonica(r.mind_id) mind_id,
         mode() within group (order by nullif(btrim(r."Empresa Patrocinadora, quando aplicável"), '')) patrocinador_ingresso,
         bool_or(nullif(btrim(r."Data/horário do primeiro acesso"), '') is not null) app_ativou,
         max(nullif(btrim(r."Data/horário do primeiro acesso"), '')) app_primeiro_acesso,
         max(nullif(btrim(r."Data/horário do último acesso"), '')) app_ultimo_acesso,
         sum(r."Postagens") postagens, sum(r."Curtidas") curtidas, sum(r."Comentários") comentarios,
         sum(r."Favoritos em agendas") favoritos_agenda, sum(r."Favoritos em palestrantes") favoritos_palestrantes,
         sum(r."Mensagens trocadas") mensagens, sum(r."Trocas de contato") trocas_contato
    from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r
   where r.mind_id is not null group by 1),
icp as (
  select distinct on (public.mind_pessoa_canonica(m.mind_id)) public.mind_pessoa_canonica(m.mind_id) mind_id,
         coalesce(m.valor->>'code', i.codigo) icp
    from intelligence.participante_memoria m
    left join intelligence.icp i on (m.valor->>'code') is null
         and (m.valor->>'text') in (i.rotulo, i.hubspot_valor, i.rotulo_legado)
   where m.tipo = 'icp' and m.chave = 'icp_atual' and m.status = 'ativa'
   order by public.mind_pessoa_canonica(m.mind_id), m.atualizado_em desc),
emp as (select * from crm.empresa_participantes_summit_2026()),
res as (
  select public.mind_pessoa_canonica(r.mind_id) mind_id, count(*) reservas,
         count(*) filter (where r."Fila de espera"::text = 'Sim') fila_espera
    from credenciamento_summit_2026."Reservas_Agenda_APP" r where r.mind_id is not null group by 1),
chk as (
  select public.mind_pessoa_canonica(k.mind_id) mind_id, count(distinct k.sessao_id) sessoes_checkin
    from credenciamento_summit_2026."Check Ins Summit" k where k.mind_id is not null group by 1)
select c.mind_id,
       c.dia_16, c.dia_17, (c.dia_16 or c.dia_17) presente, (c.dia_16 and c.dia_17) dois_dias,
       c.ingresso,
       yz.patrocinador_ingresso,
       p.cargo,
       icp.icp,
       intelligence.senioridade_por_cargo(p.cargo, icp.icp) senioridade,
       intelligence.area_por_cargo(p.cargo, icp.icp) area,
       p.empresa,
       emp.hubspot_company_id,
       emp.fonte empresa_fonte,
       e.industry setor_hubspot,
       coalesce(e.numberofemployees, la.funcionarios_usado) funcionarios,
       case when coalesce(e.numberofemployees, la.funcionarios_usado) is null then null
            when coalesce(e.numberofemployees, la.funcionarios_usado) <= 100 then '1. até 100'
            when coalesce(e.numberofemployees, la.funcionarios_usado) <= 500 then '2. 101–500'
            when coalesce(e.numberofemployees, la.funcionarios_usado) <= 1000 then '3. 501–1.000'
            when coalesce(e.numberofemployees, la.funcionarios_usado) <= 5000 then '4. 1.001–5.000'
            when coalesce(e.numberofemployees, la.funcionarios_usado) <= 10000 then '5. 5.001–10.000'
            else '6. +10.000' end porte,
       e.country pais_empresa, e.city cidade_empresa, e.state uf_empresa,
       coalesce(yz.app_ativou, false) app_ativou, yz.app_primeiro_acesso, yz.app_ultimo_acesso,
       yz.postagens, yz.curtidas, yz.comentarios, yz.favoritos_agenda, yz.favoritos_palestrantes,
       yz.mensagens, yz.trocas_contato,
       coalesce(res.reservas, 0) reservas, coalesce(res.fila_espera, 0) fila_espera,
       coalesce(chk.sessoes_checkin, 0) sessoes_checkin,
       coalesce(emp.hubspot_company_id, 'k:' || intelligence.texto_chave(p.empresa, true)) emp_id,
       intelligence.setor_macro(e.industry, la.setor) setor,
       case when e.numberofemployees is not null then 'hubspot' when la.funcionarios_usado is not null then 'lusha' end porte_fonte,
       case when e.industry is not null then 'hubspot' when la.setor is not null then 'lusha' end setor_fonte
  from ctrl c
  join pessoas.pessoas p on p.id = c.mind_id
  left join yz on yz.mind_id = c.mind_id
  left join icp on icp.mind_id = c.mind_id
  left join emp on emp.mind_id = c.mind_id
  left join crm.empresa_espelho e on e.hubspot_company_id = emp.hubspot_company_id
  left join crm.v_empresa_lusha_aceita la on la.emp_id = coalesce(emp.hubspot_company_id, 'k:' || intelligence.texto_chave(p.empresa, true))
  left join res on res.mind_id = c.mind_id
  left join chk on chk.mind_id = c.mind_id
 where not coalesce(c.palestrante, false) and not coalesce(c.staff, false);


revoke all on intelligence.v_relatorio_patrocinador_audiencia from public, anon, authenticated;
