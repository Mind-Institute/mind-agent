-- Cargo declarado no credenciamento: relatório consolidado da Yazo e, na falta dele, o espelho vivo
-- da Yazo (attributes.text_102 = cargo, text_67 = empresa). Acrescenta 16 cargos de pessoas do Summit
-- 2026 que não estavam no relatório (24/09/2026). O mind_id sai já na pessoa sobrevivente de fusão.
-- É a fonte 1 da prioridade da Adriana (REGRA_ICP_POR_CARGO.md) para pessoas.pessoas e para o HubSpot.

create or replace view credenciamento_summit_2026.v_cargo_declarado as
select distinct on (s.mind_id) s.mind_id, s.cargo, s.empresa, s.fonte
  from (
    select coalesce(q.fundida_em, r.mind_id) as mind_id,
           nullif(btrim(r."Cargo / Profissão"), '') as cargo, nullif(btrim(r."Empresa"), '') as empresa,
           'relatorio_yazo' as fonte, 1 as prio
      from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r
      join pessoas.pessoas q on q.id = r.mind_id
    union all
    select coalesce(q.fundida_em, y.mind_id),
           nullif(btrim(y.attributes->>'text_102'), ''), nullif(btrim(y.attributes->>'text_67'), ''),
           'espelho_yazo', 2
      from credenciamento_summit_2026.yazo_espelho y
      join pessoas.pessoas q on q.id = y.mind_id
     where y.sumiu_em is null and jsonb_typeof(y.attributes) = 'object'
  ) s
 where s.cargo is not null or s.empresa is not null
 order by s.mind_id, (s.cargo is not null) desc, s.prio;

comment on view credenciamento_summit_2026.v_cargo_declarado is
  'Cargo e empresa que a pessoa escreveu no credenciamento do Summit 2026: relatório consolidado da Yazo; na falta, o espelho vivo (text_102/text_67). Uma linha por pessoa sobrevivente.';
revoke all on credenciamento_summit_2026.v_cargo_declarado from public, anon, authenticated;
grant select on credenciamento_summit_2026.v_cargo_declarado to service_role;

-- as duas funções passam a ler a view no lugar do relatório
do $migra$
declare
  alvo text;
  d text; o text;
  antigo_gravar text := $x$    with yazo as (
      select r.mind_id, max(nullif(btrim(r."Cargo / Profissão"), '')) as cargo, max(nullif(btrim(r."Empresa"), '')) as empresa
        from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r where r.mind_id is not null group by r.mind_id),$x$;
  novo_gravar text := $x$    with yazo as (
      select v.mind_id, v.cargo, v.empresa from credenciamento_summit_2026.v_cargo_declarado v),$x$;
  antigo_plano text := $x$  with yazo as (
    select r.mind_id, max(nullif(btrim(r."Cargo / Profissão"), '')) as cargo, max(nullif(btrim(r."Empresa"), '')) as empresa
      from credenciamento_summit_2026."Relatorio Yazzo Consolidado" r where r.mind_id is not null group by r.mind_id),$x$;
  novo_plano text := $x$  with yazo as (
    select v.mind_id, v.cargo, v.empresa from credenciamento_summit_2026.v_cargo_declarado v),$x$;
begin
  d := pg_get_functiondef('intelligence.perfil_gravar_pessoas(boolean)'::regprocedure); o := d;
  d := replace(d, antigo_gravar, novo_gravar);
  if d = o then raise exception 'perfil_gravar_pessoas: trecho do relatório não encontrado'; end if;
  execute d;

  d := pg_get_functiondef('public.mind_hubspot_perfil_plano(timestamptz)'::regprocedure); o := d;
  d := replace(d, antigo_plano, novo_plano);
  if d = o then raise exception 'mind_hubspot_perfil_plano: trecho do relatório não encontrado'; end if;
  execute d;
end $migra$;
