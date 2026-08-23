-- treble_agent_start passa a listar sobrenome no que falta.
create or replace function public.treble_agent_start(
  p_session_external_id text,
  p_contact jsonb default '{}'::jsonb,
  p_origem text default null,
  p_utm_token text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public','summit','comum','engagement','intelligence','mind','treble','crm'
as $function$
declare
  conv treble.conversations;
  hist jsonb;
  u engagement.utm_sessoes;
  origem_final text;
  v_pessoa uuid;
  v_digitos text;
  v_perfil jsonb := null;
  v_falta text[] := array[]::text[];
begin
  if p_session_external_id is null or length(p_session_external_id) < 3 then
    raise exception 'session_external_id invalido';
  end if;

  select * into u from engagement.utm_sessoes
   where token = nullif(trim(coalesce(p_utm_token,'')),'');

  origem_final := coalesce(
    (select o.codigo from engagement.origens o
      where o.codigo = nullif(trim(coalesce(p_origem,'')),'') and o.ativo),
    u.origem_codigo);

  insert into treble.conversations
    (session_external_id, nome_contato, telefone, telefone_hash, origem_codigo,
     utm_token, utm, produto_codigo)
  values (
    p_session_external_id,
    nullif(trim(coalesce(p_contact->>'nome','')),''),
    nullif(trim(coalesce(coalesce(p_contact->>'whatsapp', p_contact->>'telefone'),'')),''),
    nullif(trim(coalesce(p_contact->>'telefone_hash','')),''),
    origem_final,
    u.token,
    case when u.token is null then null else jsonb_strip_nulls(jsonb_build_object(
      'utm_source', u.utm_source, 'utm_medium', u.utm_medium,
      'utm_campaign', u.utm_campaign, 'utm_content', u.utm_content,
      'utm_term', u.utm_term, 'gclid', u.gclid, 'fbclid', u.fbclid,
      'site', u.site, 'referrer', u.referrer, 'landing_url', u.landing_url)) end,
    coalesce((select o.produto_codigo from engagement.origens o where o.codigo = origem_final),
             (select valor from treble.config where chave = 'produto_padrao')))
  on conflict (session_external_id) do update
    set ultima_atividade = now(),
        nome_contato = coalesce(treble.conversations.nome_contato, excluded.nome_contato),
        telefone = coalesce(treble.conversations.telefone, excluded.telefone),
        telefone_hash = coalesce(treble.conversations.telefone_hash, excluded.telefone_hash),
        origem_codigo = coalesce(treble.conversations.origem_codigo, excluded.origem_codigo),
        utm_token = coalesce(treble.conversations.utm_token, excluded.utm_token),
        utm = coalesce(treble.conversations.utm, excluded.utm),
        produto_codigo = coalesce(treble.conversations.produto_codigo, excluded.produto_codigo)
  returning * into conv;

  if u.token is not null then
    update engagement.utm_sessoes set usado_em = coalesce(usado_em, now()) where token = u.token;
  end if;

  -- PRIMEIRA BUSCA: pelo WhatsApp, a chave que veio.
  v_pessoa  := conv.participante_id;
  v_digitos := regexp_replace(coalesce(conv.telefone,''), '\D', '', 'g');

  if v_pessoa is null then
    v_pessoa := public.treble_resolver_por_whatsapp(conv.telefone);
  end if;

  if v_pessoa is not null then
    if length(v_digitos) >= 10 then
      insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
      values (v_pessoa, 'whatsapp', v_digitos, true, 'alta')
      on conflict (canal, identificador) do nothing;
    end if;
    insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
    values (v_pessoa, 'treble_session', conv.session_external_id, true, 'alta')
    on conflict (canal, identificador) do nothing;

    update treble.conversations set participante_id = v_pessoa
     where id = conv.id and participante_id is null;
    conv.participante_id := v_pessoa;

    select jsonb_strip_nulls(jsonb_build_object(
             'pessoa_id', p.id, 'primeiro_nome', p.primeiro_nome, 'sobrenome', p.sobrenome,
             'email', p.email, 'whatsapp', p.whatsapp,
             'empresa', p.empresa, 'cargo', p.cargo, 'estagio', p.estagio))
      into v_perfil
    from crm.pessoas p where p.id = v_pessoa;
  end if;

  -- O QUE FALTA. Nunca pedir o que ja se sabe.
  if coalesce(v_perfil->>'primeiro_nome', conv.nome_contato) is null then
    v_falta := array_append(v_falta, 'nome');
  end if;
  if (v_perfil->>'sobrenome') is null then
    v_falta := array_append(v_falta, 'sobrenome');
  end if;
  if length(v_digitos) < 10 and (v_perfil->>'whatsapp') is null then
    v_falta := array_append(v_falta, 'whatsapp');
  end if;
  if (v_perfil->>'email') is null then
    v_falta := array_append(v_falta, 'email');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('papel', m.papel, 'conteudo', m.conteudo)
                            order by m.criado_em), '[]'::jsonb)
    into hist
  from (select papel, conteudo, criado_em from treble.messages
         where conversation_id = conv.id order by criado_em desc limit 12) m;

  return jsonb_build_object(
    'conversation_id', conv.id, 'audience', conv.audience, 'stage', conv.stage,
    'variables', conv.variables, 'nome_contato', conv.nome_contato,
    'origem_codigo', conv.origem_codigo, 'utm', conv.utm,
    'produto_codigo', conv.produto_codigo, 'historico', hist,
    'participante_id', conv.participante_id,
    'pessoa_encontrada', (conv.participante_id is not null),
    'perfil', v_perfil,
    'falta', to_jsonb(v_falta));
end;
$function$;