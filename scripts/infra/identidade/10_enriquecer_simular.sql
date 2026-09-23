-- 10 — fase A, SIMULAÇÃO. Faz o enriquecimento de todas as pessoas e desfaz tudo.
-- O resultado vem como mensagem de erro começando com "SIMULACAO — nada gravado",
-- com o resumo em JSON: pessoas processadas, identificadores novos por canal,
-- pessoas com conflito (duplicatas) e propostas pendentes por padrão.
-- "pessoas_criadas" tem de ser 0: a fase A nunca cria ninguém.
select public.mind_identidade_enriquecer_todas(p_lote := 20000, p_simular := true);
