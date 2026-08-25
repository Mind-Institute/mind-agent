-- Visão geral de conteúdo sempre presente no contexto do agente:
-- perguntas genéricas ("me fala do conteúdo") passam a ter matéria-prima
-- mesmo quando a busca literal não encontra nada.
create or replace function public.treble_agent_context() returns jsonb
language sql security definer set search_path = public, mind
as $$
select jsonb_build_object(
  'evento', (select to_jsonb(e) - 'id' from mind.events e limit 1),
  'visao_geral', jsonb_build_object(
    'numeros', jsonb_build_object(
      'sessoes', (select count(*) from mind.sessions),
      'palestrantes', (select count(*) from mind.speakers),
      'dias', 2),
    'trilhas', (select coalesce(jsonb_agg(distinct t.trilha), '[]'::jsonb)
                from mind.sessions s, unnest(s.trilhas) as t(trilha)),
    'palestrantes_destaque', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'nome', d.nome, 'cargo', d.cargo, 'organizacao', d.organizacao)), '[]'::jsonb)
      from (select nome, cargo, organizacao from mind.speakers
             where destaque order by nome limit 12) d),
    'publico_e_dores', (
      select coalesce(jsonb_agg(x.rotulo), '[]'::jsonb)
      from (select rotulo from mind.taxonomy where ativo and tipo in ('area','dor') limit 18) x)
  ),
  'ofertas_vigentes', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'codigo', o.codigo, 'nome', o.nome, 'valor', o.valor,
      'condicoes_pagamento', o.condicoes_pagamento,
      'checkout_url', o.checkout_url,
      'lote_termina_em', o.encerra_em)), '[]'::jsonb)
    from mind.offers o where o.ativo and o.publico),
  'proximo_lote', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'codigo', o.codigo, 'valor', o.valor, 'comeca_em', o.inicia_em)), '[]'::jsonb)
    from mind.offers o
    where not o.ativo and o.inicia_em is not null and o.inicia_em > now()
      and o.inicia_em = (select min(i.inicia_em) from mind.offers i
                          where i.inicia_em > now() and not (i.elegibilidade ? 'grupo'))
      and not (o.elegibilidade ? 'grupo')),
  'regras_comerciais', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'chave', r.chave, 'descricao', r.descricao, 'config', r.config)), '[]'::jsonb)
    from mind.commercial_rules r where r.ativo),
  'politicas', (
    select coalesce(jsonb_agg(jsonb_build_object('titulo', p.titulo, 'texto', p.texto)), '[]'::jsonb)
    from mind.policies p where p.ativo),
  'faq', (
    select coalesce(jsonb_agg(jsonb_build_object('titulo', c.titulo, 'texto', c.corpo)), '[]'::jsonb)
    from (select titulo, corpo from mind.organization_content
           where ativo and categoria = 'faq' limit 20) c)
)
$$;
