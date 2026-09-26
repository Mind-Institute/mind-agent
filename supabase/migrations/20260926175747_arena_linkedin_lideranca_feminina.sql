-- Adriana (26/09): "Liderança feminina em um futuro do trabalho líquido" (17/09, 16:00-16:50,
-- Arena LinkedIn, app 1038, d2-1600-curadoria) foi de Dani Junco, Liliane Rocha e Carolina Dostal,
-- conforme a tela de edição da programação no app. Nenhuma das três existia no cadastro; entram
-- com a bio do site (src/data/speakers.json; a da Dani Junco é idêntica à do app). Papel e formato
-- vêm do site (src/data/programacao.json): "Dani Junco, Liliane Rocha · Mediação: Carolina
-- Dostal", etiqueta "Painel". Idempotente.
insert into ecossistema.palestrantes_especialistas (nome, slug)
select v.nome, v.slug
  from (values ('Dani Junco', 'dani-junco'),
               ('Liliane Rocha', 'liliane-rocha'),
               ('Carolina Dostal', 'carolina-dostal')) as v(nome, slug)
 where not exists (select 1 from ecossistema.palestrantes_especialistas p where p.slug = v.slug);

update ecossistema.palestrantes_especialistas p
   set quem_e = v.quem_e, atualizado_em = now()
  from (values
    ('dani-junco', 'Fundadora e CEO da B2Mamy, plataforma que conecta marcas à maior comunidade materno-infantil do Brasil e que já impactou mais de 200 mil pessoas. Especialista em inovação, vendas e construção de comunidades, é palestrante, escritora, mentora de startups e conselheira. Reconhecida pela Exame entre as mulheres mais inovadoras do Brasil e pelo Meio & Mensagem entre as Women to Watch.'),
    ('liliane-rocha', 'Fundadora e CEO da Gestão Kairós, consultoria especializada em Sustentabilidade e Diversidade, com mais de 20 anos de carreira executiva. É conselheira do Instituto Tomie Ohtake, integra o Comitê de Impacto da Ambev e é docente da pós-graduação da PUCPR. Colunista da Época Negócios e da Vogue, é autora de Como ser uma liderança inclusiva e criadora do conceito Diversitywashing.'),
    ('carolina-dostal', 'Conselheira e especialista em Thought Leadership, Inteligência Artificial e AEO. Fundadora da Oitenta In e ex-diretora da ABRH-SP, já apoiou mais de mil executivos na construção de posicionamento e autoridade digital. Mentora e investidora-anjo, é coautora dos livros Mentores e suas histórias inspiradoras e Os Conselheiros, e lidera o ecossistema Conexão Protagonistas.')
  ) as v(slug, quem_e)
 where p.slug = v.slug
   and p.quem_e is distinct from v.quem_e;

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, case when p.slug = 'carolina-dostal' then 'mediacao' else 'palestrante' end
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where s.site_session_id = 'd2-1600-curadoria'
   and p.slug in ('dani-junco', 'liliane-rocha', 'carolina-dostal')
on conflict do nothing;

update summit_2026.sessions
   set tipo = 'painel', atualizado_em = now()
 where site_session_id = 'd2-1600-curadoria'
   and tipo is distinct from 'painel';
