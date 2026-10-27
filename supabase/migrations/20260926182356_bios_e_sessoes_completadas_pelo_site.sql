-- Adriana (26/09): completar pelo site do Summit (Mind-Institute/mindsummit2026) o que faltava.
-- 1. Bios (src/data/speakers.json) de Clarissa Daroit e Flavio Boan, que estavam sem quem_e.
-- 2. Pessoas das sessões que estavam vazias ou incompletas, como o site lista em
--    src/data/programacao.json ("who"). Todos já existem no cadastro. Papel 'palestrante', como nas
--    demais sessões de autógrafo/abertura do banco (o site não indica outro papel).
--    d1-0900-abertura              Abertura (16/09)                 Ivana Moreira
--    d1-1330-autografos-autores    Autógrafos com os autores (16/09) Denize Savi, Tamara Myles, Izabella Camargo,
--                                                                    Yuri Trafane, Fernanda Catena, João Yosef Torres, Veruska Galvão
--    d1-1700-autografos-autores    Autógrafos com os autores (16/09) Michelle Schneider, Stela Campos, Renata Rivetti,
--                                                                    Oscar de Bos, Ana Claudia Quintana Arantes
--    d2-1330-autografos-carla      Autógrafos com os autores (17/09) + Edna Goldoni, Arthur Guerra, Daniel de Barros,
--                                                                    Alana Anijar (Carla Tieppo já estava)
--    d2-1700-autografo-ana-vazquez Autógrafo Ana Vazquez (17/09)     Ana Vazquez
--    d2-1700-autografos-autores    Autógrafos com os autores (17/09) Vini Kitahara, Denise Salvador, Ana Vazquez
-- Idempotente.
update ecossistema.palestrantes_especialistas p
   set quem_e = v.quem_e, atualizado_em = now()
  from (values
    ('clarissa-daroit', 'Comunicadora, especialista em Neurociências e Comportamento e Chief Happiness Officer certificada. Diretora na Mais Diversidade e à frente da Happiness 360, atua há 20 anos em Recursos Humanos, conectando ciência, estratégia e gestão de pessoas. Nos projetos que lidera, posiciona inclusão, pertencimento e inovação como alavancas estratégicas para construir organizações onde pessoas e negócios prosperam juntos.'),
    ('flavio-boan', 'Engenheiro e mestre em Engenharia de Produção pela UFMG, com mais de 30 anos de experiência em gestão, governança e transformação organizacional. Foi sócio sênior da Falconi Consultoria entre 2014 e 2024. Atua como conselheiro e consultor independente, com foco em governança corporativa, liderança, excelência operacional e promoção do bem-estar no ambiente de trabalho.')
  ) as v(slug, quem_e)
 where p.slug = v.slug
   and p.quem_e is distinct from v.quem_e;

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, 'palestrante'
  from (values
    ('d1-0900-abertura', 'ivana-moreira'),
    ('d1-1330-autografos-autores', 'denize-savi'),
    ('d1-1330-autografos-autores', 'tamara-myles'),
    ('d1-1330-autografos-autores', 'izabella-camargo'),
    ('d1-1330-autografos-autores', 'yuri-trafane'),
    ('d1-1330-autografos-autores', 'fernanda-catena'),
    ('d1-1330-autografos-autores', 'joao-yosef-torres'),
    ('d1-1330-autografos-autores', 'veruska-galvao'),
    ('d1-1700-autografos-autores', 'michelle-schneider'),
    ('d1-1700-autografos-autores', 'stela-campos'),
    ('d1-1700-autografos-autores', 'renata-rivetti'),
    ('d1-1700-autografos-autores', 'oscar-de-bos'),
    ('d1-1700-autografos-autores', 'ana-claudia-quintana-arantes'),
    ('d2-1330-autografos-carla', 'edna-goldoni'),
    ('d2-1330-autografos-carla', 'arthur-guerra-de-andrade'),
    ('d2-1330-autografos-carla', 'daniel-martins-de-barros'),
    ('d2-1330-autografos-carla', 'alana-anijar'),
    ('d2-1700-autografo-ana-vazquez', 'ana-vazquez'),
    ('d2-1700-autografos-autores', 'vini-kitahara'),
    ('d2-1700-autografos-autores', 'denise-salvador'),
    ('d2-1700-autografos-autores', 'ana-vazquez')
  ) as v(sessao, slug)
  join summit_2026.sessions s on s.site_session_id = v.sessao
  join ecossistema.palestrantes_especialistas p on p.slug = v.slug
on conflict do nothing;
