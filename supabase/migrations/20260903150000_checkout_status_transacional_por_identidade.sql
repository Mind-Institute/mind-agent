-- Para abandono de checkout, a ausência de compra só é conclusiva quando o
-- espelho Eduzz já sincronizou depois do clique e a pessoa tem identidade
-- canônica suficiente para a comparação. Até lá o estado continua unknown.

begin;

create or replace function public.mind_checkout_event_purchase_status(p_event_id uuid)
returns text
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_conversation uuid;
  v_participant uuid;
  v_clicked_at timestamptz;
  v_email text;
  v_phone text;
  v_last_sync timestamptz;
  v_sync_ok boolean;
begin
  select e.conversa_id,e.participante_id,min(c.clicked_at)
    into v_conversation,v_participant,v_clicked_at
  from engagement.agente_eventos e
  join engagement.checkout_clicks c on c.event_id=e.id
  where e.id=p_event_id and e.tipo='checkout_link_enviado'
  group by e.conversa_id,e.participante_id;
  if v_conversation is null then return 'unknown'; end if;

  if exists(select 1 from intelligence.v_conversoes_agente v where v.event_id=p_event_id and v.paid)
     or public.mind_recovery_purchase_status(v_conversation)='purchased' then
    return 'purchased';
  end if;

  select lower(nullif(btrim(p.email),'')),right(regexp_replace(coalesce(p.whatsapp,''),'\D','','g'),11)
    into v_email,v_phone from pessoas.pessoas p where p.id=v_participant;
  if v_email is null and length(coalesce(v_phone,''))<10 then return 'unknown'; end if;

  -- A conclusão da varredura completa é a evidência de ausência. O maior
  -- `sincronizado_em` de uma venda isolada não prova que as outras vendas já
  -- foram lidas.
  select e.concluido_em,
    e.status='ok' and e.registros_lidos=e.total_na_origem
      and e.registros_gravados=e.total_na_origem
    into v_last_sync,v_sync_ok
  from public.espelho_estado e
  where e.fonte='vendas' and e.destino='eduzz.vendas';
  if not coalesce(v_sync_ok,false) or v_last_sync is null or v_clicked_at is null
     or v_last_sync<v_clicked_at then return 'unknown'; end if;

  if exists (
    select 1 from eduzz.vendas v
    where lower(coalesce(v.status,'')) in ('paga','paid','aprovada','approved')
      and (
        (v_email is not null and lower(btrim(coalesce(v.cliente_email,'')))=v_email)
        or (length(coalesce(v_phone,''))>=10
          and right(regexp_replace(coalesce(v.cliente_telefone_norm,v.cliente_fones,''),'\D','','g'),11)=v_phone)
      )
  ) then return 'purchased'; end if;
  return 'not_purchased';
end
$function$;

create or replace view intelligence.v_checkout_abandonment
with (security_invoker=true)
as
with click_summary as (
  select e.id event_id,e.conversa_id conversation_id,e.participante_id,
    e.dados->>'canal' channel,e.dados->>'agente' agent_id,e.dados->>'motivo' checkout_reason,
    min(c.clicked_at) first_clicked_at,max(c.clicked_at) last_clicked_at,count(*) click_count
  from engagement.agente_eventos e join engagement.checkout_clicks c on c.event_id=e.id
  where e.tipo='checkout_link_enviado'
  group by e.id,e.conversa_id,e.participante_id,e.dados
), last_lead as (
  select m.conversa_id,max(m.criado_em) last_lead_at
  from engagement.mensagens m where m.papel='lead' group by m.conversa_id
)
select c.*,l.last_lead_at,l.last_lead_at+interval '24 hours' whatsapp_window_expires_at,
  c.first_clicked_at+interval '12 hours' abandonment_due_at,
  case
    when now()<c.first_clicked_at+interval '12 hours' then 'monitoring'
    when c.channel='whatsapp' and now()>=l.last_lead_at+interval '24 hours' then 'needs_hsm'
    when c.channel='whatsapp' and public.mind_recovery_delivery_slot(
      c.first_clicked_at+interval '12 hours',l.last_lead_at+interval '24 hours','whatsapp') is null then 'needs_hsm'
    else 'ready' end abandonment_state
from click_summary c left join last_lead l on l.conversa_id=c.conversation_id
where public.mind_checkout_event_purchase_status(c.event_id)='not_purchased';

revoke all on function public.mind_checkout_event_purchase_status(uuid) from public,anon,authenticated;
grant execute on function public.mind_checkout_event_purchase_status(uuid) to service_role;
revoke all on intelligence.v_checkout_abandonment from public,anon,authenticated;
grant select on intelligence.v_checkout_abandonment to service_role;

commit;
