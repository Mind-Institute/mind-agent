-- FUNÇÕES INTERNAS SÓ PARA O SISTEMA, E FUNÇÃO NOVA NASCE FECHADA.
--
-- Decisão da Adriana, 25/09/2026, depois da auditoria de acesso ao banco.
--
-- AS 19 FUNÇÕES são peças internas das filas do WhatsApp (Treble), do
-- follow-up (silence) e do status do Summit no HubSpot. Quem as chama é o
-- próprio sistema: Edge Functions com a chave secreta (service_role) e os jobs
-- `treble_status_dia` e `treble_status_noite`, que rodam como postgres, o
-- dono. Nenhuma view, policy, default, check ou trigger depende delas, e as
-- funções que as chamam por dentro rodam como o dono (SECURITY DEFINER).
--
-- EXECUTE sai de PUBLIC, anon e authenticated; o service_role continua.
-- Revogar só de anon e authenticated não basta: no Postgres toda função nasce
-- executável por PUBLIC, e todo papel herda PUBLIC.
--
-- `espelho_para_mind` entra junto. Ela confere um segredo que não existe no
-- Vault deste projeto, então hoje recusa toda chamada; fechar é para ela não
-- depender disso. Ela não nasceu de migration deste repositório, por isso a
-- ausência dela não é erro.
--
-- FUNÇÃO NOVA NASCE FECHADA. O padrão do schema `public` para funções do
-- postgres já concedia só a postgres e service_role, mas padrão por schema
-- não tira o PUBLIC que o Postgres dá a toda função nova; isso exige o padrão
-- global, sem `in schema`. Vale para funções criadas daqui em diante:
-- `create or replace` numa função que já existe mantém as permissões dela, e
-- `drop` + `create` recria sem PUBLIC.
--
-- Para quem escreve migration: função que o app ou o site chamam com a chave
-- pública precisa de `grant execute ... to anon` (ou `authenticated`)
-- explícito. Sem ele a chamada falha, em vez de abrir por acidente.
--
-- Idempotente. Falha se uma das 19 sumir, para ninguém achar que fechou o que
-- não existe.
--
-- Contrato: tests/permissoes_funcoes_contract.sql (termina em PERMISSOES_OK).

alter default privileges for role postgres revoke execute on functions from public;

do $$
declare
  v_nome text;
  v_sig text;
  v_achadas int;
begin
  foreach v_nome in array array[
    'silence_claim_pendentes', 'silence_liberar_lock', 'silence_montar_contexto',
    'silence_registrar_decisao', 'silence_sync_from_analysis',
    'summit_contato_criar_pendentes', 'summit_motivo_exclusao',
    'summit_status_confirmar', 'summit_status_pendentes',
    'treble_cta_da_conversa', 'treble_evento_gravar', 'treble_poll_sincronizado',
    'treble_status_ciclo', 'treble_status_confirmar', 'treble_status_confirmar_contato',
    'treble_status_marcar', 'treble_status_pendentes', 'treble_status_pendentes_contato',
    'treble_status_recompute', 'espelho_para_mind'
  ] loop
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
    if v_achadas = 0 and v_nome <> 'espelho_para_mind' then
      raise exception 'funcao nao encontrada: public.%', v_nome;
    end if;
  end loop;
end
$$;
