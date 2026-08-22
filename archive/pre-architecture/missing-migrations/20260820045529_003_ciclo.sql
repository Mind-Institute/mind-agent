create table taxonomia (
  id            uuid primary key default uuid_generate_v4(),
  tipo          text not null,
  codigo        text not null,
  rotulo        text not null,
  sinonimos     text[] not null default '{}',
  pai           text,
  ativo         boolean not null default true,
  unique (tipo, codigo)
);
create unique index taxonomia_codigo_uk on taxonomia (codigo);
create index on taxonomia (tipo) where ativo;

create table participante_objetivos (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid not null references participantes(id) on delete cascade,
  pergunta_guia     text not null,
  dor_codigo        text references taxonomia(codigo),
  area_codigo       text,
  decisao_pendente  text,
  prazo             text,
  status            text not null default 'ativo',
  definido_em       timestamptz not null default now(),
  revisado_em       timestamptz,
  evidencia_message_id uuid references mensagens(id) on delete set null
);
create index on participante_objetivos (participante_id, status);

create table ciclo_estado (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid not null references participantes(id) on delete cascade,
  objetivo_id       uuid references participante_objetivos(id) on delete cascade,
  etapa             text not null default 'entender',
  atualizado_em     timestamptz not null default now(),
  unique (participante_id, objetivo_id)
);

create table perguntas_feitas (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid not null references participantes(id) on delete cascade,
  chave             text not null,
  conversa_id       uuid references conversas(id) on delete set null,
  respondida        boolean not null default false,
  recusada          boolean not null default false,
  feita_em          timestamptz not null default now(),
  unique (participante_id, chave)
);

create table recomendacoes (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid not null references participantes(id) on delete cascade,
  objetivo_id       uuid references participante_objetivos(id) on delete set null,
  tipo              text not null default 'sessao',
  sessao_id         uuid references agenda_sessoes(id) on delete cascade,
  referencia        text,
  justificativa     text not null,
  origem            text not null default 'agente',
  estado            text not null default 'oferecida',
  mensagem_id       uuid references mensagens(id) on delete set null,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);
create index on recomendacoes (participante_id, estado);
create index on recomendacoes (sessao_id);

create table sessao_feedback (
  id                  uuid primary key default uuid_generate_v4(),
  participante_id     uuid not null references participantes(id) on delete cascade,
  sessao_id           uuid not null references agenda_sessoes(id) on delete cascade,
  objetivo_id         uuid references participante_objetivos(id) on delete set null,
  nota                integer check (nota between 0 and 10),
  relevancia          text,
  insight             text,
  intencao_aplicar    text,
  o_que_faltou        text,
  comentario          text,
  conversa_id         uuid references conversas(id) on delete set null,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  unique (participante_id, sessao_id)
);
create index on sessao_feedback (sessao_id, nota);

create table evento_feedback (
  id                uuid primary key default uuid_generate_v4(),
  participante_id   uuid references participantes(id) on delete set null,
  categoria         text not null,
  sentimento        text not null,
  severidade        integer not null default 1 check (severidade between 1 and 5),
  comentario        text,
  local             text,
  mensagem_id       uuid references mensagens(id) on delete set null,
  tratado           boolean not null default false,
  criado_em         timestamptz not null default now()
);
create index on evento_feedback (severidade desc, tratado, criado_em desc);

create table sinais_comerciais (
  id                  uuid primary key default uuid_generate_v4(),
  participante_id     uuid not null references participantes(id) on delete cascade,
  area_codigo         text references taxonomia(codigo),
  produto_codigo      text,
  forca               text not null,
  evidencia_texto     text not null,
  mensagem_id         uuid references mensagens(id) on delete set null,
  contato_solicitado  boolean not null default false,
  consentimento_em    timestamptz,
  canal_preferido     text,
  status              text not null default 'novo',
  observacao          text,
  criado_em           timestamptz not null default now()
);
create index on sinais_comerciais (forca, status, criado_em desc);
create index on sinais_comerciais (participante_id);

create view v_funil_valor as
select
  (select count(*) from participantes where not anonimo)                     as participantes,
  (select count(distinct participante_id) from participante_objetivos
     where status = 'ativo')                                                 as com_objetivo,
  (select count(distinct participante_id) from recomendacoes)                as receberam_recomendacao,
  (select count(distinct participante_id) from recomendacoes
     where estado in ('aceita','agendada','compareceu'))                     as aceitaram,
  (select count(distinct participante_id) from sessao_feedback)              as avaliaram,
  (select count(distinct participante_id) from sinais_comerciais
     where forca in ('media','alta'))                                        as com_sinal_comercial;

create view v_operacao_agora as
select categoria, severidade, count(*) as ocorrencias, max(criado_em) as ultima
from evento_feedback
where tratado = false and criado_em > now() - interval '3 hours'
group by categoria, severidade
order by severidade desc, ocorrencias desc;

create view v_sessoes_avaliadas as
select s.id, s.titulo, s.dia, count(f.*) as respostas,
       round(avg(f.nota)::numeric, 1) as nota_media
from agenda_sessoes s
left join sessao_feedback f on f.sessao_id = s.id
group by s.id, s.titulo, s.dia
order by s.dia, s.inicio;

alter table participante_objetivos enable row level security;
alter table ciclo_estado           enable row level security;
alter table perguntas_feitas       enable row level security;
alter table recomendacoes          enable row level security;
alter table sessao_feedback        enable row level security;
alter table evento_feedback        enable row level security;
alter table sinais_comerciais      enable row level security;
