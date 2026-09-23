-- 51 — fase C, VALENDO, uma fonte por vez, em lotes de 2.000, na ordem da Adriana.
-- Repita a mesma linha até "restantes_nesta_fonte" chegar a 0; só então passe à próxima.
-- Quem existe é ligado; quem não existe, depois de procurado, é criado (com origem da fonte).

select public.mind_identidade_criar_faltantes('crm.contato_espelho', 2000, false);                        -- 1. HubSpot
-- select public.mind_identidade_criar_faltantes('eduzz.vendas', 2000, false);                             -- 2. Eduzz (vendas)
-- select public.mind_identidade_criar_faltantes('eduzz.ingressos', 2000, false);                          -- 3. Blinket (ingressos)

-- 4. Treble: engagement.conversas não tem o trigger (a porta única ali é mind_inbound, que já
--    resolve identidade a cada mensagem). Só as conversas antigas sem pessoa passam aqui:
-- update engagement.conversas c
--    set participante_id = (public.mind_identidade_resolver(jsonb_build_object('whatsapp', c.telefone), c.nome_contato, 'treble')->>'pessoa_id')::uuid
--  where c.participante_id is null and c.telefone is not null;

-- select public.mind_identidade_criar_faltantes('credenciamento_summit_2026.participantes', 2000, false); -- 5. credenciamento
-- select public.mind_identidade_criar_faltantes('credenciamento_summit_2026.yazo_espelho', 2000, false);  -- 6. Yazo
-- select public.mind_identidade_criar_faltantes('credenciamento_summit_2026."Relatorio Yazzo Consolidado"', 2000, false);
-- select public.mind_identidade_criar_faltantes('crm.leads_capturados', 2000, false);
-- select public.mind_identidade_criar_faltantes('checkout.pedidos', 2000, false);
