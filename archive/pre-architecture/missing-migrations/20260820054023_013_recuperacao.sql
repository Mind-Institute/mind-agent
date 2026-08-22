drop index if exists mind.conhecimento_trechos_embedding_idx;
create index knowledge_chunks_embedding_hnsw
  on mind.knowledge_chunks using hnsw (embedding vector_cosine_ops)
  with (m = 16, ef_construction = 64);

comment on index mind.knowledge_chunks_embedding_hnsw is
  'HNSW, não ivfflat: este índice nasce vazio. ivfflat treinado em tabela vazia recupera errado sem dar erro.';

do $$
declare r record;
begin
  for r in
    select c.conrelid::regclass::text as tabela,
           a.attname                  as coluna,
           c.conrelid, c.conkey[1] as attnum
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f'
      and c.connamespace::regnamespace::text in ('mind','concierge','platform')
      and array_length(c.conkey,1) = 1
      and not exists (select 1 from pg_index i
                      where i.indrelid = c.conrelid and i.indkey[0] = c.conkey[1])
  loop
    execute format('create index on %s (%I)', r.tabela, r.coluna);
  end loop;
end $$;

create index if not exists sessions_event_dia_inicio
  on mind.sessions (event_id, dia, inicio);
create index if not exists sessions_dia_inicio
  on mind.sessions (dia, inicio);

alter table mind.knowledge_documents
  add column if not exists agents text[] not null default '{}';
comment on column mind.knowledge_documents.agents is
  'Quais agentes podem recuperar este documento. Vazio = todos. Não é permissão, é relevância: material fora de escopo no contexto piora a resposta mesmo sem vazar nada.';
create index if not exists knowledge_documents_agents
  on mind.knowledge_documents using gin (agents);

alter table mind.knowledge_documents
  add column if not exists atualizado_em_fonte timestamptz;

create or replace function api.knowledge(
  p_pergunta  text,
  p_embedding vector(1536) default null,
  p_agent     text default null,
  p_limit     integer default 6)
returns jsonb
language sql stable security definer
set search_path = mind, public as $$
  with permitido as (
    select d.id, d.titulo, d.tipo_conteudo, d.url, f.nome as fonte
    from mind.knowledge_documents d
    join mind.knowledge_sources f on f.id = d.fonte_id
    where f.ativo and d.ativo
      and (p_agent is null or cardinality(d.agents) = 0 or d.agents @> array[p_agent])
  ),
  por_texto as (
    select c.id, row_number() over (
             order by ts_rank(c.tsv, plainto_tsquery('portuguese', p_pergunta)) desc) as pos
    from mind.knowledge_chunks c
    join permitido d on d.id = c.doc_id
    where not c.stale
      and c.tsv @@ plainto_tsquery('portuguese', p_pergunta)
    limit p_limit * 4
  ),
  por_vetor as (
    select c.id, row_number() over (order by c.embedding <=> p_embedding) as pos
    from mind.knowledge_chunks c
    join permitido d on d.id = c.doc_id
    where p_embedding is not null
      and not c.stale
      and c.embedding is not null
    order by c.embedding <=> p_embedding
    limit p_limit * 4
  ),
  fundido as (
    select id, sum(peso) as score from (
      select id, 1.0 / (60 + pos) as peso from por_texto
      union all
      select id, 1.0 / (60 + pos) as peso from por_vetor) u
    group by id
    order by score desc
    limit p_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'texto', c.texto, 'documento', d.titulo, 'fonte', d.fonte,
           'tipo', d.tipo_conteudo, 'url', d.url,
           'score', round(fu.score::numeric, 5)) order by fu.score desc), '[]')
  from fundido fu
  join mind.knowledge_chunks c on c.id = fu.id
  join permitido d on d.id = c.doc_id;
$$;

comment on function api.knowledge(text, vector, text, integer) is
  'Busca híbrida no conhecimento do Mind. Sem embedding, degrada para texto e continua respondendo — a assinatura não muda quando o embedding entrar.';

create or replace function mind.tocar() returns trigger
language plpgsql set search_path = mind, public as $$
begin
  new.atualizado_em := now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['events','sessions','locations','speakers',
                           'event_rules','knowledge_documents']
  loop
    execute format('alter table mind.%I add column if not exists atualizado_em timestamptz not null default now()', t);
    execute format('drop trigger if exists t_touch on mind.%I', t);
    execute format('create trigger t_touch before update on mind.%I
                    for each row execute function mind.tocar()', t);
    execute format('create index if not exists %I on mind.%I (atualizado_em desc)',
                   t || '_atualizado_em', t);
  end loop;
end $$;

create or replace function api.changed_since(p_desde timestamptz)
returns jsonb language sql stable security definer
set search_path = mind, public as $$
  select jsonb_build_object(
    'events',              (select count(*) from mind.events              where atualizado_em > p_desde),
    'sessions',            (select count(*) from mind.sessions            where atualizado_em > p_desde),
    'locations',           (select count(*) from mind.locations           where atualizado_em > p_desde),
    'speakers',            (select count(*) from mind.speakers            where atualizado_em > p_desde),
    'event_rules',         (select count(*) from mind.event_rules         where atualizado_em > p_desde),
    'knowledge_documents', (select count(*) from mind.knowledge_documents where atualizado_em > p_desde),
    'agora', now());
$$;

comment on function api.changed_since(timestamptz) is
  'O que mudou desde X. É o que permite um agente cachear sem que dois agentes respondam coisas diferentes sobre o mesmo fato.';

comment on function api.sessions(text, date, text, integer) is
  'Devolve a grade inteira num jsonb só. Correto na escala de um evento (dezenas de sessões); a partir de alguns milhares de linhas, isto precisa virar paginado. Está dito aqui para ninguém descobrir em produção.';

revoke all on all functions in schema api from anon, authenticated;
