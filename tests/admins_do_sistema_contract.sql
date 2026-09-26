-- Contrato: admins do sistema por Mind ID.
--
-- Migration: supabase/migrations/*_admins_do_sistema_por_mind_id.sql.
-- Roda numa transação e termina em rollback: pessoas, contas e acessos de teste somem junto.
-- Sucesso é o erro `ADMINS_OK: ...`; qualquer outro erro é quebra.

begin;

do $$
declare
  v_equipe uuid := gen_random_uuid();
  v_lead uuid := gen_random_uuid();
  v_fundida uuid := gen_random_uuid();
  v_fora uuid := gen_random_uuid();
  v_conta uuid := gen_random_uuid();
  v_conta_senha uuid := gen_random_uuid();
  v_conta_outro_dominio uuid := gen_random_uuid();
  v_conta_fora uuid := gen_random_uuid();
  v_r jsonb;
  v_msg text;
begin
  -- Pessoas de teste: uma da equipe, um lead, uma fundida e uma da equipe fora da lista.
  insert into pessoas.pessoas (id, email, primeiro_nome, origem, relacionamento_mind) values
    (v_equipe, 'contrato.admin@joinmind.com.br', 'Contrato', 'manual', array['staff']),
    (v_lead, 'contrato.lead@exemplo.com.br', 'Lead', 'manual', array['lead']),
    (v_fora, 'contrato.fora@joinmind.com.br', 'Fora', 'manual', array['staff']);
  insert into pessoas.pessoas (id, email, primeiro_nome, origem, relacionamento_mind, fundida_em) values
    (v_fundida, 'contrato.fundida@joinmind.com.br', 'Fundida', 'manual', array['staff'], v_equipe);

  -- 1. Admin novo sem Mind ID é recusado.
  begin
    insert into public.mind_admin_users (display_name, role, active) values ('Sem pessoa', 'editor', true);
    raise exception 'QUEBRADA: aceitou admin sem Mind ID';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg not like 'admin_sem_pessoa%' then raise exception 'QUEBRADA (1): %', v_msg; end if;
  end;

  -- 2. Mind ID que não existe é recusado (a pessoa tem que existir antes).
  begin
    insert into public.mind_admin_users (mind_id, display_name, role, active) values (gen_random_uuid(), 'Fantasma', 'editor', true);
    raise exception 'QUEBRADA: aceitou Mind ID que não existe';
  exception when foreign_key_violation then null;
  end;

  -- 3. Lead não vira admin: tem que estar marcado como equipe.
  begin
    insert into public.mind_admin_users (mind_id, display_name, role, active) values (v_lead, 'Lead', 'editor', true);
    raise exception 'QUEBRADA: aceitou lead como admin';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg not like 'admin_nao_e_equipe%' then raise exception 'QUEBRADA (3): %', v_msg; end if;
  end;

  -- 4. Pessoa fundida não vira admin.
  begin
    insert into public.mind_admin_users (mind_id, display_name, role, active) values (v_fundida, 'Fundida', 'editor', true);
    raise exception 'QUEBRADA: aceitou pessoa fundida';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg not like 'admin_pessoa_fundida%' then raise exception 'QUEBRADA (4): %', v_msg; end if;
  end;

  -- 5. Pessoa da equipe entra, ainda sem conta de login.
  insert into public.mind_admin_users (mind_id, display_name, role, active) values (v_equipe, 'Contrato', 'editor', true);

  -- Contas de teste: Google com e-mail da Mind; senha; Google de outro domínio; Google fora da lista.
  insert into auth.users (id, email, email_confirmed_at, aud, role) values
    (v_conta, 'contrato.admin@joinmind.com.br', now(), 'authenticated', 'authenticated'),
    (v_conta_senha, 'contrato.senha@joinmind.com.br', now(), 'authenticated', 'authenticated'),
    (v_conta_outro_dominio, 'contrato@outrodominio.com', now(), 'authenticated', 'authenticated'),
    (v_conta_fora, 'contrato.fora@joinmind.com.br', now(), 'authenticated', 'authenticated');
  insert into auth.identities (provider_id, user_id, identity_data, provider) values
    ('g-contrato-1', v_conta, jsonb_build_object('email', 'contrato.admin@joinmind.com.br', 'email_verified', true), 'google'),
    (v_conta_senha::text, v_conta_senha, jsonb_build_object('email', 'contrato.senha@joinmind.com.br', 'email_verified', true), 'email'),
    ('g-contrato-2', v_conta_outro_dominio, jsonb_build_object('email', 'contrato@outrodominio.com', 'email_verified', true), 'google'),
    ('g-contrato-3', v_conta_fora, jsonb_build_object('email', 'contrato.fora@joinmind.com.br', 'email_verified', true), 'google');

  -- 6. Login por senha não se liga: só Google.
  begin
    perform public.mind_admin_vincular_login(v_conta_senha);
    raise exception 'QUEBRADA: ligou conta de senha';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_forbidden:so_google' then raise exception 'QUEBRADA (6): %', v_msg; end if;
  end;

  -- 7. Google de outro domínio não se liga.
  begin
    perform public.mind_admin_vincular_login(v_conta_outro_dominio);
    raise exception 'QUEBRADA: ligou outro domínio';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_forbidden:dominio' then raise exception 'QUEBRADA (7): %', v_msg; end if;
  end;

  -- 8. Pessoa da equipe fora da lista não entra.
  begin
    perform public.mind_admin_vincular_login(v_conta_fora);
    raise exception 'QUEBRADA: ligou quem não está na lista';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg <> 'admin_forbidden:sem_acesso' then raise exception 'QUEBRADA (8): %', v_msg; end if;
  end;

  -- 9. Google da Mind, pessoa na lista e marcada como equipe: liga a conta e registra a identidade.
  v_r := public.mind_admin_vincular_login(v_conta);
  if not (v_r->>'vinculado')::boolean or (v_r->>'mind_id')::uuid <> v_equipe or v_r->>'role' <> 'editor' then
    raise exception 'QUEBRADA (9): %', v_r;
  end if;
  if not exists (select 1 from public.mind_admin_users where mind_id = v_equipe and user_id = v_conta) then
    raise exception 'QUEBRADA (9): user_id não ficou gravado';
  end if;
  if not exists (select 1 from engagement.identidades where canal = 'auth_user' and identificador = v_conta::text and mind_id = v_equipe) then
    raise exception 'QUEBRADA (9): login não virou identidade da pessoa';
  end if;

  -- 10. Segundo login: nada muda.
  v_r := public.mind_admin_vincular_login(v_conta);
  if (v_r->>'vinculado')::boolean or (v_r->>'mind_id')::uuid <> v_equipe then
    raise exception 'QUEBRADA (10): %', v_r;
  end if;

  -- 11. Tirar a marca de equipe de quem tem acesso ativo é recusado na próxima escrita do acesso.
  update pessoas.pessoas set relacionamento_mind = array['lead'] where id = v_equipe;
  begin
    update public.mind_admin_users set role = 'administrador' where mind_id = v_equipe;
    raise exception 'QUEBRADA: manteve acesso ativo de quem não é equipe';
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if v_msg not like 'admin_nao_e_equipe%' then raise exception 'QUEBRADA (11): %', v_msg; end if;
  end;

  -- 12. Só o sistema executa a ligação.
  if has_function_privilege('anon', 'public.mind_admin_vincular_login(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.mind_admin_vincular_login(uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.mind_admin_vincular_login(uuid)', 'execute') then
    raise exception 'QUEBRADA (12): permissões da ligação';
  end if;

  raise exception 'ADMINS_OK: pessoa tem que existir e ser equipe; só Google da Mind se liga; ligação idempotente e só do sistema';
end
$$;

rollback;
