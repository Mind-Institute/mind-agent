-- A 013 trocou a assinatura de api.knowledge com `create or replace`, o que cria
-- SOBRECARGA, não substituição: ficaram duas versões e api.knowledge('pergunta')
-- virou ambíguo — erro em runtime, não na migration. A antiga sai.
drop function if exists api.knowledge(text, integer);
