-- Atribuição do checkout que foi efetivamente emitido por um Agent.
--
-- A aquisição original continua na conversa e nos parâmetros de campanha. O
-- identificador público é somente o UUID opaco de engagement.agente_eventos.
-- `utm_content` carrega motivo + token porque esse campo já percorre a Eduzz e
-- os dois espelhos atuais; `utm_term` é redundância para a evolução do conector.

create or replace function public.mind_checkout_envio_registrar(
  p_evento_id uuid,
  p_conversa_id uuid,
  p_checkout_url text,
  p_canal text,
  p_agente text,
  p_rota text,
  p_motivo text,
  p_request_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, engagement, pessoas
as $function$
declare
  v_participante_id uuid;
  v_existente engagement.agente_eventos%rowtype;
begin
  if p_evento_id is null or p_conversa_id is null then
    raise exception 'evento_e_conversa_obrigatorios' using errcode = '22023';
  end if;

  if p_canal not in ('whatsapp', 'app') then
    raise exception 'canal_invalido' using errcode = '22023';
  end if;

  if p_checkout_url is null
     or p_checkout_url !~* '^https://([a-z0-9-]+\.)*eduzz\.com/' then
    raise exception 'checkout_nao_oficial' using errcode = '22023';
  end if;

  if coalesce(p_agente, '') !~ '^[a-z][a-z0-9_-]{1,79}$'
     or coalesce(p_rota, '') !~ '^[a-z][a-z0-9_]{1,59}$'
     or coalesce(p_motivo, '') !~ '^[a-z][a-z0-9_]{1,159}$' then
    raise exception 'metadado_invalido' using errcode = '22023';
  end if;

  select c.participante_id
    into v_participante_id
  from engagement.conversas c
  where c.id = p_conversa_id;

  if not found then
    raise exception 'conversa_inexistente' using errcode = '22023';
  end if;

  insert into engagement.agente_eventos (
    id, participante_id, conversa_id, tipo, intencao, dados
  ) values (
    p_evento_id,
    v_participante_id,
    p_conversa_id,
    'checkout_link_enviado',
    'compra',
    jsonb_build_object(
      'canal', p_canal,
      'agente', p_agente,
      'rota', p_rota,
      'motivo', p_motivo,
      'checkout_url_original', p_checkout_url,
      'request_id', nullif(p_request_id, ''),
      'estado', 'emitido_pelo_runtime'
    )
  )
  on conflict (id) do nothing;

  select e.* into v_existente
  from engagement.agente_eventos e
  where e.id = p_evento_id;

  if v_existente.conversa_id is distinct from p_conversa_id
     or v_existente.tipo is distinct from 'checkout_link_enviado'
     or v_existente.dados->>'checkout_url_original' is distinct from p_checkout_url then
    raise exception 'evento_id_em_conflito' using errcode = '23505';
  end if;

  return jsonb_build_object(
    'ok', true,
    'event_id', v_existente.id,
    'conversation_id', v_existente.conversa_id,
    'channel', v_existente.dados->>'canal',
    'agent_id', v_existente.dados->>'agente',
    'reason', v_existente.dados->>'motivo',
    'sent_at', v_existente.criado_em
  );
end
$function$;

revoke all on function public.mind_checkout_envio_registrar(
  uuid, uuid, text, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.mind_checkout_envio_registrar(
  uuid, uuid, text, text, text, text, text, text
) to service_role;

comment on function public.mind_checkout_envio_registrar(
  uuid, uuid, text, text, text, text, text, text
) is
  'Registra, de forma idempotente, o checkout oficial que um runtime realmente devolvera. O UUID opaco do evento liga a URL a conversa, canal, agente, rota e motivo sem PII.';

create or replace view intelligence.v_conversoes_agente
with (security_invoker = true)
as
with vendas_tokenizadas as (
  select
    v.*,
    coalesce(
      substring(lower(coalesce(v.utm_term, '')) from 'ae_([0-9a-f]{32})'),
      substring(lower(coalesce(v.utm_content, '')) from 'ae_([0-9a-f]{32})')
    ) as evento_hex
  from eduzz.vendas v
)
select
  v.linha_origem as sale_line_id,
  v.fatura as order_id,
  v.status as payment_status,
  lower(coalesce(v.status, '')) in ('paga', 'paid', 'aprovada', 'approved') as paid,
  v.data_de_criacao as ordered_at,
  v.data_de_pagamento as paid_at,
  coalesce(nullif(v.produto_mapeado, ''), nullif(v.nome_da_oferta, ''), v.produto) as ticket_type,
  case when btrim(coalesce(v.quantidade, '')) ~ '^[0-9]+$'
       then btrim(v.quantidade)::integer end as quantity,
  case when btrim(coalesce(nullif(v.valor_total_do_item, ''), v.valor_total_da_venda, '')) ~ '^-?[0-9]+([.,][0-9]+)?$'
       then replace(btrim(coalesce(nullif(v.valor_total_do_item, ''), v.valor_total_da_venda)), ',', '.')::numeric end as revenue,
  v.moeda as currency,
  v.utm_source,
  v.utm_medium,
  v.utm_campaign,
  regexp_replace(coalesce(v.utm_content, ''), '__ae_[0-9a-f]{32}.*$', '') as checkout_content,
  e.id as event_id,
  e.conversa_id as conversation_id,
  e.participante_id as participant_id,
  e.dados->>'canal' as channel,
  e.dados->>'agente' as agent_id,
  e.dados->>'rota' as route,
  e.dados->>'motivo' as checkout_reason,
  e.criado_em as checkout_sent_at,
  'ai'::text as conversion_owner,
  'ai_conversion'::text as conversion_classification
from vendas_tokenizadas v
join engagement.agente_eventos e
  on e.id = v.evento_hex::uuid
 and e.tipo = 'checkout_link_enviado'
where v.evento_hex is not null;

revoke all on intelligence.v_conversoes_agente from public, anon, authenticated;
grant select on intelligence.v_conversoes_agente to service_role, mind_agent;

comment on view intelligence.v_conversoes_agente is
  'Vendas Eduzz atribuídas ao envio exato de checkout por Agent. Não expõe nome, e-mail, telefone, documento ou endereço do comprador.';

-- O app continua entrando como concierge. A rota de venda individual fica
-- disponível somente para uma troca explícita de competência, por exemplo um
-- upgrade porque o ingresso atual não dá acesso ao conteúdo desejado.
update agentes.canal_competencia
set ativo = true,
    observacao = 'O app entra como concierge e pode trocar para venda individual quando houver intenção explícita de compra ou upgrade.',
    atualizado_em = now()
where canal = 'mindagent-web'
  and rota = 'summit_b2c';

do $assert$
begin
  if not exists (
    select 1 from agentes.canal_competencia
    where canal = 'mindagent-web' and rota = 'summit_b2c' and ativo
  ) then
    raise exception 'canal_competencia do app para summit_b2c nao foi habilitada';
  end if;
end
$assert$;
