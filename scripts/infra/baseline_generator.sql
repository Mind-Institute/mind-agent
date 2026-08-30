-- ============================================================================
-- baseline_generator.sql — GERADOR DE BASELINE ESTRUTURAL (100% READ-ONLY)
-- ----------------------------------------------------------------------------
-- USO
--   Executar em produção (ymnmotgglsrxmjmonwjz). Devolve 1 linha / 1 coluna:
--       baseline_sql text
--   O texto é o DDL estrutural completo do escopo de aplicação, montado
--   server-side e na ordem correta. Copiar o blob inteiro — não transcrever
--   objeto a objeto.
--
-- GARANTIAS
--   - Somente SELECT sobre catálogos do sistema. Não escreve, não altera.
--   - O script NÃO executa DDL: o DDL existe apenas como TEXTO no resultado.
--   - Não lê nenhuma linha de dado de negócio.
--
-- ESCOPO (decisão fechada na issue #31)
--   Filtro canônico de archive/pre-architecture/structural-baseline/reproduce.sql:
--   exclui apenas schemas gerenciados do Supabase. Hoje resolve para 19 schemas
--   / 117 tabelas. Objetos pertencentes a extensões são excluídos (deptype='e').
--
-- ROLES
--   `mind_agent` é o único role de aplicação criado pelo baseline. Emitido
--   explicitamente e de forma idempotente, com as memberships funcionais já
--   existentes (`postgres` e, se existir na branch, `authenticator`).
--   Roles de plataforma (postgres/anon/authenticated/service_role/authenticator/
--   supabase_*) já nascem no bootstrap da branch e não são criados aqui.
--
-- EXTENSÕES
--   Somente `pg_trgm` e `vector` — as únicas com objetos pertencentes ao escopo
--   de aplicação (probe do catálogo). Extensões de bootstrap/gerenciadas
--   (`pg_net`, `pg_cron`, `pgcrypto`, `uuid-ossp`, `supabase_vault`, ...) são
--   pré-requisito da branch, divergem de namespace entre produção e preview e
--   NÃO pertencem ao baseline.
--
-- NÃO EMITE
--   OWNER TO (o executor da branch já é o role privilegiado);
--   ALTER DEFAULT PRIVILEGES (bootstrap da branch — ver baseline_fingerprint.sql);
--   nenhum dado.
--
-- Ver bloco SANIDADE no fim deste arquivo para conferir o resultado antes de usar.
-- ============================================================================

with recursive
scope as (                          -- filtro canônico do reproduce.sql
  select n.oid, n.nspname
  from pg_namespace n
  where n.nspname not in (
    'pg_catalog','information_schema','pg_toast','auth','storage','extensions',
    'graphql','graphql_public','realtime','supabase_functions','supabase_migrations',
    'vault','pgsodium','pgsodium_masks','cron','net','pgbouncer'
  )
  and n.nspname !~ '^pg_'
),
extobj as (                         -- tudo que pertence a uma extensão: nunca reemitido
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
fn_rowtype as (                     -- funções cuja ASSINATURA usa rowtype de relação do escopo
  select distinct d.objid as prooid -- (essas precisam sair DEPOIS das tabelas)
  from pg_depend d
  join pg_type t on t.oid = d.refobjid
  join pg_class c on c.oid = t.typrelid
  join scope n on n.oid = c.relnamespace
  where d.classid = 'pg_proc'::regclass
    and d.refclassid = 'pg_type'::regclass
    and t.typrelid <> 0
    and c.relkind in ('r','p','v','m')
),
ident_seq as (                      -- sequence interna de coluna identity (deptype 'i')
  select d.objid as seqoid, d.refobjid as relid, d.refobjsubid as attnum
  from pg_depend d
  where d.classid = 'pg_class'::regclass and d.refclassid = 'pg_class'::regclass
    and d.deptype = 'i' and d.refobjsubid > 0
),
owned_seq as (                      -- sequence OWNED BY coluna (serial / explícito)
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
        -- (a) coluna GENERATED ... STORED: expressão vive em pg_attrdef, NÃO é DEFAULT
        when a.attgenerated::text = 's'
          then ' GENERATED ALWAYS AS (' || pg_get_expr(ad.adbin, ad.adrelid) || ') STORED'
        -- (b) coluna IDENTITY: opções lidas da sequence interna; sequence não sai à parte
        when a.attidentity::text in ('a','d')
          then coalesce((
                 select format(
                   ' GENERATED %s AS IDENTITY (SEQUENCE NAME %I.%I START WITH %s INCREMENT BY %s MINVALUE %s MAXVALUE %s CACHE %s%s)',
                   case a.attidentity::text when 'a' then 'ALWAYS' else 'BY DEFAULT' end,
                   ps.schemaname, ps.sequencename,
                   ps.start_value, ps.increment_by, ps.min_value, ps.max_value, ps.cache_size,
                   case when ps.cycle then ' CYCLE' else ' NO CYCLE' end)
                 from ident_seq i
                 join pg_class sc on sc.oid = i.seqoid
                 join pg_namespace sn on sn.oid = sc.relnamespace
                 join pg_sequences ps
                   on ps.schemaname = sn.nspname and ps.sequencename = sc.relname
                 where i.relid = a.attrelid and i.attnum = a.attnum),
               case a.attidentity::text when 'a' then ' GENERATED ALWAYS AS IDENTITY'
                                        else ' GENERATED BY DEFAULT AS IDENTITY' end)
        when ad.adbin is not null
          then ' DEFAULT ' || pg_get_expr(ad.adbin, ad.adrelid)
        else '' end,
      case when a.attnotnull and a.attidentity::text = '' then ' NOT NULL' else '' end
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
  from vpath p join vedge e on e.vid = p.cur
  where p.depth < 24
),
vlvl as (select vid, max(depth) as lvl from vpath group by vid),
frag(sec, k, stmt) as (

  -- 0 ── cabeçalho ------------------------------------------------------------
  select 0, ''::text,
    '-- =========================================================================' || E'\n' ||
    '-- BASELINE ESTRUTURAL — extraído do catálogo de produção (schema-only).'      || E'\n' ||
    '-- Sem dados. Sem OWNER. Sem ALTER DEFAULT PRIVILEGES (bootstrap da branch).'  || E'\n' ||
    '-- Extensões de bootstrap não são recriadas: só pg_trgm e vector.'             || E'\n' ||
    '-- Em produção esta versão já consta no ledger e o arquivo é ignorado.'        || E'\n' ||
    '-- =========================================================================' || E'\n' ||
    'SET check_function_bodies = false;'                                           || E'\n' ||
    format('SELECT set_config(%L, %L, false);', 'search_path', current_setting('search_path'))

  -- 1 ── role de aplicação: mind_agent (explícito, idempotente) ---------------
  --      Precisa existir ANTES de policies (15) e GRANTs (16).
  union all
  select 1, 'a:mind_agent',
    'DO $mind_role$'                                                                     || E'\n' ||
    'BEGIN'                                                                              || E'\n' ||
    '  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ''mind_agent'') THEN'        || E'\n' ||
    '    CREATE ROLE mind_agent NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE'      || E'\n' ||
    '                           NOREPLICATION NOBYPASSRLS;'                               || E'\n' ||
    '  END IF;'                                                                          || E'\n' ||
    'END'                                                                                || E'\n' ||
    '$mind_role$;'
  where exists (select 1 from pg_roles where rolname = 'mind_agent')

  union all
  select 1, 'b:mind_agent_members',
    'DO $mind_role$'                                                                     || E'\n' ||
    'BEGIN'                                                                              || E'\n' ||
    '  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ''postgres'') THEN'              || E'\n' ||
    '    EXECUTE ''GRANT mind_agent TO postgres'';'                                       || E'\n' ||
    '  END IF;'                                                                          || E'\n' ||
    '  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = ''authenticator'') THEN'         || E'\n' ||
    '    EXECUTE ''GRANT mind_agent TO authenticator'';'                                  || E'\n' ||
    '  END IF;'                                                                          || E'\n' ||
    'END'                                                                                || E'\n' ||
    '$mind_role$;'
  where exists (select 1 from pg_roles where rolname = 'mind_agent')

  union all                          -- comentário do role, só se já existir em produção
  select 1, 'c:mind_agent_comment',
         format('COMMENT ON ROLE mind_agent IS %L;', d.description)
  from pg_shdescription d
  join pg_roles r on r.oid = d.objoid
  where d.classoid = 'pg_authid'::regclass
    and r.rolname = 'mind_agent'

  -- 2 ── schemas --------------------------------------------------------------
  union all
  select 2, s.nspname, format('CREATE SCHEMA IF NOT EXISTS %I;', s.nspname)
  from scope s

  -- 3 ── extensões de aplicação (SOMENTE pg_trgm e vector) --------------------
  --      pg_net / pg_cron / pgcrypto / uuid-ossp / supabase_vault são bootstrap
  --      da branch, divergem de namespace entre prod e preview, e ficam de fora.
  union all
  select 3, e.extname,
         format('CREATE EXTENSION IF NOT EXISTS %I WITH SCHEMA %I;', e.extname, n.nspname)
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname in ('pg_trgm','vector')

  -- 4 ── sequences não-identity ----------------------------------------------
  union all
  select 4, s.nspname || '.' || s.relname,
    format('CREATE SEQUENCE %I.%I AS %s START WITH %s INCREMENT BY %s MINVALUE %s MAXVALUE %s CACHE %s%s;',
      s.nspname, s.relname, ps.data_type, ps.start_value, ps.increment_by,
      ps.min_value, ps.max_value, ps.cache_size,
      case when ps.cycle then ' CYCLE' else ' NO CYCLE' end)
  from seq s
  join pg_sequences ps on ps.schemaname = s.nspname and ps.sequencename = s.relname
  where not exists (select 1 from ident_seq i where i.seqoid = s.oid)

  -- 5 ── funções (bloco 1) — antes das tabelas --------------------------------
  --      check_function_bodies=false não protege função USADA em DDL de tabela:
  --      DEFAULT, GENERATED ... STORED, CHECK e índice-por-expressão resolvem a
  --      função na hora. Por isso tudo que não depende de rowtype sai aqui.
  union all
  select 5, f.nspname || '.' || f.proname || '(' || f.idargs || ')',
         pg_get_functiondef(f.oid) || ';'
  from fn f
  where not exists (select 1 from fn_rowtype fr where fr.prooid = f.oid)

  -- 6 ── tabelas --------------------------------------------------------------
  union all
  select 6, t.nspname || '.' || t.relname,
    format('CREATE %sTABLE %I.%I (' || E'\n' || '%s' || E'\n' || ')%s;',
      case t.relpersistence::text when 'u' then 'UNLOGGED ' else '' end,
      t.nspname, t.relname,
      coalesce((select string_agg(c.txt, ',' || E'\n' order by c.attnum)
                from col c where c.relid = t.oid), ''),
      case when t.reloptions is not null
           then ' WITH (' || array_to_string(t.reloptions, ', ') || ')' else '' end)
  from tbl t

  -- 7 ── ALTER SEQUENCE ... OWNED BY -----------------------------------------
  union all
  select 7, s.nspname || '.' || s.relname,
    format('ALTER SEQUENCE %I.%I OWNED BY %I.%I.%I;',
           s.nspname, s.relname, t.nspname, t.relname, a.attname)
  from seq s
  join owned_seq o on o.seqoid = s.oid
  join tbl t on t.oid = o.relid
  join pg_attribute a on a.attrelid = o.relid and a.attnum = o.attnum
  where not exists (select 1 from ident_seq i where i.seqoid = s.oid)

  -- 8 ── funções (bloco 2) — depois das tabelas -------------------------------
  --      só as que usam rowtype de tabela/view na assinatura.
  union all
  select 8, f.nspname || '.' || f.proname || '(' || f.idargs || ')',
         pg_get_functiondef(f.oid) || ';'
  from fn f
  where exists (select 1 from fn_rowtype fr where fr.prooid = f.oid)

  -- 9 ── PK / UNIQUE / CHECK / EXCLUDE ---------------------------------------
  union all
  select 9, t.nspname || '.' || t.relname || ':' || con.conname,
    format('ALTER TABLE %I.%I ADD CONSTRAINT %I %s;',
           t.nspname, t.relname, con.conname, pg_get_constraintdef(con.oid, true))
  from pg_constraint con
  join tbl t on t.oid = con.conrelid
  where con.contype in ('p','u','c','x')
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_constraint'::regclass and e.objid = con.oid)

  -- 10 ── índices não-constraint (traz WITH (m=..., ef_construction=...)) -----
  union all
  select 10, t.nspname || '.' || t.relname || ':' || ic.relname,
         pg_get_indexdef(i.indexrelid) || ';'
  from pg_index i
  join tbl t on t.oid = i.indrelid
  join pg_class ic on ic.oid = i.indexrelid
  where not exists (select 1 from pg_constraint con where con.conindid = i.indexrelid)
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_class'::regclass and e.objid = i.indexrelid)

  -- 11 ── views em ordem topológica ------------------------------------------
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

  -- 12 ── foreign keys (depois de todas as tabelas) --------------------------
  union all
  select 12, t.nspname || '.' || t.relname || ':' || con.conname,
    format('ALTER TABLE %I.%I ADD CONSTRAINT %I %s;',
           t.nspname, t.relname, con.conname, pg_get_constraintdef(con.oid, true))
  from pg_constraint con
  join tbl t on t.oid = con.conrelid
  where con.contype = 'f'
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_constraint'::regclass and e.objid = con.oid)

  -- 13 ── triggers ------------------------------------------------------------
  union all
  select 13, r.nspname || '.' || r.relname || ':' || tg.tgname,
         pg_get_triggerdef(tg.oid, true) || ';'
  from pg_trigger tg
  join rel r on r.oid = tg.tgrelid
  where not tg.tgisinternal
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_trigger'::regclass and e.objid = tg.oid)

  -- 14 ── RLS (ENABLE e FORCE são flags separadas) ---------------------------
  union all
  select 14, t.nspname || '.' || t.relname || ':1',
         format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY;', t.nspname, t.relname)
  from tbl t where t.relrowsecurity
  union all
  select 14, t.nspname || '.' || t.relname || ':2',
         format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY;', t.nspname, t.relname)
  from tbl t where t.relforcerowsecurity

  -- 15 ── policies ------------------------------------------------------------
  union all
  select 15, t.nspname || '.' || t.relname || ':' || p.polname,
    format('CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s%s%s;',
      p.polname, t.nspname, t.relname,
      case when p.polpermissive then 'PERMISSIVE' else 'RESTRICTIVE' end,
      case p.polcmd::text when 'r' then 'SELECT' when 'a' then 'INSERT'
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

  -- 16a ── REVOKE FROM PUBLIC só onde produção realmente revogou -------------
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

  -- 16a3 ── normalização de anon/authenticated, restrita a `public` ----------
  -- POR QUE EXISTE
  --   O bootstrap da branch traz ALTER DEFAULT PRIVILEGES que concedem a
  --   anon/authenticated no momento do CREATE. Num banco reconstruído do zero
  --   isso dá a esses papéis privilégio que produção não tem. GRANT não
  --   expressa ausência, e "revogar só quando o papel está ausente do ACL" não
  --   basta: o papel pode existir em produção com privilégio PARCIAL e ainda
  --   ganhar privilégio extra do default. Então zeramos os dois papéis e
  --   deixamos 16b/16c/16d reaplicarem o ACL real — inclusive os EXECUTE
  --   legítimos. `service_role` e PUBLIC não são tocados aqui.
  --
  -- POR QUE SÓ `public`
  --   Os default ACLs do Supabase são escopados no schema `public`
  --   (defaclnamespace = public, papéis postgres e supabase_admin, para
  --   r/f/S). Nenhum outro schema recebe concessão automática — medido: numa
  --   preview criada do zero o excesso de anon/authenticated apareceu
  --   exclusivamente em `public`.
  --   REVOKE tem efeito colateral: materializa o ACL de um objeto cujo acl é
  --   NULL (privilégio default). Produção tem 48 objetos com ACL NULL fora de
  --   `public`; revogar neles criaria 279 linhas de ACL de dono que produção
  --   não tem — divergência de catálogo sem nenhuma diferença de privilégio.
  --   Dentro de `public` nenhum objeto tem ACL NULL, então aqui o REVOKE não
  --   materializa nada.
  union all
  select 16, 'a3:' || n.nspname,
         format('REVOKE ALL ON SCHEMA %I FROM anon, authenticated;', n.nspname)
  from pg_namespace n
  join scope s on s.oid = n.oid
  where n.nspname = 'public'
  union all
  select 16, 'a4:' || r.nspname || '.' || r.relname,
         format('REVOKE ALL ON %s %I.%I FROM anon, authenticated;',
                case when r.relkind = 'S' then 'SEQUENCE' else 'TABLE' end,
                r.nspname, r.relname)
  from rel r
  where r.relkind in ('r','p','v','m','S')
    and r.nspname = 'public'
  union all
  select 16, 'a5:' || f.nspname || '.' || f.proname || '(' || f.idargs || ')',
         format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM anon, authenticated;',
                f.nspname, f.proname, f.idargs)
  from fn f
  where f.nspname = 'public'

  -- 16b ── GRANTs de schema ---------------------------------------------------
  union all
  select 16, 'b:' || x.nspname || ':' || x.g,
    format('GRANT %s ON SCHEMA %I TO %s%s;',
           x.privs, x.nspname, x.g, case when x.is_grantable then ' WITH GRANT OPTION' else '' end)
  from (
    select n.nspname,
           case when a.grantee = 0::oid then 'PUBLIC'
                else quote_ident(pg_get_userbyid(a.grantee)::text) end as g,
           a.is_grantable,
           string_agg(a.privilege_type, ', ' order by a.privilege_type) as privs
    from pg_namespace n
    join scope s on s.oid = n.oid
    cross join lateral aclexplode(n.nspacl) a
    group by 1,2,3
  ) x

  -- 16c ── GRANTs de tabela / view / sequence --------------------------------
  union all
  select 16, 'c:' || x.nspname || '.' || x.relname || ':' || x.g,
    format('GRANT %s ON %s %I.%I TO %s%s;',
           x.privs, case when x.relkind = 'S' then 'SEQUENCE' else 'TABLE' end,
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
    group by 1,2,3,4,5
  ) x

  -- 16d ── GRANTs de função ---------------------------------------------------
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
    group by 1,2,3,4,5
  ) x

  -- 17 ── comments ------------------------------------------------------------
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

  -- índices: o comentário mora na row de pg_class do índice (mesma fonte que o
  -- fingerprint lê no ramo 'rel|'), logo COMMENT ON INDEX é round-trip exato.
  union all
  select 17, 'e:' || r.nspname || '.' || r.relname,
         format('COMMENT ON INDEX %I.%I IS %L;',
                r.nspname, r.relname, obj_description(r.oid, 'pg_class'))
  from rel r
  where r.relkind in ('i','I')
    and obj_description(r.oid, 'pg_class') is not null

  -- 99 ── rodapé --------------------------------------------------------------
  union all
  select 99, ''::text, 'RESET search_path;' || E'\n' || '-- fim do baseline estrutural.'
)
select string_agg(stmt, E'\n\n' order by sec, k) as baseline_sql
from frag
where stmt is not null;


-- ============================================================================
-- SANIDADE — rodar ANTES de usar o texto. Troque só o SELECT final acima por:
--
--   select sec, count(*) as stmts, sum(length(stmt)) as bytes
--   from frag group by sec order by sec;
--
-- Confira contra `counts` de scripts/infra/baseline_fingerprint.sql (mesma
-- régua; nada de estimativa):
--
--   sec  1  → 2 ou 3 statements, SÓ mind_agent (create, memberships, comment)
--   sec  2  == counts.schemas          (referência medida: 19)
--   sec  3  == 2                        (pg_trgm e vector; nada mais)
--   sec  5 + sec 8 == counts.functions  (referência medida: 135)
--                     ^ prova que o filtro de extensão pegou
--   sec  6  == counts.tables           (referência medida: 117)
--   sec  8  deve ser 0 ou quase        (só funções com rowtype na assinatura;
--                                       se vier grande, olhe antes de usar)
--   sec 10  == counts.indexes menos os índices de constraint
--   sec 13  == counts.triggers         (referência medida: 18)
--   sec 15  == counts.policies         (referência medida: 21)
--   sec 16  inclui 16a3/a4/a5 — normalização de anon/authenticated em `public`:
--             1 schema + relations(r,p,v,m,S) de public + funcoes de public
--             (referência medida: 1 + 5 + 104 = 110 REVOKE)
--             Conferir só esse delta:  select count(*) from frag
--                                      where sec = 16 and k ~ '^a[345]:';  -- 110
--             Todos precisam sair ANTES do primeiro GRANT (16b).
--   sec 17  == counts.comments         (referência medida: 197)
--             schema + relation/view/sequence + coluna + funcao + INDEX.
--             Antes do fix eram 192: faltavam os 5 COMMENT ON INDEX.
--             Conferir só o delta:  select count(*) from frag
--                                   where sec = 17 and k like 'e:%';  -- esperado 5
--
-- Se sec 3 trouxer pg_net, pg_cron ou qualquer outra extensão, o filtro
-- quebrou: extensão de bootstrap não pertence ao baseline.
-- ============================================================================
