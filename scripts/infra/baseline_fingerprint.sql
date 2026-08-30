-- ============================================================================
-- baseline_fingerprint.sql — FINGERPRINT ESTRUTURAL AMPLIADO (100% READ-ONLY)
-- ----------------------------------------------------------------------------
-- USO
--   1) Rodar em produção AGORA  → guardar o JSON como referência congelada.
--   2) Rodar na fresh preview depois do baseline → comparar classe a classe.
--   Devolve 1 linha / 1 coluna: fingerprint jsonb
--
-- GARANTIAS
--   Somente SELECT sobre catálogos do sistema. Não escreve, não altera,
--   não lê linha de dado de negócio.
--
-- ESCOPO
--   Mesmo filtro canônico de archive/pre-architecture/structural-baseline/
--   reproduce.sql (19 schemas / 117 tabelas na referência medida antes do 12B).
--   Estende as 7 classes do reproduce.sql para 14, cobrindo os pontos cegos:
--   índices, identity/generated, grants, sequences, extensões, comments,
--   default ACLs e relforcerowsecurity.
--
-- EXTENSÕES
--   O md5 estrutural cobre SOMENTE as extensões de aplicação (`pg_trgm`,
--   `vector`) — as únicas com objetos pertencentes ao escopo. Extensões de
--   bootstrap/gerenciadas (`pg_net`, `pg_cron`, `pgcrypto`, `uuid-ossp`,
--   `supabase_vault`, ...) divergem legitimamente entre produção e preview
--   (namespace e presença) e ficam FORA do md5 — aparecem só em
--   `bootstrap_extensions_raw`, para inspeção, nunca como critério de fidelidade.
--
-- DEFAULT ACLs
--   Limitados ao `scope` (em produção: 6, todos em `public`). Não são emitidos
--   pelo baseline — são bootstrap. Comparar prod × preview VERIFICA essa
--   premissa em vez de reproduzi-la por DDL inventado.
--
-- ROLE
--   `mind_agent_raw` traz o role explicitamente (atributos, memberships,
--   comentário) — é a conferência 1-a-1 contra a seção 1 do gerador.
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
extobj as (select d.classid, d.objid from pg_depend d where d.deptype = 'e'),
rel as (
  select c.oid, c.relname, c.relkind, c.relpersistence, c.reloptions,
         c.relrowsecurity, c.relforcerowsecurity, c.relacl, n.nspname
  from pg_class c join scope n on n.oid = c.relnamespace
  where not exists (select 1 from extobj e
                    where e.classid = 'pg_class'::regclass and e.objid = c.oid)
),
tbl as (select * from rel where relkind in ('r','p')),
fn as (
  select p.oid, p.proname, n.nspname, p.proacl, p.prosecdef, p.provolatile,
         p.prokind, p.prosrc, coalesce(array_to_string(p.proconfig, ','), '') as cfg,
         pg_get_function_identity_arguments(p.oid) as idargs,
         pg_get_function_result(p.oid) as res
  from pg_proc p join scope n on n.oid = p.pronamespace
  where p.prokind in ('f','p')
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_proc'::regclass and e.objid = p.oid)
),
f_schemas as (select nspname::text as v from scope),

-- extensões DE APLICAÇÃO: só essas entram no md5
f_ext as (
  select e.extname::text || '|' || n.nspname::text || '|' || e.extversion::text as v
  from pg_extension e join pg_namespace n on n.oid = e.extnamespace
  where e.extname in ('pg_trgm','vector')
),
-- extensões de bootstrap/gerenciadas: FORA do md5, só para inspeção
f_ext_bootstrap as (
  select e.extname::text || '|' || n.nspname::text || '|' || e.extversion::text as v
  from pg_extension e join pg_namespace n on n.oid = e.extnamespace
  where e.extname not in ('pg_trgm','vector')
),
f_tables as (
  select nspname::text || '.' || relname::text || '|' || relrowsecurity::text
         || '|' || relforcerowsecurity::text
         || '|' || relpersistence::text
         || '|' || coalesce(array_to_string(reloptions, ','), '') as v
  from tbl
),
f_tables_by_schema as (
  select nspname::text as s, count(*) as n from tbl group by 1
),
f_columns as (
  select r.nspname::text || '.' || r.relname::text || '|' || a.attnum::text || '|' || a.attname::text
         || '|' || pg_catalog.format_type(a.atttypid, a.atttypmod)
         || '|' || a.attnotnull::text
         || '|' || coalesce(pg_get_expr(ad.adbin, ad.adrelid), '')
         || '|id=' || a.attidentity::text                -- ponto cego #1 do reproduce.sql
         || '|gen=' || a.attgenerated::text              -- ponto cego #2
         || '|coll=' || a.attcollation::text as v
  from rel r
  join pg_attribute a on a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped
  left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
  where r.relkind in ('r','p','v','m')
),
f_constraints as (
  select t.nspname::text || '.' || t.relname::text || '|' || con.conname::text
         || '|' || pg_get_constraintdef(con.oid, true) as v
  from pg_constraint con join tbl t on t.oid = con.conrelid
  where con.contype in ('p','u','c','x','f')
),
f_indexes as (
  select t.nspname::text || '.' || t.relname::text || '|' || ic.relname::text
         || '|' || pg_get_indexdef(i.indexrelid) as v   -- inclui WITH (m=..., ef_construction=...)
  from pg_index i
  join tbl t on t.oid = i.indrelid
  join pg_class ic on ic.oid = i.indexrelid
),
f_sequences as (
  select ps.schemaname::text || '.' || ps.sequencename::text || '|' || ps.data_type::text
         || '|' || ps.start_value::text || '|' || ps.min_value::text || '|' || ps.max_value::text
         || '|' || ps.increment_by::text || '|' || ps.cycle::text || '|' || ps.cache_size::text
         || '|owned=' || coalesce((
              select t.nspname::text || '.' || t.relname::text || '.' || a.attname::text
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
  select nspname::text || '.' || relname::text || '|' || relkind::text
         || '|' || coalesce(array_to_string(reloptions, ','), '')
         || '|' || pg_get_viewdef(oid, true) as v
  from rel where relkind in ('v','m')
),
f_functions as (
  select nspname::text || '.' || proname::text || '(' || idargs || ')|' || res
         || '|' || prokind::text || '|secdef=' || prosecdef::text || '|vol=' || provolatile::text
         || '|cfg=' || cfg || '|body=' || md5(coalesce(prosrc, '')) as v
  from fn
),
f_triggers as (
  select r.nspname::text || '.' || r.relname::text || '|' || tg.tgname::text
         || '|' || pg_get_triggerdef(tg.oid, true) as v
  from pg_trigger tg join rel r on r.oid = tg.tgrelid
  where not tg.tgisinternal
),
f_policies as (
  select t.nspname::text || '.' || t.relname::text || '|' || p.polname::text
         || '|perm=' || p.polpermissive::text || '|cmd=' || p.polcmd::text
         || '|roles=' || coalesce((select string_agg(pg_get_userbyid(u.r)::text, ','
                                                     order by pg_get_userbyid(u.r)::text)
                                   from unnest(p.polroles) as u(r)), 'public')
         || '|using=' || coalesce(pg_get_expr(p.polqual, p.polrelid), '')
         || '|check=' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') as v
  from pg_policy p join tbl t on t.oid = p.polrelid
),
f_grants as (
  select 'schema|' || n.nspname::text || '|'
         || case when a.grantee = 0::oid then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end
         || '|' || a.privilege_type || '|' || a.is_grantable::text as v
  from pg_namespace n join scope s on s.oid = n.oid
  cross join lateral aclexplode(n.nspacl) a
  union all
  select 'rel|' || r.nspname::text || '.' || r.relname::text || '|'
         || case when a.grantee = 0::oid then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end
         || '|' || a.privilege_type || '|' || a.is_grantable::text
  from rel r cross join lateral aclexplode(r.relacl) a
  union all
  select 'fn|' || f.nspname::text || '.' || f.proname::text || '(' || f.idargs || ')|'
         || case when a.grantee = 0::oid then 'PUBLIC' else pg_get_userbyid(a.grantee)::text end
         || '|' || a.privilege_type || '|' || a.is_grantable::text
  from fn f cross join lateral aclexplode(f.proacl) a
),
f_comments as (
  select 'schema|' || s.nspname::text || '|' || obj_description(s.oid, 'pg_namespace') as v
  from scope s where obj_description(s.oid, 'pg_namespace') is not null
  union all
  select 'rel|' || r.nspname::text || '.' || r.relname::text || '|' || obj_description(r.oid, 'pg_class')
  from rel r where obj_description(r.oid, 'pg_class') is not null
  union all
  select 'col|' || r.nspname::text || '.' || r.relname::text || '.' || a.attname::text || '|'
         || col_description(r.oid, a.attnum)
  from rel r join pg_attribute a on a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped
  where col_description(r.oid, a.attnum) is not null
  union all
  select 'fn|' || f.nspname::text || '.' || f.proname::text || '(' || f.idargs || ')|'
         || obj_description(f.oid, 'pg_proc')
  from fn f where obj_description(f.oid, 'pg_proc') is not null
),
-- default ACLs LIMITADOS AO SCOPE (produção: 6, todos em `public`)
f_defacl as (
  select coalesce(pg_get_userbyid(d.defaclrole)::text, '?') || '|'
         || n.nspname::text || '|' || d.defaclobjtype::text
         || '|' || coalesce(d.defaclacl::text, '') as v
  from pg_default_acl d
  join pg_namespace n on n.oid = d.defaclnamespace
  join scope s on s.oid = n.oid
),
-- defaults globais (defaclnamespace = 0): valem para qualquer schema.
-- Fora do md5; em produção devem vir vazios. Se vier algo, é achado.
f_defacl_global as (
  select coalesce(pg_get_userbyid(d.defaclrole)::text, '?') || '|<all>|'
         || d.defaclobjtype::text || '|' || coalesce(d.defaclacl::text, '') as v
  from pg_default_acl d
  where d.defaclnamespace = 0::oid
),
f_roles as (   -- roles que a branch PRECISA ter para o baseline aplicar
  select distinct pg_get_userbyid(u.r)::text as v
  from pg_policy p join tbl t on t.oid = p.polrelid
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
  from pg_namespace n join scope s on s.oid = n.oid
  cross join lateral aclexplode(n.nspacl) a where a.grantee <> 0::oid
),
-- verificação explícita do único role de aplicação criado pelo baseline
f_mind_agent as (
  select r.rolname::text
         || '|login='      || r.rolcanlogin::text
         || '|inherit='    || r.rolinherit::text
         || '|super='      || r.rolsuper::text
         || '|createdb='   || r.rolcreatedb::text
         || '|createrole=' || r.rolcreaterole::text
         || '|repl='       || r.rolreplication::text
         || '|bypassrls='  || r.rolbypassrls::text
         || '|members='    || coalesce((select string_agg(m.rolname::text, ',' order by m.rolname::text)
                                        from pg_auth_members am
                                        join pg_roles m on m.oid = am.member
                                        where am.roleid = r.oid), '')
         || '|comment='    || coalesce((select d.description from pg_shdescription d
                                        where d.objoid = r.oid
                                          and d.classoid = 'pg_authid'::regclass), '') as v
  from pg_roles r where r.rolname = 'mind_agent'
)
select jsonb_build_object(
  'generated_at', now(),
  'server_version', current_setting('server_version'),
  'search_path', current_setting('search_path'),
  'schemas', (select jsonb_agg(v order by v) from f_schemas),
  'counts', jsonb_build_object(
    'schemas',       (select count(*) from f_schemas),
    'app_extensions',(select count(*) from f_ext),
    'tables',        (select count(*) from f_tables),
    'columns',       (select count(*) from f_columns),
    'constraints',   (select count(*) from f_constraints),
    'indexes',       (select count(*) from f_indexes),
    'sequences',     (select count(*) from f_sequences),
    'views',         (select count(*) from f_views),
    'functions',     (select count(*) from f_functions),
    'triggers',      (select count(*) from f_triggers),
    'policies',      (select count(*) from f_policies),
    'grants',        (select count(*) from f_grants),
    'comments',      (select count(*) from f_comments),
    'default_acls',  (select count(*) from f_defacl)
  ),
  'tables_by_schema', (select jsonb_object_agg(s, n) from f_tables_by_schema),
  'fingerprints', jsonb_build_object(
    'schemas',       (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_schemas),
    'app_extensions',(select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_ext),
    'tables',        (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_tables),
    'columns',       (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_columns),
    'constraints',   (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_constraints),
    'indexes',       (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_indexes),
    'sequences',     (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_sequences),
    'views',         (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_views),
    'functions',     (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_functions),
    'triggers',      (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_triggers),
    'policies',      (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_policies),
    'grants',        (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_grants),
    'comments',      (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_comments),
    'default_acls',  (select md5(coalesce(string_agg(v, E'\n' order by v), '')) from f_defacl)
  ),
  'app_extensions_raw',       (select jsonb_agg(v order by v) from f_ext),
  'bootstrap_extensions_raw', (select jsonb_agg(v order by v) from f_ext_bootstrap),
  'default_acls_raw',         (select jsonb_agg(v order by v) from f_defacl),
  'default_acls_global_raw',  (select jsonb_agg(v order by v) from f_defacl_global),
  'required_roles',           (select jsonb_agg(v order by v) from f_roles),
  'mind_agent_raw',           (select jsonb_agg(v order by v) from f_mind_agent)
) as fingerprint;


-- ============================================================================
-- COMO LER O RESULTADO (preview × produção)
--
--   schemas, app_extensions, tables, columns, constraints, indexes, sequences,
--   views, functions, triggers, policies, grants, comments
--       → devem ser IGUAIS. Diferença = infidelidade do gerador (ou o delta
--         explicado pelos objetos do 12B, se rodar depois de 12B.1A/1B).
--
--   default_acls
--       → iguais POR BOOTSTRAP, não por emissão. Se diferir, é achado — e
--         valida ou invalida a decisão de não emitir ALTER DEFAULT PRIVILEGES.
--
--   bootstrap_extensions_raw
--       → NÃO comparar por igualdade. Produção tem pg_cron e pg_net em `public`;
--         a preview nasce com pg_net em `extensions` e sem pg_cron. É esperado.
--         Serve só para inspeção.
--
--   required_roles / mind_agent_raw
--       → todo role de required_roles precisa existir na branch. `mind_agent`
--         é o único de aplicação e é criado pela seção 1 do gerador; confira
--         mind_agent_raw da preview contra o de produção (memberships podem
--         diferir se `authenticator` não existir na branch — isso é por desenho).
-- ============================================================================
