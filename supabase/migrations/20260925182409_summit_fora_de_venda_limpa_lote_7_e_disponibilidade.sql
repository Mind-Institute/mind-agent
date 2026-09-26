-- LIMPEZA DO SUMMIT: o banco passa a dizer o mesmo que a Adriana.
--
-- Decisão dela, 25/09/2026, depois da 20260925181108: desligar também a cópia
-- diária das 21h e marcar o Lote 7 como inativo. O Summit 2026 não está à
-- venda, e o site dele continua no ar como está, sem oferta nenhuma.
--
-- 1. O job `mindagent-sync-disponibilidade-diaria` (21h) lia o site do Summit
--    para gravar a porcentagem vendida de VIP e Prime. Sem venda, não há o que
--    ler. Desligado, não apagado; volta com
--      select cron.alter_job(jobid, active := true)
--        from cron.job where jobname = 'mindagent-sync-disponibilidade-diaria';
--
-- 2. As três linhas do Lote 7 (Mind, VIP e Prime) ficaram ativas e públicas
--    porque a fonte de preço ainda dizia que o lote 7 era o vigente; a janela
--    delas fechou em 16/09 23h59. Passam a ativo = false e publico = false,
--    como todo lote encerrado que a cópia gravava, com `atualizado_em`
--    carimbado: é a única evidência de quando uma oferta mudou.
--    Nada muda para o cliente: `mind_kit_ofertas` já não as entregava.
--
-- Idempotente: rodar de novo, ou num banco sem o job, não faz nada.

do $$
declare
  v_job bigint;
begin
  select jobid into v_job from cron.job where jobname = 'mindagent-sync-disponibilidade-diaria';
  if v_job is not null then
    perform cron.alter_job(v_job, active := false);
  end if;
end
$$;

update summit_2026.offers
   set ativo = false,
       publico = false,
       atualizado_em = now()
 where codigo in ('mind-lote-7', 'vip-lote-7', 'prime-lote-7')
   and (ativo or publico);
