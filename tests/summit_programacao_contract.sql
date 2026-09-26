-- Contrato: a programação do Mind Summit 2026 no painel — mind_admin_read_summit_2026_sessoes
-- (migration 20260926154547_summit_2026_programacao_no_painel). Só leitura: não escreve nada.
-- Sucesso é o erro `SUMMIT_PROGRAMACAO_OK: ...`; qualquer outro erro é quebra.

begin;

do $$
declare
  v_lista jsonb;
  v_um jsonb;
  v_sessao summit_2026.sessions%rowtype;
  n int;
  v_coluna text;
begin
  -- 1. Todas as sessões, na ordem do banco (dia, início, título).
  v_lista := public.mind_admin_read_summit_2026_sessoes();
  select count(*) into n from summit_2026.sessions;
  if jsonb_array_length(v_lista) <> n then
    raise exception 'QUEBRADA (1): % sessões na leitura, % na tabela', jsonb_array_length(v_lista), n;
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_lista) with ordinality a(e, i)
      join jsonb_array_elements(v_lista) with ordinality b(e, i) on b.i = a.i + 1
     where (a.e->>'dia', (a.e->>'inicio')::timestamptz, a.e->>'titulo')
         > (b.e->>'dia', (b.e->>'inicio')::timestamptz, b.e->>'titulo')
  ) then
    raise exception 'QUEBRADA (1b): fora da ordem dia, início, título';
  end if;

  -- 2. Cada linha traz TODAS as colunas da tabela, com os nomes do banco, mais espaço e palestrantes.
  for v_coluna in
    select column_name from information_schema.columns
     where table_schema = 'summit_2026' and table_name = 'sessions'
  loop
    if exists (select 1 from jsonb_array_elements(v_lista) e where not e ? v_coluna) then
      raise exception 'QUEBRADA (2): falta a coluna % em alguma linha', v_coluna;
    end if;
  end loop;
  if exists (select 1 from jsonb_array_elements(v_lista) e
              where not e ? 'espaco' or jsonb_typeof(e->'palestrantes') <> 'array') then
    raise exception 'QUEBRADA (2b): espaço ou palestrantes fora do formato';
  end if;

  -- 3. Uma sessão pelo id, igual à tabela; o nome do espaço e dos palestrantes batem com as casas deles.
  select * into v_sessao from summit_2026.sessions
   where espaco_id is not null and exists (select 1 from summit_2026.session_speakers ss where ss.sessao_id = id)
   order by dia, inicio limit 1;
  v_um := public.mind_admin_read_summit_2026_sessoes(v_sessao.id);
  if jsonb_array_length(v_um) <> 1 or v_um->0->>'titulo' <> v_sessao.titulo
     or (v_um->0->>'inicio')::timestamptz <> v_sessao.inicio then
    raise exception 'QUEBRADA (3): %', v_um;
  end if;
  if v_um->0->>'espaco' is distinct from (select nome from summit_2026.locations where id = v_sessao.espaco_id) then
    raise exception 'QUEBRADA (3b): espaço %', v_um->0->>'espaco';
  end if;
  if jsonb_array_length(v_um->0->'palestrantes') <> (
       select count(*) from summit_2026.session_speakers ss
         join ecossistema.palestrantes_especialistas pe on pe.id = ss.speaker_id
        where ss.sessao_id = v_sessao.id) then
    raise exception 'QUEBRADA (3c): palestrantes %', v_um->0->'palestrantes';
  end if;

  -- 4. Id que não existe volta vazio.
  if jsonb_array_length(public.mind_admin_read_summit_2026_sessoes(gen_random_uuid())) <> 0 then
    raise exception 'QUEBRADA (4): id inexistente devia voltar vazio';
  end if;

  -- 5. Só o service_role executa.
  if has_function_privilege('anon', 'public.mind_admin_read_summit_2026_sessoes(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.mind_admin_read_summit_2026_sessoes(uuid)', 'execute') then
    raise exception 'QUEBRADA (5): porta aberta para anon ou authenticated';
  end if;
  if not has_function_privilege('service_role', 'public.mind_admin_read_summit_2026_sessoes(uuid)', 'execute') then
    raise exception 'QUEBRADA (5b): service_role não executa';
  end if;

  -- 6. É leitura: a função é STABLE e não escreve.
  if (select provolatile from pg_proc where proname = 'mind_admin_read_summit_2026_sessoes') <> 's' then
    raise exception 'QUEBRADA (6): a porta devia ser STABLE';
  end if;

  raise exception 'SUMMIT_PROGRAMACAO_OK: 6 casos';
end
$$;

rollback;
