-- A Adriana renomeou crm.summit_em_andamento para crm.pipeline_summit_leads_captados.
-- O codigo segue o nome dela, nao o contrario.
--
-- E o mapa fonte -> tabela sai do corpo da funcao e vai para crm.sync_estado:
-- proximo rename vira UPDATE, nao migration.
alter table crm.sync_estado add column if not exists tabela_destino text;
alter table crm.sync_estado add column if not exists chave_destino text;

update crm.sync_estado set tabela_destino = 'contato_espelho',               chave_destino = 'hubspot_id'      where fonte = 'hubspot_contatos';
update crm.sync_estado set tabela_destino = 'pipeline_summit_leads_captados', chave_destino = 'hubspot_deal_id' where fonte = 'hubspot_negocios';
update crm.sync_estado set tabela_destino = 'negocios_historicos',            chave_destino = 'hubspot_deal_id' where fonte = 'hubspot_negocios_historicos';

comment on column crm.sync_estado.tabela_destino is
  'Em qual tabela de crm o espelho dessa fonte e gravado. Fica aqui, e nao dentro da funcao, para que renomear a tabela seja UPDATE e nao deploy.';

create or replace function public.mind_espelho_gravar(p_fonte text, p_registros jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'crm'
as $function$
declare
  v_tabela text;
  v_chave  text;
  v_cols   text[];
  v_lista  text;
  v_sets   text;
  v_n      int;
begin
  if jsonb_typeof(p_registros) <> 'array' then
    raise exception 'p_registros precisa ser array';
  end if;
  v_n := jsonb_array_length(p_registros);
  if v_n = 0 then
    return jsonb_build_object('gravados', 0);
  end if;

  select tabela_destino, chave_destino into v_tabela, v_chave
    from crm.sync_estado where fonte = p_fonte;

  if v_tabela is null then
    raise exception 'fonte sem tabela_destino em crm.sync_estado: %', p_fonte;
  end if;

  -- So as colunas que EXISTEM na tabela E vieram no lote. O que nao veio fica
  -- como esta: sincronizacao nao apaga o que ela nao viu.
  select array_agg(distinct k order by k) into v_cols
  from jsonb_array_elements(p_registros) r,
       jsonb_object_keys(r) k
  where k in (
    select column_name from information_schema.columns
     where table_schema = 'crm' and table_name = v_tabela
       and column_name not in ('id', 'pessoa_id', 'produto_codigo', 'criado_em')
  );

  if v_cols is null or array_length(v_cols, 1) is null then
    raise exception 'lote nao trouxe nenhuma coluna conhecida de crm.%', v_tabela;
  end if;
  if not (v_chave = any(v_cols)) then
    raise exception 'lote sem a chave %', v_chave;
  end if;

  select string_agg(quote_ident(c), ', ' order by c) into v_lista from unnest(v_cols) c;
  select string_agg(format('%I = excluded.%I', c, c), ', ' order by c) into v_sets
    from unnest(v_cols) c where c <> v_chave;

  execute format(
    'insert into crm.%I (%s) select %s from jsonb_populate_recordset(null::crm.%I, $1)
      on conflict (%I) do update set %s, sincronizado_em = now(), atualizado_em = now()',
    v_tabela, v_lista, v_lista, v_tabela, v_chave, v_sets
  ) using p_registros;

  return jsonb_build_object('gravados', v_n, 'tabela', v_tabela, 'colunas', array_length(v_cols, 1));
end;
$function$;

create or replace function public.mind_espelho_ligar()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'crm', 'catalogo'
as $function$
declare
  v_contatos int := 0;
  v_neg int := 0;
  v_hist int := 0;
  v_prod int := 0;
  v_tmp int := 0;
begin
  with casado as (
    select e.id as espelho_id, min(p.id::text)::uuid as pessoa_id
    from crm.contato_espelho e
    join crm.pessoas p on lower(p.email) = lower(nullif(e.email, ''))
    where e.pessoa_id is null and nullif(e.email, '') is not null
    group by e.id having count(distinct p.id) = 1
  )
  update crm.contato_espelho e set pessoa_id = c.pessoa_id, atualizado_em = now()
  from casado c where e.id = c.espelho_id;
  get diagnostics v_contatos = row_count;

  with casado as (
    select e.id as espelho_id, min(p.id::text)::uuid as pessoa_id
    from crm.contato_espelho e
    join crm.pessoas p
      on regexp_replace(coalesce(p.whatsapp, ''), '\D', '', 'g') =
         regexp_replace(coalesce(e.hs_whatsapp_phone_number, e.phone, ''), '\D', '', 'g')
    where e.pessoa_id is null
      and length(regexp_replace(coalesce(e.hs_whatsapp_phone_number, e.phone, ''), '\D', '', 'g')) >= 10
    group by e.id having count(distinct p.id) = 1
  )
  update crm.contato_espelho e set pessoa_id = c.pessoa_id, atualizado_em = now()
  from casado c where e.id = c.espelho_id;
  get diagnostics v_tmp = row_count;
  v_contatos := v_contatos + v_tmp;

  with casado as (
    select n.id as neg_id, min(e.pessoa_id::text)::uuid as pessoa_id
    from crm.pipeline_summit_leads_captados n
    join lateral jsonb_array_elements_text(coalesce(n.propriedades->'_contatos', '[]'::jsonb)) c(hid) on true
    join crm.contato_espelho e on e.hubspot_id = c.hid and e.pessoa_id is not null
    where n.pessoa_id is null
    group by n.id having count(distinct e.pessoa_id) = 1
  )
  update crm.pipeline_summit_leads_captados n set pessoa_id = c.pessoa_id, atualizado_em = now()
  from casado c where n.id = c.neg_id;
  get diagnostics v_neg = row_count;

  with casado as (
    select n.id as neg_id, min(e.pessoa_id::text)::uuid as pessoa_id
    from crm.negocios_historicos n
    join lateral jsonb_array_elements_text(coalesce(n.propriedades->'_contatos', '[]'::jsonb)) c(hid) on true
    join crm.contato_espelho e on e.hubspot_id = c.hid and e.pessoa_id is not null
    where n.pessoa_id is null
    group by n.id having count(distinct e.pessoa_id) = 1
  )
  update crm.negocios_historicos n set pessoa_id = c.pessoa_id, atualizado_em = now()
  from casado c where n.id = c.neg_id;
  get diagnostics v_hist = row_count;

  update crm.pipeline_summit_leads_captados n
     set produto_codigo = p.codigo, atualizado_em = now()
    from catalogo.produtos p
   where n.produto_codigo is null and p.pipeline_hubspot = n.pipeline;
  get diagnostics v_prod = row_count;

  update crm.negocios_historicos n
     set produto_codigo = p.codigo, atualizado_em = now()
    from catalogo.produtos p
   where n.produto_codigo is null
     and p.codigo = 'mind-summit-' || regexp_replace(coalesce(n.summit_year, ''), '\D', '', 'g');
  get diagnostics v_tmp = row_count;
  v_prod := v_prod + v_tmp;

  return jsonb_build_object(
    'contatos_ligados', v_contatos,
    'negocios_ligados', v_neg,
    'historicos_ligados', v_hist,
    'produtos_ligados', v_prod);
end;
$function$;

revoke all on function public.mind_espelho_gravar(text, jsonb) from public, anon, authenticated;
revoke all on function public.mind_espelho_ligar() from public, anon, authenticated;