-- ============================================================================
-- baseline_generator.sql — GERADOR DE BASELINE ESTRUTURAL (issue #31)
-- ============================================================================
-- USO
--   Rode em PRODUCAO, no SQL editor / psql, como uma unica query.
--   Retorna 1 linha / 1 coluna: baseline_sql text  (o DDL inteiro como blob).
--   Copie o texto para supabase/migrations/20260829185445_historical_prod_stub.sql
--   SOMENTE depois de conferir o bloco SANIDADE no fim deste arquivo.
--
-- GARANTIAS
--   * Estritamente READ-ONLY: so SELECT sobre catalogo do sistema.
--   * Este script NAO executa DDL. Ele EMITE DDL como texto no resultado.
--   * Nao le dado de negocio. Nao emite nenhuma linha de tabela.
--
-- ESCOPO
--   Filtro canonico de archive/pre-architecture/structural-baseline/reproduce.sql
--   (exclui apenas schemas gerenciados do Supabase). Hoje: 19 schemas / 117 tabelas.
--   Objetos pertencentes a extensao sao excluidos (pg_depend.deptype = 'e');
--   as extensoes em si sao emitidas com CREATE EXTENSION IF NOT EXISTS.
--
-- NAO EMITE (deliberado)
--   * OWNER TO      — o executor da branch ja e o role privilegiado; emitir
--                     OWNER TO supabase_admin quebraria a migration.
--   * ALTER DEFAULT PRIVILEGES — os 6 pg_default_acl de producao sao de
--                     bootstrap do Supabase (schema public, roles postgres/
--                     supabase_admin) e a branch ja nasce com eles. Sao
--                     verificados pelo fingerprint, nao reemitidos.
--   * SUPERUSER em role — nunca. Ver bloco SANIDADE.
--
-- ORDEM DAS SECOES
--   0 header · 1 roles de aplicacao · 2 schemas · 3 extensoes · 4 sequences
--   5 funcoes (bloco 1) · 6 tabelas · 7 OWNED BY · 8 funcoes (bloco 2)
--   9 PK/UNIQUE/CHECK/EXCLUDE · 10 indices · 11 views (topologica) · 12 FKs
--   13 triggers · 14 RLS · 15 policies · 16 REVOKE/GRANT · 17 comments · 99 footer
--
--   Funcoes saem em DOIS blocos de proposito: DEFAULT, GENERATED ... STORED,
--   CHECK e indice-por-expressao podem chamar funcao propria, e
--   check_function_bodies = false NAO protege esse caso (ele desliga o parse do
--   corpo da funcao, nao a resolucao de uma funcao USADA em DDL de tabela).
--   Bloco 1 = funcoes que nao dependem do rowtype de nenhuma relacao do escopo
--   (a esmagadora maioria) e sai ANTES das tabelas. Bloco 2 = so as que usam
--   rowtype de tabela/view na assinatura e por isso precisam vir depois.
--   O probe ja confirmou prosqlbody = 0, entao criar funcao antes da tabela
--   que ela referencia no corpo e seguro.
--
--   A secao 1 (roles) vem antes de policies e GRANTs porque o baseline referencia
--   roles de aplicacao que a fresh preview NAO possui. Medido no PR #30: a preview
--   tem anon, authenticated, pg_database_owner, postgres, service_role — e nao
--   mind_agent. Roles de plataforma nunca sao emitidos (a branch ja os tem).
-- ============================================================================

with recursive
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
extobj as (                        -- tudo que pertence a uma extensao: nunca reemitido
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
seq as (select * from rel where relkind = 'S'),
vw  as (select * from rel where relkind in ('v','m')),
fn as (
  select p.oid, p.proname, n.nspname, p.proacl,
         pg_get_function_identity_arguments(p.oid) as idargs
  from pg_proc p
  join scope n on n.oid = p.pronamespace
  where p.prokind in ('f','p')
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_proc'::regclass and e.objid = p.oid)
),
-- funcoes cuja ASSINATURA depende do rowtype de uma relacao do escopo:
-- essas precisam sair depois das tabelas (bloco 2). Todas as outras saem antes.
fn_after as (
  select distinct d.objid as prooid
  from pg_depend d
  join pg_type ty on ty.oid = d.refobjid
  join pg_class c on c.oid = ty.typrelid
  join scope s on s.oid = c.relnamespace
  where d.classid = 'pg_proc'::regclass
    and d.refclassid = 'pg_type'::regclass
    and c.relkind in ('r','p','v','m')
),
-- ---------------------------------------------------------------------------
-- roles: apenas os roles DE APLICACAO efetivamente referenciados por policies
-- ou GRANTs do escopo. Roles de plataforma sao assumidos presentes na branch.
-- ---------------------------------------------------------------------------
platform_roles(rolname) as (
  values ('postgres'),('anon'),('authenticated'),('service_role'),('authenticator'),
         ('supabase_admin'),('supabase_auth_admin'),('supabase_storage_admin'),
         ('supabase_functions_admin'),('supabase_read_only_user'),
         ('supabase_realtime_admin'),('supabase_replication_admin'),
         ('dashboard_user'),('pgbouncer'),
         ('pgsodium_keyholder'),('pgsodium_keyiduser'),('pgsodium_keymaker')
),
req_role_oid as (
  select distinct u.r as roleoid
  from pg_policy p
  join tbl t on t.oid = p.polrelid
  cross join lateral unnest(p.polroles) as u(r)
  where u.r <> 0::oid
  union
  select distinct a.grantee
  from rel r
  cross join lateral aclexplode(r.relacl) a
  where a.grantee <> 0::oid
  union
  select distinct a.grantee
  from fn f
  cross join lateral aclexplode(f.proacl) a
  where a.grantee <> 0::oid
  union
  select distinct a.grantee
  from pg_namespace n
  join scope s on s.oid = n.oid
  cross join lateral aclexplode(n.nspacl) a
  where a.grantee <> 0::oid
),
app_role as (
  select r.oid, r.rolname::text as rolname,
         r.rolsuper, r.rolinherit, r.rolcanlogin,
         r.rolcreatedb, r.rolcreaterole, r.rolreplication, r.rolbypassrls
  from pg_roles r
  join req_role_oid q on q.roleoid = r.oid
  where r.rolname not in (select rolname from platform_roles)
    and r.rolname !~ '^pg_'
),
app_role_member as (                -- GRANT <app_role> TO <member>, como ja existe hoje
  select ar.rolname::text as role_name, m.rolname::text as member_name
  from app_role ar
  join pg_auth_members am on am.roleid = ar.oid
  join pg_roles m on m.oid = am.member
),
-- ---------------------------------------------------------------------------
ident_seq as (                      -- sequence interna de coluna identity (deptype 'i')
  select d.objid as seqoid, d.refobjid as relid, d.refobjsubid as attnum
  from pg_depend d
  where d.classid = 'pg_class'::regclass and d.refclassid = 'pg_class'::regclass
    and d.deptype = 'i' and d.refobjsubid > 0
),
owned_seq as (                      -- sequence OWNED BY coluna (serial / explicito)
  select d.objid as seqoid, d.refobjid as relid, d.refobjsubid as attnum
  from pg_depend d
  where d.classid = 'pg_class'::regclass and d.refclassid = 'pg_class'::regclass
    and d.deptype = 'a' and d.refobjsubid > 0
),
col as (
  select t.oid as relid, a.attnum,
    format('  %I %s%s%s%s',
      a.attname,
      pg_catalog.format_type(a.atttypid, a.atttypmod),
      case when a.attcollation <> 0::oid and a.attcollation <> ty.typcollation
        then ' COLLATE ' || (select quote_ident(cn.nspname) || '.' || quote_ident(cl.collname)
                             from pg_collation cl
                             join pg_namespace cn on cn.oid = cl.collnamespace
                             where cl.oid = a.attcollation)
        else '' end,
      case
        -- (a) GENERATED ... STORED: a expressao mora em pg_attrdef e NAO e DEFAULT
        when a.attgenerated = 's'
          then ' GENERATED ALWAYS AS (' || pg_get_expr(ad.adbin, ad.adrelid) || ') STORED'
        -- (b) IDENTITY: opcoes lidas da sequence interna; a sequence nao sai separada
        when a.attidentity in ('a','d')
          then coalesce((
                 select format(
                   ' GENERATED %s AS IDENTITY (SEQUENCE NAME %I.%I START WITH %s INCREMENT BY %s MINVALUE %s MAXVALUE %s CACHE %s%s)',
                   case a.attidentity when 'a' then 'ALWAYS' else 'BY DEFAULT' end,
                   ps.schemaname, ps.sequencename,
                   ps.start_value, ps.increment_by, ps.min_value, ps.max_value, ps.cache_size,
                   case when ps.cycle then ' CYCLE' else ' NO CYCLE' end)
                 from ident_seq i
                 join pg_class sc on sc.oid = i.seqoid
                 join pg_namespace sn on sn.oid = sc.relnamespace
                 join pg_sequences ps
                   on ps.schemaname = sn.nspname and ps.sequencename = sc.relname
                 where i.relid = a.attrelid and i.attnum = a.attnum),
               case a.attidentity when 'a' then ' GENERATED ALWAYS AS IDENTITY'
                                  else ' GENERATED BY DEFAULT AS IDENTITY' end)
        when ad.adbin is not null
          then ' DEFAULT ' || pg_get_expr(ad.adbin, ad.adrelid)
        else '' end,
      case when a.attnotnull and a.attidentity = '' then ' NOT NULL' else '' end
    ) as txt
  from tbl t
  join pg_attribute a on a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped
  join pg_type ty on ty.oid = a.atttypid
  left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
),
vedge as (                          -- arestas view -> view
  select distinct r.ev_class as vid, d.refobjid as dep
  from pg_rewrite r
  join pg_depend d on d.classid = 'pg_rewrite'::regclass and d.objid = r.oid
  where d.refclassid = 'pg_class'::regclass
    and d.refobjid <> r.ev_class
    and r.ev_class in (select oid from vw)
    and d.refobjid in (select oid from vw)
),
vpath as (
  select v.oid as vid, v.oid as cur, 0 as depth from vw v
  union all
  select p.vid, e.dep, p.depth + 1
  from vpath p
  join vedge e on e.vid = p.cur
  where p.depth < 24
),
vlvl as (select vid, max(depth) as lvl from vpath group by vid),
frag(sec, k, stmt) as (

  -- 0 ── header ---------------------------------------------------------------
  select 0, ''::text,
    '-- =========================================================================' || E'\n' ||
    '-- BASELINE ESTRUTURAL — extraido do catalogo de producao (schema-only).'      || E'\n' ||
    '-- Sem dados. Sem OWNER. Sem ALTER DEFAULT PRIVILEGES (bootstrap da branch).'  || E'\n' ||
    '-- Em producao esta versao ja consta no ledger e o arquivo e ignorado;'        || E'\n' ||
    '-- numa fresh branch o ledger nasce vazio e este arquivo executa.'             || E'\n' ||
    '-- =========================================================================' || E'\n' ||
    'SET check_function_bodies = false;'                                           || E'\n' ||
    format('SELECT set_config(%L, %L, false);', 'search_path', current_setting('search_path'))

  -- 1a ── roles de aplicacao (idempotente) ------------------------------------
  union all
  select 1, 'a:' || ar.rolname,
    format(
      'DO $mind_role$' || E'\n' ||
      'BEGIN' || E'\n' ||
      '  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = %L) THEN' || E'\n' ||
      '    CREATE ROLE %I %s;' || E'\n' ||
      '  END IF;' || E'\n' ||
      'END' || E'\n' ||
      '$mind_role$;',
      ar.rolname, ar.rolname,
      concat_ws(' ',
        case when ar.rolcanlogin      then 'LOGIN'       else 'NOLOGIN'       end,
        case when ar.rolinherit       then 'INHERIT'     else 'NOINHERIT'     end,
        case when ar.rolcreatedb      then 'CREATEDB'    else 'NOCREATEDB'    end,
        case when ar.rolcreaterole    then 'CREATEROLE'  else 'NOCREATEROLE'  end,
        case when ar.rolreplication   then 'REPLICATION' else 'NOREPLICATION' end,
        case when ar.rolbypassrls     then 'BYPASSRLS'   else 'NOBYPASSRLS'   end))
  from app_role ar

  -- 1b ── memberships ja existentes (o membro pode nao existir na branch) -----
  union all
  select 1, 'b:' || m.role_name || ':' || m.member_name,
    format(
      'DO $mind_role$' || E'\n' ||
      'BEGIN' || E'\n' ||
      '  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = %L) THEN' || E'\n' ||
      '    EXECUTE %L;' || E'\n' ||
      '  END IF;' || E'\n' ||
      'END' || E'\n' ||
      '$mind_role$;',
      m.member_name,
      'GRANT ' || quote_ident(m.role_name) || ' TO ' || quote_ident(m.member_name))
  from app_role_member m

  -- 1c ── comentario do role --------------------------------------------------
  union all
  select 1, 'c:' || ar.rolname,
    format('COMMENT ON ROLE %I IS %L;', ar.rolname,
           shobj_description(ar.oid, 'pg_authid'))
  from app_role ar
  where shobj_description(ar.oid, 'pg_authid') is not null

  -- 2 ── schemas ---------------------------------------------------------------
  union all
  select 2, s.nspname::text, format('CREATE SCHEMA IF NOT EXISTS %I;', s.nspname)
  from scope s

  -- 3 ── extensoes cujo schema esta no escopo (pg_trgm / vector em public) -----
  union all
  select 3, e.extname::text,
         format('CREATE EXTENSION IF NOT EXISTS %I WITH SCHEMA %I;', e.extname, s.nspname)
  from pg_extension e
  join scope s on s.oid = e.extnamespace

  -- 4 ── sequences nao-identity ------------------------------------------------
  union all
  select 4, s.nspname || '.' || s.relname,
    format('CREATE SEQUENCE IF NOT EXISTS %I.%I AS %s START WITH %s INCREMENT BY %s MINVALUE %s MAXVALUE %s CACHE %s%s;',
      s.nspname, s.relname, ps.data_type::text, ps.start_value, ps.increment_by,
      ps.min_value, ps.max_value, ps.cache_size,
      case when ps.cycle then ' CYCLE' else ' NO CYCLE' end)
  from seq s
  join pg_sequences ps on ps.schemaname = s.nspname and ps.sequencename = s.relname
  where not exists (select 1 from ident_seq i where i.seqoid = s.oid)

  -- 5 ── funcoes, bloco 1: antes das tabelas ----------------------------------
  union all
  select 5, f.nspname || '.' || f.proname || '(' || f.idargs || ')',
         pg_get_functiondef(f.oid) || ';'
  from fn f
  where not exists (select 1 from fn_after a where a.prooid = f.oid)

  -- 6 ── tabelas ----------------------------------------------------------------
  union all
  select 6, t.nspname || '.' || t.relname,
    format('CREATE %sTABLE %I.%I (' || E'\n' || '%s' || E'\n' || ')%s;',
      case t.relpersistence when 'u' then 'UNLOGGED ' else '' end,
      t.nspname, t.relname,
      coalesce((select string_agg(c.txt, ',' || E'\n' order by c.attnum)
                from col c where c.relid = t.oid), ''),
      case when t.reloptions is not null
           then ' WITH (' || array_to_string(t.reloptions, ', ') || ')' else '' end)
  from tbl t

  -- 7 ── ALTER SEQUENCE ... OWNED BY -------------------------------------------
  union all
  select 7, s.nspname || '.' || s.relname,
    format('ALTER SEQUENCE %I.%I OWNED BY %I.%I.%I;',
           s.nspname, s.relname, t.nspname, t.relname, a.attname)
  from seq s
  join owned_seq o on o.seqoid = s.oid
  join tbl t on t.oid = o.relid
  join pg_attribute a on a.attrelid = o.relid and a.attnum = o.attnum
  where not exists (select 1 from ident_seq i where i.seqoid = s.oid)

  -- 8 ── funcoes, bloco 2: dependem do rowtype de uma relacao do escopo -------
  union all
  select 8, f.nspname || '.' || f.proname || '(' || f.idargs || ')',
         pg_get_functiondef(f.oid) || ';'
  from fn f
  where exists (select 1 from fn_after a where a.prooid = f.oid)

  -- 9 ── PK / UNIQUE / CHECK / EXCLUDE -----------------------------------------
  union all
  select 9, t.nspname || '.' || t.relname || ':' || con.conname,
    format('ALTER TABLE %I.%I ADD CONSTRAINT %I %s;',
           t.nspname, t.relname, con.conname, pg_get_constraintdef(con.oid, true))
  from pg_constraint con
  join tbl t on t.oid = con.conrelid
  where con.contype in ('p','u','c','x')
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_constraint'::regclass and e.objid = con.oid)

  -- 10 ── indices nao-constraint (pg_get_indexdef ja traz WITH (m=..., ...)) ---
  union all
  select 10, t.nspname || '.' || t.relname || ':' || ic.relname,
         pg_get_indexdef(i.indexrelid) || ';'
  from pg_index i
  join tbl t on t.oid = i.indrelid
  join pg_class ic on ic.oid = i.indexrelid
  where not exists (select 1 from pg_constraint con where con.conindid = i.indexrelid)
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_class'::regclass and e.objid = i.indexrelid)

  -- 11 ── views em ordem topologica --------------------------------------------
  union all
  select 11, lpad(coalesce(l.lvl, 0)::text, 4, '0') || ':' || v.nspname || '.' || v.relname,
    case when v.relkind = 'm'
      then format('CREATE MATERIALIZED VIEW %I.%I%s AS %s',
             v.nspname, v.relname,
             case when v.reloptions is not null
                  then ' WITH (' || array_to_string(v.reloptions, ', ') || ')' else '' end,
             rtrim(rtrim(pg_get_viewdef(v.oid, true)), ';') || ';')
      else format('CREATE OR REPLACE VIEW %I.%I%s AS %s',
             v.nspname, v.relname,
             case when v.reloptions is not null
                  then ' WITH (' || array_to_string(v.reloptions, ', ') || ')' else '' end,
             rtrim(rtrim(pg_get_viewdef(v.oid, true)), ';') || ';')
    end
  from vw v
  left join vlvl l on l.vid = v.oid

  -- 12 ── foreign keys (depois de todas as tabelas) ----------------------------
  union all
  select 12, t.nspname || '.' || t.relname || ':' || con.conname,
    format('ALTER TABLE %I.%I ADD CONSTRAINT %I %s;',
           t.nspname, t.relname, con.conname, pg_get_constraintdef(con.oid, true))
  from pg_constraint con
  join tbl t on t.oid = con.conrelid
  where con.contype = 'f'
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_constraint'::regclass and e.objid = con.oid)

  -- 13 ── triggers ---------------------------------------------------------------
  union all
  select 13, r.nspname || '.' || r.relname || ':' || tg.tgname,
         pg_get_triggerdef(tg.oid, true) || ';'
  from pg_trigger tg
  join rel r on r.oid = tg.tgrelid
  where not tg.tgisinternal
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_trigger'::regclass and e.objid = tg.oid)

  -- 14 ── RLS (ENABLE e FORCE sao flags separadas) -----------------------------
  union all
  select 14, t.nspname || '.' || t.relname || ':1',
         format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY;', t.nspname, t.relname)
  from tbl t where t.relrowsecurity
  union all
  select 14, t.nspname || '.' || t.relname || ':2',
         format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY;', t.nspname, t.relname)
  from tbl t where t.relforcerowsecurity

  -- 15 ── policies ---------------------------------------------------------------
  union all
  select 15, t.nspname || '.' || t.relname || ':' || p.polname,
    format('CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s%s%s;',
      p.polname, t.nspname, t.relname,
      case when p.polpermissive then 'PERMISSIVE' else 'RESTRICTIVE' end,
      case p.polcmd when 'r' then 'SELECT' when 'a' then 'INSERT'
                    when 'w' then 'UPDATE' when 'd' then 'DELETE' else 'ALL' end,
      case when p.polroles is null or 0::oid = any(p.polroles) then 'PUBLIC'
           else (select string_agg(quote_ident(pg_get_userbyid(u.r)::text), ', '
                                   order by pg_get_userbyid(u.r)::text)
                 from unnest(p.polroles) as u(r)) end,
      case when p.polqual is not null
           then ' USING (' || pg_get_expr(p.polqual, p.polrelid) || ')' else '' end,
      case when p.polwithcheck is not null
           then ' WITH CHECK (' || pg_get_expr(p.polwithcheck, p.polrelid) || ')' else '' end)
  from pg_policy p
  join tbl t on t.oid = p.polrelid

  -- 16a ── REVOKE FROM PUBLIC so onde producao realmente revogou ---------------
  union all
  select 16, 'a1:' || n.nspname,
         format('REVOKE ALL ON SCHEMA %I FROM PUBLIC;', n.nspname)
  from pg_namespace n
  join scope s on s.oid = n.oid
  where n.nspacl is not null
    and not exists (select 1 from aclexplode(n.nspacl) a where a.grantee = 0::oid)
  union all
  select 16, 'a2:' || f.nspname || '.' || f.proname || '(' || f.idargs || ')',
         format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC;', f.nspname, f.proname, f.idargs)
  from fn f
  where f.proacl is not null
    and not exists (select 1 from aclexplode(f.proacl) a where a.grantee = 0::oid)

  -- 16b ── GRANTs de schema ------------------------------------------------------
  union all
  select 16, 'b:' || x.nspname || ':' || x.g,
    format('GRANT %s ON SCHEMA %I TO %s%s;',
           x.privs, x.nspname, x.g,
           case when x.is_grantable then ' WITH GRANT OPTION' else '' end)
  from (
    select n.nspname,
           case when a.grantee = 0::oid then 'PUBLIC'
                else quote_ident(pg_get_userbyid(a.grantee)::text) end as g,
           a.is_grantable,
           string_agg(a.privilege_type, ', ' order by a.privilege_type) as privs
    from pg_namespace n
    join scope s on s.oid = n.oid
    cross join lateral aclexplode(n.nspacl) a
    group by 1, 2, 3
  ) x

  -- 16c ── GRANTs de tabela / view / sequence -----------------------------------
  union all
  select 16, 'c:' || x.nspname || '.' || x.relname || ':' || x.g,
    format('GRANT %s ON %s %I.%I TO %s%s;',
           x.privs,
           case when x.relkind = 'S' then 'SEQUENCE' else 'TABLE' end,
           x.nspname, x.relname, x.g,
           case when x.is_grantable then ' WITH GRANT OPTION' else '' end)
  from (
    select r.nspname, r.relname, r.relkind,
           case when a.grantee = 0::oid then 'PUBLIC'
                else quote_ident(pg_get_userbyid(a.grantee)::text) end as g,
           a.is_grantable,
           string_agg(a.privilege_type, ', ' order by a.privilege_type) as privs
    from rel r
    cross join lateral aclexplode(r.relacl) a
    where r.relkind in ('r','p','v','m','S')
    group by 1, 2, 3, 4, 5
  ) x

  -- 16d ── GRANTs de funcao -------------------------------------------------------
  union all
  select 16, 'd:' || x.nspname || '.' || x.proname || '(' || x.idargs || '):' || x.g,
    format('GRANT %s ON FUNCTION %I.%I(%s) TO %s%s;',
           x.privs, x.nspname, x.proname, x.idargs, x.g,
           case when x.is_grantable then ' WITH GRANT OPTION' else '' end)
  from (
    select f.nspname, f.proname, f.idargs,
           case when a.grantee = 0::oid then 'PUBLIC'
                else quote_ident(pg_get_userbyid(a.grantee)::text) end as g,
           a.is_grantable,
           string_agg(a.privilege_type, ', ' order by a.privilege_type) as privs
    from fn f
    cross join lateral aclexplode(f.proacl) a
    group by 1, 2, 3, 4, 5
  ) x

  -- 17 ── comments ----------------------------------------------------------------
  union all
  select 17, 'a:' || s.nspname,
         format('COMMENT ON SCHEMA %I IS %L;', s.nspname, obj_description(s.oid, 'pg_namespace'))
  from scope s where obj_description(s.oid, 'pg_namespace') is not null
  union all
  select 17, 'b:' || r.nspname || '.' || r.relname,
    format('COMMENT ON %s %I.%I IS %L;',
           case when r.relkind = 'v' then 'VIEW'
                when r.relkind = 'm' then 'MATERIALIZED VIEW'
                when r.relkind = 'S' then 'SEQUENCE' else 'TABLE' end,
           r.nspname, r.relname, obj_description(r.oid, 'pg_class'))
  from rel r
  where r.relkind in ('r','p','v','m','S')
    and obj_description(r.oid, 'pg_class') is not null
  union all
  select 17, 'c:' || r.nspname || '.' || r.relname || ':' || lpad(a.attnum::text, 5, '0'),
         format('COMMENT ON COLUMN %I.%I.%I IS %L;',
                r.nspname, r.relname, a.attname, col_description(r.oid, a.attnum))
  from rel r
  join pg_attribute a on a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped
  where r.relkind in ('r','p','v','m')
    and col_description(r.oid, a.attnum) is not null
  union all
  select 17, 'd:' || f.nspname || '.' || f.proname || '(' || f.idargs || ')',
         format('COMMENT ON FUNCTION %I.%I(%s) IS %L;',
                f.nspname, f.proname, f.idargs, obj_description(f.oid, 'pg_proc'))
  from fn f where obj_description(f.oid, 'pg_proc') is not null

  -- 99 ── footer --------------------------------------------------------------------
  union all
  select 99, ''::text, 'RESET search_path;' || E'\n' || '-- fim do baseline estrutural.'
)
select string_agg(stmt, E'\n\n' order by sec, k) as baseline_sql
from frag
where stmt is not null;

-- ============================================================================
-- SANIDADE — rode ANTES de usar o texto. Troque so o SELECT final acima por:
--
--   select sec, count(*) as stmts, sum(length(stmt)) as bytes
--   from frag group by sec order by sec;
--
-- Confira contra o `counts` de scripts/infra/baseline_fingerprint.sql
-- (referencia congelada em producao: 19 schemas, 117 tabelas, 135 funcoes,
--  18 triggers, 21 policies):
--
--   sec 6                  == counts.tables      (117)
--   sec 5 + sec 8          == counts.functions   (135)   <- prova que o filtro
--                                                            de extensao pegou:
--                                                            os 157 objetos de
--                                                            pg_trgm/vector fora
--   sec 13                 == counts.triggers    (18)
--   sec 15                 == counts.policies    (21)
--   sec 2                  == counts.schemas     (19)
--   sec 8                  deve ser 0 ou quase; se vier grande, olhe antes de usar
--   sec 1 'a:'             == 1 statement, e so para mind_agent
--
-- E confirme que nenhum role de aplicacao e superuser (este gerador nunca
-- emite SUPERUSER; se houver algum, e achado a tratar, nao a silenciar):
--
--   select rolname from pg_roles where rolsuper and rolname = 'mind_agent';
-- ============================================================================
