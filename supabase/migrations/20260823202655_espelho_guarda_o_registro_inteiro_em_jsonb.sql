-- Opcao B (Adriana, 23/08): as propriedades que os agentes usam continuam colunas
-- tipadas, com indice. O registro INTEIRO do HubSpot -- as 418 de contato e as 334
-- de negocio, incluindo as que ainda nao existem -- vive em `propriedades`.
--
-- Traz tudo igual. A diferenca e que propriedade nova no HubSpot entra sozinha, sem
-- migration aqui, e propriedade renomeada la nao quebra nada aqui.
alter table crm.contato_espelho      add column if not exists propriedades jsonb not null default '{}'::jsonb;
alter table crm.summit_em_andamento  add column if not exists propriedades jsonb not null default '{}'::jsonb;
alter table crm.negocios_historicos  add column if not exists propriedades jsonb not null default '{}'::jsonb;

comment on column crm.contato_espelho.propriedades is
  'O registro cru do contato no HubSpot, inteiro. Consulta: propriedades->>''lead_score_summit_26''. As colunas tipadas ao lado sao as que os agentes usam de verdade -- estas aqui existem para nada se perder e nada quebrar.';
comment on column crm.summit_em_andamento.propriedades is
  'O registro cru do negocio no HubSpot, inteiro. Mesma regra do contato.';
comment on column crm.negocios_historicos.propriedades is
  'O registro cru do negocio no HubSpot, inteiro. Mesma regra do contato.';

-- GIN para conseguir filtrar pelo que nao virou coluna sem varrer a tabela.
create index if not exists contato_espelho_props_idx     on crm.contato_espelho     using gin (propriedades jsonb_path_ops);
create index if not exists summit_em_andamento_props_idx on crm.summit_em_andamento using gin (propriedades jsonb_path_ops);
create index if not exists negocios_hist_props_idx       on crm.negocios_historicos using gin (propriedades jsonb_path_ops);

-- O controle da carga ja existia para contatos, com marca d'agua. Os negocios
-- entram pelo mesmo caminho: cada fonte lembra sozinha de onde parou.
insert into crm.sync_estado (fonte, status)
values ('hubspot_negocios', 'ocioso'), ('hubspot_negocios_historicos', 'ocioso')
on conflict (fonte) do nothing;
