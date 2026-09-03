-- Um clique pode acontecer antes de o analisador assíncrono visitar a conversa.
-- Nesse caso o abandono já é um fato comercial suficiente para criar o item do
-- inbox. A análise abaixo é determinística, identificada pelo próprio analisador
-- e não finge ter inferido objeção além do que o clique comprova.

begin;

create or replace function public.mind_checkout_abandonment_refresh()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare v_count integer;
begin
  insert into intelligence.analise_conversa as a (
    conversa_id,participante_id,analisador,funcao,vertical,dados,modelo,prompt_versao,
    conversa_atualizada_ate,analisado_em,criado_em,atualizado_em
  )
  select x.conversation_id,x.participante_id,'checkout_abandonment_v1','comercial',
    coalesce(nullif(e.dados->>'rota',''),'summit_b2c'),
    jsonb_build_object(
      'motion',coalesce(nullif(e.dados->>'rota',''),'summit_b2c'),
      'purchase_intent','very_high',
      'primary_barrier','checkout_abandonment',
      'continuation_status','silence',
      'conversation_summary','Abriu o checkout oficial e o pagamento não foi confirmado após 12 horas.',
      'next_best_move','Retomar o checkout sem reabrir uma decisão já tomada.',
      'followup_anchor','checkout aberto e pagamento ainda não confirmado',
      'response_target','Concluir a compra ou informar se surgiu algum impedimento.',
      'evidence',jsonb_build_object('type','checkout_click','event_id',x.event_id,'clicked_at',x.last_clicked_at)
    ),null,1,x.last_clicked_at,now(),now(),now()
  from intelligence.v_checkout_abandonment x
  join engagement.agente_eventos e on e.id=x.event_id
  where x.abandonment_state<>'monitoring'
  on conflict (conversa_id,analisador) do update set
    participante_id=excluded.participante_id,vertical=excluded.vertical,dados=excluded.dados,
    conversa_atualizada_ate=excluded.conversa_atualizada_ate,
    analisado_em=excluded.analisado_em,atualizado_em=excluded.atualizado_em
  where a.conversa_atualizada_ate is distinct from excluded.conversa_atualizada_ate
     or a.dados is distinct from excluded.dados;

  -- Materializa também as conversas que ainda não tinham passado pelo
  -- analisador geral. O dispatcher continua desligado e a fila continua vazia.
  perform public.mind_recovery_refresh(10000);

  with latest as materialized (
    select distinct on (a.conversation_id) a.*
    from intelligence.v_checkout_abandonment a
    where a.abandonment_state<>'monitoring'
    order by a.conversation_id,a.last_clicked_at desc,a.event_id
  ), updated as (
    update intelligence.recovery_inbox r set
      checkout_event_id=a.event_id,checkout_clicked_at=a.last_clicked_at,
      purchase_status='not_purchased',
      heat='very_hot',objection='checkout_abandonment',objection_group='checkout_abandonment',
      recommended_action='retomar_checkout_sem_reabrir_a_decisao',
      followup_anchor='checkout aberto e pagamento ainda não confirmado',
      inbox_state=case when a.abandonment_state='needs_hsm' then 'needs_hsm'
                       when a.channel in ('mindagent-web','app') then 'app_inbox'
                       else 'freeform_ready' end,
      next_send_at=case when a.channel='whatsapp' then public.mind_recovery_delivery_slot(
        a.abandonment_due_at,a.whatsapp_window_expires_at,'whatsapp') else greatest(a.abandonment_due_at,now()) end,
      draft_status=case when r.checkout_event_id is distinct from a.event_id then 'stale' else r.draft_status end,
      refreshed_at=now(),updated_at=now()
    from latest a where r.conversation_id=a.conversation_id
      and r.inbox_state not in ('excluded_purchased','blocked_optout','blocked_human_owned')
    returning 1
  ) select count(*) into v_count from updated;

  return jsonb_build_object('ok',true,'abandonments_marked',v_count,'dispatcher_enabled',false);
end
$function$;

revoke all on function public.mind_checkout_abandonment_refresh() from public,anon,authenticated;
grant execute on function public.mind_checkout_abandonment_refresh() to service_role;

commit;
