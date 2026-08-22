-- ============================================================
-- crm.pessoas_interno — o que orienta, mas nao se diz
-- ============================================================
-- Tabela separada de propósito. crm.buscar_pessoa (a porta dos bots
-- voltados ao cliente) nao alcanca este conteudo: a barreira e
-- estrutural, nao uma instrucao de prompt que um jeito de perguntar
-- consegue contornar.
--
-- Campos escolhidos por preenchimento real (11.536 contatos):
--   origem original e origem da ultima interacao ... 100%
--   negocios associados .......................... 50,0%
--   dono no CRM ................................. 22,9%
--   primeira pagina vista ......................... 9,9%
--   utm_source / medium / campaign ............. 8,0 / 7,0 / 6,6%
--   ultimo contato ................................ 5,3%
--   perfil do cliente ............................. 3,8%
--   status de lead ................................ 3,1%
--   descadastro de e-mail ......................... 0,9%
-- Fora: score de cadencia e origem Clint, ambos 0%.

create table if not exists crm.pessoas_interno (
  pessoa_id uuid primary key references crm.pessoas(id) on delete cascade,

  -- Onde a pessoa chegou primeiro e por onde veio da última vez.
  -- Os dois vêm preenchidos em 100% dos contatos; os utm_* abaixo são o
  -- detalhe fino, presente em menos de 10% — servem para enriquecer,
  -- nunca como base de contagem.
  origem_primeira text,
  origem_ultima text,
  primeira_url text,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_content text,
  utm_term text,

  -- Quem cuida da pessoa e em que pé está a relação comercial.
  -- dono_nome existe para o agente falar "a Fernanda está cuidando"
  -- sem precisar resolver um identificador numérico.
  dono_id text,
  dono_nome text,
  status_lead text,
  negocios_associados integer,
  ultimo_contato_em timestamptz,
  perfil_cliente text,

  -- Sinal de consentimento: descadastrado não deve receber abordagem.
  descadastrado_email boolean not null default false,

  sincronizado_em timestamptz,
  atualizado_em timestamptz not null default now()
);

comment on table crm.pessoas_interno is
  'Sinais internos por pessoa: origem, dono, estagio comercial, engajamento. Orienta o tom e o argumento dos agentes; nunca e recitado ao usuario final.';
comment on column crm.pessoas_interno.origem_primeira is
  'Origem original do contato no HubSpot (100% preenchida). Versao confiavel do "onde a pessoa chegou primeiro".';
comment on column crm.pessoas_interno.utm_source is
  'Detalhe de campanha do primeiro contato. Preenchido em ~8% da base: serve para enriquecer um caso, nao para medir a base.';
comment on column crm.pessoas_interno.descadastrado_email is
  'Pessoa pediu para nao receber e-mail. Sinal de consentimento: respeitar antes de qualquer abordagem.';

create index if not exists pessoas_interno_dono_idx on crm.pessoas_interno (dono_id) where dono_id is not null;

-- ------------------------------------------------------------
-- NPS por produto. Uma pessoa responde uma vez por produto, e a nota de
-- 2025 nao deve ser confundida com a de 2026 — por isso a chave inclui
-- o produto, em vez de uma coluna solta em pessoas_interno.
--
-- AINDA SEM FONTE: a propriedade de NPS do HubSpot esta 100% vazia.
-- A tabela nasce pronta e vazia, em vez de a base fingir que tem NPS.
-- ------------------------------------------------------------
create table if not exists crm.pessoa_nps (
  pessoa_id uuid not null references crm.pessoas(id) on delete cascade,
  produto_codigo text not null references catalogo.produtos(codigo),
  nota smallint check (nota between 0 and 10),
  comentario text,
  respondido_em timestamptz,
  fonte text,
  primary key (pessoa_id, produto_codigo)
);

comment on table crm.pessoa_nps is
  'NPS por pessoa e por produto. Sem fonte conectada ainda: o campo de NPS do HubSpot esta vazio em toda a base.';

alter table crm.pessoas_interno enable row level security;
alter table crm.pessoa_nps enable row level security;
