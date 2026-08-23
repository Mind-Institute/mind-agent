-- Read-only structural fingerprint for Mind Intelligence migration baseline.
-- Intentionally excludes Supabase/system schemas and extension-owned cron/net/pgbouncer objects.
-- This query does not read business row data and does not mutate the database.

with user_schemas as (
  select n.oid, n.nspname
  from pg_namespace n
  where n.nspname not in (
    'pg_catalog','information_schema','pg_toast','auth','storage','extensions',
    'graphql','graphql_public','realtime','supabase_functions','supabase_migrations',
    'vault','pgsodium','pgsodium_masks','cron','net','pgbouncer'
  )
    and n.nspname !~ '^pg_'
),
tables as (
  select n.nspname schema_name,c.relname table_name,c.relrowsecurity rls_enabled
  from pg_class c
  join user_schemas n on n.oid=c.relnamespace
  where c.relkind in ('r','p')
),
columns as (
  select n.nspname schema_name,c.relname table_name,a.attnum pos,a.attname col,
         pg_catalog.format_type(a.atttypid,a.atttypmod) typ,a.attnotnull nn,
         coalesce(pg_get_expr(ad.adbin,ad.adrelid),'') def
  from pg_attribute a
  join pg_class c on c.oid=a.attrelid
  join user_schemas n on n.oid=c.relnamespace
  left join pg_attrdef ad on ad.adrelid=a.attrelid and ad.adnum=a.attnum
  where c.relkind in ('r','p') and a.attnum>0 and not a.attisdropped
),
constraints as (
  select n.nspname schema_name,c.relname table_name,con.conname name,
         pg_get_constraintdef(con.oid,true) def
  from pg_constraint con
  join pg_class c on c.oid=con.conrelid
  join user_schemas n on n.oid=c.relnamespace
),
views as (
  select n.nspname schema_name,c.relname name,pg_get_viewdef(c.oid,true) def
  from pg_class c
  join user_schemas n on n.oid=c.relnamespace
  where c.relkind in ('v','m')
),
funcs as (
  select n.nspname schema_name,p.proname name,
         pg_get_function_identity_arguments(p.oid) args,
         pg_get_function_result(p.oid) result,
         p.prosecdef secdef,
         coalesce(array_to_string(p.proconfig,','),'') cfg
  from pg_proc p
  join user_schemas n on n.oid=p.pronamespace
  where p.prokind in ('f','p')
    and not (n.nspname='public' and p.probin is not null and p.prosrc like '%$libdir/%')
),
triggers as (
  select n.nspname schema_name,c.relname table_name,t.tgname name,
         pg_get_triggerdef(t.oid,true) def
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join user_schemas n on n.oid=c.relnamespace
  where not t.tgisinternal
),
policies as (
  select schemaname schema_name,tablename table_name,policyname name,cmd,
         roles::text roles,coalesce(qual,'') qual,coalesce(with_check,'') chk
  from pg_policies
  where schemaname in (select nspname from user_schemas)
)
select jsonb_build_object(
  'generated_at',now(),
  'schemas',(select jsonb_agg(nspname order by nspname) from user_schemas),
  'counts',jsonb_build_object(
    'tables',(select count(*) from tables),
    'columns',(select count(*) from columns),
    'constraints',(select count(*) from constraints),
    'views',(select count(*) from views),
    'functions',(select count(*) from funcs),
    'triggers',(select count(*) from triggers),
    'policies',(select count(*) from policies)
  ),
  'fingerprints',jsonb_build_object(
    'tables',md5(coalesce((select string_agg(schema_name||'.'||table_name||':'||rls_enabled,E'\n' order by schema_name,table_name) from tables),'')),
    'columns',md5(coalesce((select string_agg(schema_name||'.'||table_name||':'||pos||':'||col||':'||typ||':'||nn||':'||def,E'\n' order by schema_name,table_name,pos) from columns),'')),
    'constraints',md5(coalesce((select string_agg(schema_name||'.'||table_name||':'||name||':'||def,E'\n' order by schema_name,table_name,name) from constraints),'')),
    'views',md5(coalesce((select string_agg(schema_name||'.'||name||':'||def,E'\n' order by schema_name,name) from views),'')),
    'functions',md5(coalesce((select string_agg(schema_name||'.'||name||'('||args||'):'||result||':'||secdef||':'||cfg,E'\n' order by schema_name,name,args) from funcs),'')),
    'triggers',md5(coalesce((select string_agg(schema_name||'.'||table_name||':'||name||':'||def,E'\n' order by schema_name,table_name,name) from triggers),'')),
    'policies',md5(coalesce((select string_agg(schema_name||'.'||table_name||':'||name||':'||cmd||':'||roles||':'||qual||':'||chk,E'\n' order by schema_name,table_name,name) from policies),''))
  ),
  'phase1_current_objects',(
    select jsonb_agg(
      jsonb_build_object('table',schema_name||'.'||table_name,'rls',rls_enabled)
      order by schema_name,table_name
    )
    from tables
    where (schema_name,table_name) in (
      ('crm','pessoas'),('crm','pessoas_interno'),('crm','pessoa_produtos'),
      ('crm','mapa_produtos'),('crm','consents'),
      ('engagement','identidades'),('engagement','identidade_fusoes'),
      ('engagement','pessoa_perfil'),
      ('catalogo','produtos'),('catalogo','produto_componentes')
    )
  )
) snapshot;
