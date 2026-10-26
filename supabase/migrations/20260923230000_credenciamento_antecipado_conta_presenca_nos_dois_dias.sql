-- Decisão da Adriana (23/09): quem retirou o crachá no credenciamento antecipado
-- (13 a 15/09) conta como presente nos dois dias. São 93 ingressos do relatório da
-- Worknet - patrocinadores, expositores e equipe (Sextante, Vale, Heineken, Mind) -
-- que a Worknet marca como "Presente" mas sem bip em 16 ou 17/09; 60 deles não
-- tinham evidência nenhuma de dia e estavam como ausentes. A regra vale para os 93,
-- inclusive os 33 que a Yazo viu em um dos dias, para que quem tem mais evidência
-- não fique pior do que quem não tem nenhuma.
--
-- A evidência entra como a Worknet reportou (dia 13, 14 ou 15); a regra de presença
-- é que trata dia < 16 como presença nos dois dias, com a fonte "antecipado".
insert into credenciamento_summit_2026.credenciamento_worknet (chave, dia) values
  ('2603OAO1E8',14),('2606UBQCDZ',15),('2607ZSAFXP',15),('2608IYQUCL',15),('2608XA3AY9',15),('26093WHGFX',15),('26094E5ZMV',15),('26094KD6CL',15),
  ('26096LDHHH',15),('26098KTY12',15),('26099PQLTM',15),('26099QGDE9',15),('26099S7LBG',15),('2609BI9BAX',15),('2609CGTTYN',15),('2609CXMGQ5',15),
  ('2609D9WELM',15),('2609DD1GDP',15),('2609DO6JKR',15),('2609EDC4SJ',15),('2609EE616H',15),('2609ESGJJY',15),('2609EVQJEH',15),('2609EZCZPQ',15),
  ('2609F4ISWA',15),('2609FOFX27',15),('2609FWMMJY',15),('2609G5TVYI',15),('2609GAOIXW',15),('2609GJFF7V',15),('2609GMGTWT',15),('2609GMVCK8',15),
  ('2609GWKZNR',15),('2609HIEBJ7',15),('2609HKFKLK',15),('2609HMYRDS',15),('2609HOKZT4',15),('2609I41WKH',15),('2609IFEFD3',15),('2609IFRFFZ',15),
  ('2609IJWLBD',15),('2609IRDVNO',15),('2609IVSR0X',15),('2609JEA4WZ',15),('2609JI8TVE',15),('2609K1ZPRR',15),('2609KIZPH8',15),('2609KJIRAH',15),
  ('2609KLU3BA',15),('2609KNNAKO',15),('2609KVSIR7',15),('2609KWFVAV',15),('2609KXJLVF',15),('2609LCFHTU',15),('2609LH89BH',15),('2609LSAZT9',15),
  ('2609M4QDNW',15),('2609MIFNZR',15),('2609MNUB6S',15),('2609NXEFHT',15),('2609OFBOGF',15),('2609OIUJKV',15),('2609QWOTP9',15),('2609R8XYKK',15),
  ('2609RBEDDY',15),('2609S0IXIT',15),('2609SQ737X',15),('2609STQB8W',15),('2609T1JAMR',15),('2609T5C4VB',15),('2609TDIR79',15),('2609TEGM0N',15),
  ('2609TLUPTP',15),('2609UA2ULS',15),('2609UEPMO0',15),('2609UKLVCO',15),('2609USODHW',15),('2609UVQWZD',15),('2609UWIICG',15),('2609V7TIEY',15),
  ('2609VE39OD',15),('2609VSYBZA',15),('2609W7NOWW',15),('2609WGGXLM',13),('2609WL2GAD',15),('2609WMPZBX',15),('2609XA8H6K',15),('2609XOUVG1',15),
  ('2609YALVWX',15),('2609YBJBWD',15),('2609YP1IL8',15),('2609YQSC3U',15),('2609ZM1Z27',15)
on conflict (chave, dia) do nothing;

comment on table credenciamento_summit_2026.credenciamento_worknet is
  'Evidência do credenciamento da Worknet (o sistema de bip na entrada), relatório de 23/09/2026: uma linha por ingresso (chave = número do ingresso) e dia em que foi bipado. dia 16 ou 17 = bip no dia do evento (1.673 e 187); dia 13, 14 ou 15 = credenciamento antecipado (93), que a regra de presença conta como presente nos dois dias (decisão da Adriana, 23/09).';
comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.presenca_16_09 is
  'sim / ausente / cancelado. sim = a Worknet bipou o ingresso na entrada em 16/09 (credenciamento_worknet) OU check-in Yazo em alguma sala em 16/09 (Check Ins Summit, por e-mail, só quando o e-mail tem um único ingresso válido) OU crachá retirado no credenciamento antecipado de 13-15/09 (conta nos dois dias). cancelado = ingresso não válido no Mind.';
comment on column credenciamento_summit_2026.controle_de_inscritos_e_presenca.fonte_16_09 is
  'Evidências da presença no dia, unidas por "+": bip (a Worknet bipou o ingresso nesse dia), yazo (check-in de sala no app), antecipado (crachá retirado em 13-15/09, conta nos dois dias). "yazo" sozinho = a pessoa estava nas salas mas a Worknet não a bipou nesse dia.';

-- presença, na forma final
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
         exists (select 1 from credenciamento_summit_2026.credenciamento_worknet b where b.dia < 16 and b.chave = upper(trim(c.ticket_number))) as antecipado,
         (lower(trim(c.email)) in (select email from unico) and exists (select 1 from yazo y where y.email = lower(trim(c.email)) and y.dia = 16)) as yazo16,
         (lower(trim(c.email)) in (select email from unico) and exists (select 1 from yazo y where y.email = lower(trim(c.email)) and y.dia = 17)) as yazo17
    from credenciamento_summit_2026.controle_de_inscritos_e_presenca c
)
update credenciamento_summit_2026.controle_de_inscritos_e_presenca c
   set presenca_16_09 = case when c.valido_no_mind='nao' then 'cancelado' when ev.bip16 or ev.yazo16 or ev.antecipado then 'sim' else 'ausente' end,
       presenca_17_09 = case when c.valido_no_mind='nao' then 'cancelado' when ev.bip17 or ev.yazo17 or ev.antecipado then 'sim' else 'ausente' end,
       fonte_16_09 = case when c.valido_no_mind='nao' then null else nullif(concat_ws('+', case when ev.bip16 then 'bip' end, case when ev.yazo16 then 'yazo' end, case when ev.antecipado then 'antecipado' end), '') end,
       fonte_17_09 = case when c.valido_no_mind='nao' then null else nullif(concat_ws('+', case when ev.bip17 then 'bip' end, case when ev.yazo17 then 'yazo' end, case when ev.antecipado then 'antecipado' end), '') end,
       atualizado_em = now()
  from ev where ev.uuid = c.uuid;
update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set presenca_2_dias = case when valido_no_mind='nao' then 'cancelado' when presenca_16_09='sim' and presenca_17_09='sim' then 'sim' else 'nao' end;
