-- ============================================================================
-- HISTÓRICO DE CONVERSAS DA MIA — o aluno sai, volta e continua de onde parou
-- ============================================================================
--
-- O DEFEITO. Hoje o aluno que fecha a página e volta encontra a MIA do zero.
-- São três camadas somadas, e esta migration trata a do banco:
--
--   1. a posse da conversa é do APARELHO, não da pessoa. `get_context`,
--      `save_message` e `bind_identity` todos casam por
--      `conversas.dispositivo_id = agent_sessions.dispositivo_id`. Outro
--      navegador é outro `dispositivo`, logo outra conversa;
--   2. só existe uma vaga de conversa no bloco, e nenhuma forma de listar as
--      outras — o banco nunca foi perguntado "quais são as conversas desta
--      pessoa?";
--   3. o histórico que `get_context` devolve são as ÚLTIMAS 12 mensagens, e
--      existe para alimentar o modelo. Não serve para redesenhar a tela.
--
-- O QUE ESTA MIGRATION FAZ, e o que ela deliberadamente NÃO faz. O caminho do
-- turno continua exatamente como está, casando por aparelho: afrouxar aquela
-- checagem mexeria na porta por onde passa toda mensagem. Em vez disso entram
-- duas funções novas que perguntam pela PESSOA, e uma delas ADOTA a conversa
-- para o aparelho atual quando o dono a abre. Depois da adoção, tudo o que
-- vem depois funciona sem saber que algo mudou.
--
-- QUEM É O DONO, e o limite disto. A pessoa da sessão (`agent_sessions.mind_id`)
-- é resolvida a partir do que o LearnWorlds escreve na página — e-mail e id do
-- aluno — que chegam como TEXTO, não como prova. Quem souber o par de outra
-- pessoa consegue a sessão dela e lê as conversas dela. Isso identifica, não
-- autentica, e foi decisão do Vinícius em 29/10/2026 liberar assim mesmo para
-- o piloto no curso. O dia em que isto sair do piloto, a porta de entrada tem
-- de virar OTP ou SSO — e nada aqui muda por causa disso: o que muda é só como
-- `agent_sessions.mind_id` passa a ser estabelecido.
--
-- O TÍTULO não ganha coluna. `conversas.variables` é jsonb e já guarda
-- `rota_ativa` pelo mesmo caminho; o título entra como mais uma chave, escrita
-- uma única vez, no primeiro turno em que o modelo o devolver.

-- ---------------------------------------------------------------- 1. TÍTULO
-- O writer já recebia `blocks.state` e lia `rota_ativa` dali. O título segue a
-- mesma estrada em vez de abrir outra: nenhuma chamada nova, nenhuma ida a
-- mais ao banco, e a gravação acontece na mesma transação da mensagem.
--
-- Escreve UMA VEZ. O `where` repete a condição em vez de confiar no que foi
-- lido no começo da função: entre a leitura e a escrita cabe outro turno da
-- mesma conversa, e um título que se reescreve a cada mensagem seria pior que
-- não ter título — a lista mudaria de nome debaixo do aluno.
create or replace function public.mindagent_chat_save_message(
  p_auth_user_id uuid, p_session_id uuid, p_conversation_id uuid, p_token_hash text,
  p_role text, p_content text, p_client_message_id text, p_blocks jsonb default null::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'engagement'
as $function$
declare
  v_sess engagement.agent_sessions%rowtype;
  v_conv engagement.conversas%rowtype;
  v_msg jsonb;
  v_rota text;
  v_titulo text;
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

    -- TÍTULO DA CONVERSA, para a pessoa reconhecer a conversa numa lista.
    v_titulo := nullif(btrim(coalesce(p_blocks->'state'->>'titulo','')), '');
    if v_titulo is not null then
      update engagement.conversas
         set variables = coalesce(variables, '{}'::jsonb)
                         || jsonb_build_object('titulo', left(v_titulo, 80))
       where id = v_conv.id
         and coalesce(variables->>'titulo', '') = '';
    end if;
  end if;

  v_msg := public.mind_mensagem_registrar(p_conversation_id, p_role, p_content,
                                          p_client_message_id, p_blocks, 'mindagent-chat');
  update engagement.agent_sessions set ultima_atividade = now() where id = p_session_id;
  return v_msg;
end $function$;

-- ------------------------------------------------------------- 2. A LISTA
-- "Quais são as minhas conversas?" — pergunta que o banco nunca tinha recebido.
--
-- Casa por PESSOA, que é o ponto: a lista tem de atravessar aparelhos, senão
-- ela responde a mesma coisa que o localStorage já respondia.
--
-- Sessão sem pessoa resolvida devolve lista VAZIA, nunca erro: é o estado
-- normal de quem abriu o bloco num lugar onde o LearnWorlds não trocou o
-- e-mail. Ali a conversa do turno funciona; só não há o que listar.
--
-- Conversa sem mensagem do aluno não entra. Toda abertura de página cria uma
-- conversa (`mind_conversa_resolver`: "canal sem id de sessao externa: cada
-- entrada abre conversa nova"), e sem este filtro a lista encheria de linhas
-- vazias que o aluno nunca escreveu.
create or replace function public.mindagent_chat_conversas(
  p_auth_user_id uuid, p_session_id uuid, p_token_hash text, p_limite int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'engagement'
as $function$
declare
  v_sess engagement.agent_sessions%rowtype;
  v_itens jsonb;
  v_lim int := least(100, greatest(1, coalesce(p_limite, 30)));
begin
  select * into v_sess from engagement.agent_sessions
   where id = p_session_id and auth_user_id = p_auth_user_id
     and token_hash = p_token_hash and expira_em > now();
  if not found then raise exception using errcode='28000', message='invalid_chat_session'; end if;

  if v_sess.mind_id is null then
    return jsonb_build_object('ok', true, 'conversas', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.ultima_atividade desc), '[]'::jsonb)
    into v_itens
  from (
    select c.id,
           nullif(btrim(coalesce(c.variables->>'titulo', '')), '') as titulo,
           coalesce(c.ultima_atividade, c.iniciada_em) as ultima_atividade,
           -- A primeira fala do aluno serve de nome quando o título ainda não
           -- existe: conversa velha, ou turno que falhou antes de nomear.
           (select left(btrim(m.conteudo), 70) from engagement.mensagens m
             where m.conversa_id = c.id and m.papel = 'lead' and m.conteudo is not null
             order by m.criado_em limit 1) as inicio,
           (select count(*) from engagement.mensagens m
             where m.conversa_id = c.id and m.papel in ('lead','agente')) as mensagens
      from engagement.conversas c
     where c.mind_id = v_sess.mind_id
       and c.canal = 'mindagent-web'
       and c.encerrada_em is null
       and exists (select 1 from engagement.mensagens m
                    where m.conversa_id = c.id and m.papel = 'lead')
     order by coalesce(c.ultima_atividade, c.iniciada_em) desc
     limit v_lim
  ) t;

  return jsonb_build_object('ok', true, 'conversas', v_itens);
end $function$;

-- ------------------------------------------------------------- 3. ABRIR
-- Abrir uma conversa da lista faz duas coisas, e a segunda é a que importa.
--
-- Devolve as mensagens para a tela redesenhar o que já foi dito — todas, não
-- as 12 do modelo.
--
-- E ADOTA a conversa para o aparelho de agora. É isto que deixa o resto do
-- sistema intocado: `get_context` e `save_message` continuam exigindo que a
-- conversa seja do aparelho da sessão, e continuam certos, porque a conversa
-- passou a ser. Sem a adoção, abrir no celular uma conversa começada no
-- computador mostraria o histórico e falharia na primeira mensagem nova.
--
-- A dona é a pessoa da sessão. Conversa de outra pessoa não abre — e a
-- mensagem de erro não distingue "não existe" de "não é sua", porque a
-- diferença entre as duas já é informação sobre a conversa alheia.
create or replace function public.mindagent_chat_abrir(
  p_auth_user_id uuid, p_session_id uuid, p_token_hash text, p_conversa_id uuid,
  p_limite int default 200)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'engagement'
as $function$
declare
  v_sess engagement.agent_sessions%rowtype;
  v_conv engagement.conversas%rowtype;
  v_msgs jsonb;
  v_lim int := least(500, greatest(1, coalesce(p_limite, 200)));
begin
  select * into v_sess from engagement.agent_sessions
   where id = p_session_id and auth_user_id = p_auth_user_id
     and token_hash = p_token_hash and expira_em > now();
  if not found then raise exception using errcode='28000', message='invalid_chat_session'; end if;

  if v_sess.mind_id is null then
    raise exception using errcode='28000', message='invalid_chat_conversation';
  end if;

  select * into v_conv from engagement.conversas c
   where c.id = p_conversa_id and c.mind_id = v_sess.mind_id
     and c.encerrada_em is null;
  if not found then raise exception using errcode='28000', message='invalid_chat_conversation'; end if;

  -- A ADOÇÃO. Daqui em diante esta conversa é deste aparelho.
  update engagement.conversas
     set dispositivo_id = v_sess.dispositivo_id, ultima_atividade = now()
   where id = v_conv.id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'papel', case h.papel when 'lead' then 'user' else 'assistant' end,
           'conteudo', h.conteudo,
           'criado_em', h.criado_em) order by h.criado_em), '[]'::jsonb)
    into v_msgs
  from (select papel, conteudo, criado_em
          from engagement.mensagens
         where conversa_id = v_conv.id and papel in ('lead','agente') and conteudo is not null
         order by criado_em desc
         limit v_lim) h;

  return jsonb_build_object(
    'ok', true,
    'conversation_id', v_conv.id,
    'titulo', nullif(btrim(coalesce(v_conv.variables->>'titulo','')), ''),
    'mensagens', v_msgs);
end $function$;

-- ------------------------------------------------------- PERMISSÕES
-- Função nasce fechada (25/09). As três são RPC interna, chamadas pela Edge
-- com a chave de serviço: ninguém do navegador fala com elas direto.
revoke all on function public.mindagent_chat_save_message(uuid,uuid,uuid,text,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function public.mindagent_chat_conversas(uuid,uuid,text,int) from public, anon, authenticated;
revoke all on function public.mindagent_chat_abrir(uuid,uuid,text,uuid,int) from public, anon, authenticated;

grant execute on function public.mindagent_chat_save_message(uuid,uuid,uuid,text,text,text,text,jsonb) to service_role;
grant execute on function public.mindagent_chat_conversas(uuid,uuid,text,int) to service_role;
grant execute on function public.mindagent_chat_abrir(uuid,uuid,text,uuid,int) to service_role;
