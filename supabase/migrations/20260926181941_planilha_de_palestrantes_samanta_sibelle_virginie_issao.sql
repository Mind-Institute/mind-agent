-- Adriana (26/09), a partir da planilha "Palestrantes Mind Summit 2026": entram no cadastro e nas
-- sessões quatro nomes que faltavam no banco.
--   Samanta Pillar  -> palestrante de "Da estratégia à prática" (d2-1720-estrategia-pratica); o site
--                      diz "Samanta Pillar, Maurício Giamellaro · Apresentação: Ivana Moreira". Bio do site.
--   Sibelle Pedral  -> mediação de "Seu cérebro não foi feito para isso" (d2-1500-seu-cerebro); o site
--                      diz "Paul Goldsmith · Mediação: Sibelle Pedral". Sem bio no site.
--   Virginie Leite  -> mediação de "Florescendo em tempos de incerteza" (d2-1640-florescendo-tempos); o
--                      site diz "Deepika Chopra · Mediação: Virginie Leite". Sem bio no site.
--   Issao Imamura   -> "é a abertura do dia 2" (Adriana): palestrante de "Quem enxerga antes, lidera
--                      antes" (d2-0900-quem-enxerga), que o site marca como "Abertura" com "Convidado
--                      Especial". Sem bio.
-- Formatos seguem a regra (mais de 2 pessoas é painel, senão palestra): seu-cerebro e florescendo
-- ficam 'palestra' (2 pessoas); estrategia-pratica ('entrevista') e quem-enxerga ('experiencia') não
-- são palestra/painel e ficam como estão. Idempotente.
insert into ecossistema.palestrantes_especialistas (nome, slug)
select v.nome, v.slug
  from (values ('Samanta Pillar', 'samanta-pillar'),
               ('Sibelle Pedral', 'sibelle-pedral'),
               ('Virginie Leite', 'virginie-leite'),
               ('Issao Imamura', 'issao-imamura')) as v(nome, slug)
 where not exists (select 1 from ecossistema.palestrantes_especialistas p where p.slug = v.slug);

update ecossistema.palestrantes_especialistas
   set quem_e = 'Vice-Presidente Executiva de Pessoas da Vale, Samanta tem 30 anos de experiência em Recursos Humanos, com atuação em gestão de talentos, desenvolvimento organizacional, sucessão, remuneração, produtividade e negociações sindicais. Liderou agendas de RH em contextos complexos de transformação, incluindo fusões e aquisições, venda de ativos, recuperação judicial e lançamento de startups. Sua trajetória conecta estratégia, cultura e liderança de pessoas para sustentar alta performance em ambientes de pressão e mudança.',
       atualizado_em = now()
 where slug = 'samanta-pillar'
   and quem_e is distinct from 'Vice-Presidente Executiva de Pessoas da Vale, Samanta tem 30 anos de experiência em Recursos Humanos, com atuação em gestão de talentos, desenvolvimento organizacional, sucessão, remuneração, produtividade e negociações sindicais. Liderou agendas de RH em contextos complexos de transformação, incluindo fusões e aquisições, venda de ativos, recuperação judicial e lançamento de startups. Sua trajetória conecta estratégia, cultura e liderança de pessoas para sustentar alta performance em ambientes de pressão e mudança.';

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, v.papel
  from (values ('d2-1720-estrategia-pratica', 'samanta-pillar', 'palestrante'),
               ('d2-1500-seu-cerebro', 'sibelle-pedral', 'mediacao'),
               ('d2-1640-florescendo-tempos', 'virginie-leite', 'mediacao'),
               ('d2-0900-quem-enxerga', 'issao-imamura', 'palestrante')) as v(sessao, slug, papel)
  join summit_2026.sessions s on s.site_session_id = v.sessao
  join ecossistema.palestrantes_especialistas p on p.slug = v.slug
on conflict do nothing;
