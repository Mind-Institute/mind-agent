-- VOLTA DA VIRADA DO PASSO 5: O SITE DO INSTITUTE VOLTA A LER A CASA ANTIGA (institute.*).
--
-- Só para emergência, e só com o OK da Adriana: é troca de autoridade de novo (D2). Ensaiada junto com a
-- virada (tests/virada_institute_contract.sql). Aplica-se como migration, numa transação só.
--
-- A volta não pode desfazer em silêncio o que foi mudado no painel depois da virada. Por isso, antes de as
-- portas voltarem, a casa antiga recebe o que está no catálogo AGORA:
--   · cada preço de produto do Institute que um leitor vê (catalogo.institute_ofertas) vira — ou atualiza —
--     uma linha de institute.ofertas, com o mesmo código: uma linha por programa do Institute;
--   · os bônus e as regras de order bump dessas ofertas são regravados a partir do catálogo;
--   · rascunho que nunca foi ao ar não vai: nunca chegou ao site.
-- Depois: as 3 funções de pedido voltam a ler institute.ofertas; as 3 portas voltam às definições de antes da
-- virada; o congelamento sai (o /admin do Join volta a editar); e a view interna catalogo.institute_ofertas sai.
--
-- As ofertas continuam no catálogo, com a origem. "Pôr no ar" trava de novo sozinho, porque api.ofertas deixa
-- de ler o catálogo. Enquanto a virada não for refeita, mudar uma oferta do Institute no painel não chega ao site.
--
-- Conferido na mesma transação, com o mesmo relógio: as portas entregam o que entregavam antes da volta
-- (api.ofertas volta a mostrar também oferta ligada fora do prazo, como antes da virada: compara-se o que está
-- valendo; e o bump volta a ter programa, se 03-bump-fora-da-lista.sql tiver rodado), o bloco do agente fica igual,
-- e as funções só com o nome trocado de volta.

-- ---------------------------------------------------------------------------------------------------
-- 0. SÓ DEPOIS DA VIRADA
-- ---------------------------------------------------------------------------------------------------
do $$
begin
  if to_regclass('catalogo.institute_ofertas') is null
     or not exists (
       select 1
         from pg_depend d
         join pg_rewrite rw on rw.oid = d.objid
        where d.classid = 'pg_rewrite'::regclass and d.refclassid = 'pg_class'::regclass
          and rw.ev_class = 'api.ofertas'::regclass and d.refobjid = 'catalogo.institute_ofertas'::regclass
     ) then
    raise exception 'volta: a virada não está aplicada';
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------
-- 1. FOTO DO QUE AS PORTAS ENTREGAM AGORA
-- ---------------------------------------------------------------------------------------------------
create temp table volta_antes_ofertas on commit drop as select * from api.ofertas;
create temp table volta_antes_bumps on commit drop as select * from api.bump_regras;
create temp table volta_antes_inclui on commit drop as select * from api.oferta_inclui;
create temp table volta_antes_bloco on commit drop as
  select public.mind_kit_institute_catalogo(null::uuid, '{}'::jsonb) as bloco;
create temp table volta_antes_funcoes on commit drop as
  select p.oid::regprocedure::text as nome,
         jsonb_build_object(
           'dono', p.proowner::regrole::text,
           'acl', p.proacl::text,
           'definer', p.prosecdef,
           'config', to_jsonb(p.proconfig),
           'volatil', p.provolatile,
           'resultado', pg_get_function_result(p.oid),
           'argumentos', pg_get_function_arguments(p.oid),
           'corpo', replace(p.prosrc, 'catalogo.institute_ofertas', 'institute.ofertas')
         ) as meta
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'api' and p.proname in ('criar_pedido', 'validar_cupom', 'cadastrar_compra_manual');

-- ---------------------------------------------------------------------------------------------------
-- 2. A CASA ANTIGA DESCONGELA E RECEBE O QUE ESTÁ NO CATÁLOGO AGORA
-- ---------------------------------------------------------------------------------------------------
drop trigger casa_antiga_congelada on institute.ofertas;
drop trigger casa_antiga_congelada on institute.oferta_bonus;
drop trigger casa_antiga_congelada on institute.bump_regras;
drop function institute.casa_antiga_congelada();

-- As ofertas: atualiza as que já existiam (só se algo mudou) e cria as novas do painel.
insert into institute.ofertas as io
  (codigo, programa_codigo, nome, descricao, moeda, valor, parcelas, valor_parcela, meios_pagamento,
   valor_referencia, checkout_url, elegibilidade, publico, ativo, inicia_em, encerra_em)
select h.codigo, h.programa_codigo, h.nome, h.descricao, h.moeda, h.valor, h.parcelas, h.valor_parcela,
       h.meios_pagamento, h.valor_referencia, h.checkout_url, h.elegibilidade, h.publico, h.ativo and not h.historico,
       h.inicia_em, h.encerra_em
  from catalogo.institute_ofertas h
on conflict (codigo) do update set
  programa_codigo = excluded.programa_codigo,
  nome = excluded.nome,
  descricao = excluded.descricao,
  moeda = excluded.moeda,
  valor = excluded.valor,
  parcelas = excluded.parcelas,
  valor_parcela = excluded.valor_parcela,
  meios_pagamento = excluded.meios_pagamento,
  valor_referencia = excluded.valor_referencia,
  checkout_url = excluded.checkout_url,
  elegibilidade = excluded.elegibilidade,
  publico = excluded.publico,
  ativo = excluded.ativo,
  inicia_em = excluded.inicia_em,
  encerra_em = excluded.encerra_em,
  atualizado_em = now()
where (io.programa_codigo, io.nome, io.descricao, io.moeda, io.valor, io.parcelas, io.valor_parcela,
       io.meios_pagamento, io.valor_referencia, io.checkout_url, io.elegibilidade, io.publico, io.ativo,
       io.inicia_em, io.encerra_em)
      is distinct from
      (excluded.programa_codigo, excluded.nome, excluded.descricao, excluded.moeda, excluded.valor,
       excluded.parcelas, excluded.valor_parcela, excluded.meios_pagamento, excluded.valor_referencia,
       excluded.checkout_url, excluded.elegibilidade, excluded.publico, excluded.ativo, excluded.inicia_em,
       excluded.encerra_em);

-- Os bônus dessas ofertas, regravados. A ordem é renumerada na ordem que o site mostrava.
delete from institute.oferta_bonus b
 where b.oferta_codigo in (select h.codigo from catalogo.institute_ofertas h);
insert into institute.oferta_bonus
  (oferta_codigo, nome, descricao, valor_referencia, gratuito, ordem, programa_codigo, detalhe, nota, inicia_em, encerra_em)
select h.codigo, coalesce(oi.nome, inc.nome), oi.descricao, oi.valor_referencia, oi.valor = 0,
       row_number() over (partition by h.codigo order by oi.ordem, inc.codigo)::smallint,
       pr.codigo, oi.detalhe, oi.nota, oi.inicia_em, oi.encerra_em
  from catalogo.institute_ofertas h
  join catalogo.oferta_inclui oi on oi.oferta_id = h.oferta_id and oi.produto_id = h.produto_id
  join catalogo.produtos inc on inc.id = oi.incluso_id
  left join institute.programas pr on pr.produto_codigo = inc.codigo;

-- As regras de order bump dessas ofertas, regravadas a partir das exigências de carrinho.
delete from institute.bump_regras r
 where r.oferta_bump_codigo in (select h.codigo from catalogo.institute_ofertas h);
insert into institute.bump_regras
  (gatilho_programa_codigo, oferta_bump_codigo, prioridade, grupo_exclusivo, ativo, inicia_em, encerra_em, observacao)
select gp.codigo, h.codigo, rq.prioridade, rq.grupo_exclusivo, rq.ativo, rq.inicia_em, rq.encerra_em, rq.observacao
  from catalogo.institute_ofertas h
  join catalogo.oferta_requer rq on rq.oferta_id = h.oferta_id and rq.modo = 'carrinho'
  join catalogo.produtos gpp on gpp.id = rq.produto_id
  join institute.programas gp on gp.produto_codigo = gpp.codigo
 where h.eh_bump;

-- ---------------------------------------------------------------------------------------------------
-- 3. AS FUNÇÕES DE PEDIDO VOLTAM A LER A CASA ANTIGA
-- ---------------------------------------------------------------------------------------------------
do $$
declare
  r record;
  v_def text;
  v_vezes int;
  v_esperado constant jsonb := '{"criar_pedido": 5, "validar_cupom": 2, "cadastrar_compra_manual": 2}';
begin
  for r in
    select p.oid, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'api' and p.proname in ('criar_pedido', 'validar_cupom', 'cadastrar_compra_manual')
  loop
    v_def := pg_get_functiondef(r.oid);
    v_vezes := (length(v_def) - length(replace(v_def, 'catalogo.institute_ofertas', '')))
               / length('catalogo.institute_ofertas');
    if v_vezes <> (v_esperado->>r.proname)::int then
      raise exception 'volta: api.% cita catalogo.institute_ofertas % vezes, esperava %',
        r.proname, v_vezes, v_esperado->>r.proname;
    end if;
    execute replace(v_def, 'catalogo.institute_ofertas', 'institute.ofertas');
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------------
-- 4. AS PORTAS VOLTAM ÀS DEFINIÇÕES DE ANTES DA VIRADA (por último)
-- ---------------------------------------------------------------------------------------------------
select set_config('volta.troca_inicio', clock_timestamp()::text, true);
set local lock_timeout = '1s';

create or replace view api.ofertas with (security_invoker = false) as
select o.codigo,
       o.programa_codigo,
       o.produto_codigo,
       o.nome,
       o.descricao,
       o.moeda,
       o.valor,
       o.parcelas,
       o.valor_parcela,
       o.condicoes_pagamento,
       o.meios_pagamento,
       o.valor_referencia,
       o.economia,
       o.checkout_url,
       o.inicia_em,
       o.encerra_em,
       now() >= coalesce(o.inicia_em, '-infinity'::timestamptz)
         and now() <= coalesce(o.encerra_em, 'infinity'::timestamptz) as vigente,
       coalesce((
         select jsonb_agg(jsonb_build_object(
                  'nome', b.nome,
                  'descricao', b.descricao,
                  'detalhe', b.detalhe,
                  'nota', b.nota,
                  'valor_referencia', b.valor_referencia,
                  'gratuito', b.gratuito,
                  'inicia_em', b.inicia_em,
                  'encerra_em', b.encerra_em,
                  'vigente', now() >= coalesce(b.inicia_em, '-infinity'::timestamptz)
                             and now() <= coalesce(b.encerra_em, 'infinity'::timestamptz))
                order by b.ordem)
           from institute.oferta_bonus b
          where b.oferta_codigo = o.codigo
       ), '[]'::jsonb) as bonus,
       o.elegibilidade
  from institute.ofertas o
 where o.ativo and o.publico;

create or replace view api.bump_regras as
select r.gatilho_programa_codigo,
       r.oferta_bump_codigo,
       r.prioridade,
       r.grupo_exclusivo,
       o.nome as oferta_nome,
       o.descricao as oferta_descricao,
       o.valor as oferta_valor,
       o.programa_codigo as oferta_programa_codigo,
       (o.elegibilidade->>'valor_riscado')::numeric as oferta_valor_riscado
  from institute.bump_regras r
  join institute.ofertas o on o.codigo = r.oferta_bump_codigo
 where r.ativo and o.ativo and o.publico
   and now() >= coalesce(r.inicia_em, '-infinity'::timestamptz)
   and now() <= coalesce(r.encerra_em, 'infinity'::timestamptz)
   and now() >= coalesce(o.inicia_em, '-infinity'::timestamptz)
   and now() <= coalesce(o.encerra_em, 'infinity'::timestamptz);

create or replace view api.oferta_inclui as
select b.oferta_codigo,
       b.programa_codigo
  from institute.oferta_bonus b
 where b.programa_codigo is not null
union
select o.codigo as oferta_codigo,
       c.item_codigo as programa_codigo
  from institute.ofertas o
  join institute.programa_composicao c on c.programa_codigo = o.programa_codigo and c.incluso;

-- A view interna sai: mais ninguém lê dela.
drop view catalogo.institute_ofertas;

-- ---------------------------------------------------------------------------------------------------
-- 5. CONFERÊNCIA, COM O MESMO RELÓGIO (se falhar, a volta não acontece)
-- ---------------------------------------------------------------------------------------------------
do $$
declare
  v_ms numeric;
begin
  -- O programa do bump não entra na comparação: se 03-bump-fora-da-lista.sql rodou, ele vinha vazio na porta.
  if exists ((select codigo, case when elegibilidade->>'tipo' = 'order_bump' then null else programa_codigo end,
                     produto_codigo, nome, descricao, moeda, valor, parcelas, valor_parcela, condicoes_pagamento,
                     meios_pagamento, valor_referencia, economia, checkout_url, inicia_em, encerra_em, vigente, bonus,
                     elegibilidade
                from volta_antes_ofertas
              except
              select codigo, case when elegibilidade->>'tipo' = 'order_bump' then null else programa_codigo end,
                     produto_codigo, nome, descricao, moeda, valor, parcelas, valor_parcela, condicoes_pagamento,
                     meios_pagamento, valor_referencia, economia, checkout_url, inicia_em, encerra_em, vigente, bonus,
                     elegibilidade
                from api.ofertas where vigente)
             union all
             (select codigo, case when elegibilidade->>'tipo' = 'order_bump' then null else programa_codigo end,
                     produto_codigo, nome, descricao, moeda, valor, parcelas, valor_parcela, condicoes_pagamento,
                     meios_pagamento, valor_referencia, economia, checkout_url, inicia_em, encerra_em, vigente, bonus,
                     elegibilidade
                from api.ofertas where vigente
              except
              select codigo, case when elegibilidade->>'tipo' = 'order_bump' then null else programa_codigo end,
                     produto_codigo, nome, descricao, moeda, valor, parcelas, valor_parcela, condicoes_pagamento,
                     meios_pagamento, valor_referencia, economia, checkout_url, inicia_em, encerra_em, vigente, bonus,
                     elegibilidade
                from volta_antes_ofertas))
     or (select count(*) from api.ofertas where vigente) <> (select count(*) from volta_antes_ofertas) then
    raise exception 'volta: api.ofertas mudou';
  end if;
  if exists ((select * from volta_antes_bumps except select * from api.bump_regras)
             union all
             (select * from api.bump_regras except select * from volta_antes_bumps))
     or (select count(*) from api.bump_regras) <> (select count(*) from volta_antes_bumps) then
    raise exception 'volta: api.bump_regras mudou';
  end if;
  if exists ((select * from volta_antes_inclui except select * from api.oferta_inclui)
             union all
             (select * from api.oferta_inclui except select * from volta_antes_inclui))
     or (select count(*) from api.oferta_inclui) <> (select count(*) from volta_antes_inclui) then
    raise exception 'volta: api.oferta_inclui mudou';
  end if;
  if (select bloco from volta_antes_bloco)
     is distinct from public.mind_kit_institute_catalogo(null::uuid, '{}'::jsonb) then
    raise exception 'volta: o bloco do agente mudou';
  end if;
  if exists (
    select 1
      from volta_antes_funcoes m
      join pg_proc p on p.oid = m.nome::regprocedure
     where jsonb_build_object(
             'dono', p.proowner::regrole::text,
             'acl', p.proacl::text,
             'definer', p.prosecdef,
             'config', to_jsonb(p.proconfig),
             'volatil', p.provolatile,
             'resultado', pg_get_function_result(p.oid),
             'argumentos', pg_get_function_arguments(p.oid),
             'corpo', p.prosrc
           ) is distinct from m.meta
  ) or (select count(*) from volta_antes_funcoes) <> 3 then
    raise exception 'volta: função de pedido mudou além do nome';
  end if;

  v_ms := extract(epoch from clock_timestamp() - current_setting('volta.troca_inicio')::timestamptz) * 1000;
  if v_ms > 1000 then
    raise exception 'volta: a troca das portas levou % ms (o limite é 1000)', round(v_ms);
  end if;
end $$;
