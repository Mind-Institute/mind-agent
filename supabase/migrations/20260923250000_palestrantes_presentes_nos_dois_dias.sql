-- Decisão da Adriana (23/09): todo palestrante conta como presente nos dois dias.
-- Palestrante = ingresso com origem "Palestrante" (Blinket) OU nome que está na
-- programação (ecossistema.palestrantes_especialistas ligado a summit_2026.sessions;
-- casamento por nome sem acento, todos os nomes do cadastro dentro do nome do
-- ingresso - "Stela Campos" acha "Stela Maria Campos Pinto"). A marca fica na
-- coluna palestrante, para a regra não depender de casar nome toda vez.
alter table credenciamento_summit_2026.controle_de_inscritos_e_presenca
  add column if not exists palestrante boolean not null default false;
comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.palestrante is
  'true = palestrante/mediador do Summit (origem do ingresso "Palestrante" ou nome na programação). Conta como presente nos dois dias (decisão da Adriana, 23/09).';

update credenciamento_summit_2026.controle_de_inscritos_e_presenca set palestrante = false;
update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set palestrante = true
 where origem_ingresso = 'Palestrante';
with sp as (
  select lower(translate(s.nome, 'áàâãéêíóôõúüçÁÀÂÃÉÊÍÓÔÕÚÜÇ', 'aaaaeeiooouucaaaeeiooouuc')) as sn
    from ecossistema.palestrantes_especialistas s
   where exists (select 1 from summit_2026.session_speakers ss where ss.speaker_id = s.id)
)
update credenciamento_summit_2026.controle_de_inscritos_e_presenca c
   set palestrante = true
 where not c.palestrante
   and exists (
     select 1 from sp
      where length(sp.sn) > 8
        and lower(translate(c.nome, 'áàâãéêíóôõúüçÁÀÂÃÉÊÍÓÔÕÚÜÇ', 'aaaaeeiooouucaaaeeiooouuc'))
            ~ ('\m' || replace(regexp_replace(sp.sn, '\s+', ' ', 'g'), ' ', '\M.*\m') || '\M'));

comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.presenca_16_09 is
  'sim / ausente / cancelado. sim = a Worknet bipou o ingresso na entrada em 16/09 (credenciamento_worknet) OU check-in Yazo em alguma sala em 16/09 (Check Ins Summit, por e-mail, só quando o e-mail tem um único ingresso válido) OU palestrante (conta nos dois dias). cancelado = ingresso não válido no Mind.';
comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.fonte_16_09 is
  'Evidências da presença no dia, unidas por "+": bip (a Worknet bipou o ingresso nesse dia), yazo (check-in de sala no app), palestrante (conta nos dois dias). "yazo" sozinho = a pessoa estava nas salas mas a Worknet não a bipou nesse dia.';

with unico as (
  select lower(trim(email)) as email from credenciamento_summit_2026.controle_de_inscritos_e_presenca
   where valido_no_mind = 'sim' group by 1 having count(*) = 1
),
yazo as (
  select distinct lower(trim("Email")) as email, extract(day from checkin_em at time zone 'America/Sao_Paulo')::int as dia
    from credenciamento_summit_2026."Check Ins Summit" where checkin_em is not null
),
ev as (
  select c.uuid, c.palestrante,
         exists (select 1 from credenciamento_summit_2026.credenciamento_worknet b where b.dia = 16 and b.chave = upper(trim(c.ticket_number))) as bip16,
         exists (select 1 from credenciamento_summit_2026.credenciamento_worknet b where b.dia = 17 and b.chave = upper(trim(c.ticket_number))) as bip17,
         (lower(trim(c.email)) in (select email from unico) and exists (select 1 from yazo y where y.email = lower(trim(c.email)) and y.dia = 16)) as yazo16,
         (lower(trim(c.email)) in (select email from unico) and exists (select 1 from yazo y where y.email = lower(trim(c.email)) and y.dia = 17)) as yazo17
    from credenciamento_summit_2026.controle_de_inscritos_e_presenca c
)
update credenciamento_summit_2026.controle_de_inscritos_e_presenca c
   set presenca_16_09 = case when c.valido_no_mind='nao' then 'cancelado' when ev.bip16 or ev.yazo16 or ev.palestrante then 'sim' else 'ausente' end,
       presenca_17_09 = case when c.valido_no_mind='nao' then 'cancelado' when ev.bip17 or ev.yazo17 or ev.palestrante then 'sim' else 'ausente' end,
       fonte_16_09 = case when c.valido_no_mind='nao' then null else nullif(concat_ws('+', case when ev.bip16 then 'bip' end, case when ev.yazo16 then 'yazo' end, case when ev.palestrante then 'palestrante' end), '') end,
       fonte_17_09 = case when c.valido_no_mind='nao' then null else nullif(concat_ws('+', case when ev.bip17 then 'bip' end, case when ev.yazo17 then 'yazo' end, case when ev.palestrante then 'palestrante' end), '') end,
       atualizado_em = now()
  from ev where ev.uuid = c.uuid;
update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set presenca_2_dias = case when valido_no_mind='nao' then 'cancelado' when presenca_16_09='sim' and presenca_17_09='sim' then 'sim' else 'nao' end;
