-- ADMINS DO SISTEMA NO PAINEL: A AUDITORIA NO VOCABULÁRIO QUE ELA JÁ TEM.
--
-- A migration 20260926144621 gravava action = 'conceder' em mind_admin_audit, e a tabela só aceita
-- criar, atualizar, publicar, arquivar, reindexar e login (mind_admin_audit_action_check): dar acesso
-- falhava inteiro, com rollback — nada foi gravado. Em vez de mexer na regra da tabela, o registro usa
-- o vocabulário que existe: dar acesso a quem nunca teve é 'criar'; devolver a quem tinha perdido, ou
-- mudar papel e ativo, é 'atualizar'. O verbo da porta continua 'conceder'. Só a função muda.
--
-- Contrato: tests/admins_no_painel_contract.sql (termina em ADMINS_PAINEL_OK).

create or replace function public.mind_admin_mutate_admins(
  p_action text,
  p_id uuid,
  p_payload jsonb,
  p_expected_updated_at text,
  p_actor_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
declare
  v_papeis constant text[] := array['administrador', 'editor', 'aprovador', 'atendimento', 'analista'];
  v_email text;
  v_papel text;
  v_ativo boolean;
  v_pessoas uuid[];
  v_mind uuid;
  v_rel text[];
  v_nome text;
  v_linha public.mind_admin_users;
  v_id uuid;
  v_before jsonb;
  v_after jsonb;
  v_msg text;
begin
  if not exists (
    select 1 from public.mind_admin_users
     where user_id = p_actor_id and active and role = 'administrador'
  ) then
    raise exception using errcode = '42501', message = 'admin_forbidden:so_administrador';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'admin_validation:corpo_invalido';
  end if;
  if p_payload ? 'papel' then
    v_papel := p_payload->>'papel';
    if v_papel is null or not (v_papel = any(v_papeis)) then
      raise exception using errcode = '22023', message = 'admin_validation:papel_invalido';
    end if;
  end if;

  if p_action = 'conceder' then
    v_email := lower(btrim(coalesce(p_payload->>'email', '')));
    if v_email = '' then
      raise exception using errcode = '22023', message = 'admin_validation:email_obrigatorio';
    end if;
    if v_email !~ '^[^@[:space:]]+@joinmind\.com\.br$' then
      raise exception using errcode = '22023', message = 'admin_validation:dominio';
    end if;
    v_papel := coalesce(v_papel, 'analista');

    -- A pessoa pelo e-mail: tem que ser uma só, e não fundida. Mesma regra do primeiro login.
    select array_agg(distinct x.mind_id) into v_pessoas
      from (
        select i.mind_id from engagement.identidades i
         where i.canal = 'email' and lower(i.identificador) = v_email
        union
        select p.id from pessoas.pessoas p where lower(p.email) = v_email
      ) x
      join pessoas.pessoas p on p.id = x.mind_id and p.fundida_em is null;
    if coalesce(cardinality(v_pessoas), 0) = 0 then
      raise exception using errcode = '22023', message = 'admin_validation:pessoa_nao_encontrada';
    end if;
    if cardinality(v_pessoas) > 1 then
      raise exception using errcode = '22023', message = 'admin_validation:email_em_mais_de_uma_pessoa';
    end if;
    v_mind := v_pessoas[1];

    select p.relacionamento_mind, nullif(btrim(concat_ws(' ', p.primeiro_nome, p.sobrenome)), '')
      into v_rel, v_nome
      from pessoas.pessoas p where p.id = v_mind;
    if not ('staff' = any(coalesce(v_rel, '{}'))) then
      raise exception using errcode = '22023', message = 'admin_validation:nao_e_equipe';
    end if;

    select * into v_linha from public.mind_admin_users where mind_id = v_mind for update;
    if found then
      if v_linha.active then
        raise exception using errcode = '22023', message = 'admin_validation:ja_tem_acesso';
      end if;
      v_id := v_linha.id;
      v_before := public.mind_admin_admins_json(v_id)->0;
      update public.mind_admin_users
         set role = v_papel, active = true, display_name = coalesce(v_nome, display_name),
             updated_at = clock_timestamp()
       where id = v_id;
    else
      insert into public.mind_admin_users (mind_id, display_name, role, active)
      values (v_mind, v_nome, v_papel, true)
      returning id into v_id;
    end if;

  elsif p_action = 'atualizar' then
    if p_id is null then
      raise exception using errcode = '22023', message = 'admin_validation:id_obrigatorio';
    end if;
    select * into v_linha from public.mind_admin_users where id = p_id for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'admin_not_found';
    end if;
    if p_expected_updated_at is null or btrim(p_expected_updated_at) = '' then
      raise exception using errcode = '22023', message = 'admin_validation:versao_obrigatoria';
    end if;
    if v_linha.updated_at <> p_expected_updated_at::timestamptz then
      raise exception using errcode = '40001', message = 'admin_conflict';
    end if;
    if p_payload ? 'ativo' then
      if jsonb_typeof(p_payload->'ativo') <> 'boolean' then
        raise exception using errcode = '22023', message = 'admin_validation:ativo_invalido';
      end if;
      v_ativo := (p_payload->>'ativo')::boolean;
    end if;
    v_papel := coalesce(v_papel, v_linha.role);
    v_ativo := coalesce(v_ativo, v_linha.active);

    -- Ninguém se tranca para fora: o próprio acesso e o próprio papel de administrador não mudam aqui.
    if v_linha.user_id = p_actor_id and (not v_ativo or v_papel <> 'administrador') then
      raise exception using errcode = '22023', message = 'admin_validation:proprio_acesso';
    end if;
    -- E o sistema nunca fica sem administrador ativo.
    if v_linha.active and v_linha.role = 'administrador' and (not v_ativo or v_papel <> 'administrador')
       and not exists (
         select 1 from public.mind_admin_users
          where active and role = 'administrador' and id <> v_linha.id
       ) then
      raise exception using errcode = '22023', message = 'admin_validation:ultimo_administrador';
    end if;

    v_id := v_linha.id;
    v_before := public.mind_admin_admins_json(v_id)->0;
    update public.mind_admin_users
       set role = v_papel, active = v_ativo, updated_at = clock_timestamp()
     where id = v_id;

  else
    raise exception using errcode = '22023', message = 'admin_validation:acao_invalida';
  end if;

  v_after := public.mind_admin_admins_json(v_id)->0;

  insert into public.mind_admin_audit(
    actor_user_id, action, resource, record_id, record_label, before_data, after_data, request_id
  ) values (
    -- A auditoria fala o vocabulário que já tem: dar acesso a quem nunca teve é 'criar';
    -- devolver a quem tinha perdido, ou mudar papel e ativo, é 'atualizar'.
    p_actor_id, case when p_action = 'conceder' and v_before is null then 'criar' else 'atualizar' end,
    'admins', v_id::text, v_after->>'nome', v_before, v_after, p_request_id
  );

  return v_after;
exception
  when check_violation then
    -- A trava da tabela (mind_admin_users_valida) fala com a tela na mesma língua.
    get stacked diagnostics v_msg = message_text;
    if v_msg like 'admin_nao_e_equipe%' then
      raise exception using errcode = '22023', message = 'admin_validation:nao_e_equipe';
    end if;
    if v_msg like 'admin_pessoa_fundida%' then
      raise exception using errcode = '22023', message = 'admin_validation:pessoa_fundida';
    end if;
    raise exception using errcode = '22023', message = 'admin_validation:dados_invalidos';
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception using errcode = '22023', message = 'admin_validation:dados_invalidos';
end
$fn$;


revoke all on function public.mind_admin_mutate_admins(text, uuid, jsonb, text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.mind_admin_mutate_admins(text, uuid, jsonb, text, uuid, uuid) to service_role;
