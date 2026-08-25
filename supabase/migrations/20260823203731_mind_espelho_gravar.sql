-- Gravacao generica do espelho do HubSpot.
--
-- A Edge Function nao sabe quais colunas existem: ela manda o registro inteiro e
-- ESTA funcao decide. O que casa com uma coluna tipada vira coluna; o resto ja
-- veio dentro de `propriedades`. Coluna nova passa a ser preenchida sozinha, sem
-- tocar no codigo da funcao -- que e a razao de a Adriana ter escolhido a opcao B.
--
-- Uma instrucao por lote, nao uma por registro: jsonb_populate_recordset ignora
-- chave que nao e coluna e preenche com null a coluna que nao veio.
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

  select t, c into v_tabela, v_chave from (values
    ('hubspot_contatos',            'contato_espelho',     'hubspot_id'),
    ('hubspot_negocios',            'summit_em_andamento', 'hubspot_deal_id'),
    ('hubspot_negocios_historicos', 'negocios_historicos', 'hubspot_deal_id')
  ) as m(f, t, c) where m.f = p_fonte;

  if v_tabela is null then
    raise exception 'fonte desconhecida: %', p_fonte;
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

comment on function public.mind_espelho_gravar(text, jsonb) is
  'Grava um lote do HubSpot no espelho. A funcao descobre sozinha quais chaves do registro sao colunas tipadas -- coluna nova passa a ser preenchida sem mudar codigo. O registro inteiro ja vem em propriedades. Nao apaga coluna que o lote nao trouxe.';

revoke all on function public.mind_espelho_gravar(text, jsonb) from public, anon, authenticated;
