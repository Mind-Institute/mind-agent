-- O papel `mind_agent` existia, mas ninguém podia assumi-lo: `set role mind_agent`
-- dava "permission denied". Papel que não dá para vestir não protege nada — o
-- Worker cairia de volta no service_role, que passa por cima de toda a RLS, e a
-- camada 2 viraria decoração.
--
-- Achado testando, não lendo. Sem o teste, isso só apareceria no dia em que
-- alguém confiasse na política e ela não estivesse valendo.
grant mind_agent to postgres;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    execute 'grant mind_agent to authenticator';
  end if;
end $$;

comment on role mind_agent is
  'Papel do Worker para tudo que é dado de pessoa. NÃO é o service_role: obedece RLS. O Worker faz set role mind_agent + set local mind.person_id a cada transação.';
