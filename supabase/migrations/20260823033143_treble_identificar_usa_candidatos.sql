-- Uma so implementacao de casamento: treble_candidatos_identidade.
-- treble_agent_identificar passa a consumi-la em vez de repetir a logica.

drop function if exists public.treble_agent_identificar(text,text,text,text,boolean);

create or replace function public.treble_agent_identificar(
  p_session_external_id text,
  p_email text default null,
  p_nome text default null,
  p_sobrenome text default null,
  p_mesma_pessoa boolean default null)
returns jsonb
language plpgsql security definer
set search_path to 'public','treble','crm','engagement'
as $function$
declare
  conv      treble.conversations;
  v_email   text := lower(nullif(trim(coalesce(p_email,'')),''));
  v_nome    text := nullif(left(trim(coalesce(p_nome,'')),120),'');
  v_sobre   text := nullif(left(trim(coalesce(p_sobrenome,'')),120),'');
  v_dig     text;
  v_cands   jsonb;
  v_n       int;
  v_c       jsonb;
  v_pessoa  uuid;
  v_email_livre boolean;
  v_criou   boolean := false;
begin
  select * into conv from treble.conversations
   where session_external_id = p_session_external_id;
  if not found then raise exception 'conversa_nao_encontrada'; end if;

  if v_email is not null and v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$' then
    v_email := null;
  end if;
  if v_sobre is null and v_nome is not null and position(' ' in v_nome) > 0 then
    v_sobre := nullif(trim(substring(v_nome from position(' ' in v_nome) + 1)),'');
    v_nome  := trim(split_part(v_nome, ' ', 1));
  end if;

  v_dig := regexp_replace(coalesce(conv.telefone,''), '\D', '', 'g');
  if length(v_dig) < 10 then v_dig := null; end if;

  -- ja resolvida antes nesta conversa
  if conv.participante_id is not null then
    v_pessoa := conv.participante_id;
  else
    v_cands := public.treble_candidatos_identidade(v_nome, v_sobre, v_email, v_dig);
    v_n := jsonb_array_length(v_cands);

    if v_n = 0 then
      v_pessoa := null;                                   -- ninguem: cria
    elsif v_n = 1 then
      v_c := v_cands->0;
      if (v_c->>'precisa_confirmar_nome')::boolean and p_mesma_pessoa is null then
        return jsonb_build_object(
          'pessoa_encontrada', false, 'criou', false,
          'precisa_perguntar', true,
          'pergunta', public.treble_pergunta_de_identidade(v_cands));
      end if;
      if (v_c->>'precisa_confirmar_nome')::boolean and p_mesma_pessoa is false then
        v_pessoa := null;                                 -- e outra pessoa: cria
      else
        v_pessoa := (v_c->>'pessoa_id')::uuid;
      end if;
    else
      -- varios: nao decide sozinho
      return jsonb_build_object(
        'pessoa_encontrada', false, 'criou', false,
        'precisa_perguntar', true,
        'candidatos', jsonb_array_length(v_cands),
        'pergunta', public.treble_pergunta_de_identidade(v_cands));
    end if;
  end if;

  -- o e-mail ja pertence a outra pessoa? entao nao e desta.
  v_email_livre := v_email is not null and not exists (
    select 1 from crm.pessoas p where lower(p.email) = v_email
      and (v_pessoa is null or p.id <> v_pessoa));

  if v_pessoa is null then
    if v_email is null and v_dig is null then
      return jsonb_build_object('pessoa_encontrada', false, 'criou', false, 'motivo','sem_chave');
    end if;
    insert into crm.pessoas (email, whatsapp, primeiro_nome, sobrenome, origem)
    values (case when v_email_livre then v_email end, v_dig, v_nome, v_sobre, 'bot')
    returning id into v_pessoa;
    v_criou := true;
  else
    update crm.pessoas set
      email         = case when email is null and v_email_livre then v_email else email end,
      whatsapp      = coalesce(whatsapp, v_dig),
      primeiro_nome = coalesce(primeiro_nome, v_nome),
      sobrenome     = coalesce(sobrenome, v_sobre),
      atualizado_em = now()
    where id = v_pessoa;
  end if;

  if v_dig is not null then
    insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
    values (v_pessoa, 'whatsapp', v_dig, true, 'alta')
    on conflict (canal, identificador) do nothing;
  end if;
  if v_email_livre then
    insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
    values (v_pessoa, 'email', v_email, false, 'media')
    on conflict (canal, identificador) do nothing;
  end if;
  insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
  values (v_pessoa, 'treble_session', conv.session_external_id, true, 'alta')
  on conflict (canal, identificador) do nothing;

  update treble.conversations
     set participante_id  = coalesce(participante_id, v_pessoa),
         nome_contato     = coalesce(nome_contato, v_nome),
         ultima_atividade = now()
   where id = conv.id;

  return (
    select jsonb_build_object(
      'pessoa_encontrada', true, 'criou', v_criou, 'precisa_perguntar', false,
      'participante_id', v_pessoa,
      'perfil', jsonb_strip_nulls(jsonb_build_object(
        'primeiro_nome', p.primeiro_nome, 'sobrenome', p.sobrenome,
        'email', p.email, 'whatsapp', p.whatsapp,
        'empresa', p.empresa, 'cargo', p.cargo, 'estagio', p.estagio)),
      'falta', to_jsonb(array_remove(array[
        case when p.primeiro_nome is null then 'nome' end,
        case when p.sobrenome     is null then 'sobrenome' end,
        case when p.email is null and p.whatsapp is null then 'email' end], null)))
    from crm.pessoas p where p.id = v_pessoa);
end;
$function$;

revoke all on function public.treble_agent_identificar(text,text,text,text,boolean) from public, anon, authenticated;
grant execute on function public.treble_agent_identificar(text,text,text,text,boolean) to service_role;