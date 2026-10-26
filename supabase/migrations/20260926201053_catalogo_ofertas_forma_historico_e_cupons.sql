-- CATÁLOGO: A CASA DAS OFERTAS GANHA FORMA, OS CUPONS MUDAM PARA CÁ E O SUMMIT 2026 ENTRA COMO HISTÓRICO.
--
-- Decisões da Adriana (26/09/2026, D2 — Passo 3 de docs/PLANO_OFERTAS_PASSO_A_PASSO.md aprovado):
--   "no schema catálogo deve organizar as tabelas de preço, oferta, order bump, cupom — todas devem estar
--   neste schema, embora não necessariamente na mesma tabela"; "todas as infos importantes deste schema
--   devem ser espelhadas e editáveis via painel"; "histórico importante"; e, sobre o checkout próprio,
--   "não tem nada relevante ainda — podemos migrar qualquer coisa relacionada sem medo de quebrar".
--
-- Onde cada coisa mora depois desta migration:
--   catalogo.ofertas        a condição comercial: nome, tipo, janela, liga/desliga, pública ou não
--   catalogo.oferta_precos  o preço de cada produto dentro da oferta, com o código vendável
--   catalogo.oferta_inclui  o bônus (o que vem junto): um produto, com os textos e a janela dele
--   catalogo.oferta_requer  order bump e upgrade: a oferta condicional e o produto que ela exige
--   catalogo.cupons         o cupom (a tabela checkout.cupons, vazia, muda de schema)
--
-- NADA MUDA NO SITE NEM NO AGENTE. Os sites e o agente continuam lendo institute.* pelas views api.* até
-- a virada (Passo 5). Nenhuma view nem função lê as tabelas oferta* do catálogo. O schema catalogo não é
-- exposto (PostgREST expõe public e api; anon e authenticated não têm USAGE nele).
--
-- HISTÓRICO DO SUMMIT 2026, copiado DENTRO do banco — nenhum preço, link ou cupom fica escrito neste
-- arquivo, que vai para um repositório público:
--   · 3 produtos de categoria (Mind, VIP, Prime), filhos de mind-summit-2026, desligados e sem venda;
--   · summit_2026.offers (28 linhas) → 14 ofertas com 28 preços: 7 lotes (as 3 categorias têm o mesmo
--     prazo em cada lote — conferido abaixo), 4 preços de grupo do VIP e 3 upgrades (exigem ter a
--     categoria de origem, modo "posse");
--   · os códigos ganham "-2026", para os códigos de lote ficarem livres em 2027;
--   · o parcelamento em texto, a procura e o resto da linha original ficam em "origem" (10 dos 21
--     parcelamentos em texto dão menos que o preço à vista, e o catálogo recusa isso);
--   · summit_2026.coupons (3) → catalogo.cupons, como histórico desligado.
-- As tabelas antigas do Summit ficam como estão: o agente ainda lê summit_2026.offers (0 ativas).
--
-- Mais 2 produtos, desligados e sem venda: mind-summit-2027 e a categoria Mind dele. São o que o bônus
-- "Ingresso categoria Mind para o Mind Summit 2027" das ofertas do Institute entrega (Passo 5).
--
-- Cupons: checkout.cupons (0 linhas) muda para catalogo.cupons. As 3 funções que citam a tabela pelo nome
-- (api.criar_pedido, api.validar_cupom, api.salvar_cupom) passam a citar o nome novo; o resto delas não
-- muda. institute.calcular_desconto recebe a linha pelo tipo, que acompanha a tabela. A tela de cupons do
-- /admin do Join (api.admin_cupons) deixa de abrir para usuário logado, porque o catalogo não é exposto —
-- ela não é usada (a Adriana: "podemos migrar ... sem medo de quebrar").
--
-- Contrato: tests/catalogo_ofertas_contract.sql (termina em CATALOGO_OFERTAS_OK).

-- ---------------------------------------------------------------------------------------------------
-- 1. FORMA
-- ---------------------------------------------------------------------------------------------------

-- produtos: a categoria de um evento aponta para a edição
alter table catalogo.produtos
  add column produto_pai uuid references catalogo.produtos(id) on delete restrict,
  add constraint produto_pai_nao_e_ele_mesmo check (produto_pai is distinct from id);
comment on column catalogo.produtos.produto_pai is
  'A edição a que esta categoria pertence (ex.: Mind, VIP e Prime → Mind Summit 2026). Vazio = produto sem pai.';

-- ofertas
alter table catalogo.ofertas drop constraint ofertas_tipo_check;
alter table catalogo.ofertas
  add constraint ofertas_tipo_check check (tipo = any (array['base', 'periodo', 'combo', 'condicional'])),
  add column publico boolean not null default true,
  add column meios_pagamento text[] not null default '{}',
  add column historico boolean not null default false,
  add column origem jsonb,
  add constraint ofertas_meios_pagamento_validos check (meios_pagamento <@ array['cartao', 'pix', 'boleto']);
comment on column catalogo.ofertas.tipo is
  'base = preço sem prazo; periodo = condição com prazo; combo = vários produtos; condicional = order bump ou upgrade (só vale com o que oferta_requer exige).';
comment on column catalogo.ofertas.publico is 'Aparece no site. Desligado = só por link direto.';
comment on column catalogo.ofertas.meios_pagamento is 'Meios aceitos: cartao, pix, boleto.';
comment on column catalogo.ofertas.historico is
  'Importada como histórico: só leitura no painel (dá para duplicar). Uma oferta que só venceu NÃO é histórico.';
comment on column catalogo.ofertas.origem is
  'De onde a linha veio: {tabela, id, importado_em, confianca, dados}. Guarda a linha original.';

-- oferta_precos: o código vendável e o que é de cada linha
alter table catalogo.oferta_precos drop constraint oferta_precos_produto_id_fkey;
alter table catalogo.oferta_precos
  add column codigo text not null,
  add column nome text,
  add column descricao text,
  add column checkout_url text,
  add column sistema_externo text,
  add column sku_externo text,
  add column valor_riscado numeric(12,2),
  add column origem jsonb,
  add constraint oferta_precos_codigo_key unique (codigo),
  add constraint oferta_precos_produto_id_fkey
    foreign key (produto_id) references catalogo.produtos(id) on delete restrict,
  add constraint oferta_precos_sistema_externo_valido check (sistema_externo in ('eduzz', 'infinitepay')),
  add constraint oferta_precos_valor_riscado_check check (valor_riscado is null or valor_riscado >= 0),
  add constraint oferta_precos_moeda_iso check (moeda ~ '^[A-Z]{3}$');
comment on column catalogo.oferta_precos.codigo is
  'Código vendável: o que links, pedidos, acessos e relatórios usam para identificar o item. Único.';
comment on column catalogo.oferta_precos.nome is 'Nome desta linha; vazio = o nome da oferta.';
comment on column catalogo.oferta_precos.sku_externo is 'Código do produto no sistema que cobra (ex.: Eduzz).';
comment on column catalogo.oferta_precos.valor_riscado is 'Preço "de" mostrado riscado, quando houver.';

-- oferta_inclui: o bônus tem texto e prazo próprios
alter table catalogo.oferta_inclui
  add column nome text,
  add column descricao text,
  add column detalhe text,
  add column nota text,
  add column valor_referencia numeric(12,2),
  add column inicia_em timestamptz,
  add column encerra_em timestamptz,
  add column origem jsonb,
  add constraint oferta_inclui_valor_referencia_check check (valor_referencia is null or valor_referencia >= 0),
  add constraint oferta_inclui_janela_coerente check (inicia_em is null or encerra_em is null or inicia_em < encerra_em);
comment on table catalogo.oferta_inclui is
  'Bônus: o produto que vem junto com o preço de uma oferta, com o texto e o prazo que o site mostra.';

-- oferta_requer: order bump (exige no carrinho) e upgrade (exige ter comprado)
alter table catalogo.oferta_requer
  add column modo text not null default 'carrinho',
  add column prioridade smallint not null default 100,
  add column grupo_exclusivo text,
  add column ativo boolean not null default true,
  add column inicia_em timestamptz,
  add column encerra_em timestamptz,
  add column observacao text,
  add column ordem smallint not null default 1,
  add column origem jsonb,
  add constraint oferta_requer_modo_valido check (modo in ('carrinho', 'posse')),
  add constraint oferta_requer_janela_coerente check (inicia_em is null or encerra_em is null or inicia_em < encerra_em);
comment on table catalogo.oferta_requer is
  'Order bump e upgrade: a oferta condicional só vale com o produto exigido — no carrinho (bump) ou já comprado (upgrade).';

-- Cada linha de origem entra uma vez só.
create unique index ofertas_origem_unica on catalogo.ofertas ((origem->>'tabela'), (origem->>'id')) where origem is not null;
create unique index oferta_precos_origem_unica on catalogo.oferta_precos ((origem->>'tabela'), (origem->>'id')) where origem is not null;
create unique index oferta_inclui_origem_unica on catalogo.oferta_inclui ((origem->>'tabela'), (origem->>'id')) where origem is not null;
create unique index oferta_requer_origem_unica on catalogo.oferta_requer ((origem->>'tabela'), (origem->>'id')) where origem is not null;

-- cupons: a tabela vazia do checkout próprio muda para o catálogo
alter table checkout.cupons set schema catalogo;
alter table catalogo.cupons
  add column sistema text not null default 'checkout_proprio',
  add column produtos text[] not null default '{}',
  add column historico boolean not null default false,
  add column origem jsonb,
  add constraint cupons_sistema_valido check (sistema in ('checkout_proprio', 'eduzz'));
create unique index cupons_codigo_unico on catalogo.cupons (lower(codigo));
create unique index cupons_origem_unica on catalogo.cupons ((origem->>'tabela'), (origem->>'id')) where origem is not null;
comment on table catalogo.cupons is 'Cupons de desconto. Até 26/09/2026 moravam em checkout.cupons.';
comment on column catalogo.cupons.sistema is 'Onde o cupom é aplicado: checkout_proprio ou eduzz.';
comment on column catalogo.cupons.produtos is 'Escopo por produto (códigos de catalogo.produtos); vazio = não restringe.';

-- As funções que citavam checkout.cupons pelo nome passam a citar catalogo.cupons (só isso muda nelas;
-- CREATE OR REPLACE mantém dono e grants, e a definição regravada traz SECURITY DEFINER e search_path).
do $$
declare
  r record;
  n int := 0;
begin
  for r in
    select p.oid from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname in ('api', 'institute', 'checkout', 'public') and p.prokind = 'f'
       and p.prosrc ~ 'checkout\.cupons'
  loop
    execute replace(pg_get_functiondef(r.oid), 'checkout.cupons', 'catalogo.cupons');
    n := n + 1;
  end loop;
  if n <> 3 then raise exception 'esperava 3 funções citando checkout.cupons, vieram %', n; end if;
end $$;

-- ---------------------------------------------------------------------------------------------------
-- 2. PRODUTOS: categorias do Summit 2026 (histórico) e o que o bônus do Institute promete (2027)
-- ---------------------------------------------------------------------------------------------------

insert into catalogo.produtos
  (codigo, nome, tipo, vertical, categoria, produto_pai, ativo, vende, schema_dados, pipelines_hubspot, comeca_em, encerra_em)
select 'mind-summit-2026-' || e.chave, 'Mind Summit 2026 — Experiência ' || e.nome, 'evento', 'summit', e.chave,
       p.id, false, false, p.schema_dados, null, p.comeca_em, p.encerra_em
  from summit_2026.experiencias e
  cross join catalogo.produtos p
 where p.codigo = 'mind-summit-2026' and e.chave in ('mind', 'vip', 'prime');

insert into catalogo.produtos (codigo, nome, tipo, vertical, ativo, vende, pipelines_hubspot)
values ('mind-summit-2027', 'Mind Summit 2027', 'evento', 'summit', false, false, null);

insert into catalogo.produtos (codigo, nome, tipo, vertical, categoria, produto_pai, ativo, vende, pipelines_hubspot)
select 'mind-summit-2027-mind', 'Mind Summit 2027 — Experiência Mind', 'evento', 'summit', 'mind', p.id, false, false, null
  from catalogo.produtos p where p.codigo = 'mind-summit-2027';

-- ---------------------------------------------------------------------------------------------------
-- 3. HISTÓRICO DO SUMMIT 2026
-- ---------------------------------------------------------------------------------------------------

-- Em cada lote, Mind, VIP e Prime têm o mesmo prazo — senão a oferta única do lote mentiria.
do $$
begin
  if exists (
    select 1 from summit_2026.offers
     where elegibilidade->>'lote' is not null and elegibilidade->'grupo' is null and elegibilidade->>'tipo' is null
     group by elegibilidade->>'lote'
    having count(distinct coalesce(inicia_em::text, '-')) > 1 or count(distinct coalesce(encerra_em::text, '-')) > 1
  ) then
    raise exception 'um lote do Summit 2026 tem prazos diferentes entre as categorias';
  end if;
end $$;

-- 7 lotes: uma oferta por lote
insert into catalogo.ofertas (codigo, nome, tipo, ativo, publico, inicia_em, encerra_em, historico, origem)
select 'mind-summit-2026-lote-' || l.lote, 'Mind Summit 2026 — Lote ' || l.lote, 'periodo', false, false,
       l.inicia_em, l.encerra_em, true,
       jsonb_build_object('tabela', 'summit_2026.offers', 'id', 'lote-' || l.lote, 'importado_em', now(),
                          'confianca', 'copia_viva', 'dados', jsonb_build_object('codigos', l.codigos))
  from (
    select elegibilidade->>'lote' as lote, min(inicia_em) as inicia_em, max(encerra_em) as encerra_em,
           jsonb_agg(codigo order by codigo) as codigos
      from summit_2026.offers
     where elegibilidade->>'lote' is not null and elegibilidade->'grupo' is null and elegibilidade->>'tipo' is null
     group by 1
  ) l;

-- 4 preços de grupo e 3 upgrades: uma oferta cada
insert into catalogo.ofertas (codigo, nome, descricao, tipo, ativo, publico, inicia_em, encerra_em, historico, origem)
select s.codigo || '-2026', s.nome, s.descricao,
       case when s.elegibilidade->>'tipo' = 'upgrade' then 'condicional' else 'periodo' end,
       false, s.publico, s.inicia_em, s.encerra_em, true,
       jsonb_build_object('tabela', 'summit_2026.offers', 'id', s.id::text, 'importado_em', now(), 'confianca', 'copia_viva')
  from summit_2026.offers s
 where s.elegibilidade->'grupo' is not null or s.elegibilidade->>'tipo' = 'upgrade';

-- 28 preços, um por linha antiga; o que não tem coluna vai para origem.dados
insert into catalogo.oferta_precos
  (oferta_id, produto_id, codigo, nome, descricao, valor, parcelas, valor_parcela, moeda, ordem,
   checkout_url, sistema_externo, sku_externo, origem)
select o.id, p.id, s.codigo || '-2026', s.nome, s.descricao, s.valor, null, null, s.moeda::text,
       coalesce(e.ordem, 1)::smallint,
       s.checkout_url,
       case when s.elegibilidade ? 'eduzz_product_id' or s.checkout_url ~* 'eduzz' then 'eduzz' end,
       s.elegibilidade->>'eduzz_product_id',
       jsonb_build_object(
         'tabela', 'summit_2026.offers', 'id', s.id::text, 'codigo', s.codigo, 'importado_em', now(),
         'confianca', 'copia_viva',
         'dados', jsonb_strip_nulls(jsonb_build_object(
           'condicoes_pagamento', s.condicoes_pagamento, 'procura', s.procura, 'procura_nota', s.procura_nota,
           'elegibilidade', s.elegibilidade, 'publico', s.publico, 'ativo', s.ativo,
           'inicia_em', s.inicia_em, 'encerra_em', s.encerra_em, 'atualizado_em', s.atualizado_em,
           'event_id', s.event_id)))
  from summit_2026.offers s
  join catalogo.ofertas o
    on o.origem->>'tabela' = 'summit_2026.offers'
   and o.origem->>'id' = case
         when s.elegibilidade->'grupo' is not null or s.elegibilidade->>'tipo' = 'upgrade' then s.id::text
         else 'lote-' || (s.elegibilidade->>'lote') end
  join catalogo.produtos p
    on p.codigo = 'mind-summit-2026-' || coalesce(s.elegibilidade->>'destino', s.elegibilidade->>'categoria')
  left join summit_2026.experiencias e
    on e.chave = coalesce(s.elegibilidade->>'destino', s.elegibilidade->>'categoria');

-- 3 upgrades: exigem ter comprado a categoria de origem
insert into catalogo.oferta_requer (oferta_id, produto_id, modo, ativo, ordem, origem)
select o.id, p.id, 'posse', false, 1,
       jsonb_build_object('tabela', 'summit_2026.offers', 'id', s.id::text, 'importado_em', now(), 'confianca', 'copia_viva')
  from summit_2026.offers s
  join catalogo.ofertas o on o.codigo = s.codigo || '-2026'
  join catalogo.produtos p on p.codigo = 'mind-summit-2026-' || (s.elegibilidade->>'origem')
 where s.elegibilidade->>'tipo' = 'upgrade';

-- 3 cupons, como histórico desligado
insert into catalogo.cupons
  (codigo, descricao, tipo, valor, ofertas, produtos, inicia_em, encerra_em, usos_maximos, ativo, sistema, historico, origem)
select c.codigo, c.descricao,
       case c.tipo when 'valor_fixo' then 'valor' else c.tipo end,
       c.valor,
       case when c.offer_codigo is null then '{}'::text[] else array[c.offer_codigo || '-2026'] end,
       array['mind-summit-2026'], c.valido_de, c.valido_ate, c.max_usos, false, 'eduzz', true,
       jsonb_build_object(
         'tabela', 'summit_2026.coupons', 'id', c.id::text, 'importado_em', now(), 'confianca', 'copia_viva',
         'dados', jsonb_strip_nulls(jsonb_build_object(
           'tipo', c.tipo, 'ativo', c.ativo, 'offer_codigo', c.offer_codigo, 'condicoes', c.condicoes,
           'event_id', c.event_id, 'atualizado_em', c.atualizado_em)))
  from summit_2026.coupons c;

-- ---------------------------------------------------------------------------------------------------
-- 4. CONFERÊNCIA (se falhar, nada desta migration fica)
-- ---------------------------------------------------------------------------------------------------
do $$
declare
  v_fonte int;
begin
  select count(*) into v_fonte from summit_2026.offers;
  if (select count(*) from catalogo.oferta_precos where origem->>'tabela' = 'summit_2026.offers') <> v_fonte then
    raise exception 'preços do Summit 2026: esperava %', v_fonte; end if;
  if (select count(*) from catalogo.ofertas where origem->>'tabela' = 'summit_2026.offers') <> 14 then
    raise exception 'ofertas do Summit 2026: esperava 14'; end if;
  if (select count(*) from catalogo.oferta_requer where origem->>'tabela' = 'summit_2026.offers') <> 3 then
    raise exception 'upgrades do Summit 2026: esperava 3'; end if;
  if (select count(*) from catalogo.cupons where origem->>'tabela' = 'summit_2026.coupons')
     <> (select count(*) from summit_2026.coupons) then
    raise exception 'cupons do Summit 2026 incompletos'; end if;
  if exists (select 1 from catalogo.ofertas where ativo) or exists (select 1 from catalogo.cupons where ativo) then
    raise exception 'o histórico entrou ligado'; end if;
  if exists (
    select 1 from summit_2026.offers s
      join catalogo.oferta_precos op on op.origem->>'tabela' = 'summit_2026.offers' and op.origem->>'id' = s.id::text
      join catalogo.ofertas o on o.id = op.oferta_id
     where op.valor is distinct from s.valor or op.moeda is distinct from s.moeda::text
        or op.checkout_url is distinct from s.checkout_url or op.nome is distinct from s.nome
        or o.inicia_em is distinct from s.inicia_em or o.encerra_em is distinct from s.encerra_em
  ) then
    raise exception 'um preço do Summit 2026 não bate com a linha de origem'; end if;
  if exists (select 1 from catalogo.produtos where codigo like 'mind-summit-202%-%' and (ativo or vende or pipelines_hubspot is not null)) then
    raise exception 'produto novo entrou ligado, à venda ou com funil'; end if;
  if exists (select 1 from pg_proc p where p.prokind = 'f' and p.prosrc ~ 'checkout\.cupons') then
    raise exception 'ainda há função citando checkout.cupons'; end if;
end $$;
