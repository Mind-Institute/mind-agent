-- Preferência operacional e pausa do piloto: usa as conversas existentes.
-- Não cria tabelas, não migra memórias nem altera consentimentos comerciais.

CREATE OR REPLACE FUNCTION public.mind_turno_registrar(p_conversa_id uuid, p_resposta text, p_estado jsonb DEFAULT '{}'::jsonb, p_meta jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement'
AS $function$
declare
  v_msg jsonb;
  v_conv engagement.conversas%rowtype;
  v_rota text;
  v_gate jsonb;
begin
  select * into v_conv
  from engagement.conversas
  where id = p_conversa_id;

  if not found then
    raise exception using errcode = '22023', message = 'conversa_inexistente';
  end if;

  v_rota := nullif(btrim(coalesce(p_estado->>'rota_ativa', '')), '');
  if v_rota is not null then
    v_gate := public.mind_rota_capacidade(v_rota, v_conv.canal);
    if not (coalesce(v_gate->>'ok', 'false')::boolean
            and coalesce(v_gate->>'pode_executar', 'false')::boolean) then
      v_rota := null;
    end if;
  end if;

  v_msg := public.mind_mensagem_registrar(p_conversa_id, 'agente', p_resposta,
             p_meta->>'request_id', p_meta, 'agente');

  update engagement.conversas set
    audience  = coalesce(nullif(p_estado->>'audience',''), audience),
    stage     = coalesce(nullif(p_estado->>'stage',''), stage),
    variables = (case when jsonb_typeof(variables) = 'object'
                      then variables else '{}'::jsonb end)
                || jsonb_strip_nulls(jsonb_build_object(
      'intent',          nullif(p_estado->>'intent',''),
      'ticket_interest', nullif(p_estado->>'ticket_interest',''),
      'objection',       nullif(p_estado->>'objection',''),
      'needs_human',     (p_estado->>'needs_human')::boolean,
      'checkout_sent',   (coalesce((variables->>'checkout_sent')::boolean,false)
                          or coalesce((p_estado->>'checkout_sent')::boolean,false)),
      'desfecho',        nullif(p_estado->>'desfecho',''),
      'rota_ativa',      v_rota,
      'marketing_whatsapp_concedido', case when jsonb_typeof(p_estado->'marketing_whatsapp_concedido') = 'boolean' then p_estado->'marketing_whatsapp_concedido' end,
      'marketing_whatsapp_atualizado_em', case when jsonb_typeof(p_estado->'marketing_whatsapp_concedido') = 'boolean' then to_jsonb(now()) end)),
    encerrada_em = case when nullif(p_estado->>'desfecho','') is not null then now() else encerrada_em end,
    ultima_atividade = now()
  where id = p_conversa_id;

  return v_msg;
end $function$;

CREATE OR REPLACE FUNCTION public.treble_agent_start(p_session_external_id text, p_contact jsonb DEFAULT '{}'::jsonb, p_origem text DEFAULT NULL::text, p_utm_token text DEFAULT NULL::text, p_mensagem jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'engagement', 'pessoas', 'treble'
AS $function$
declare
  v_in    jsonb;
  v_out   jsonb;
  v_est   jsonb;
  v_conv  engagement.conversas;
  v_marketing boolean;
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

  -- Preferência explícita do WhatsApp, mais recente para esta identidade.
  -- Não altera consentimentos de e-mail nem interpreta uma nova pergunta como opt-in.
  select (c.variables->>'marketing_whatsapp_concedido')::boolean into v_marketing
  from engagement.conversas c
  where c.mind_id = v_conv.mind_id and c.canal = 'whatsapp'
    and jsonb_typeof(c.variables->'marketing_whatsapp_concedido') = 'boolean'
  order by (c.variables->>'marketing_whatsapp_atualizado_em')::timestamptz desc nulls last,
           c.ultima_atividade desc
  limit 1;

  return v_out || v_est || jsonb_build_object(
    'conversation_id',  v_conv.id,
    'pessoa_encontrada',(v_out->>'pessoa_id') is not null,
    'participante_id',  v_out->'pessoa_id',
    -- NOVO: a competência que um handoff anterior deixou ativa nesta conversa.
    -- Só leitura. Quem grava é `mind_turno_registrar`, pelo estado do turno, e
    -- quem autoriza a troca é o Capability Gate, no runtime.
    'rota_ativa',       v_conv.variables->>'rota_ativa',
    'marketing_whatsapp_bloqueado', v_marketing = false,
    'marketing_whatsapp_preferencia_explicita', v_marketing,
    'needs_human',      coalesce((v_conv.variables->>'needs_human')::boolean, false));
end $function$;

