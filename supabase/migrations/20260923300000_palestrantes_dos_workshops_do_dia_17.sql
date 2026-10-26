-- Adriana (23/09): "Bem-estar começa na agenda" foi de Esabela Cruz, Clarissa Daroit
-- e Igor Gomes Menezes (era a Adriana; o Igor a substituiu); "O líder como
-- arquiteto do trabalho" foi do Flavio Boan. Clarissa e Flavio não existiam no
-- cadastro de palestrantes (ecossistema.palestrantes_especialistas); entram só
-- com nome e slug. Idempotente.
insert into ecossistema.palestrantes_especialistas (nome, slug, instituicao)
select 'Clarissa Daroit', 'clarissa-daroit', 'Mais Diversidade'
 where not exists (select 1 from ecossistema.palestrantes_especialistas where slug = 'clarissa-daroit');
insert into ecossistema.palestrantes_especialistas (nome, slug)
select 'Flavio Boan', 'flavio-boan'
 where not exists (select 1 from ecossistema.palestrantes_especialistas where slug = 'flavio-boan');

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, 'palestrante'
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where (s.titulo like 'Bem-estar começa na agenda%' and p.slug in ('esabela-cruz', 'clarissa-daroit', 'igor-gomes-menezes'))
    or (s.titulo like 'O líder como arquiteto do trabalho%' and p.slug = 'flavio-boan')
on conflict do nothing;
