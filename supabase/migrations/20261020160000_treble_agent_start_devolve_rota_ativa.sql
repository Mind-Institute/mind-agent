-- `treble_agent_start` passa a devolver a COMPETÊNCIA ATIVA da conversa.
--
-- GATE D7: alterar função de banco exige o ok prévio da Adriana. Esta migration é
-- PROPOSTA — escrita, provada em leitura contra produção, NÃO aplicada.
--
-- Por que ela existe: os playbooks de `institute`, `dash` e `cliente_suporte`
-- instruem o agente a usar `next_route=…` para passar a conversa a outra
-- competência. O `mindagent-chat` implementa isso há tempo: o modelo PEDE a troca,
-- o Gate CONFIRMA, e o writer grava `engagement.conversas.variables.rota_ativa` na
-- mesma transação da mensagem; no turno seguinte a rota ativa tem precedência sobre
-- a origem e sobre o Router. No WhatsApp o mecanismo não existia, então a instrução
-- dos playbooks não tinha receptor — o schema de saída do runtime sequer tem o
-- campo, e ele é `additionalProperties: false`.
--
-- Para o runtime do Treble ler a rota ativa no turno seguinte, ela precisa chegar
-- junto com o resto do estado da conversa. Hoje `treble_agent_start` já lê
-- `variables` para devolver `needs_human`; esta mudança acrescenta UMA chave ao
-- mesmo `jsonb_build_object`, lendo a mesma coluna.
--
-- É aditivo e compatível: nenhum consumidor existente perde chave, nenhum tipo muda,
-- nenhuma escrita nova acontece aqui. Quem ESCREVE `rota_ativa` continua sendo
-- `mind_turno_registrar`, pelo `p_estado` do runtime — exatamente como no App.
--
-- O corpo abaixo é o da função viva em 20/10/2026, com a única linha nova marcada.

create or replace function public.treble_agent_start(
  p_session_external_id text,
  p_contact jsonb default '{}'::jsonb,
  p_origem text default null::text,
  p_utm_token text default null::text,
  p_mensagem jsonb default null::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'engagement', 'pessoas', 'treble'
as $function$
declare
  v_in    jsonb;
  v_out   jsonb;
  v_est   jsonb;
  v_conv  engagement.conversas;
begin
  if p_session_external_id is null or length(p_session_external_id) < 3 then
    raise exception using errcode='22023', message='session_external_id invalido';
  end if;

  v_in := jsonb_build_object(
    'canal','whatsapp',
    'agente','treble-inbound-agent',
    'sessao_externa', p_session_external_id,
    'nome', p_contact->>'nome',
    'identificadores', jsonb_strip_nulls(jsonb_build_object(
      'whatsapp',      coalesce(p_contact->>'whatsapp', p_contact->>'telefone'),
      'email',         p_contact->>'email',
      'telefone_hash', p_contact->>'telefone_hash')),
    'origem', jsonb_strip_nulls(jsonb_build_object(
      'origem_codigo', p_origem, 'utm_token', p_utm_token)),
    'mensagem', p_mensagem);

  v_out := public.mind_inbound(v_in);
  select * into v_conv from engagement.conversas where id = (v_out->>'conversa_id')::uuid;

  -- particularidade REAL do canal: o cliente falou => janela de 24h reaberta
  if v_conv.telefone is not null then
    perform public.treble_status_marcar(v_conv.telefone, 'aberta', now(), v_conv.session_external_id);
  end if;

  v_est := public.mind_conversa_estado(v_conv.id);

  return v_out || v_est || jsonb_build_object(
    'conversation_id',  v_conv.id,
    'pessoa_encontrada',(v_out->>'pessoa_id') is not null,
    'participante_id',  v_out->'pessoa_id',
    -- NOVO: a competência que um handoff anterior deixou ativa nesta conversa.
    -- Só leitura. Quem grava é `mind_turno_registrar`, pelo estado do turno, e
    -- quem autoriza a troca é o Capability Gate, no runtime.
    'rota_ativa',       v_conv.variables->>'rota_ativa',
    'needs_human',      coalesce((v_conv.variables->>'needs_human')::boolean, false));
end $function$;

-- A função nasce/continua fechada: só quem chama executa (regra de 25/09).
revoke all on function public.treble_agent_start(text, jsonb, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.treble_agent_start(text, jsonb, text, text, jsonb) to service_role;
