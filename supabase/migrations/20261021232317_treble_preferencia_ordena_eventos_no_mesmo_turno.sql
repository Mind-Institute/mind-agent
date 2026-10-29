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
      'marketing_whatsapp_atualizado_em', case when jsonb_typeof(p_estado->'marketing_whatsapp_concedido') = 'boolean' then to_jsonb(clock_timestamp()) end)),
    encerrada_em = case when nullif(p_estado->>'desfecho','') is not null then now() else encerrada_em end,
    ultima_atividade = now()
  where id = p_conversa_id;

  return v_msg;
end $function$;

