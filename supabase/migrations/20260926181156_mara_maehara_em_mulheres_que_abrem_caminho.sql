-- Adriana (26/09): "Mulheres que abrem caminho" (Arena Mind, 17/09 12:30-13:20, app 1019,
-- d2-1230-mulheres-abrem) foi de Ana Diniz, Edna Goldoni e Mara Maehara, conforme a tela da
-- sessão no app. Ana Diniz e Edna Goldoni já estavam ligadas; Mara Maehara não existia no cadastro
-- e entra com a bio do site (src/data/speakers.json). O site lista as três sem mediação
-- ("Edna Goldoni, Ana Diniz, Mara Maehara"), então ela entra como palestrante. O tipo segue
-- 'painel' (3 pessoas, regra da Adriana). Idempotente.
insert into ecossistema.palestrantes_especialistas (nome, slug)
select 'Mara Maehara', 'mara-maehara'
 where not exists (select 1 from ecossistema.palestrantes_especialistas where slug = 'mara-maehara');

update ecossistema.palestrantes_especialistas
   set quem_e = 'CIO da TOTVS desde 2016, Mara Maehara lidera a tecnologia que sustenta as operações de uma das maiores empresas de tecnologia do Brasil. Com mais de 30 anos de experiência em TI e passagens por Ambev, BRF, Carrefour e GPA, conecta visão estratégica, infraestrutura, segurança da informação e desenvolvimento de equipes. Sua atuação mostra como tecnologia, liderança e eficiência operacional podem impulsionar produtividade, inovação e transformação em escala.',
       atualizado_em = now()
 where slug = 'mara-maehara'
   and quem_e is distinct from 'CIO da TOTVS desde 2016, Mara Maehara lidera a tecnologia que sustenta as operações de uma das maiores empresas de tecnologia do Brasil. Com mais de 30 anos de experiência em TI e passagens por Ambev, BRF, Carrefour e GPA, conecta visão estratégica, infraestrutura, segurança da informação e desenvolvimento de equipes. Sua atuação mostra como tecnologia, liderança e eficiência operacional podem impulsionar produtividade, inovação e transformação em escala.';

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, 'palestrante'
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where s.site_session_id = 'd2-1230-mulheres-abrem'
   and p.slug = 'mara-maehara'
on conflict do nothing;
