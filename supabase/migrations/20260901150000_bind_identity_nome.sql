-- O nome que a URL da Yazo entrega para de morrer no caminho.
--
-- O QUE ESTAVA QUEBRADO. O front lê `?email=…&nome=…`, `chat-service.js` manda
-- `identity.email`, `identity.name` e `identity.source`, e a Edge REGISTRA os dois
-- (`identity_received: {email:true, name:true}` está gravado em `blocos`). Só que
-- `mindagent_chat_bind_identity` só aceitava `p_email` e chamava o resolvedor com
-- `p_nome = null`. Resultado medido: o e-mail vira identidade e liga a pessoa;
-- `pessoas.pessoas.primeiro_nome` fica null. O dado chegou até a porta e foi jogado
-- fora por falta de um parâmetro.
--
-- POR QUE SÓ ISTO. `mind_identidade_resolver` JÁ sabe o que fazer com nome, e sabe
-- fazer do jeito conservador que queremos:
--   - pessoa nova  -> `insert ... (primeiro_nome, sobrenome, ...)` a partir do nome;
--   - pessoa que já existe -> `update ... set primeiro_nome = ... where primeiro_nome is null`.
-- Ou seja: preenche buraco, nunca sobrescreve nome canônico existente. Uma URL com
-- outro valor não reescreve quem a pessoa é. Nada aqui muda essa regra — nem a de
-- conflito, nem a de merge. Isto é encanamento: o nome passa a atravessar o fluxo
-- que já existia.
--
-- NENHUM RESOLVEDOR NOVO. NENHUMA TABELA NOVA.
--
-- COMPATIBILIDADE COM A VERSÃO VIVA. `p_nome` entra com DEFAULT e a assinatura de 5
-- argumentos é removida: o PostgREST resolve por nomes e aceita omitir parâmetro com
-- default, então o `mindagent-chat` publicado hoje — que manda 5 — continua chamando
-- esta função e continua se comportando exatamente como antes (nome null). Isso
-- importa porque migration aplica no merge e Edge Function não: as duas versões
-- convivem na janela entre uma coisa e outra.

drop function if exists public.mindagent_chat_bind_identity(uuid, uuid, uuid, text, text);

create or replace function public.mindagent_chat_bind_identity(
  p_auth_user_id  uuid,
  p_session_id    uuid,
  p_conversation_id uuid,
  p_token_hash    text,
  p_email         text,
  p_nome          text default null
) returns jsonb
language plpgsql security definer
set search_path to 'public', 'engagement', 'pessoas'
as $function$
declare v_sess engagement.agent_sessions%rowtype; v_res jsonb; v_pessoa uuid; v_ancora uuid;
begin
  select * into v_sess from engagement.agent_sessions
   where id = p_session_id and auth_user_id = p_auth_user_id
     and token_hash = p_token_hash and expira_em > now() for update;
  if not found then raise exception using errcode='28000', message='invalid_chat_session'; end if;

  select participante_id into v_ancora from engagement.conversas
   where id = p_conversation_id and dispositivo_id = v_sess.dispositivo_id;

  v_res := public.mind_identidade_resolver(
    jsonb_build_object('email', p_email, 'auth_user_id', p_auth_user_id::text),
    nullif(btrim(coalesce(p_nome, '')), ''), 'mindagent-web', v_ancora);

  v_pessoa := coalesce(v_ancora, nullif(v_res->>'pessoa_id','')::uuid);
  if v_pessoa is not null then
    update engagement.agent_sessions set participante_id = v_pessoa, ultima_atividade = now()
     where id = v_sess.id;
    update engagement.conversas set participante_id = coalesce(participante_id, v_pessoa),
           ultima_atividade = now()
     where id = p_conversation_id and dispositivo_id = v_sess.dispositivo_id;
    update engagement.mensagens set participante_id = v_pessoa
     where conversa_id = p_conversation_id and participante_id is null;
  end if;

  return v_res || jsonb_build_object(
    'pessoa_id', v_pessoa,
    'found', v_pessoa is not null,
    'conflict', (v_res->'conflito') is not null and v_res->>'conflito' <> 'null',
    'profile', coalesce((public.mind_conversa_estado(p_conversation_id))->'perfil','{}'::jsonb));
end $function$;

comment on function public.mindagent_chat_bind_identity(uuid, uuid, uuid, text, text, text) is
  'Liga a sessao do app a pessoa canonica. Repassa email E nome para mind_identidade_resolver, que preenche o nome quando ele falta e nunca sobrescreve nome existente. Nao decide identidade por conta propria.';

revoke all on function public.mindagent_chat_bind_identity(uuid, uuid, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.mindagent_chat_bind_identity(uuid, uuid, uuid, text, text, text)
  to service_role;
