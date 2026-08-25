-- Faxina passo 4: cada produto na casa dele.
-- 15 tabelas de mecanica e comercial do Summit -> summit
--  3 que os produtos reusam                    -> comum
--  3 que sao de pessoa/captacao                -> engagement
--  1 orfa                                      -> quarentena
-- knowledge_documents/chunks/sources ficam em mind: o passo 5 parte elas por linha.
--
-- Nomes preservados de proposito. Renomear (origens -> pontos_de_entrada,
-- utm_sessoes -> atribuicao) fica para uma migration separada: 20 funcoes usam
-- nome sem qualificar e o rename tem que vir junto com a reescrita delas.

do $$
declare
  v_summit text[] := array[
    'commercial_rules','coupons','event_rules','events','exhibitors','locations',
    'offers','poll_answers','polls','registrations','route_edges',
    'session_reservations','session_speakers','sessions','venues'];
  v_comum  text[] := array['speakers','taxonomy','materiais'];
  v_eng    text[] := array['data_requests','origens','utm_sessoes'];
  v_quar   text[] := array['mechanisms'];
  t text; destino text;
begin
  foreach t in array (v_summit || v_comum || v_eng || v_quar) loop
    destino := case when t = any(v_summit) then 'summit'
                    when t = any(v_comum)  then 'comum'
                    when t = any(v_eng)    then 'engagement'
                    else 'quarentena' end;
    execute format('alter table mind.%I set schema %I', t, destino);
    execute format('create view mind.%I as select * from %I.%I', t, destino, t);
    execute format('comment on view mind.%I is %L', t,
      'COMPATIBILIDADE: a tabela mora em '||destino||'.'||t||
      '. Esta view cai na migration final da faxina.');
    if exists (select 1 from pg_roles where rolname = 'mind_agent') then
      execute format('grant select, insert, update, delete on mind.%I to mind_agent', t);
      execute format('grant select, insert, update, delete on %I.%I to mind_agent', destino, t);
    end if;
  end loop;
end $$;

comment on table quarentena.mechanisms is
  'REVISAR: 7 linhas, proposito desconhecido, nenhum agente le. Decidir o que e'' ou apagar.';

-- --------------------------------------------------------- funcoes reapontam
do $$
declare
  r record; v_def text; t text; destino text;
  v_sp text; v_lista text[]; v_novo text[]; i int; v_inseriu boolean;
  v_summit text[] := array[
    'commercial_rules','coupons','event_rules','events','exhibitors','locations',
    'offers','poll_answers','polls','registrations','route_edges',
    'session_reservations','session_speakers','sessions','venues'];
  v_comum  text[] := array['speakers','taxonomy','materiais'];
  v_eng    text[] := array['data_requests','origens','utm_sessoes'];
  -- os schemas novos entram ANTES de mind/concierge, para que o nome sem
  -- qualificar caia na TABELA e nao na view de compatibilidade: ON CONFLICT
  -- nao funciona em view auto-atualizavel.
  v_antes  text[] := array['summit','comum','engagement','intelligence'];
begin
  for r in
    select p.oid, n.nspname||'.'||p.proname as fn, p.proconfig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language l on l.oid = p.prolang
    where p.prokind = 'f'
      and l.lanname in ('sql','plpgsql')
      and n.nspname in ('public','api','concierge','treble','mind','crm')
  loop
    -- 1. referencias qualificadas mind.x viram o schema novo
    v_def := pg_get_functiondef(r.oid);
    if v_def ~ '\mmind\.' then
      foreach t in array (v_summit || v_comum || v_eng) loop
        destino := case when t = any(v_summit) then 'summit'
                        when t = any(v_comum)  then 'comum'
                        else 'engagement' end;
        v_def := regexp_replace(v_def, '\mmind\.'||t||'\M', destino||'.'||t, 'g');
      end loop;
      v_def := regexp_replace(v_def, '\mmind\.mechanisms\M', 'quarentena.mechanisms', 'g');
      execute v_def;
    end if;

    -- 2. search_path: os schemas novos entram antes de mind e de concierge
    select c into v_sp from unnest(coalesce(r.proconfig, '{}')) c where c like 'search_path=%';
    if v_sp is not null then
      v_lista := string_to_array(replace(substr(v_sp, 13), '"', ''), ',');
      v_novo := '{}'; v_inseriu := false;
      for i in 1 .. coalesce(array_length(v_lista,1),0) loop
        if not v_inseriu and btrim(v_lista[i]) in ('mind','concierge') then
          v_novo := v_novo || (select array_agg(x) from unnest(v_antes) x
                               where not (x = any(select btrim(y) from unnest(v_lista) y)));
          v_inseriu := true;
        end if;
        v_novo := v_novo || btrim(v_lista[i]);
      end loop;
      if v_inseriu then
        execute format('alter function %s(%s) set search_path = %s',
                       r.fn, pg_get_function_identity_arguments(r.oid),
                       (select string_agg(quote_ident(x), ', ') from unnest(v_novo) x));
      end if;
    end if;
  end loop;
end $$;
