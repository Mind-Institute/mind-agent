-- READ PATH — serve aos dois passos, e por isso a função é tocada uma vez só.
--
-- PASSO 5: `analise_projetar_memoria` grava em `intelligence.participante_memoria` desde
-- sempre, e NENHUM leitor canônico devolvia isso ao Agent. Ou seja: o Concierge extraía
-- cargo/objetivo/interesse e nunca reusava nada. Estender a função existente é a menor
-- mudança; não nasce um segundo reader.
--   * só `ativa` e não expirada — `proposta` e `substituida` nunca chegam ao modelo;
--   * o valor textual aceita as duas formas históricas: `valor->>'text'` e, na falta,
--     `valor->>'label'` (o writer antigo de interesses gravava `label`).
--
-- PASSO 6: `engagement.conversas.variables.rota_ativa` é a competência que está atendendo
-- agora. `origem_codigo` continua sendo a porta de entrada, imutável — são conceitos
-- diferentes e por isso convivem no mesmo retorno.
--
-- Sem ranking nem "primeiros N": medido no vivo, o máximo por pessoa é 3 memórias ativas
-- (p95=3, média 1,45). Cortar isso seria inventar um problema que não existe.

create or replace function public.mindagent_chat_get_context(
  p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','summit','comum','mind','engagement','intelligence','concierge'
as $function$
declare
  v_session engagement.agent_sessions%rowtype;
  v_conversation engagement.conversas%rowtype;
  v_history jsonb := '[]'::jsonb;
  v_interests jsonb := '[]'::jsonb;
  v_memories jsonb := '[]'::jsonb;
  v_profile jsonb := null;
  v_rota_ativa text := null;
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

    -- MEMÓRIA DURÁVEL ATIVA. Só o que o Agent pode usar como fato.
    select coalesce(jsonb_agg(jsonb_build_object(
      'type', pm.tipo,
      'key', pm.chave,
      'value', coalesce(pm.valor->>'text', pm.valor->>'label'),
      'scope', pm.valor->>'scope',
      'confidence', pm.confianca
    ) order by pm.confianca desc nulls last, pm.atualizado_em desc nulls last), '[]'::jsonb)
    into v_memories
    from intelligence.participante_memoria pm
    where pm.participante_id = v_session.participante_id
      and pm.status = 'ativa'
      and (pm.valido_ate is null or pm.valido_ate > now())
      and coalesce(pm.valor->>'text', pm.valor->>'label') is not null;
  end if;

  -- COMPETÊNCIA ATIVA DA CONVERSA. Texto simples; quem valida contra a política do canal
  -- é o Gate, no runtime. Aqui só se devolve o que foi persistido.
  if jsonb_typeof(v_conversation.variables) = 'object' then
    v_rota_ativa := nullif(btrim(coalesce(v_conversation.variables->>'rota_ativa','')), '');
  end if;

  return jsonb_build_object(
    'identity_verified', false,
    'identity_source', v_session.origem_identidade,
    'identity_confidence', v_session.confianca,
    'participant_profile', v_profile,
    'history', v_history,
    'interests', v_interests,
    'memories', v_memories,
    -- A PORTA DE ENTRADA DA CONVERSA. Autoritativa porque foi gravada uma vez, na
    -- abertura, e nao chega do cliente a cada turno.
    'origem_codigo', v_conversation.origem_codigo,
    -- QUEM ESTA ATENDENDO AGORA. Diferente da porta de entrada: muda com o handoff.
    'rota_ativa', v_rota_ativa,
    'expires_at', v_session.expira_em
  );
end;
$function$;

do $g$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mindagent_chat_get_context';
  if d !~ 'participante_memoria' then raise exception 'read path nao le memoria duravel'; end if;
  if d !~ 'pm.status = ''ativa''' then raise exception 'read path nao filtra por ativa'; end if;
  if d !~ 'valido_ate is null or pm.valido_ate > now\(\)' then raise exception 'read path nao filtra expiradas'; end if;
  if d !~ 'valor->>''label''' then raise exception 'read path nao aceita a forma historica label'; end if;
  if d !~ 'rota_ativa' then raise exception 'read path nao devolve rota_ativa'; end if;
  if d !~ 'session_interests' or d !~ 'origem_codigo' or d !~ 'v_history' then
    raise exception 'read path perdeu interesses, origem ou historico'; end if;
end $g$;
