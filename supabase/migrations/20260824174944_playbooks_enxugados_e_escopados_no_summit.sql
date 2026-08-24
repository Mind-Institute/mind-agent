-- Enxuga os playbooks para o que o agente do Summit usa de fato.
--  * b2b/b2c passam a summit_b2b / summit_b2c: venda é escopada por produto.
--  * ja_comprou sai: cliente_suporte já cobre o pós-compra.
--  * desconhecido sai: a descoberta ("ainda não sei quem é") vive no base.
-- Nenhuma função referencia essas chaves (verificado antes de aplicar).
-- Rollback: reverter este commit — o conteúdo original dos removidos está na
-- migration de seed dos prompts (cerebro_do_agente_sai_do_treble).
delete from agentes.prompts where chave in ('playbook_ja_comprou','playbook_desconhecido');
update agentes.prompts set chave = 'playbook_summit_b2b' where chave = 'playbook_b2b';
update agentes.prompts set chave = 'playbook_summit_b2c' where chave = 'playbook_b2c';
