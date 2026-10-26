-- Contrato da casa das ofertas no catálogo (migration 20260926201053_catalogo_ofertas_forma_historico_e_cupons).
-- Sempre termina em rollback: a exceção CATALOGO_OFERTAS_OK é o resultado. Não cria pessoa; as linhas de
-- teste (códigos "contrato-…") somem com o rollback.
begin;
do $$
declare
  v_mind uuid;
  v_vip uuid;
  v_of uuid;
  v_estado text;
  v_msg text;
  n int;
begin
  select id into v_mind from catalogo.produtos where codigo = 'mind-summit-2026-mind';
  select id into v_vip from catalogo.produtos where codigo = 'mind-summit-2026-vip';
  if v_mind is null or v_vip is null then raise exception 'faltam as categorias do Summit 2026'; end if;

  -- 1. FORMA: o que é proibido é recusado
  insert into catalogo.ofertas (codigo, nome, tipo) values ('contrato-oferta', 'Contrato', 'condicional')
  returning id into v_of;

  begin
    insert into catalogo.ofertas (codigo, nome, tipo) values ('contrato-tipo', 'X', 'bump');
    raise exception 'tipo de oferta inválido passou';
  exception when check_violation then null; end;

  begin
    insert into catalogo.ofertas (codigo, nome, tipo, meios_pagamento) values ('contrato-meio', 'X', 'base', array['cheque']);
    raise exception 'meio de pagamento inválido passou';
  exception when check_violation then null; end;

  insert into catalogo.oferta_precos (oferta_id, produto_id, codigo, valor) values (v_of, v_mind, 'contrato-sku', 10);

  begin
    insert into catalogo.oferta_precos (oferta_id, produto_id, codigo, valor) values (v_of, v_vip, 'contrato-sku', 10);
    raise exception 'código vendável repetido passou';
  exception when unique_violation then null; end;

  begin
    update catalogo.oferta_precos set parcelas = 12, valor_parcela = 0.5 where codigo = 'contrato-sku';
    raise exception 'parcelado abaixo do à vista passou';
  exception when check_violation then null; end;

  begin
    update catalogo.oferta_precos set moeda = 'real' where codigo = 'contrato-sku';
    raise exception 'moeda fora do padrão passou';
  exception when check_violation then null; end;

  begin
    update catalogo.oferta_precos set sistema_externo = 'outro' where codigo = 'contrato-sku';
    raise exception 'sistema externo inválido passou';
  exception when check_violation then null; end;

  begin
    update catalogo.oferta_precos set valor_riscado = -1 where codigo = 'contrato-sku';
    raise exception 'preço riscado negativo passou';
  exception when check_violation then null; end;

  begin
    delete from catalogo.produtos where id = v_mind;
    raise exception 'apagar produto com preço passou';
  exception when foreign_key_violation then null; end;

  begin
    insert into catalogo.oferta_inclui (oferta_id, produto_id, incluso_id, inicia_em, encerra_em)
    values (v_of, v_mind, v_vip, now(), now() - interval '1 day');
    raise exception 'bônus com prazo invertido passou';
  exception when check_violation then null; end;

  begin
    insert into catalogo.oferta_requer (oferta_id, produto_id, modo) values (v_of, v_vip, 'talvez');
    raise exception 'modo de exigência inválido passou';
  exception when check_violation then null; end;

  begin
    update catalogo.produtos set produto_pai = id where id = v_mind;
    raise exception 'produto pai de si mesmo passou';
  exception when check_violation then null; end;

  begin
    insert into catalogo.oferta_precos (oferta_id, produto_id, codigo, valor, origem)
    select v_of, v_vip, 'contrato-dup', 1, origem
      from catalogo.oferta_precos where origem->>'tabela' = 'summit_2026.offers' limit 1;
    raise exception 'a mesma linha de origem entrou duas vezes';
  exception when unique_violation then null; end;

  insert into catalogo.cupons (codigo, tipo, valor) values ('Contrato-Cupom', 'valor', 10);
  begin
    insert into catalogo.cupons (codigo, tipo, valor) values ('contrato-cupom', 'percentual', 10);
    raise exception 'cupom repetido (maiúsculas diferentes) passou';
  exception when unique_violation then null; end;
  begin
    insert into catalogo.cupons (codigo, tipo, valor) values ('contrato-cupom-2', 'valor_fixo', 10);
    raise exception 'tipo de cupom inválido passou';
  exception when check_violation then null; end;
  begin
    insert into catalogo.cupons (codigo, tipo, valor, sistema) values ('contrato-cupom-3', 'valor', 10, 'outro');
    raise exception 'sistema de cupom inválido passou';
  exception when check_violation then null; end;

  -- 2. CARGA DO SUMMIT 2026: igual à tabela antiga, desligada, marcada como histórico
  select count(*) into n from catalogo.oferta_precos where origem->>'tabela' = 'summit_2026.offers';
  if n <> (select count(*) from summit_2026.offers) then raise exception 'preços do Summit 2026: % no catálogo', n; end if;
  if (select count(*) from catalogo.ofertas where origem->>'tabela' = 'summit_2026.offers') <> 14 then
    raise exception 'ofertas do Summit 2026: esperava 14 (7 lotes, 4 de grupo, 3 upgrades)'; end if;

  if exists (
    select 1 from summit_2026.offers s
      left join catalogo.oferta_precos op on op.origem->>'tabela' = 'summit_2026.offers' and op.origem->>'id' = s.id::text
      left join catalogo.ofertas o on o.id = op.oferta_id
      left join catalogo.produtos p on p.id = op.produto_id
     where op.oferta_id is null
        or op.codigo <> s.codigo || '-2026'
        or op.valor is distinct from s.valor or op.moeda is distinct from s.moeda::text
        or op.nome is distinct from s.nome or op.descricao is distinct from s.descricao
        or op.checkout_url is distinct from s.checkout_url
        or op.sku_externo is distinct from s.elegibilidade->>'eduzz_product_id'
        or op.parcelas is not null
        or op.origem->'dados'->>'condicoes_pagamento' is distinct from s.condicoes_pagamento
        or o.inicia_em is distinct from s.inicia_em or o.encerra_em is distinct from s.encerra_em
        or p.categoria is distinct from coalesce(s.elegibilidade->>'destino', s.elegibilidade->>'categoria')
  ) then raise exception 'uma linha do Summit 2026 não bate com a origem'; end if;

  if exists (select 1 from catalogo.ofertas where origem->>'tabela' = 'summit_2026.offers' and (ativo or not historico)) then
    raise exception 'oferta do Summit 2026 entrou ligada ou fora do histórico'; end if;
  if (select count(*) from catalogo.ofertas where origem->>'tabela' = 'summit_2026.offers' and tipo = 'condicional') <> 3 then
    raise exception 'os 3 upgrades deviam ser condicionais'; end if;

  if exists (
    select 1 from summit_2026.offers s
      join catalogo.ofertas o on o.codigo = s.codigo || '-2026'
     where s.elegibilidade->>'tipo' = 'upgrade'
       and not exists (
         select 1 from catalogo.oferta_requer r join catalogo.produtos p on p.id = r.produto_id
          where r.oferta_id = o.id and r.modo = 'posse' and p.codigo = 'mind-summit-2026-' || (s.elegibilidade->>'origem'))
  ) then raise exception 'upgrade sem a exigência da categoria de origem'; end if;

  if (select count(*) from catalogo.produtos p join catalogo.produtos pai on pai.id = p.produto_pai
       where pai.codigo = 'mind-summit-2026' and p.categoria in ('mind', 'vip', 'prime')) <> 3 then
    raise exception 'as 3 categorias do Summit 2026 deviam ser filhas da edição'; end if;
  if exists (select 1 from catalogo.produtos
              where codigo in ('mind-summit-2026-mind', 'mind-summit-2026-vip', 'mind-summit-2026-prime',
                               'mind-summit-2027', 'mind-summit-2027-mind')
                and (ativo or vende or pipelines_hubspot is not null)) then
    raise exception 'produto novo ligado, à venda ou com funil do HubSpot'; end if;
  if (select count(*) from catalogo.produtos where codigo in ('mind-summit-2027', 'mind-summit-2027-mind')) <> 2 then
    raise exception 'faltam os produtos do Summit 2027'; end if;

  if (select count(*) from catalogo.cupons where origem->>'tabela' = 'summit_2026.coupons')
     <> (select count(*) from summit_2026.coupons) then raise exception 'cupons do Summit 2026 incompletos'; end if;
  if exists (
    select 1 from summit_2026.coupons c
      join catalogo.cupons k on k.origem->>'tabela' = 'summit_2026.coupons' and k.origem->>'id' = c.id::text
     where k.codigo <> c.codigo or k.valor <> c.valor or k.ativo or not k.historico or k.sistema <> 'eduzz'
  ) then raise exception 'cupom do Summit 2026 não bate com a origem ou entrou ligado'; end if;

  -- 3. ISOLAMENTO: o site e o agente ainda não leem a casa nova
  if exists (
    select 1 from pg_depend d
      join pg_rewrite rw on rw.oid = d.objid
     where d.refobjid in ('catalogo.ofertas'::regclass, 'catalogo.oferta_precos'::regclass,
                          'catalogo.oferta_inclui'::regclass, 'catalogo.oferta_requer'::regclass)
  ) then raise exception 'uma view já lê as tabelas de oferta do catálogo'; end if;
  if exists (select 1 from pg_proc where prokind = 'f' and prosrc ~ 'catalogo\.oferta') then
    raise exception 'uma função já lê as tabelas de oferta do catálogo'; end if;

  -- 4. CUPONS NO CATÁLOGO: a tabela antiga saiu e as funções apontam para a nova, com as mesmas permissões
  if to_regclass('checkout.cupons') is not null then raise exception 'checkout.cupons ainda existe'; end if;
  if exists (select 1 from pg_proc where prokind = 'f' and prosrc ~ 'checkout\.cupons') then
    raise exception 'função ainda cita checkout.cupons'; end if;
  if (select count(*) from pg_proc p join pg_namespace s on s.oid = p.pronamespace
       where s.nspname = 'api' and p.proname in ('criar_pedido', 'validar_cupom', 'salvar_cupom')
         and p.prosrc ~ 'catalogo\.cupons' and p.prosecdef) <> 3 then
    raise exception 'as 3 funções de cupom deviam citar catalogo.cupons e continuar security definer'; end if;
  if not has_function_privilege('anon', 'api.validar_cupom(text,text[],text)', 'execute')
     or not has_function_privilege('anon', 'api.criar_pedido(text[],text,text,text,text,text,text,text,text)', 'execute') then
    raise exception 'as funções de cupom perderam as permissões de antes'; end if;
  begin
    perform api.validar_cupom('contrato-inexistente', array[]::text[], null);
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
    if v_estado in ('42P01', '42703', '42883') then
      raise exception 'validar_cupom quebrou depois da mudança: % %', v_estado, v_msg; end if;
  end;

  raise exception 'CATALOGO_OFERTAS_OK: forma (tipos, meios, código vendável único, parcela, moeda, sistema, riscado, produto com preço não se apaga, bônus e exigência coerentes, pai, origem única, cupom único), carga do Summit 2026 igual à origem e desligada, upgrades com exigência, produtos novos desligados e sem funil, cupons no catálogo com as funções apontando para lá, e nada que o site ou o agente lê usa a casa nova';
end $$;
rollback;
