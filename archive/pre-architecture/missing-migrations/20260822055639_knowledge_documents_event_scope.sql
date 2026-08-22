-- Separa conteúdo institucional (Mind) de conteúdo de produto (Mind Summit 2026)
-- no banco comum de conhecimento, sem duplicar registros entre agentes.
alter table mind.knowledge_documents
  add column if not exists event_id uuid references mind.events(id);

comment on column mind.knowledge_documents.event_id is
  'NULL = conteúdo institucional do Mind (permanente); preenchido = conteúdo do produto/evento, sai de cena junto com ele.';

-- Backfill: tudo que existe hoje veio do site do Summit 2026; a revisão
-- editorial em andamento reclassifica caso a caso (ex.: políticas institucionais).
update mind.knowledge_documents
  set event_id = (select id from mind.events where slug = 'mind-summit-2026')
  where event_id is null;

create index if not exists knowledge_documents_event_ativo_idx
  on mind.knowledge_documents (event_id) where ativo;
