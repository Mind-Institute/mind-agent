drop table if exists public._faxina_check;

-- Faxina passo 3: o concierge deixa de ser dono do dado.
-- 15 tabelas de pessoa/conversa/feedback -> engagement
-- 10 de inferencia e governanca          -> intelligence
--  1 de vocabulario                      -> comum
-- Ficam 16 no concierge: config, prompts, ferramentas, filas, flags e os
-- casos de teste do agente (avaliacoes, avaliacao_execucoes, intencoes).

-- ------------------------------------------------------------------------
-- Conserto pre-requisito: concierge.resumo_do_dia ja estava quebrada.
-- Ela le "agenda_sessoes", que foi renomeada para mind.sessions ha tempos
-- (os indices ainda carregam o nome velho: mind.agenda_sessoes_pkey).
-- Sem consertar, o CREATE OR REPLACE do passo seguinte nao valida.
-- ------------------------------------------------------------------------
do $$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'concierge' and p.proname = 'resumo_do_dia';

  v_def := regexp_replace(v_def, '\magenda_sessoes\M', 'mind.sessions', 'g');
  execute v_def;
end $$;

-- ------------------------------------------------------------- mudanca de casa
do $$
declare
  v_eng text[] := array[
    'agent_sessions','agente_eventos','contatos','conversas','dispositivos',
    'evento_feedback','feedbacks','identidade_fusoes','jornada_eventos',
    'jornada_sessao','mensagens','nps','sessao_feedback','session_interests',
    'verificacoes_email'];
  v_int text[] := array[
    'acessos_dado_pessoal','dossies','memoria_bloqueios','memoria_regras',
    'participante_contexto','participante_memoria','participante_objetivos',
    'perguntas_feitas','recomendacoes','sinais_comerciais'];
  v_com text[] := array['motivos_ausencia'];
  t text; destino text;
begin
  foreach t in array (v_eng || v_int || v_com) loop
    destino := case when t = any(v_eng) then 'engagement'
                    when t = any(v_int) then 'intelligence'
                    else 'comum' end;
    execute format('alter table concierge.%I set schema %I', t, destino);
    execute format('create view concierge.%I as select * from %I.%I', t, destino, t);
    execute format(
      'comment on view concierge.%I is %L', t,
      'COMPATIBILIDADE: a tabela mora em '||destino||'.'||t||
      '. Esta view cai na migration final da faxina.');
    if exists (select 1 from pg_roles where rolname = 'mind_agent') then
      execute format('grant select, insert, update, delete on concierge.%I to mind_agent', t);
      execute format('grant select, insert, update, delete on %I.%I to mind_agent', destino, t);
    end if;
  end loop;
end $$;

-- ------------------------------------------------------- as funcoes reapontam
-- Referencia qualificada (concierge.x) vira o schema novo.
-- Referencia NAO qualificada -- 3 funcoes do concierge dependem do search_path --
-- e' resolvida pondo engagement e intelligence ANTES de concierge, para cair na
-- tabela real e nao na view: ON CONFLICT nao funciona em view auto-atualizavel.
do $$
declare
  r record; v_def text; t text; destino text;
  v_eng text[] := array[
    'agent_sessions','agente_eventos','contatos','conversas','dispositivos',
    'evento_feedback','feedbacks','identidade_fusoes','jornada_eventos',
    'jornada_sessao','mensagens','nps','sessao_feedback','session_interests',
    'verificacoes_email'];
  v_int text[] := array[
    'acessos_dado_pessoal','dossies','memoria_bloqueios','memoria_regras',
    'participante_contexto','participante_memoria','participante_objetivos',
    'perguntas_feitas','recomendacoes','sinais_comerciais'];
begin
  for r in
    select p.oid, n.nspname||'.'||p.proname as fn
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_language l on l.oid = p.prolang
    where p.prokind = 'f'
      and l.lanname in ('sql','plpgsql')
      and n.nspname in ('public','api','concierge','treble','mind','crm')
      and pg_get_functiondef(p.oid) ~ '\mconcierge\.'
  loop
    v_def := pg_get_functiondef(r.oid);

    foreach t in array (v_eng || v_int) loop
      destino := case when t = any(v_eng) then 'engagement' else 'intelligence' end;
      v_def := regexp_replace(v_def, '\mconcierge\.'||t||'\M', destino||'.'||t, 'g');
    end loop;

    v_def := replace(v_def,
      'SET search_path TO ''concierge''',
      'SET search_path TO ''engagement'', ''intelligence'', ''concierge''');
    v_def := replace(v_def,
      'SET search_path TO ''pg_catalog'', ''public'', ''concierge''',
      'SET search_path TO ''pg_catalog'', ''public'', ''engagement'', ''intelligence'', ''concierge''');
    v_def := replace(v_def,
      'SET search_path TO ''pg_catalog'', ''public'', ''mind'', ''concierge''',
      'SET search_path TO ''pg_catalog'', ''public'', ''mind'', ''engagement'', ''intelligence'', ''concierge''');

    execute v_def;
  end loop;
end $$;
