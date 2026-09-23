-- 11 — fase A, VALENDO. Enriquece 1.500 pessoas por execução, sem criar ninguém.
-- Rode de novo até "restantes_nesta_rodada" chegar a 0. Cada execução é uma transação
-- própria: pode parar e voltar quando quiser.
select public.mind_identidade_enriquecer_todas(p_lote := 1500, p_simular := false);

-- Depois de aprovar fusões no 40, abra uma RODADA NOVA (a fusão libera identificadores
-- que antes pertenciam à pessoa absorvida) e repita o 11 até zerar:
-- update pessoas.pessoas set enriquecida_em = null where fundida_em is null;
