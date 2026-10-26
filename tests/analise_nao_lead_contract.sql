-- Contrato: os prompts que geram inteligência sobre o cliente/lead (analisar-conversa e silence-reavaliar)
-- não rodam para quem não é lead (professor, palestrante, staff, parceiro de venda — pessoas.relacionamento_mind).
-- A trava está nas três funções que as Edge Functions consultam antes de chamar a IA: analise_pendentes (fila),
-- analise_montar_contexto (contexto; sem transcrito a Edge Function não chama a IA) e silence_claim_pendentes.
-- Sempre termina em rollback: a exceção ANALISE_NAO_LEAD_OK é o resultado.
-- Rodar depois das migrations 20260923143941 e 20260923145909.
begin;
set local mind.d5_pular_trigger = '1';
do $$
declare
  v_lead uuid := gen_random_uuid(); v_nl uuid := gen_random_uuid();
  v_c_lead uuid; v_c_nl uuid; v_c_sem uuid; v_ctx jsonb; v_primeira uuid;
begin
  insert into pessoas.pessoas (id, primeiro_nome, sobrenome, origem)
  values (v_lead, 'Contrato', 'Lead', 'bot'), (v_nl, 'Contrato', 'Palestrante', 'bot');
  update pessoas.pessoas set relacionamento_mind = '{palestrante}' where id = v_nl;

  insert into engagement.conversas (canal, agente, mind_id) values ('mindagent-web', 'mindagent-chat', v_lead) returning id into v_c_lead;
  insert into engagement.conversas (canal, agente, mind_id) values ('mindagent-web', 'mindagent-chat', v_nl) returning id into v_c_nl;
  insert into engagement.conversas (canal, agente, mind_id) values ('whatsapp', 'treble', null) returning id into v_c_sem;
  -- mensagens "no futuro" para ficarem no topo da fila, que é ordenada pela última mensagem
  insert into engagement.mensagens (conversa_id, papel, conteudo, mind_id, criado_em) values
    (v_c_lead, 'lead', 'Quero levar um programa de bem-estar para a minha empresa', v_lead, now() + interval '1 hour'),
    (v_c_nl,   'lead', 'Onde fica a sala da minha palestra?', v_nl, now() + interval '1 hour'),
    (v_c_sem,  'lead', 'Oi, quero saber do Summit', null, now() + interval '1 hour');

  -- 1. fila: lead e conversa sem pessoa entram; não-lead não
  if not exists (select 1 from public.analise_pendentes(10) x where x.conversa_id = v_c_lead) then raise exception 'fila: conversa de lead devia entrar'; end if;
  if not exists (select 1 from public.analise_pendentes(10) x where x.conversa_id = v_c_sem) then raise exception 'fila: conversa sem pessoa devia entrar'; end if;
  if exists (select 1 from public.analise_pendentes(100000) x where x.conversa_id = v_c_nl) then raise exception 'fila: conversa de palestrante não devia entrar'; end if;

  -- 2. contexto: sem transcrito para não-lead (a Edge Function pula sem chamar a IA); completo para lead
  v_ctx := public.analise_montar_contexto(v_c_nl);
  if coalesce((v_ctx->>'nao_lead')::boolean, false) is not true or jsonb_array_length(v_ctx->'transcrito') <> 0 then
    raise exception 'contexto de não-lead devia vir sem transcrito: %', v_ctx; end if;
  if v_ctx ? 'pessoa' or v_ctx ? 'crm' then raise exception 'contexto de não-lead não devia levar pessoa/CRM'; end if;
  v_ctx := public.analise_montar_contexto(v_c_lead);
  if jsonb_array_length(v_ctx->'transcrito') <> 1 or v_ctx->'transcrito'->0->>'papel' <> 'lead' then
    raise exception 'contexto de lead devia trazer a fala: %', v_ctx; end if;
  if public.analise_montar_contexto(gen_random_uuid()) is not null then raise exception 'conversa inexistente devia devolver nulo'; end if;

  -- 3. Silence: a continuidade de não-lead não é reavaliada (a dele vence antes e mesmo assim é pulada)
  insert into intelligence.continuidade_comercial (conversa_id, continuation_status, next_review_at, next_review_policy)
  values (v_c_nl, 'followup_due', now() - interval '30 years', 'timing_matrix'),
         (v_c_lead, 'followup_due', now() - interval '20 years', 'timing_matrix');
  select x.conversa_id into v_primeira from public.silence_claim_pendentes(1) x;
  if v_primeira is distinct from v_c_lead then raise exception 'silence: devia pegar a do lead e pular a do palestrante, pegou %', v_primeira; end if;

  -- 4. volta a lead: a conversa volta para a fila
  update pessoas.pessoas set relacionamento_mind = '{lead}' where id = v_nl;
  if not exists (select 1 from public.analise_pendentes(10) x where x.conversa_id = v_c_nl) then raise exception 'de volta a lead, a conversa devia voltar para a fila'; end if;

  raise exception 'ANALISE_NAO_LEAD_OK: fila, contexto e Silence travam não-lead; lead e conversa sem pessoa seguem';
end $$;
rollback;
