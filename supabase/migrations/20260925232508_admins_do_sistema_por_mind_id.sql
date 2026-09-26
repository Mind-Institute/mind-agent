-- ADMINS DO SISTEMA: A LISTA PASSA A DIZER QUEM É PELO MIND ID.
--
-- Decisão da Adriana, 25/09/2026: "não é backoffice mas admins deste sistema e daí sim podemos fazer
-- por Mind ID e sempre antes de colocar a pessoa ela deve existir como um Mind ID e em Mind ID da
-- equipe tem que poder marcar equipe para não confundir com lead".
--
-- A LISTA É A QUE O PAINEL JÁ CONFERE: public.mind_admin_users. O que muda:
--   · mind_id: a pessoa (D6). Tem que existir em pessoas.pessoas (chave estrangeira), não pode ser
--     pessoa fundida e, enquanto o acesso estiver ativo, tem que estar marcada como equipe
--     ('staff' em relacionamento_mind, a marca de 23/09 que já tira a pessoa das regras de lead).
--     A lista nunca cria pessoa: escolhe-se uma que já existe. Por isso não entra o trigger da D5
--     (mind_pessoa_ligar_tabela), que resolveria ou criaria pessoa a partir de e-mail e telefone.
--   · user_id: a conta de login. Passa a poder ficar vazia: a pessoa entra na lista antes do
--     primeiro login, e a conta se liga a ela nesse primeiro login (mind_admin_vincular_login).
--   · id: chave própria da linha, já que a conta de login pode ainda não existir. user_id e mind_id
--     continuam únicos, e quem confere papel por user_id segue igual.
-- Linha sem mind_id só existe a antiga (a conta genérica com senha, que não é uma pessoa). Ela vale
-- até o login com Google estar no ar e depois sai. Linha nova sem mind_id é recusada.
--
-- O PRIMEIRO LOGIN LIGA A CONTA À PESSOA: public.mind_admin_vincular_login(p_user_id) confere no
-- próprio auth que a conta tem identidade Google com e-mail verificado @joinmind.com.br; acha a pessoa
-- por esse e-mail (tem que ser uma só); exige linha ativa e pessoa marcada como equipe; grava o
-- user_id na linha e registra o login como identidade da pessoa pela porta única
-- (mind_identidade_resolver, sem criar pessoa). Pessoa já ligada a outra conta é recusada. Só o
-- service_role executa: quem chama é a Edge Function do painel, depois de validar a sessão.
--
-- Contrato: tests/admins_do_sistema_contract.sql (termina em ADMINS_OK).

alter table public.mind_admin_users add column if not exists id uuid not null default gen_random_uuid();
alter table public.mind_admin_users add column if not exists mind_id uuid references pessoas.pessoas(id);

alter table public.mind_admin_users drop constraint if exists mind_admin_users_pkey;
alter table public.mind_admin_users add constraint mind_admin_users_pkey primary key (id);
alter table public.mind_admin_users alter column user_id drop not null;
alter table public.mind_admin_users drop constraint if exists mind_admin_users_user_id_key;
alter table public.mind_admin_users add constraint mind_admin_users_user_id_key unique (user_id);
alter table public.mind_admin_users drop constraint if exists mind_admin_users_mind_id_key;
alter table public.mind_admin_users add constraint mind_admin_users_mind_id_key unique (mind_id);

comment on column public.mind_admin_users.mind_id is
  'A pessoa que é admin do sistema (D6). Tem que existir, não pode ser fundida e, com acesso ativo, tem que estar marcada como equipe (staff em pessoas.relacionamento_mind). A lista nunca cria pessoa.';
comment on column public.mind_admin_users.user_id is
  'A conta de login da pessoa. Fica vazia até o primeiro login com Google, quando mind_admin_vincular_login a liga.';

create or replace function public.mind_admin_users_valida()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
declare
  v_rel text[];
  v_fundida uuid;
begin
  if new.mind_id is null then
    if tg_op = 'INSERT' then
      raise exception using errcode = '23502',
        message = 'admin_sem_pessoa: todo admin novo aponta para um Mind ID que já existe';
    end if;
    return new; -- só a linha antiga, da conta genérica, até ela sair
  end if;

  select p.relacionamento_mind, p.fundida_em into v_rel, v_fundida
    from pessoas.pessoas p where p.id = new.mind_id;
  if v_fundida is not null then
    raise exception using errcode = '23514',
      message = 'admin_pessoa_fundida: use o Mind ID que ficou depois da fusão';
  end if;
  if new.active and not ('staff' = any(v_rel)) then
    raise exception using errcode = '23514',
      message = 'admin_nao_e_equipe: marque a pessoa como equipe antes de dar acesso';
  end if;
  return new;
end
$fn$;

drop trigger if exists mind_admin_users_valida on public.mind_admin_users;
create trigger mind_admin_users_valida
  before insert or update on public.mind_admin_users
  for each row execute function public.mind_admin_users_valida();

create or replace function public.mind_admin_vincular_login(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
declare
  v_linha public.mind_admin_users;
  v_email text;
  v_confirmado timestamptz;
  v_pessoas uuid[];
  v_mind uuid;
  v_rel text[];
begin
  if p_user_id is null then
    raise exception using errcode = '22023', message = 'admin_validation:sem_usuario';
  end if;

  -- Conta já ligada: devolve o que está, sem mexer.
  select * into v_linha from public.mind_admin_users where user_id = p_user_id;
  if found then
    return jsonb_build_object('vinculado', false, 'mind_id', v_linha.mind_id, 'role', v_linha.role,
      'active', v_linha.active, 'display_name', v_linha.display_name);
  end if;

  -- A conta tem que ser Google, com e-mail verificado da Mind.
  select lower(u.email), u.email_confirmed_at into v_email, v_confirmado
    from auth.users u where u.id = p_user_id and not u.is_anonymous;
  if v_email is null then
    raise exception using errcode = '42501', message = 'admin_forbidden:conta_invalida';
  end if;
  if v_confirmado is null then
    raise exception using errcode = '42501', message = 'admin_forbidden:email_nao_verificado';
  end if;
  if v_email !~ '@joinmind\.com\.br$' then
    raise exception using errcode = '42501', message = 'admin_forbidden:dominio';
  end if;
  if not exists (
    select 1 from auth.identities i
     where i.user_id = p_user_id and i.provider = 'google'
       and lower(i.identity_data->>'email') = v_email
       and coalesce((i.identity_data->>'email_verified')::boolean, false)
  ) then
    raise exception using errcode = '42501', message = 'admin_forbidden:so_google';
  end if;

  -- A pessoa pelo e-mail: tem que ser uma só, e não fundida.
  select array_agg(distinct x.mind_id) into v_pessoas
    from (
      select i.mind_id from engagement.identidades i
       where i.canal = 'email' and lower(i.identificador) = v_email
      union
      select p.id from pessoas.pessoas p where lower(p.email) = v_email
    ) x
    join pessoas.pessoas p on p.id = x.mind_id and p.fundida_em is null;
  if coalesce(cardinality(v_pessoas), 0) = 0 then
    raise exception using errcode = '42501', message = 'admin_forbidden:pessoa_nao_encontrada';
  end if;
  if cardinality(v_pessoas) > 1 then
    raise exception using errcode = '42501', message = 'admin_forbidden:email_em_mais_de_uma_pessoa';
  end if;
  v_mind := v_pessoas[1];

  select * into v_linha from public.mind_admin_users where mind_id = v_mind for update;
  if not found or not v_linha.active then
    raise exception using errcode = '42501', message = 'admin_forbidden:sem_acesso';
  end if;
  if v_linha.user_id is not null then
    raise exception using errcode = '42501', message = 'admin_forbidden:pessoa_ja_ligada_a_outra_conta';
  end if;
  select p.relacionamento_mind into v_rel from pessoas.pessoas p where p.id = v_mind;
  if not ('staff' = any(v_rel)) then
    raise exception using errcode = '42501', message = 'admin_forbidden:nao_e_equipe';
  end if;

  update public.mind_admin_users set user_id = p_user_id, updated_at = now() where id = v_linha.id;

  -- O login vira identidade da pessoa pela porta única, ancorado nela e sem criar pessoa.
  perform public.mind_identidade_resolver(
    jsonb_build_object('email', v_email, 'auth_user_id', p_user_id::text),
    null, 'mindagent-admin', v_mind, false);

  return jsonb_build_object('vinculado', true, 'mind_id', v_mind, 'role', v_linha.role,
    'active', true, 'display_name', v_linha.display_name);
end
$fn$;

comment on function public.mind_admin_vincular_login(uuid) is
  'Primeiro login de um admin do sistema: confere conta Google com e-mail verificado @joinmind.com.br, acha a pessoa por esse e-mail (uma só), exige acesso ativo e pessoa marcada como equipe, grava o user_id e registra o login como identidade pela porta única, sem criar pessoa. Conta já ligada devolve o que está. Só service_role executa.';

revoke all on function public.mind_admin_users_valida() from public, anon, authenticated;
revoke all on function public.mind_admin_vincular_login(uuid) from public, anon, authenticated;
grant execute on function public.mind_admin_vincular_login(uuid) to service_role;
