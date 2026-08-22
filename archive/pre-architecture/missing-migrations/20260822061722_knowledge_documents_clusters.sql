-- Clusterização da base de conhecimento (definição editorial da Adriana):
--   empresa — conhecimento geral do Mind (institucional, permanente)
--   produto — conhecimento de cada produto (Summit 2026 etc.), amarrado a event_id
--   ciencia — conteúdo e ciência que apoiam todos os produtos (pesquisadores,
--             construtos, obras); não pertence a produto nenhum
alter table mind.knowledge_documents
  add column if not exists cluster text;

update mind.knowledge_documents set cluster = 'produto' where cluster is null;

alter table mind.knowledge_documents
  alter column cluster set not null,
  add constraint knowledge_documents_cluster_valido
    check (cluster in ('empresa', 'produto', 'ciencia')),
  add constraint knowledge_documents_cluster_evento
    check ((cluster = 'produto') = (event_id is not null));

comment on column mind.knowledge_documents.cluster is
  'empresa = Mind institucional; produto = por produto (exige event_id); ciencia = base científica compartilhada por todos os produtos.';
