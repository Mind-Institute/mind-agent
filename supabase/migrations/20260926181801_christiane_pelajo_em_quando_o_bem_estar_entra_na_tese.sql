-- Adriana (26/09): Christiane Pelajo, da planilha "Palestrantes Mind Summit 2026", entra em
-- "Quando o bem-estar entra na tese" (Arena Mind, 16/09 10:20, d1-1030-quando-bem) como mediadora,
-- como está escrito no site (src/data/programacao.json: "Paula Benevides, Daniel Izzo · Mediação:
-- Christiane Pelajo"). Não existia no cadastro; entra com a bio do site (src/data/speakers.json).
-- O tipo segue 'painel' (3 pessoas). Idempotente.
insert into ecossistema.palestrantes_especialistas (nome, slug)
select 'Christiane Pelajo', 'christiane-pelajo'
 where not exists (select 1 from ecossistema.palestrantes_especialistas where slug = 'christiane-pelajo');

update ecossistema.palestrantes_especialistas
   set quem_e = 'Christiane Pelajo é jornalista, apresentadora e especialista em comunicação, com mais de 30 anos de carreira. Durante 26 anos, integrou a Globo e a GloboNews, onde esteve à frente de grandes coberturas e apresentou, por uma década, o Jornal da Globo. Atualmente, é âncora do Times Brasil – CNBC e atua também como palestrante e especialista em comunicação e liderança, conectando sua experiência no jornalismo aos desafios do mundo corporativo.',
       atualizado_em = now()
 where slug = 'christiane-pelajo'
   and quem_e is distinct from 'Christiane Pelajo é jornalista, apresentadora e especialista em comunicação, com mais de 30 anos de carreira. Durante 26 anos, integrou a Globo e a GloboNews, onde esteve à frente de grandes coberturas e apresentou, por uma década, o Jornal da Globo. Atualmente, é âncora do Times Brasil – CNBC e atua também como palestrante e especialista em comunicação e liderança, conectando sua experiência no jornalismo aos desafios do mundo corporativo.';

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, 'mediacao'
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where s.site_session_id = 'd1-1030-quando-bem'
   and p.slug = 'christiane-pelajo'
on conflict do nothing;
