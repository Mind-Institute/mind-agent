-- Espelho das Companies do HubSpot em crm (pedido e aprovação da Adriana, 24/09/2026 — D2:
-- "crie sim em schema CRM, faça um espelho das empresas e infos relacionadas às empresas que
-- estão hoje no HubSpot").
--
-- Entra no motor de espelhos que já existe (Edge Function `hubspot-sync` + crm.sync_estado +
-- mind_espelho_gravar): uma linha em sync_estado, a tabela destino, `companies` aceito na
-- remoção de arquivados e um horário no cron. Mirror, nunca fonte autoral: empresa nasce e é
-- corrigida no HubSpot. Não fala de pessoa, então não leva mind_id (Regra #1 não se aplica).

create table if not exists crm.empresa_espelho (
  id                          uuid primary key default gen_random_uuid(),
  hubspot_company_id          text not null unique,
  name                        text,
  domain                      text,
  website                     text,
  industry                    text,
  type                        text,
  description                 text,
  phone                       text,
  address                     text,
  city                        text,
  state                       text,
  country                     text,
  zip                         text,
  numberofemployees           numeric,
  annualrevenue               numeric,
  lifecyclestage              text,
  hs_lead_status              text,
  hubspot_owner_id            text,
  linkedin_company_page       text,
  num_associated_contacts     numeric,
  num_associated_deals        numeric,
  total_revenue               numeric,
  recent_deal_amount          numeric,
  recent_deal_close_date      timestamptz,
  first_deal_created_date     timestamptz,
  hs_num_open_deals           numeric,
  notes_last_updated          timestamptz,
  createdate                  timestamptz,
  hs_lastmodifieddate         timestamptz,
  -- chave de comparação de nome (mesma regra do perfil: sem acento, sufixo jurídico, artigo)
  nome_chave                  text generated always as (intelligence.texto_chave(name, true)) stored,
  propriedades                jsonb not null default '{}'::jsonb,
  sincronizado_em             timestamptz not null default now(),
  criado_em                   timestamptz not null default now(),
  atualizado_em               timestamptz not null default now()
);

comment on table crm.empresa_espelho is
  'Espelho da Company do HubSpot (todas as propriedades em `propriedades`). Mirror, nunca fonte autoral: empresa se cria e se corrige no HubSpot.';
comment on column crm.empresa_espelho.nome_chave is
  'intelligence.texto_chave(name, true): casar grafias da mesma empresa sem duplicar.';

create index if not exists empresa_espelho_nome_chave_idx on crm.empresa_espelho (nome_chave);
create index if not exists empresa_espelho_domain_idx on crm.empresa_espelho (lower(domain));

insert into crm.sync_estado (fonte, status, tabela_destino, chave_destino, registros_lidos, registros_gravados, ignorados)
values ('hubspot_empresas', 'ocioso', 'empresa_espelho', 'hubspot_company_id', 0, 0, '[]'::jsonb)
on conflict (fonte) do nothing;

create or replace function public.mind_espelho_remover_objeto(p_objeto text, p_ids text[])
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'crm'
as $function$
declare
  v_fonte text;
  v_resultado jsonb;
  v_total integer := 0;
begin
  if p_objeto not in ('contacts', 'deals', 'leads', 'companies') then
    raise exception 'objeto HubSpot desconhecido: %', p_objeto;
  end if;

  for v_fonte in
    select fonte
      from crm.sync_estado
     where (p_objeto = 'contacts' and fonte = 'hubspot_contatos')
        or (p_objeto = 'leads' and fonte = 'hubspot_leads_inbound')
        or (p_objeto = 'companies' and fonte = 'hubspot_empresas')
        or (p_objeto = 'deals' and fonte in (
          'hubspot_negocios',
          'hubspot_negocios_historicos',
          'hubspot_negocios_empenho_2026'))
  loop
    v_resultado := public.mind_espelho_remover(v_fonte, p_ids);
    v_total := v_total + coalesce((v_resultado->>'removidos')::integer, 0);
  end loop;

  return jsonb_build_object('removidos', v_total, 'objeto', p_objeto);
end;
$function$;

-- a cada 6 h, fora dos minutos dos outros espelhos
select cron.schedule('hubspot-empresas-diario', '32 */6 * * *',
  $$select public.mind_espelho_disparar('hubspot_empresas');$$)
 where not exists (select 1 from cron.job where jobname = 'hubspot-empresas-diario');
