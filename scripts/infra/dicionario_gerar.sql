-- ============================================================
-- DICIONÁRIO DE DADOS — GERADOR — 100% READ-ONLY
-- ============================================================
-- Monta docs/DICIONARIO.md a partir do que o banco sabe sobre si.
-- Só SELECT sobre catálogo do sistema e count(*) por tabela; não lê
-- nenhuma coluna de negócio e não escreve nada.
--
-- Rodar:
--   psql "$DATABASE_URL" -At -f scripts/infra/dicionario_gerar.sql > docs/DICIONARIO.md
--
-- POR QUE GERADO, E NÃO ESCRITO
-- Um dicionário escrito à mão envelhece no primeiro merge que ninguém
-- lembrou de refletir. Este sai do banco, então ou está certo ou o banco
-- mudou — e nos dois casos rodar de novo resolve.
--
-- A COLUNA "objetivo" VEM DO `comment on table`, que é onde a decisão de
-- 21/09/2026 colocou essa informação. Tabela sem comentário aparece aqui
-- como lacuna explícita, e quebra tests/objetivo_por_tabela_contract.sql.
--
-- O ESCOPO É POR EXCLUSÃO, igual ao contrato: o que não é schema
-- gerenciado do Supabase é schema de negócio, inclusive schema que ainda
-- não existe.
-- ============================================================

\pset format unaligned
\pset tuples_only on
\pset footer off

with escopo as (
  select
    ns.nspname                                as sch,
    c.relname                                 as tbl,
    c.oid                                     as oid,
    c.relrowsecurity                          as rls,
    coalesce(trim(d.description), '')         as objetivo,
    (select count(*) from pg_attribute a
      where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped) as colunas,
    (xpath('/row/cnt/text()',
       query_to_xml(format('select count(*) as cnt from %I.%I', ns.nspname, c.relname),
                    false, true, '')))[1]::text::bigint                  as linhas
  from pg_class c
  join pg_namespace ns on ns.oid = c.relnamespace
  left join pg_description d on d.objoid = c.oid and d.objsubid = 0
  where c.relkind = 'r'
    and ns.nspname not in (
      'pg_catalog','information_schema','auth','storage','realtime',
      'vault','supabase_migrations','supabase_functions','extensions',
      'net','cron','pgsodium','pgsodium_masks','pgbouncer','graphql',
      'graphql_public','_realtime','_analytics'
    )
    and ns.nspname not like 'pg\_%'
),
cabecalho as (
  select 0 as ord, '' as sch, 0 as sub, format(
E'# Dicionário de dados\n'
'\n'
'> **Arquivo gerado. Não editar à mão.**\n'
'>\n'
'> `psql "$DATABASE_URL" -At -f scripts/infra/dicionario_gerar.sql > docs/DICIONARIO.md`\n'
'>\n'
'> Gerado em %s a partir do banco. A coluna **objetivo** é o `comment on\n'
'> table` da própria tabela — se estiver vazia aqui, está vazia no banco, e\n'
'> `tests/objetivo_por_tabela_contract.sql` reprova.\n'
'\n'
'| | |\n'
'|---|---:|\n'
'| schemas de negócio | %s |\n'
'| tabelas | %s |\n'
'| com objetivo declarado | %s |\n'
'| **sem objetivo** | **%s** |\n'
'| com RLS | %s |\n'
'| linhas no total | %s |\n',
    to_char(now() at time zone 'UTC', 'DD/MM/YYYY HH24:MI') || ' UTC',
    (select count(distinct sch) from escopo),
    (select count(*) from escopo),
    (select count(*) from escopo where objetivo <> ''),
    (select count(*) from escopo where objetivo =  ''),
    (select count(*) from escopo where rls),
    (select to_char(sum(linhas), 'FM999G999G999') from escopo)
  ) as linha
),
secoes as (
  select 1 as ord, sch, 0 as sub, format(
    E'\n## `%s`\n\n%s tabelas · %s linhas · %s com objetivo · %s com RLS\n\n'
    '| tabela | objetivo | linhas | col. | RLS |\n'
    '|---|---|---:|---:|---|',
    sch, count(*),
    to_char(sum(linhas), 'FM999G999G999'),
    count(*) filter (where objetivo <> ''),
    count(*) filter (where rls)
  ) as linha
  from escopo group by sch
),
linhas_tabela as (
  select 2 as ord, sch, row_number() over (partition by sch order by linhas desc, tbl) as sub,
    format('| `%s` | %s | %s | %s | %s |',
      tbl,
      case when objetivo = '' then '**— sem objetivo declarado —**'
           else replace(replace(objetivo, E'\n', ' '), '|', '\')
      end,
      to_char(linhas, 'FM999G999G999'),
      colunas,
      case when rls then 'sim' else '**não**' end
    ) as linha
  from escopo
),
rodape as (
  select 3 as ord, 'zzzz' as sch, 999999 as sub, format(
E'\n---\n'
'\n'
'## Lacunas\n'
'\n'
'%s\n'
'\n'
'%s\n',
    case when (select count(*) from escopo where objetivo = '') = 0
      then 'Nenhuma tabela sem objetivo declarado.'
      else format('**%s tabela(s) sem objetivo declarado:** %s',
        (select count(*) from escopo where objetivo = ''),
        (select string_agg('`' || sch || '.' || tbl || '`', ', ' order by sch, tbl)
           from escopo where objetivo = ''))
    end,
    case when (select count(*) from escopo where not rls) = 0
      then 'Todas as tabelas têm RLS.'
      else format('**%s tabela(s) sem RLS:** %s',
        (select count(*) from escopo where not rls),
        (select string_agg('`' || sch || '.' || tbl || '`', ', ' order by sch, tbl)
           from escopo where not rls))
    end
  ) as linha
)
select linha from (
  select ord, sch, sub, linha from cabecalho
  union all select ord, sch, sub, linha from secoes
  union all select ord, sch, sub, linha from linhas_tabela
  union all select ord, sch, sub, linha from rodape
) t
order by
  case when ord = 0 then 0 when ord = 3 then 2 else 1 end,
  sch, ord, sub;
