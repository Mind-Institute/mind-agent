-- leads_capturados vira o landing do formulário do site. Sistema novo, tabela
-- vazia (0 linhas), ninguém lê ainda -- reconstruída limpa com os campos do
-- formulário (nomes do HubSpot) + rastreamento de campanha + estado.
-- Fluxo: o formulário grava aqui como 'pendente'; quando o nome casa no espelho
-- do HubSpot, vira 'enviado' (enviado_em); depois os enviados podem ser limpos.
-- A função antiga mind_lead_capturar era do rascunho anterior (colunas em pt-BR
-- e fila de agente) e sai junto -- será reconstruída depois com o banco pronto.
drop function if exists public.mind_lead_capturar(uuid, text, text, jsonb);
drop table if exists crm.leads_capturados;

create table crm.leads_capturados (
  id                        uuid primary key default gen_random_uuid(),
  -- identidade (nomes do formulário / HubSpot)
  firstname                 text,
  lastname                  text,
  email                     text,
  phone                     text,
  company                   text,
  -- segmento e ponto de entrada no site
  perfil_d_cliente          text,
  botao_selecionado_no_site text,
  -- rastreamento de campanha
  utm_source                text,
  utm_medium                text,
  utm_campaign              text,
  utm_term                  text,
  utm_content               text,
  fbclid                    text,
  gclid                     text,
  msclkid                   text,
  li_fat_id                 text,
  -- controle
  estado                    text not null default 'pendente'
                              check (estado in ('pendente','enviado')),
  criado_em                 timestamptz not null default now(),
  enviado_em                timestamptz
);

comment on table crm.leads_capturados is
  'Landing dos leads do formulário do site: campos do formulário (nomes do HubSpot) + rastreamento de campanha + estado. pendente -> enviado quando o lead casa no espelho do HubSpot; enviados podem ser limpos depois.';
