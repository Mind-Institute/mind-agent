-- Quarto cluster editorial: conhecimento sobre clientes e leads do Mind
-- (ICPs, jobs to be done, dores por perfil). Conhecimento de SEGMENTO, interno:
-- orienta a argumentação dos bots, nunca é recitado ao usuário final.
-- Dados individuais de clientes/leads NÃO entram aqui (ficam no CRM/inscrições).
alter table mind.knowledge_documents
  drop constraint knowledge_documents_cluster_valido,
  add constraint knowledge_documents_cluster_valido
    check (cluster in ('empresa', 'produto', 'ciencia', 'clientes'));

-- Marcação de audiência: quem pode ver o conteúdo em si.
-- 'publico' = pode ser dito ao usuário final; 'interno' = só orienta o bot.
alter table mind.knowledge_documents
  add column if not exists audiencia text not null default 'publico'
    check (audiencia in ('publico', 'interno'));

comment on column mind.knowledge_documents.cluster is
  'empresa = Mind institucional; produto = por produto (exige event_id); ciencia = base científica compartilhada; clientes = ICPs/segmentos e leads (interno).';
comment on column mind.knowledge_documents.audiencia is
  'publico = o bot pode dizer isso ao usuário; interno = só orienta tom e argumento, nunca é recitado.';
