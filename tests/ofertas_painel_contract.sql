-- Contrato das portas de leitura de ofertas e cupons do painel (migration
-- 20260926202049_ofertas_e_cupons_no_painel_leitura). Sempre termina em rollback: a exceção
-- OFERTAS_PAINEL_OK é o resultado. As linhas de teste ("contrato-…") somem com o rollback.
begin;
do $$
declare
  v_prod uuid;
  v_agora timestamptz := now();
  v_lista jsonb;
  v_um jsonb;
  n int;
begin
  -- 1. leitura: todas as ofertas, no formato do contrato
  v_lista := public.mind_admin_read_ofertas();
  select count(*) into n from catalogo.ofertas;
  if jsonb_array_length(v_lista) <> n then
    raise exception 'ofertas: % na leitura, % no catálogo', jsonb_array_length(v_lista), n; end if;
  if exists (select 1 from jsonb_array_elements(v_lista) e
              where e->>'id' is null or e->>'codigo' is null or e->>'nome' is null or e->>'tipo' is null
                 or e->>'situacao' is null or e->>'atualizadoEm' is null
                 or jsonb_typeof(e->'precos') <> 'array' or jsonb_typeof(e->'bonus') <> 'array'
                 or jsonb_typeof(e->'requer') <> 'array' or jsonb_typeof(e->'noSite') <> 'boolean') then
    raise exception 'ofertas: item fora do contrato'; end if;
  if (select coalesce(sum(jsonb_array_length(e->'precos')), 0) from jsonb_array_elements(v_lista) e)
     <> (select count(*) from catalogo.oferta_precos) then
    raise exception 'ofertas: faltou linha de preço na leitura'; end if;

  -- noSite é o que o site lê de verdade: o código vendável está em api.ofertas
  if exists (
    select 1 from jsonb_array_elements(v_lista) e, jsonb_array_elements(e->'precos') p
     where (p->>'noSite')::boolean is distinct from exists (select 1 from api.ofertas a where a.codigo = p->>'codigo')
  ) then raise exception 'ofertas: noSite não bate com api.ofertas'; end if;

  -- o preço da Eduzz é o da cópia, pelo código do produto lá
  if exists (
    select 1 from jsonb_array_elements(v_lista) e, jsonb_array_elements(e->'precos') p
      join eduzz.produtos ez on ez.eduzz_product_id = p->>'skuExterno'
     where (p->'eduzz'->>'preco')::numeric is distinct from ez.price_value
  ) then raise exception 'ofertas: preço da Eduzz não bate com a cópia'; end if;

  -- por id: um; inexistente: nenhum
  select id into v_prod from catalogo.ofertas order by codigo limit 1;
  v_um := public.mind_admin_read_ofertas(v_prod);
  if jsonb_array_length(v_um) <> 1 or v_um->0->>'id' <> v_prod::text then raise exception 'ofertas: leitura por id'; end if;
  if jsonb_array_length(public.mind_admin_read_ofertas(gen_random_uuid())) <> 0 then
    raise exception 'ofertas: id inexistente devia voltar vazio'; end if;

  -- 2. situação: cada combinação vira o rótulo certo (ofertas de teste, desfeitas no fim)
  insert into catalogo.ofertas (codigo, nome, tipo, ativo, publico, historico, inicia_em, encerra_em) values
    ('contrato-no-ar', 'X', 'base', true, true, false, null, null),
    ('contrato-so-link', 'X', 'base', true, false, false, null, null),
    ('contrato-agendada', 'X', 'periodo', true, true, false, v_agora + interval '1 day', v_agora + interval '2 days'),
    ('contrato-encerrada', 'X', 'periodo', true, true, false, v_agora - interval '2 days', v_agora - interval '1 day'),
    ('contrato-no-fim', 'X', 'periodo', true, true, false, v_agora - interval '1 day', v_agora),
    ('contrato-desligada', 'X', 'base', false, true, false, null, null),
    ('contrato-historico', 'X', 'base', true, true, true, null, null);
  if exists (
    select 1 from jsonb_array_elements(public.mind_admin_read_ofertas(null, v_agora)) e
     where e->>'codigo' like 'contrato-%'
       and e->>'situacao' is distinct from case e->>'codigo'
             when 'contrato-no-ar' then 'no_ar' when 'contrato-so-link' then 'so_link'
             when 'contrato-agendada' then 'agendada' when 'contrato-encerrada' then 'encerrada'
             when 'contrato-no-fim' then 'no_ar' when 'contrato-desligada' then 'desligada'
             when 'contrato-historico' then 'historico' end
  ) then raise exception 'ofertas: situação calculada errada'; end if;
  -- a ordem da lista: no ar primeiro, histórico por último
  if (select e->>'situacao' from jsonb_array_elements(public.mind_admin_read_ofertas(null, v_agora)) with ordinality t(e, i)
       order by i limit 1) <> 'no_ar' then raise exception 'ofertas: no ar devia vir primeiro'; end if;

  -- 3. cupons
  v_lista := public.mind_admin_read_cupons();
  select count(*) into n from catalogo.cupons;
  if jsonb_array_length(v_lista) <> n then raise exception 'cupons: % na leitura, % no catálogo', jsonb_array_length(v_lista), n; end if;
  if exists (select 1 from jsonb_array_elements(v_lista) e
              where e->>'id' is null or e->>'codigo' is null or e->>'situacao' is null or e->>'atualizadoEm' is null
                 or jsonb_typeof(e->'ativo') <> 'boolean' or jsonb_typeof(e->'produtos') <> 'array') then
    raise exception 'cupons: item fora do contrato'; end if;
  insert into catalogo.cupons (codigo, tipo, valor, ativo, historico, inicia_em, encerra_em, usos_maximos, usos) values
    ('contrato-valendo', 'valor', 10, true, false, null, null, null, 0),
    ('contrato-agendado', 'valor', 10, true, false, v_agora + interval '1 day', null, null, 0),
    ('contrato-encerrado', 'valor', 10, true, false, null, v_agora - interval '1 day', null, 0),
    ('contrato-esgotado', 'valor', 10, true, false, null, null, 3, 3),
    ('contrato-desligado', 'valor', 10, false, false, null, null, null, 0),
    ('contrato-historico', 'valor', 10, false, true, null, null, null, 0);
  if exists (
    select 1 from jsonb_array_elements(public.mind_admin_read_cupons(null, v_agora)) e
     where e->>'codigo' like 'contrato-%'
       and e->>'situacao' is distinct from case e->>'codigo'
             when 'contrato-valendo' then 'valendo' when 'contrato-agendado' then 'agendado'
             when 'contrato-encerrado' then 'encerrado' when 'contrato-esgotado' then 'esgotado'
             when 'contrato-desligado' then 'desligado' when 'contrato-historico' then 'historico' end
  ) then raise exception 'cupons: situação calculada errada'; end if;
  if jsonb_array_length(public.mind_admin_read_cupons(gen_random_uuid())) <> 0 then
    raise exception 'cupons: id inexistente devia voltar vazio'; end if;

  -- 4. só o service_role executa as duas portas
  if has_function_privilege('anon', 'public.mind_admin_read_ofertas(uuid,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.mind_admin_read_ofertas(uuid,timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.mind_admin_read_cupons(uuid,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.mind_admin_read_cupons(uuid,timestamptz)', 'execute') then
    raise exception 'anon/authenticated não podem ler ofertas e cupons pelo painel'; end if;
  if not has_function_privilege('service_role', 'public.mind_admin_read_ofertas(uuid,timestamptz)', 'execute')
     or not has_function_privilege('service_role', 'public.mind_admin_read_cupons(uuid,timestamptz)', 'execute') then
    raise exception 'o service_role precisa ler ofertas e cupons'; end if;

  raise exception 'OFERTAS_PAINEL_OK: leitura de ofertas (todas, uma, inexistente, preços completos, noSite = api.ofertas, preço da Eduzz = cópia), situação das ofertas e dos cupons em cada combinação, no ar primeiro, e só o service_role lê';
end $$;
rollback;
