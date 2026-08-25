-- "CRM Summit em andamento" (Adriana, 23/08). O nome diz o que a tabela e: o que
-- ainda esta de pe. `crm.negocios` era generico demais para uma tabela que so
-- existe por causa de um pipeline especifico.
--
-- Sem o ano no nome de proposito: edicao e LINHA, nao tabela -- a mesma regra que
-- ja vale para summit.events e catalogo.produtos. Qual edicao e um negocio, quem
-- diz e produto_codigo. O pipeline "Pipeline de vendas - Summit" nao e anual.
alter table crm.negocios rename to summit_em_andamento;

alter index crm.negocios_pessoa_pipeline_idx rename to summit_em_andamento_pessoa_pipeline_idx;
alter index crm.negocios_abertos_idx         rename to summit_em_andamento_abertos_idx;

comment on table crm.summit_em_andamento is
  'Negocios VIVOS do Mind Summit -- pipeline "Pipeline de vendas - Summit" (917379159). E aqui, e so aqui, que o agente pergunta "essa pessoa ja tem negocio aberto?" antes de decidir se preenche o formulario. Nunca no historico. A edicao (2026, 2027...) e produto_codigo, nao tabela.';
