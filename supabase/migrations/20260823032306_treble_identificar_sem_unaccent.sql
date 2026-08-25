-- Normalizacao de nome sem depender da extensao unaccent (nao instalada).
-- Erro seguro: acento diferente vira conflito (agente pergunta), nunca fusao errada.
create or replace function public.mind_nome_simples(p text)
returns text language sql immutable as $$
  select nullif(regexp_replace(
           lower(translate(coalesce(p,''),
             'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
             'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')),
           '[^a-z0-9]+', '', 'g'), '');
$$;

drop function if exists public.treble_agent_identificar(text,text,text,text,boolean);

create or replace function public.treble_agent_identificar(
  p_session_external_id text,
  p_email text default null,
  p_nome text default null,
  p_sobrenome text default null,
  p_confirmar_mesmo_email boolean default false)
returns jsonb
language plpgsql security definer
set search_path to 'public','treble','crm','engagement'
as $function$
declare
  conv        treble.conversations;
  v_email     text := lower(nullif(trim(coalesce(p_email,'')),''));
  v_nome      text := nullif(left(trim(coalesce(p_nome,'')),120),'');
  v_sobre     text := nullif(left(trim(coalesce(p_sobrenome,'')),120),'');
  v_digitos   text;
  v_pessoa    uuid;
  v_por_email uuid;
  v_dono_nome text;
  v_criou     boolean := false;
  v_conflito  boolean := false;
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

  v_digitos := regexp_replace(coalesce(conv.telefone,''), '\D', '', 'g');
  v_pessoa  := conv.participante_id;

  -- WhatsApp e chave forte: e o aparelho de quem esta falando.
  -- E-mail e chave FRACA: quem compra varios ingressos usa o proprio e-mail
  -- para as outras pessoas. Os dois contatos existem no CRM, mas so depois
  -- da atribuicao do ingresso -- que pode demorar meses. Antes disso, so o
  -- comprador existe, e o convidado que chega dando o e-mail dele nao e ele.
  if v_email is not null then
    select p.id, p.primeiro_nome into v_por_email, v_dono_nome
      from crm.pessoas p where lower(p.email) = v_email limit 1;
    if v_por_email is null then
      select i.pessoa_id into v_por_email from engagement.identidades i
       where i.canal = 'email' and i.identificador = v_email limit 1;
      if v_por_email is not null then
        select p.primeiro_nome into v_dono_nome from crm.pessoas p where p.id = v_por_email;
      end if;
    end if;
  end if;

  if v_por_email is not null and v_pessoa is null and not p_confirmar_mesmo_email
     and v_nome is not null and v_dono_nome is not null
     and public.mind_nome_simples(v_nome) is distinct from public.mind_nome_simples(v_dono_nome) then
    return jsonb_build_object(
      'pessoa_encontrada', false, 'criou', false,
      'conflito_identidade', true,
      'motivo', 'email_de_outra_pessoa',
      'nome_de_quem_tem_o_email', v_dono_nome,
      'falta', to_jsonb(array['confirmar_titular_do_email']));
  end if;

  if v_pessoa is null then
    v_pessoa := v_por_email;
  elsif v_por_email is not null and v_por_email <> v_pessoa then
    v_conflito := true;
  end if;

  if v_pessoa is null then
    if v_email is null and length(v_digitos) < 10 then
      return jsonb_build_object('pessoa_encontrada', false, 'criou', false, 'motivo', 'sem_chave');
    end if;
    insert into crm.pessoas (email, whatsapp, primeiro_nome, sobrenome, origem)
    values (case when v_por_email is null then v_email else null end,
            nullif(v_digitos,''), v_nome, v_sobre, 'bot')
    returning id into v_pessoa;
    v_criou := true;
  else
    update crm.pessoas set
      email         = coalesce(email, case when v_por_email is null then v_email else email end),
      whatsapp      = coalesce(whatsapp, nullif(v_digitos,'')),
      primeiro_nome = coalesce(primeiro_nome, v_nome),
      sobrenome     = coalesce(sobrenome, v_sobre),
      atualizado_em = now()
    where id = v_pessoa;
  end if;

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
     set participante_id  = coalesce(participante_id, v_pessoa),
         nome_contato     = coalesce(nome_contato, v_nome),
         ultima_atividade = now()
   where id = conv.id;

  return (
    select jsonb_build_object(
      'pessoa_encontrada', true, 'criou', v_criou,
      'conflito_identidade', v_conflito,
      'participante_id', v_pessoa,
      'perfil', jsonb_strip_nulls(jsonb_build_object(
        'primeiro_nome', p.primeiro_nome, 'sobrenome', p.sobrenome,
        'email', p.email, 'whatsapp', p.whatsapp,
        'empresa', p.empresa, 'cargo', p.cargo, 'estagio', p.estagio)),
      'falta', to_jsonb(array_remove(array[
        case when p.sobrenome is null then 'sobrenome' end,
        case when p.email     is null then 'email'     end], null)))
    from crm.pessoas p where p.id = v_pessoa);
end;
$function$;

revoke all on function public.treble_agent_identificar(text,text,text,text,boolean) from public, anon, authenticated;
grant execute on function public.treble_agent_identificar(text,text,text,text,boolean) to service_role;
