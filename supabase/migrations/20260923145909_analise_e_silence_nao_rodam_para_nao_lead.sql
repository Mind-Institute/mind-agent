-- =====================================================================================
-- Os prompts que geram inteligência sobre o cliente/lead não rodam para quem não é lead
-- (pedido da Adriana, 23/09/2026: "Quero que os prompts que geram inteligência sobre o cliente e lead
-- não rodem para quem é professor, palestrante e equipe").
--
-- Onde a IA gera inteligência sobre a pessoa (medido em 23/09):
--   1. Edge Function `analisar-conversa` (cron `analise_conversas`, a cada 15 min): um classificador e os
--      analisadores de `agentes.prompts` (analise_vendas_*, analise_concierge, analise_atendimento,
--      analise_contexto_geral) → `intelligence.analise_conversa` → memórias (`analise_projetar_memoria`) →
--      continuidade comercial (`silence_sync_from_analysis`). Ela lê a fila em `analise_pendentes` ou recebe
--      um `conversa_id`; nos dois caminhos monta o contexto em `analise_montar_contexto` e só chama a IA se o
--      transcrito tiver fala do lead.
--   2. Edge Function `silence-reavaliar` (cron `silence_reavaliar`, hoje desligado): reavaliação da
--      continuidade por IA, fila em `silence_claim_pendentes`.
-- `analisar-conversa` e `silence-reavaliar` não estão versionadas neste repositório: a trava fica no banco,
-- nos três pontos que elas consultam ANTES de chamar a IA — nenhuma Edge Function muda.
--
--   a. analise_pendentes: conversa de quem não é lead não entra na fila;
--   b. analise_montar_contexto: para quem não é lead devolve contexto sem transcrito ({nao_lead: true}) — o
--      analisar-conversa pula a conversa sem chamar a IA (cobre a chamada direta com conversa_id);
--   c. silence_claim_pendentes: a continuidade de quem não é lead não é reavaliada.
--
-- Quem não é lead = pessoas.relacionamento_mind sem 'lead' (staff, palestrante, professor, parceiro_venda;
-- migration 20260923143941). Conversa sem pessoa continua sendo analisada (lead desconhecido).
-- O atendimento não muda: mindagent-chat, treble-inbound-agent e router continuam respondendo a professor,
-- palestrante e staff; o que deixa de existir para eles é a inteligência comercial sobre a pessoa.
-- =====================================================================================

-- a. fila da análise pós-conversa
create or replace function public.analise_pendentes(p_limite integer default 20)
returns table(conversa_id uuid)
language sql
stable security definer
set search_path to 'public', 'intelligence', 'engagement'
as $function$
  with conv as (
    select c.id,
           (select max(m.criado_em) from engagement.mensagens m where m.conversa_id = c.id) as ult_msg
    from engagement.conversas c
    left join pessoas.pessoas p on p.id = c.mind_id
    where c.agente in ('treble','treble-inbound-agent','mindagent-chat')
      and exists (select 1 from engagement.mensagens m2
                   where m2.conversa_id = c.id and m2.papel = 'lead' and m2.conteudo is not null)
      -- quem não é lead (professor, palestrante, staff, parceiro de venda) não passa pelos prompts de
      -- inteligência (23/09); conversa sem pessoa continua na fila
      and (p.id is null or 'lead' = any(p.relacionamento_mind))
  )
  select conv.id
  from conv
  where not exists (
    select 1 from intelligence.analise_conversa a
    where a.conversa_id = conv.id
      and a.conversa_atualizada_ate >= conv.ult_msg)
  order by conv.ult_msg desc, conv.id
  limit greatest(1, p_limite);
$function$;
comment on function public.analise_pendentes(integer) is 'Fila da análise pós-conversa (analisar-conversa, cron analise_conversas): conversas com fala do lead ainda não analisadas até a última mensagem, da mais recente para a mais antiga. Quem não é lead (pessoas.relacionamento_mind: professor, palestrante, staff, parceiro de venda) não entra — os prompts de inteligência não rodam para eles (23/09/2026).';

-- b. contexto que vai para os prompts da análise (e para o Silence)
CREATE OR REPLACE FUNCTION public.analise_montar_contexto(p_conversa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence', 'engagement', 'pessoas', 'crm'
AS $function$
declare
  c         engagement.conversas%rowtype;
  v_hub     text;
  v_vars    jsonb;
  v_cta     text;
  v_origem  jsonb;
  v_sessao  jsonb;
  v_crm_atr jsonb;
  v_atr     jsonb;
  v_ctx     jsonb;
begin
  select * into c from engagement.conversas where id = p_conversa_id;
  if not found then return null; end if;

  -- quem não é lead (professor, palestrante, staff, parceiro de venda) não passa pelos prompts de
  -- inteligência (23/09): sem transcrito, o analisar-conversa pula a conversa sem chamar a IA
  if not pessoas.e_lead(c.mind_id) then
    return jsonb_build_object(
      'conversa_id', p_conversa_id,
      'nao_lead', true,
      'relacionamento', (select to_jsonb(p.relacionamento_mind) from pessoas.pessoas p where p.id = c.mind_id),
      'transcrito', '[]'::jsonb);
  end if;

  select hubspot_id into v_hub from pessoas.pessoas where id = c.mind_id;

  v_vars := case
    when jsonb_typeof(c.variables) = 'array' then (
      select coalesce(jsonb_object_agg(v->>'key', v->>'value')
             filter (where nullif(v->>'key','') is not null
                       and nullif(v->>'value','') is not null), '{}'::jsonb)
      from jsonb_array_elements(c.variables) v)
    when jsonb_typeof(c.variables) = 'object' then c.variables
    else '{}'::jsonb end;

  v_cta := nullif(trim(coalesce(
             v_vars->>'hubspot_opcao_selecionada_treble',
             v_vars->>'opcao_selecionada', '')), '');

  select to_jsonb(o) - 'atualizado_em' - 'hubspot' into v_origem
    from engagement.origens o where o.codigo = c.origem_codigo;

  select jsonb_strip_nulls(to_jsonb(u) - 'token' - 'criado_em' - 'usado_em') into v_sessao
    from engagement.utm_sessoes u where u.token = c.utm_token;

  select jsonb_strip_nulls(to_jsonb(x)) into v_crm_atr from (
    select utm_source, utm_medium, utm_campaign, utm_content, utm_term,
           msclkid, li_fat_id,
           hs_analytics_source, hs_analytics_source_data_1, hs_analytics_source_data_2,
           hs_analytics_first_url, hs_analytics_first_referrer, hs_analytics_first_timestamp,
           hs_latest_source, hs_latest_source_data_1, hs_latest_source_timestamp,
           hs_analytics_last_url, hs_analytics_last_referrer,
           first_conversion_event_name, first_conversion_date,
           hs_analytics_first_touch_converting_campaign,
           hs_analytics_last_touch_converting_campaign
    from crm.contato_espelho where hubspot_id = v_hub limit 1) x;

  v_atr := jsonb_strip_nulls(jsonb_build_object(
    'utm_conversa',   c.utm,
    'utm_token',      c.utm_token,
    'sessao_do_site', nullif(coalesce(v_sessao,'{}'::jsonb), '{}'::jsonb),
    'hubspot',        nullif(coalesce(v_crm_atr,'{}'::jsonb), '{}'::jsonb)
  ));

  v_ctx := jsonb_strip_nulls(jsonb_build_object(
    'canal',          c.canal,
    'agente',         c.agente,
    'origem_codigo',  c.origem_codigo,
    'origem',         v_origem,
    'produto_codigo', c.produto_codigo,
    'entry_action',   v_cta,
    'atribuicao',     nullif(coalesce(v_atr,'{}'::jsonb), '{}'::jsonb),
    'audience',       c.audience,
    'stage',          c.stage,
    'iniciada_em',    c.iniciada_em,
    'encerrada_em',   c.encerrada_em,
    'variables',      nullif(v_vars, '{}'::jsonb)
  ));

  return jsonb_build_object(
    'conversation_context', v_ctx,
    'conversa_id', p_conversa_id,
    'transcrito', coalesce((
       select jsonb_agg(jsonb_build_object(
                'mensagem_id', m.id,
                'papel', m.papel,
                'conteudo', m.conteudo,
                'criado_em', m.criado_em)
                order by m.criado_em, m.id)
       from engagement.mensagens m
       where m.conversa_id = p_conversa_id and m.conteudo is not null), '[]'::jsonb),
    'pessoa', (select to_jsonb(x) from (
       select primeiro_nome, sobrenome, email, empresa, cargo
       from pessoas.pessoas where id = c.mind_id) x),
    'crm', (select to_jsonb(y) from (
       select lead_tier, lead_icp, icp, hs_lead_status, produto_de_interesse, motivo_do_lead__perdido,
              company, total_de_ingressos_comprados_lifetime, num_associated_deals, total_revenue
       from crm.contato_espelho where hubspot_id = v_hub limit 1) y)
  );
end
$function$;
comment on function public.analise_montar_contexto(uuid) is 'Contexto que vai para os prompts da análise pós-conversa (analisar-conversa) e do Silence: contexto da conversa, atribuição, transcrito, pessoa e CRM. Para quem não é lead (pessoas.relacionamento_mind) devolve {nao_lead: true, transcrito: []} — sem fala do lead, a Edge Function não chama a IA (23/09/2026).';

-- c. fila da reavaliação de continuidade (Silence; cron hoje desligado)
CREATE OR REPLACE FUNCTION public.silence_claim_pendentes(p_limite integer DEFAULT 10)
 RETURNS TABLE(conversa_id uuid, analise_conversa_id uuid, continuation_status text, next_review_at timestamp with time zone, next_review_policy text, followup_count integer, last_followup_at timestamp with time zone, ultimo_evento_em timestamp with time zone, dados jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'intelligence', 'engagement'
AS $function$
declare v_lock integer; v_cfg jsonb;
begin
  select c.valor into v_cfg from intelligence.config c where c.chave = 'silence_timing_v1';
  v_lock := coalesce((v_cfg->>'lock_minutos')::int, 10);

  return query
  with alvo as (
    select cc.conversa_id
      from intelligence.continuidade_comercial cc
     where cc.next_review_at is not null
       and cc.next_review_at <= now()
       and (cc.processing_until is null or cc.processing_until < now())
       and cc.continuation_status not in ('stopped','dormant')
       -- quem não é lead (professor, palestrante, staff, parceiro de venda) não é reavaliado (23/09)
       and not exists (select 1 from engagement.conversas cv join pessoas.pessoas p on p.id = cv.mind_id
                        where cv.id = cc.conversa_id and not ('lead' = any(p.relacionamento_mind)))
     order by cc.next_review_at asc
     limit greatest(coalesce(p_limite,10), 1)
     for update skip locked
  ), travado as (
    update intelligence.continuidade_comercial c
       set processing_until = now() + make_interval(mins => v_lock)
      from alvo a
     where c.conversa_id = a.conversa_id
     returning c.*
  )
  select t.conversa_id, t.analise_conversa_id, t.continuation_status,
         t.next_review_at, t.next_review_policy, t.followup_count, t.last_followup_at,
         public.silence_ultimo_evento(t.conversa_id),
         (select ac.dados from intelligence.analise_conversa ac where ac.id = t.analise_conversa_id)
    from travado t;
end $function$;
comment on function public.silence_claim_pendentes(integer) is 'Fila da reavaliação de continuidade comercial (silence-reavaliar): trava e devolve as conversas com revisão vencida. Quem não é lead (pessoas.relacionamento_mind) não é reavaliado (23/09/2026).';
