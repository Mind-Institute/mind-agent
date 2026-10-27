-- Adriana (26/09): bios de Eymi Rocha e Simone Nascimento, palestrantes de "Como incorporar a
-- saúde mental à gestão de equipes" (Arena LinkedIn, 16/09 12:30). Texto dela, sem edição, em
-- quem_e — como a bio da Renata Rivetti (id 45). cargo_curto e instituicao ficam como estão.
update ecossistema.palestrantes_especialistas p
   set quem_e = v.quem_e, atualizado_em = now()
  from (values
    ('eymi-rocha', 'Psicóloga clínica e organizacional, especialista em saúde mental no trabalho e prevenção do burnout. MBA em Gestão de Pessoas pela USP/Esalq, atua apoiando empresas na identificação e gestão de riscos psicossociais e na construção de ambientes de trabalho mais saudáveis. É LinkedIn Top Voice em Equilíbrio Vida e Trabalho.'),
    ('simone-nascimento', 'Médica, especialista em Saúde Mental nas Organizações e Medicina do Estilo de Vida. TEDx Speaker e LinkedIn Top Voice em Saúde Mental e Equilíbrio, é apresentadora do Canal Futura e integra o Comitê Consultivo do Movimento Mente em Foco, do Pacto Global da ONU no Brasil.')
  ) as v(slug, quem_e)
 where p.slug = v.slug
   and p.quem_e is distinct from v.quem_e;
