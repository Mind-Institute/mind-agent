-- ============================================================
-- Contrato: toda tabela de negócio declara para que serve
-- ============================================================
-- Rodar:  psql "$DATABASE_URL" -f tests/objetivo_por_tabela_contract.sql
--
-- Não escreve nada. Abre transação e desfaz no fim, como os outros
-- contratos deste diretório.
--
-- POR QUE ESTE CONTRATO EXISTE
-- Em 21/09/2026, 89 das 160 tabelas do projeto não diziam para que
-- serviam, e 84 delas não eram citadas em nenhum documento do repositório
-- — entre elas o schema `checkout` inteiro, com pedidos reais do
-- Institute. Documento ao lado do banco se separa do banco em silêncio;
-- o `comment on table` viaja dentro do objeto e some junto com ele.
--
-- Este contrato torna isso verificável: uma tabela nova sem objetivo
-- declarado quebra aqui, e quebra com o nome dela na mensagem.
--
-- O ESCOPO É POR EXCLUSÃO, DE PROPÓSITO
-- A lista abaixo remove os schemas gerenciados pelo Supabase e pelas
-- extensões. Tudo o que não está nela é considerado schema de negócio —
-- inclusive um schema que ainda não existe. Uma allowlist precisaria ser
-- editada a cada schema novo, e o dia em que alguém esquecesse de editá-la
-- seria justamente o dia em que o contrato pararia de proteger.
-- ============================================================

begin;

do $$
declare
  n_sem int;
  lista text;
begin
  select count(*), string_agg(nome, E'\n    ' order by nome)
    into n_sem, lista
  from (
    select ns.nspname || '.' || c.relname as nome
    from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
    left join pg_description d on d.objoid = c.oid and d.objsubid = 0
    where c.relkind = 'r'
      and d.description is null
      and ns.nspname not in (
        'pg_catalog','information_schema','auth','storage','realtime',
        'vault','supabase_migrations','supabase_functions','extensions',
        'net','cron','pgsodium','pgsodium_masks','pgbouncer','graphql',
        'graphql_public','_realtime','_analytics'
      )
      and ns.nspname not like 'pg\_%'
  ) t;

  if n_sem > 0 then
    raise exception E'CONTRATO QUEBRADO — objetivo por tabela\n\n  % tabela(s) sem `comment on table`:\n\n    %\n\n  Toda tabela de negócio declara para que serve, dentro do banco.\n  Conserto: `comment on table <schema>.<tabela> is ''<uma frase>'';`\n  na mesma migration que criou a tabela.\n', n_sem, lista;
  end if;

  raise notice 'contrato ok — todas as tabelas de negócio declaram objetivo';
end $$;

-- Segundo contrato: o objetivo precisa dizer alguma coisa.
-- Um comentário de três palavras satisfaz o primeiro contrato e não
-- ajuda ninguém. 40 caracteres é o piso — abaixo disso não cabe uma
-- frase que explique para que a tabela serve.
do $$
declare
  n_curto int;
  lista text;
begin
  select count(*), string_agg(nome || ' (' || tam || ' car.)', E'\n    ' order by tam)
    into n_curto, lista
  from (
    select ns.nspname || '.' || c.relname as nome,
           length(trim(d.description)) as tam
    from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
    join pg_description d on d.objoid = c.oid and d.objsubid = 0
    where c.relkind = 'r'
      and length(trim(d.description)) < 40
      and ns.nspname not in (
        'pg_catalog','information_schema','auth','storage','realtime',
        'vault','supabase_migrations','supabase_functions','extensions',
        'net','cron','pgsodium','pgsodium_masks','pgbouncer','graphql',
        'graphql_public','_realtime','_analytics'
      )
      and ns.nspname not like 'pg\_%'
  ) t;

  if n_curto > 0 then
    raise exception E'CONTRATO QUEBRADO — objetivo curto demais\n\n  % tabela(s) com comentário abaixo de 40 caracteres:\n\n    %\n\n  O objetivo responde "para que esta tabela serve", em uma frase.\n', n_curto, lista;
  end if;

  raise notice 'contrato ok — nenhum objetivo abaixo de 40 caracteres';
end $$;

rollback;
