-- Porte e setor pela Lusha para as empresas dos presentes do Summit 2026 que o HubSpot não cobre
-- (pedido da Adriana, 24/09: "complete porte e setor pelo Lusha"). Uma linha por empresa
-- (emp_id = hubspot_company_id ou 'k:' || chave do nome). Consulta sem reveal (1 crédito a cada 25).
-- Aceite em crm.v_empresa_lusha_aceita (domínio bateu, ou nome compatível com sede no Brasil).
create table if not exists crm.empresa_lusha (
  emp_id          text primary key,
  nome_busca      text,
  dominio_busca   text,
  pessoas         int,
  lusha_id        text,
  lusha_nome      text,
  lusha_dominio   text,
  funcionarios    int,
  faixa_min       int,
  faixa_max       int,
  setor           text,
  cidade          text,
  uf              text,
  pais            text,
  aceito          boolean,
  motivo          text,
  consultado_em   timestamptz,
  criado_em       timestamptz not null default now()
);
comment on table crm.empresa_lusha is
  'Porte/setor da Lusha (consulta sem reveal) para empresas dos presentes do Summit 2026 sem dado no HubSpot. aceito = domínio bateu, ou nome compatível com sede no Brasil.';

insert into crm.empresa_lusha (emp_id, nome_busca, dominio_busca, pessoas)
select emp_id, nome, dom, n from (
  select coalesce(v.hubspot_company_id, 'k:' || intelligence.texto_chave(v.empresa, true)) emp_id,
         mode() within group (order by v.empresa) nome, count(*) n,
         bool_or(v.porte is not null and v.setor_hubspot is not null) completo,
         coalesce(
           max(nullif(regexp_replace(lower(e.domain), '^www\.', ''), '')),
           mode() within group (order by lower(split_part(p.email, '@', 2)))
             filter (where lower(split_part(p.email, '@', 2)) !~ '^(gmail|googlemail|hotmail|outlook|live|msn|yahoo|ymail|icloud|me|mac|uol|bol|terra|ig|globo|aol|protonmail|email|mail)\.')) dom
    from intelligence.v_relatorio_patrocinador_audiencia v
    join pessoas.pessoas p on p.id = v.mind_id
    left join crm.empresa_espelho e on e.hubspot_company_id = v.hubspot_company_id
   where v.presente and nullif(btrim(v.empresa), '') is not null
     and coalesce(intelligence.texto_chave(v.empresa), '') !~ '^(autonom|independente|particular|consultorio|freela|liberal|aposentad|nenhum|estudante)'
   group by 1) x
 where not completo
on conflict (emp_id) do nothing;
