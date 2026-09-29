-- Adriana (26/09): "O que levamos de casa para o trabalho" (17/09, 11:30-12:20, Arena LinkedIn,
-- app 1018, d2-1130-curadoria) foi de Ivana Moreira, Marcos Trindade e Ana Drummond, conforme a
-- tela de edição da programação no app. Marcos e Ana não existiam no cadastro; entram com a bio
-- do app (idêntica à do site, src/data/speakers.json). Ivana Moreira já existe (slug
-- ivana-moreira) e fica como está. Papel e formato vêm do site (src/data/programacao.json):
-- "Marcos Trindade, Ana Drummond · Mediação: Ivana Moreira", etiqueta "Painel". Idempotente.
insert into ecossistema.palestrantes_especialistas (nome, slug)
select v.nome, v.slug
  from (values ('Marcos Trindade', 'marcos-trindade'),
               ('Ana Drummond', 'ana-drummond')) as v(nome, slug)
 where not exists (select 1 from ecossistema.palestrantes_especialistas p where p.slug = v.slug);

update ecossistema.palestrantes_especialistas p
   set quem_e = v.quem_e, atualizado_em = now()
  from (values
    ('marcos-trindade', 'Sócio e CEO da FSB Holding, ecossistema de gestão de reputação que reúne marcas como FSB Comunicação, Loures, Giusti, JotaCom, Nexus, Beon e Bússola. É também fundador do Rituaali Clínica & Spa, dedicado à saúde e ao bem-estar integral. Administrador de empresas, com pós-graduação em Finanças, é especialista em planejamento e gestão de crises.'),
    ('ana-drummond', 'Ana Drummond é Diretora-Presidente da Fundação Maria Cecilia Souto Vidigal, onde atua para fortalecer políticas públicas e mobilizar a sociedade em torno da primeira infância. Com mais de 20 anos de atuação no terceiro setor, liderou a Childhood Brasil por mais de 15 anos e foi Diretora Institucional do Instituto Vencer o Câncer. Administradora pela FAAP e mestre pela Universidade Luigi Bocconi, também é cofundadora da startup social Somos Todas Marias.')
  ) as v(slug, quem_e)
 where p.slug = v.slug
   and p.quem_e is distinct from v.quem_e;

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, case when p.slug = 'ivana-moreira' then 'mediacao' else 'palestrante' end
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where s.site_session_id = 'd2-1130-curadoria'
   and p.slug in ('ivana-moreira', 'marcos-trindade', 'ana-drummond')
on conflict do nothing;

update summit_2026.sessions
   set tipo = 'painel', atualizado_em = now()
 where site_session_id = 'd2-1130-curadoria'
   and tipo is distinct from 'painel';
