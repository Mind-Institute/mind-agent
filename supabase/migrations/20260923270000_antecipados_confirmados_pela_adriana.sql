-- Adriana (23/09), sobre os 34 ingressos com crachá antecipado que ainda estavam
-- ausentes: Reinaldo Costa é palestrante; Ricardo Sales não veio; os outros 32
-- (equipes de Sextante, Vale, WellZ, Heineken, BWG, Mindself, Mind) estiveram nos
-- dois dias. A confirmação dela fica na coluna confirmado_pela_adriana.
alter table credenciamento_summit_2026.controle_de_inscritos_e_presenca
  add column if not exists confirmado_pela_adriana boolean not null default false;
comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.confirmado_pela_adriana is
  'true = a Adriana confirmou presença nos dois dias (equipes de patrocinador com crachá antecipado, 23/09).';

update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set palestrante = true where ticket_number = '2609UVQWZD';
update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set confirmado_pela_adriana = true
 where ticket_number in (
   '2609OFBOGF','2609UKLVCO','26093WHGFX','2609WGGXLM','2609DO6JKR','2609UWIICG','2609IFEFD3','2609TEGM0N',
   '2609CXMGQ5','2609HIEBJ7','2609FWMMJY','2609MIFNZR','2609G5TVYI','2609OIUJKV','2609JEA4WZ','2609F4ISWA',
   '2609MNUB6S','26094E5ZMV','2609FOFX27','2609S0IXIT','26098KTY12','2609EDC4SJ','2609R8XYKK','2609KNNAKO',
   '2609T1JAMR','2609BI9BAX','2609RBEDDY','2609W7NOWW','2609TLUPTP','26096LDHHH','2609JI8TVE','2609HOKZT4');

comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.fonte_16_09 is
  'Evidências da presença no dia, unidas por "+": bip (a Worknet bipou o ingresso nesse dia), yazo (check-in de sala no app), palestrante, staff, adriana (confirmação dela) - os três últimos contam nos dois dias. "yazo" sozinho = a pessoa estava nas salas mas a Worknet não a bipou nesse dia.';

with unico as (
  select lower(trim(email)) as email from credenciamento_summit_2026.controle_de_inscritos_e_presenca
   where valido_no_mind = 'sim' group by 1 having count(*) = 1
),
yazo as (
  select distinct lower(trim("Email")) as email, extract(day from checkin_em at time zone 'America/Sao_Paulo')::int as dia
    from credenciamento_summit_2026."Check Ins Summit" where checkin_em is not null
),
ev as (
  select c.uuid, c.palestrante, c.staff_mind, c.confirmado_pela_adriana as adr,
         exists (select 1 from credenciamento_summit_2026.credenciamento_worknet b where b.dia = 16 and b.chave = upper(trim(c.ticket_number))) as bip16,
         exists (select 1 from credenciamento_summit_2026.credenciamento_worknet b where b.dia = 17 and b.chave = upper(trim(c.ticket_number))) as bip17,
         (lower(trim(c.email)) in (select email from unico) and exists (select 1 from yazo y where y.email = lower(trim(c.email)) and y.dia = 16)) as yazo16,
         (lower(trim(c.email)) in (select email from unico) and exists (select 1 from yazo y where y.email = lower(trim(c.email)) and y.dia = 17)) as yazo17
    from credenciamento_summit_2026.controle_de_inscritos_e_presenca c
)
update credenciamento_summit_2026.controle_de_inscritos_e_presenca c
   set presenca_16_09 = case when c.valido_no_mind='nao' then 'cancelado' when ev.bip16 or ev.yazo16 or ev.palestrante or ev.staff_mind or ev.adr then 'sim' else 'ausente' end,
       presenca_17_09 = case when c.valido_no_mind='nao' then 'cancelado' when ev.bip17 or ev.yazo17 or ev.palestrante or ev.staff_mind or ev.adr then 'sim' else 'ausente' end,
       fonte_16_09 = case when c.valido_no_mind='nao' then null else nullif(concat_ws('+', case when ev.bip16 then 'bip' end, case when ev.yazo16 then 'yazo' end, case when ev.palestrante then 'palestrante' end, case when ev.staff_mind then 'staff' end, case when ev.adr then 'adriana' end), '') end,
       fonte_17_09 = case when c.valido_no_mind='nao' then null else nullif(concat_ws('+', case when ev.bip17 then 'bip' end, case when ev.yazo17 then 'yazo' end, case when ev.palestrante then 'palestrante' end, case when ev.staff_mind then 'staff' end, case when ev.adr then 'adriana' end), '') end,
       atualizado_em = now()
  from ev where ev.uuid = c.uuid;
update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set presenca_2_dias = case when valido_no_mind='nao' then 'cancelado' when presenca_16_09='sim' and presenca_17_09='sim' then 'sim' else 'nao' end;
