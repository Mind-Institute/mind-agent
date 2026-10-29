-- Espelho de eduzz.ingressos / eduzz.vendas ganha conta_venda (mind_dash | ef), igual à origem
-- (mind-summit-vendas-dashboard, migration 2026-09-24-conta-venda-ef). espelho_gravar usa
-- jsonb_populate_record, então a coluna é preenchida sem mudar a função.
alter table eduzz.ingressos add column if not exists conta_venda text not null default 'mind_dash';
alter table eduzz.vendas    add column if not exists conta_venda text not null default 'mind_dash';
comment on column eduzz.ingressos.conta_venda is 'Conta que vendeu (origem): mind_dash ou ef.';
comment on column eduzz.vendas.conta_venda    is 'Conta que vendeu (origem): mind_dash ou ef.';
