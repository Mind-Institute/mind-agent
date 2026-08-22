create schema if not exists mind;
create schema if not exists platform;
create schema if not exists concierge;
create schema if not exists api;

comment on schema mind      is 'Conhecimento do Mind: verdade para qualquer agente. Nenhum agente lê daqui direto — o acesso é por api.*';
comment on schema platform  is 'Infra compartilhada de agentes: provedores de LLM, embeddings, custo.';
comment on schema concierge is 'O agente do Mind Summit. Comportamento, memória e jornada — nada aqui é verdade institucional.';
comment on schema api       is 'Mind Intelligence API: o contrato. Estável enquanto mind.* muda por baixo.';

alter table agenda_espacos              set schema mind;
alter table agenda_palestrantes         set schema mind;
alter table agenda_sessoes              set schema mind;
alter table agenda_sessao_palestrantes  set schema mind;
alter table conhecimento_fontes         set schema mind;
alter table conhecimento_docs           set schema mind;
alter table conhecimento_trechos        set schema mind;
alter table taxonomia                   set schema mind;
alter table mecanismos                  set schema mind;
alter table regras_evento               set schema mind;
alter table politicas                   set schema mind;
alter table consentimentos              set schema mind;
alter table solicitacoes_titular        set schema mind;
alter table participantes               set schema mind;
alter table reservas                    set schema mind;
alter table enquetes                    set schema mind;
alter table enquete_respostas           set schema mind;

alter table mind.agenda_espacos             rename to locations;
alter table mind.agenda_palestrantes        rename to speakers;
alter table mind.agenda_sessoes             rename to sessions;
alter table mind.agenda_sessao_palestrantes rename to session_speakers;
alter table mind.conhecimento_fontes        rename to knowledge_sources;
alter table mind.conhecimento_docs          rename to knowledge_documents;
alter table mind.conhecimento_trechos       rename to knowledge_chunks;
alter table mind.taxonomia                  rename to taxonomy;
alter table mind.mecanismos                 rename to mechanisms;
alter table mind.regras_evento              rename to event_rules;
alter table mind.politicas                  rename to policies;
alter table mind.consentimentos             rename to consents;
alter table mind.solicitacoes_titular       rename to data_requests;
alter table mind.participantes              rename to people;
alter table mind.reservas                   rename to session_reservations;
alter table mind.enquetes                   rename to polls;
alter table mind.enquete_respostas          rename to poll_answers;

comment on table mind.people is
  'A MESMA pessoa é lead do B2C, participante do Summit e cliente do CS. Três cadastros seriam três verdades.';
comment on table mind.consents is
  'Consentimento é do titular, não do agente. Dois agentes pedindo o mesmo consentimento duas vezes é falha legal, não de UX.';

create table mind.events (
  id            uuid primary key default uuid_generate_v4(),
  slug          text unique not null,
  nome          text not null,
  dias          date[] not null default '{}',
  local         text,
  cidade        text,
  fuso          text not null default 'America/Sao_Paulo',
  ativo         boolean not null default true
);
insert into mind.events (slug, nome, dias, local, cidade) values
('mind-summit-2026', 'Mind Summit 2026', '{2026-09-16,2026-09-17}',
 'Transamérica Expo Center — Pavilhão 3', 'São Paulo');

alter table mind.sessions   add column if not exists event_id uuid references mind.events(id);
alter table mind.locations  add column if not exists event_id uuid references mind.events(id);
alter table mind.event_rules add column if not exists event_id uuid references mind.events(id);
update mind.sessions    set event_id = (select id from mind.events where slug='mind-summit-2026');
update mind.locations   set event_id = (select id from mind.events where slug='mind-summit-2026');
update mind.event_rules set event_id = (select id from mind.events where slug='mind-summit-2026');

create table mind.registrations (
  id                uuid primary key default uuid_generate_v4(),
  person_id         uuid not null references mind.people(id) on delete cascade,
  event_id          uuid not null references mind.events(id) on delete cascade,
  ticket_category   text,
  external_ref      text,
  status            text not null default 'ativa',
  criado_em         timestamptz not null default now(),
  unique (person_id, event_id)
);
comment on column mind.registrations.ticket_category is
  'O catálogo de categorias vive em mind-summit-propostas.ticket_categories. Aqui é referência, não cópia.';

insert into mind.registrations (person_id, event_id, ticket_category)
select p.id, e.id, p.trilha
from mind.people p cross join mind.events e
where e.slug = 'mind-summit-2026' and p.trilha is not null;
alter table mind.people drop column if exists trilha;

alter table llm_provedores    set schema platform;
alter table llm_modelos       set schema platform;
alter table llm_rotas         set schema platform;
alter table embeddings_config set schema platform;
alter table llm_chamadas      set schema platform;

alter table platform.llm_provedores rename to llm_providers;
alter table platform.llm_modelos    rename to llm_models;
alter table platform.llm_rotas      rename to llm_routes;
alter table platform.llm_chamadas   rename to llm_calls;

alter table platform.llm_calls add column if not exists agent text not null default 'concierge';

alter table conversas              set schema concierge;
alter table mensagens              set schema concierge;
alter table dispositivos           set schema concierge;
alter table sessoes                set schema concierge;
alter table identidade_fusoes      set schema concierge;
alter table verificacoes_email     set schema concierge;
alter table participante_memoria   set schema concierge;
alter table participante_contexto  set schema concierge;
alter table participante_objetivos set schema concierge;
alter table memoria_regras         set schema concierge;
alter table memoria_bloqueios      set schema concierge;
alter table ciclo_estado           set schema concierge;
alter table perguntas_feitas       set schema concierge;
alter table recomendacoes          set schema concierge;
alter table sessao_feedback        set schema concierge;
alter table evento_feedback        set schema concierge;
alter table sinais_comerciais      set schema concierge;
alter table jornada_eventos        set schema concierge;
alter table jornada_sessao         set schema concierge;
alter table motivos_ausencia       set schema concierge;
alter table nps_summit             set schema concierge;
alter table dossies                set schema concierge;
alter table tutorial_passos        set schema concierge;
alter table prompts                set schema concierge;
alter table ferramentas            set schema concierge;
alter table intencoes              set schema concierge;
alter table templates              set schema concierge;
alter table feature_flags          set schema concierge;
alter table regras_proativas       set schema concierge;
alter table proativo_fila          set schema concierge;
alter table config                 set schema concierge;
alter table config_revisao         set schema concierge;
alter table config_auditoria       set schema concierge;
alter table agente_eventos         set schema concierge;
alter table ferramenta_chamadas    set schema concierge;
alter table integracao_logs        set schema concierge;
alter table feedbacks              set schema concierge;
alter table avaliacoes             set schema concierge;
alter table avaliacao_execucoes    set schema concierge;

alter table concierge.sessoes    rename to agent_sessions;
alter table concierge.nps_summit rename to nps;
alter table concierge.nps add column if not exists event_id uuid references mind.events(id);
update concierge.nps set event_id = (select id from mind.events where slug='mind-summit-2026');

alter view v_funil_valor       set schema concierge;
alter view v_operacao_agora    set schema concierge;
alter view v_sessoes_avaliadas set schema concierge;
alter view v_conflitos_agenda  set schema concierge;
alter view v_sessoes_jornada   set schema concierge;
alter view v_demanda_frustrada set schema concierge;
alter view v_aderencia_por_area set schema concierge;

alter function bump_config_revisao()     set schema concierge;
alter function aplicar_evento_jornada()  set schema concierge;
alter function resumo_do_dia(uuid, date) set schema concierge;
alter function esquecer_participante(uuid) set schema mind;

alter function concierge.bump_config_revisao()      set search_path = concierge, mind, public;
alter function concierge.aplicar_evento_jornada()   set search_path = concierge, mind, public;
alter function concierge.resumo_do_dia(uuid, date)  set search_path = concierge, mind, public;
alter function mind.esquecer_participante(uuid)     set search_path = mind, concierge, public;

create or replace function api.event(p_slug text default 'mind-summit-2026')
returns jsonb language sql stable security definer set search_path = mind, public as $$
  select jsonb_build_object('slug', e.slug, 'nome', e.nome, 'dias', e.dias,
                            'local', e.local, 'cidade', e.cidade, 'fuso', e.fuso,
                            'regras', (select coalesce(jsonb_agg(jsonb_build_object(
                                          'chave', r.chave, 'titulo', r.titulo, 'texto', r.texto)), '[]')
                                       from mind.event_rules r
                                       where r.event_id = e.id and r.ativo))
  from mind.events e where e.slug = p_slug and e.ativo;
$$;

create or replace function api.sessions(
  p_event text default 'mind-summit-2026',
  p_dia   date default null,
  p_tema  text default null,
  p_limit integer default 50)
returns jsonb language sql stable security definer set search_path = mind, public as $$
  select coalesce(jsonb_agg(x order by x->>'inicio'), '[]') from (
    select jsonb_build_object(
      'id', s.id, 'titulo', s.titulo, 'descricao', s.descricao,
      'dia', s.dia, 'inicio', s.inicio, 'fim', s.fim,
      'tipo', s.tipo, 'formato', s.formato, 'nivel', s.nivel,
      'espaco', l.nome, 'vaga_limitada', s.precisa_reserva,
      'trilhas', s.trilhas, 'topicos', s.topicos_aprendizado,
      'quem', (select coalesce(jsonb_agg(sp.nome), '[]')
               from mind.session_speakers ss
               join mind.speakers sp on sp.id = ss.palestrante_id
               where ss.sessao_id = s.id)) as x
    from mind.sessions s
    left join mind.locations l on l.id = s.espaco_id
    join mind.events e on e.id = s.event_id and e.slug = p_event
    where (p_dia is null or s.dia = p_dia)
      and (p_tema is null or s.topicos_aprendizado ? p_tema)
    order by s.dia, s.inicio
    limit p_limit) t;
$$;

create or replace function api.speakers(p_event text default 'mind-summit-2026')
returns jsonb language sql stable security definer set search_path = mind, public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'nome', sp.nome, 'cargo', sp.cargo, 'organizacao', sp.organizacao,
           'bio', sp.bio, 'foto', sp.foto_url)), '[]')
  from mind.speakers sp
  where exists (select 1 from mind.session_speakers ss
                join mind.sessions s on s.id = ss.sessao_id
                join mind.events e on e.id = s.event_id and e.slug = p_event
                where ss.palestrante_id = sp.id);
$$;

create or replace function api.knowledge(p_pergunta text, p_limit integer default 6)
returns jsonb language sql stable security definer set search_path = mind, public as $$
  select coalesce(jsonb_agg(x), '[]') from (
    select jsonb_build_object(
      'texto', c.texto, 'documento', d.titulo, 'fonte', f.nome,
      'tipo', d.tipo_conteudo, 'url', d.url) as x
    from mind.knowledge_chunks c
    join mind.knowledge_documents d on d.id = c.doc_id
    join mind.knowledge_sources f on f.id = d.fonte_id
    where f.ativo and d.ativo and not c.stale
      and c.tsv @@ plainto_tsquery('portuguese', p_pergunta)
    order by ts_rank(c.tsv, plainto_tsquery('portuguese', p_pergunta)) desc
    limit p_limit) t;
$$;

comment on schema api is
  'Mind Intelligence API. Preço, lote e cupom NÃO estão aqui: vivem em mind-summit-propostas, que serve o site em tempo real. Quando entrarem, entram como função desta API — nunca como cópia de tabela.';

revoke usage on schema mind, platform, concierge, api from anon, authenticated;
revoke all on all tables in schema mind, platform, concierge, api from anon, authenticated;
revoke all on all functions in schema mind, platform, concierge, api from anon, authenticated;

do $$
declare t record;
begin
  for t in select schemaname, tablename from pg_tables
            where schemaname in ('mind','platform','concierge','public')
  loop
    execute format('alter table %I.%I enable row level security', t.schemaname, t.tablename);
  end loop;
end $$;

alter default privileges in schema mind, platform, concierge, api
  revoke all on tables from anon, authenticated;
alter default privileges in schema mind, platform, concierge, api
  revoke all on functions from anon, authenticated;
