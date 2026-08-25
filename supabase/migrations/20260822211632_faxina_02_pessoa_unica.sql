-- Faxina passo 2: uma pessoa so.
-- mind.people era o hub real do grafo de pessoa: 33 FKs apontavam para ela,
-- inclusive crm.consents. crm.pessoas tinha 0 linhas e 0 FKs.
-- Aqui a linha migra preservando o MESMO uuid, entao as 33 filhas nao mudam
-- de dado -- so mudam de alvo. mind.people vira view de compatibilidade.

-- ---------------------------------------------------------------- identidade
create table if not exists engagement.identidades (
  id             uuid primary key default gen_random_uuid(),
  pessoa_id      uuid not null references crm.pessoas(id) on delete cascade,
  canal          text not null,
  identificador  text not null,
  verificado     boolean not null default false,
  confianca      text,
  criado_em      timestamptz not null default now(),
  constraint identidades_canal_ck check (canal in
    ('whatsapp','email','yazo','eduzz','hubspot','dispositivo','treble_session','telefone')),
  constraint identidades_unica unique (canal, identificador)
);
comment on table engagement.identidades is
  'Resolve telefone, session_external_id do Treble, e-mail do HubSpot, id da Eduzz e dispositivo_id do site para UMA pessoa em crm.pessoas.';
create index if not exists identidades_pessoa_ix on engagement.identidades(pessoa_id);

-- idioma e anonimo sao perfil de canal, nao sao atributo de CRM.
create table if not exists engagement.pessoa_perfil (
  pessoa_id  uuid primary key references crm.pessoas(id) on delete cascade,
  idioma     text,
  anonimo    boolean not null default false
);

-- ------------------------------------------------------- migra a unica linha
insert into crm.pessoas (id, email, whatsapp, primeiro_nome, sobrenome,
                         empresa, cargo, origem, criado_em, atualizado_em)
select p.id,
       nullif(lower(btrim(p.email)), ''),
       nullif(btrim(coalesce(p.telefone, '')), ''),
       nullif(split_part(btrim(p.nome), ' ', 1), ''),
       nullif(btrim(substr(btrim(p.nome), length(split_part(btrim(p.nome), ' ', 1)) + 1)), ''),
       p.empresa, p.cargo, 'manual', p.criado_em, p.atualizado_em
from mind.people p;

insert into engagement.pessoa_perfil (pessoa_id, idioma, anonimo)
select p.id, p.idioma, coalesce(p.anonimo, false) from mind.people p;

insert into engagement.identidades (pessoa_id, canal, identificador, verificado)
select p.id, 'yazo', p.yazo_id, true from mind.people p where p.yazo_id is not null;

insert into engagement.identidades (pessoa_id, canal, identificador, verificado)
select p.id, 'email', lower(btrim(p.email)), false
from mind.people p where nullif(btrim(coalesce(p.email, '')), '') is not null;

-- --------------------------------------------- as 33 FKs mudam de alvo
do $$
declare r record; v_del text; v_upd text;
begin
  for r in
    select c.conname, c.conrelid::regclass::text as tbl, a.attname as col,
           c.confdeltype, c.confupdtype
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f'
      and c.confrelid = 'mind.people'::regclass
      and array_length(c.conkey, 1) = 1
  loop
    v_del := case r.confdeltype when 'c' then ' on delete cascade'
                                when 'n' then ' on delete set null'
                                when 'r' then ' on delete restrict'
                                when 'd' then ' on delete set default' else '' end;
    v_upd := case r.confupdtype when 'c' then ' on update cascade'
                                when 'n' then ' on update set null'
                                when 'r' then ' on update restrict' else '' end;
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    execute format('alter table %s add constraint %I foreign key (%I) references crm.pessoas(id)%s%s',
                   r.tbl, r.conname, r.col, v_del, v_upd);
  end loop;
end $$;

-- ------------------------------------- mind.people vira view sobre crm.pessoas
drop view if exists concierge.v_funil_valor;
drop table mind.people;

create view mind.people as
select p.id,
       (select i.identificador from engagement.identidades i
         where i.pessoa_id = p.id and i.canal = 'yazo' limit 1)        as yazo_id,
       nullif(btrim(concat_ws(' ', p.primeiro_nome, p.sobrenome)), '') as nome,
       p.email,
       p.whatsapp                                                     as telefone,
       p.empresa,
       p.cargo,
       f.idioma,
       coalesce(f.anonimo, false)                                     as anonimo,
       p.sincronizado_em,
       p.criado_em,
       p.atualizado_em
from crm.pessoas p
left join engagement.pessoa_perfil f on f.pessoa_id = p.id;

comment on view mind.people is
  'COMPATIBILIDADE: a pessoa mora em crm.pessoas. Esta view existe so para as 6 funcoes que ainda leem mind.people. Cai na migration final da faxina.';

create view concierge.v_funil_valor as
 select (select count(*) from mind.people where not people.anonimo) as participantes,
    (select count(distinct participante_objetivos.participante_id)
       from concierge.participante_objetivos
      where participante_objetivos.status = 'ativo') as com_objetivo,
    (select count(distinct recomendacoes.participante_id)
       from concierge.recomendacoes) as receberam_recomendacao,
    (select count(distinct recomendacoes.participante_id)
       from concierge.recomendacoes
      where recomendacoes.estado = any (array['aceita','agendada','compareceu'])) as aceitaram,
    (select count(distinct sessao_feedback.participante_id)
       from concierge.sessao_feedback) as avaliaram,
    (select count(distinct sinais_comerciais.participante_id)
       from concierge.sinais_comerciais
      where sinais_comerciais.forca = any (array['media','alta'])) as com_sinal_comercial;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'mind_agent') then
    grant select on mind.people to mind_agent;
    grant select on engagement.identidades, engagement.pessoa_perfil to mind_agent;
  end if;
end $$;

-- ------------------------------------------- conserta api.my_data, ja quebrada
-- Ela lia mind.consents, que deixou de existir quando consents foi para o crm.
create or replace function api.my_data(p_token text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'concierge', 'mind', 'crm', 'public'
as $function$
  with eu as (select api.quem_sou(p_token) as id)
  select jsonb_build_object(
    'perfil',    (select jsonb_build_object('nome', p.nome, 'email', p.email,
                          'empresa', p.empresa, 'cargo', p.cargo)
                  from mind.people p, eu where p.id = eu.id),
    'memoria',   (select coalesce(jsonb_agg(jsonb_build_object(
                          'chave', m.chave, 'valor', m.valor, 'origem', m.origem)), '[]')
                  from concierge.participante_memoria m, eu
                  where m.participante_id = eu.id and m.status = 'ativa'),
    'objetivos', (select coalesce(jsonb_agg(o.pergunta_guia), '[]')
                  from concierge.participante_objetivos o, eu where o.participante_id = eu.id),
    'insights',  (select coalesce(jsonb_agg(f.insight), '[]')
                  from concierge.sessao_feedback f, eu
                  where f.participante_id = eu.id and f.insight is not null),
    'consentimentos', (select coalesce(jsonb_agg(jsonb_build_object(
                          'finalidade', k.finalidade, 'concedido', k.concedido,
                          'em', k.criado_em)), '[]')
                  from crm.consents k, eu where k.participante_id = eu.id));
$function$;
