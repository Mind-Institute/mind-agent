-- 50 — fase C, SIMULAÇÃO, uma fonte por vez, na ordem da Adriana.
-- Cada chamada faz o trabalho e desfaz; o resumo vem como mensagem "SIMULACAO — nada gravado":
-- linhas processadas, ligadas a pessoa existente, pessoas criadas, sem pessoa (e por quê).
-- Se a fase A não terminou, a função recusa ("fase_a_incompleta").
-- Rode UMA linha por vez (a mensagem de erro interrompe o script).

select public.mind_identidade_criar_faltantes('crm.contato_espelho', 100000, true);                       -- 1. HubSpot
-- select public.mind_identidade_criar_faltantes('eduzz.vendas', 100000, true);                            -- 2. Eduzz (vendas)
-- select public.mind_identidade_criar_faltantes('eduzz.ingressos', 100000, true);                         -- 3. Blinket (ingressos)
-- (4. Treble: conversas sem pessoa são 42 hoje, 4 com telefone; ver o 51)
-- select public.mind_identidade_criar_faltantes('credenciamento_summit_2026.participantes', 100000, true); -- 5. credenciamento
-- select public.mind_identidade_criar_faltantes('credenciamento_summit_2026.yazo_espelho', 100000, true);  -- 6. Yazo
-- select public.mind_identidade_criar_faltantes('credenciamento_summit_2026."Relatorio Yazzo Consolidado"', 100000, true);
-- select public.mind_identidade_criar_faltantes('crm.leads_capturados', 100000, true);
-- select public.mind_identidade_criar_faltantes('checkout.pedidos', 100000, true);
