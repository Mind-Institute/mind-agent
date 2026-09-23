-- Decisão da Adriana (23/09): as recepcionistas da Workshop 1 erraram - quem tinha
-- reserva em "Falhar melhor" (e não em "Resiliência em tempo real") e foi checado
-- às 18h de 16/09 como "Resiliência" estava em "Falhar melhor": a reserva vence o
-- check-in errado. 19 pessoas.
with falhar as (select distinct lower(trim(r."Email")) as email from credenciamento_summit_2026."Reservas_Agenda_APP" r where r.sessao_id = '2f642361-10d5-4ef4-853f-8e3958bb6fa4'),
res as (select distinct lower(trim(r."Email")) as email from credenciamento_summit_2026."Reservas_Agenda_APP" r where r.sessao_id = '5de30250-2156-4b00-8580-fe3509b440b0')
update credenciamento_summit_2026."Check Ins Summit" k
   set sessao_id = '2f642361-10d5-4ef4-853f-8e3958bb6fa4', sessao_resolvida_em = now()
 where k.sessao_id = '5de30250-2156-4b00-8580-fe3509b440b0'
   and lower(trim(k."Email")) in (select email from falhar)
   and lower(trim(k."Email")) not in (select email from res);

-- Mesma regra para quem reservou "Falhar melhor" e foi checado no mesmo horário
-- em "Liderança engajadora" (Workshop 3) sem ter reserva lá: 1 pessoa.
with falhar as (select distinct lower(trim(r."Email")) as email from credenciamento_summit_2026."Reservas_Agenda_APP" r where r.sessao_id = '2f642361-10d5-4ef4-853f-8e3958bb6fa4'),
lid as (select distinct lower(trim(r."Email")) as email from credenciamento_summit_2026."Reservas_Agenda_APP" r where r.sessao_id = 'fcbd16c9-c575-42d4-bd17-343654f01af0')
update credenciamento_summit_2026."Check Ins Summit" k
   set sessao_id = '2f642361-10d5-4ef4-853f-8e3958bb6fa4', sessao_resolvida_em = now()
 where k.sessao_id = 'fcbd16c9-c575-42d4-bd17-343654f01af0'
   and lower(trim(k."Email")) in (select email from falhar)
   and lower(trim(k."Email")) not in (select email from lid);
