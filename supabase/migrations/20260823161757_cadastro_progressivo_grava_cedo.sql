-- CADASTRO PROGRESSIVO. Decisao da Adriana em 23/08/2026:
-- "nome e WhatsApp ja precisa ser gravado, inclusive transmitido para o HubSpot.
--  Nao acho que a gente deixe de atender uma pessoa porque ela nao quer nos dar
--  o email. Entao, insiste duas vezes antes de comecar a atender sem o email."
--
-- Isto DESFAZ uma regra que eu tinha posto por cima do CRM dela: exigir e-mail
-- para criar. O proprio CRM ja aceitava os dois casos --
-- `pessoas_tem_chave CHECK (email is not null or whatsapp is not null)`.
--
-- O risco que a regra do e-mail cobria continua coberto por outra coisa: a
-- SEGUNDA BUSCA roda em todo turno em que a pessoa fala de si, e quando o
-- e-mail que chega pertence a outra ficha ela devolve precisa_fundir com os
-- dois ids, em vez de enriquecer em silencio. Ninguem funde sozinho.

-- 1. mind_pessoa_completar -- preenche so o que esta vazio, nunca sobrescreve.
--    Nome do Mind, nao do Treble: o Concierge e o CS completam cadastro igual.
create or replace function public.mind_pessoa_completar(
  p_pessoa_id uuid,
  p_sobrenome text default null,
  p_empresa   text default null,
  p_cargo     text default null,
  p_email     text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public','crm','engagement'
as $function$
declare
  v_email text := lower(nullif(trim(coalesce(p_email,'')),''));
  v_dono  uuid;
begin
  if p_pessoa_id is null then return null; end if;

  if v_email is not null and v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$' then
    v_email := null;
  end if;

  -- o e-mail so entra se nao for de outra ficha. Se for, quem resolve e
  -- mind_identificar_pessoa, que devolve precisa_fundir.
  if v_email is not null then
    select p.id into v_dono from crm.pessoas p where lower(p.email) = v_email limit 1;
    if v_dono is not null and v_dono <> p_pessoa_id then v_email := null; end if;
  end if;

  update crm.pessoas set
    sobrenome     = coalesce(sobrenome, nullif(left(trim(coalesce(p_sobrenome,'')),120),'')),
    empresa       = coalesce(empresa,   nullif(left(trim(coalesce(p_empresa,'')),160),'')),
    cargo         = coalesce(cargo,     nullif(left(trim(coalesce(p_cargo,'')),120),'')),
    email         = case when email is null then v_email else email end,
    atualizado_em = now()
  where id = p_pessoa_id;

  if v_email is not null then
    insert into engagement.identidades (pessoa_id, canal, identificador, verificado, confianca)
    values (p_pessoa_id, 'email', v_email, false, 'media')
    on conflict (canal, identificador) do nothing;
  end if;

  return (
    select jsonb_build_object(
      'perfil', jsonb_strip_nulls(jsonb_build_object(
        'primeiro_nome', p.primeiro_nome, 'sobrenome', p.sobrenome,
        'email', p.email, 'whatsapp', p.whatsapp,
        'empresa', p.empresa, 'cargo', p.cargo, 'estagio', p.estagio)),
      -- OBRIGATORIO trava; DESEJAVEL nunca trava a venda.
      'falta_obrigatorio', to_jsonb(array_remove(array[
        case when p.primeiro_nome is null then 'nome'     end,
        case when p.whatsapp      is null then 'whatsapp' end,
        case when p.email         is null then 'email'    end], null)),
      'falta_desejavel', to_jsonb(array_remove(array[
        case when p.sobrenome is null then 'sobrenome' end,
        case when p.empresa   is null then 'empresa'   end,
        case when p.cargo     is null then 'cargo'     end], null)))
    from crm.pessoas p where p.id = p_pessoa_id);
end;
$function$;

-- 2. mind_lead_capturar -- a fila de saida para o HubSpot. Uma linha por
--    conversa: reescreve a pendente em vez de empilhar duplicata.
create or replace function public.mind_lead_capturar(
  p_pessoa_id uuid,
  p_agente text,
  p_referencia text,
  p_contexto jsonb default '{}'::jsonb)
returns uuid
language plpgsql security definer
set search_path to 'public','crm'
as $function$
declare
  p crm.pessoas;
  v_id uuid;
begin
  select * into p from crm.pessoas where id = p_pessoa_id;
  if not found then return null; end if;
  if p.email is null and p.whatsapp is null then return null; end if;

  update crm.leads_capturados l set
    email         = p.email,
    whatsapp      = p.whatsapp,
    primeiro_nome = p.primeiro_nome,
    sobrenome     = p.sobrenome,
    empresa       = p.empresa,
    cargo         = p.cargo,
    contexto      = l.contexto || coalesce(p_contexto,'{}'::jsonb)
                      || jsonb_build_object('pessoa_id', p.id, 'referencia', p_referencia)
  where l.estado = 'pendente'
    and l.agente = p_agente
    and l.contexto->>'referencia' = p_referencia
  returning l.id into v_id;

  if v_id is not null then return v_id; end if;

  insert into crm.leads_capturados
    (email, whatsapp, primeiro_nome, sobrenome, empresa, cargo, agente, contexto, estado)
  values (p.email, p.whatsapp, p.primeiro_nome, p.sobrenome, p.empresa, p.cargo,
          p_agente,
          coalesce(p_contexto,'{}'::jsonb)
            || jsonb_build_object('pessoa_id', p.id, 'referencia', p_referencia),
          'pendente')
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function public.mind_pessoa_completar(uuid,text,text,text,text) from public, anon, authenticated;
revoke all on function public.mind_lead_capturar(uuid,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.mind_pessoa_completar(uuid,text,text,text,text) to service_role;
grant execute on function public.mind_lead_capturar(uuid,text,text,jsonb) to service_role;

comment on function public.mind_pessoa_completar(uuid,text,text,text,text) is
  'Cadastro progressivo: preenche so o que esta vazio, nunca sobrescreve. Devolve falta_obrigatorio (nome, whatsapp, email) e falta_desejavel (sobrenome, empresa, cargo). Desejavel nunca trava a venda.';
comment on function public.mind_lead_capturar(uuid,text,text,jsonb) is
  'Fila de saida para o HubSpot. Uma linha pendente por (agente, referencia): reescreve em vez de empilhar. Assim nenhum lead se perde mesmo que a conversa morra antes do fim.';
