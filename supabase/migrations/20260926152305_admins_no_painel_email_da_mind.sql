-- ADMINS DO SISTEMA: O E-MAIL DA LISTA É O DA MIND, COM QUE A PESSOA ENTRA.
--
-- A Adriana abriu a própria linha e viu o e-mail pessoal (26/09/2026): "a adriana que é administradora
-- do painel sou eu com o e-mail @joinmind.com.br — por que apareceu o outro?". A lista mostrava o
-- e-mail principal do Mind ID (pessoas.pessoas.email), que pode ser pessoal; quem entra no painel entra
-- com o e-mail da Mind, pelo Google. Agora, na ordem: o e-mail da conta de login ligada; sem login
-- ainda, o e-mail @joinmind.com.br da pessoa no Mind ID (o principal, se for da Mind, ou uma das
-- identidades de e-mail); só sem nenhum dos dois, o principal. Só esta função muda.
--
-- Contrato: tests/admins_no_painel_contract.sql (termina em ADMINS_PAINEL_OK).

create or replace function public.mind_admin_admins_json(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', m.id,
      'mindId', m.mind_id,
      'nome', coalesce(nullif(btrim(concat_ws(' ', p.primeiro_nome, p.sobrenome)), ''), m.display_name, u.email),
      'email', coalesce(u.email, da_mind.email, p.email),
      'papel', m.role,
      'ativo', m.active,
      'loginLigado', m.user_id is not null,
      'ultimoLoginEm', u.last_sign_in_at,
      'criadoEm', m.created_at,
      'atualizadoEm', m.updated_at
    ) order by m.active desc, coalesce(nullif(btrim(concat_ws(' ', p.primeiro_nome, p.sobrenome)), ''), m.display_name, u.email)), '[]'::jsonb)
  from public.mind_admin_users m
  left join pessoas.pessoas p on p.id = m.mind_id
  left join auth.users u on u.id = m.user_id
  left join lateral (
    select e.email
      from (
        select lower(btrim(p.email)) as email, 0 as ordem
         where p.email ~* '@joinmind\.com\.br$'
        union all
        select lower(btrim(i.identificador)), 1
          from engagement.identidades i
         where i.mind_id = m.mind_id and i.canal = 'email' and i.identificador ~* '@joinmind\.com\.br$'
      ) e
     order by e.ordem, e.email
     limit 1
  ) da_mind on true
  where p_id is null or m.id = p_id
$fn$;

comment on function public.mind_admin_admins_json(uuid) is
  'Registro de admin do sistema como o painel mostra (nome do Mind ID; e-mail com que entra: o do login, senão o @joinmind.com.br do Mind ID; papel, ativo, login ligado, último login). Interna: não confere quem pede. Só service_role executa.';

revoke all on function public.mind_admin_admins_json(uuid) from public, anon, authenticated;
grant execute on function public.mind_admin_admins_json(uuid) to service_role;
