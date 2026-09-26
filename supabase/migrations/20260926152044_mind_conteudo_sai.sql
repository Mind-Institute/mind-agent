-- MIND_CONTEUDO SAI: CÓDIGO MORTO.
--
-- Pedido da Adriana (26/09/2026): "veja se pode deletar essa função". Conferido antes de apagar:
-- ela lê summit.conhecimento, que não existe mais (qualquer chamada falharia); nenhuma função, view
-- ou job cron do banco a chama; nenhuma das 35 Edge Functions publicadas nem o código do repositório;
-- nenhuma chamada nos logs do banco das últimas 24 h; só postgres e service_role executavam.
-- O corpo antigo continua em 20260829185445_historical_prod_stub.sql, se um dia precisar.

drop function if exists public.mind_conteudo(text, text);
