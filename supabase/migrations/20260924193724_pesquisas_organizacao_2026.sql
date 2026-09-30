-- Organização das pesquisas (Adriana, 24/09/2026).
-- 1) Saem duas tabelas vazias e sem uso: engagement.feedbacks e engagement.avaliacao_execucoes (0 linhas, nenhuma
--    função, visão ou código as usa). As outras quatro vazias (engagement.nps, crm.pessoa_nps, engagement.sessao_feedback,
--    engagement.evento_feedback) ficam: ainda são lidas por crm.contexto_comercial, mind.esquecer_participante,
--    api.my_data, concierge.resumo_do_dia e visões do concierge.
-- 2) As avaliações do app de 2026 (29 respostas, formulário antigo) passam a se chamar engagement.avaliacao_app_2026.
-- 3) A pesquisa pós-evento de 2026 vira engagement.pesquisa_summit_2026, no mesmo padrão de 2024 e 2025, na Regra #1.
-- 4) Uma visão só para comparar os anos: engagement.v_pesquisa_summit_comparativo (substitui v_pesquisa_summit_2024_2025).
-- DESFAZER:
--   create table engagement.feedbacks (id uuid default uuid_generate_v4() primary key, mind_id uuid references pessoas.pessoas(id) on delete cascade,
--     tipo text not null, valor text, contexto jsonb not null default '{}', criado_em timestamptz not null default now());
--   create table engagement.avaliacao_execucoes (id uuid default uuid_generate_v4() primary key, avaliacao_id uuid not null references engagement.avaliacoes(id) on delete cascade,
--     provedor text not null, modelo text not null, resposta text, passou boolean, notas text, custo_usd numeric(10,6), latencia_ms integer, criado_em timestamptz not null default now());
--   drop view engagement.v_pesquisa_summit_comparativo; drop table engagement.pesquisa_summit_2026; alter view engagement.avaliacao_app_2026 rename to pesquisa_summit_2026;

drop table engagement.feedbacks;
drop table engagement.avaliacao_execucoes;

alter view engagement.pesquisa_summit_2026 rename to avaliacao_app_2026;

create table engagement.pesquisa_summit_2026 (
  id bigint generated always as identity primary key,
  resposta_ref text not null unique,              -- id da resposta no formulário
  respondido_em timestamptz,
  email_informado text,
  mind_id uuid references pessoas.pessoas(id),
  experiencia text,                                -- Mind / VIP / Prime / Camarote
  profissao text,
  nps smallint check (nps between 0 and 10),       -- 0–10, mesma pergunta de 2025
  nota_curadoria numeric check (nota_curadoria between 1 and 5),
  nota_organizacao numeric check (nota_organizacao between 1 and 5),
  nota_infraestrutura numeric check (nota_infraestrutura between 1 and 5),
  nota_comunicacao numeric check (nota_comunicacao between 1 and 5),
  nota_conteudo numeric check (nota_conteudo between 1 and 5),
  nota_aplicabilidade numeric check (nota_aplicabilidade between 1 and 5),
  interesse_continuar text,
  aceita_contato text,
  respostas jsonb not null,                        -- a resposta inteira: pergunta → resposta, texto original
  importado_em timestamptz not null default now()
);
create index on engagement.pesquisa_summit_2026 (mind_id);
alter table engagement.pesquisa_summit_2026 enable row level security;
revoke all on engagement.pesquisa_summit_2026 from anon, authenticated;
select public.mind_pessoa_ligar_tabela('engagement.pesquisa_summit_2026', '{"emails":["email_informado"]}');

drop view engagement.v_pesquisa_summit_2024_2025;
create view engagement.v_pesquisa_summit_comparativo with (security_invoker = true) as
with u as (
  select 2024 ano, mind_id, null::smallint nps, nota_organizacao, null::numeric nota_infraestrutura, null::numeric nota_comunicacao,
         nota_conteudo, nota_aplicabilidade from engagement.pesquisa_summit_2024
  union all
  select 2025, mind_id, nps, nota_organizacao, nota_infraestrutura, nota_comunicacao, nota_conteudo, nota_aplicabilidade from engagement.pesquisa_summit_2025
  union all
  select 2026, mind_id, nps, nota_organizacao, nota_infraestrutura, nota_comunicacao, nota_conteudo, nota_aplicabilidade from engagement.pesquisa_summit_2026)
select ano,
       count(*) respostas,
       count(distinct mind_id) pessoas,
       round(100.0 * (count(*) filter (where nps >= 9) - count(*) filter (where nps <= 6)) / nullif(count(nps), 0)) nps,
       count(nps) respostas_nps,
       round(avg(nota_organizacao), 2) media_organizacao,
       round(avg(nota_infraestrutura), 2) media_infraestrutura,
       round(avg(nota_comunicacao), 2) media_comunicacao,
       round(avg(nota_conteudo), 2) media_conteudo,
       round(avg(nota_aplicabilidade), 2) media_aplicabilidade,
       round(100.0 * count(*) filter (where nota_organizacao >= 4) / nullif(count(nota_organizacao), 0), 1) pct_organizacao_4_ou_5,
       round(100.0 * count(*) filter (where nota_infraestrutura >= 4) / nullif(count(nota_infraestrutura), 0), 1) pct_infraestrutura_4_ou_5,
       round(100.0 * count(*) filter (where nota_comunicacao >= 4) / nullif(count(nota_comunicacao), 0), 1) pct_comunicacao_4_ou_5,
       round(100.0 * count(*) filter (where nota_conteudo >= 4) / nullif(count(nota_conteudo), 0), 1) pct_conteudo_4_ou_5,
       round(100.0 * count(*) filter (where nota_aplicabilidade >= 4) / nullif(count(nota_aplicabilidade), 0), 1) pct_aplicabilidade_4_ou_5
  from u group by ano;
revoke all on engagement.v_pesquisa_summit_comparativo, engagement.avaliacao_app_2026 from anon, authenticated;
