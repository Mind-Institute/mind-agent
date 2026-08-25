-- Dois furos encontrados no teste em producao:
--  1. criava pessoa so com WhatsApp, antes de pedir o e-mail;
--  2. depois de ligada, o e-mail que chegasse nunca era buscado de novo --
--     entao a duplicata com uma cliente antiga ficava permanente.
--
-- Agora: mesmo com a conversa ja ligada, se chegar um e-mail que pertence a
-- OUTRA pessoa, nao enriquece em silencio. Devolve precisa_fundir com os dois
-- ids e deixa a decisao para gente.

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
  v_dono_email uuid;
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

  -- de quem e esse e-mail hoje?
  if v_email is not null then
    select p.id into v_dono_email from crm.pessoas p where lower(p.email) = v_email limit 1;
    if v_dono_email is null then
      select i.pessoa_id into v_dono_email from engagement.identidades i
       where i.canal='email' and i.identificador = v_email limit 1;
    end if;
  end if;

  if conv.participante_id is not null then
    v_pessoa := conv.participante_id;
    -- SEGUNDA BUSCA acontece mesmo com a conversa ja ligada: se o e-mail e de
    -- outra pessoa que ja existe, temos duas fichas para a mesma gente.
    if v_dono_email is not null and v_dono_email <> v_pessoa then
      return jsonb_build_object(
        'pessoa_encontrada', true, 'criou', false, 'precisa_perguntar', false,
        'precisa_fundir', true,
        'participante_id', v_pessoa,
        'outro_cadastro_id', v_dono_email,
        'motivo', 'email_pertence_a_outro_cadastro');
    end if;
  else
    v_cands := public.treble_candidatos_identidade(v_nome, v_sobre, v_email, v_dig);
    v_n := jsonb_array_length(v_cands);

    if v_n = 0 then
      -- SO CRIA COM E-MAIL. Sem ele, a segunda busca nao aconteceu ainda:
      -- devolve o que falta para o agente pedir, e tenta de novo no proximo turno.
      if v_email is null then
        return jsonb_build_object(
          'pessoa_encontrada', false, 'criou', false, 'precisa_perguntar', false,
          'motivo','falta_email_para_a_segunda_busca',
          'falta', to_jsonb(array['email']));
      end if;
      v_pessoa := null;
    elsif v_n = 1 then
      v_c := v_cands->0;
      if (v_c->>'precisa_confirmar_nome')::boolean and p_mesma_pessoa is null then
        return jsonb_build_object(
          'pessoa_encontrada', false, 'criou', false, 'precisa_perguntar', true,
          'pergunta', public.treble_pergunta_de_identidade(v_cands));
      end if;
      if (v_c->>'precisa_confirmar_nome')::boolean and p_mesma_pessoa is false then
        v_pessoa := null;
      else
        v_pessoa := (v_c->>'pessoa_id')::uuid;
      end if;
    else
      return jsonb_build_object(
        'pessoa_encontrada', false, 'criou', false, 'precisa_perguntar', true,
        'candidatos', v_n,
        'pergunta', public.treble_pergunta_de_identidade(v_cands));
    end if;
  end if;

  v_email_livre := v_email is not null
    and (v_dono_email is null or v_dono_email = v_pessoa);

  if v_pessoa is null then
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
      'pessoa_encontrada', true, 'criou', v_criou,
      'precisa_perguntar', false, 'precisa_fundir', false,
      'participante_id', v_pessoa,
      'perfil', jsonb_strip_nulls(jsonb_build_object(
        'primeiro_nome', p.primeiro_nome, 'sobrenome', p.sobrenome,
        'email', p.email, 'whatsapp', p.whatsapp,
        'empresa', p.empresa, 'cargo', p.cargo, 'estagio', p.estagio)),
      'falta', to_jsonb(array_remove(array[
        case when p.primeiro_nome is null then 'nome' end,
        case when p.sobrenome     is null then 'sobrenome' end,
        case when p.email         is null then 'email' end], null)))
    from crm.pessoas p where p.id = v_pessoa);
end;
$function$;

revoke all on function public.treble_agent_identificar(text,text,text,text,boolean) from public, anon, authenticated;
grant execute on function public.treble_agent_identificar(text,text,text,text,boolean) to service_role;

comment on function public.treble_agent_identificar(text,text,text,text,boolean) is
  'SEGUNDA busca da pessoa. So cria com e-mail em maos -- sem ele a segunda busca nao aconteceu. Roda a busca mesmo com a conversa ja ligada: e-mail de outro cadastro devolve precisa_fundir, nunca enriquece em silencio.';
