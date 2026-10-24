-- pessoas.empresas: o registro de empresas do Mind (pedido e aprovação da Adriana, 24/09/2026 — D2:
-- "pessoas.empresas deve ser nosso registro de empresas surgindo primeiro como um espelho de crm.empresas
-- mas depois novas empresas e enriquecimento devem ser preenchidos aqui e gravados no HubSpot").
--
-- Nasce do espelho do HubSpot (crm.empresa_espelho) e recebe o que o HubSpot não tem: empresas
-- declaradas no credenciamento, domínio de e-mail e enriquecimento (Lusha). O que nasce ou muda aqui
-- fica com hubspot_pendente = true até o write-back gravar no HubSpot (write-back tem gate próprio).
-- pessoas.pessoas.empresa_id liga a pessoa à empresa; pessoas.pessoas.empresa (texto) continua.

create table if not exists pessoas.empresas (
  id                       uuid primary key default gen_random_uuid(),
  nome                     text not null,
  nome_chave               text generated always as (intelligence.texto_chave(nome, true)) stored,
  dominio                  text,
  hubspot_company_id       text unique,
  setor                    text,
  setor_bruto              text,
  funcionarios             integer,
  porte                    text generated always as (
                             case when funcionarios is null then null
                                  when funcionarios <= 100 then 'até 100'
                                  when funcionarios <= 500 then '101–500'
                                  when funcionarios <= 1000 then '501–1.000'
                                  when funcionarios <= 5000 then '1.001–5.000'
                                  when funcionarios <= 10000 then '5.001–10.000'
                                  else '+10.000' end) stored,
  cidade                   text,
  uf                       text,
  pais                     text,
  origem                   text not null check (origem in ('hubspot', 'credenciamento', 'dominio', 'lusha')),
  lusha_id                 text,
  enriquecido_por          text,
  enriquecido_em           timestamptz,
  hubspot_pendente         boolean not null default false,
  hubspot_sincronizado_em  timestamptz,
  criado_em                timestamptz not null default now(),
  atualizado_em            timestamptz not null default now()
);
comment on table pessoas.empresas is
  'Registro de empresas do Mind. Nasce do espelho do HubSpot; recebe empresas novas (credenciamento, domínio) e enriquecimento (Lusha). hubspot_pendente = falta gravar no HubSpot.';
create index if not exists empresas_nome_chave_idx on pessoas.empresas (nome_chave);
create index if not exists empresas_dominio_idx on pessoas.empresas (lower(dominio));

alter table pessoas.pessoas add column if not exists empresa_id uuid references pessoas.empresas(id) on delete set null;
comment on column pessoas.pessoas.empresa_id is 'Empresa da pessoa em pessoas.empresas (o texto em empresa continua para exibição).';
create index if not exists pessoas_empresa_id_idx on pessoas.pessoas (empresa_id);

-- 1. espelho do HubSpot → registro (não pisa em enriquecimento já feito aqui)
create or replace function pessoas.empresas_sincronizar_espelho()
 returns jsonb language plpgsql security definer
 set search_path to 'pg_catalog', 'public', 'pessoas', 'crm', 'intelligence'
as $$
declare v_n int;
begin
  insert into pessoas.empresas (nome, dominio, hubspot_company_id, setor, setor_bruto, funcionarios, cidade, uf, pais, origem, hubspot_sincronizado_em)
  select btrim(regexp_replace(replace(replace(e.name, '&amp;', '&'), '&#39;', ''''), '\s*\[[^]]*\]\([^)]*\)', '', 'g')),
         nullif(regexp_replace(lower(btrim(e.domain)), '^www\.', ''), ''),
         e.hubspot_company_id, intelligence.setor_macro(e.industry, null), e.industry,
         e.numberofemployees::int, e.city, e.state, e.country, 'hubspot', e.sincronizado_em
    from crm.empresa_espelho e where nullif(btrim(e.name), '') is not null
  on conflict (hubspot_company_id) do update set
    nome = excluded.nome,
    dominio = coalesce(excluded.dominio, empresas.dominio),
    setor = coalesce(excluded.setor, empresas.setor),
    setor_bruto = coalesce(excluded.setor_bruto, empresas.setor_bruto),
    funcionarios = coalesce(excluded.funcionarios, empresas.funcionarios),
    cidade = coalesce(excluded.cidade, empresas.cidade), uf = coalesce(excluded.uf, empresas.uf), pais = coalesce(excluded.pais, empresas.pais),
    hubspot_sincronizado_em = excluded.hubspot_sincronizado_em,
    atualizado_em = now()
  where (empresas.nome, empresas.dominio, empresas.setor, empresas.funcionarios, empresas.cidade)
        is distinct from (excluded.nome, coalesce(excluded.dominio, empresas.dominio), coalesce(excluded.setor, empresas.setor),
                          coalesce(excluded.funcionarios, empresas.funcionarios), coalesce(excluded.cidade, empresas.cidade));
  get diagnostics v_n = row_count;
  return jsonb_build_object('espelho_gravadas', v_n);
end $$;

-- 2. empresas dos participantes que o HubSpot não tem + enriquecimento da Lusha + ligação pessoa → empresa
create or replace function pessoas.empresas_registrar_summit_2026()
 returns jsonb language plpgsql security definer
 set search_path to 'pg_catalog', 'public', 'pessoas', 'crm', 'intelligence'
as $$
declare v_novas int; v_enr int; v_lig int;
begin
  create temp table emp_part on commit drop as
    select t.mind_id, t.hubspot_company_id, t.empresa_final, lower(split_part(t.email, '@', 2)) dom,
           coalesce(t.hubspot_company_id, 'k:' || intelligence.texto_chave(t.empresa_final, true)) emp_id
      from crm.empresa_participantes_summit_2026() t
     where t.empresa_final is not null
       and coalesce(intelligence.texto_chave(t.empresa_final), '') !~ '^(autonom|independente|particular|consultorio|freela|liberal|aposentad|nenhum|estudante|desempregad)';

  -- empresas novas (fora do HubSpot): uma por chave de nome
  insert into pessoas.empresas (nome, dominio, origem, hubspot_pendente)
  select x.nome, x.dom, case when x.dom is not null then 'dominio' else 'credenciamento' end, true
    from (select intelligence.texto_chave(p.empresa_final, true) k,
                 mode() within group (order by p.empresa_final) nome,
                 mode() within group (order by p.dom) filter (where p.dom !~ '^(gmail|googlemail|hotmail|outlook|live|msn|yahoo|ymail|icloud|me|mac|uol|bol|terra|ig|globo|aol|protonmail|email|mail)\.' and p.dom <> '') dom
            from emp_part p where p.hubspot_company_id is null group by 1) x
   where x.k is not null
     and not exists (select 1 from pessoas.empresas e where e.nome_chave = x.k);
  get diagnostics v_novas = row_count;

  -- enriquecimento Lusha: preenche o que falta (não pisa no que veio do HubSpot)
  update pessoas.empresas e set
         funcionarios = coalesce(e.funcionarios, l.funcionarios_usado),
         setor = coalesce(e.setor, intelligence.setor_macro(null, l.setor)),
         setor_bruto = coalesce(e.setor_bruto, l.setor),
         cidade = coalesce(e.cidade, l.cidade), uf = coalesce(e.uf, l.uf), pais = coalesce(e.pais, l.pais),
         dominio = coalesce(e.dominio, nullif(regexp_replace(lower(l.lusha_dominio), '^(https?://)?(www\.)?', ''), '')),
         lusha_id = l.lusha_id, enriquecido_por = 'lusha', enriquecido_em = coalesce(l.consultado_em, now()),
         hubspot_pendente = true, atualizado_em = now()
    from crm.v_empresa_lusha_aceita l
   where (l.emp_id = e.hubspot_company_id or l.emp_id = 'k:' || e.nome_chave)
     and e.lusha_id is distinct from l.lusha_id
     and ((e.funcionarios is null and l.funcionarios_usado is not null) or (e.setor is null and l.setor is not null));
  get diagnostics v_enr = row_count;

  -- pessoa → empresa
  update pessoas.pessoas p set empresa_id = e.id, atualizado_em = now()
    from emp_part t
    join pessoas.empresas e on (t.hubspot_company_id is not null and e.hubspot_company_id = t.hubspot_company_id)
                            or (t.hubspot_company_id is null and e.hubspot_company_id is null and e.nome_chave = intelligence.texto_chave(t.empresa_final, true))
   where p.id = t.mind_id and p.empresa_id is distinct from e.id;
  get diagnostics v_lig = row_count;

  return jsonb_build_object('empresas_novas', v_novas, 'enriquecidas_lusha', v_enr, 'pessoas_ligadas', v_lig);
end $$;

revoke all on function pessoas.empresas_sincronizar_espelho() from public, anon, authenticated;
revoke all on function pessoas.empresas_registrar_summit_2026() from public, anon, authenticated;

-- o registro acompanha o espelho: roda 10 min depois de cada sincronização de companies
select cron.schedule('pessoas-empresas-espelho', '42 */6 * * *', $$select pessoas.empresas_sincronizar_espelho();$$)
 where not exists (select 1 from cron.job where jobname = 'pessoas-empresas-espelho');
