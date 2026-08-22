-- start passa a resolver o token de UTM que veio no texto do wa.me.
-- Primeira gravacao vence: a atribuicao e da entrada.
drop function if exists public.treble_agent_start(text, jsonb, text);

create or replace function public.treble_agent_start(
  p_session_external_id text,
  p_contact jsonb default '{}'::jsonb,
  p_origem text default null,
  p_utm_token text default null
) returns jsonb
language plpgsql security definer set search_path = public, mind, treble
as $fn$
declare
  conv treble.conversations;
  hist jsonb;
  u mind.utm_sessoes;
  origem_final text;
begin
  if p_session_external_id is null or length(p_session_external_id) < 3 then
    raise exception 'session_external_id invalido';
  end if;

  select * into u from mind.utm_sessoes
   where token = nullif(trim(coalesce(p_utm_token,'')),'');

  -- A origem pode vir do payload do Treble ou de dentro da sessao de UTM.
  origem_final := coalesce(
    (select o.codigo from mind.origens o
      where o.codigo = nullif(trim(coalesce(p_origem,'')),'') and o.ativo),
    u.origem_codigo);

  insert into treble.conversations
    (session_external_id, nome_contato, telefone, telefone_hash, origem_codigo,
     utm_token, utm)
  values (
    p_session_external_id,
    nullif(trim(coalesce(p_contact->>'nome','')),''),
    nullif(trim(coalesce(p_contact->>'telefone','')),''),
    nullif(trim(coalesce(p_contact->>'telefone_hash','')),''),
    origem_final,
    u.token,
    case when u.token is null then null else jsonb_strip_nulls(jsonb_build_object(
      'utm_source', u.utm_source, 'utm_medium', u.utm_medium,
      'utm_campaign', u.utm_campaign, 'utm_content', u.utm_content,
      'utm_term', u.utm_term, 'gclid', u.gclid, 'fbclid', u.fbclid,
      'site', u.site, 'referrer', u.referrer, 'landing_url', u.landing_url)) end)
  on conflict (session_external_id) do update
    set ultima_atividade = now(),
        nome_contato = coalesce(treble.conversations.nome_contato, excluded.nome_contato),
        telefone = coalesce(treble.conversations.telefone, excluded.telefone),
        telefone_hash = coalesce(treble.conversations.telefone_hash, excluded.telefone_hash),
        origem_codigo = coalesce(treble.conversations.origem_codigo, excluded.origem_codigo),
        utm_token = coalesce(treble.conversations.utm_token, excluded.utm_token),
        utm = coalesce(treble.conversations.utm, excluded.utm)
  returning * into conv;

  if u.token is not null then
    update mind.utm_sessoes set usado_em = coalesce(usado_em, now()) where token = u.token;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('papel', m.papel, 'conteudo', m.conteudo)
                            order by m.criado_em), '[]'::jsonb)
    into hist
  from (select papel, conteudo, criado_em
          from treble.messages
         where conversation_id = conv.id
         order by criado_em desc limit 12) m;

  return jsonb_build_object(
    'conversation_id', conv.id,
    'audience', conv.audience,
    'stage', conv.stage,
    'variables', conv.variables,
    'nome_contato', conv.nome_contato,
    'origem_codigo', conv.origem_codigo,
    'utm', conv.utm,
    'historico', hist
  );
end;
$fn$;
revoke all on function public.treble_agent_start(text, jsonb, text, text)
  from public, anon, authenticated;

-- O contexto entrega o checkout JA com a atribuicao embutida, para o agente
-- nunca ter que montar URL — ele so copia o que esta em checkout_url.
drop function if exists public.treble_agent_context(text, text);

create or replace function public.treble_agent_context(
  p_audience text default 'desconhecido',
  p_origem text default null,
  p_utm jsonb default null,
  p_conversa text default null
) returns jsonb
language sql security definer set search_path = public, mind, treble
as $fn$
select public.treble_agent_context_base()
  || jsonb_build_object(
    'ofertas_vigentes', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'codigo', o.codigo, 'nome', o.nome, 'valor', o.valor,
        'condicoes_pagamento', o.condicoes_pagamento,
        'checkout_url', public.mind_checkout_url(o.checkout_url, p_utm, p_origem, p_conversa),
        'lote_termina_em', o.encerra_em,
        'procura', o.procura, 'procura_nota', o.procura_nota)), '[]'::jsonb)
      from mind.offers o where o.ativo and o.publico),
    'momento', public.treble_momento(),
    'origem_da_conversa', public.mind_origem(p_origem),
    'precos_por_volume', public.mind_precos_por_volume(),
    'materiais_que_posso_enviar', public.treble_materiais(p_audience, p_origem)
  )
$fn$;
revoke all on function public.treble_agent_context(text, text, jsonb, text)
  from public, anon, authenticated;
