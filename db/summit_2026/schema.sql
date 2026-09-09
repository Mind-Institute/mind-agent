-- =============================================================================
-- Mind Summit 2026 — schema declarativo da BASE DE CONHECIMENTO  (schema: summit_2026)
-- -----------------------------------------------------------------------------
-- FONTE DECLARATIVA PARA REVISÃO — **ainda NÃO aplicada em produção**.
-- Espelha o catálogo aprovado no plano. Cada tabela tem UM papel; nomes em PT
-- consistentes; uma casa por conceito (sem duplicar verdade).
--
-- Convenções:
--   • [SYNC]    = espelhado do git do site (mindsummit2026/src/data/*.json); o sync
--                 NUNCA sobrescreve campos [AUTORADO]. Carrega proveniência.
--   • [AUTORADO]= escrito no banco (Adriana/curadoria); o sync não toca.
--   • Preço/%-vendido/datas NÃO moram aqui — são LIVE em `mind-summit-propostas`
--     (rwqdperfphubzteckyqd), sempre no fuso America/Sao_Paulo.
--   • Palestrante canônico = ecossistema.palestrantes_especialistas (ADR 0001).
-- =============================================================================

create schema if not exists summit_2026;

-- Colunas de proveniência padrão das tabelas [SYNC] (comentadas por tabela):
--   origem text default 'site-git', commit_sha text, sincronizado_em timestamptz.

-- -----------------------------------------------------------------------------
-- evento — [SYNC/curado] 1 linha: o Mind Summit 2026
-- Responde: "o que é / quando / onde é o evento".
-- -----------------------------------------------------------------------------
create table if not exists summit_2026.evento (
  id                    uuid primary key default gen_random_uuid(),
  slug                  text not null unique,                 -- 'mind-summit-2026'
  nome                  text not null,
  dias                  date[] not null,                      -- [2026-09-16, 2026-09-17]
  local                 text not null,                        -- 'São Paulo Expo'
  cidade                text not null default 'São Paulo',
  fuso                  text not null default 'America/Sao_Paulo',
  endereco              jsonb not null default '{}'::jsonb,
  transporte            text,
  posicionamento_ancora text,                                 -- resumo curto; detalhe vive em `posicionamento`
  ativo                 boolean not null default true,
  atualizado_em         timestamptz not null default now(),
  linha_unica           boolean not null default true unique  -- trava: só 1 evento neste schema
);

-- -----------------------------------------------------------------------------
-- locais — [SYNC/curado] arenas, salas, lounges, alimentação, serviços, logística,
--          acessos e zonas de assento (Mind/VIP/Prime como filhas da Arena Mind).
-- Responde: "o que tem no local / onde fica X / alimentação / estacionamento /
--            acessibilidade".
-- -----------------------------------------------------------------------------
create table if not exists summit_2026.locais (
  id               uuid primary key default gen_random_uuid(),
  slug             text not null unique,
  nome             text not null,
  tipo             text not null,        -- arena | sala | lounge | alimentacao | servico | acesso | logistica | ativacao | zona_assento
  parent_id        uuid references summit_2026.locais(id),   -- hierarquia (zona de assento -> arena)
  tier             text,                 -- p/ zona_assento: mind | vip | prime
  andar            text,
  capacidade       integer,
  como_chegar      text,
  coordenadas_mapa jsonb not null default '{}'::jsonb,
  acessibilidade   jsonb not null default '{}'::jsonb,
  ativo            boolean not null default true,
  origem           text not null default 'site-git',
  commit_sha       text,
  sincronizado_em  timestamptz,
  atualizado_em    timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- sessoes — [SYNC] a grade. tipo/formato/duração DERIVADOS (nunca hardcoded).
-- Responde: "programação: o que rola, quando, em que espaço"; "online × presencial".
-- Chave estável = id do site (ex.: 'd1-09_00-abertura').
-- -----------------------------------------------------------------------------
create table if not exists summit_2026.sessoes (
  id               text primary key,                          -- id estável do site
  titulo           text not null,
  super_titulo     text,
  subtitulo        text,
  descricao        text,
  dia              date not null,
  inicio           timestamptz,                               -- gravado em UTC; exibir em America/Sao_Paulo
  fim              timestamptz,
  duracao_min      integer,                                   -- derivado do tipo, como o site
  espaco_id        uuid references summit_2026.locais(id),
  tipo             text,                                      -- palestra | painel | workshop | masterclass | experiencia
  formato          text,
  tiers            text[] not null default '{}',              -- acesso por tier: {mind,vip,prime}
  precisa_reserva  boolean not null default false,
  online           boolean not null default false,           -- FATO (não decidir "alardear")
  origem           text not null default 'site-git',
  commit_sha       text,
  sincronizado_em  timestamptz
);

-- -----------------------------------------------------------------------------
-- sessao_expectativa — [AUTORADO] 1:1 com sessoes. "O que esperar" para o
--          concierge RECOMENDAR. Separado de sessoes p/ o sync nunca sobrescrever.
-- Responde: "o que esperar dessa sessão / vale pra mim".
-- -----------------------------------------------------------------------------
create table if not exists summit_2026.sessao_expectativa (
  sessao_id     text primary key references summit_2026.sessoes(id) on delete cascade,
  o_que_esperar text,                                         -- o que a pessoa vai viver/aprender
  para_quem     text,                                         -- perfil que mais se beneficia
  por_que_ir    text,
  topicos       text[] not null default '{}',
  resultados    text[] not null default '{}',
  nivel         text,                                         -- introdutorio | intermediario | avancado
  atualizado_em timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- sessao_palestrantes — [SYNC (link) + FK canônica] papel do palestrante na sessão.
-- Responde: "quem palestra em tal sessão / onde a Amy fala".
-- -----------------------------------------------------------------------------
create table if not exists summit_2026.sessao_palestrantes (
  sessao_id   text   not null references summit_2026.sessoes(id) on delete cascade,
  speaker_id  bigint not null references ecossistema.palestrantes_especialistas(id),
  papel       text   not null default 'palestrante',         -- palestrante | moderador | ...
  ordem       integer not null default 0,
  primary key (sessao_id, speaker_id)
);

-- -----------------------------------------------------------------------------
-- experiencias — [SYNC] as áreas/experiências curadas.
-- Responde: "quais experiências existem / o que é o Prime Lounge".
-- -----------------------------------------------------------------------------
create table if not exists summit_2026.experiencias (
  id               text primary key,                          -- slug do site
  nome             text not null,
  tipo             text,
  espaco_id        uuid references summit_2026.locais(id),
  tier_selo        text,                                      -- 'Todos' | 'VIP' | 'Prime'
  chamada          text,
  narrativa        text,
  midia            text,
  ordem            integer not null default 0,
  origem           text not null default 'site-git',
  commit_sha       text,
  sincronizado_em  timestamptz
);

-- -----------------------------------------------------------------------------
-- ingressos — [SYNC] identidade do tier. SEM preço/%-vendido/datas/CHECKOUT: tudo isso
-- vive junto na CAMADA COMERCIAL (espelho de mind-summit-propostas):
--   • ticket_categories.checkout_url + slug  → o link de cada tier
--   • lote_precos / lotes                    → preço por lote + datas
--   • pricing_tiers                          → descontos de delegação (min_ingressos → off%)
-- `categoria_preco` = chave p/ casar com `ticket_categories.slug` (o agente pega link/preço lá).
-- Responde: "diferença entre ingressos" (junto com ingresso_inclusoes).
-- -----------------------------------------------------------------------------
create table if not exists summit_2026.ingressos (
  id               text primary key,                          -- mind | vip | prime
  nome             text not null,
  tagline          text,
  badge            text,
  simbolo          text,
  accent           text,
  para_quem        text,                                      -- persona resumida (RH/Gestor/Liderança…)
  categoria_preco  text,                                      -- chave -> ticket_categories.slug (checkout/preço/desconto vivem lá)
  ordem            integer not null default 0,
  origem           text not null default 'site-git',
  commit_sha       text,
  sincronizado_em  timestamptz
);

-- -----------------------------------------------------------------------------
-- ingresso_inclusoes — [SYNC] matriz tier × benefício (compare.json).
-- Responde: "o que o VIP inclui / o que muda do Mind pro Prime".
-- -----------------------------------------------------------------------------
create table if not exists summit_2026.ingresso_inclusoes (
  id       bigint generated always as identity primary key,
  grupo    text not null,          -- 'Acesso ao evento' | 'Aprendizado prático' | ...
  rotulo   text not null,          -- 'Workshops VIP de 2 horas'
  mind     text,                   -- '✓' | '—' | texto
  vip      text,
  prime    text,
  ordem    integer not null default 0,
  origem   text not null default 'site-git',
  commit_sha text,
  sincronizado_em timestamptz
);

-- -----------------------------------------------------------------------------
-- patrocinadores — [AUTORADO] patrocinadores e apoiadores. Preenchível aos poucos.
-- Responde: "quem patrocina/apoia e o que traz ao Mind".
-- (≠ participantes.sponsor_company, que é o comprador do ingresso — fora daqui.)
-- -----------------------------------------------------------------------------
create table if not exists summit_2026.patrocinadores (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null,
  tipo          text not null default 'patrocinador',        -- patrocinador | apoiador | parceiro
  descricao     text,                                        -- quem é / o que traz ao Mind
  logo          text,
  site_url      text,
  ordem         integer not null default 0,
  ativo         boolean not null default true,
  atualizado_em timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- posicionamento — [AUTORADO por Adriana] posição do Mind por ÂNGULO.
-- Também acolhe o "por que vale / objeções" por ingresso via `alvo`.
-- Responde: "posição do Mind / por que importa"; "por que o VIP vale".
-- É POSIÇÃO (fato), não instrução de pitch — o playbook decide o uso.
-- -----------------------------------------------------------------------------
create table if not exists summit_2026.posicionamento (
  id            uuid primary key default gen_random_uuid(),
  angulo        text not null,          -- performance | nr1_risco | cultura | lideranca | ...
  alvo          text,                   -- null=geral | 'ingresso:vip' | 'experiencia:masterclasses' ...
  titulo        text,
  texto         text not null,
  ordem         integer not null default 0,
  atualizado_em timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- recursos — [AUTORADO/curado] catálogo de ENTREGÁVEIS que o agente PODE entregar
-- (calculadora, vídeo, arte, esquema, PDF, link). INSUMO para o agente DECIDIR
-- se/quando entregar: o que faz, o que inclui, vantagem × desvantagem, quando
-- ajuda × quando atrapalha. Nunca uma ordem de entregar.
-- Responde: "tem arte/vídeo/calculadora sobre X pra entregar? e quando vale?".
-- -----------------------------------------------------------------------------
create table if not exists summit_2026.recursos (
  id               uuid primary key default gen_random_uuid(),
  chave            text not null unique,        -- 'calculadora_delegacao' | 'video_masterclasses' | 'arte_diferenca_ingressos' | 'programacao_pdf' | 'mapa' ...
  tipo             text not null,               -- calculadora | video | arte | esquema | pdf | link | imagem
  titulo           text not null,
  assunto          text[] not null default '{}',        -- sobre o que é (tags livres)
  ancoras          jsonb  not null default '{}'::jsonb,  -- {ingresso?, experiencia?, sessao_id?, tema?}
  o_que_faz        text,                        -- o que exatamente entrega/mostra
  o_que_inclui     text,
  vantagens        text,
  desvantagens     text,
  quando_ajuda     text,                        -- situações/intenções em que entregar ajuda
  quando_atrapalha text,                        -- quando atrapalha / melhor não entregar
  url              text,                        -- link OU referência ao asset
  formato_entrega  text,                        -- link | arquivo | imagem_inline | midia_whatsapp
  tier_escopo      text[] not null default '{}',
  ativo            boolean not null default true,
  atualizado_em    timestamptz not null default now()
);

-- =============================================================================
-- Conhecimento p/ RAG (insumos indexados). O índice físico (documents+chunks+
-- embeddings) vive na camada `knowledge` (decisão de nome na migração). Abaixo:
-- as fontes autoradas/estruturadas que são indexadas com âncoras.
-- =============================================================================

-- faq — [SYNC/curado] Q&A operacional. Insumo estruturado; também indexado no RAG.
create table if not exists summit_2026.faq (
  id              bigint generated always as identity primary key,
  categoria       text,                 -- ingressos | experiencias | logistica | app | ...
  pergunta        text not null,
  resposta        text not null,
  relacionadas    text[] not null default '{}',
  tier_escopo     text[] not null default '{}',
  origem          text not null default 'site-git',
  commit_sha      text,
  sincronizado_em timestamptz,
  atualizado_em   timestamptz not null default now()
);

-- atendimento — [AUTORADO] fatos de atendimento importantes (marcados por
-- importância). Insumo — NÃO uma ordem de "sempre dizer".
create table if not exists summit_2026.atendimento (
  id            uuid primary key default gen_random_uuid(),
  tema          text,
  texto         text not null,
  importancia   smallint not null default 0,   -- 0..3 (peso do insumo)
  ancoras       jsonb not null default '{}'::jsonb,  -- {sessao_id?, tier?, local_id?, ...}
  atualizado_em timestamptz not null default now()
);

-- transcricoes — [AUTORADO] transcrições/descrições de palestra (você sobe).
-- Corpo longo p/ RAG; âncora à sessão.
create table if not exists summit_2026.transcricoes (
  id            uuid primary key default gen_random_uuid(),
  sessao_id     text references summit_2026.sessoes(id) on delete set null,
  titulo        text,
  corpo         text not null,
  fonte         text,
  atualizado_em timestamptz not null default now()
);

-- =============================================================================
-- Notas de retrieval:
--   • ESTRUTURADO primeiro; RAG (faq/atendimento/transcricoes/logística-prosa)
--     só no long-tail. O vetor NUNCA é fonte de preço/inclusão/horário.
--   • Índice RAG (chunks/embeddings) guarda ÂNCORAS: {sessao_id, tier, local_id,
--     speaker_id, tema, tipo, commit_sha} — busca filtrável e citável.
--   • logística = atributos de `locais` + prosa indexada (sem tabela própria).
-- =============================================================================
