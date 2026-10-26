-- PAINEL: AS OFERTAS E OS CUPONS DO CATÁLOGO, COMO ESTÃO NO BANCO (SÓ LEITURA).
--
-- Pedido da Adriana (26/09/2026): "o que eu quero é ver a fonte da verdade e ter editável no meu painel,
-- e que o painel seja o controle deste schema e do que é importante nele". Este é o Passo 2 de
-- docs/PLANO_OFERTAS_PASSO_A_PASSO.md: ver. A edição é o Passo 4.
--
-- Duas portas, no molde de mind_admin_read_catalogo (só o service_role executa; a mindagent-catalogo chama):
--   · mind_admin_read_ofertas(p_id, p_agora) — cada oferta de catalogo.ofertas com os preços
--     (oferta_precos), o bônus (oferta_inclui) e o que ela exige (oferta_requer), mais a SITUAÇÃO calculada
--     com as mesmas pontas de janela de api.ofertas (as duas incluídas):
--       historico  importada como histórico (só leitura);
--       desligada  ativo = false;
--       agendada   ainda não começou;
--       encerrada  já terminou;
--       so_link    valendo, mas publico = false (não aparece no site);
--       no_ar      valendo e pública.
--     "noSite" diz se o código vendável está em api.ofertas — o que o site lê de verdade. Hoje nenhuma
--     oferta do catálogo está lá (o site ainda lê institute.*); depois da virada (Passo 5), as do Institute.
--     "eduzz" traz o preço de lista que a cópia da Eduzz tem para o código do produto lá, quando houver.
--   · mind_admin_read_cupons(p_id, p_agora) — cada cupom de catalogo.cupons, com a situação
--     (historico, desligado, agendado, encerrado, esgotado, valendo).
-- p_agora existe para o contrato simular a hora; o painel não o manda.
--
-- Contrato: tests/ofertas_painel_contract.sql (termina em OFERTAS_PAINEL_OK).

create or replace function public.mind_admin_read_ofertas(p_id uuid default null, p_agora timestamptz default now())
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
  select coalesce(jsonb_agg(x.obj order by x.ordem, x.inicio desc nulls last, x.codigo), '[]'::jsonb)
  from (
    select o.codigo, o.inicia_em as inicio, s.ordem,
      jsonb_build_object(
        'id', o.id::text,
        'codigo', o.codigo,
        'nome', o.nome,
        'descricao', o.descricao,
        'tipo', o.tipo,
        'ativo', o.ativo,
        'publico', o.publico,
        'historico', o.historico,
        'iniciaEm', o.inicia_em,
        'encerraEm', o.encerra_em,
        'meiosPagamento', to_jsonb(o.meios_pagamento),
        'situacao', s.situacao,
        'situacaoOrdem', s.ordem,
        'noSite', coalesce(p.no_site, false),
        'verticais', coalesce(p.verticais, '[]'::jsonb),
        'produtos', coalesce(p.produtos, '[]'::jsonb),
        'precos', coalesce(p.precos, '[]'::jsonb),
        'bonus', coalesce(b.bonus, '[]'::jsonb),
        'requer', coalesce(r.requer, '[]'::jsonb),
        'origem', o.origem,
        'criadoEm', o.criado_em,
        'atualizadoEm', o.atualizado_em
      ) as obj
    from catalogo.ofertas o
    cross join lateral (
      select case
               when o.historico then 'historico'
               when not o.ativo then 'desligada'
               when o.inicia_em is not null and p_agora < o.inicia_em then 'agendada'
               when o.encerra_em is not null and p_agora > o.encerra_em then 'encerrada'
               when not o.publico then 'so_link'
               else 'no_ar'
             end as situacao
    ) s0
    cross join lateral (
      select s0.situacao,
             case s0.situacao
               when 'no_ar' then 1 when 'so_link' then 2 when 'agendada' then 3
               when 'encerrada' then 4 when 'desligada' then 5 else 6
             end as ordem
    ) s
    left join lateral (
      select
        jsonb_agg(jsonb_build_object(
          'codigo', op.codigo,
          'produtoId', pr.id::text,
          'produtoCodigo', pr.codigo,
          'produtoNome', pr.nome,
          'produtoVertical', pr.vertical,
          'produtoCategoria', pr.categoria,
          'nome', op.nome,
          'descricao', op.descricao,
          'valor', op.valor,
          'parcelas', op.parcelas,
          'valorParcela', op.valor_parcela,
          'valorRiscado', op.valor_riscado,
          'moeda', op.moeda,
          'ordem', op.ordem,
          'checkoutUrl', op.checkout_url,
          'sistemaExterno', op.sistema_externo,
          'skuExterno', op.sku_externo,
          'noSite', site.codigo is not null,
          'vigenteNoSite', coalesce(site.vigente, false),
          'eduzz', case when ez.eduzz_product_id is null then null
                        else jsonb_build_object('preco', ez.price_value, 'lidoEm', ez.last_synced_at,
                                                'arquivado', ez.arquivado) end
        ) order by op.ordem, pr.nome, op.codigo) as precos,
        jsonb_agg(distinct to_jsonb(pr.vertical)) filter (where pr.vertical is not null) as verticais,
        jsonb_agg(distinct to_jsonb(pr.codigo)) as produtos,
        bool_or(site.codigo is not null) as no_site
      from catalogo.oferta_precos op
      join catalogo.produtos pr on pr.id = op.produto_id
      left join api.ofertas site on site.codigo = op.codigo
      left join eduzz.produtos ez on ez.eduzz_product_id = op.sku_externo
      where op.oferta_id = o.id
    ) p on true
    left join lateral (
      select jsonb_agg(jsonb_build_object(
               'produtoCodigo', pp.codigo,
               'inclusoCodigo', pi.codigo,
               'inclusoNome', pi.nome,
               'nome', oi.nome,
               'descricao', oi.descricao,
               'detalhe', oi.detalhe,
               'nota', oi.nota,
               'valor', oi.valor,
               'valorReferencia', oi.valor_referencia,
               'iniciaEm', oi.inicia_em,
               'encerraEm', oi.encerra_em,
               'ordem', oi.ordem
             ) order by oi.ordem, pi.nome) as bonus
        from catalogo.oferta_inclui oi
        join catalogo.produtos pp on pp.id = oi.produto_id
        join catalogo.produtos pi on pi.id = oi.incluso_id
       where oi.oferta_id = o.id
    ) b on true
    left join lateral (
      select jsonb_agg(jsonb_build_object(
               'produtoCodigo', pq.codigo,
               'produtoNome', pq.nome,
               'modo', rq.modo,
               'prioridade', rq.prioridade,
               'grupoExclusivo', rq.grupo_exclusivo,
               'ativo', rq.ativo,
               'iniciaEm', rq.inicia_em,
               'encerraEm', rq.encerra_em,
               'observacao', rq.observacao,
               'ordem', rq.ordem
             ) order by rq.ordem, pq.nome) as requer
        from catalogo.oferta_requer rq
        join catalogo.produtos pq on pq.id = rq.produto_id
       where rq.oferta_id = o.id
    ) r on true
    where p_id is null or o.id = p_id
  ) x;
$fn$;

create or replace function public.mind_admin_read_cupons(p_id uuid default null, p_agora timestamptz default now())
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public'
as $fn$
  select coalesce(jsonb_agg(x.obj order by x.ordem, x.codigo), '[]'::jsonb)
  from (
    select c.codigo, s.ordem,
      jsonb_build_object(
        'id', c.id::text,
        'codigo', c.codigo,
        'descricao', c.descricao,
        'tipo', c.tipo,
        'valor', c.valor,
        'aplicaEm', c.aplica_em,
        'ofertas', to_jsonb(c.ofertas),
        'programas', to_jsonb(c.programas),
        'produtos', to_jsonb(c.produtos),
        'valorMinimo', c.valor_minimo,
        'tetoDesconto', c.teto_desconto,
        'usosMaximos', c.usos_maximos,
        'usos', c.usos,
        'usosPorEmail', c.usos_por_email,
        'iniciaEm', c.inicia_em,
        'encerraEm', c.encerra_em,
        'ativo', c.ativo,
        'sistema', c.sistema,
        'historico', c.historico,
        'situacao', s.situacao,
        'situacaoOrdem', s.ordem,
        'origem', c.origem,
        'criadoEm', c.criado_em,
        'atualizadoEm', c.atualizado_em
      ) as obj
    from catalogo.cupons c
    cross join lateral (
      select case
               when c.historico then 'historico'
               when not c.ativo then 'desligado'
               when c.inicia_em is not null and p_agora < c.inicia_em then 'agendado'
               when c.encerra_em is not null and p_agora > c.encerra_em then 'encerrado'
               when c.usos_maximos is not null and c.usos >= c.usos_maximos then 'esgotado'
               else 'valendo'
             end as situacao
    ) s0
    cross join lateral (
      select s0.situacao,
             case s0.situacao
               when 'valendo' then 1 when 'agendado' then 2 when 'esgotado' then 3
               when 'encerrado' then 4 when 'desligado' then 5 else 6
             end as ordem
    ) s
    where p_id is null or c.id = p_id
  ) x;
$fn$;

revoke all on function public.mind_admin_read_ofertas(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.mind_admin_read_cupons(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.mind_admin_read_ofertas(uuid, timestamptz) to service_role;
grant execute on function public.mind_admin_read_cupons(uuid, timestamptz) to service_role;
