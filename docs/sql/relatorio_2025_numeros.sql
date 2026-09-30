-- Relatório de valor — seções 3 (empresas) e 4 (setores) para o Mind Summit 2025, e base da comparação.
-- Base 2025 = INSCRITOS: ingresso "Atribuído" (participante nominal) nas duas contas que venderam 2025
-- (eduzz.ingressos, conta_venda 'mind_dash' + 'ef'); reembolsados e não atribuídos ficam de fora; staff e
-- palestrantes (pessoas.relacionamento_mind) também. Não há check-in de 2025 na base.
-- Empresa = pessoas.pessoas.empresa; porte/setor = HubSpot da empresa ligada (pessoas.empresas →
-- crm.empresa_espelho), completado pela Lusha aceita e por pessoas.empresas. Mesma regra de grupo de
-- empresa do relatório 2026 (docs/sql/relatorio_patrocinadores_base.sql).
set statement_timeout = '55s';
create temp table a25 on commit drop as
with t as (
  select distinct public.mind_pessoa_canonica(i.mind_id) mind_id
    from eduzz.ingressos i
   where i.evento_titulo = 'Mind Summit 2025' and i.status = 'Atribuído' and i.mind_id is not null),
a as (
  select p.id mind_id, p.empresa, p.cargo, nullif(lower(split_part(p.email, '@', 2)), '') dom,
         pe.hubspot_company_id, e.industry, pe.setor_bruto,
         coalesce(e.numberofemployees, la.funcionarios_usado::numeric, pe.funcionarios::numeric) func,
         la.setor la_setor
    from t join pessoas.pessoas p on p.id = t.mind_id
    left join pessoas.empresas pe on pe.id = p.empresa_id
    left join crm.empresa_espelho e on e.hubspot_company_id = pe.hubspot_company_id
    left join crm.v_empresa_lusha_aceita la on la.emp_id = coalesce(pe.hubspot_company_id, 'k:' || intelligence.texto_chave(p.empresa, true))
   where not (coalesce(p.relacionamento_mind, '{}') && array['staff', 'palestrante'])),
b as (
  select a.*,
         case when empresa is null or empresa ~* '^(aut[oô]nom[oa]|freelancer?|nenhuma?|sem empresa)$' then null else empresa end emp,
         case when dom ~ '(gmail|gmai\.|hotmail|hotmai\.|outlook|outlok|yahoo|icloud|live|uol|bol|terra|msn|me\.com|protonmail|globo\.com|ig\.com|joinmind)' then null else dom end cdom,
         case when func is null then null when func <= 100 then '1. até 100' when func <= 500 then '2. 101–500'
              when func <= 1000 then '3. 501–1.000' when func <= 5000 then '4. 1.001–5.000'
              when func <= 10000 then '5. 5.001–10.000' else '6. +10.000' end porte,
         intelligence.setor_detalhe(industry, coalesce(la_setor, setor_bruto), empresa) setor
    from a),
nd as (select emp, mode() within group (order by cdom) d from b where emp is not null and cdom is not null group by 1)
select b.*,
       case when b.emp is null then null
            when b.emp ~* 'heineken' then 'heineken.com.br'
            when b.emp ~* '^vale( |$)' then 'vale.com'
            when b.emp ~* '^bwg' then 'bwg.com.br'
            when b.emp ~* '(faculdade bp|benefici?encia portuguesa)' then 'bp.org.br'
            when b.emp ~* '^natura( |$)' then 'natura.net'
            when b.emp ~* 'haleon' then 'haleon.com'
            when b.emp ~* '(sextante|gmt editores)' then 'sextante.com.br'
            when b.emp ~* '^bluma' then 'blumaoficial.com.br'
            when b.emp ~* '^mais diversidade' then 'maisdiversidade.com.br'
            when b.emp ~* 'mindself' then 'mindself.com.br'
            when b.emp ~* 'senac' or nd.d ~ 'senac' then 'senac'
            when b.emp ~* '(sefaz|secretaria da fazenda)' then 'sefaz'
            when nd.d ~ 'beiersdorf' or b.emp ~* '(beiersdorf|bdf nivea)' then 'beiersdorf'
            when b.emp ~* 'sebrae' then 'sebrae'
            when b.emp ~* '^(usp|universidade de s[aã]o paulo)( |$)' then 'usp'
            when b.emp ~* '^(pmsp|prefeitura de s[aã]o paulo)' then 'pmsp'
            when nd.d in ('gympass.com', 'wellhub.com') or b.emp ~* '^(wellhub|wellz)' then 'wellhub'
            else coalesce(nd.d, 'n:' || intelligence.texto_chave(b.emp, true)) end k
  from b left join nd using (emp);
create temp table g25 on commit drop as
select k, count(*) n, mode() within group (order by emp) nome, max(porte) porte, mode() within group (order by setor) setor
  from a25 where k is not null group by k;
select jsonb_build_object(
  'inscritos', (select count(*) from a25),
  'com_empresa', (select count(*) from a25 where k is not null),
  'com_porte', (select count(*) from a25 a join g25 g using (k) where g.porte is not null),
  'com_setor', (select count(*) from a25 a join g25 g using (k) where g.setor is not null),
  'empresas', (select count(*) from g25),
  'porte_pessoas', (select jsonb_object_agg(porte, n) from (select g.porte, count(*) n from a25 a join g25 g using (k) where g.porte is not null group by 1) x),
  'porte_empresas', (select jsonb_object_agg(porte, n) from (select porte, count(*) n from g25 where porte is not null group by 1) x),
  'delegacoes', (select jsonb_agg(jsonb_build_array(nome, n, porte, setor) order by n desc, nome) from g25 where n >= 5),
  'g10', (select string_agg(nome || ' ' || n, '|' order by n desc, nome) from g25 where porte = '6. +10.000'),
  'g5', (select string_agg(nome || ' ' || n, '|' order by n desc, nome) from g25 where porte = '5. 5.001–10.000'),
  'setor', (select jsonb_agg(jsonb_build_array(setor, n, ex) order by n desc) from (
             select g.setor, sum(g.n) n,
                    (select string_agg(nome, ', ' order by n2 desc, nome) from (select nome, n n2 from g25 g2 where g2.setor = g.setor order by n desc, nome limit 3) z) ex
               from g25 g where g.setor is not null group by g.setor) s)
) r;
