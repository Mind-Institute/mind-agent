-- 1) credenciamento_worknet fica só com ingresso.
--    Os 9 check-ins manuais que a Worknet registrou por e-mail não identificam
--    ingresso: 7 e-mails não existem entre os 2.577 e os 2 que existem já tinham
--    o bip do próprio ingresso (Alexandre Dias; Francisco de Assis, 2 ingressos).
--    Saem, com a coluna por_email: a tabela deixa de carregar identificador de
--    pessoa e a Regra #1 (D5) não se aplica a ela. A presença não muda.
delete from credenciamento_summit_2026.credenciamento_worknet where por_email;
alter table credenciamento_summit_2026.credenciamento_worknet
  drop constraint if exists credenciamento_worknet_pkey,
  drop column if exists por_email;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'credenciamento_worknet_pkey') then
    alter table credenciamento_summit_2026.credenciamento_worknet add primary key (chave, dia);
  end if;
end $$;
comment on table credenciamento_summit_2026.credenciamento_worknet is
  'Evidência do credenciamento da Worknet (o sistema de bip na entrada), relatório de 23/09/2026: uma linha por ingresso (chave = número do ingresso) e dia (16 ou 17/09) em que foi bipado. 1.670 em 16/09 e 187 em 17/09. Os 93 crachás retirados de 13 a 15/09 (credenciamento antecipado) não marcam dia.';

-- 2) controle_de_inscritos_e_presenca entra na Regra #1 (D5): pessoa_id resolvido
--    pela porta única com os hints e-mail, nome e id do credenciamento
--    (participante_id = participantes.id), como Reservas_Agenda_APP e Check Ins
--    Summit (d5_5). As linhas já existentes passam pela porta uma vez: o trigger
--    só resolve quando pessoa_id está nulo.
select public.mind_pessoa_ligar_tabela('credenciamento_summit_2026.controle_de_inscritos_e_presenca',
  '{"emails":["email"],"nome":["nome"],"credenciamento_id":"participante_id"}');
update credenciamento_summit_2026.controle_de_inscritos_e_presenca
   set atualizado_em = atualizado_em
 where pessoa_id is null;

-- 3) presença, na forma final: a Worknet bipou o ingresso no dia OU check-in Yazo
--    em sala no dia (por e-mail, só quando o e-mail identifica um único ingresso
--    válido). Mesmo resultado da migration anterior, sem o ramo por e-mail.
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

-- 4) a leitura pedida pela Adriana: uma linha por ingresso, nome, e-mail, presença
--    por dia, tipo/origem do ingresso e patrocinador (que só existe em participantes).
create or replace view credenciamento_summit_2026.v_inscritos_e_presenca
  with (security_invoker = true) as
select c.nome,
       split_part(regexp_replace(btrim(c.nome), '\s+', ' ', 'g'), ' ', 1)                       as first_name,
       nullif(btrim(substr(regexp_replace(btrim(c.nome), '\s+', ' ', 'g'),
                           length(split_part(regexp_replace(btrim(c.nome), '\s+', ' ', 'g'), ' ', 1)) + 1)), '') as last_name,
       c.email,
       c.presenca_16_09 as status_16_09,
       c.presenca_17_09 as status_17_09,
       c.categoria      as tipo_de_ingresso,
       c.origem_ingresso as ticket_origin,
       p.sponsor_company
  from credenciamento_summit_2026.controle_de_inscritos_e_presenca c
  left join credenciamento_summit_2026.participantes p on p.id = c.participante_id;
comment on view credenciamento_summit_2026.v_inscritos_e_presenca is
  'Leitura do controle_de_inscritos_e_presenca: uma linha por ingresso (2.577) com nome, e-mail, presença em 16/09 e 17/09 (sim / ausente / cancelado), tipo e origem do ingresso e patrocinador (participantes.sponsor_company).';
