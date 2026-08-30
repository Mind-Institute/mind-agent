-- ============================================================================
-- FINGERPRINT ESTRUTURAL AMPLIADO — 100% READ-ONLY
-- ----------------------------------------------------------------------------
-- USO
--   Rodar em PRODUCAO  -> congela a referencia estrutural (guardar o JSON).
--   Rodar na PREVIEW   -> apos aplicar o baseline, comparar classe a classe.
--
-- Retorna 1 linha / 1 coluna `fingerprint jsonb`.
-- Somente SELECT sobre catalogo do sistema. Nao escreve, nao altera,
-- nao le dado de negocio.
--
-- ESCOPO
--   Mesmo filtro canonico de archive/pre-architecture/structural-baseline/
--   reproduce.sql: exclui apenas schemas gerenciados do Supabase.
--   Referencia medida em producao antes do 12B: 19 schemas / 117 tabelas.
--   Objetos pertencentes a extensoes (pg_depend.deptype='e') ficam de fora.
--
-- EXTENSOES
--   Somente `pg_trgm` e `vector` sao extensoes da APLICACAO (sao as unicas
--   com objetos no escopo). Elas entram no md5 como `app_extensions`.
--   Extensoes de bootstrap/gerenciadas (pg_net, pg_cron, pgcrypto, ...) saem
--   apenas em `bootstrap_extensions_raw`, FORA do md5: producao e fresh
--   preview divergem legitimamente (pg_net nasce em `extensions` na preview
--   e aparece em `public` em producao; pg_cron nao existe na preview).
--   Namespace de extensao de bootstrap NAO e criterio de fidelidade.
--
-- DEFAULT PRIVILEGES (pg_default_acl)
--   DIAGNOSTICO DE BOOTSTRAP, NAO REQUISITO DE IGUALDADE ESTRUTURAL.
--   Medido em 2026-08-30: producao e fresh preview tem 6 rows cada, mas NAO
--   sao iguais — em `postgres|public` a fresh preview tambem da defaults a
--   anon/authenticated para functions/tables, e producao nao. Divergencia de
--   bootstrap e ESPERADA e nao invalida o baseline: o baseline emite ACL por
--   objeto a partir de producao, entao os objetos existentes sao reproduzidos
--   com o ACL real deles, independente do default do ambiente.
--   Por isso `default_acls` NAO entra em `fingerprints`/md5 — fica so como
--   `default_acls_raw` / `default_acls_global_raw` informativos.
--   Consequencia para o futuro: migration nova que dependa de privilegio deve
--   normalizar ACL EXPLICITAMENTE (REVOKE/GRANT no proprio arquivo), como o
--   12B.1B ja faz nas cinco funcoes publicas. Este script nao emite, e o
--   baseline nao deve emitir, ALTER DEFAULT PRIVILEGES.
-- ============================================================================
with
scope as (
  select n.oid, n.nspname
  from pg_namespace n
  where n.nspname not in (
    'pg_catalog','information_schema','pg_toast','auth','storage','extensions',
    'graphql','graphql_public','realtime','supabase_functions','supabase_migrations',
    'vault','pgsodium','pgsodium_masks','cron','net','pgbouncer'
  )
  and n.nspname !~ '^pg_'
),
extobj as (
  select d.classid, d.objid from pg_depend d where d.deptype = 'e'
),
rel as (
  select c.oid, c.relname, c.relkind, c.relpersistence, c.reloptions,
         c.relrowsecurity, c.relforcerowsecurity, c.relacl, n.nspname
  from pg_class c
  join scope n on n.oid = c.relnamespace
  where not exists (select 1 from extobj e
                    where e.classid = 'pg_class'::regclass and e.objid = c.oid)
),
tbl as (select * from rel where relkind in ('r','p')),
fn as (
  select p.oid, p.proname, n.nspname, p.proacl, p.prosecdef, p.provolatile,
         p.prokind, p.prosrc, coalesce(array_to_string(p.proconfig, ','), '') as cfg,
         pg_get_function_identity_arguments(p.oid) as idargs,
         pg_get_function_result(p.oid) as res
  from pg_proc p
  join scope n on n.oid = p.pronamespace
  where p.prokind in ('f','p')
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_proc'::regclass and e.objid = p.oid)
),

-- ── classes que entram no md5 ───────────────────────────────────────────────
f_schemas as (
  select s.nspname::text as v from scope s
),
f_ext_app as (                       -- SO extensoes da aplicacao
  select e.extname::text || '|' || n.nspname::text || '|' || e.extversion::text as v
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname in ('pg_trgm','vector')
),
f_tables as (
  select nspname::text || '.' || relname::text
         || '|rls=' || relrowsecurity::text
         || '|force=' || relforcerowsecurity::text
         || '|persist=' || relpersistence::text
         || '|opts=' || coalesce(array_to_string(reloptions, ','), '') as v
  from tbl
),
f_columns as (
  -- POSICAO = ordinal RELATIVO (row_number sobre attnum), nao o attnum absoluto.
  -- attnum absoluto nao sobrevive a um rebuild: coluna dropada deixa buraco
  -- permanente em producao e nenhum CREATE TABLE reproduz buraco. O ordinal
  -- relativo mantem a deteccao do que importa — mudanca real na ORDEM das
  -- colunas continua divergindo o fingerprint.
  select r.nspname::text || '.' || r.relname::text || '|'
         || row_number() over (partition by r.oid order by a.attnum)::text
         || '|' || a.attname::text
         || '|' || pg_catalog.format_type(a.atttypid, a.atttypmod)
         || '|notnull=' || a.attnotnull::text
         || '|default=' || coalesce(pg_get_expr(ad.adbin, ad.adrelid), '')
         || '|id=' || a.attidentity::text          -- ponto cego do reproduce.sql
         || '|gen=' || a.attgenerated::text        -- idem
         || '|coll=' || a.attcollation::text as v
  from rel r
  join pg_attribute a on a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped
  left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
  where r.relkind in ('r','p','v','m')
),
f_constraints as (
  select t.nspname::text || '.' || t.relname::text || '|' || con.conname::text
         || '|' || pg_get_constraintdef(con.oid, true) as v
  from pg_constraint con
  join tbl t on t.oid = con.conrelid
  where con.contype in ('p','u','c','x','f')
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_constraint'::regclass and e.objid = con.oid)
),
f_indexes as (
  select t.nspname::text || '.' || t.relname::text || '|' || ic.relname::text
         || '|' || pg_get_indexdef(i.indexrelid) as v   -- inclui WITH (m=..., ef_construction=...)
  from pg_index i
  join tbl t on t.oid = i.indrelid
  join pg_class ic on ic.oid = i.indexrelid
),
f_sequences as (
  select ps.schemaname::text || '.' || ps.sequencename::text
         || '|' || ps.data_type::text
         || '|' || ps.start_value::text || '|' || ps.min_value::text
         || '|' || ps.max_value::text || '|' || ps.increment_by::text
         || '|cycle=' || ps.cycle::text || '|cache=' || ps.cache_size::text
         || '|owned=' || coalesce((
              select o.nspname::text || '.' || o.relname::text || '.' || a.attname::text
              from pg_depend d
              join rel o on o.oid = d.refobjid
              join pg_attribute a on a.attrelid = d.refobjid and a.attnum = d.refobjsubid
              where d.classid = 'pg_class'::regclass and d.objid = r.oid
                and d.deptype in ('a','i') and d.refobjsubid > 0
              limit 1), '') as v
  from rel r
  join pg_sequences ps on ps.schemaname = r.nspname and ps.sequencename = r.relname
  where r.relkind = 'S'
),
f_views as (
  select nspname::text || '.' || relname::text || '|' || relkind::text
         || '|opts=' || coalesce(array_to_string(reloptions, ','), '')
         || '|' || pg_get_viewdef(oid, true) as v
  from rel where relkind in ('v','m')
),
f_functions as (
  select nspname::text || '.' || proname::text || '(' || idargs || ')|' || res
         || '|kind=' || prokind::text
         || '|secdef=' || prosecdef::text
         || '|vol=' || provolatile::text
         || '|cfg=' || cfg
         || '|body=' || md5(coalesce(prosrc, '')) as v
  from fn
),
f_triggers as (
  select r.nspname::text || '.' || r.relname::text || '|' || tg.tgname::text
         || '|' || pg_get_triggerdef(tg.oid, true) as v
  from pg_trigger tg
  join rel r on r.oid = tg.tgrelid
  where not tg.tgisinternal
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_trigger'::regclass and e.objid = tg.oid)
),
f_policies as (
  select t.nspname::text || '.' || t.relname::text || '|' || p.polname::text
         || '|perm=' || p.polpermissive::text
         || '|cmd=' || p.polcmd::text
         || '|roles=' || coalesce((
              select string_agg(pg_get_userbyid(u.r)::text, ',' order by pg_get_userbyid(u.r)::text)
              from unnest(p.polroles) as u(r)), 'public')
         || '|using=' || coalesce(pg_get_expr(p.polqual, p.polrelid), '')
         || '|check=' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') as v
  from pg_policy p
  join tbl t on t.oid = p.polrelid
),
f_grants as (
  select 'schema|' || n.nspname::text || '|'
         || case when a.grantee = 0::oid then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end
         || '|' || a.privilege_type::text || '|' || a.is_grantable::text as v
  from pg_namespace n
  join scope s on s.oid = n.oid
  cross join lateral aclexplode(n.nspacl) a
  union all
  select 'rel|' || r.nspname::text || '.' || r.relname::text || '|'
         || case when a.grantee = 0::oid then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end
         || '|' || a.privilege_type::text || '|' || a.is_grantable::text
  from rel r
  cross join lateral aclexplode(r.relacl) a
  union all
  select 'fn|' || f.nspname::text || '.' || f.proname::text || '(' || f.idargs || ')|'
         || case when a.grantee = 0::oid then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end
         || '|' || a.privilege_type::text || '|' || a.is_grantable::text
  from fn f
  cross join lateral aclexplode(f.proacl) a
),
f_comments as (
  select 'schema|' || s.nspname::text || '|' || obj_description(s.oid, 'pg_namespace') as v
  from scope s where obj_description(s.oid, 'pg_namespace') is not null
  union all
  select 'rel|' || r.nspname::text || '.' || r.relname::text || '|'
         || obj_description(r.oid, 'pg_class')
  from rel r where obj_description(r.oid, 'pg_class') is not null
  union all
  select 'col|' || r.nspname::text || '.' || r.relname::text || '.' || a.attname::text || '|'
         || col_description(r.oid, a.attnum)
  from rel r
  join pg_attribute a on a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped
  where col_description(r.oid, a.attnum) is not null
  union all
  select 'fn|' || f.nspname::text || '.' || f.proname::text || '(' || f.idargs || ')|'
         || obj_description(f.oid, 'pg_proc')
  from fn f where obj_description(f.oid, 'pg_proc') is not null
),

-- ── classes informativas, FORA do md5 ──────────────────────────────────────
f_ext_bootstrap as (                 -- gerenciadas/bootstrap: divergem por desenho
  select e.extname::text || '|' || n.nspname::text || '|' || e.extversion::text as v
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname not in ('pg_trgm','vector')
),
f_defacl as (                        -- diagnostico; escopo de aplicacao (producao: 6, em public)
  select coalesce(pg_get_userbyid(d.defaclrole)::text, '?') || '|'
         || n.nspname::text || '|' || d.defaclobjtype::text
         || '|' || coalesce(d.defaclacl::text, '') as v
  from pg_default_acl d
  join pg_namespace n on n.oid = d.defaclnamespace
  join scope s on s.oid = n.oid
),
f_defacl_global as (                 -- defaults sem schema (valem para qualquer schema)
  select coalesce(pg_get_userbyid(d.defaclrole)::text, '?') || '|<all>|'
         || d.defaclobjtype::text || '|' || coalesce(d.defaclacl::text, '') as v
  from pg_default_acl d
  where d.defaclnamespace = 0::oid
),
f_roles as (                         -- roles que policies/GRANTs do escopo referenciam
  select distinct pg_get_userbyid(u.r)::text as v
  from pg_policy p
  join tbl t on t.oid = p.polrelid
  cross join lateral unnest(p.polroles) as u(r)
  where u.r <> 0::oid
  union
  select distinct pg_get_userbyid(a.grantee)::text
  from rel r cross join lateral aclexplode(r.relacl) a
  where a.grantee <> 0::oid
  union
  select distinct pg_get_userbyid(a.grantee)::text
  from fn f cross join lateral aclexplode(f.proacl) a
  where a.grantee <> 0::oid
  union
  select distinct pg_get_userbyid(a.grantee)::text
  from pg_namespace n
  join scope s on s.oid = n.oid
  cross join lateral aclexplode(n.nspacl) a
  where a.grantee <> 0::oid
),
f_mind_agent_members as (
  -- membership FUNCIONAL: agregada por NOME, DISTINCT.
  -- Producao tem duas rows para `postgres` (grantors postgres/supabase_admin,
  -- admin_option false/true). Grantor e admin_option sao detalhe de plataforma
  -- e NAO devem ser reproduzidos pelo baseline — por isso so o nome importa.
  select distinct pg_get_userbyid(m.member)::text as v
  from pg_auth_members m
  join pg_roles r on r.oid = m.roleid
  where r.rolname = 'mind_agent'
),
f_mind_agent as (
  select jsonb_build_object(
    'exists',         true,
    'rolname',        r.rolname::text,
    'rolcanlogin',    r.rolcanlogin,
    'rolinherit',     r.rolinherit,
    'rolsuper',       r.rolsuper,
    'rolcreatedb',    r.rolcreatedb,
    'rolcreaterole',  r.rolcreaterole,
    'rolreplication', r.rolreplication,
    'rolbypassrls',   r.rolbypassrls,
    'members',        (select string_agg(m.v, ',' order by m.v) from f_mind_agent_members m),
    'comment',        shobj_description(r.oid, 'pg_authid')
  ) as v
  from pg_roles r
  where r.rolname = 'mind_agent'
),
f_tables_by_schema as (
  select jsonb_object_agg(x.nspname, x.n) as v
  from (select nspname::text as nspname, count(*)::int as n from tbl group by 1) x
)

select jsonb_build_object(
  'generated_at',   now(),
  'server_version', current_setting('server_version'),
  'search_path',    current_setting('search_path'),
  'schemas',        (select jsonb_agg(v order by v) from f_schemas),
  'tables_by_schema', (select v from f_tables_by_schema),
  'counts', jsonb_build_object(
    'schemas',        (select count(*) from f_schemas),
    'app_extensions', (select count(*) from f_ext_app),
    'tables',         (select count(*) from f_tables),
    'columns',        (select count(*) from f_columns),
    'constraints',    (select count(*) from f_constraints),
    'indexes',        (select count(*) from f_indexes),
    'sequences',      (select count(*) from f_sequences),
    'views',          (select count(*) from f_views),
    'functions',      (select count(*) from f_functions),
    'triggers',       (select count(*) from f_triggers),
    'policies',       (select count(*) from f_policies),
    'grants',         (select count(*) from f_grants),
    'comments',       (select count(*) from f_comments),
    -- diagnostico de bootstrap; divergencia entre producao e preview e esperada
    'default_acls',   (select count(*) from f_defacl)
  ),
  -- md5 por classe: TUDO aqui e requisito de igualdade estrutural.
  -- `default_acls` NAO esta aqui de proposito (ver cabecalho).
  'fingerprints', jsonb_build_object(
    'schemas',        (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_schemas),
    'app_extensions', (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_ext_app),
    'tables',         (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_tables),
    'columns',        (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_columns),
    'constraints',    (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_constraints),
    'indexes',        (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_indexes),
    'sequences',      (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_sequences),
    'views',          (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_views),
    'functions',      (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_functions),
    'triggers',       (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_triggers),
    'policies',       (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_policies),
    'grants',         (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_grants),
    'comments',       (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_comments)
  ),
  -- informativos (fora do md5)
  'app_extensions_raw',       (select jsonb_agg(v order by v) from f_ext_app),
  'bootstrap_extensions_raw', (select jsonb_agg(v order by v) from f_ext_bootstrap),
  'default_acls_raw',         (select jsonb_agg(v order by v) from f_defacl),
  'default_acls_global_raw',  (select jsonb_agg(v order by v) from f_defacl_global),
  'required_roles',           (select jsonb_agg(v order by v) from f_roles),
  'mind_agent_raw',           coalesce((select v from f_mind_agent),
                                       jsonb_build_object('exists', false))
) as fingerprint;

-- ============================================================================
-- COMO LER O RESULTADO (producao x preview pos-baseline)
-- ----------------------------------------------------------------------------
--   fingerprints.*           -> devem ser IGUAIS. Diferenca = infidelidade do
--                               baseline, exceto o delta explicado pelos
--                               objetos do 12B se a preview ja aplicou 12B.1A/1B.
--   counts.tables            -> 117 na referencia pre-12B; counts.schemas -> 19.
--   app_extensions_raw       -> pg_trgm e vector nos dois lados.
--   bootstrap_extensions_raw -> DIVERGENCIA ESPERADA. Preview tem pg_net em
--                               `extensions` e nao tem pg_cron; producao tem
--                               pg_net em `public` e tem pg_cron. Nao e achado.
--   default_acls_raw         -> DIAGNOSTICO. Divergencia de bootstrap e
--                               ESPERADA (preview da defaults a anon/
--                               authenticated em postgres|public; producao
--                               nao). Nao invalida o baseline e NAO deve virar
--                               ALTER DEFAULT PRIVILEGES. Migration nova que
--                               dependa de privilegio normaliza ACL
--                               explicitamente no proprio arquivo.
--   default_acls_global_raw  -> esperado vazio; se vier algo, e achado.
--   mind_agent_raw           -> confere 1-a-1 contra a secao de roles do
--                               baseline_generator.sql. Em producao:
--                               rolcanlogin=false, rolinherit=true, demais
--                               atributos false, members = authenticator,postgres.
--   required_roles           -> todos precisam existir na branch. Fora de
--                               anon/authenticated/service_role/postgres/
--                               authenticator/supabase_*/dashboard_user, so
--                               `mind_agent` — e ele e criado pelo baseline.
-- ============================================================================
