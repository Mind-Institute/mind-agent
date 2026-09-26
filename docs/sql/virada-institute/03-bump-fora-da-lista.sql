-- O ORDER BUMP SAI DAS LISTAS DE PREÇO POR PROGRAMA. É a pergunta (b) da virada: só roda com o OK da Adriana.
--
-- RASCUNHO, como os outros desta pasta. Depende da virada (01-virada.sql) e tem de rodar antes de 30/09 23h59.
--
-- O problema: depois de 30/09 23h59, sem condição valendo, a seção "Avulsas" da página da Certificação, nos dois
-- sites, pega a oferta mais barata do programa. Na Liderança Consciente, essa é o bump de R$ 1.497 do checkout do
-- Journey. As páginas montam a lista de cada programa a partir de api.ofertas, pelo programa_codigo, na ordem do
-- valor.
--
-- A saída: em api.ofertas, o bump passa a vir sem programa. Com isso:
--   · ele sai de todas as listas de preço por programa, e a "Avulsas" passa a mostrar o balcão;
--   · a página do Journey já ignorava o bump, e o bloco do agente também — nada muda neles;
--   · o checkout próprio continua funcionando: ele acha o bump pelo código e não usa o programa dele;
--   · a regra do bump (api.bump_regras, com o programa que ele entrega) e a cobrança (api.criar_pedido, que lê
--     catalogo.institute_ofertas) não mudam.
-- Tirar o bump de api.ofertas de vez quebraria o checkout próprio: o carrinho procura ali o preço do bump aceito.
--
-- Conferido na mesma transação: api.ofertas igual a antes, fora o programa_codigo dos bumps, que fica vazio; as
-- outras duas portas e o bloco do agente iguais. A volta é a definição de api.ofertas de 01-virada.sql.

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
    raise exception 'bump: a virada não está aplicada';
  end if;
end $$;

create temp table bump_antes_ofertas on commit drop as select * from api.ofertas;
create temp table bump_antes_bumps on commit drop as select * from api.bump_regras;
create temp table bump_antes_inclui on commit drop as select * from api.oferta_inclui;
create temp table bump_antes_bloco on commit drop as
  select public.mind_kit_institute_catalogo(null::uuid, '{}'::jsonb) as bloco;

select set_config('bump.troca_inicio', clock_timestamp()::text, true);
set local lock_timeout = '1s';

-- A definição de 01-virada.sql, com uma diferença: o programa_codigo do bump.
create or replace view api.ofertas with (security_invoker = false) as
select io.codigo,
       case when io.eh_bump then null else io.programa_codigo end as programa_codigo,
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

do $$
declare
  v_ms numeric;
begin
  -- Igual a antes, com o programa do bump vazio, e só isso.
  if exists ((select codigo,
                     case when elegibilidade->>'tipo' = 'order_bump' then null else programa_codigo end,
                     produto_codigo, nome, descricao, moeda, valor, parcelas, valor_parcela, condicoes_pagamento,
                     meios_pagamento, valor_referencia, economia, checkout_url, inicia_em, encerra_em, vigente, bonus,
                     elegibilidade
                from bump_antes_ofertas
              except
              select * from api.ofertas)
             union all
             (select * from api.ofertas
              except
              select codigo,
                     case when elegibilidade->>'tipo' = 'order_bump' then null else programa_codigo end,
                     produto_codigo, nome, descricao, moeda, valor, parcelas, valor_parcela, condicoes_pagamento,
                     meios_pagamento, valor_referencia, economia, checkout_url, inicia_em, encerra_em, vigente, bonus,
                     elegibilidade
                from bump_antes_ofertas))
     or (select count(*) from api.ofertas) <> (select count(*) from bump_antes_ofertas) then
    raise exception 'bump: api.ofertas mudou além do programa do bump';
  end if;
  if exists (select 1 from api.ofertas where elegibilidade->>'tipo' = 'order_bump' and programa_codigo is not null)
     or exists (select 1 from api.ofertas where coalesce(elegibilidade->>'tipo', '') <> 'order_bump' and programa_codigo is null) then
    raise exception 'bump: programa vazio onde não devia, ou bump ainda com programa';
  end if;
  if exists ((select * from bump_antes_bumps except select * from api.bump_regras)
             union all (select * from api.bump_regras except select * from bump_antes_bumps))
     or exists ((select * from bump_antes_inclui except select * from api.oferta_inclui)
                union all (select * from api.oferta_inclui except select * from bump_antes_inclui))
     or (select bloco from bump_antes_bloco) is distinct from public.mind_kit_institute_catalogo(null::uuid, '{}'::jsonb) then
    raise exception 'bump: outra porta ou o bloco do agente mudou';
  end if;
  v_ms := extract(epoch from clock_timestamp() - current_setting('bump.troca_inicio')::timestamptz) * 1000;
  if v_ms > 1000 then
    raise exception 'bump: a troca levou % ms (o limite é 1000)', round(v_ms);
  end if;
end $$;
