-- BACKFILL DAS PROJEÇÕES PERDIDAS NA JANELA DE ROLLOUT DO PASSO 4.
--
-- Entre 06:45 e 10:15 UTC de 02/09, 28 análises `analise_concierge` do App
-- emitiram 63 itens de `customer_memory` com evidência válida (mensagem `lead` da
-- própria conversa) — entre eles os 16 únicos ICP/JTBD já emitidos pelo sistema —
-- e nenhum chegou a `intelligence.participante_memoria`. `analise_gravar` só
-- reprojeta quando chega mensagem nova, então ficariam perdidos.
--
-- O writer vivo está certo: um dry-run em 03/09 (transação encerrada em RAISE)
-- gravou `jtbd:JT05 ativa` e `icp_atual` a partir de uma dessas análises. Este
-- backfill apenas repete a chamada que `analise_gravar` faria, com o mesmo
-- `analise_conversa_id`, para toda análise concierge que tem itens e nenhuma
-- memória vinculada. Não passa por `analise_gravar`, logo não reexecuta o
-- `silence_sync_from_analysis`. Idempotente: o writer deduplica por chave e uma
-- análise já projetada deixa de ser selecionada.
do $do$
declare r record; v_n int; v_total int := 0; v_analises int := 0;
begin
  for r in
    select a.id, a.participante_id, a.dados->'customer_memory' as memorias
    from intelligence.analise_conversa a
    where a.analisador = 'analise_concierge'
      and a.participante_id is not null
      and jsonb_typeof(a.dados->'customer_memory') = 'array'
      and jsonb_array_length(a.dados->'customer_memory') > 0
      and not exists (select 1 from intelligence.participante_memoria pm
                       where pm.analise_conversa_id = a.id)
    order by a.analisado_em
  loop
    v_n := public.analise_projetar_memoria(r.participante_id, 'analise_concierge', r.memorias, r.id);
    v_total := v_total + coalesce(v_n, 0);
    v_analises := v_analises + 1;
  end loop;
  raise notice 'backfill_projecoes_perdidas: % analises reprojetadas, % memorias novas/substituidas',
    v_analises, v_total;
end
$do$;
