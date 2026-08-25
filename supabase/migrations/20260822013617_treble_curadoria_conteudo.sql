-- Curadoria de conteúdo do bot (pedido da Adriana): o contexto do agente
-- nasce VAZIO de conteúdo — só preços/lotes (mind.offers, fonte da verdade)
-- e regras comerciais (guardrails). Todo o resto entra item a item:
--   · documentos (o-que-inclui, FAQ, experiências): coluna aprovado_treble
--   · blocos estruturados (visão geral, políticas, agenda): flags em treble.config
-- Nada é apagado — sessions/speakers/knowledge seguem servindo o site.

alter table mind.knowledge_documents
  add column if not exists aprovado_treble boolean not null default false;

comment on column mind.knowledge_documents.aprovado_treble is
  'Curadoria do bot do WhatsApp: só documentos aprovados entram no contexto do agente Treble. O concierge do site NÃO é afetado por esta coluna.';

insert into treble.config (chave, valor) values
  ('bloco_visao_geral', 'false'),
  ('bloco_politicas', 'false'),
  ('bloco_agenda_busca', 'false')
on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();

create or replace function public.treble_agent_context() returns jsonb
language sql security definer set search_path = public, mind, treble
as $$
select jsonb_build_object(
  'evento', (select to_jsonb(e) - 'id' from mind.events e limit 1),
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
  -- Conteúdo curado: só o que a Adriana aprovou, um a um
  'experiencias_o_que_inclui', (
    select coalesce(jsonb_agg(jsonb_build_object('titulo', k.titulo, 'texto', left(k.corpo, 1500))), '[]'::jsonb)
    from mind.knowledge_documents k
    where k.tipo_conteudo = 'ingresso' and k.aprovado_treble),
  'faq', (
    select coalesce(jsonb_agg(jsonb_build_object('titulo', k.titulo, 'texto', left(k.corpo, 1200))), '[]'::jsonb)
    from mind.knowledge_documents k
    where k.tipo_conteudo = 'faq' and k.aprovado_treble),
  'conteudo_aprovado', (
    select coalesce(jsonb_agg(jsonb_build_object('titulo', k.titulo, 'texto', left(k.corpo, 1200))), '[]'::jsonb)
    from mind.knowledge_documents k
    where k.tipo_conteudo not in ('ingresso','faq') and k.aprovado_treble),
  -- Blocos estruturados: ligados por flag em treble.config
  'visao_geral', case when (select valor from treble.config where chave='bloco_visao_geral') = 'true'
    then jsonb_build_object(
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
        from (select rotulo from mind.taxonomy where ativo and tipo in ('area','dor') limit 18) x))
    else '"bloco desligado — aguardando aprovação"'::jsonb end,
  'politicas', case when (select valor from treble.config where chave='bloco_politicas') = 'true'
    then (select coalesce(jsonb_agg(jsonb_build_object('titulo', p.titulo, 'texto', p.texto)), '[]'::jsonb)
          from mind.policies p where p.ativo)
    else '"bloco desligado — aguardando aprovação"'::jsonb end
)
$$;
