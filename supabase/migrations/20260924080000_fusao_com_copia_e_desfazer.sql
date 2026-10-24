-- Fusão de pessoas com cópia completa e desfazer (Adriana, 24/09/2026 — passo 11).
--
-- A Adriana autorizou fundir duplicatas pela recomendação, desde que tudo possa ser desfeito. A fusão
-- continua pela porta de sempre (mind_fusao_decidir → mind_pessoa_fundir); o que muda é o antes e o depois:
--   mind_fusao_snapshot(sobrevive, absorvida): grava em mind_admin_audit (resource 'fusao_snapshot') as
--     duas linhas de pessoas.pessoas e TODAS as linhas de todas as tabelas que apontam para a absorvida
--     (a fusão move essas linhas e, quando há conflito de chave, apaga a repetida — a cópia guarda ambas).
--   mind_fusao_aprovar_com_copia(fusao_id, quem): tira a cópia e aprova a proposta pendente.
--   mind_fusao_desfazer(absorvida, quem): devolve cada linha à absorvida (reinsere as apagadas), restaura
--     os campos da absorvida, desfaz na sobrevivente só o que a fusão preencheu e reabre a proposta.
-- Nenhuma tabela nova: a cópia mora em mind_admin_audit.

create or replace function public.mind_fusao_snapshot(p_sobrevive uuid, p_absorvida uuid)
returns uuid language plpgsql security definer set search_path to 'public', 'pessoas', 'engagement'
as $$
declare fk record; v_rows jsonb; v_linhas jsonb := '[]'::jsonb; v_id uuid := gen_random_uuid();
begin
  for fk in
    select con.conrelid::regclass tab, a.attname col,
           (select coalesce(jsonb_agg(pa.attname order by pa.attnum), '[]'::jsonb)
              from pg_index i join pg_attribute pa on pa.attrelid = i.indrelid and pa.attnum = any(i.indkey)
             where i.indrelid = con.conrelid and i.indisprimary) pk
      from pg_constraint con join pg_attribute a on a.attrelid = con.conrelid and a.attnum = any(con.conkey)
     where con.contype = 'f' and con.confrelid = 'pessoas.pessoas'::regclass and con.conrelid <> 'pessoas.pessoas'::regclass
  loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from %s t where %I = $1', fk.tab, fk.col)
      into v_rows using p_absorvida;
    if jsonb_array_length(v_rows) > 0 then
      v_linhas := v_linhas || jsonb_build_array(jsonb_build_object('tabela', fk.tab::text, 'coluna', fk.col, 'pk', fk.pk, 'linhas', v_rows));
    end if;
  end loop;
  insert into public.mind_admin_audit (id, action, resource, record_id, record_label, before_data, after_data, request_id)
  values (v_id, 'atualizar', 'fusao_snapshot', p_absorvida::text, 'cópia antes de fundir (para desfazer)',
          jsonb_build_object('sobrevive', (select to_jsonb(p) from pessoas.pessoas p where p.id = p_sobrevive),
                             'absorvida', (select to_jsonb(p) from pessoas.pessoas p where p.id = p_absorvida)),
          jsonb_build_object('sobrevive_id', p_sobrevive, 'absorvida_id', p_absorvida, 'linhas', v_linhas),
          gen_random_uuid());
  return v_id;
end $$;

create or replace function public.mind_fusao_aprovar_com_copia(p_fusao_id uuid, p_quem text)
returns jsonb language plpgsql security definer set search_path to 'public', 'engagement', 'pessoas'
as $$
declare f engagement.identidade_fusoes%rowtype; v_snap uuid; v_r jsonb;
begin
  select * into f from engagement.identidade_fusoes where id = p_fusao_id and status = 'pendente' and proposta is not null;
  if f.id is null then return jsonb_build_object('ok', false, 'motivo', 'proposta_nao_pendente'); end if;
  -- par já fundido (proposta repetida): não tira cópia, só deixa a porta registrar
  if not exists (select 1 from pessoas.pessoas p where p.id = (f.proposta->>'absorvida')::uuid and p.fundida_em is not null) then
    v_snap := public.mind_fusao_snapshot((f.proposta->>'sobrevive')::uuid, (f.proposta->>'absorvida')::uuid);
  end if;
  v_r := public.mind_fusao_decidir(p_fusao_id::text, 'aprovar', p_quem);
  return jsonb_build_object('ok', (v_r->>'fundidas')::int = 1, 'snapshot', v_snap, 'resultado', v_r);
end $$;

create or replace function public.mind_fusao_desfazer(p_absorvida uuid, p_quem text)
returns jsonb language plpgsql security definer set search_path to 'public', 'engagement', 'pessoas'
as $$
declare
  s record; t jsonb; r jsonb; v_sob uuid; v_abs_antes jsonb; v_sob_antes jsonb; v_pk text[]; v_where text; v_cols text;
  v_voltaram int := 0; v_reinseridas int := 0; v_n int; c text;
begin
  -- a cópia de ANTES da fusão (uma aprovação repetida do mesmo par não tira cópia, mas cópias antigas podem existir)
  select * into s from public.mind_admin_audit
   where resource = 'fusao_snapshot' and record_id = p_absorvida::text
     and before_data->'absorvida'->>'fundida_em' is null
   order by occurred_at desc limit 1;
  if s.id is null then return jsonb_build_object('ok', false, 'motivo', 'sem_copia'); end if;
  v_sob := (s.after_data->>'sobrevive_id')::uuid;
  v_abs_antes := s.before_data->'absorvida';
  v_sob_antes := s.before_data->'sobrevive';

  perform set_config('mind.d5_pular_trigger', '1', true);  -- devolver linhas não é nova escrita de pessoa

  for t in select * from jsonb_array_elements(s.after_data->'linhas') loop
    v_pk := array(select jsonb_array_elements_text(t->'pk'));
    select string_agg(format('%I', k), ', ') into v_cols
      from jsonb_object_keys((t->'linhas')->0) k
     where exists (select 1 from pg_attribute a where a.attrelid = (t->>'tabela')::regclass and a.attname = k
                    and a.attnum > 0 and not a.attisdropped and a.attgenerated = '');
    for r in select * from jsonb_array_elements(t->'linhas') loop
      if cardinality(v_pk) > 0 then
        select string_agg(format('%I = (jsonb_populate_record(null::%s, $1)).%I', k, t->>'tabela', k), ' and ')
          into v_where from unnest(v_pk) k;
      else
        -- sem chave primária: a mesma linha, só que apontando para a sobrevivente
        select string_agg(format('%I is not distinct from (jsonb_populate_record(null::%s, $1)).%I', a.attname, t->>'tabela', a.attname), ' and ')
          into v_where
          from pg_attribute a
         where a.attrelid = (t->>'tabela')::regclass and a.attnum > 0 and not a.attisdropped
           and a.attname <> (t->>'coluna') and format_type(a.atttypid, a.atttypmod) not in ('json', 'xml');
        v_where := v_where || format(' and %I = %L', t->>'coluna', v_sob);
        v_where := format('ctid = (select ctid from %s where %s limit 1)', t->>'tabela', v_where);
      end if;
      -- a linha volta inteira ao que era antes da fusão
      execute format('update %s set (%s) = (select %s from jsonb_populate_record(null::%s, $1)) where %s',
                     t->>'tabela', v_cols, v_cols, t->>'tabela', v_where) using r;
      get diagnostics v_n = row_count;
      if v_n > 0 then
        v_voltaram := v_voltaram + v_n;
      else
        execute format('insert into %s (%s) select %s from jsonb_populate_record(null::%s, $1)',
                       t->>'tabela', v_cols, v_cols, t->>'tabela') using r;
        v_reinseridas := v_reinseridas + 1;
      end if;
    end loop;
  end loop;

  -- na sobrevivente, só o que a fusão preencheu (estava vazio na cópia e hoje é o valor da absorvida)
  foreach c in array array['primeiro_nome', 'sobrenome', 'empresa', 'cargo', 'email', 'whatsapp', 'hubspot_id'] loop
    if v_sob_antes->>c is null then
      execute format('update pessoas.pessoas set %I = null where id = $1 and %I is not distinct from $2', c, c)
        using v_sob, v_abs_antes->>c;
    end if;
  end loop;
  -- depois de soltar na sobrevivente o que era da absorvida (e-mail, telefone, hubspot são únicos)
  update pessoas.pessoas set
         email = v_abs_antes->>'email', whatsapp = v_abs_antes->>'whatsapp', hubspot_id = v_abs_antes->>'hubspot_id',
         fundida_em = null, fundida_quando = null, atualizado_em = now()
   where id = p_absorvida;

  perform set_config('mind.d5_pular_trigger', '', true);

  insert into public.mind_admin_audit (action, resource, record_id, record_label, before_data, after_data, request_id)
  values ('atualizar', 'fusao_desfeita', p_absorvida::text, 'fusão desfeita por ' || coalesce(p_quem, '?'),
          jsonb_build_object('snapshot', s.id), jsonb_build_object('sobrevive', v_sob, 'voltaram', v_voltaram, 'reinseridas', v_reinseridas),
          gen_random_uuid());
  return jsonb_build_object('ok', true, 'sobrevive', v_sob, 'absorvida', p_absorvida, 'voltaram', v_voltaram, 'reinseridas', v_reinseridas);
end $$;

revoke all on function public.mind_fusao_snapshot(uuid, uuid) from public, anon, authenticated;
revoke all on function public.mind_fusao_aprovar_com_copia(uuid, text) from public, anon, authenticated;
revoke all on function public.mind_fusao_desfazer(uuid, text) from public, anon, authenticated;
