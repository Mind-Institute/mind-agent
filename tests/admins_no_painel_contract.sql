-- Contrato: admins do sistema no painel — ver e cadastrar quem entra no Mind Intelligence Admin.
--
-- Migrations: supabase/migrations/*_admins_do_sistema_no_painel.sql, *_auditoria.sql e
-- *_admins_no_painel_email_da_mind.sql.
-- Roda numa transação e termina em rollback: pessoas, contas e acessos de teste somem junto.
-- Sucesso é o erro `ADMINS_PAINEL_OK: ...`; qualquer outro erro é quebra.

begin;

do $$
declare
  v_adm uuid := gen_random_uuid();
  v_editor uuid := gen_random_uuid();
  v_equipe uuid := gen_random_uuid();
  v_lead uuid := gen_random_uuid();
  v_pessoal uuid := gen_random_uuid();
  v_conta_adm uuid := gen_random_uuid();
  v_conta_editor uuid := gen_random_uuid();
  v_linha_adm uuid;
  v_r jsonb;
  v_id uuid;
  v_versao text;
  v_msg text;
  v_state text;
begin
  -- Pessoas de teste: a admin que opera, uma editora, alguém da equipe sem acesso e um lead.
  insert into pessoas.pessoas (id, email, primeiro_nome, sobrenome, origem, relacionamento_mind) values
    (v_adm, 'contrato.painel.adm@joinmind.com.br', 'Contrato', 'Adm', 'manual', array['staff']),
    (v_editor, 'contrato.painel.editor@joinmind.com.br', 'Contrato', 'Editor', 'manual', array['staff']),
    (v_equipe, 'contrato.painel.equipe@joinmind.com.br', 'Contrato', 'Equipe', 'manual', array['staff']),
    (v_lead, 'contrato.painel.lead@joinmind.com.br', 'Contrato', 'Lead', 'manual', array['lead']),
    -- Alguém da equipe cujo e-mail principal no Mind ID é pessoal; o da Mind é uma identidade.
    (v_pessoal, 'contrato.painel.pessoal@exemplo.com', 'Contrato', 'Pessoal', 'manual', array['staff']);
  insert into engagement.identidades (mind_id, canal, identificador) values
    (v_pessoal, 'email', 'contrato.painel.pessoal@joinmind.com.br');
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
    (v_conta_adm, 'contrato.painel.adm@joinmind.com.br', now(), 'authenticated', 'authenticated'),
    (v_conta_editor, 'contrato.painel.editor@joinmind.com.br', now(), 'authenticated', 'authenticated');
  insert into public.mind_admin_users (mind_id, user_id, display_name, role, active) values
    (v_adm, v_conta_adm, 'Contrato Adm', 'administrador', true),
    (v_editor, v_conta_editor, 'Contrato Editor', 'editor', true);
  select id into v_linha_adm from public.mind_admin_users where mind_id = v_adm;

  -- 1. Quem não está na lista não lê nem escreve.
  begin
    perform public.mind_admin_read_admins(gen_random_uuid(), null);
    raise exception 'QUEBRADA: estranho leu a lista';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_forbidden:so_administrador' then raise exception 'QUEBRADA (1): %', v_msg; end if;
  end;

  -- 2. Editora não é administradora: não lê a lista nem dá acesso.
  begin
    perform public.mind_admin_read_admins(v_conta_editor, null);
    raise exception 'QUEBRADA: editora leu a lista';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_forbidden:so_administrador' then raise exception 'QUEBRADA (2a): %', v_msg; end if;
  end;
  begin
    perform public.mind_admin_mutate_admins('conceder', null,
      jsonb_build_object('email', 'contrato.painel.equipe@joinmind.com.br', 'papel', 'editor'),
      null, v_conta_editor, gen_random_uuid());
    raise exception 'QUEBRADA: editora deu acesso';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_forbidden:so_administrador' then raise exception 'QUEBRADA (2b): %', v_msg; end if;
  end;

  -- 3. A administradora lê a lista: nome do Mind ID, papel, login ligado.
  v_r := public.mind_admin_read_admins(v_conta_adm, v_linha_adm);
  if jsonb_array_length(v_r) <> 1 or v_r->0->>'nome' <> 'Contrato Adm' or v_r->0->>'papel' <> 'administrador'
     or (v_r->0->>'loginLigado')::boolean is not true or v_r->0->>'email' <> 'contrato.painel.adm@joinmind.com.br' then
    raise exception 'QUEBRADA (3): %', v_r;
  end if;
  if not exists (select 1 from jsonb_array_elements(public.mind_admin_read_admins(v_conta_adm, null)) e
                  where (e->>'id')::uuid = v_linha_adm) then
    raise exception 'QUEBRADA (3b): a lista inteira não traz a própria linha';
  end if;

  -- 4. Conceder: só e-mail da Mind — é com ele que a pessoa entra pelo Google.
  begin
    perform public.mind_admin_mutate_admins('conceder', null,
      jsonb_build_object('email', 'alguem@gmail.com', 'papel', 'editor'), null, v_conta_adm, gen_random_uuid());
    raise exception 'QUEBRADA: aceitou e-mail de fora';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_validation:dominio' then raise exception 'QUEBRADA (4): %', v_msg; end if;
  end;

  -- 5. E-mail que não é de ninguém no Mind ID: a lista não cria pessoa.
  begin
    perform public.mind_admin_mutate_admins('conceder', null,
      jsonb_build_object('email', 'contrato.painel.ninguem@joinmind.com.br', 'papel', 'editor'), null, v_conta_adm, gen_random_uuid());
    raise exception 'QUEBRADA: criou acesso sem pessoa';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_validation:pessoa_nao_encontrada' then raise exception 'QUEBRADA (5): %', v_msg; end if;
  end;

  -- 6. Lead não vira admin: tem que estar marcado como equipe.
  begin
    perform public.mind_admin_mutate_admins('conceder', null,
      jsonb_build_object('email', 'contrato.painel.lead@joinmind.com.br', 'papel', 'editor'), null, v_conta_adm, gen_random_uuid());
    raise exception 'QUEBRADA: deu acesso a lead';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_validation:nao_e_equipe' then raise exception 'QUEBRADA (6): %', v_msg; end if;
  end;

  -- 7. Papel fora da lista é recusado.
  begin
    perform public.mind_admin_mutate_admins('conceder', null,
      jsonb_build_object('email', 'contrato.painel.equipe@joinmind.com.br', 'papel', 'dono'), null, v_conta_adm, gen_random_uuid());
    raise exception 'QUEBRADA: aceitou papel inventado';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_validation:papel_invalido' then raise exception 'QUEBRADA (7): %', v_msg; end if;
  end;

  -- 8. Conceder certo: pessoa da equipe, e-mail em qualquer caixa. Nasce ativa, sem login ainda; vai para a auditoria.
  v_r := public.mind_admin_mutate_admins('conceder', null,
    jsonb_build_object('email', ' CONTRATO.PAINEL.EQUIPE@JOINMIND.COM.BR ', 'papel', 'editor'), null, v_conta_adm, gen_random_uuid());
  v_id := (v_r->>'id')::uuid;
  if (v_r->>'mindId')::uuid <> v_equipe or v_r->>'papel' <> 'editor' or (v_r->>'ativo')::boolean is not true
     or (v_r->>'loginLigado')::boolean is not false or v_r->>'nome' <> 'Contrato Equipe' then
    raise exception 'QUEBRADA (8): %', v_r;
  end if;
  if not exists (select 1 from public.mind_admin_audit where resource = 'admins' and action = 'criar'
                   and record_id = v_id::text and actor_user_id = v_conta_adm and before_data is null) then
    raise exception 'QUEBRADA (8b): conceder não foi para a auditoria';
  end if;

  -- 9. Quem já tem acesso não recebe de novo: papel se troca no 'atualizar'.
  begin
    perform public.mind_admin_mutate_admins('conceder', null,
      jsonb_build_object('email', 'contrato.painel.equipe@joinmind.com.br', 'papel', 'analista'), null, v_conta_adm, gen_random_uuid());
    raise exception 'QUEBRADA: duplicou acesso';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_validation:ja_tem_acesso' then raise exception 'QUEBRADA (9): %', v_msg; end if;
  end;

  -- 10. Atualizar exige a versão que a tela viu; versão velha é conflito (40001).
  begin
    perform public.mind_admin_mutate_admins('atualizar', v_id, jsonb_build_object('papel', 'analista'), null, v_conta_adm, gen_random_uuid());
    raise exception 'QUEBRADA: atualizou sem versão';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_validation:versao_obrigatoria' then raise exception 'QUEBRADA (10a): %', v_msg; end if;
  end;
  begin
    perform public.mind_admin_mutate_admins('atualizar', v_id, jsonb_build_object('papel', 'analista'),
      '2000-01-01T00:00:00Z', v_conta_adm, gen_random_uuid());
    raise exception 'QUEBRADA: sobrescreveu versão velha';
  exception when others then
    get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    if v_msg <> 'admin_conflict' or v_state <> '40001' then raise exception 'QUEBRADA (10b): % %', v_state, v_msg; end if;
  end;

  -- 11. Tirar o acesso: fica na lista, inativo, com antes e depois na auditoria.
  select updated_at::text into v_versao from public.mind_admin_users where id = v_id;
  v_r := public.mind_admin_mutate_admins('atualizar', v_id, jsonb_build_object('ativo', false), v_versao, v_conta_adm, gen_random_uuid());
  if (v_r->>'ativo')::boolean is not false or v_r->>'papel' <> 'editor' then
    raise exception 'QUEBRADA (11): %', v_r;
  end if;
  if not exists (select 1 from public.mind_admin_audit where resource = 'admins' and action = 'atualizar'
                   and record_id = v_id::text and (before_data->>'ativo')::boolean and not (after_data->>'ativo')::boolean) then
    raise exception 'QUEBRADA (11b): atualizar não foi para a auditoria com antes e depois';
  end if;

  -- 12. Conceder de novo a quem perdeu o acesso reativa a mesma linha, com o papel pedido.
  v_r := public.mind_admin_mutate_admins('conceder', null,
    jsonb_build_object('email', 'contrato.painel.equipe@joinmind.com.br', 'papel', 'analista'), null, v_conta_adm, gen_random_uuid());
  if (v_r->>'id')::uuid <> v_id or (v_r->>'ativo')::boolean is not true or v_r->>'papel' <> 'analista' then
    raise exception 'QUEBRADA (12): %', v_r;
  end if;

  -- 13. Ninguém se tranca para fora: nem tira o próprio acesso, nem o próprio papel de administrador.
  select updated_at::text into v_versao from public.mind_admin_users where id = v_linha_adm;
  begin
    perform public.mind_admin_mutate_admins('atualizar', v_linha_adm, jsonb_build_object('ativo', false), v_versao, v_conta_adm, gen_random_uuid());
    raise exception 'QUEBRADA: tirou o próprio acesso';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_validation:proprio_acesso' then raise exception 'QUEBRADA (13a): %', v_msg; end if;
  end;
  begin
    perform public.mind_admin_mutate_admins('atualizar', v_linha_adm, jsonb_build_object('papel', 'editor'), v_versao, v_conta_adm, gen_random_uuid());
    raise exception 'QUEBRADA: rebaixou o próprio papel';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_validation:proprio_acesso' then raise exception 'QUEBRADA (13b): %', v_msg; end if;
  end;

  -- 14. Linha que não existe é 404; ação inventada é recusada.
  begin
    perform public.mind_admin_mutate_admins('atualizar', gen_random_uuid(), jsonb_build_object('ativo', true), now()::text, v_conta_adm, gen_random_uuid());
    raise exception 'QUEBRADA: atualizou linha que não existe';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_not_found' then raise exception 'QUEBRADA (14a): %', v_msg; end if;
  end;
  begin
    perform public.mind_admin_mutate_admins('apagar', v_id, '{}'::jsonb, null, v_conta_adm, gen_random_uuid());
    raise exception 'QUEBRADA: aceitou ação inventada';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_validation:acao_invalida' then raise exception 'QUEBRADA (14b): %', v_msg; end if;
  end;

  -- 15. Só o service_role executa as três portas.
  if has_function_privilege('anon', 'public.mind_admin_read_admins(uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.mind_admin_read_admins(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public.mind_admin_mutate_admins(text, uuid, jsonb, text, uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.mind_admin_mutate_admins(text, uuid, jsonb, text, uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public.mind_admin_admins_json(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.mind_admin_admins_json(uuid)', 'execute') then
    raise exception 'QUEBRADA (15): porta aberta para anon ou authenticated';
  end if;
  if not has_function_privilege('service_role', 'public.mind_admin_mutate_admins(text, uuid, jsonb, text, uuid, uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.mind_admin_read_admins(uuid, uuid)', 'execute') then
    raise exception 'QUEBRADA (15b): service_role não executa';
  end if;

  -- 16. A lista mostra o e-mail da Mind, com que a pessoa entra — não o pessoal do Mind ID.
  v_r := public.mind_admin_mutate_admins('conceder', null,
    jsonb_build_object('email', 'contrato.painel.pessoal@joinmind.com.br', 'papel', 'analista'),
    null, v_conta_adm, gen_random_uuid());
  if v_r->>'email' <> 'contrato.painel.pessoal@joinmind.com.br' or (v_r->>'loginLigado')::boolean then
    raise exception 'QUEBRADA (16): %', v_r;
  end if;

  raise exception 'ADMINS_PAINEL_OK: 16 casos';
end
$$;

rollback;
