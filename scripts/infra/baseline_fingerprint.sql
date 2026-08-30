-- ============================================================================
-- baseline_fingerprint.sql — FINGERPRINT ESTRUTURAL AMPLIADO (issue #31)
-- ============================================================================
-- USO
--   1) Rode em PRODUCAO e guarde o JSON como referencia congelada.
--   2) Rode na fresh preview depois do baseline e compare classe a classe.
--   Retorna 1 linha / 1 coluna: fingerprint jsonb.
--
-- GARANTIAS
--   Estritamente READ-ONLY: so SELECT sobre catalogo do sistema.
--   Nao le dado de negocio, nao escreve, nao altera nada.
--
-- ESCOPO
--   Mesmo filtro canonico de archive/pre-architecture/structural-baseline/
--   reproduce.sql (exclui apenas schemas gerenciados do Supabase) e mesmo
--   escopo do gerador. Objetos de extensao excluidos (pg_depend.deptype='e').
--
-- POR QUE 14 CLASSES E NAO AS 7 DO reproduce.sql
--   O reproduce.sql nao cobre indices, identity/generated, grants, sequences,
--   extensoes, comments nem relforcerowsecurity — justamente os pontos cegos
--   que um baseline templatado poderia perder em silencio.
--
-- CAMPOS EXTRAS
--   required_roles     — roles que a branch PRECISA ter para o baseline aplicar.
--   app_roles_raw      — subconjunto de required_roles que NAO e role de
--                        plataforma: sao exatamente os que o gerador emite em
--                        CREATE ROLE (hoje: mind_agent). Confira 1 a 1 contra
--                        a secao 1 do baseline_generator.sql.
--   default_acls_raw   — os pg_default_acl DO ESCOPO (producao: 6, todos public).
--                        Nao sao emitidos pelo baseline: sao bootstrap do projeto
--                        e a branch ja nasce com eles. Aqui servem para PROVAR
--                        essa premissa, comparando producao x preview.
--   default_acls_global_raw — pg_default_acl sem namespace (valem para qualquer
--                        schema). Informativo, fora do md5; em producao deve ser
--                        vazio. Se aparecer algo, e achado a tratar.
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
  select d.classid, d.objid
  from pg_depend d
  where d.deptype = 'e'
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
platform_roles(rolname) as (
  values ('postgres'),('anon'),('authenticated'),('service_role'),('authenticator'),
         ('supabase_admin'),('supabase_auth_admin'),('supabase_storage_admin'),
         ('supabase_functions_admin'),('supabase_read_only_user'),
         ('supabase_realtime_admin'),('supabase_replication_admin'),
         ('dashboard_user'),('pgbouncer'),
         ('pgsodium_keyholder'),('pgsodium_keyiduser'),('pgsodium_keymaker')
),
f_schemas as (select nspname as v from scope),
f_ext as (
  select e.extname || '|' || n.nspname || '|' || e.extversion as v
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
),
f_tables as (
  select nspname || '.' || relname
         || '|' || relrowsecurity::text
         || '|' || relforcerowsecurity::text
         || '|' || relpersistence::text
         || '|' || coalesce(array_to_string(reloptions, ','), '') as v
  from tbl
),
f_columns as (
  select r.nspname || '.' || r.relname || '|' || a.attnum::text || '|' || a.attname
         || '|' || pg_catalog.format_type(a.atttypid, a.atttypmod)
         || '|' || a.attnotnull::text
         || '|' || coalesce(pg_get_expr(ad.adbin, ad.adrelid), '')
         || '|id='   || a.attidentity::text      -- ponto cego #1 do reproduce.sql
         || '|gen='  || a.attgenerated::text     -- ponto cego #2
         || '|coll=' || a.attcollation::text as v
  from rel r
  join pg_attribute a on a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped
  left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
  where r.relkind in ('r','p','v','m')
),
f_constraints as (
  select t.nspname || '.' || t.relname || '|' || con.conname
         || '|' || pg_get_constraintdef(con.oid, true) as v
  from pg_constraint con
  join tbl t on t.oid = con.conrelid
  where con.contype in ('p','u','c','x','f')
),
f_indexes as (
  select t.nspname || '.' || t.relname || '|' || ic.relname
         || '|' || pg_get_indexdef(i.indexrelid) as v   -- inclui WITH (m=..., ef_construction=...)
  from pg_index i
  join tbl t on t.oid = i.indrelid
  join pg_class ic on ic.oid = i.indexrelid
),
f_sequences as (
  select ps.schemaname || '.' || ps.sequencename || '|' || ps.data_type::text
         || '|' || ps.start_value::text || '|' || ps.min_value::text
         || '|' || ps.max_value::text   || '|' || ps.increment_by::text
         || '|' || ps.cycle::text       || '|' || ps.cache_size::text
         || '|owned=' || coalesce((
              select t.nspname || '.' || t.relname || '.' || a.attname
              from pg_depend d
              join rel t on t.oid = d.refobjid
              join pg_attribute a on a.attrelid = d.refobjid and a.attnum = d.refobjsubid
              where d.classid = 'pg_class'::regclass and d.objid = r.oid
                and d.deptype in ('a','i') and d.refobjsubid > 0
              limit 1), '') as v
  from rel r
  join pg_sequences ps on ps.schemaname = r.nspname and ps.sequencename = r.relname
  where r.relkind = 'S'
),
f_views as (
  select nspname || '.' || relname || '|' || relkind::text
         || '|' || coalesce(array_to_string(reloptions, ','), '')
         || '|' || pg_get_viewdef(oid, true) as v
  from rel where relkind in ('v','m')
),
f_functions as (
  select nspname || '.' || proname || '(' || idargs || ')|' || res
         || '|' || prokind::text
         || '|secdef=' || prosecdef::text
         || '|vol=' || provolatile::text
         || '|cfg=' || cfg
         || '|body=' || md5(coalesce(prosrc, '')) as v
  from fn
),
f_triggers as (
  select r.nspname || '.' || r.relname || '|' || tg.tgname
         || '|' || pg_get_triggerdef(tg.oid, true) as v
  from pg_trigger tg
  join rel r on r.oid = tg.tgrelid
  where not tg.tgisinternal
),
f_policies as (
  select t.nspname || '.' || t.relname || '|' || p.polname
         || '|perm=' || p.polpermissive::text
         || '|cmd='  || p.polcmd::text
         || '|roles=' || coalesce((select string_agg(pg_get_userbyid(u.r)::text, ','
                                                     order by pg_get_userbyid(u.r)::text)
                                   from unnest(p.polroles) as u(r)), 'public')
         || '|using=' || coalesce(pg_get_expr(p.polqual, p.polrelid), '')
         || '|check=' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') as v
  from pg_policy p
  join tbl t on t.oid = p.polrelid
),
f_grants as (
  select 'schema|' || n.nspname || '|'
         || case when a.grantee = 0::oid then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end
         || '|' || a.privilege_type || '|' || a.is_grantable::text as v
  from pg_namespace n
  join scope s on s.oid = n.oid
  cross join lateral aclexplode(n.nspacl) a
  union all
  select 'rel|' || r.nspname || '.' || r.relname || '|'
         || case when a.grantee = 0::oid then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end
         || '|' || a.privilege_type || '|' || a.is_grantable::text
  from rel r
  cross join lateral aclexplode(r.relacl) a
  union all
  select 'fn|' || f.nspname || '.' || f.proname || '(' || f.idargs || ')|'
         || case when a.grantee = 0::oid then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end
         || '|' || a.privilege_type || '|' || a.is_grantable::text
  from fn f
  cross join lateral aclexplode(f.proacl) a
),
f_comments as (
  select 'schema|' || s.nspname || '|' || obj_description(s.oid, 'pg_namespace') as v
  from scope s where obj_description(s.oid, 'pg_namespace') is not null
  union all
  select 'rel|' || r.nspname || '.' || r.relname || '|' || obj_description(r.oid, 'pg_class')
  from rel r where obj_description(r.oid, 'pg_class') is not null
  union all
  select 'col|' || r.nspname || '.' || r.relname || '.' || a.attname || '|'
         || col_description(r.oid, a.attnum)
  from rel r
  join pg_attribute a on a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped
  where col_description(r.oid, a.attnum) is not null
  union all
  select 'fn|' || f.nspname || '.' || f.proname || '(' || f.idargs || ')|'
         || obj_description(f.oid, 'pg_proc')
  from fn f where obj_description(f.oid, 'pg_proc') is not null
),
-- default ACLs: SO os do escopo de aplicacao. Sem o join com `scope` isto
-- capturava auth/storage/cron/extensions/graphql*/realtime (27 em producao) e
-- comparava defaults de schemas gerenciados, que nao pertencem ao baseline.
f_defacl as (
  select pg_get_userbyid(d.defaclrole)::text || '|'
         || n.nspname || '|' || d.defaclobjtype::text
         || '|' || coalesce(d.defaclacl::text, '') as v
  from pg_default_acl d
  join pg_namespace n on n.oid = d.defaclnamespace
  join scope s on s.oid = n.oid
),
f_defacl_global as (               -- informativo, fora do md5: vale p/ qualquer schema
  select pg_get_userbyid(d.defaclrole)::text || '|<all>|' || d.defaclobjtype::text
         || '|' || coalesce(d.defaclacl::text, '') as v
  from pg_default_acl d
  where d.defaclnamespace = 0::oid
),
f_roles as (   -- roles que a branch PRECISA ter para o baseline aplicar
  select distinct pg_get_userbyid(u.r)::text as v
  from pg_policy p
  join tbl t on t.oid = p.polrelid
  cross join lateral unnest(p.polroles) as u(r)
  where u.r <> 0::oid
  union
  select distinct pg_get_userbyid(a.grantee)::text
  from rel r cross join lateral aclexplode(r.relacl) a where a.grantee <> 0::oid
  union
  select distinct pg_get_userbyid(a.grantee)::text
  from fn f cross join lateral aclexplode(f.proacl) a where a.grantee <> 0::oid
  union
  select distinct pg_get_userbyid(a.grantee)::text
  from pg_namespace n
  join scope s on s.oid = n.oid
  cross join lateral aclexplode(n.nspacl) a
  where a.grantee <> 0::oid
),
f_app_roles as (   -- required_roles menos roles de plataforma = o que o baseline cria
  select r.rolname::text || '|login=' || r.rolcanlogin::text
         || '|inherit=' || r.rolinherit::text
         || '|super='   || r.rolsuper::text
         || '|createdb=' || r.rolcreatedb::text
         || '|createrole=' || r.rolcreaterole::text
         || '|repl=' || r.rolreplication::text
         || '|bypassrls=' || r.rolbypassrls::text
         || '|members=' || coalesce((
              select string_agg(m.rolname::text, ',' order by m.rolname::text)
              from pg_auth_members am
              join pg_roles m on m.oid = am.member
              where am.roleid = r.oid), '') as v
  from pg_roles r
  where r.rolname in (select v from f_roles)
    and r.rolname not in (select rolname from platform_roles)
    and r.rolname !~ '^pg_'
),
f_tables_by_schema as (
  select nspname, count(*) as n from tbl group by nspname
)
select jsonb_build_object(
  'generated_at', now(),
  'server_version', current_setting('server_version'),
  'search_path', current_setting('search_path'),
  'schemas', (select jsonb_agg(v order by v) from f_schemas),
  'tables_by_schema', (select jsonb_object_agg(nspname, n) from f_tables_by_schema),
  'counts', jsonb_build_object(
    'schemas',      (select count(*) from f_schemas),
    'extensions',   (select count(*) from f_ext),
    'tables',       (select count(*) from f_tables),
    'columns',      (select count(*) from f_columns),
    'constraints',  (select count(*) from f_constraints),
    'indexes',      (select count(*) from f_indexes),
    'sequences',    (select count(*) from f_sequences),
    'views',        (select count(*) from f_views),
    'functions',    (select count(*) from f_functions),
    'triggers',     (select count(*) from f_triggers),
    'policies',     (select count(*) from f_policies),
    'grants',       (select count(*) from f_grants),
    'comments',     (select count(*) from f_comments),
    'default_acls', (select count(*) from f_defacl),
    'app_roles',    (select count(*) from f_app_roles)
  ),
  'fingerprints', jsonb_build_object(
    'schemas',      (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_schemas),
    'extensions',   (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_ext),
    'tables',       (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_tables),
    'columns',      (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_columns),
    'constraints',  (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_constraints),
    'indexes',      (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_indexes),
    'sequences',    (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_sequences),
    'views',        (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_views),
    'functions',    (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_functions),
    'triggers',     (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_triggers),
    'policies',     (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_policies),
    'grants',       (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_grants),
    'comments',     (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_comments),
    'default_acls', (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_defacl)
  ),
  'default_acls_raw',        (select jsonb_agg(v order by v) from f_defacl),
  'default_acls_global_raw', (select jsonb_agg(v order by v) from f_defacl_global),
  'required_roles',          (select jsonb_agg(v order by v) from f_roles),
  'app_roles_raw',           (select jsonb_agg(v order by v) from f_app_roles),
  'extensions_raw',          (select jsonb_agg(v order by v) from f_ext)
) as fingerprint;
