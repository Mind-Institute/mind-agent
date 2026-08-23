-- Controle do sincronismo com o HubSpot.
-- Guarda a marca d'água: o maior "última modificação" já trazido. A próxima
-- execução pede ao HubSpot só quem mudou depois disso — é o que torna a
-- rodada diária barata e a carga inicial apenas a primeira rodada, sem
-- código separado que ninguém saberia repetir.
create table if not exists crm.sync_estado (
  fonte text primary key,
  marca_dagua timestamptz,        -- maior lastmodifieddate já processado
  iniciado_em timestamptz,
  concluido_em timestamptz,
  status text not null default 'ocioso'
    check (status in ('ocioso', 'rodando', 'concluido', 'erro')),
  registros_lidos integer not null default 0,
  registros_gravados integer not null default 0,
  ignorados jsonb not null default '[]'::jsonb,  -- ex.: produto fora do catálogo
  erro text
);

comment on table crm.sync_estado is
  'Marca d''agua e resultado da ultima sincronizacao por fonte. A carga inicial e a primeira rodada: mesma logica, marca d''agua vazia.';
comment on column crm.sync_estado.ignorados is
  'O que a rodada nao conseguiu gravar e por que. Silenciar isso faria a base parecer completa quando nao esta.';

insert into crm.sync_estado (fonte) values ('hubspot_contatos')
on conflict (fonte) do nothing;

alter table crm.sync_estado enable row level security;
