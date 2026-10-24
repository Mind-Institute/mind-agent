-- A pesquisa do app foi apagada (Adriana, 24/09/2026). Saem as duas chaves que a ligavam.
-- DESFAZER:
--   insert into concierge.config (chave, valor, descricao) values
--     ('avaliacao_do_dia', '{"ativo": true}', 'Liga e desliga a pesquisa "Avaliação do dia" no app. Desligada, o card não aparece e envio novo é recusado; respostas já gravadas não são afetadas.'),
--     ('avaliacao_do_evento', '{"abre": "2026-09-18", "ativo": false, "fecha": "2026-10-02"}', null);
delete from concierge.config where chave in ('avaliacao_do_dia', 'avaliacao_do_evento');
