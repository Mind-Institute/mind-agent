-- Adriana (23/09): a regra do crachá antecipado sai. Os 93 ingressos bipados em
-- 13-15/09 voltam a não marcar dia - primeiro vamos entender quem são. A presença
-- volta à regra anterior: bip da Worknet no dia OU check-in Yazo em sala no dia.
delete from credenciamento_summit_2026.credenciamento_worknet where dia < 16;

comment on table credenciamento_summit_2026.credenciamento_worknet is
  'Evidência do credenciamento da Worknet (o sistema de bip na entrada), relatório de 23/09/2026: uma linha por ingresso (chave = número do ingresso) e dia (16 ou 17/09) em que foi bipado. 1.673 em 16/09 e 187 em 17/09. Os 93 crachás retirados de 13 a 15/09 (credenciamento antecipado) não marcam dia.';
comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.presenca_16_09 is
  'sim / ausente / cancelado. sim = a Worknet bipou o ingresso na entrada em 16/09 (credenciamento_worknet) OU check-in Yazo em alguma sala em 16/09 (Check Ins Summit, por e-mail, só quando o e-mail tem um único ingresso válido). cancelado = ingresso não válido no Mind.';
comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.fonte_16_09 is
  'bip | yazo | bip+yazo. bip = a Worknet bipou o ingresso nesse dia (credenciamento_worknet); yazo = check-in de sala no app. "yazo" sozinho = a pessoa estava nas salas mas a Worknet não a bipou nesse dia.';

with unico as (
  select lower(trim(email)) as email from credenciamento_summit_2026.controle_de_inscritos_e_presenca
   where valido_no_mind = 'sim' group by 1 having count(*) = 1
),
yazo as (
  select distinct lower(trim("Email")) as email, extract(day from checkin_em at time zone 'America/Sao_Paulo')::int as dia
    from credenciamento_summit_2026."Check Ins Summit" where checkin_em is not null
),
ev as (
  select c.uuid,
         exists (select 1 from credenciamento_summit_2026.credenciamento_worknet b where b.dia = 16 and b.chave = upper(trim(c.ticket_number))) as bip16,
         exists (select 1 from credenciamento_summit_2026.credenciamento_worknet b where b.dia = 17 and b.chave = upper(trim(c.ticket_number))) as bip17,
         (lower(trim(c.email)) in (select email from unico) and exists (select 1 from yazo y where y.email = lower(trim(c.email)) and y.dia = 16)) as yazo16,
         (lower(trim(c.email)) in (select email from unico) and exists (select 1 from yazo y where y.email = lower(trim(c.email)) and y.dia = 17)) as yazo17
    from credenciamento_summit_2026.controle_de_inscritos_e_presenca c
)
update credenciamento_summit_2026.controle_de_inscritos_e_presenca c
   set presenca_16_09 = case when c.valido_no_mind='nao' then 'cancelado' when ev.bip16 or ev.yazo16 then 'sim' else 'ausente' end,
       presenca_17_09 = case when c.valido_no_mind='nao' then 'cancelado' when ev.bip17 or ev.yazo17 then 'sim' else 'ausente' end,
       fonte_16_09 = case when c.valido_no_mind='nao' then null when ev.bip16 and ev.yazo16 then 'bip+yazo' when ev.bip16 then 'bip' when ev.yazo16 then 'yazo' end,
       fonte_17_09 = case when c.valido_no_mind='nao' then null when ev.bip17 and ev.yazo17 then 'bip+yazo' when ev.bip17 then 'bip' when ev.yazo17 then 'yazo' end,
       atualizado_em = now()
  from ev where ev.uuid = c.uuid;
update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set presenca_2_dias = case when valido_no_mind='nao' then 'cancelado' when presenca_16_09='sim' and presenca_17_09='sim' then 'sim' else 'nao' end;
