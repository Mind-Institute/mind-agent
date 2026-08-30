-- ============================================================================
-- DECOMPOSIÇÃO DO D1 DO SILENCE — diagnóstico repetível, SOMENTE LEITURA
--
-- Este arquivo NÃO é teste de contrato e NÃO é SQL de produção. Ele responde
-- uma pergunta de negócio com número em vez de impressão:
--
--   quantas oportunidades estão fora da fila de continuidade PORQUE DEVEM
--   estar (compra, opt-out), e quantas estão fora só porque o analisador
--   devolveu `continuation_status = "stopped"` com o sentido de "a conversa
--   acabou" — o D1 registrado no BACKLOG §2?
--
-- E, para as do D1, quanto custaria corrigir: o que cada uma VIRARIA se aquele
-- `stopped` sem razão da seção 22 deixasse de valer.
--
-- NADA É ESCRITO E NADA É ENVIADO. A simulação chama a própria
-- `public.silence_calcular_next_review` de produção — que é STABLE e recebe
-- `p_dados` por parâmetro — com `dados - 'continuation_status'`. O cron 13
-- continua desligado, `intelligence.continuidade_comercial` não é tocada, e o
-- arquivo roda inteiro dentro de uma transação que termina em ROLLBACK.
--
-- POR QUE A SIMULAÇÃO É HONESTA
--   A precedência da função testa compra e opt-out ANTES de olhar o
--   `continuation_status` do analisador. Então remover essa chave não pode
--   ressuscitar quem comprou nem quem pediu descadastro: eles param nas
--   guardas anteriores. A saída abaixo mostra isso acontecendo.
--
-- DEMORA. São ~113 chamadas e cada uma lê o histórico da conversa
-- (`silence_ultimo_evento`). Conte dezenas de segundos, não milissegundos.
--
-- Como rodar:  psql "$DATABASE_URL" -f tests/silence_d1_decomposicao.sql
-- ============================================================================

begin;

-- ------------------------------------------------- 1. DE ONDE VEM CADA `stopped`
-- `last_decision.calculo.reason_code` guarda o motivo com que a linha foi
-- gravada. É ele que separa o intencional do bug — não dá para separar pelo
-- `continuation_status`, que é o mesmo nos dois casos.
select
  'decomposicao' as bloco,
  cc.continuation_status,
  cc.last_decision#>>'{calculo,reason_code}' as reason_code,
  cc.next_review_policy,
  count(*) as linhas,
  case
    when cc.last_decision#>>'{calculo,reason_code}'
         in ('purchase_confirmed_crm','purchase_declared','opt_out') then 'intencional'
    when cc.continuation_status = 'stopped'
         and cc.last_decision#>>'{calculo,reason_code}' = 'stopped'  then 'D1 — bug de semantica'
    else 'demais'
  end as classificacao
from intelligence.continuidade_comercial cc
group by 1,2,3,4,6
order by linhas desc;


-- --------------------------------------- 2. O QUE AS DO D1 VIRARIAM SE CORRIGIDO
-- Única mudança: `dados - 'continuation_status'`. Tudo o mais é a função de
-- produção, com os mesmos `followup_count` e `last_followup_at` reais.
with d1 as (
  select cc.conversa_id, cc.followup_count, cc.last_followup_at, ac.dados
  from intelligence.continuidade_comercial cc
  join intelligence.analise_conversa ac on ac.id = cc.analise_conversa_id
  where cc.continuation_status = 'stopped'
    and cc.last_decision#>>'{calculo,reason_code}' = 'stopped'
),
sim as (
  select public.silence_calcular_next_review(
           d.conversa_id,
           d.dados - 'continuation_status',
           d.followup_count, d.last_followup_at,
           null::text, null::timestamptz) as calc
  from d1 d
)
select
  'simulacao' as bloco,
  calc->>'continuation_status' as viraria,
  calc->>'next_review_policy'  as policy,
  calc->>'reason_code'         as reason_code,
  count(*) as linhas,
  case when calc->>'next_review_policy' in ('timing_matrix','commitment_due')
       then 'ENTRA na fila' else 'fica fora' end as efeito
from sim
group by 2,3,4,6
order by linhas desc;


-- ------------------------------------------- 3. O QUE HÁ DENTRO DAS DO D1 HOJE
-- Serve para dimensionar o custo do bug sem abrir conversa por conversa.
with d1 as (
  select ac.dados
  from intelligence.continuidade_comercial cc
  join intelligence.analise_conversa ac on ac.id = cc.analise_conversa_id
  where cc.continuation_status = 'stopped'
    and cc.last_decision#>>'{calculo,reason_code}' = 'stopped'
)
select
  'materialidade' as bloco,
  count(*) as total_d1,
  count(*) filter (
    where nullif(btrim(coalesce(dados->>'open_loop','')),'') is not null
      and lower(dados->>'open_loop') not in ('none','null','n/a','nenhum')
  ) as com_open_loop_real,
  count(*) filter (where dados#>>'{commitment,due}' is not null) as com_compromisso_datado,
  count(*) filter (where lower(coalesce(dados->>'purchase_intent','')) in ('high','medium'))
    as intent_alto_ou_medio,
  count(*) filter (where lower(coalesce(dados->>'commercial_priority','')) in ('urgent','high'))
    as prioridade_alta
from d1;


-- ----------------------------------------------- 4. AS TRAVAS CONTINUAM VALENDO
-- Se qualquer linha aparecer aqui, a simulação puxou de volta alguém que
-- comprou ou pediu descadastro — e aí a leitura acima não vale.
do $$
declare v_n integer;
begin
  with d1 as (
    select cc.conversa_id, cc.followup_count, cc.last_followup_at, ac.dados
    from intelligence.continuidade_comercial cc
    join intelligence.analise_conversa ac on ac.id = cc.analise_conversa_id
    where cc.continuation_status = 'stopped'
      and cc.last_decision#>>'{calculo,reason_code}' = 'stopped'
  ),
  sim as (
    select public.silence_calcular_next_review(
             d.conversa_id, d.dados - 'continuation_status',
             d.followup_count, d.last_followup_at, null::text, null::timestamptz) as calc
    from d1 d
  )
  select count(*) into v_n from sim
   where calc->>'next_review_policy' in ('timing_matrix','commitment_due')
     and calc->>'reason_code' in ('purchase_confirmed_crm','purchase_declared','opt_out');

  if v_n > 0 then
    raise exception 'TRAVA VIOLADA: % linha(s) com compra/opt-out entrariam na fila', v_n;
  end if;
  raise notice 'travas de compra e opt-out preservadas na simulacao';
end $$;

-- Nada do que este arquivo tocou sobrevive a esta linha (e ele não escreveu nada).
rollback;
