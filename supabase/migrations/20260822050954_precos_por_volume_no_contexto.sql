-- Item 11: preco de grupo ja na primeira resposta. A conta nao pode ser
-- aritmetica do LLM (o guardrail de preco derruba, e com razao): os
-- valores com desconto por volume passam a ser calculados no banco a
-- partir de mind.offers + os tiers de commercial_rules, e entram no
-- contexto oficial como qualquer outro preco (D-3).

create or replace function public.mind_precos_por_volume()
returns jsonb
language sql
security definer
set search_path = public, mind
as $fn$
  with tiers as (
    select (t->>'min')::int as min_ingressos,
           (t->>'off')::numeric as off,
           t->>'label' as faixa
    from mind.commercial_rules r,
         lateral jsonb_array_elements(r.config->'tiers') t
    where r.chave = 'desconto_por_volume' and r.ativo
      and (t->>'off')::numeric > 0
  ), ofertas as (
    select o.codigo, o.nome, o.valor
    from mind.offers o
    where o.ativo and o.publico and o.valor is not null
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'faixa', t.faixa,
           'a_partir_de_ingressos', t.min_ingressos,
           'desconto_percentual', round(t.off * 100),
           'experiencia', o.nome,
           'valor_cheio_por_ingresso', o.valor,
           'valor_por_ingresso_com_desconto', round(o.valor * (1 - t.off)),
           'economia_por_ingresso', round(o.valor * t.off),
           'parcelamento_com_desconto', '12x de R$ ' || round(o.valor * (1 - t.off) / 12)
         ) order by t.min_ingressos, o.valor), '[]'::jsonb)
  from tiers t cross join ofertas o;
$fn$;
revoke all on function public.mind_precos_por_volume() from public, anon, authenticated;

comment on function public.mind_precos_por_volume() is
  'Tabela de precos por volume ja calculada (offers x tiers). Entra no contexto oficial para o agente citar valor de grupo sem fazer conta.';

create or replace function public.treble_agent_context(
  p_audience text default 'desconhecido',
  p_origem text default null
) returns jsonb
language sql security definer set search_path = public, mind, treble
as $fn$
select public.treble_agent_context_base() || jsonb_build_object(
    'momento', public.treble_momento(),
    'origem_da_conversa', public.mind_origem(p_origem),
    'precos_por_volume', public.mind_precos_por_volume(),
    'materiais_que_posso_enviar', public.treble_materiais(p_audience, p_origem)
  )
$fn$;
revoke all on function public.treble_agent_context(text, text)
  from public, anon, authenticated;
