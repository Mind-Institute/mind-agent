-- MIA no LearnWorlds: a pessoa logada na escola chega identificada (Adriana, 22/10/2026).
--
-- O bloco da MIA colado no LearnWorlds manda o e-mail e o ID de quem está logado
-- ({{USER.EMAIL}}, {{USER.ID}}). Confiar no LearnWorlds foi decisão dela. O ID do
-- LearnWorlds passa a ir junto do e-mail para a porta única (`mind_identidade_resolver`,
-- D5), que já conhece `learnworlds_user_id` e o grava em `engagement.identidades`.
-- Na primeira conversa a pessoa é achada pelo e-mail (ou criada); dali em diante também
-- pelo ID do LearnWorlds.
--
-- Assinatura nova, de 7 parâmetros e sem padrão. A de 6 continua e só repassa: a
-- `mindagent-chat` v49 no ar a chama até a próxima versão subir, e o PostgREST escolhe
-- pelos nomes dos parâmetros. Corpo um só.

set lock_timeout = '10s';

create or replace function public.mindagent_chat_bind_identity(
  p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text,
  p_email text, p_nome text, p_learnworlds_user_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'engagement', 'pessoas'
as $function$
declare v_sess engagement.agent_sessions%rowtype; v_res jsonb; v_pessoa uuid; v_ancora uuid;
  v_ids jsonb;
begin
  select * into v_sess from engagement.agent_sessions
   where id = p_session_id and auth_user_id = p_auth_user_id
     and token_hash = p_token_hash and expira_em > now() for update;
  if not found then raise exception using errcode='28000', message='invalid_chat_session'; end if;

  select mind_id into v_ancora from engagement.conversas
   where id = p_conversation_id and dispositivo_id = v_sess.dispositivo_id;

  v_ids := jsonb_build_object('email', p_email, 'auth_user_id', p_auth_user_id::text);
  if nullif(btrim(coalesce(p_learnworlds_user_id, '')), '') is not null then
    v_ids := v_ids || jsonb_build_object('learnworlds_user_id', btrim(p_learnworlds_user_id));
  end if;

  v_res := public.mind_identidade_resolver(
    v_ids, nullif(btrim(coalesce(p_nome, '')), ''), 'mindagent-web', v_ancora);

  v_pessoa := coalesce(v_ancora, nullif(v_res->>'pessoa_id','')::uuid);
  if v_pessoa is not null then
    update engagement.agent_sessions set mind_id = v_pessoa, ultima_atividade = now()
     where id = v_sess.id;
    update engagement.conversas set mind_id = coalesce(mind_id, v_pessoa),
           ultima_atividade = now()
     where id = p_conversation_id and dispositivo_id = v_sess.dispositivo_id;
    update engagement.mensagens set mind_id = v_pessoa
     where conversa_id = p_conversation_id and mind_id is null;
  end if;

  return v_res || jsonb_build_object(
    'pessoa_id', v_pessoa,
    'found', v_pessoa is not null,
    'conflict', (v_res->'conflito') is not null and v_res->>'conflito' <> 'null',
    'profile', coalesce((public.mind_conversa_estado(p_conversation_id))->'perfil','{}'::jsonb));
end $function$;

revoke all on function public.mindagent_chat_bind_identity(uuid, uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.mindagent_chat_bind_identity(uuid, uuid, uuid, text, text, text, text)
  to service_role;

-- A de 6 parâmetros (Yazo, app do Summit) passa a repassar, sem ID do LearnWorlds.
create or replace function public.mindagent_chat_bind_identity(
  p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text,
  p_email text, p_nome text default null)
returns jsonb
language sql
security definer
set search_path to 'public', 'engagement', 'pessoas'
as $function$
  select public.mindagent_chat_bind_identity(
    p_auth_user_id, p_session_id, p_conversation_id, p_token_hash, p_email, p_nome, null::text);
$function$;
