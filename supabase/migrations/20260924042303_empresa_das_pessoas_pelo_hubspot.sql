-- Empresa de TODAS as pessoas (Adriana, 24/09/2026, passo 1 do enriquecimento): "procurar em hubspot a
-- empresa ... e preencher em pessoas.pessoas". A regra do Summit 2026 (crm.empresa_participantes_summit_2026)
-- continua dona dos participantes; esta cuida do resto e só preenche quem está SEM empresa.
--
-- Ordem (a primeira que existir vence):
--   1. company associada ao contato no HubSpot (propriedades.associatedcompanyid) — nome da company;
--   2. domínio do e-mail corporativo = domínio de UMA company do HubSpot — nome da company;
--   3. campo "company" do contato: se casa com uma company pelo nome, usa o nome do HubSpot; texto solto só
--      vale se tem cara de empresa (ltda, grupo, instituto, consultoria…) ou se repete em 2+ pessoas —
--      nome de pessoa, profissão, cidade e telefone ficam para os passos seguintes (domínio / Lusha).
-- Companies-lixo do HubSpot ("Gmail", "Br", nome com menos de 3 letras) nunca viram empresa.
-- Liga pessoas.pessoas.empresa_id ao registro em pessoas.empresas (pela company do HubSpot ou pelo nome).
-- Grava o antes/depois em mind_admin_audit. Roda dentro de intelligence.perfil_gravar_pessoas.

create or replace function crm.empresa_pessoas()
returns table (mind_id uuid, email text, empresa_final text, hubspot_company_id text, fonte text)
language sql stable security definer
set search_path to 'pg_catalog', 'public', 'pessoas', 'crm', 'intelligence'
as $$
  with part as (   -- mesma base de participantes da regra do Summit 2026 (Yazo + credenciamento não revogado)
    select distinct public.mind_pessoa_canonica(x.mind_id) mind_id from (
      select r.mind_id from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r where r.mind_id is not null
      union select c.mind_id from credenciamento_summit_2026.participantes c where c.mind_id is not null and c.revogado_em is null) x),
  p as (
    select p.id, p.email, lower(split_part(p.email, '@', 2)) dom
      from pessoas.pessoas p
     where p.fundida_em is null and nullif(btrim(p.empresa), '') is null
       and not exists (select 1 from part where part.mind_id = p.id)),
  hs as (
    select distinct on (public.mind_pessoa_canonica(c.mind_id)) public.mind_pessoa_canonica(c.mind_id) mind_id,
           nullif(c.propriedades->>'associatedcompanyid', '') assoc, nullif(btrim(c.company), '') company
      from crm.contato_espelho c where c.mind_id is not null
     order by public.mind_pessoa_canonica(c.mind_id), (nullif(c.propriedades->>'associatedcompanyid', '') is not null) desc,
              c.atualizado_em desc nulls last),
  hs_ok as (
    select e.* from crm.empresa_espelho e
     where length(btrim(coalesce(e.name, ''))) >= 3
       and btrim(e.name) !~* '^(gmail|googlemail|hotmail|outlook|live|msn|yahoo|icloud|uol|bol|terra|ig|globo|aol|protonmail|e-?mail)(\.com)?$'),
  texto_rep as (
    select intelligence.texto_chave(company, true) k from hs where company is not null group by 1 having count(*) >= 2),
  dom_unico as (
    select lower(regexp_replace(e.domain, '^(https?://)?(www\.)?', '')) dom, min(e.hubspot_company_id) hid
      from hs_ok e where nullif(e.domain, '') is not null
     group by 1 having count(*) = 1),
  nome_unico as (
    select e.nome_chave, min(e.hubspot_company_id) hid from hs_ok e
     where e.nome_chave is not null group by 1 having count(*) = 1)
  select p.id, p.email,
         coalesce(ea.name, ed.name, en.name, hs.company) empresa_final,
         coalesce(ea.hubspot_company_id, ed.hubspot_company_id, en.hubspot_company_id) hubspot_company_id,
         case when ea.hubspot_company_id is not null then 'hubspot_associada'
              when ed.hubspot_company_id is not null then 'dominio_hubspot'
              when en.hubspot_company_id is not null then 'hubspot_campo_company'
              else 'hubspot_campo_texto' end fonte
    from p
    left join hs on hs.mind_id = p.id
    left join hs_ok ea on ea.hubspot_company_id = hs.assoc and nullif(btrim(ea.name), '') is not null
    left join dom_unico du on ea.hubspot_company_id is null and du.dom = p.dom
         and p.dom !~ '^(gmail|googlemail|hotmail|outlook|live|msn|yahoo|ymail|icloud|me|mac|uol|bol|terra|ig|globo|aol|protonmail|email|mail)\.'
    left join hs_ok ed on ed.hubspot_company_id = du.hid
    left join nome_unico nu on ea.hubspot_company_id is null and ed.hubspot_company_id is null
         and hs.company is not null and nu.nome_chave = intelligence.texto_chave(hs.company, true)
    left join hs_ok en on en.hubspot_company_id = nu.hid
   where coalesce(ea.name, ed.name, en.name) is not null
      or (hs.company is not null and pessoas.empresa_nome_de_empresa(hs.company)
          and hs.company !~ '^[\d\s()+-]+$'
          and length(intelligence.texto_chave(hs.company, true)) >= 4
          and intelligence.texto_chave(hs.company) !~ '^(teste|nao tenho|nao|domain|agencia de marketing|empresa|minha empresa)\M'
          and btrim(hs.company) !~* '^(gmail|googlemail|hotmail|outlook|live|msn|yahoo|icloud|uol|bol|terra|ig|globo|aol|protonmail|e-?mail)(\.com)?$'
          and (intelligence.texto_chave(hs.company) ~ '\m(ltda|s a|eireli|grupo|instituto|consultoria|banco|universidade|faculdade|escola|colegio|hospital|clinica|associacao|fundacao|advocacia|advogados|psicologia|tecnologia|servicos|comercio|industria|agencia|educacao|saude|holding|group|inc|corp|company|solucoes|engenharia|seguros|cooperativa|prefeitura|secretaria)\M'
               or intelligence.texto_chave(hs.company, true) in (select k from texto_rep)))
$$;

create or replace function crm.empresa_pessoas_gravar(p_gravar boolean default false)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pessoas', 'crm', 'intelligence'
as $$
declare v_resumo jsonb; v_n int := 0; v_lig int := 0;
begin
  create temp table emp_pes on commit drop as select * from crm.empresa_pessoas();
  select jsonb_build_object('a_preencher', count(*), 'por_fonte', (select jsonb_object_agg(fonte, n) from
           (select fonte, count(*) n from emp_pes group by 1) f)) into v_resumo from emp_pes;
  if p_gravar then
    update pessoas.pessoas p set empresa = e.empresa_final, atualizado_em = now()
      from emp_pes e where e.mind_id = p.id and nullif(btrim(p.empresa), '') is null;
    get diagnostics v_n = row_count;
    update pessoas.pessoas p set empresa_id = r.id
      from emp_pes e
      join lateral (select x.id from pessoas.empresas x
                     where (e.hubspot_company_id is not null and x.hubspot_company_id = e.hubspot_company_id)
                        or (e.hubspot_company_id is null and x.nome_chave = intelligence.texto_chave(e.empresa_final, true))
                     order by (x.hubspot_company_id is not null) desc limit 1) r on true
     where e.mind_id = p.id and p.empresa_id is distinct from r.id;
    get diagnostics v_lig = row_count;
    if v_n > 0 then
      insert into public.mind_admin_audit (action, resource, record_id, record_label, after_data, request_id)
      values ('atualizar', 'pessoas_empresa_hubspot', to_char(now(), 'YYYYMMDDHH24MISS'),
              'Empresa das pessoas pelo HubSpot (associada > domínio > campo company)',
              v_resumo || jsonb_build_object('gravadas', v_n, 'ligadas', v_lig), gen_random_uuid());
    end if;
  end if;
  return v_resumo || jsonb_build_object('gravadas', v_n, 'ligadas_empresa_id', v_lig, 'gravou', p_gravar);
end $$;

-- entra na rodada diária, depois da regra do Summit
do $$
declare def text;
begin
  def := pg_get_functiondef('intelligence.perfil_gravar_pessoas'::regproc);
  if def not like '%empresa_pessoas_gravar%' then
    def := replace(def,
      'v_empresa := coalesce((crm.empresa_participantes_summit_2026_gravar(true)->>''a_mudar'')::int, 0);',
      'v_empresa := coalesce((crm.empresa_participantes_summit_2026_gravar(true)->>''a_mudar'')::int, 0);
    v_empresa := v_empresa + coalesce((crm.empresa_pessoas_gravar(true)->>''gravadas'')::int, 0);');
    if def not like '%empresa_pessoas_gravar%' then raise exception 'trecho de perfil_gravar_pessoas não encontrado'; end if;
    execute def;
  end if;
end $$;
