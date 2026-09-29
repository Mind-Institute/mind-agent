-- Adriana (26/09): "Como incorporar a saúde mental à gestão de equipes" (16/09, 12:30-13:20,
-- Arena LinkedIn, app 983) foi de Eymi Rocha, Simone Nascimento e Ana Prado, conforme a tela
-- de edição da programação no app. Nenhuma das três existia no cadastro de palestrantes
-- (ecossistema.palestrantes_especialistas); entram só com nome e slug, como Clarissa Daroit e
-- Flavio Boan em 20260923300000. Idempotente.
insert into ecossistema.palestrantes_especialistas (nome, slug)
select v.nome, v.slug
  from (values ('Eymi Rocha', 'eymi-rocha'),
               ('Simone Nascimento', 'simone-nascimento'),
               ('Ana Prado', 'ana-prado')) as v(nome, slug)
 where not exists (select 1 from ecossistema.palestrantes_especialistas p where p.slug = v.slug);

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, 'palestrante'
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where s.site_session_id = 'd1-1230-curadoria'
   and p.slug in ('eymi-rocha', 'simone-nascimento', 'ana-prado')
on conflict do nothing;
