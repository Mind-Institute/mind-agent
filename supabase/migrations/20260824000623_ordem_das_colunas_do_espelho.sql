-- A ordem das colunas é para quem lê a tabela.
--
-- O espelho nasceu na ordem em que o HubSpot devolve as propriedades: `email`
-- caía na posição 126, depois de 120 colunas de métrica de e-mail marketing.
-- Ninguém rola 150 colunas para achar o e-mail de um contato.
--
-- A ordem agora é: identidade, quem é a pessoa, onde ela está no funil, de onde
-- veio, o que comprou no Summit, o que fez no Institute, negócios, atividade
-- comercial, pesquisa, e-mail marketing, e por último o controle.
--
-- Postgres não reordena coluna existente. É tabela nova, cópia, troca de nome --
-- e as definições saem do catálogo, não digitadas de novo: tipo, not null e
-- default vêm da tabela que está no ar, então nada muda além da ordem.

do $$
declare
  v_ordem text[] := array[
    'id',
    'hubspot_id',
    'pessoa_id',
    'firstname',
    'lastname',
    'email',
    'phone',
    'hs_whatsapp_phone_number',
    'company',
    'jobtitle',
    'hs_linkedin_url',
    'hs_email_domain',
    'lifecyclestage',
    'hs_lead_status',
    'hubspot_owner_id',
    'lead_icp',
    'icp',
    'lead_tier',
    'produto_de_interesse',
    'intent_signals',
    'motivo_do_lead__perdido',
    'utm_campaign',
    'utm_source',
    'utm_medium',
    'utm_content',
    'utm_term',
    'msclkid',
    'li_fat_id',
    'first_conversion_date',
    'first_conversion_event_name',
    'hs_analytics_source',
    'hs_analytics_source_data_1',
    'hs_analytics_source_data_2',
    'hs_latest_source',
    'hs_latest_source_data_1',
    'hs_latest_source_data_2',
    'hs_latest_source_timestamp',
    'hs_analytics_first_referrer',
    'hs_analytics_first_url',
    'hs_analytics_first_timestamp',
    'hs_analytics_first_visit_timestamp',
    'hs_analytics_first_touch_converting_campaign',
    'hs_analytics_last_referrer',
    'hs_analytics_last_url',
    'hs_analytics_last_timestamp',
    'hs_analytics_last_visit_timestamp',
    'hs_analytics_last_touch_converting_campaign',
    'hs_analytics_average_page_views',
    'hs_analytics_num_page_views',
    'hs_analytics_num_visits',
    'hs_analytics_num_event_completions',
    'hs_analytics_revenue',
    'status_summit_2026',
    'summit__categoria_do_ingresso',
    'summit__categoria_2025',
    'summit__categoria_2026',
    'summit__categoria_do_ingresso_2027',
    'summit__tipo_entrada_2025',
    'summit__tipo_entrada_2026',
    'tipo_de_entrada',
    'summit_papel_2025',
    'summit__papel_2026',
    'summit__participacao_anual',
    'summit__cortesia_anos',
    'summit__patrocinio_anos',
    'participou_de_mais_de_um_summit',
    'total_de_summits_participados',
    'ingressos_comprados__2023',
    'ingressos_comprados__2024',
    'ingressos_comprados__2025',
    'ingressos_comprados__2026',
    'total_de_ingressos_comprados_lifetime',
    'comprou_ingressos_adicionais',
    'formacao__produtos_comprados',
    'total_de_formacoes_no_instituto',
    'concluiu_as_3_formacoes',
    'projeto_integrador_concluido',
    'formacao_1__status',
    'formacao_1__progresso',
    'formacao_1__ultimo_acesso',
    'formacao_1__enps',
    'formacao_2__status',
    'formacao_2__progresso__clonado',
    'formacao_2__ultimo_acesso',
    'formacao_2__enps',
    'formacao_3__status',
    'formacao_3__progresso',
    'formacao_3__ultimo_acesso',
    'formacao_3__enps',
    'certificacao_lideranca_positiva_comprada',
    'certificacao_lideranca_positiva_elegivel',
    'certificacao_avancada__progresso',
    'certificado_lideranca_positiva__enps',
    'num_associated_deals',
    'total_revenue',
    'recent_deal_amount',
    'recent_deal_close_date',
    'first_deal_created_date',
    'closedate',
    'days_to_close',
    'hs_buying_role',
    'notes_last_contacted',
    'notes_next_activity_date',
    'notes_last_updated',
    'num_contacted_notes',
    'num_notes',
    'message',
    'hs_last_sales_activity_timestamp',
    'hs_sales_email_last_opened',
    'hs_sales_email_last_clicked',
    'hs_sales_email_last_replied',
    'hs_sequences_is_enrolled',
    'engagements_last_meeting_booked',
    'engagements_last_meeting_booked_campaign',
    'engagements_last_meeting_booked_medium',
    'engagements_last_meeting_booked_source',
    'hs_feedback_last_nps_rating',
    'hs_feedback_last_nps_follow_up',
    'hs_feedback_last_ces_survey_rating',
    'hs_feedback_last_ces_survey_follow_up',
    'hs_feedback_last_ces_survey_date',
    'hs_feedback_last_survey_date',
    'hs_content_membership_status',
    'hs_content_membership_notes',
    'hs_emailconfirmationstatus',
    'hs_email_bad_address',
    'hs_email_optout',
    'hs_email_quarantined',
    'hs_email_quarantined_reason',
    'hs_email_customer_quarantined_reason',
    'hs_quarantined_emails',
    'hs_email_hard_bounce_reason_enum',
    'hs_legal_basis',
    'hs_email_optout_1701138329',
    'hs_email_optout_1701138330',
    'hs_email_optout_1702074925',
    'hs_email_optout_3137279076',
    'hs_email_type',
    'hs_email_delivered',
    'hs_email_bounce',
    'hs_email_open',
    'hs_email_click',
    'hs_email_replied',
    'hs_email_sends_since_last_engagement',
    'hs_email_first_send_date',
    'hs_email_first_open_date',
    'hs_email_first_click_date',
    'hs_email_first_reply_date',
    'hs_email_last_send_date',
    'hs_email_last_open_date',
    'hs_email_last_click_date',
    'hs_email_last_reply_date',
    'hs_email_last_email_name',
    'propriedades',
    'sincronizado_em',
    'criado_em',
    'atualizado_em'
  ];
  v_cols  text;
  v_lista text;
  v_faltando text;
  v_velho bigint;
  v_novo  bigint;
begin
  -- Trava: a lista tem que ser exatamente as colunas de hoje. Se alguém criou
  -- coluna nova entre escrever e rodar isto, a migration para aqui em vez de
  -- copiar a tabela pela metade.
  select string_agg(nome, ', ') into v_faltando
  from (
    select a.attname as nome from pg_attribute a
     where a.attrelid = 'crm.contato_espelho'::regclass
       and a.attnum > 0 and not a.attisdropped
    except
    select unnest(v_ordem)
  ) x;
  if v_faltando is not null then
    raise exception 'coluna fora da nova ordem: %', v_faltando;
  end if;

  select string_agg(
           format('%I %s%s%s',
             a.attname,
             format_type(a.atttypid, a.atttypmod),
             case when a.attnotnull then ' not null' else '' end,
             case when d.adbin is not null
                  then ' default ' || pg_get_expr(d.adbin, d.adrelid) else '' end),
           E',\n  ' order by o.ord)
    into v_cols
  from unnest(v_ordem) with ordinality o(nome, ord)
  join pg_attribute a
    on a.attrelid = 'crm.contato_espelho'::regclass and a.attname = o.nome
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum;

  select string_agg(format('%I', nome), ', ' order by ord)
    into v_lista from unnest(v_ordem) with ordinality t(nome, ord);

  execute format('create table crm.contato_espelho_novo (%s)', v_cols);
  execute format(
    'insert into crm.contato_espelho_novo (%s) select %s from crm.contato_espelho',
    v_lista, v_lista);

  -- Confere a cópia antes de destruir o original.
  select count(*) into v_velho from crm.contato_espelho;
  select count(*) into v_novo  from crm.contato_espelho_novo;
  if v_velho <> v_novo then
    raise exception 'cópia incompleta: % linhas viraram %', v_velho, v_novo;
  end if;
end $$;

drop table crm.contato_espelho;
alter table crm.contato_espelho_novo rename to contato_espelho;

alter table crm.contato_espelho add primary key (id);
alter table crm.contato_espelho
  add constraint contato_espelho_hubspot_id_key unique (hubspot_id);
alter table crm.contato_espelho
  add constraint contato_espelho_pessoa_id_fkey
  foreign key (pessoa_id) references crm.pessoas(id) on delete cascade;

create index contato_espelho_pessoa_idx on crm.contato_espelho (pessoa_id);
create index contato_espelho_email_idx  on crm.contato_espelho (lower(email));
create index contato_espelho_phone_idx  on crm.contato_espelho (phone);
create index contato_espelho_props_idx  on crm.contato_espelho using gin (propriedades jsonb_path_ops);

comment on column crm.contato_espelho.propriedades is
  'O registro cru do contato no HubSpot, inteiro. Consulta: propriedades->>''lead_score_summit_26''. As colunas tipadas ao lado sao as que os agentes usam de verdade -- estas aqui existem para nada se perder e nada quebrar.';


-- O negócio do pipeline de leads segue a mesma regra: nome, valor, estágio e
-- dono logo depois da identidade. Hoje `dealname` vem depois de duas datas e
-- `amount` depois de oito colunas -- é a mesma tabela ilegível, em versão menor.
do $$
declare
  v_ordem text[] := array[
    'id', 'hubspot_deal_id', 'pessoa_id', 'produto_codigo',
    'dealname', 'amount', 'dealstage', 'hubspot_owner_id', 'pipeline',
    'hs_is_closed', 'hs_is_closed_lost', 'hs_deal_stage_probability',
    'hs_forecast_amount', 'quantidade_ingressos', 'produto',
    'temperatura', 'lead_b2c_ou_b2b', 'origem_do_lead',
    'createdate', 'hs_v2_date_entered_current_stage', 'hubspot_owner_assigneddate',
    'notes_last_updated', 'num_notes', 'num_associated_contacts',
    'hs_updated_by_user_id', 'hs_lastmodifieddate',
    'propriedades', 'sincronizado_em', 'criado_em', 'atualizado_em'
  ];
  v_cols text; v_lista text; v_faltando text; v_velho bigint; v_novo bigint;
begin
  select string_agg(nome, ', ') into v_faltando
  from (
    select a.attname as nome from pg_attribute a
     where a.attrelid = 'crm.pipeline_summit_leads_captados'::regclass
       and a.attnum > 0 and not a.attisdropped
    except select unnest(v_ordem)
  ) x;
  if v_faltando is not null then
    raise exception 'coluna fora da nova ordem: %', v_faltando;
  end if;

  select string_agg(
           format('%I %s%s%s', a.attname, format_type(a.atttypid, a.atttypmod),
             case when a.attnotnull then ' not null' else '' end,
             case when d.adbin is not null
                  then ' default ' || pg_get_expr(d.adbin, d.adrelid) else '' end),
           E',\n  ' order by o.ord)
    into v_cols
  from unnest(v_ordem) with ordinality o(nome, ord)
  join pg_attribute a
    on a.attrelid = 'crm.pipeline_summit_leads_captados'::regclass and a.attname = o.nome
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum;

  select string_agg(format('%I', nome), ', ' order by ord)
    into v_lista from unnest(v_ordem) with ordinality t(nome, ord);

  execute format('create table crm.pipeline_summit_leads_captados_novo (%s)', v_cols);
  execute format('insert into crm.pipeline_summit_leads_captados_novo (%s) select %s from crm.pipeline_summit_leads_captados', v_lista, v_lista);

  select count(*) into v_velho from crm.pipeline_summit_leads_captados;
  select count(*) into v_novo  from crm.pipeline_summit_leads_captados_novo;
  if v_velho <> v_novo then
    raise exception 'cópia incompleta: % linhas viraram %', v_velho, v_novo;
  end if;
end $$;

drop table crm.pipeline_summit_leads_captados;
alter table crm.pipeline_summit_leads_captados_novo rename to pipeline_summit_leads_captados;

alter table crm.pipeline_summit_leads_captados add primary key (id);
alter table crm.pipeline_summit_leads_captados
  add constraint pipeline_summit_leads_captados_hubspot_deal_id_key unique (hubspot_deal_id);
alter table crm.pipeline_summit_leads_captados
  add constraint pipeline_summit_leads_captados_pessoa_id_fkey
  foreign key (pessoa_id) references crm.pessoas(id) on delete set null;
alter table crm.pipeline_summit_leads_captados
  add constraint pipeline_summit_leads_captados_produto_codigo_fkey
  foreign key (produto_codigo) references catalogo.produtos(codigo);

create index pipeline_summit_leads_pessoa_pipeline_idx
  on crm.pipeline_summit_leads_captados (pessoa_id, pipeline);
-- O índice que o agente usa: dada uma pessoa, ela tem negócio ABERTO?
create index pipeline_summit_leads_abertos_idx
  on crm.pipeline_summit_leads_captados (pessoa_id) where hs_is_closed is not true;
create index pipeline_summit_leads_props_idx
  on crm.pipeline_summit_leads_captados using gin (propriedades jsonb_path_ops);

comment on column crm.pipeline_summit_leads_captados.propriedades is
  'O registro cru do negocio no HubSpot, inteiro. Mesma regra do contato.';


-- O histórico já estava quase na ordem certa. O que muda: a compra (categoria,
-- lote, valor, pagamento) vem antes do encanamento, e `propriedades` volta para
-- o começo do bloco de controle, antes dos timestamps.
do $$
declare
  v_ordem text[] := array[
    'id', 'hubspot_deal_id', 'pessoa_id', 'produto_codigo',
    'dealname', 'produto', 'summit_year', 'summit_categoria', 'summit_lote',
    'quantidade_ingressos', 'tipo_de_acesso', 'tipo_de_venda', 'modalidade_comercial',
    'amount_in_home_currency', 'valor_com_juros', 'valor_do_desconto',
    'cupom_utilizado', 'numero_parcelas', 'metodo_pagamento', 'bandeira_cartao',
    'status_de_pagamento', 'data_da_compra', 'data_do_pagamento',
    'houve_reembolso', 'valor_reembolsado', 'data_reembolso', 'houve_upgrade',
    'pipeline', 'hs_is_closed', 'hs_closed_won_count', 'hs_is_closed_count',
    'hs_deal_stage_probability', 'num_associated_contacts',
    'id_da_compra', 'mind_deal_id', 'eduzz_product_id',
    'hs_analytics_source', 'hs_analytics_source_data_1', 'hs_analytics_source_data_2',
    'hs_analytics_latest_source', 'hs_analytics_latest_source_data_1',
    'hs_analytics_latest_source_data_2', 'hs_analytics_latest_source_timestamp',
    'hs_lastmodifieddate',
    'propriedades', 'sincronizado_em', 'criado_em', 'atualizado_em'
  ];
  v_cols text; v_lista text; v_faltando text; v_velho bigint; v_novo bigint;
begin
  select string_agg(nome, ', ') into v_faltando
  from (
    select a.attname as nome from pg_attribute a
     where a.attrelid = 'crm.negocios_historicos'::regclass
       and a.attnum > 0 and not a.attisdropped
    except select unnest(v_ordem)
  ) x;
  if v_faltando is not null then
    raise exception 'coluna fora da nova ordem: %', v_faltando;
  end if;

  select string_agg(
           format('%I %s%s%s', a.attname, format_type(a.atttypid, a.atttypmod),
             case when a.attnotnull then ' not null' else '' end,
             case when d.adbin is not null
                  then ' default ' || pg_get_expr(d.adbin, d.adrelid) else '' end),
           E',\n  ' order by o.ord)
    into v_cols
  from unnest(v_ordem) with ordinality o(nome, ord)
  join pg_attribute a
    on a.attrelid = 'crm.negocios_historicos'::regclass and a.attname = o.nome
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum;

  select string_agg(format('%I', nome), ', ' order by ord)
    into v_lista from unnest(v_ordem) with ordinality t(nome, ord);

  execute format('create table crm.negocios_historicos_novo (%s)', v_cols);
  execute format('insert into crm.negocios_historicos_novo (%s) select %s from crm.negocios_historicos', v_lista, v_lista);

  select count(*) into v_velho from crm.negocios_historicos;
  select count(*) into v_novo  from crm.negocios_historicos_novo;
  if v_velho <> v_novo then
    raise exception 'cópia incompleta: % linhas viraram %', v_velho, v_novo;
  end if;
end $$;

drop table crm.negocios_historicos;
alter table crm.negocios_historicos_novo rename to negocios_historicos;

alter table crm.negocios_historicos add primary key (id);
alter table crm.negocios_historicos
  add constraint negocios_historicos_hubspot_deal_id_key unique (hubspot_deal_id);
alter table crm.negocios_historicos
  add constraint negocios_historicos_pessoa_id_fkey
  foreign key (pessoa_id) references crm.pessoas(id) on delete set null;
alter table crm.negocios_historicos
  add constraint negocios_historicos_produto_codigo_fkey
  foreign key (produto_codigo) references catalogo.produtos(codigo);

create index negocios_hist_pessoa_idx on crm.negocios_historicos (pessoa_id);
create index negocios_hist_ano_idx    on crm.negocios_historicos (pessoa_id, summit_year);
create index negocios_hist_props_idx  on crm.negocios_historicos using gin (propriedades jsonb_path_ops);

comment on column crm.negocios_historicos.propriedades is
  'O registro cru do negocio no HubSpot, inteiro. Mesma regra do contato.';

