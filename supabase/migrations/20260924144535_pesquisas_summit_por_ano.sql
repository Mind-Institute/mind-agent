-- Pesquisas do Mind Summit, uma tabela por pesquisa (aprovado pela Adriana em 24/09/2026 — D2: "uma tabela
-- para cada uma, uma tabela por ano, e depois comparar"; pediu também a comparação 2024 × 2025).
-- Cada linha é uma resposta. Toda resposta com e-mail tem mind_id resolvido pela porta única
-- mind_identidade_resolver ANTES da gravação (Regra #1). A resposta inteira fica em `respostas`
-- (pergunta → resposta, texto original); as perguntas que se repetem entre os anos viram colunas para comparar.
-- Nada disto vai para a memória do agente nem dispara contato (aceite de contato fica só registrado).

create table engagement.pesquisa_summit_2024 (
  id bigint generated always as identity primary key,
  resposta_ref text not null unique,              -- linha da planilha "Construa o Mind Summit conosco"
  respondido_em timestamptz,
  email_informado text,
  mind_id uuid references pessoas.pessoas(id),
  experiencia text,                                -- Mind / VIP / Prime / Camarote
  profissao text,
  nota_expectativa numeric,                        -- 0–5: quanto o Summit 2024 atendeu às expectativas
  nota_organizacao numeric,                        -- 1–5
  nota_conteudo numeric,                           -- 1–5: satisfação geral com o conteúdo
  nota_aplicabilidade numeric,                     -- 1–5: temas aplicáveis e úteis
  aceita_contato text,
  respostas jsonb not null,
  importado_em timestamptz not null default now()
);

create table engagement.pesquisa_summit_2025 (
  id bigint generated always as identity primary key,
  resposta_ref text not null unique,              -- linha da planilha "Sua voz importa — Mind Summit 2025"
  respondido_em timestamptz,
  email_informado text,
  mind_id uuid references pessoas.pessoas(id),
  experiencia text,
  profissao text,
  nps smallint,                                    -- 0–10
  nota_curadoria numeric,                          -- 1–5
  nota_organizacao numeric,                        -- 1–5: organização e logística
  nota_infraestrutura numeric,                     -- 1–5: conforto e infraestrutura
  nota_comunicacao numeric,                        -- 1–5
  nota_conteudo numeric,                           -- 1–5: satisfação geral com o conteúdo
  nota_aplicabilidade numeric,                     -- 1–5: temas aplicáveis e úteis
  interesse_continuar text,                        -- Sim / Talvez / Não
  aceita_contato text,
  respostas jsonb not null,
  importado_em timestamptz not null default now()
);

create table engagement.pesquisa_interesse_2025 (
  id bigint generated always as identity primary key,
  resposta_ref text not null unique,              -- ResponseId do Qualtrics
  respondido_em timestamptz,
  concluida boolean,
  email_informado text,                            -- só nas 149 enviadas por e-mail
  mind_id uuid references pessoas.pessoas(id),
  funcao text,
  respostas jsonb not null,
  importado_em timestamptz not null default now()
);

create index on engagement.pesquisa_summit_2024 (mind_id);
create index on engagement.pesquisa_summit_2025 (mind_id);
create index on engagement.pesquisa_interesse_2025 (mind_id);

alter table engagement.pesquisa_summit_2024 enable row level security;
alter table engagement.pesquisa_summit_2025 enable row level security;
alter table engagement.pesquisa_interesse_2025 enable row level security;
revoke all on engagement.pesquisa_summit_2024, engagement.pesquisa_summit_2025, engagement.pesquisa_interesse_2025 from anon, authenticated;

-- Comparação 2024 × 2025: só o que as duas pesquisas perguntaram igual (escala 1–5).
create view engagement.v_pesquisa_summit_2024_2025 with (security_invoker = true) as
with u as (
  select 2024 ano, mind_id, experiencia, nota_organizacao, nota_conteudo, nota_aplicabilidade from engagement.pesquisa_summit_2024
  union all
  select 2025, mind_id, experiencia, nota_organizacao, nota_conteudo, nota_aplicabilidade from engagement.pesquisa_summit_2025)
select ano,
       count(*) respostas,
       count(distinct mind_id) pessoas,
       round(avg(nota_organizacao), 2) media_organizacao,
       round(avg(nota_conteudo), 2) media_conteudo,
       round(avg(nota_aplicabilidade), 2) media_aplicabilidade,
       round(100.0 * count(*) filter (where nota_conteudo >= 4) / nullif(count(nota_conteudo), 0), 1) pct_conteudo_4_ou_5,
       round(100.0 * count(*) filter (where nota_aplicabilidade >= 4) / nullif(count(nota_aplicabilidade), 0), 1) pct_aplicabilidade_4_ou_5,
       count(distinct mind_id) filter (where mind_id in (select mind_id from engagement.pesquisa_summit_2024 where mind_id is not null)
                                          and mind_id in (select mind_id from engagement.pesquisa_summit_2025 where mind_id is not null)) responderam_os_dois_anos
  from u group by ano;

-- 2026: as avaliações do app continuam nas tabelas que o app grava; esta view só junta tudo num lugar.
create view engagement.pesquisa_summit_2026 with (security_invoker = true) as
select a.*, n.nota nps, n.comentario nps_comentario
  from engagement.avaliacao_do_evento a
  left join engagement.nps n on n.mind_id = a.mind_id and n.event_id is not distinct from a.event_id;

revoke all on engagement.v_pesquisa_summit_2024_2025, engagement.pesquisa_summit_2026 from anon, authenticated;
