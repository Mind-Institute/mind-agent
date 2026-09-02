-- PASSO 6 — a troca de competência é persistida pelo MESMO writer que grava a resposta.
--
-- Por que aqui e não numa RPC nova: o estado impossível que precisamos evitar é "a
-- resposta disse que encaminhou, mas a rota não mudou". Duas chamadas separadas permitem
-- exatamente isso. Dentro desta função, gravar a mensagem e mudar a competência são a
-- mesma transação — ou acontecem as duas, ou nenhuma.
--
-- O canal sai da própria conversa, não de uma constante: este writer é do App hoje, mas
-- hardcodar 'mindagent-web' criaria a segunda lista de política que o Passo 6 proíbe.
-- Quem autoriza continua sendo `mind_rota_capacidade`; aqui só se obedece.
--
-- `origem_codigo` não é tocado. Porta de entrada e competência ativa são coisas diferentes.

create or replace function public.mindagent_chat_save_message(
  p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text,
  p_role text, p_content text, p_client_message_id text, p_blocks jsonb default null::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public','engagement'
as $function$
declare
  v_sess engagement.agent_sessions%rowtype;
  v_conv engagement.conversas%rowtype;
  v_msg jsonb;
  v_rota text;
  v_gate jsonb;
begin
  select * into v_sess from engagement.agent_sessions
   where id = p_session_id and auth_user_id = p_auth_user_id
     and token_hash = p_token_hash and expira_em > now();
  if not found then raise exception using errcode='28000', message='invalid_chat_session'; end if;

  select * into v_conv from engagement.conversas c
   where c.id = p_conversation_id and c.dispositivo_id = v_sess.dispositivo_id
     and c.encerrada_em is null;
  if not found then raise exception using errcode='28000', message='invalid_chat_conversation'; end if;

  -- TROCA DE COMPETÊNCIA. Só o turno do assistant pode pedir, e só o Gate autoriza.
  if p_role = 'assistant' and jsonb_typeof(p_blocks) = 'object' then
    v_rota := nullif(btrim(coalesce(p_blocks->'state'->>'rota_ativa','')), '');

    if v_rota is not null then
      v_gate := public.mind_rota_capacidade(v_rota, v_conv.canal);

      if coalesce(v_gate->>'ok','false')::boolean
         and coalesce(v_gate->>'pode_executar','false')::boolean then
        update engagement.conversas
           set variables = coalesce(variables, '{}'::jsonb)
                           || jsonb_build_object('rota_ativa', v_rota)
         where id = v_conv.id;
      end if;
      -- Gate fechado: não persiste. A mensagem ainda é gravada, e o runtime registra em
      -- `blocks` que a troca foi pedida e não efetivada — é assim que a auditoria mostra
      -- a diferença entre pedir e conseguir.
    end if;
  end if;

  v_msg := public.mind_mensagem_registrar(p_conversation_id, p_role, p_content,
                                          p_client_message_id, p_blocks, 'mindagent-chat');
  update engagement.agent_sessions set ultima_atividade = now() where id = p_session_id;
  return v_msg;
end $function$;

do $g$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='mindagent_chat_save_message';
  if d !~ 'mind_rota_capacidade' then raise exception 'writer nao valida o Gate'; end if;
  if d !~ 'variables' then raise exception 'writer nao persiste rota_ativa'; end if;
  if d ~ '''mindagent-web''' then raise exception 'writer hardcodou o canal'; end if;
  if d !~ 'mind_mensagem_registrar' then raise exception 'writer perdeu a gravacao da mensagem'; end if;
  if d ~ 'origem_codigo' then raise exception 'writer passou a mexer em origem_codigo'; end if;
end $g$;
