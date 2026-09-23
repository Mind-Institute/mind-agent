-- Reservas na agenda e check-ins do Summit, importados do app (Yazo) pelo painel
-- como "Reservas_Agenda_APP" (21.032 linhas) e "Check Ins Summit" (9.718 linhas).
-- O relatório do Yazo não traz id de pessoa nem de sessão: traz e-mail e o
-- nome/horário da sessão. Esta migration liga cada linha:
--   pessoa_id         -> id universal (pessoas.pessoas.id), pelo e-mail
--   participante_id   -> credenciamento_summit_2026.participantes.id, pelo e-mail
--   sessao_id         -> summit_2026.sessions.id, por nome + horário (FK real)
--   yazo_session_ids  -> id(s) da sessão no app, herdados de sessions.yazo_ids
-- Idempotente: pode rodar de novo quando o relatório for reimportado.

-- ---------------------------------------------------------------------------
-- colunas
alter table credenciamento_summit_2026."Reservas_Agenda_APP"
  add column if not exists agenda_inicio        timestamptz,
  add column if not exists criada_em            timestamptz,
  add column if not exists participante_id      uuid,
  add column if not exists pessoa_id            uuid,
  add column if not exists pessoa_criterio      text,
  add column if not exists pessoa_resolvido_em  timestamptz,
  add column if not exists sessao_id            uuid,
  add column if not exists yazo_session_ids     text[] not null default '{}',
  add column if not exists sessao_resolvida_em  timestamptz;

alter table credenciamento_summit_2026."Check Ins Summit"
  add column if not exists agenda_inicio        timestamptz,
  add column if not exists checkin_em           timestamptz,
  add column if not exists participante_id      uuid,
  add column if not exists pessoa_id            uuid,
  add column if not exists pessoa_criterio      text,
  add column if not exists pessoa_resolvido_em  timestamptz,
  add column if not exists sessao_id            uuid,
  add column if not exists yazo_session_ids     text[] not null default '{}',
  add column if not exists sessao_resolvida_em  timestamptz;

comment on column credenciamento_summit_2026."Reservas_Agenda_APP".pessoa_id is
  'Id universal da pessoa (pessoas.pessoas.id), resolvido pelo e-mail. Nulo enquanto a pessoa não passou pela resolução de identidade - participante_id aponta para ela mesmo assim.';
comment on column credenciamento_summit_2026."Reservas_Agenda_APP".yazo_session_ids is
  'Id(s) da sessão no app Yazo, herdados de summit_2026.sessions.yazo_ids. Dois ids quando a sessão foi duplicada no app por turma (masterclasses); um id específico quando o horário identifica a cópia.';
comment on column credenciamento_summit_2026."Check Ins Summit".pessoa_id is
  'Id universal da pessoa (pessoas.pessoas.id), resolvido pelo e-mail. Nulo enquanto a pessoa não passou pela resolução de identidade.';
comment on column credenciamento_summit_2026."Check Ins Summit".yazo_session_ids is
  'Id(s) da sessão no app Yazo, herdados de summit_2026.sessions.yazo_ids.';

create index if not exists reservas_agenda_app_email_idx  on credenciamento_summit_2026."Reservas_Agenda_APP" (lower(trim("Email")));
create index if not exists reservas_agenda_app_sessao_idx on credenciamento_summit_2026."Reservas_Agenda_APP" (sessao_id);
create index if not exists reservas_agenda_app_pessoa_idx on credenciamento_summit_2026."Reservas_Agenda_APP" (pessoa_id);
create index if not exists check_ins_summit_email_idx     on credenciamento_summit_2026."Check Ins Summit" (lower(trim("Email")));
create index if not exists check_ins_summit_sessao_idx    on credenciamento_summit_2026."Check Ins Summit" (sessao_id);
create index if not exists check_ins_summit_pessoa_idx    on credenciamento_summit_2026."Check Ins Summit" (pessoa_id);

-- ---------------------------------------------------------------------------
-- datas: o relatório escreve dd/mm/aaaa hh:mm:ss em horário de Brasília.
-- to_timestamp() lê como UTC; tira-se o timestamp cru e só então se diz que é de SP.
update credenciamento_summit_2026."Reservas_Agenda_APP"
   set agenda_inicio = ((to_timestamp("Início da agenda", 'DD/MM/YYYY HH24:MI:SS') at time zone 'UTC') at time zone 'America/Sao_Paulo'),
       criada_em     = case when coalesce("Data de criação reserva",'') <> ''
                            then ((to_timestamp("Data de criação reserva", 'DD/MM/YYYY HH24:MI:SS') at time zone 'UTC') at time zone 'America/Sao_Paulo') end
 where agenda_inicio is null;

update credenciamento_summit_2026."Check Ins Summit"
   set agenda_inicio = ((to_timestamp("Início da agenda", 'DD/MM/YYYY HH24:MI:SS') at time zone 'UTC') at time zone 'America/Sao_Paulo'),
       checkin_em    = case when coalesce("Data do checkin",'') <> ''
                            then ((to_timestamp("Data do checkin", 'DD/MM/YYYY HH24:MI:SS') at time zone 'UTC') at time zone 'America/Sao_Paulo') end
 where agenda_inicio is null;

-- ---------------------------------------------------------------------------
-- sessão por nome + início. A normalização de espaços existe porque o relatório
-- escreve "automação,  podem" com dois espaços em um dos títulos.
update credenciamento_summit_2026."Reservas_Agenda_APP" r
   set sessao_id = s.id, yazo_session_ids = s.yazo_ids, sessao_resolvida_em = now()
  from summit_2026.sessions s
 where r.sessao_id is null
   and regexp_replace(trim(s.titulo),'\s+',' ','g') = regexp_replace(trim(r."Agenda"),'\s+',' ','g')
   and s.inicio = r.agenda_inicio;

update credenciamento_summit_2026."Check Ins Summit" r
   set sessao_id = s.id, yazo_session_ids = s.yazo_ids, sessao_resolvida_em = now()
  from summit_2026.sessions s
 where r.sessao_id is null
   and regexp_replace(trim(s.titulo),'\s+',' ','g') = regexp_replace(trim(r."Agenda"),'\s+',' ','g')
   and s.inicio = r.agenda_inicio;

-- "Os 6 desalinhamentos do burnout" existe duas vezes no app (turma Vale x demais):
-- a cópia 1029 abre 15:00 e a 1060 abre 15:30. A de 15:30 é a mesma sessão real,
-- e o horário diz de qual cópia a linha veio.
update credenciamento_summit_2026."Reservas_Agenda_APP" r
   set sessao_id = s.id, yazo_session_ids = array['1060'], sessao_resolvida_em = now()
  from summit_2026.sessions s
 where s.site_session_id = 'd2-1500-desalinhamentos-burnout' and r.sessao_id is null
   and regexp_replace(trim(r."Agenda"),'\s+',' ','g') = 'Os 6 desalinhamentos do burnout: Como ler e redesenhar o trabalho do seu time'
   and r.agenda_inicio = timestamptz '2026-09-17 15:30-03';
update credenciamento_summit_2026."Reservas_Agenda_APP" r
   set yazo_session_ids = array['1029']
  from summit_2026.sessions s
 where r.sessao_id = s.id and s.site_session_id = 'd2-1500-desalinhamentos-burnout'
   and r.agenda_inicio = timestamptz '2026-09-17 15:00-03';

update credenciamento_summit_2026."Check Ins Summit" r
   set sessao_id = s.id, yazo_session_ids = array['1060'], sessao_resolvida_em = now()
  from summit_2026.sessions s
 where s.site_session_id = 'd2-1500-desalinhamentos-burnout' and r.sessao_id is null
   and regexp_replace(trim(r."Agenda"),'\s+',' ','g') = 'Os 6 desalinhamentos do burnout: Como ler e redesenhar o trabalho do seu time'
   and r.agenda_inicio = timestamptz '2026-09-17 15:30-03';
update credenciamento_summit_2026."Check Ins Summit" r
   set yazo_session_ids = array['1029']
  from summit_2026.sessions s
 where r.sessao_id = s.id and s.site_session_id = 'd2-1500-desalinhamentos-burnout'
   and r.agenda_inicio = timestamptz '2026-09-17 15:00-03';

-- uma linha do relatório de reservas veio com o título corrompido ("governan��a")
update credenciamento_summit_2026."Reservas_Agenda_APP" r
   set sessao_id = s.id, yazo_session_ids = s.yazo_ids, sessao_resolvida_em = now()
  from summit_2026.sessions s
 where r.sessao_id is null and s.site_session_id = 'd2-1020-obrigacao-gestao'
   and r."Agenda" like 'Da obrigação à gestão real: como construir governan%'
   and r.agenda_inicio = s.inicio;

-- ---------------------------------------------------------------------------
-- pessoa. O id universal mora em pessoas.pessoas; participantes.pessoa_id e
-- yazo_espelho.pessoa_id são cópias que a lane de identidade refaz (d5), então
-- a resolução lê a fonte. Quem não está lá fica como aguardando: identidade não
-- se inventa aqui. participante_id vem mesmo sem id universal: a pessoa existe.
update credenciamento_summit_2026."Reservas_Agenda_APP"
   set pessoa_criterio = 'aguardando resolucao de identidade', pessoa_resolvido_em = now()
 where pessoa_criterio is null;
update credenciamento_summit_2026."Check Ins Summit"
   set pessoa_criterio = 'aguardando resolucao de identidade', pessoa_resolvido_em = now()
 where pessoa_criterio is null;

with mapa as (
  select lower(trim(email)) as email, count(distinct id) as n, min(id::text)::uuid as pessoa
    from pessoas.pessoas where fundida_em is null and coalesce(email,'') <> '' group by 1
)
update credenciamento_summit_2026."Reservas_Agenda_APP" x
   set pessoa_id = case when m.n=1 then m.pessoa end,
       pessoa_criterio = case when m.n=1 then 'email:pessoas.pessoas' else 'email ambiguo em pessoas.pessoas' end,
       pessoa_resolvido_em = now()
  from mapa m where lower(trim(x."Email")) = m.email;

with mapa as (
  select lower(trim(email)) as email, count(distinct id) as n, min(id::text)::uuid as pessoa
    from pessoas.pessoas where fundida_em is null and coalesce(email,'') <> '' group by 1
)
update credenciamento_summit_2026."Check Ins Summit" x
   set pessoa_id = case when m.n=1 then m.pessoa end,
       pessoa_criterio = case when m.n=1 then 'email:pessoas.pessoas' else 'email ambiguo em pessoas.pessoas' end,
       pessoa_resolvido_em = now()
  from mapa m where lower(trim(x."Email")) = m.email;

with mapa as (
  select lower(trim(email)) as email, min(id::text)::uuid as participante
    from credenciamento_summit_2026.participantes where coalesce(email,'') <> '' group by 1
)
update credenciamento_summit_2026."Reservas_Agenda_APP" x set participante_id = m.participante
  from mapa m where lower(trim(x."Email")) = m.email and x.participante_id is null;

with mapa as (
  select lower(trim(email)) as email, min(id::text)::uuid as participante
    from credenciamento_summit_2026.participantes where coalesce(email,'') <> '' group by 1
)
update credenciamento_summit_2026."Check Ins Summit" x set participante_id = m.participante
  from mapa m where lower(trim(x."Email")) = m.email and x.participante_id is null;

-- ---------------------------------------------------------------------------
-- a ligação com a programação vira chave estrangeira: o banco recusa sessao_id
-- que não exista e não deixa apagar sessão com reserva ou check-in apontando.
alter table credenciamento_summit_2026."Reservas_Agenda_APP"
  drop constraint if exists reservas_agenda_app_sessao_fk,
  add constraint reservas_agenda_app_sessao_fk
    foreign key (sessao_id) references summit_2026.sessions(id) on delete restrict;
alter table credenciamento_summit_2026."Check Ins Summit"
  drop constraint if exists check_ins_summit_sessao_fk,
  add constraint check_ins_summit_sessao_fk
    foreign key (sessao_id) references summit_2026.sessions(id) on delete restrict;
