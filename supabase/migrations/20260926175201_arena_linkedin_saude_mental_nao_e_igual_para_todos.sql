-- Adriana (26/09): "Saúde mental não é igual para todos" (16/09, 16:00-16:50, Arena LinkedIn,
-- app 1002, d1-1600-curadoria) foi de Arthur Lima, Daniel Leal e Luiz Gustavo Ribeiro, conforme
-- a tela de edição da programação no app. Nenhum dos três existia no cadastro de palestrantes.
-- Papel e formato vêm do site do Summit (Mind-Institute/mindsummit2026, src/data/programacao.json):
-- "Arthur Lima, Daniel Leal · Mediação: Luiz Gustavo Ribeiro", etiqueta "Painel". Bio em quem_e é
-- a do site (src/data/speakers.json), idêntica à do app para Arthur Lima. Idempotente.
insert into ecossistema.palestrantes_especialistas (nome, slug)
select v.nome, v.slug
  from (values ('Arthur Lima', 'arthur-lima'),
               ('Daniel Leal', 'daniel-leal'),
               ('Luiz Gustavo Ribeiro', 'luiz-gustavo-ribeiro')) as v(nome, slug)
 where not exists (select 1 from ecossistema.palestrantes_especialistas p where p.slug = v.slug);

update ecossistema.palestrantes_especialistas p
   set quem_e = v.quem_e, atualizado_em = now()
  from (values
    ('arthur-lima', 'Fundador e CEO da AfroSaúde, pesquisador em saúde digital no CIDACS/Fiocruz Bahia e doutorando em Medicina e Saúde pela UFBA. Atua na interseção entre saúde mental, inovação e equidade, desenvolvendo soluções para a gestão de riscos psicossociais nas organizações. Reconhecido como MIT Innovator Under 35, integra iniciativas do Pacto Global da ONU no Brasil voltadas à saúde e ao futuro do trabalho.'),
    ('daniel-leal', 'Estrategista criativo, produtor e LinkedIn Top Voice, com trabalhos para marcas como Coca-Cola, Google Cloud, Globo, Disney e Itaú. Atua especialmente nos temas de criatividade, inovação, diversidade e novas formas de comunicação no mundo do trabalho. É criador, produtor executivo e diretor da série Conversas que Inspiram, disponível no Canal Futura e Globoplay.'),
    ('luiz-gustavo-ribeiro', 'Trabalha na interseção entre creator economy, comunidades e o futuro do trabalho. É Gerente Sênior de Creators no LinkedIn, jornalista, professor da ESPM e acompanha de perto como a influência está transformando carreiras e negócios.')
  ) as v(slug, quem_e)
 where p.slug = v.slug
   and p.quem_e is distinct from v.quem_e;

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, case when p.slug = 'luiz-gustavo-ribeiro' then 'mediacao' else 'palestrante' end
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where s.site_session_id = 'd1-1600-curadoria'
   and p.slug in ('arthur-lima', 'daniel-leal', 'luiz-gustavo-ribeiro')
on conflict do nothing;

update summit_2026.sessions
   set tipo = 'painel', atualizado_em = now()
 where site_session_id = 'd1-1600-curadoria'
   and tipo is distinct from 'painel';
