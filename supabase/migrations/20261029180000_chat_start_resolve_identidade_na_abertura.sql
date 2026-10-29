-- A IDENTIDADE CHEGAVA TARDE DEMAIS PARA VALER.
--
-- Medido em 29/10/2026. `mindagent_chat_start` chamava `mind_inbound` com dois
-- identificadores — `auth_user_id` e `dispositivo` —, e o usuário do Supabase
-- num bloco colado é ANÔNIMO: um por navegador. `mind_identidade_resolver` não
-- tinha por onde reconhecer ninguém, então criava uma pessoa nova, e a conversa
-- nascia ancorada nela.
--
-- Depois disso, `mindagent_chat_bind_identity` até recebia o e-mail e o id do
-- LearnWorlds, mas a âncora já estava posta:
--
--     v_pessoa := coalesce(v_ancora, nullif(v_res->>'pessoa_id','')::uuid);
--
-- A âncora vence, e é certo que vença — trocar o dono de uma conversa com
-- mensagem dentro é fusão, e fusão é decisão da Adriana (D5). O defeito não era
-- a precedência: era a identidade chegar depois de a âncora existir.
--
-- Prova: o aluno `6a8ccfdec7bbf584c706bead` já estava em
-- `engagement.identidades` ligado à pessoa de 33 conversas. Ainda assim cada
-- abertura criava outra pessoa, sem e-mail, com uma conversa só.
--
-- Agora os identificadores entram na ABERTURA, junto com os outros. A conversa
-- ainda não existe quando `mind_identidade_resolver` corre, logo não há âncora,
-- logo ele reconhece a pessoa pelo e-mail ou pelo id — exatamente o que a Regra
-- #1 manda: resolver pela porta única ANTES da escrita. Nenhuma pessoa é
-- fundida aqui; a certa é encontrada antes de a errada nascer.
--
-- O LIMITE: e-mail e id vêm como texto escrito na página pelo LearnWorlds.
-- Identificam, não autenticam. Decisão do Vinícius em 29/10/2026 para o piloto
-- no curso; sair do piloto pede OTP ou SSO nesta mesma porta.
create or replace function public.mindagent_chat_start(
  p_auth_user_id uuid, p_device_key text, p_user_agent text default null::text,
  p_token_hash text default null::text, p_origem_codigo text default null::text,
  p_email text default null::text, p_nome text default null::text,
  p_learnworlds_user_id text default null::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'engagement', 'pessoas', 'auth'
as $function$
declare
  v_session uuid; v_out jsonb; v_disp uuid; v_conversa uuid;
  v_origem text := nullif(btrim(coalesce(p_origem_codigo, '')), '');
  v_expira timestamptz := now() + interval '24 hours';
  v_ids jsonb;
  v_email text := lower(nullif(btrim(coalesce(p_email, '')), ''));
  v_lw text := nullif(btrim(coalesce(p_learnworlds_user_id, '')), '');
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
  -- Identificador fora de formato é descartado em silêncio, não recusado: um
  -- marcador que o LearnWorlds não trocou não pode impedir a pessoa de conversar.
  if v_email is not null and v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$' then
    v_email := null;
  end if;
  if v_lw is not null and v_lw !~ '^[A-Za-z0-9_-]{6,64}$' then
    v_lw := null;
  end if;

  v_ids := jsonb_build_object(
    'auth_user_id', p_auth_user_id::text, 'dispositivo', btrim(p_device_key));
  if v_email is not null then v_ids := v_ids || jsonb_build_object('email', v_email); end if;
  if v_lw is not null then v_ids := v_ids || jsonb_build_object('learnworlds_user_id', v_lw); end if;

  -- o core resolve conversa + identidade (auth_user e a evidencia mais forte)
  v_out := public.mind_inbound(jsonb_build_object(
    'canal','mindagent-web', 'agente','mindagent-chat',
    'user_agent', p_user_agent,
    'nome', nullif(btrim(coalesce(p_nome, '')), ''),
    'identificadores', v_ids));

  v_conversa := (v_out->>'conversa_id')::uuid;
  select dispositivo_id into v_disp from engagement.conversas where id = v_conversa;

  -- Primeira entrada manda. Turno posterior nao reescreve a porta de entrada.
  if v_origem is not null then
    update engagement.conversas
       set origem_codigo = v_origem
     where id = v_conversa and origem_codigo is null;
  end if;

  insert into engagement.agent_sessions
    (dispositivo_id, mind_id, auth_user_id, token_hash, origem_identidade,
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

-- A assinatura de 5 argumentos sai: duas versões do mesmo nome deixam a chamada
-- por nome ambígua, e a Edge chama por nome.
drop function if exists public.mindagent_chat_start(uuid, text, text, text, text);

revoke all on function public.mindagent_chat_start(uuid,text,text,text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.mindagent_chat_start(uuid,text,text,text,text,text,text,text) to service_role;
