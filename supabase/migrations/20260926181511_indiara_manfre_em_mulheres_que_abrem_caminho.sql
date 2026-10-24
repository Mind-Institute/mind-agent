-- Adriana (26/09): Indiara Kurtz Danelli Manfre também esteve em "Mulheres que abrem caminho"
-- (Arena Mind, 17/09 12:30-13:20, app 1019, d2-1230-mulheres-abrem), com Edna Goldoni, Ana Diniz e
-- Mara Maehara. Não existia no cadastro; entra com a bio enviada pela Adriana, sem edição, como
-- palestrante (nenhum texto a indica como mediadora). O tipo segue 'painel' (4 pessoas). Idempotente.
insert into ecossistema.palestrantes_especialistas (nome, slug)
select 'Indiara Kurtz Danelli Manfre', 'indiara-kurtz-danelli-manfre'
 where not exists (select 1 from ecossistema.palestrantes_especialistas where slug = 'indiara-kurtz-danelli-manfre');

update ecossistema.palestrantes_especialistas
   set quem_e = 'Indiara Kurtz Danelli Manfre é Chief Human Resources Officer (CHRO) Global da Citrosuco, com cerca de 28 anos de experiência em Gestão de Pessoas e atuação estratégica em toda a cadeia de Recursos Humanos. Ao longo de sua trajetória, consolidou expertise em cultura organizacional, desenvolvimento de lideranças, atração de talentos, remuneração, diversidade, transformação digital e sistema gestão para alta performance. Com sólida experiência na liderança de equipes e no desenho de estratégias de pessoas alinhadas ao negócio, também atuou como conselheira. Está entre os Top 10 RHs Mais Admirados da América Latina em 2025 pela Gestão RH.',
       atualizado_em = now()
 where slug = 'indiara-kurtz-danelli-manfre'
   and quem_e is distinct from 'Indiara Kurtz Danelli Manfre é Chief Human Resources Officer (CHRO) Global da Citrosuco, com cerca de 28 anos de experiência em Gestão de Pessoas e atuação estratégica em toda a cadeia de Recursos Humanos. Ao longo de sua trajetória, consolidou expertise em cultura organizacional, desenvolvimento de lideranças, atração de talentos, remuneração, diversidade, transformação digital e sistema gestão para alta performance. Com sólida experiência na liderança de equipes e no desenho de estratégias de pessoas alinhadas ao negócio, também atuou como conselheira. Está entre os Top 10 RHs Mais Admirados da América Latina em 2025 pela Gestão RH.';

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, 'palestrante'
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where s.site_session_id = 'd2-1230-mulheres-abrem'
   and p.slug = 'indiara-kurtz-danelli-manfre'
on conflict do nothing;
