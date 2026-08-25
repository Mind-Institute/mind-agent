-- Passo 1b: a SEGUNDA busca. O agente pediu o que faltava; agora procuramos
-- de novo com a chave nova antes de criar qualquer coisa. E aqui que a
-- cliente antiga que chegou por um numero desconhecido volta a ser uma so.

create or replace function public.treble_agent_identificar(
  p_session_external_id text,
  p_email text default null,
  p_nome text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public','treble','crm','engagement'
as $function$
declare
  conv        treble.conversations;
  v_email     text := lower(nullif(trim(coalesce(p_email,'')),''));
  v_nome      text := nullif(left(trim(coalesce(p_nome,'')),120),'');
  v_digitos   text;
  v_pessoa    uuid;
  v_por_email uuid;
  v_criou     boolean := false;
  v_conflito  boolean := false;
begin
  select * into conv from treble.conversations
   where session_external_id = p_session_external_id;
  if not found then
    raise exception 'conversa_nao_encontrada';
  end if;

  if v_email is not null and v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$' then
    v_email := null;
  end if;

  v_digitos := regexp_replace(coalesce(conv.telefone,''), '\D', '', 'g');
  v_pessoa  := conv.participante_id;

  -- SEGUNDA BUSCA: agora pelo e-mail.
  if v_email is not null then
    select p.id into v_por_email from crm.pessoas p where lower(p.email) = v_email limit 1;
    if v_por_email is null then
      select i.pessoa_id into v_por_email from engagement.identidades i
       where i.canal = 'email' and i.identificador = v_email limit 1;
    end if;
  end if;

  if v_pessoa is null then
    v_pessoa := v_por_email;
  elsif v_por_email is not null and v_por_email <> v_pessoa then
    -- o e-mail e de outra pessoa que ja existe. Nao funde sozinho.
    v_conflito := true;
  end if;

  -- So cria depois que as duas buscas falharam.
  if v_pessoa is null then
    if v_email is null and length(v_digitos) < 10 then
      return jsonb_build_object('pessoa_encontrada', false, 'criou', false,
                                'motivo', 'sem_chave');
    end if;
    insert into crm.pessoas (email, whatsapp, primeiro_nome, origem)
    values (v_email, nullif(v_digitos,''), v_nome, 'bot')
    returning id into v_pessoa;
    v_criou := true;
  else
    -- achou: completa o que faltava sem sobrescrever o que ja havia
    update crm.pessoas set
      email         = coalesce(email, v_email),
      whatsapp      = coalesce(whatsapp, nullif(v_digitos,'')),
      primeiro_nome = coalesce(primeiro_nome, v_nome),
      atualizado_em = now()
    where id = v_pessoa;
  end if;

  -- as identidades de canal: e por elas que a proxima conversa acha essa pessoa
  if length(v_digitos) >= 10 then
    insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
    values (v_pessoa, 'whatsapp', v_digitos, true, 'alta')
    on conflict (canal, identificador) do nothing;
  end if;
  if v_email is not null and not v_conflito then
    insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
    values (v_pessoa, 'email', v_email, false, 'media')
    on conflict (canal, identificador) do nothing;
  end if;
  insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
  values (v_pessoa, 'treble_session', conv.session_external_id, true, 'alta')
  on conflict (canal, identificador) do nothing;

  update treble.conversations
     set participante_id = coalesce(participante_id, v_pessoa),
         nome_contato    = coalesce(nome_contato, v_nome),
         ultima_atividade = now()
   where id = conv.id;

  return (
    select jsonb_strip_nulls(jsonb_build_object(
      'pessoa_encontrada', true,
      'criou', v_criou,
      'conflito_identidade', v_conflito,
      'participante_id', v_pessoa,
      'perfil', jsonb_strip_nulls(jsonb_build_object(
        'primeiro_nome', p.primeiro_nome, 'email', p.email, 'whatsapp', p.whatsapp,
        'empresa', p.empresa, 'cargo', p.cargo, 'estagio', p.estagio))))
    from crm.pessoas p where p.id = v_pessoa);
end;
$function$;

revoke all on function public.treble_agent_identificar(text,text,text) from public, anon, authenticated;
grant execute on function public.treble_agent_identificar(text,text,text) to service_role;

comment on function public.treble_agent_identificar(text,text,text) is
  'SEGUNDA busca da pessoa, com a chave que o agente acabou de pedir. So cria em crm.pessoas se esta busca tambem falhar. Se o e-mail pertencer a outra pessoa ja existente, marca conflito_identidade e NAO funde sozinho.';
