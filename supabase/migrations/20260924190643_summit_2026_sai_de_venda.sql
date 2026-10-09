-- Summit 2026 sai de venda: o evento aconteceu em 16 e 17/09.
--
-- Decisão da Adriana em 24/09/2026: "tem que colocar no backend em catálogo que não estamos
-- mais vendendo o summit". O catálogo ainda dizia o contrário: `catalogo.produtos` com
-- `vende = true` para mind-summit-2026 e quatro ofertas no ar (lote 7 Mind, VIP e Prime e o
-- upgrade Mind→VIP, este sem data de fim). Em 17/09, às 06:18, o agente ofereceu o upgrade a
-- uma participante no último dia do evento.
--
-- Mesmo padrão de 20260906143000_prime_esgotado_sai_de_venda:
--   1. o produto continua `ativo` (o pós-evento — gravações, certificados — ainda é dele),
--      mas `vende = false` e `vende_ate` no fim do evento. O Kit lê isso como
--      `vendavel_agora = false`;
--   2. as ofertas ainda ativas saem do ar com `ativo = false`. `mind_kit_ofertas` exige
--      `ativo and publico`, então não sobra checkout; o sync de preços só atualiza linhas com
--      `ativo = true`, então não as ressuscita.
--
-- Reversível: `vende = true` no produto e `ativo = true` nas quatro ofertas.
-- Idempotente: no-op quando já aplicada.

begin;

update catalogo.produtos
   set vende = false,
       vende_ate = coalesce(vende_ate, '2026-09-17 23:59:59-03'),
       atualizado_em = now()
 where codigo = 'mind-summit-2026'
   and vende;

update summit_2026.offers
   set ativo = false,
       encerra_em = coalesce(encerra_em, '2026-09-17 23:59:59-03'),
       atualizado_em = now()
 where codigo in ('mind-lote-7', 'vip-lote-7', 'prime-lote-7', 'upgrade-mind-vip')
   and ativo;

commit;
