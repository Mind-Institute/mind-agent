-- "Falhar melhor" (16/09, 18h, Sala Workshop 2) ficou com 1 check-in: o app do
-- credenciamento listava a sessão na Workshop 1, e na porta da Workshop 2 a
-- recepcionista só via a sessão da tarde daquela sala ("O que sustenta equipes de
-- alta performance"). Os check-ins que ela fez às 18h sob essa sessão (11 pessoas,
-- 9 com reserva em "Falhar melhor") são de "Falhar melhor": hora e sala batem.
-- Decisão da Adriana (23/09). Os 19 que reservaram "Falhar melhor" e foram
-- checados na Workshop 1 como "Resiliência" ficam como estão até ela decidir.
update credenciamento_summit_2026."Check Ins Summit" k
   set sessao_id = '2f642361-10d5-4ef4-853f-8e3958bb6fa4',
       sessao_resolvida_em = now()
 where k.sessao_id = '586055a2-7ae0-49ba-b18a-0c2e2919a176'
   and (k.checkin_em at time zone 'America/Sao_Paulo')::time >= '13:30';
