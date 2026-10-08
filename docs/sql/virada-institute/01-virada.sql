-- VIRADA: O SITE DO INSTITUTE PASSA A LER O CATÁLOGO (PASSO 5 DE docs/PLANO_OFERTAS_PASSO_A_PASSO.md).
--
-- Aprovada no plano (D2). Em 27/09/2026 a Adriana ficou com o sinal da hora: só é aplicada quando ela escreve
-- "pode virar", com apply_migration e o nome virada_institute_le_o_catalogo, e então vai para
-- supabase/migrations/ com a versão do registro. Logo depois, no mesmo sinal, vem bump_fora_da_lista_de_precos.
--
-- Decisões da Adriana (26/09/2026): "no schema catálogo deve organizar as tabelas de preço, oferta, order
-- bump, cupom"; "todas as infos importantes deste schema devem ser espelhadas e editáveis via painel"; os
-- sites leem direto — as mesmas views api.* passam a ler o catalogo, sem cópia por cron; "não tira bumps do
-- ar"; e a virada vem antes de 30/09 23h59 ("vamos ter migrado antes disso"). É troca de autoridade (D2),
-- aprovada no plano.
--
-- O que muda, numa transação só (entra tudo ou nada):
--   1. carga das ofertas do Institute no catálogo, uma por código antigo, copiada DENTRO do banco — nenhum
--      preço, link ou texto de oferta fica escrito neste arquivo, que vai para um repositório público:
--        · cada linha de institute.ofertas vira uma oferta com um preço; o código vendável é o mesmo;
--        · os 2 testes entram como histórico (só leitura); o teste sem programa entra sem preço;
--        · os bônus viram oferta_inclui: o Journey aponta para o produto do Journey; o ingresso do
--          Mind Summit 2027 aponta para mind-summit-2027-mind (desligado, criado no Passo 3), que não é
--          programa do Institute e por isso não abre acesso a nada;
--        · as regras de order bump viram exigência de carrinho (oferta_requer);
--        · cada linha guarda de onde veio (origem), com a linha original inteira;
--   2. catalogo.institute_ofertas: as ofertas do Institute na forma de institute.ofertas, lidas do catálogo.
--      Rascunho que nunca foi ao ar e upgrade (exigência de posse) ficam de fora: o checkout do Institute
--      não sabe conferir posse;
--   3. as 3 funções que leem oferta (api.criar_pedido, api.validar_cupom e api.cadastrar_compra_manual)
--      passam a ler catalogo.institute_ofertas no lugar de institute.ofertas — só esse nome muda nelas;
--   4. "pôr no ar" destrava para os produtos do Institute: catalogo.produto_tem_leitor passa a reconhecer
--      a leitura do catálogo por qualquer relação do schema, e não só por catalogo.ofertas;
--   5. as 3 tabelas antigas congelam e recusam qualquer escrita. Com isso o /admin do Join deixa de editar
--      ofertas e bumps: as 5 funções de edição dele respondem onde editar agora. Cupom não muda;
--   6. por último, as 3 portas do site passam a ler o catálogo, com as mesmas colunas, tipos, dono,
--      permissões e opções:
--        · api.ofertas entrega só o que está valendo agora (decisão 8);
--        · api.bump_regras, com a mesma regra de antes;
--        · api.oferta_inclui, sem filtro: é por ela que um pedido pago abre o acesso.
--      As portas só alcançam produtos que têm programa no Institute.
--
-- Conferido dentro da própria transação, com o mesmo relógio antes e depois. Qualquer diferença desfaz tudo:
--   · api.ofertas = o que ela entregava e estava valendo; api.bump_regras e api.oferta_inclui iguais,
--     linha a linha;
--   · o bloco do agente (mind_kit_institute_catalogo) igual;
--   · a fonte das funções de pedido igual, código a código, com a exceção aprovada: o teste sem programa
--     deixa de ter preço;
--   · colunas, tipos, dono, permissões e opções das portas; dono, permissões, modo de segurança,
--     search_path e volatilidade das funções, e o corpo delas só com a troca do nome.
-- A troca das portas vai por último, espera no máximo 1 s por trava e, com a conferência final, tem de
-- levar menos de 1 s. Se não der, nada acontece.
--
-- Volta: docs/sql/virada-institute/02-volta.sql. Contrato: tests/virada_institute_contract.sql.

-- ---------------------------------------------------------------------------------------------------
-- 0. A CASA ANTIGA TEM A FORMA QUE ESTA CARGA CONHECE (senão, nada acontece)
-- ---------------------------------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from catalogo.ofertas where origem->>'tabela' = 'institute.ofertas') then
    raise exception 'virada: as ofertas do Institute já estão no catálogo';
  end if;
  if exists (
    select 1
      from pg_depend d
      join pg_rewrite rw on rw.oid = d.objid
      join pg_class c on c.oid = d.refobjid
     where d.classid = 'pg_rewrite'::regclass and d.refclassid = 'pg_class'::regclass
       and rw.ev_class = 'api.ofertas'::regclass and c.relnamespace = 'catalogo'::regnamespace
  ) then
    raise exception 'virada: api.ofertas já lê o catálogo';
  end if;

  -- Desligados, só os 2 testes: eles viram histórico. O de R$ 1 do Journey entra assim para ninguém
  -- pô-lo no ar por engano.
  if (select count(*) from institute.ofertas where codigo in ('teste-1-real', 'teste-um-centavo') and not ativo) <> 2
     or exists (select 1 from institute.ofertas where not ativo and codigo not in ('teste-1-real', 'teste-um-centavo')) then
    raise exception 'virada: esperava desligados só os 2 testes';
  end if;
  -- Sem programa, só o teste; e cada programa com oferta tem o produto dele no catálogo, um para um.
  if exists (select 1 from institute.ofertas where programa_codigo is null and codigo <> 'teste-um-centavo') then
    raise exception 'virada: oferta sem programa além do teste';
  end if;
  if exists (
    select 1 from institute.ofertas io
     where io.programa_codigo is not null
       and not exists (select 1 from institute.programas pr join catalogo.produtos p on p.codigo = pr.produto_codigo
                        where pr.codigo = io.programa_codigo)
  ) then
    raise exception 'virada: oferta de programa sem produto no catálogo';
  end if;
  if exists (select 1 from institute.programas where produto_codigo is not null group by produto_codigo having count(*) > 1) then
    raise exception 'virada: dois programas apontam para o mesmo produto';
  end if;
  -- O que não tem coluna no catálogo está vazio nas 16.
  if exists (select 1 from institute.ofertas
              where produto_codigo is not null or condicoes_pagamento is not null
                 or valor_referencia is not null or economia is not null) then
    raise exception 'virada: oferta com produto_codigo, condições em texto, valor de referência ou economia';
  end if;
  -- elegibilidade: order bump e nada mais; o preço riscado só em bump; "tela" é só registro.
  if exists (select 1 from institute.ofertas io, jsonb_object_keys(io.elegibilidade) k
              where k not in ('tipo', 'requer_no_carrinho', 'valor_riscado', 'tela'))
     or exists (select 1 from institute.ofertas where elegibilidade ? 'tipo' and elegibilidade->>'tipo' <> 'order_bump')
     or exists (select 1 from institute.ofertas where elegibilidade ? 'valor_riscado' and coalesce(elegibilidade->>'tipo', '') <> 'order_bump') then
    raise exception 'virada: elegibilidade que a carga não conhece';
  end if;
  -- Cada bump: as regras ligadas dele são exatamente o que ele exige no carrinho; toda regra é de um bump.
  if exists (
    select 1 from institute.ofertas io
     where io.elegibilidade->>'tipo' = 'order_bump'
       and (select coalesce(array_agg(x order by x), '{}') from jsonb_array_elements_text(io.elegibilidade->'requer_no_carrinho') x)
           is distinct from
           (select coalesce(array_agg(r.gatilho_programa_codigo order by r.gatilho_programa_codigo), '{}')
              from institute.bump_regras r where r.oferta_bump_codigo = io.codigo and r.ativo)
  ) or exists (
    select 1 from institute.bump_regras r
      left join institute.ofertas io on io.codigo = r.oferta_bump_codigo
     where io.codigo is null or coalesce(io.elegibilidade->>'tipo', '') <> 'order_bump' or not r.ativo
        or not exists (select 1 from institute.programas pr join catalogo.produtos p on p.codigo = pr.produto_codigo
                        where pr.codigo = r.gatilho_programa_codigo)
  ) then
    raise exception 'virada: regra de bump não bate com a oferta';
  end if;
  -- Bônus: todos de graça; sem programa, só o ingresso do Summit 2027, que tem produto.
  if exists (select 1 from institute.oferta_bonus where not gratuito) then
    raise exception 'virada: bônus pago';
  end if;
  if exists (select 1 from institute.oferta_bonus
              where programa_codigo is null and nome <> 'Ingresso categoria Mind para o Mind Summit 2027')
     or not exists (select 1 from catalogo.produtos where codigo = 'mind-summit-2027-mind') then
    raise exception 'virada: bônus sem programa que não é o ingresso do Summit 2027';
  end if;
  if exists (select 1 from institute.oferta_bonus b
              where not exists (select 1 from institute.ofertas io where io.codigo = b.oferta_codigo and io.programa_codigo is not null)
                 or (b.programa_codigo is not null
                     and not exists (select 1 from institute.programas pr join catalogo.produtos p on p.codigo = pr.produto_codigo
                                      where pr.codigo = b.programa_codigo))) then
    raise exception 'virada: bônus sem oferta com preço ou sem produto';
  end if;
  -- Nenhum código antigo já usado no catálogo, e nenhum preço de produto do Institute no ar por lá
  -- ("pôr no ar" estava travado até agora).
  if exists (select 1 from institute.ofertas io
              where exists (select 1 from catalogo.ofertas o where o.codigo = io.codigo)
                 or exists (select 1 from catalogo.oferta_precos op where op.codigo = io.codigo)) then
    raise exception 'virada: código antigo já usado no catálogo';
  end if;
  if exists (select 1 from catalogo.oferta_precos op
               join catalogo.ofertas o on o.id = op.oferta_id
               join catalogo.produtos p on p.id = op.produto_id
               join institute.programas pr on pr.produto_codigo = p.codigo
              where o.ativo) then
    raise exception 'virada: já há oferta de produto do Institute no ar no catálogo';
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------
-- 1. FOTO DO ANTES. now() é o da transação: o mesmo relógio vale antes e depois.
-- ---------------------------------------------------------------------------------------------------
create temp table virada_antes_ofertas on commit drop as select * from api.ofertas;
create temp table virada_antes_bumps on commit drop as select * from api.bump_regras;
create temp table virada_antes_inclui on commit drop as select * from api.oferta_inclui;
create temp table virada_antes_bloco on commit drop as
  select public.mind_kit_institute_catalogo(null::uuid, '{}'::jsonb) as bloco;
create temp table virada_antes_meta on commit drop as
  select 'porta' as tipo, c.oid::regclass::text as nome,
         jsonb_build_object(
           'dono', c.relowner::regrole::text,
           'acl', c.relacl::text,
           'opcoes', to_jsonb(c.reloptions),
           'colunas', (select jsonb_agg(jsonb_build_array(a.attname, format_type(a.atttypid, a.atttypmod), a.attcollation::regcollation::text)
                                        order by a.attnum)
                         from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped)
         ) as meta
    from pg_class c
   where c.oid in ('api.ofertas'::regclass, 'api.bump_regras'::regclass, 'api.oferta_inclui'::regclass)
  union all
  select 'funcao', p.oid::regprocedure::text,
         jsonb_build_object(
           'dono', p.proowner::regrole::text,
           'acl', p.proacl::text,
           'definer', p.prosecdef,
           'config', to_jsonb(p.proconfig),
           'volatil', p.provolatile,
           'resultado', pg_get_function_result(p.oid),
           'argumentos', pg_get_function_arguments(p.oid),
           'corpo', replace(p.prosrc, 'institute.ofertas', 'catalogo.institute_ofertas')
         )
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'api' and p.proname in ('criar_pedido', 'validar_cupom', 'cadastrar_compra_manual');

-- ---------------------------------------------------------------------------------------------------
-- 2. CARGA
-- ---------------------------------------------------------------------------------------------------

-- 16 ofertas, uma por linha antiga, com a linha inteira em origem.dados.
insert into catalogo.ofertas
  (codigo, nome, descricao, tipo, ativo, publico, inicia_em, encerra_em, meios_pagamento, historico,
   criado_em, atualizado_em, origem)
select io.codigo, io.nome, io.descricao,
       case when io.elegibilidade->>'tipo' = 'order_bump' then 'condicional'
            when io.inicia_em is not null or io.encerra_em is not null then 'periodo'
            else 'base' end,
       io.ativo, io.publico, io.inicia_em, io.encerra_em, io.meios_pagamento,
       io.codigo in ('teste-1-real', 'teste-um-centavo'),
       io.criado_em, io.atualizado_em,
       jsonb_build_object('tabela', 'institute.ofertas', 'id', io.id::text, 'codigo', io.codigo,
                          'importado_em', now(), 'confianca', 'copia_viva', 'dados', to_jsonb(io))
  from institute.ofertas io;

-- Um preço por oferta que tem programa: o produto é o do programa. Nome e descrição ficam na oferta
-- (vazio no preço = o da oferta), para uma mudança no painel valer para os dois.
insert into catalogo.oferta_precos
  (oferta_id, produto_id, codigo, nome, descricao, valor, parcelas, valor_parcela, moeda, ordem,
   checkout_url, valor_riscado, origem)
select o.id, p.id, io.codigo, null, null, io.valor, io.parcelas, io.valor_parcela, io.moeda::text, 1,
       io.checkout_url, (io.elegibilidade->>'valor_riscado')::numeric,
       jsonb_build_object('tabela', 'institute.ofertas', 'id', io.id::text, 'codigo', io.codigo,
                          'importado_em', now(), 'confianca', 'copia_viva')
  from institute.ofertas io
  join catalogo.ofertas o on o.origem->>'tabela' = 'institute.ofertas' and o.origem->>'id' = io.id::text
  join institute.programas pr on pr.codigo = io.programa_codigo
  join catalogo.produtos p on p.codigo = pr.produto_codigo;

-- Bônus: o produto que vem junto. De graça (valor 0), com o texto e o prazo de antes.
insert into catalogo.oferta_inclui
  (oferta_id, produto_id, incluso_id, valor, ordem, nome, descricao, detalhe, nota, valor_referencia,
   inicia_em, encerra_em, origem)
select op.oferta_id, op.produto_id, inc.id, 0, coalesce(b.ordem, 1), b.nome, b.descricao, b.detalhe, b.nota,
       b.valor_referencia, b.inicia_em, b.encerra_em,
       jsonb_build_object('tabela', 'institute.oferta_bonus', 'id', b.id::text, 'importado_em', now(),
                          'confianca', 'copia_viva', 'dados', to_jsonb(b))
  from institute.oferta_bonus b
  join catalogo.oferta_precos op on op.codigo = b.oferta_codigo
  join catalogo.produtos inc
    on inc.codigo = coalesce((select pr.produto_codigo from institute.programas pr where pr.codigo = b.programa_codigo),
                             'mind-summit-2027-mind');

-- Order bump: exige no carrinho o produto do programa-gatilho. A ordem é a de requer_no_carrinho.
insert into catalogo.oferta_requer
  (oferta_id, produto_id, modo, prioridade, grupo_exclusivo, ativo, inicia_em, encerra_em, observacao, ordem, origem)
select op.oferta_id, p.id, 'carrinho', r.prioridade, r.grupo_exclusivo, r.ativo, r.inicia_em, r.encerra_em,
       r.observacao,
       (select e.pos from institute.ofertas io,
               jsonb_array_elements_text(io.elegibilidade->'requer_no_carrinho') with ordinality as e(cod, pos)
         where io.codigo = r.oferta_bump_codigo and e.cod = r.gatilho_programa_codigo)::smallint,
       jsonb_build_object('tabela', 'institute.bump_regras', 'id', r.id::text, 'importado_em', now(),
                          'confianca', 'copia_viva', 'dados', to_jsonb(r))
  from institute.bump_regras r
  join catalogo.oferta_precos op on op.codigo = r.oferta_bump_codigo
  join institute.programas pr on pr.codigo = r.gatilho_programa_codigo
  join catalogo.produtos p on p.codigo = pr.produto_codigo;

do $$
begin
  if (select count(*) from catalogo.ofertas where origem->>'tabela' = 'institute.ofertas')
     <> (select count(*) from institute.ofertas) then
    raise exception 'virada: carga das ofertas incompleta'; end if;
  if (select count(*) from catalogo.oferta_precos where origem->>'tabela' = 'institute.ofertas')
     <> (select count(*) from institute.ofertas where programa_codigo is not null) then
    raise exception 'virada: carga dos preços incompleta'; end if;
  if (select count(*) from catalogo.oferta_inclui where origem->>'tabela' = 'institute.oferta_bonus')
     <> (select count(*) from institute.oferta_bonus) then
    raise exception 'virada: carga dos bônus incompleta'; end if;
  if (select count(*) from catalogo.oferta_requer where origem->>'tabela' = 'institute.bump_regras')
     <> (select count(*) from institute.bump_regras) then
    raise exception 'virada: carga das regras de bump incompleta'; end if;
end $$;

-- ---------------------------------------------------------------------------------------------------
-- 3. AS OFERTAS DO INSTITUTE NA FORMA ANTIGA, LIDAS DO CATÁLOGO
-- ---------------------------------------------------------------------------------------------------
-- Uma linha por preço de produto que tem programa no Institute. O que a forma antiga chamava de
-- elegibilidade sai das exigências (bump = exigência de carrinho ligada); o preço riscado vai para
-- valor_referencia na oferta comum e para elegibilidade.valor_riscado no bump, como o site lê; chaves sem
-- coluna (a "tela" dos 3 bumps) seguem da linha original. Fica de fora o que nenhum leitor do Institute
-- deve ver: rascunho que nunca foi ao ar e upgrade (condicional sem exigência de carrinho).
create view catalogo.institute_ofertas as
select op.codigo,
       pr.codigo as programa_codigo,
       coalesce(op.nome, o.nome) as nome,
       coalesce(op.descricao, o.descricao) as descricao,
       op.moeda::character(3) as moeda,
       op.valor,
       op.parcelas,
       op.valor_parcela,
       o.meios_pagamento,
       (case when b.eh_bump then null else op.valor_riscado end)::numeric(12,2) as valor_referencia,
       op.checkout_url,
       (coalesce(o.origem->'dados'->'elegibilidade', '{}'::jsonb) - 'tipo' - 'valor_riscado' - 'requer_no_carrinho')
         || case when b.eh_bump
                 then jsonb_build_object('tipo', 'order_bump', 'requer_no_carrinho', b.programas)
                      || case when op.valor_riscado is null then '{}'::jsonb
                              else jsonb_build_object('valor_riscado', trim_scale(op.valor_riscado)) end
                 else '{}'::jsonb end as elegibilidade,
       o.publico,
       o.ativo,
       o.inicia_em,
       o.encerra_em,
       o.historico,
       o.tipo,
       coalesce(b.eh_bump, false) as eh_bump,
       op.valor_riscado,
       o.id as oferta_id,
       op.produto_id,
       op.ordem
  from catalogo.oferta_precos op
  join catalogo.ofertas o on o.id = op.oferta_id
  join catalogo.produtos p on p.id = op.produto_id
  join institute.programas pr on pr.produto_codigo = p.codigo
  left join lateral (
    select true as eh_bump,
           coalesce(jsonb_agg(gp.codigo order by rq.ordem, gp.codigo) filter (where gp.codigo is not null),
                    '[]'::jsonb) as programas
      from catalogo.oferta_requer rq
      join catalogo.produtos gpp on gpp.id = rq.produto_id
      left join institute.programas gp on gp.produto_codigo = gpp.codigo
     where rq.oferta_id = o.id and rq.modo = 'carrinho' and rq.ativo
    having count(*) > 0
  ) b on o.tipo = 'condicional'
 where (o.tipo <> 'condicional' or b.eh_bump)
   and (o.ativo or o.historico or o.origem is not null
        or exists (select 1 from public.mind_admin_audit a
                    where a.resource = 'offers' and a.record_id = o.id::text and a.action = 'publicar'));

comment on view catalogo.institute_ofertas is
  'As ofertas do Institute na forma antiga de institute.ofertas, lidas do catálogo (desde a virada do Passo 5). '
  'Leem daqui as portas api.ofertas, api.bump_regras e api.oferta_inclui e as funções de pedido.';
revoke all on catalogo.institute_ofertas from public, anon, authenticated, service_role;

-- A fonte das funções de pedido: igual à casa antiga, código a código. A exceção aprovada é o teste sem
-- programa, que não tem produto e por isso deixa de ter preço.
do $$
begin
  if exists (
    (select codigo, programa_codigo, nome, descricao, moeda, valor, parcelas, valor_parcela, meios_pagamento,
            valor_referencia, checkout_url, elegibilidade, publico, ativo, inicia_em, encerra_em
       from institute.ofertas where codigo <> 'teste-um-centavo'
     except
     select codigo, programa_codigo, nome, descricao, moeda, valor, parcelas, valor_parcela, meios_pagamento,
            valor_referencia, checkout_url, elegibilidade, publico, ativo, inicia_em, encerra_em
       from catalogo.institute_ofertas)
    union all
    (select codigo, programa_codigo, nome, descricao, moeda, valor, parcelas, valor_parcela, meios_pagamento,
            valor_referencia, checkout_url, elegibilidade, publico, ativo, inicia_em, encerra_em
       from catalogo.institute_ofertas
     except
     select codigo, programa_codigo, nome, descricao, moeda, valor, parcelas, valor_parcela, meios_pagamento,
            valor_referencia, checkout_url, elegibilidade, publico, ativo, inicia_em, encerra_em
       from institute.ofertas where codigo <> 'teste-um-centavo')
  ) or (select count(*) from catalogo.institute_ofertas)
       <> (select count(*) from institute.ofertas where codigo <> 'teste-um-centavo') then
    raise exception 'virada: a fonte das funções de pedido mudou';
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------
-- 4. AS FUNÇÕES QUE LEEM OFERTA PASSAM A LER O CATÁLOGO (só o nome da tabela muda nelas)
-- ---------------------------------------------------------------------------------------------------
-- CREATE OR REPLACE mantém dono e permissões; a definição regravada traz SECURITY DEFINER e search_path.
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
    v_vezes := (length(v_def) - length(replace(v_def, 'institute.ofertas', ''))) / length('institute.ofertas');
    if v_vezes <> (v_esperado->>r.proname)::int then
      raise exception 'virada: api.% cita institute.ofertas % vezes, esperava %', r.proname, v_vezes, v_esperado->>r.proname;
    end if;
    execute replace(v_def, 'institute.ofertas', 'catalogo.institute_ofertas');
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------------
-- 5. "PÔR NO AR" DESTRAVA: o site do Institute passa a ler o catálogo
-- ---------------------------------------------------------------------------------------------------
-- api.ofertas lê catalogo.institute_ofertas, e não catalogo.ofertas direto: a conferência passa a aceitar
-- qualquer relação do schema catalogo. Se a porta voltar a ler a casa antiga, trava de novo sozinha.
create or replace function catalogo.produto_tem_leitor(p_produto_id uuid)
returns boolean
language sql
stable
set search_path to 'pg_catalog', 'public'
as $fn$
  select exists (
           select 1
             from catalogo.produtos p
             join institute.programas pr on pr.produto_codigo = p.codigo
            where p.id = p_produto_id
         )
     and exists (
           select 1
             from pg_catalog.pg_depend d
             join pg_catalog.pg_rewrite rw on rw.oid = d.objid
             join pg_catalog.pg_class c on c.oid = d.refobjid
            where d.classid = 'pg_catalog.pg_rewrite'::regclass
              and d.refclassid = 'pg_catalog.pg_class'::regclass
              and rw.ev_class = 'api.ofertas'::regclass
              and c.relnamespace = 'catalogo'::regnamespace
         );
$fn$;

-- ---------------------------------------------------------------------------------------------------
-- 6. A CASA ANTIGA CONGELA
-- ---------------------------------------------------------------------------------------------------
-- Toda escrita nas 3 tabelas é recusada, inclusive pelas 5 funções de edição do /admin do Join
-- (api.criar_oferta, api.salvar_oferta, api.criar_bump, api.salvar_bump e api.remover_bump), que passam a
-- responder com esta mensagem. A leitura continua: as telas antigas do Join mostram o congelado até o Passo 9.
create function institute.casa_antiga_congelada()
returns trigger
language plpgsql
set search_path to 'pg_catalog'
as $fn$
begin
  raise exception 'Preços, ofertas e bumps agora se editam no painel do Mind. Nada foi alterado.'
    using errcode = '42501',
          hint = format('%I.%I está congelada desde a virada para o catálogo.', tg_table_schema, tg_table_name);
end;
$fn$;
revoke all on function institute.casa_antiga_congelada() from public, anon, authenticated, service_role;

create trigger casa_antiga_congelada before insert or update or delete or truncate on institute.ofertas
  for each statement execute function institute.casa_antiga_congelada();
create trigger casa_antiga_congelada before insert or update or delete or truncate on institute.oferta_bonus
  for each statement execute function institute.casa_antiga_congelada();
create trigger casa_antiga_congelada before insert or update or delete or truncate on institute.bump_regras
  for each statement execute function institute.casa_antiga_congelada();


-- ---------------------------------------------------------------------------------------------------
-- 7. A TROCA DAS PORTAS — por último: daqui até o fim, as leituras do site esperam
-- ---------------------------------------------------------------------------------------------------
select set_config('virada.troca_inicio', clock_timestamp()::text, true);
set local lock_timeout = '1s';

create or replace view api.ofertas with (security_invoker = false) as
select io.codigo,
       io.programa_codigo,
       null::text as produto_codigo,
       io.nome,
       io.descricao,
       io.moeda,
       io.valor,
       io.parcelas,
       io.valor_parcela,
       null::text as condicoes_pagamento,
       io.meios_pagamento,
       io.valor_referencia,
       null::numeric(12,2) as economia,
       io.checkout_url,
       io.inicia_em,
       io.encerra_em,
       now() >= coalesce(io.inicia_em, '-infinity'::timestamptz)
         and now() <= coalesce(io.encerra_em, 'infinity'::timestamptz) as vigente,
       coalesce((
         select jsonb_agg(jsonb_build_object(
                  'nome', coalesce(oi.nome, inc.nome),
                  'descricao', oi.descricao,
                  'detalhe', oi.detalhe,
                  'nota', oi.nota,
                  'valor_referencia', oi.valor_referencia,
                  'gratuito', oi.valor = 0,
                  'inicia_em', oi.inicia_em,
                  'encerra_em', oi.encerra_em,
                  'vigente', now() >= coalesce(oi.inicia_em, '-infinity'::timestamptz)
                             and now() <= coalesce(oi.encerra_em, 'infinity'::timestamptz))
                order by oi.ordem, inc.codigo)
           from catalogo.oferta_inclui oi
           join catalogo.produtos inc on inc.id = oi.incluso_id
          where oi.oferta_id = io.oferta_id and oi.produto_id = io.produto_id
       ), '[]'::jsonb) as bonus,
       io.elegibilidade
  from catalogo.institute_ofertas io
 where io.ativo and io.publico and not io.historico
   and now() >= coalesce(io.inicia_em, '-infinity'::timestamptz)
   and now() <= coalesce(io.encerra_em, 'infinity'::timestamptz);

create or replace view api.bump_regras as
select gp.codigo as gatilho_programa_codigo,
       io.codigo as oferta_bump_codigo,
       rq.prioridade,
       rq.grupo_exclusivo,
       io.nome as oferta_nome,
       io.descricao as oferta_descricao,
       io.valor as oferta_valor,
       io.programa_codigo as oferta_programa_codigo,
       trim_scale(io.valor_riscado) as oferta_valor_riscado
  from catalogo.oferta_requer rq
  join catalogo.institute_ofertas io on io.oferta_id = rq.oferta_id
  join catalogo.produtos gpp on gpp.id = rq.produto_id
  join institute.programas gp on gp.produto_codigo = gpp.codigo
 where rq.modo = 'carrinho' and rq.ativo
   and io.eh_bump and io.ativo and io.publico and not io.historico
   and now() >= coalesce(rq.inicia_em, '-infinity'::timestamptz)
   and now() <= coalesce(rq.encerra_em, 'infinity'::timestamptz)
   and now() >= coalesce(io.inicia_em, '-infinity'::timestamptz)
   and now() <= coalesce(io.encerra_em, 'infinity'::timestamptz);

create or replace view api.oferta_inclui as
select io.codigo as oferta_codigo,
       pr.codigo as programa_codigo
  from catalogo.oferta_inclui oi
  join catalogo.institute_ofertas io on io.oferta_id = oi.oferta_id and io.produto_id = oi.produto_id
  join catalogo.produtos inc on inc.id = oi.incluso_id
  join institute.programas pr on pr.produto_codigo = inc.codigo
union
select io.codigo as oferta_codigo,
       c.item_codigo as programa_codigo
  from catalogo.institute_ofertas io
  join institute.programa_composicao c on c.programa_codigo = io.programa_codigo and c.incluso;

-- ---------------------------------------------------------------------------------------------------
-- 8. CONFERÊNCIA FINAL, COM O MESMO RELÓGIO (se falhar, nada desta virada fica)
-- ---------------------------------------------------------------------------------------------------
do $$
declare
  v_ms numeric;
begin
  -- A porta de preços entrega o que entregava e estava valendo (decisão 8).
  if exists ((select * from virada_antes_ofertas where vigente except select * from api.ofertas)
             union all
             (select * from api.ofertas except select * from virada_antes_ofertas where vigente))
     or (select count(*) from api.ofertas) <> (select count(*) from virada_antes_ofertas where vigente) then
    raise exception 'virada: api.ofertas mudou';
  end if;
  if exists ((select * from virada_antes_bumps except select * from api.bump_regras)
             union all
             (select * from api.bump_regras except select * from virada_antes_bumps))
     or (select count(*) from api.bump_regras) <> (select count(*) from virada_antes_bumps) then
    raise exception 'virada: api.bump_regras mudou';
  end if;
  if exists ((select * from virada_antes_inclui except select * from api.oferta_inclui)
             union all
             (select * from api.oferta_inclui except select * from virada_antes_inclui))
     or (select count(*) from api.oferta_inclui) <> (select count(*) from virada_antes_inclui) then
    raise exception 'virada: api.oferta_inclui mudou';
  end if;
  if (select bloco from virada_antes_bloco)
     is distinct from public.mind_kit_institute_catalogo(null::uuid, '{}'::jsonb) then
    raise exception 'virada: o bloco do agente mudou';
  end if;

  -- Portas: colunas, tipos, dono, permissões e opções. Funções: tudo igual, e o corpo só com o nome trocado.
  if exists (
    select 1
      from virada_antes_meta m
      join pg_class c on c.oid = m.nome::regclass
     where m.tipo = 'porta'
       and jsonb_build_object(
             'dono', c.relowner::regrole::text,
             'acl', c.relacl::text,
             'opcoes', to_jsonb(c.reloptions),
             'colunas', (select jsonb_agg(jsonb_build_array(a.attname, format_type(a.atttypid, a.atttypmod), a.attcollation::regcollation::text)
                                          order by a.attnum)
                           from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped)
           ) is distinct from m.meta
  ) or exists (
    select 1
      from virada_antes_meta m
      join pg_proc p on p.oid = m.nome::regprocedure
     where m.tipo = 'funcao'
       and jsonb_build_object(
             'dono', p.proowner::regrole::text,
             'acl', p.proacl::text,
             'definer', p.prosecdef,
             'config', to_jsonb(p.proconfig),
             'volatil', p.provolatile,
             'resultado', pg_get_function_result(p.oid),
             'argumentos', pg_get_function_arguments(p.oid),
             'corpo', p.prosrc
           ) is distinct from m.meta
  ) or (select count(*) from virada_antes_meta where tipo = 'porta') <> 3
    or (select count(*) from virada_antes_meta where tipo = 'funcao') <> 3 then
    raise exception 'virada: dono, permissão, tipo ou corpo de porta ou função mudou';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'api' and p.proname in ('criar_pedido', 'validar_cupom', 'cadastrar_compra_manual')
                and p.prosrc ~ 'institute\.ofertas') then
    raise exception 'virada: função de pedido ainda lê a casa antiga';
  end if;

  v_ms := extract(epoch from clock_timestamp() - current_setting('virada.troca_inicio')::timestamptz) * 1000;
  if v_ms > 1000 then
    raise exception 'virada: a troca das portas levou % ms (o limite é 1000)', round(v_ms);
  end if;
end $$;
