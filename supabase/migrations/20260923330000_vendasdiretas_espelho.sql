-- Vendas diretas: vendas feitas por fora da Eduzz e dos meios de pagamento.
-- Decisão da Adriana (23/09/2026): schema novo `vendasdiretas`; `vendasdiretas.espelho` copia
-- public.receitas do projeto mind-summit-vendas-dashboard (tkludhksqcnhhpgqyfqq), sem
-- comissionado_id, comissao_pct, comissao_valor e vendedor_id (cortados na porta da origem,
-- `espelho_para_mind` fonte 'receitas'); ganha mind_id pela porta única (Regra #1 / D5) a partir de
-- contato_email; atualiza uma vez por dia (cron `vendasdiretas_espelho_diario` → eduzz-espelho-sync).

create schema if not exists vendasdiretas;
comment on schema vendasdiretas is
  'Vendas feitas por fora da Eduzz e dos meios de pagamento (venda direta, empenho, NF). Espelho do projeto mind-summit-vendas-dashboard; nunca fonte autoral.';

create table if not exists vendasdiretas.espelho (
  id                     uuid primary key,
  nome                   text,
  tipo                   text,
  pagador                text,
  moeda                  text,
  forma_recebimento      text,
  categoria_id           uuid,
  valor_total            numeric,
  valor_recebido         numeric,
  periodicidade          text,
  ultimo_recebimento     date,
  proximo_recebimento    date,
  created_at             timestamptz,
  qtd_ingressos          integer,
  ingressos_dist         jsonb,
  valor_mercado          numeric,
  desconto_pct           numeric,
  emissao_ordem          text,
  ingressos_emitidos_em  date,
  empenho_recebido_em    date,
  contato_empresa        text,
  cnpj                   text,
  participantes          text,
  nf_numero              text,
  institute_dist         jsonb,
  data_venda             date,
  contato_whatsapp       text,
  contato_email          text,
  venda_direta           boolean,
  observacao             text,
  vd_external_id         text,
  vd_evento              text,
  vd_enviado_em          timestamptz,
  vd_req_id              bigint,
  criado_por             text,
  editado_por            text,
  editado_em             timestamptz,
  comprador_nome         text,
  razao_social           text,
  endereco_empresa       text,
  nf_situacao            text,
  nf_emitir_em           date,
  empresa                text,
  vd_fechada             boolean,
  sincronizado_em        timestamptz not null default now()
);
comment on table vendasdiretas.espelho is
  'Espelho diário de public.receitas (mind-summit-vendas-dashboard). Sem comissão nem vendedor. mind_id resolvido por contato_email. Mirror: editar na origem, nunca aqui.';

alter table vendasdiretas.espelho enable row level security;
revoke all on schema vendasdiretas from public, anon, authenticated;
revoke all on all tables in schema vendasdiretas from public, anon, authenticated;
grant usage on schema vendasdiretas to service_role;
grant all on vendasdiretas.espelho to service_role;

-- Regra #1: a pessoa da linha é o contato da venda, reconhecida pelo e-mail.
select public.mind_pessoa_ligar_tabela('vendasdiretas.espelho', '{"emails":["contato_email"]}');

insert into public.espelho_estado (fonte, projeto_origem, destino)
values ('receitas', 'vendas', 'vendasdiretas.espelho')
on conflict do nothing;

-- espelho_gravar: + fonte 'receitas' (upsert por id, para o mind_id não ser re-resolvido do zero).
CREATE OR REPLACE FUNCTION public.espelho_gravar(p_fonte text, p_linhas jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'eduzz', 'credenciamento_summit_2026', 'pessoas', 'engagement'
AS $function$
declare v_n integer := 0;
begin
  if p_linhas is null or jsonb_array_length(p_linhas) = 0 then
    return 0;
  end if;

  -- --- Eduzz: bilheteria e vendas (nomes de coluna diferem da origem) -------
  if p_fonte = 'blinket' then
    delete from eduzz.ingressos
     where uuid in (select l->>'uuid' from jsonb_array_elements(p_linhas) l);
    insert into eduzz.ingressos
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::eduzz.ingressos,
        (l - 'e_mail' - 'e_mail_comprador' - 'criado_em' - 'atualizado_em')
        || jsonb_build_object(
             'email',                l->>'e_mail',
             'email_comprador',      l->>'e_mail_comprador',
             'origem_criado_em',     l->>'criado_em',
             'origem_atualizado_em', l->>'atualizado_em',
             'sincronizado_em',      now())) r
     where l->>'uuid' is not null;

  elsif p_fonte = 'vendas' then
    delete from eduzz.vendas
     where linha_origem in (select (l->>'linha_origem')::integer from jsonb_array_elements(p_linhas) l
                             where l->>'linha_origem' is not null);
    insert into eduzz.vendas
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::eduzz.vendas,
        (l - 'cliente_e_mail' - 'importado_em')
        || jsonb_build_object(
             'cliente_email',       l->>'cliente_e_mail',
             'origem_importado_em', l->>'importado_em',
             'sincronizado_em',     now())) r
     where l->>'linha_origem' is not null;

  -- --- daqui pra baixo os nomes batem: so injeta o carimbo -------------------
  elsif p_fonte = 'produtos' then
    delete from eduzz.produtos
     where eduzz_product_id in (select l->>'eduzz_product_id' from jsonb_array_elements(p_linhas) l);
    insert into eduzz.produtos
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::eduzz.produtos,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'eduzz_product_id' is not null;

  elsif p_fonte = 'produto_catalogo' then
    delete from eduzz.produto_catalogo
     where id in (select (l->>'id')::uuid from jsonb_array_elements(p_linhas) l where l->>'id' is not null);
    insert into eduzz.produto_catalogo
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::eduzz.produto_catalogo,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'id' is not null;

  elsif p_fonte = 'hubspot_stage_config' then
    delete from eduzz.hubspot_stage_config h
     where exists (select 1 from jsonb_array_elements(p_linhas) l
                    where l->>'hubspot_pipeline_id' = h.hubspot_pipeline_id
                      and l->>'evento_eduzz'        = h.evento_eduzz);
    insert into eduzz.hubspot_stage_config
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::eduzz.hubspot_stage_config,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'hubspot_pipeline_id' is not null and l->>'evento_eduzz' is not null;

  -- --- Credenciamento Summit 2026 -------------------------------------------
  elsif p_fonte = 'cred_participantes' then
    delete from credenciamento_summit_2026.participantes
     where id in (select (l->>'id')::uuid from jsonb_array_elements(p_linhas) l where l->>'id' is not null);
    insert into credenciamento_summit_2026.participantes
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::credenciamento_summit_2026.participantes,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'id' is not null;

  elsif p_fonte = 'cred_yazo_fila' then
    delete from credenciamento_summit_2026.yazo_envio_fila
     where id in (select (l->>'id')::uuid from jsonb_array_elements(p_linhas) l where l->>'id' is not null);
    insert into credenciamento_summit_2026.yazo_envio_fila
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::credenciamento_summit_2026.yazo_envio_fila,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'id' is not null;

  elsif p_fonte = 'cred_yazo_espelho' then
    delete from credenciamento_summit_2026.yazo_espelho
     where yazo_id in (select (l->>'yazo_id')::bigint from jsonb_array_elements(p_linhas) l
                        where l->>'yazo_id' is not null);
    insert into credenciamento_summit_2026.yazo_espelho
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::credenciamento_summit_2026.yazo_espelho,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'yazo_id' is not null;

  elsif p_fonte = 'cred_yazo_sync_state' then
    delete from credenciamento_summit_2026.yazo_sync_state
     where id in (select (l->>'id')::integer from jsonb_array_elements(p_linhas) l where l->>'id' is not null);
    insert into credenciamento_summit_2026.yazo_sync_state
    select r.* from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::credenciamento_summit_2026.yazo_sync_state,
        l || jsonb_build_object('sincronizado_em', now())) r
     where l->>'id' is not null;

  -- --- Vendas diretas --------------------------------------------------------
  -- Upsert por id; o trigger zz_d5_pessoa_antes_de_escrever resolve o mind_id pelo contato_email.
  elsif p_fonte = 'receitas' then
    insert into vendasdiretas.espelho as e (
      id, nome, tipo, pagador, moeda, forma_recebimento, categoria_id, valor_total, valor_recebido,
      periodicidade, ultimo_recebimento, proximo_recebimento, created_at, qtd_ingressos, ingressos_dist,
      valor_mercado, desconto_pct, emissao_ordem, ingressos_emitidos_em, empenho_recebido_em,
      contato_empresa, cnpj, participantes, nf_numero, institute_dist, data_venda, contato_whatsapp,
      contato_email, venda_direta, observacao, vd_external_id, vd_evento, vd_enviado_em, vd_req_id,
      criado_por, editado_por, editado_em, comprador_nome, razao_social, endereco_empresa, nf_situacao,
      nf_emitir_em, empresa, vd_fechada, sincronizado_em)
    select
      r.id, r.nome, r.tipo, r.pagador, r.moeda, r.forma_recebimento, r.categoria_id, r.valor_total, r.valor_recebido,
      r.periodicidade, r.ultimo_recebimento, r.proximo_recebimento, r.created_at, r.qtd_ingressos, r.ingressos_dist,
      r.valor_mercado, r.desconto_pct, r.emissao_ordem, r.ingressos_emitidos_em, r.empenho_recebido_em,
      r.contato_empresa, r.cnpj, r.participantes, r.nf_numero, r.institute_dist, r.data_venda, r.contato_whatsapp,
      r.contato_email, r.venda_direta, r.observacao, r.vd_external_id, r.vd_evento, r.vd_enviado_em, r.vd_req_id,
      r.criado_por, r.editado_por, r.editado_em, r.comprador_nome, r.razao_social, r.endereco_empresa, r.nf_situacao,
      r.nf_emitir_em, r.empresa, r.vd_fechada, now()
    from jsonb_array_elements(p_linhas) l
      cross join lateral jsonb_populate_record(null::vendasdiretas.espelho, l) r
    where l->>'id' is not null
    on conflict (id) do update set
      nome = excluded.nome, tipo = excluded.tipo, pagador = excluded.pagador, moeda = excluded.moeda,
      forma_recebimento = excluded.forma_recebimento, categoria_id = excluded.categoria_id,
      valor_total = excluded.valor_total, valor_recebido = excluded.valor_recebido,
      periodicidade = excluded.periodicidade, ultimo_recebimento = excluded.ultimo_recebimento,
      proximo_recebimento = excluded.proximo_recebimento, created_at = excluded.created_at,
      qtd_ingressos = excluded.qtd_ingressos, ingressos_dist = excluded.ingressos_dist,
      valor_mercado = excluded.valor_mercado, desconto_pct = excluded.desconto_pct,
      emissao_ordem = excluded.emissao_ordem, ingressos_emitidos_em = excluded.ingressos_emitidos_em,
      empenho_recebido_em = excluded.empenho_recebido_em, contato_empresa = excluded.contato_empresa,
      cnpj = excluded.cnpj, participantes = excluded.participantes, nf_numero = excluded.nf_numero,
      institute_dist = excluded.institute_dist, data_venda = excluded.data_venda,
      contato_whatsapp = excluded.contato_whatsapp, contato_email = excluded.contato_email,
      venda_direta = excluded.venda_direta, observacao = excluded.observacao,
      vd_external_id = excluded.vd_external_id, vd_evento = excluded.vd_evento,
      vd_enviado_em = excluded.vd_enviado_em, vd_req_id = excluded.vd_req_id,
      criado_por = excluded.criado_por, editado_por = excluded.editado_por, editado_em = excluded.editado_em,
      comprador_nome = excluded.comprador_nome, razao_social = excluded.razao_social,
      endereco_empresa = excluded.endereco_empresa, nf_situacao = excluded.nf_situacao,
      nf_emitir_em = excluded.nf_emitir_em, empresa = excluded.empresa, vd_fechada = excluded.vd_fechada,
      sincronizado_em = now();

  else
    raise exception 'fonte desconhecida: %', p_fonte;
  end if;

  get diagnostics v_n = row_count;
  return v_n;
end $function$;

-- Uma vez por dia (06:45 UTC = 03:45 em Brasília), só a fonte 'receitas'.
select cron.schedule('vendasdiretas_espelho_diario', '45 6 * * *', $cron$
  select net.http_post(
    url := 'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/eduzz-espelho-sync?token='
           || (select valor from intelligence.config where chave='analise_token'),
    body := '{"fontes":["receitas"]}'::jsonb,
    headers := '{"Content-Type":"application/json"}'::jsonb,
    timeout_milliseconds := 150000);
$cron$);
