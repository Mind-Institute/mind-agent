-- Contrato: funções internas só do service_role, e função nova nasce fechada.
--
-- Migration: supabase/migrations/*_funcoes_internas_so_service_role.sql.
-- Roda numa transação e termina em rollback: as funções de teste somem junto.
-- Sucesso é o erro `PERMISSOES_OK: ...`; qualquer outro erro é quebra.

begin;

do $$
declare
  v_nome text;
  v_fn oid;
  v_n int := 0;
begin
  -- 1. As 19 peças internas das filas: visitante não executa, o sistema sim.
  foreach v_nome in array array[
    'silence_claim_pendentes', 'silence_liberar_lock', 'silence_montar_contexto',
    'silence_registrar_decisao', 'silence_sync_from_analysis',
    'summit_contato_criar_pendentes', 'summit_motivo_exclusao',
    'summit_status_confirmar', 'summit_status_pendentes',
    'treble_cta_da_conversa', 'treble_evento_gravar', 'treble_poll_sincronizado',
    'treble_status_ciclo', 'treble_status_confirmar', 'treble_status_confirmar_contato',
    'treble_status_marcar', 'treble_status_pendentes', 'treble_status_pendentes_contato',
    'treble_status_recompute'
  ] loop
    for v_fn in
      select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v_nome
    loop
      if has_function_privilege('anon', v_fn, 'execute')
         or has_function_privilege('authenticated', v_fn, 'execute') then
        raise exception 'ABERTA: public.% executa para visitante', v_nome;
      end if;
      if not has_function_privilege('service_role', v_fn, 'execute') then
        raise exception 'QUEBRADA: service_role perdeu public.%', v_nome;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  if v_n <> 19 then
    raise exception 'esperava as 19 funcoes internas, achei %', v_n;
  end if;

  -- 2. O espelho deste projeto, quando existe, também é só do sistema.
  for v_fn in
    select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'espelho_para_mind'
  loop
    if has_function_privilege('anon', v_fn, 'execute')
       or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception 'ABERTA: public.espelho_para_mind executa para visitante';
    end if;
  end loop;

  -- 3. Função nova nasce fechada. Em `public`, o padrão do schema ainda dá
  --    EXECUTE ao service_role; em `api`, só o dono executa até alguém conceder.
  create function public.contrato_nasce_fechada() returns int language sql as 'select 1';
  if has_function_privilege('anon', 'public.contrato_nasce_fechada()', 'execute')
     or has_function_privilege('authenticated', 'public.contrato_nasce_fechada()', 'execute') then
    raise exception 'ABERTA: funcao nova em public nasce executavel por visitante';
  end if;
  if not has_function_privilege('service_role', 'public.contrato_nasce_fechada()', 'execute') then
    raise exception 'QUEBRADA: funcao nova em public deveria executar para o service_role';
  end if;

  create function api.contrato_nasce_fechada() returns int language sql as 'select 1';
  if has_function_privilege('anon', 'api.contrato_nasce_fechada()', 'execute')
     or has_function_privilege('authenticated', 'api.contrato_nasce_fechada()', 'execute') then
    raise exception 'ABERTA: funcao nova em api nasce executavel por visitante';
  end if;

  -- 4. Quem precisa abrir, abre de propósito — e continua funcionando.
  grant execute on function api.contrato_nasce_fechada() to anon;
  if not has_function_privilege('anon', 'api.contrato_nasce_fechada()', 'execute') then
    raise exception 'QUEBRADA: grant explicito para anon nao abriu a funcao';
  end if;

  raise exception 'PERMISSOES_OK: 19 funcoes internas so do service_role; espelho fechado; funcao nova nasce fechada em public e api';
end
$$;

rollback;
