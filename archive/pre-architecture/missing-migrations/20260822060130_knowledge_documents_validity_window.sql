-- Ciclo de vida fino do conteúdo: além de produto vs. institucional (event_id),
-- cada documento pode ter janela de vigência. Ex.: conteúdo de VENDA do Summit
-- pode expirar no início do 2º dia do evento, enquanto o operacional segue até
-- o fim e o institucional não expira. NULL = sempre vigente.
alter table mind.knowledge_documents
  add column if not exists valido_de timestamptz,
  add column if not exists valido_ate timestamptz;

comment on column mind.knowledge_documents.valido_ate is
  'Instante em que o conteúdo sai de circulação para os agentes (ex.: fim das vendas). NULL = sem prazo.';

-- Convenção editorial: metadata->>'fase' classifica o ciclo
-- ('vendas' | 'evento' | 'permanente') para permitir expirar em lote.
