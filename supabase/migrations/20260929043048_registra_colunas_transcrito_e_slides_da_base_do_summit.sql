-- Registra no histórico duas colunas de summit_2026.knowledge_documents que foram criadas
-- direto no banco (fora de migration) em 29/09/2026, junto com a carga dos slides dos
-- palestrantes internacionais. Idempotente: no banco atual não muda nada; num banco novo,
-- recria as colunas com os mesmos comentários.
--   transcrito: texto da transcrição da palestra (hoje só d1-0915-beneficio-transformacao).
--   slides:     texto extraído dos slides da palestra (uma linha por apresentação,
--               tipo_conteudo = 'slides', ligada à palestra por sessao_id).
alter table summit_2026.knowledge_documents add column if not exists transcrito text;
alter table summit_2026.knowledge_documents add column if not exists slides text;

comment on column summit_2026.knowledge_documents.transcrito is
  'Conteúdo textual da transcrição da sessão. Fonte primária do que foi efetivamente dito no palco.';
comment on column summit_2026.knowledge_documents.slides is
  'Conteúdo textual extraído dos slides da sessão. Fonte separada da transcrição; não implica que todo conteúdo tenha sido verbalizado.';
