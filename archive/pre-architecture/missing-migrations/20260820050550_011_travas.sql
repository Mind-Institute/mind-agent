revoke usage on schema public from anon, authenticated;
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

alter default privileges in schema public
  revoke all on tables from anon, authenticated;
alter default privileges in schema public
  revoke all on functions from anon, authenticated;

do $$
declare t record;
begin
  for t in
    select tablename from pg_tables
     where schemaname = 'public'
  loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end $$;

alter view v_funil_valor       set (security_invoker = on);
alter view v_operacao_agora    set (security_invoker = on);
alter view v_sessoes_avaliadas set (security_invoker = on);
alter view v_conflitos_agenda  set (security_invoker = on);
alter view v_sessoes_jornada   set (security_invoker = on);
alter view v_demanda_frustrada set (security_invoker = on);
alter view v_aderencia_por_area set (security_invoker = on);

alter function bump_config_revisao()                    set search_path = public;
alter function aplicar_evento_jornada()                 set search_path = public;
alter function resumo_do_dia(uuid, date)                set search_path = public;
alter function esquecer_participante(uuid)              set search_path = public;

revoke execute on function esquecer_participante(uuid) from public, anon, authenticated;
