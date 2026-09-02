-- ENTRADA PELO APP OFICIAL TEM ROTA CONHECIDA. O Router existe para decidir; quando a
-- competencia ja veio decidida pela porta de entrada, perguntar e desperdicio -- e, pior,
-- e uma chance de errar: medido em producao, "Oi" e "Ola" no App caiam em
-- `cliente_suporte` porque o Router nao tinha como saber de onde a pessoa veio.
--
-- A CASA JA EXISTE: `engagement.conversas.origem_codigo`, hoje em uso pelo WhatsApp
-- (`summit_info_evento`, `summit_garantir_ingresso`, `summit_exit_popup`,
-- `delegacoes_condicoes_wpp`). O App passa a usar o mesmo campo, com o codigo
-- `mind_summit_app`. Nenhuma tabela nova, nenhum campo novo.
--
-- QUEM ESCREVE. `mind_inbound` apenas LE `origem_codigo` (devolve `conv.origem_codigo`);
-- quem grava, no WhatsApp, e a ingestao. Para o App, quem grava e o
-- `mindagent_chat_start`, logo depois de o core abrir a conversa.
--
-- ESCRITA UNICA, DE PROPOSITO. `where origem_codigo is null` faz a origem valer o que a
-- PRIMEIRA entrada disse. Uma origem que pudesse ser reescrita a cada turno nao seria
-- autoritativa: bastaria um cliente mandar outra coisa depois para mudar a rota da
-- conversa. Assim, a porta de entrada e um fato da conversa, nao um parametro do turno.

create or replace function public.mindagent_chat_start(
  p_auth_user_id uuid,
  p_device_key text,
  p_user_agent text default null::text,
  p_token_hash text default null::text,
  p_origem_codigo text default null::text
) returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'engagement', 'pessoas', 'auth'
as $function$
declare
  v_session uuid; v_out jsonb; v_disp uuid; v_conversa uuid;
  v_origem text := nullif(btrim(coalesce(p_origem_codigo, '')), '');
  v_expira timestamptz := now() + interval '24 hours';
begin
  if p_auth_user_id is null or not exists (select 1 from auth.users where id = p_auth_user_id) then
    raise exception using errcode='28000', message='invalid_auth_user';
  end if;
  if p_device_key is null or length(btrim(p_device_key)) < 8 or length(p_device_key) > 160 then
    raise exception using errcode='22023', message='invalid_device_key';
  end if;
  if p_token_hash is null or p_token_hash !~ '^[a-f0-9]{64}$' then
    raise exception using errcode='22023', message='invalid_token_hash';
  end if;
  -- Codigo de origem e identificador, nao texto livre.
  if v_origem is not null and v_origem !~ '^[a-z][a-z0-9_]{1,59}$' then
    raise exception using errcode='22023', message='invalid_origem_codigo';
  end if;

  -- o core resolve conversa + identidade (auth_user e a evidencia mais forte)
  v_out := public.mind_inbound(jsonb_build_object(
    'canal','mindagent-web', 'agente','mindagent-chat',
    'user_agent', p_user_agent,
    'identificadores', jsonb_build_object(
      'auth_user_id', p_auth_user_id::text, 'dispositivo', btrim(p_device_key))));

  v_conversa := (v_out->>'conversa_id')::uuid;
  select dispositivo_id into v_disp from engagement.conversas where id = v_conversa;

  -- Primeira entrada manda. Turno posterior nao reescreve a porta de entrada.
  if v_origem is not null then
    update engagement.conversas
       set origem_codigo = v_origem
     where id = v_conversa and origem_codigo is null;
  end if;

  insert into engagement.agent_sessions
    (dispositivo_id, participante_id, auth_user_id, token_hash, origem_identidade,
     confianca, expira_em)
  values (v_disp, nullif(v_out->>'pessoa_id','')::uuid, p_auth_user_id, p_token_hash,
          'supabase_auth', 'alta', v_expira)
  returning id into v_session;

  return jsonb_build_object(
    'session_id', v_session,
    'conversation_id', v_out->'conversa_id',
    'participant_id',  v_out->'pessoa_id',
    'origem_codigo', (select origem_codigo from engagement.conversas where id = v_conversa),
    'expires_at', v_expira,
    'identity_verified', true);
end $function$;

drop function if exists public.mindagent_chat_start(uuid, text, text, text);

revoke all on function public.mindagent_chat_start(uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.mindagent_chat_start(uuid, text, text, text, text) to service_role;

-- O runtime precisa LER a origem em todo turno, nao so no primeiro. `get_context` ja
-- carrega a conversa inteira; devolver mais um campo dela e uma linha.
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
  v_profile jsonb := null;
begin
  select * into v_session
  from engagement.agent_sessions
  where id = p_session_id
    and auth_user_id = p_auth_user_id
    and token_hash = p_token_hash
    and expira_em > now();

  if not found then
    raise exception using errcode = '28000', message = 'invalid_chat_session';
  end if;

  select * into v_conversation
  from engagement.conversas
  where id = p_conversation_id
    and dispositivo_id = v_session.dispositivo_id
    and encerrada_em is null;

  if not found then
    raise exception using errcode = '28000', message = 'invalid_chat_conversation';
  end if;

  update engagement.agent_sessions set ultima_atividade = now() where id = v_session.id;
  update engagement.dispositivos set ultimo_acesso = now() where id = v_session.dispositivo_id;
  update engagement.conversas set ultima_atividade = now() where id = v_conversation.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'role', case h.papel when 'lead' then 'user' else 'assistant' end,
    'content', h.conteudo
  ) order by h.criado_em), '[]'::jsonb)
  into v_history
  from (
    select papel, conteudo, criado_em
    from engagement.mensagens
    where conversa_id = v_conversation.id
      and papel in ('lead', 'agente')
      and conteudo is not null
    order by criado_em desc
    limit 12
  ) h;

  select coalesce(jsonb_agg(jsonb_build_object(
    'key', i.chave,
    'label', i.rotulo,
    'confidence', i.confianca,
    'occurrences', i.ocorrencias
  ) order by i.ultima_em desc), '[]'::jsonb)
  into v_interests
  from engagement.session_interests i
  where i.agent_session_id = v_session.id;

  if v_session.participante_id is not null then
    select jsonb_build_object(
      'participant_id', p.id,
      'name', p.nome,
      'role', p.cargo,
      'company', p.empresa,
      'language', p.idioma,
      'interests', coalesce(pc.temas_relevantes, '[]'::jsonb)
    )
    into v_profile
    from engagement.v_pessoa p
    left join intelligence.participante_contexto pc
      on pc.participante_id = p.id
    where p.id = v_session.participante_id;
  end if;

  return jsonb_build_object(
    'identity_verified', false,
    'identity_source', v_session.origem_identidade,
    'identity_confidence', v_session.confianca,
    'participant_profile', v_profile,
    'history', v_history,
    'interests', v_interests,
    -- A PORTA DE ENTRADA DA CONVERSA. Autoritativa porque foi gravada uma vez, na
    -- abertura, e nao chega do cliente a cada turno.
    'origem_codigo', v_conversation.origem_codigo,
    'expires_at', v_session.expira_em
  );
end;
$function$;

do $$
declare v_c uuid;
begin
  select id into v_c from engagement.conversas where canal='mindagent-web' order by iniciada_em desc limit 1;
  if v_c is null then raise notice 'sem conversa do app para conferir'; return; end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema='engagement' and table_name='conversas' and column_name='origem_codigo') then
    raise exception 'engagement.conversas.origem_codigo sumiu';
  end if;
end $$;
