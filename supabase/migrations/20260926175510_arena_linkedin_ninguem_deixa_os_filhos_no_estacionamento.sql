-- Adriana (26/09): "Ninguém deixa os filhos no estacionamento" (17/09, 12:30-13:30, Arena
-- LinkedIn, app 1021, d2-1230-curadoria) foi de Karina Melleu, Michele Torres e Luciana Cattony,
-- conforme a tela de edição da programação no app (que confirma o fim às 13:30 do banco; o site
-- diz 13:20). Nenhuma das três existia no cadastro; entram com a bio do site (src/data/speakers.json).
-- Papel e formato vêm do site (src/data/programacao.json): "Karina Melleu, Michele Torres ·
-- Mediação: Luciana Cattony", etiqueta "Painel". Idempotente.
insert into ecossistema.palestrantes_especialistas (nome, slug)
select v.nome, v.slug
  from (values ('Karina Melleu', 'karina-melleu'),
               ('Michele Torres', 'michele-torres'),
               ('Luciana Cattony', 'luciana-cattony')) as v(nome, slug)
 where not exists (select 1 from ecossistema.palestrantes_especialistas p where p.slug = v.slug);

update ecossistema.palestrantes_especialistas p
   set quem_e = v.quem_e, atualizado_em = now()
  from (values
    ('karina-melleu', 'Médica do trabalho, lidera a área de Health Management da TIM, onde é responsável pelas estratégias de saúde e bem-estar dos colaboradores e seus familiares. Especialista em Medicina do Trabalho pela Santa Casa de São Paulo e com MBA em Gestão de Saúde pela FGV, atua há mais de uma década em Recursos Humanos. Defende uma visão integral da saúde corporativa, que conecta bem-estar físico, mental, emocional, financeiro e espiritual.'),
    ('michele-torres', 'Senior Director de People & Organization para a América do Sul na EDP, com mais de 15 anos de experiência em gestão de pessoas, liderança e cultura. Atua em transformação organizacional, desenvolvimento de lideranças e construção de culturas de alta performance. Executiva e mãe de quatro filhos, defende uma liderança mais humana e inclusiva, capaz de conciliar parentalidade, desenvolvimento profissional, diversidade e resultados sustentáveis.'),
    ('luciana-cattony', 'Cofundadora da Consultoria Maternidade nas Empresas, pioneira no Brasil na valorização da parentalidade no ambiente corporativo, e do Pacto pela Parentalidade. Sua atuação conecta parentalidade e cuidado a temas centrais para as organizações, como saúde mental, bem-estar, equidade e segurança psicológica, mostrando como esse olhar também se traduz em liderança, cultura e resultados de negócio.')
  ) as v(slug, quem_e)
 where p.slug = v.slug
   and p.quem_e is distinct from v.quem_e;

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, case when p.slug = 'luciana-cattony' then 'mediacao' else 'palestrante' end
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where s.site_session_id = 'd2-1230-curadoria'
   and p.slug in ('karina-melleu', 'michele-torres', 'luciana-cattony')
on conflict do nothing;

update summit_2026.sessions
   set tipo = 'painel', atualizado_em = now()
 where site_session_id = 'd2-1230-curadoria'
   and tipo is distinct from 'painel';
