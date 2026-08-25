-- Faxina passo 5: a base de conhecimento deixa de ser uma so.
-- O isolamento para de depender de a consulta lembrar de filtrar e vira
-- propriedade do lugar onde o documento mora.
--
-- comum  = institucional da empresa (3 politicas, sem produto_codigo)
-- summit = Summit, todas as edicoes (17 docs de mind-summit-2026)
-- institute / dash / eventos = nascem vazias, mesma estrutura
--
-- Cada linha expoe a view "conhecimento" = a casa dela UNIAO comum. O agente
-- do Institute le institute.conhecimento e e' fisicamente incapaz de trazer
-- chunk do Summit.

-- knowledge_sources nao era orfa: api.knowledge le ela e knowledge_documents
-- .fonte_id aponta para ela. E' procedencia de conteudo, e e' compartilhada.
alter table mind.knowledge_sources   set schema comum;
alter table mind.knowledge_documents set schema comum;
alter table mind.knowledge_chunks    set schema comum;

do $$
declare linha text; v_cols text;
begin
  foreach linha in array array['summit','institute','dash','eventos'] loop
    execute format('create table %I.knowledge_documents (like comum.knowledge_documents including all)', linha);
    execute format('create table %I.knowledge_chunks    (like comum.knowledge_chunks including all)', linha);
    execute format('alter table %I.knowledge_documents add constraint knowledge_documents_fonte_fk
                      foreign key (fonte_id) references comum.knowledge_sources(id)', linha);
    execute format('alter table %I.knowledge_chunks add constraint knowledge_chunks_doc_fk
                      foreign key (doc_id) references %I.knowledge_documents(id) on delete cascade', linha, linha);

    execute format('create view %I.conhecimento as
                      select * from %I.knowledge_documents
                      union all select * from comum.knowledge_documents', linha, linha);
    execute format('create view %I.conhecimento_chunks as
                      select * from %I.knowledge_chunks
                      union all select * from comum.knowledge_chunks', linha, linha);
    execute format('comment on view %I.conhecimento is %L', linha,
      'O que o agente de '||linha||' pode ler: o conhecimento desta linha mais o institucional da Mind. Nunca o de outra linha.');

    if exists (select 1 from pg_roles where rolname = 'mind_agent') then
      execute format('grant select, insert, update, delete on %I.knowledge_documents, %I.knowledge_chunks to mind_agent', linha, linha);
      execute format('grant select on %I.conhecimento, %I.conhecimento_chunks to mind_agent', linha, linha);
    end if;
  end loop;

  -- os 17 do Summit mudam de casa; os 3 institucionais ficam em comum.
  -- Lista explicita de colunas: knowledge_chunks.tsv e' coluna gerada.
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position) into v_cols
  from information_schema.columns
  where table_schema='comum' and table_name='knowledge_documents' and is_generated='NEVER';
  execute format('insert into summit.knowledge_documents (%s) select %s from comum.knowledge_documents where produto_codigo is not null', v_cols, v_cols);

  select string_agg(quote_ident(column_name), ', ' order by ordinal_position) into v_cols
  from information_schema.columns
  where table_schema='comum' and table_name='knowledge_chunks' and is_generated='NEVER';
  execute format('insert into summit.knowledge_chunks (%s) select %s from comum.knowledge_chunks where doc_id in (select id from summit.knowledge_documents)', v_cols, v_cols);

  delete from comum.knowledge_chunks    where doc_id in (select id from summit.knowledge_documents);
  delete from comum.knowledge_documents where produto_codigo is not null;
end $$;

-- compatibilidade, somente leitura: ninguem escreve knowledge_* por funcao
create view mind.knowledge_documents as
  select * from comum.knowledge_documents
  union all select * from summit.knowledge_documents
  union all select * from institute.knowledge_documents
  union all select * from dash.knowledge_documents
  union all select * from eventos.knowledge_documents;

create view mind.knowledge_chunks as
  select * from comum.knowledge_chunks
  union all select * from summit.knowledge_chunks
  union all select * from institute.knowledge_chunks
  union all select * from dash.knowledge_chunks
  union all select * from eventos.knowledge_chunks;

create view mind.knowledge_sources as select * from comum.knowledge_sources;

comment on view mind.knowledge_documents is
  'COMPATIBILIDADE (somente leitura): a base agora e uma por linha de produto. Cai na migration final da faxina.';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'mind_agent') then
    grant select on mind.knowledge_documents, mind.knowledge_chunks, mind.knowledge_sources to mind_agent;
    grant select, insert, update, delete on comum.knowledge_documents, comum.knowledge_chunks, comum.knowledge_sources to mind_agent;
  end if;
end $$;

-- --------------------------------------------- os leitores apontam para a casa
do $$
declare r record; v_def text;
begin
  for r in
    select p.oid from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language l on l.oid = p.prolang
    where p.prokind='f' and l.lanname in ('sql','plpgsql')
      and n.nspname in ('public','api','concierge','treble','mind','crm')
      and pg_get_functiondef(p.oid) ~ '\mmind\.knowledge_'
  loop
    v_def := pg_get_functiondef(r.oid);
    v_def := regexp_replace(v_def, '\mmind\.knowledge_documents\M', 'summit.conhecimento', 'g');
    v_def := regexp_replace(v_def, '\mmind\.knowledge_chunks\M',    'summit.conhecimento_chunks', 'g');
    v_def := regexp_replace(v_def, '\mmind\.knowledge_sources\M',   'comum.knowledge_sources', 'g');
    execute v_def;
  end loop;
end $$;

-- o catalogo passa a apontar para a casa certa
update catalogo.produtos set schema_dados = linha where linha is not null;
