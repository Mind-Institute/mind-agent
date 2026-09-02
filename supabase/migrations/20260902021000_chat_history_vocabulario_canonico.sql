-- O historico da conversa existia no contrato e vinha SEMPRE vazio.
--
-- `mindagent_chat_get_context` devolve `history`, e o filtro era
-- `papel in ('user','assistant')`. Só que o vocabulario canonico gravado em
-- `engagement.mensagens` e `lead` / `agente`: quem escreve
-- (`mindagent_chat_save_message`) traduz `user` -> `lead` e `assistant` -> `agente`,
-- e o leitor ficou filtrando pelos nomes de ANTES da traducao. Zero linhas, sempre.
--
-- Ninguem percebeu porque ninguem consumia: a Edge buscava `history` e descartava.
-- Medido no runtime real: perguntado "Por quê?" logo depois de uma recomendacao, o
-- Concierge respondeu "Nao entendi o suficiente para responder ao 'por quê?'". Para um
-- concierge de conversa, isso quebra toda pergunta de seguimento.
--
-- A CORRECAO E O FILTRO. `lead`/`agente` na leitura, traduzidos de volta para
-- `user`/`assistant` na saida — porque o consumidor e a API de chat do modelo, e esse e
-- o vocabulario dela. A traducao fica num lugar so, do mesmo jeito que na escrita.
-- Nada mais muda: mesma janela de 12 mensagens, mesma ordem, mesmo contrato.

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
    -- lido no vocabulario canonico do banco, devolvido no vocabulario do modelo
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
    'expires_at', v_session.expira_em
  );
end;
$function$;

-- GUARDA. Uma conversa que ja tem mensagens tem que devolver historico.
do $$
declare v_conv uuid; v_sess engagement.agent_sessions%rowtype; n int; papeis text;
begin
  select c.id into v_conv
  from engagement.conversas c
  where c.canal = 'mindagent-web'
    and c.encerrada_em is null
    and (select count(*) from engagement.mensagens m
          where m.conversa_id = c.id and m.papel in ('lead','agente')) >= 2
  order by c.iniciada_em desc limit 1;

  if v_conv is null then
    raise notice 'sem conversa com historico para conferir';
    return;
  end if;

  select s.* into v_sess from engagement.agent_sessions s
   join engagement.conversas c on c.dispositivo_id = s.dispositivo_id
   where c.id = v_conv and s.expira_em > now()
   order by s.ultima_atividade desc limit 1;

  if v_sess.id is null then
    raise notice 'sem sessao viva para conferir';
    return;
  end if;

  select jsonb_array_length(x->'history'),
         (select string_agg(distinct e->>'role', ',') from jsonb_array_elements(x->'history') e)
    into n, papeis
  from (select public.mindagent_chat_get_context(
          v_sess.auth_user_id, v_sess.id, v_conv, v_sess.token_hash) as x) t;

  if n = 0 then
    raise exception 'history continua vazio numa conversa com mensagens';
  end if;
  if papeis !~ 'user' then
    raise exception 'history nao traduziu lead->user: papeis=%', papeis;
  end if;
end $$;
