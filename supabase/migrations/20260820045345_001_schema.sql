create extension if not exists "uuid-ossp";
create extension if not exists vector;
create extension if not exists pg_trgm;

create table participantes (
  id                uuid primary key default uuid_generate_v4(),
  yazo_id           text unique,
  nome              text,
  email             text,
  telefone          text,
  empresa           text,
  cargo             text,
  trilha            text,
  idioma            text not null default 'pt-BR',
  anonimo           boolean not null default false,
  sincronizado_em   timestamptz,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);
create index on participantes (email);
create index on participantes (trilha);

create table identidade_fusoes (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid not null references participantes(id) on delete cascade,
  participante_origem uuid not null references participantes(id) on delete cascade,
  motivo            text not null,
  criado_em         timestamptz not null default now()
);

create table dispositivos (
  id                uuid primary key default uuid_generate_v4(),
  chave             text unique not null,
  user_agent        text,
  primeiro_acesso   timestamptz not null default now(),
  ultimo_acesso     timestamptz not null default now()
);

create table sessoes (
  id                uuid primary key default uuid_generate_v4(),
  dispositivo_id    uuid not null references dispositivos(id) on delete cascade,
  participante_id   uuid references participantes(id) on delete set null,
  token_hash        text not null,
  origem_identidade text not null,
  confianca         text not null default 'media',
  criada_em         timestamptz not null default now(),
  ultima_atividade  timestamptz not null default now(),
  expira_em         timestamptz not null
);
create index on sessoes (dispositivo_id, ultima_atividade desc);
create index on sessoes (participante_id);

create table conversas (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid references participantes(id) on delete cascade,
  dispositivo_id    uuid references dispositivos(id) on delete set null,
  canal             text not null default 'app',
  iniciada_em       timestamptz not null default now(),
  ultima_atividade  timestamptz not null default now(),
  encerrada_em      timestamptz
);
create index on conversas (participante_id, ultima_atividade desc);

create table mensagens (
  id                uuid primary key default uuid_generate_v4(),
  conversa_id       uuid not null references conversas(id) on delete cascade,
  participante_id   uuid references participantes(id) on delete cascade,
  papel             text not null,
  conteudo          text,
  blocos            jsonb,
  client_msg_id     text unique,
  origem            text not null default 'conversa',
  criado_em         timestamptz not null default now()
);
create index on mensagens (conversa_id, criado_em);

create table participante_memoria (
  id                    uuid primary key default uuid_generate_v4(),
  participante_id       uuid not null references participantes(id) on delete cascade,
  tipo                  text not null,
  chave                 text not null,
  valor                 jsonb not null,
  confianca             numeric(3,2) not null default 0.50,
  origem                text not null,
  evidencia_message_id  uuid references mensagens(id) on delete set null,
  status                text not null default 'proposta',
  valido_ate            timestamptz,
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now()
);
create unique index on participante_memoria (participante_id, chave)
  where status = 'ativa';
create index on participante_memoria (participante_id, status);

create table memoria_regras (
  chave             text primary key,
  tipo              text not null,
  pode_inferir      boolean not null default false,
  confianca_minima  numeric(3,2) not null default 0.80,
  ttl_dias          integer,
  descricao         text,
  ativo             boolean not null default true
);

create table agenda_espacos (
  id                uuid primary key default uuid_generate_v4(),
  yazo_id           text unique,
  nome              text not null,
  tipo              text,
  como_chegar       text,
  sincronizado_em   timestamptz
);

create table agenda_palestrantes (
  id                uuid primary key default uuid_generate_v4(),
  yazo_id           text unique,
  nome              text not null,
  cargo             text,
  organizacao       text,
  bio               text,
  foto_url          text,
  sincronizado_em   timestamptz
);

create table agenda_sessoes (
  id                uuid primary key default uuid_generate_v4(),
  yazo_id           text unique,
  titulo            text not null,
  descricao         text,
  dia               date not null,
  inicio            timestamptz not null,
  fim               timestamptz not null,
  espaco_id         uuid references agenda_espacos(id) on delete set null,
  tipo              text,
  trilhas           text[] not null default '{}',
  precisa_reserva   boolean not null default false,
  vagas_total       integer,
  vagas_disponiveis integer,
  sincronizado_em   timestamptz
);
create index on agenda_sessoes (dia, inicio);
create index on agenda_sessoes using gin (trilhas);

create table agenda_sessao_palestrantes (
  sessao_id         uuid references agenda_sessoes(id) on delete cascade,
  palestrante_id    uuid references agenda_palestrantes(id) on delete cascade,
  primary key (sessao_id, palestrante_id)
);

create table reservas (
  id                uuid primary key default uuid_generate_v4(),
  yazo_id           text unique,
  participante_id   uuid not null references participantes(id) on delete cascade,
  sessao_id         uuid not null references agenda_sessoes(id) on delete cascade,
  estado            text not null,
  criada_em         timestamptz not null default now(),
  sincronizado_em   timestamptz
);
create index on reservas (participante_id, estado);

create table conhecimento_fontes (
  id                uuid primary key default uuid_generate_v4(),
  nome              text not null,
  tipo              text not null,
  origem_url        text,
  ativo             boolean not null default true,
  sincronizado_em   timestamptz
);

create table conhecimento_docs (
  id                uuid primary key default uuid_generate_v4(),
  fonte_id          uuid not null references conhecimento_fontes(id) on delete cascade,
  titulo            text not null,
  corpo             text not null,
  metadata          jsonb not null default '{}',
  hash              text not null,
  atualizado_em     timestamptz not null default now()
);

create table conhecimento_trechos (
  id                uuid primary key default uuid_generate_v4(),
  doc_id            uuid not null references conhecimento_docs(id) on delete cascade,
  ordem             integer not null,
  texto             text not null,
  metadata          jsonb not null default '{}',
  embedding         vector(1536),
  tsv               tsvector generated always as (to_tsvector('portuguese', texto)) stored,
  stale             boolean not null default true,
  embedado_em       timestamptz
);
create index on conhecimento_trechos using ivfflat (embedding vector_cosine_ops) with (lists = 100);
create index on conhecimento_trechos using gin (tsv);
create index on conhecimento_trechos (doc_id, ordem);

create table config (
  chave             text primary key,
  valor             jsonb not null,
  descricao         text,
  atualizado_em     timestamptz not null default now(),
  atualizado_por    text
);

create table prompts (
  id                uuid primary key default uuid_generate_v4(),
  nome              text not null,
  versao            integer not null,
  conteudo          text not null,
  ativo             boolean not null default false,
  notas             text,
  criado_em         timestamptz not null default now(),
  criado_por        text,
  unique (nome, versao)
);
create unique index on prompts (nome) where ativo;

create table ferramentas (
  id                  uuid primary key default uuid_generate_v4(),
  nome                text unique not null,
  descricao           text not null,
  json_schema         jsonb not null,
  tipo_exec           text not null,
  destino             text,
  timeout_ms          integer not null default 6000,
  retries             integer not null default 1,
  escrita             boolean not null default false,
  requer_confirmacao  boolean not null default false,
  trilhas             text[] not null default '{}',
  ativo               boolean not null default true,
  versao              integer not null default 1
);

create table intencoes (
  id                uuid primary key default uuid_generate_v4(),
  nome              text unique not null,
  padroes           text[] not null default '{}',
  rota              text not null default 'llm',
  ferramenta        text references ferramentas(nome),
  effort            text not null default 'medium',
  exige_ferramenta  boolean not null default false,
  ativo             boolean not null default true
);

create table templates (
  id                uuid primary key default uuid_generate_v4(),
  chave             text not null,
  idioma            text not null default 'pt-BR',
  canal             text not null default 'app',
  texto             text not null,
  variaveis         text[] not null default '{}',
  ativo             boolean not null default true,
  unique (chave, idioma, canal)
);

create table feature_flags (
  chave             text primary key,
  ativo             boolean not null default false,
  publico           jsonb not null default '{}',
  descricao         text
);

create table config_revisao (
  id                integer primary key default 1,
  revisao           bigint not null default 1,
  atualizado_em     timestamptz not null default now(),
  check (id = 1)
);
insert into config_revisao (id) values (1) on conflict do nothing;

create or replace function bump_config_revisao() returns trigger
language plpgsql as $$
begin
  update config_revisao set revisao = revisao + 1, atualizado_em = now() where id = 1;
  return null;
end $$;

create trigger t_config_rev after insert or update or delete on config
  for each statement execute function bump_config_revisao();
create trigger t_prompts_rev after insert or update or delete on prompts
  for each statement execute function bump_config_revisao();
create trigger t_ferramentas_rev after insert or update or delete on ferramentas
  for each statement execute function bump_config_revisao();
create trigger t_intencoes_rev after insert or update or delete on intencoes
  for each statement execute function bump_config_revisao();
create trigger t_templates_rev after insert or update or delete on templates
  for each statement execute function bump_config_revisao();
create trigger t_flags_rev after insert or update or delete on feature_flags
  for each statement execute function bump_config_revisao();

create table ferramenta_chamadas (
  id                uuid primary key default uuid_generate_v4(),
  mensagem_id       uuid references mensagens(id) on delete set null,
  participante_id   uuid references participantes(id) on delete cascade,
  ferramenta        text not null,
  entrada           jsonb,
  saida             jsonb,
  status            text not null,
  http_status       integer,
  latencia_ms       integer,
  erro              text,
  idempotency_key   text,
  criado_em         timestamptz not null default now()
);
create unique index on ferramenta_chamadas (idempotency_key) where idempotency_key is not null;

create table regras_proativas (
  id                uuid primary key default uuid_generate_v4(),
  nome              text unique not null,
  gatilho           text not null,
  condicao          jsonb not null default '{}',
  template_chave    text not null,
  antecedencia_min  integer,
  publico           jsonb not null default '{}',
  canal             text not null default 'app',
  prioridade        integer not null default 5,
  cooldown_horas    integer not null default 6,
  limite_dia        integer not null default 2,
  janela_silenciosa jsonb not null default '{}',
  ativo             boolean not null default true
);

create table proativo_fila (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid not null references participantes(id) on delete cascade,
  regra_id          uuid not null references regras_proativas(id) on delete cascade,
  agendado_para     timestamptz not null,
  estado            text not null default 'agendado',
  motivo            text,
  canal             text not null default 'app',
  payload           jsonb not null default '{}',
  chave_dedupe      text,
  enviado_em        timestamptz,
  criado_em         timestamptz not null default now()
);
create unique index on proativo_fila (chave_dedupe) where chave_dedupe is not null;
create index on proativo_fila (estado, agendado_para);

create table enquetes (
  id                uuid primary key default uuid_generate_v4(),
  sessao_id         uuid references agenda_sessoes(id) on delete cascade,
  pergunta          text not null,
  opcoes            jsonb not null,
  aberta            boolean not null default false,
  criado_em         timestamptz not null default now()
);

create table enquete_respostas (
  id                uuid primary key default uuid_generate_v4(),
  enquete_id        uuid not null references enquetes(id) on delete cascade,
  participante_id   uuid not null references participantes(id) on delete cascade,
  opcao             text not null,
  criado_em         timestamptz not null default now(),
  unique (enquete_id, participante_id)
);

create table feedbacks (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid references participantes(id) on delete cascade,
  tipo              text not null,
  valor             text,
  contexto          jsonb not null default '{}',
  criado_em         timestamptz not null default now()
);

create table agente_eventos (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid references participantes(id) on delete cascade,
  conversa_id       uuid references conversas(id) on delete cascade,
  tipo              text not null,
  intencao          text,
  dados             jsonb not null default '{}',
  criado_em         timestamptz not null default now()
);
create index on agente_eventos (tipo, criado_em desc);

create table llm_chamadas (
  id                uuid primary key default uuid_generate_v4(),
  mensagem_id       uuid references mensagens(id) on delete set null,
  modelo            text not null,
  effort            text,
  tokens_entrada    integer,
  tokens_saida      integer,
  tokens_cache_read integer,
  tokens_cache_write integer,
  custo_usd         numeric(10,6),
  latencia_ms       integer,
  stop_reason       text,
  criado_em         timestamptz not null default now()
);

create table integracao_logs (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid references participantes(id) on delete set null,
  integracao        text not null,
  metodo            text,
  endpoint          text,
  payload           jsonb,
  resposta          jsonb,
  http_status       integer,
  latencia_ms       integer,
  erro              text,
  criado_em         timestamptz not null default now()
);
create index on integracao_logs (integracao, criado_em desc);

create table config_auditoria (
  id                uuid primary key default uuid_generate_v4(),
  tabela            text not null,
  registro_id       text,
  acao              text not null,
  antes             jsonb,
  depois            jsonb,
  autor             text,
  criado_em         timestamptz not null default now()
);

alter table participantes            enable row level security;
alter table identidade_fusoes        enable row level security;
alter table dispositivos             enable row level security;
alter table sessoes                  enable row level security;
alter table conversas                enable row level security;
alter table mensagens                enable row level security;
alter table participante_memoria     enable row level security;
alter table reservas                 enable row level security;
alter table ferramenta_chamadas      enable row level security;
alter table proativo_fila            enable row level security;
alter table enquete_respostas        enable row level security;
alter table feedbacks                enable row level security;
alter table agente_eventos           enable row level security;
alter table llm_chamadas             enable row level security;
alter table integracao_logs          enable row level security;
alter table config_auditoria         enable row level security;
