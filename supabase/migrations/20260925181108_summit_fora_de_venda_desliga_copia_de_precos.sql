-- O SUMMIT 2026 SAIU DE VENDA, e a cópia de preço perde o motivo de existir.
--
-- Decisão da Adriana, 25/09/2026: "O Summit não tá mais à venda. Pode parar de
-- copiar a cada 30 minutos." Os projetos do Summit fora deste banco vão ser
-- desligados — entre eles `mind-summit-propostas`, de onde este job lê o preço.
--
-- O QUE PARA. O job `mindagent-sync-precos` (a cada 30 min) chamava a Edge
-- Function de mesmo nome, que lê `pricing` do mind-summit-propostas e regrava
-- `summit_2026.offers` (valor, janela, ativo/público) e os tiers de
-- `summit_2026.commercial_rules`. Com o job parado, as duas ficam congeladas
-- como estão.
--
-- O QUE NÃO MUDA PARA O CLIENTE. `mind_kit_ofertas` só entrega oferta com
-- janela aberta, e o último lote fechou em 16/09 23h59. Nada do Summit chega ao
-- agente, antes ou depois disto. As três linhas do Lote 7 continuam marcadas
-- ativo/público na tabela — sobra da cópia, não oferta à venda.
--
-- DESLIGAR, NÃO APAGAR. O job continua cadastrado e volta com
--   select cron.alter_job(jobid, active := true)
--     from cron.job where jobname = 'mindagent-sync-precos';
-- A Edge Function continua publicada; só deixa de ser chamada.
--
-- Idempotente: rodar de novo, ou num banco sem o job, não faz nada.

do $$
declare
  v_job bigint;
begin
  select jobid into v_job from cron.job where jobname = 'mindagent-sync-precos';
  if v_job is not null then
    perform cron.alter_job(v_job, active := false);
  end if;
end
$$;
