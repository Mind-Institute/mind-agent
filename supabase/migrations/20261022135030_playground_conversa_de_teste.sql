-- Playground do Agent Intelligence (aprovado pela Adriana em 22/10/2026): testar um
-- agente no MESMO motor do chat real, numa conversa marcada como teste.
--
-- A conversa de teste nasce com `agente = 'mindagent-playground'`. É isso que a
-- deixa fora da análise pós-conversa (`analise_pendentes` só pega `treble`,
-- `treble-inbound-agent` e `mindagent-chat`) e, por consequência, fora da memória,
-- da continuidade comercial e do HubSpot. A rota pedida vai em `variables.rota_ativa`,
-- que o motor já respeita; `mindagent_chat_get_context` passa a dizer o `agente` da
-- conversa, para o motor saber que está em teste sem confiar no cliente.
-- Só administrador ativo abre conversa de teste; o banco confere.

set lock_timeout = '10s';

create or replace function public.mindagent_playground_start(
  p_auth_user_id uuid, p_token_hash text, p_rota text, p_user_agent text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'engagement', 'pessoas', 'auth'
as $$
declare
  v_session  uuid;
  v_out      jsonb;
  v_disp     uuid;
  v_conversa uuid;
  v_rota     text := nullif(btrim(coalesce(p_rota, '')), '');
  v_expira   timestamptz := now() + interval '24 hours';
begin
  if p_auth_user_id is null or not exists (select 1 from auth.users where id = p_auth_user_id) then
    raise exception using errcode = '28000', message = 'invalid_auth_user';
  end if;
  if not exists (
    select 1 from public.mind_admin_users a
     where a.user_id = p_auth_user_id and a.active and a.role = 'administrador') then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;
  if p_token_hash is null or p_token_hash !~ '^[a-f0-9]{64}$' then
    raise exception using errcode = '22023', message = 'invalid_token_hash';
  end if;
  if v_rota is null or not exists (select 1 from agentes.rotas r where r.rota = v_rota) then
    raise exception using errcode = '22023', message = 'invalid_rota';
  end if;

  -- Dispositivo próprio por conversa de teste: no app cada abertura é uma conversa
  -- nova, e aqui nunca se reaproveita a conversa real de quem testa.
  v_out := public.mind_inbound(jsonb_build_object(
    'canal', 'mindagent-web', 'agente', 'mindagent-playground',
    'user_agent', p_user_agent,
    'identificadores', jsonb_build_object(
      'auth_user_id', p_auth_user_id::text,
      'dispositivo', 'playground:' || gen_random_uuid()::text)));

  v_conversa := (v_out->>'conversa_id')::uuid;
  select dispositivo_id into v_disp from engagement.conversas where id = v_conversa;

  update engagement.conversas
     set variables = coalesce(variables, '{}'::jsonb)
                     || jsonb_build_object('teste', true, 'rota_ativa', v_rota)
   where id = v_conversa;

  insert into engagement.agent_sessions
    (dispositivo_id, mind_id, auth_user_id, token_hash, origem_identidade, confianca, expira_em)
  values (v_disp, nullif(v_out->>'pessoa_id', '')::uuid, p_auth_user_id, p_token_hash,
          'supabase_auth', 'alta', v_expira)
  returning id into v_session;

  return jsonb_build_object(
    'session_id', v_session,
    'conversation_id', v_out->'conversa_id',
    'participant_id', v_out->'pessoa_id',
    'origem_codigo', null,
    'rota', v_rota,
    'expires_at', v_expira,
    'identity_verified', true);
end
$$;

revoke all on function public.mindagent_playground_start(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.mindagent_playground_start(uuid, text, text, text) to service_role;

-- Mesma função de antes, com uma chave a mais na saída: `agente` da conversa.
create or replace function public.mindagent_chat_get_context(p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public', 'summit', 'comum', 'mind', 'engagement', 'intelligence', 'concierge'
as $function$
declare
  v_session engagement.agent_sessions%rowtype;
  v_conversation engagement.conversas%rowtype;
  v_history jsonb := '[]'::jsonb;
  v_interests jsonb := '[]'::jsonb;
  v_memories jsonb := '[]'::jsonb;
  v_profile jsonb := null;
  v_credenciamento jsonb := null;
  v_rota_ativa text := null;
begin
  select * into v_session from engagement.agent_sessions
  where id=p_session_id and auth_user_id=p_auth_user_id and token_hash=p_token_hash and expira_em>now();
  if not found then raise exception using errcode='28000', message='invalid_chat_session'; end if;

  select * into v_conversation from engagement.conversas
  where id=p_conversation_id and dispositivo_id=v_session.dispositivo_id and encerrada_em is null;
  if not found then raise exception using errcode='28000', message='invalid_chat_conversation'; end if;

  update engagement.agent_sessions set ultima_atividade=now() where id=v_session.id;
  update engagement.dispositivos set ultimo_acesso=now() where id=v_session.dispositivo_id;
  update engagement.conversas set ultima_atividade=now() where id=v_conversation.id;

  select coalesce(jsonb_agg(jsonb_build_object('role',case h.papel when 'lead' then 'user' else 'assistant' end,
                                               'content',h.conteudo) order by h.criado_em),'[]'::jsonb)
    into v_history
  from (select papel,conteudo,criado_em from engagement.mensagens
        where conversa_id=v_conversation.id and papel in ('lead','agente') and conteudo is not null
        order by criado_em desc limit 12) h;

  select coalesce(jsonb_agg(jsonb_build_object('key',i.chave,'label',i.rotulo,'confidence',i.confianca,
                                               'occurrences',i.ocorrencias) order by i.ultima_em desc),'[]'::jsonb)
    into v_interests
  from engagement.session_interests i where i.agent_session_id=v_session.id;

  if v_session.mind_id is not null then
    v_credenciamento := public.mind_credenciamento_fatos(v_session.mind_id);

    select jsonb_build_object('participant_id',p.id,'name',p.nome,'role',p.cargo,'company',p.empresa,
                              'language',p.idioma,'interests',coalesce(pc.temas_relevantes,'[]'::jsonb))
      into v_profile
    from engagement.v_pessoa p
    left join intelligence.participante_contexto pc on pc.mind_id=p.id
    where p.id=v_session.mind_id;

    select coalesce(jsonb_agg(jsonb_build_object('type',pm.tipo,'key',pm.chave,
      'value',coalesce(pm.valor->>'text',pm.valor->>'label'),'scope',pm.valor->>'scope','confidence',pm.confianca)
      order by pm.confianca desc nulls last,pm.atualizado_em desc nulls last),'[]'::jsonb)
      into v_memories
    from intelligence.participante_memoria pm
    where pm.mind_id=v_session.mind_id and pm.tipo='interesse' and pm.status='ativa'
      and (pm.valido_ate is null or pm.valido_ate>now())
      and coalesce(pm.valor->>'text',pm.valor->>'label') is not null;
  end if;

  if jsonb_typeof(v_conversation.variables)='object' then
    v_rota_ativa:=nullif(btrim(coalesce(v_conversation.variables->>'rota_ativa','')),'');
  end if;

  return jsonb_build_object('identity_verified',false,'identity_source',v_session.origem_identidade,
    'identity_confidence',v_session.confianca,'participant_profile',v_profile,
    'credenciamento',v_credenciamento,'history',v_history,
    'interests',v_interests,'memories',v_memories,'origem_codigo',v_conversation.origem_codigo,
    'rota_ativa',v_rota_ativa,'agente',v_conversation.agente,'expires_at',v_session.expira_em);
end
$function$;
