-- AS DUAS PORTAS DO SITE TAMBÉM FECHAM.
--
-- Decisão da Adriana, 25/09/2026: "pode fechar as duas do site também".
--
-- `mind_origem(p_codigo)` devolvia o texto público de uma entrada (botão ou
-- link do site) e `mind_utm_registrar(p_dados)` gravava as UTMs da visita e
-- devolvia um token curto para o link do WhatsApp. Foram abertas a `anon` e
-- `authenticated` de propósito, para o site chamar direto com a chave
-- pública, mas o site não chama mais: `engagement.utm_sessoes` tem 2 linhas,
-- a última de 22/08, e os logs olhados (16/09, pico do Summit, e as 48 h até
-- 25/09) não têm nenhuma chamada às duas. Nenhuma função, view, policy,
-- default ou job depende delas.
--
-- EXECUTE sai de PUBLIC, anon e authenticated; o service_role continua. Se o
-- site voltar a precisar, reabrir com `grant execute ... to anon` explícito.
--
-- Idempotente. As duas nasceram no stub histórico
-- (20260829185445_historical_prod_stub.sql), então a ausência é erro.
--
-- Contrato: tests/permissoes_funcoes_contract.sql (termina em PERMISSOES_OK).

do $$
declare
  v_nome text;
  v_sig text;
  v_achadas int;
begin
  foreach v_nome in array array['mind_origem', 'mind_utm_registrar'] loop
    v_achadas := 0;
    for v_sig in
      select format('%I.%I(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v_nome
    loop
      execute format('revoke all on function %s from public, anon, authenticated', v_sig);
      execute format('grant execute on function %s to service_role', v_sig);
      v_achadas := v_achadas + 1;
    end loop;
    if v_achadas = 0 then
      raise exception 'funcao nao encontrada: public.%', v_nome;
    end if;
  end loop;
end
$$;
