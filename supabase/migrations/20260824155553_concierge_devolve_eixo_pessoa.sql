-- Três tabelas ficaram no concierge mas são do eixo pessoa, não do runtime do
-- agente. Voltam para a casa certa. SET SCHEMA é troca de catálogo: instantâneo,
-- preserva dados; FKs e views que as referenciam seguem o objeto (por OID).
--   intencoes            -> intelligence  (o que o sistema infere da pessoa)
--   avaliacoes           -> engagement    (feedback da pessoa sobre sessões)
--   avaliacao_execucoes  -> engagement    (execuções das avaliações)
alter table concierge.intencoes           set schema intelligence;
alter table concierge.avaliacoes          set schema engagement;
alter table concierge.avaliacao_execucoes set schema engagement;
