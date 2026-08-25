-- A pessoa canônica não é do CRM (camada comercial, sabor HubSpot) nem do
-- intelligence (o que a gente infere). Identidade é um fato e merece casa
-- própria: schema `pessoas`. É o pino que engagement e intelligence apontam,
-- e o hubspot_id liga ao espelho. SET SCHEMA é troca de catálogo: instantâneo,
-- preserva dados; FKs, índices, RLS e views seguem por OID. Só o texto de 7
-- funções que citam "crm.pessoas" quebra e será repointado em seguida.
create schema if not exists pessoas;
comment on schema pessoas is
  'Registro canônico de identidade das pessoas do Mind Intelligence: o pino que engagement/intelligence apontam. hubspot_id liga ao espelho do HubSpot.';

alter table crm.pessoas set schema pessoas;
