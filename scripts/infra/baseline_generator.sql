-- ============================================================================
-- baseline_generator.sql — GERADOR DE BASELINE ESTRUTURAL (100% READ-ONLY)
-- ============================================================================
-- O que é:
--   Monta SERVER-SIDE, como um único texto, o DDL estrutural (schema-only) do
--   escopo canônico de produção. Devolve 1 linha / 1 coluna: `baseline_sql`.
--   O texto sai como blob opaco — ninguém retranscreve objeto a objeto.
--
-- Como usar:
--   1. Rodar `scripts/infra/baseline_fingerprint.sql` em produção primeiro
--      (valida o prelúdio de CTEs, que é o mesmo, e congela a referência).
--   2. Rodar este arquivo em produção e copiar o valor de `baseline_sql`.
--   3. Conferir as contagens por seção (bloco SANIDADE no fim do arquivo)
--      contra `counts` do fingerprint — mesma régua, sem aritmética no meio.
--   4. Só então materializar o texto no último stub já aplicado
--      (`supabase/migrations/20260829185445_historical_prod_stub.sql`),
--      recriar a preview do zero e rodar o fingerprint na preview.
--
-- Segurança: apenas SELECT sobre catálogos do sistema. NÃO executa DDL —
-- todo DDL existe somente como TEXTO no resultado. Não lê dado de negócio,
-- não escreve, não altera nada.
--
-- Escopo (decisão fechada na issue #31):
--   - filtro canônico do `archive/pre-architecture/structural-baseline/reproduce.sql`:
--     exclui SOMENTE schemas gerenciados do Supabase (hoje resolve para 19
--     schemas / 117 tabelas). `mind`, `concierge`, `treble`, `eduzz`,
--     `credenciamento_summit_2026`, `dash`, `eventos` e `institute` PERMANECEM.
--   - objetos pertencentes a extensões (pg_trgm/vector) são excluídos via
--     pg_depend.deptype = 'e'; as extensões entram como CREATE EXTENSION.
--
-- Decisões embutidas:
--   - NÃO emite OWNER TO       -> evita `OWNER TO supabase_admin` irrecusável
--                                 na branch. Consequência declarada: funções
--                                 SECURITY DEFINER rodam na preview com
--                                 privilégio >= produção, nunca menor.
--   - NÃO emite ALTER DEFAULT PRIVILEGES -> os 6 pg_default_acl são bootstrap
--                                 do projeto Supabase (roles postgres/
--                                 supabase_admin) e a branch já nasce com eles.
--                                 Emitir abortaria a migration. O fingerprint
--                                 verifica essa premissa em vez de inventá-la.
--   - identity: emitida inline (a sequence interna NÃO é emitida à parte).
--   - generated stored: emitida como GENERATED ... STORED, nunca como DEFAULT.
--   - reloptions de índice: já vêm dentro de pg_get_indexdef().
--   - REVOKE FROM PUBLIC: só onde produção realmente revogou.
--   - GRANT: só quando o ACL existe. acl NULL = "default do dono"; emitir
--            GRANT explícito nesse caso divergiria de produção.
--
-- Ordem das funções (correção de ordenação, ver seções 4 e 7):
--   Funções saem em DOIS blocos. O bloco 4 vem ANTES das tabelas porque
--   DEFAULT de coluna, expressão de coluna GENERATED, CHECK e índice por
--   expressão podem chamar função própria — emitir função só depois quebraria.
--   O bloco 7 vem DEPOIS das tabelas e contém apenas as funções cuja
--   ASSINATURA depende do rowtype de uma tabela/view do escopo (pg_depend
--   pg_proc -> pg_type -> pg_class). `SET check_function_bodies = false` no
--   topo garante que corpo de função referenciando objeto ainda inexistente
--   não é parseado (probe confirmou prosqlbody = 0, então não há BEGIN ATOMIC).
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
extobj as (                       -- tudo que pertence a uma extensão: nunca reemitido
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
fn_rowtype_dep as (               -- assinatura usa o rowtype de uma relação do escopo
  select distinct d.objid as prooid
  from pg_depend d
  join pg_type ty on ty.oid = d.refobjid
  join pg_class rc on rc.oid = ty.typrelid
  join scope sn on sn.oid = rc.relnamespace
  where d.classid = 'pg_proc'::regclass
    and d.refclassid = 'pg_type'::regclass
    and rc.relkind in ('r','p','v','m')
),
ident_seq as (                    -- sequence interna de coluna identity (deptype 'i')
  select d.objid as seqoid, d.refobjid as relid, d.refobjsubid as attnum
  from pg_depend d
  where d.classid = 'pg_class'::regclass and d.refclassid = 'pg_class'::regclass
    and d.deptype = 'i' and d.refobjsubid > 0
),
owned_seq as (                    -- sequence OWNED BY coluna (serial / explícito)
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
      case when a.attcollation <> 0 and a.attcollation <> ty.typcollation
        then ' COLLATE ' || (select quote_ident(cn.nspname) || '.' || quote_ident(cl.collname)
                             from pg_collation cl
                             join pg_namespace cn on cn.oid = cl.collnamespace
                             where cl.oid = a.attcollation)
        else '' end,
      case
        -- (a) GENERATED ... STORED: expressão vive em pg_attrdef, NÃO é DEFAULT
        when a.attgenerated = 's'
          then ' GENERATED ALWAYS AS (' || pg_get_expr(ad.adbin, ad.adrelid) || ') STORED'
        -- (b) IDENTITY: opções lidas da sequence interna; sequence não sai à parte
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
vedge as (                        -- arestas view -> view
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

  -- 0 ── cabeçalho ------------------------------------------------------------
  select 0, ''::text,
    '-- =========================================================================' || E'\n' ||
    '-- BASELINE ESTRUTURAL — extraído do catálogo de produção (schema-only).'      || E'\n' ||
    '-- Gerado por scripts/infra/baseline_generator.sql.'                           || E'\n' ||
    '-- Sem dados. Sem OWNER. Sem ALTER DEFAULT PRIVILEGES (bootstrap da branch).'  || E'\n' ||
    '-- Em produção esta versão já consta no ledger e o arquivo é ignorado.'        || E'\n' ||
    '-- =========================================================================' || E'\n' ||
    'SET check_function_bodies = false;'                                           || E'\n' ||
    format('SELECT set_config(%L, %L, false);', 'search_path', current_setting('search_path'))

  -- 1 ── schemas --------------------------------------------------------------
  union all
  select 1, s.nspname, format('CREATE SCHEMA IF NOT EXISTS %I;', s.nspname)
  from scope s

  -- 2 ── extensões instaladas dentro do escopo (pg_trgm / vector em public) ---
  union all
  select 2, e.extname,
         format('CREATE EXTENSION IF NOT EXISTS %I WITH SCHEMA %I;', e.extname, s.nspname)
  from pg_extension e
  join scope s on s.oid = e.extnamespace

  -- 3 ── sequences não-identity (antes das tabelas: DEFAULT nextval) ---------
  union all
  select 3, s.nspname || '.' || s.relname,
    format('CREATE SEQUENCE %I.%I AS %s START WITH %s INCREMENT BY %s MINVALUE %s MAXVALUE %s CACHE %s%s;',
      s.nspname, s.relname, ps.data_type, ps.start_value, ps.increment_by,
      ps.min_value, ps.max_value, ps.cache_size,
      case when ps.cycle then ' CYCLE' else ' NO CYCLE' end)
  from seq s
  join pg_sequences ps on ps.schemaname = s.nspname and ps.sequencename = s.relname
  where not exists (select 1 from ident_seq i where i.seqoid = s.oid)

  -- 4 ── funções SEM dependência de rowtype (antes das tabelas) --------------
  --      cobre DEFAULT/GENERATED/CHECK/índice-por-expressão que chamem função
  union all
  select 4, f.nspname || '.' || f.proname || '(' || f.idargs || ')',
         pg_get_functiondef(f.oid) || ';'
  from fn f
  where not exists (select 1 from fn_rowtype_dep d where d.prooid = f.oid)

  -- 5 ── tabelas --------------------------------------------------------------
  union all
  select 5, t.nspname || '.' || t.relname,
    format('CREATE %sTABLE %I.%I (' || E'\n' || '%s' || E'\n' || ')%s;',
      case t.relpersistence when 'u' then 'UNLOGGED ' else '' end,
      t.nspname, t.relname,
      coalesce((select string_agg(c.txt, ',' || E'\n' order by c.attnum)
                from col c where c.relid = t.oid), ''),
      case when t.reloptions is not null
           then ' WITH (' || array_to_string(t.reloptions, ', ') || ')' else '' end)
  from tbl t

  -- 6 ── ALTER SEQUENCE ... OWNED BY -----------------------------------------
  union all
  select 6, s.nspname || '.' || s.relname,
    format('ALTER SEQUENCE %I.%I OWNED BY %I.%I.%I;',
           s.nspname, s.relname, t.nspname, t.relname, a.attname)
  from seq s
  join owned_seq o on o.seqoid = s.oid
  join tbl t on t.oid = o.relid
  join pg_attribute a on a.attrelid = o.relid and a.attnum = o.attnum
  where not exists (select 1 from ident_seq i where i.seqoid = s.oid)

  -- 7 ── funções COM dependência de rowtype (depois das tabelas) -------------
  union all
  select 7, f.nspname || '.' || f.proname || '(' || f.idargs || ')',
         pg_get_functiondef(f.oid) || ';'
  from fn f
  where exists (select 1 from fn_rowtype_dep d where d.prooid = f.oid)

  -- 8 ── PK / UNIQUE / CHECK / EXCLUDE ---------------------------------------
  union all
  select 8, t.nspname || '.' || t.relname || ':' || con.conname,
    format('ALTER TABLE %I.%I ADD CONSTRAINT %I %s;',
           t.nspname, t.relname, con.conname, pg_get_constraintdef(con.oid, true))
  from pg_constraint con
  join tbl t on t.oid = con.conrelid
  where con.contype in ('p','u','c','x')
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_constraint'::regclass and e.objid = con.oid)

  -- 9 ── índices não-constraint (traz WITH (m=..., ef_construction=...)) -----
  union all
  select 9, t.nspname || '.' || t.relname || ':' || ic.relname,
         pg_get_indexdef(i.indexrelid) || ';'
  from pg_index i
  join tbl t on t.oid = i.indrelid
  join pg_class ic on ic.oid = i.indexrelid
  where not exists (select 1 from pg_constraint con where con.conindid = i.indexrelid)
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_class'::regclass and e.objid = i.indexrelid)

  -- 10 ── views em ordem topológica ------------------------------------------
  union all
  select 10, lpad(coalesce(l.lvl, 0)::text, 4, '0') || ':' || v.nspname || '.' || v.relname,
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

  -- 11 ── foreign keys (depois de todas as tabelas) --------------------------
  union all
  select 11, t.nspname || '.' || t.relname || ':' || con.conname,
    format('ALTER TABLE %I.%I ADD CONSTRAINT %I %s;',
           t.nspname, t.relname, con.conname, pg_get_constraintdef(con.oid, true))
  from pg_constraint con
  join tbl t on t.oid = con.conrelid
  where con.contype = 'f'
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_constraint'::regclass and e.objid = con.oid)

  -- 12 ── triggers ------------------------------------------------------------
  union all
  select 12, r.nspname || '.' || r.relname || ':' || tg.tgname,
         pg_get_triggerdef(tg.oid, true) || ';'
  from pg_trigger tg
  join rel r on r.oid = tg.tgrelid
  where not tg.tgisinternal
    and not exists (select 1 from extobj e
                    where e.classid = 'pg_trigger'::regclass and e.objid = tg.oid)

  -- 13 ── RLS (ENABLE e FORCE são flags separadas) ---------------------------
  union all
  select 13, t.nspname || '.' || t.relname || ':1',
         format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY;', t.nspname, t.relname)
  from tbl t where t.relrowsecurity
  union all
  select 13, t.nspname || '.' || t.relname || ':2',
         format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY;', t.nspname, t.relname)
  from tbl t where t.relforcerowsecurity

  -- 14 ── policies ------------------------------------------------------------
  union all
  select 14, t.nspname || '.' || t.relname || ':' || p.polname,
    format('CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s%s%s;',
      p.polname, t.nspname, t.relname,
      case when p.polpermissive then 'PERMISSIVE' else 'RESTRICTIVE' end,
      case p.polcmd when 'r' then 'SELECT' when 'a' then 'INSERT'
                    when 'w' then 'UPDATE' when 'd' then 'DELETE' else 'ALL' end,
      case when p.polroles is null or 0::oid = any(p.polroles) then 'PUBLIC'
           else (select string_agg(quote_ident(pg_get_userbyid(u.r)), ', '
                                   order by pg_get_userbyid(u.r))
                 from unnest(p.polroles) as u(r)) end,
      case when p.polqual is not null
           then ' USING (' || pg_get_expr(p.polqual, p.polrelid) || ')' else '' end,
      case when p.polwithcheck is not null
           then ' WITH CHECK (' || pg_get_expr(p.polwithcheck, p.polrelid) || ')' else '' end)
  from pg_policy p
  join tbl t on t.oid = p.polrelid

  -- 15a ── REVOKE FROM PUBLIC só onde produção realmente revogou -------------
  union all
  select 15, 'a1:' || n.nspname,
         format('REVOKE ALL ON SCHEMA %I FROM PUBLIC;', n.nspname)
  from pg_namespace n
  join scope s on s.oid = n.oid
  where n.nspacl is not null
    and not exists (select 1 from aclexplode(n.nspacl) a where a.grantee = 0::oid)
  union all
  select 15, 'a2:' || f.nspname || '.' || f.proname || '(' || f.idargs || ')',
         format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC;', f.nspname, f.proname, f.idargs)
  from fn f
  where f.proacl is not null
    and not exists (select 1 from aclexplode(f.proacl) a where a.grantee = 0::oid)

  -- 15b ── GRANTs de schema ---------------------------------------------------
  union all
  select 15, 'b:' || x.nspname || ':' || x.g,
    format('GRANT %s ON SCHEMA %I TO %s%s;',
           x.privs, x.nspname, x.g,
           case when x.is_grantable then ' WITH GRANT OPTION' else '' end)
  from (
    select n.nspname,
           case when a.grantee = 0::oid then 'PUBLIC'
                else quote_ident(pg_get_userbyid(a.grantee)) end as g,
           a.is_grantable,
           string_agg(a.privilege_type, ', ' order by a.privilege_type) as privs
    from pg_namespace n
    join scope s on s.oid = n.oid
    cross join lateral aclexplode(n.nspacl) a
    group by 1, 2, 3
  ) x

  -- 15c ── GRANTs de tabela / view / sequence --------------------------------
  union all
  select 15, 'c:' || x.nspname || '.' || x.relname || ':' || x.g,
    format('GRANT %s ON %s %I.%I TO %s%s;',
           x.privs,
           case when x.relkind = 'S' then 'SEQUENCE' else 'TABLE' end,
           x.nspname, x.relname, x.g,
           case when x.is_grantable then ' WITH GRANT OPTION' else '' end)
  from (
    select r.nspname, r.relname, r.relkind,
           case when a.grantee = 0::oid then 'PUBLIC'
                else quote_ident(pg_get_userbyid(a.grantee)) end as g,
           a.is_grantable,
           string_agg(a.privilege_type, ', ' order by a.privilege_type) as privs
    from rel r
    cross join lateral aclexplode(r.relacl) a
    where r.relkind in ('r','p','v','m','S')
    group by 1, 2, 3, 4, 5
  ) x

  -- 15d ── GRANTs de função ---------------------------------------------------
  union all
  select 15, 'd:' || x.nspname || '.' || x.proname || '(' || x.idargs || '):' || x.g,
    format('GRANT %s ON FUNCTION %I.%I(%s) TO %s%s;',
           x.privs, x.nspname, x.proname, x.idargs, x.g,
           case when x.is_grantable then ' WITH GRANT OPTION' else '' end)
  from (
    select f.nspname, f.proname, f.idargs,
           case when a.grantee = 0::oid then 'PUBLIC'
                else quote_ident(pg_get_userbyid(a.grantee)) end as g,
           a.is_grantable,
           string_agg(a.privilege_type, ', ' order by a.privilege_type) as privs
    from fn f
    cross join lateral aclexplode(f.proacl) a
    group by 1, 2, 3, 4, 5
  ) x

  -- 16 ── comments ------------------------------------------------------------
  union all
  select 16, 'a:' || s.nspname,
         format('COMMENT ON SCHEMA %I IS %L;', s.nspname, obj_description(s.oid, 'pg_namespace'))
  from scope s
  where obj_description(s.oid, 'pg_namespace') is not null
  union all
  select 16, 'b:' || r.nspname || '.' || r.relname,
    format('COMMENT ON %s %I.%I IS %L;',
           case when r.relkind = 'v' then 'VIEW'
                when r.relkind = 'm' then 'MATERIALIZED VIEW'
                when r.relkind = 'S' then 'SEQUENCE' else 'TABLE' end,
           r.nspname, r.relname, obj_description(r.oid, 'pg_class'))
  from rel r
  where r.relkind in ('r','p','v','m','S')
    and obj_description(r.oid, 'pg_class') is not null
  union all
  select 16, 'c:' || r.nspname || '.' || r.relname || ':' || lpad(a.attnum::text, 5, '0'),
         format('COMMENT ON COLUMN %I.%I.%I IS %L;',
                r.nspname, r.relname, a.attname, col_description(r.oid, a.attnum))
  from rel r
  join pg_attribute a on a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped
  where r.relkind in ('r','p','v','m')
    and col_description(r.oid, a.attnum) is not null
  union all
  select 16, 'd:' || f.nspname || '.' || f.proname || '(' || f.idargs || ')',
         format('COMMENT ON FUNCTION %I.%I(%s) IS %L;',
                f.nspname, f.proname, f.idargs, obj_description(f.oid, 'pg_proc'))
  from fn f
  where obj_description(f.oid, 'pg_proc') is not null

  -- 99 ── rodapé --------------------------------------------------------------
  union all
  select 99, ''::text, 'RESET search_path;' || E'\n' || '-- fim do baseline estrutural.'
)

select string_agg(stmt, E'\n\n' order by sec, k) as baseline_sql
from frag
where stmt is not null;

-- ============================================================================
-- SANIDADE — troque SOMENTE o SELECT final acima por este bloco para conferir
-- as contagens por seção antes de usar o texto (continua read-only):
--
--   select sec, count(*) as stmts, sum(length(stmt)) as bytes
--   from frag group by sec order by sec;
--
-- Confira contra `counts` do baseline_fingerprint.sql — mesma régua:
--   sec 4 + sec 7 (funções)  == counts.functions   (extensões já excluídas dos dois)
--   sec 5  (tabelas)         == counts.tables      (hoje 117)
--   sec 9  (índices)         == counts.indexes menos os índices de constraint
--   sec 12 (triggers)        == counts.triggers
--   sec 14 (policies)        == counts.policies
--   sec 1  (schemas)         == counts.schemas     (hoje 19)
--
-- Espera-se sec 7 == 0 ou muito pequeno: só entram funções cuja ASSINATURA usa
-- o rowtype de uma tabela/view. Se sec 7 vier grande, vale olhar antes de usar.
--
-- O check mais importante é o filtro de extensão: os objetos de pg_trgm/vector
-- NÃO podem aparecer nas seções 4/7. Se (sec 4 + sec 7) vier com o total bruto
-- de pg_proc do escopo, o filtro não pegou e o baseline está errado.
-- ============================================================================
