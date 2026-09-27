-- Adriana (27/09/2026): em "Como incorporar a saúde mental à gestão de equipes" (d1-1230-curadoria,
-- 16/09, 12:30, Arena LinkedIn), Ana Prado foi a mediadora, como diz o site
-- ("Eymi Rocha, Simone Nascimento · Mediação: Ana Prado"). Entrou como palestrante em
-- 20260926163610; passa a mediação. Eymi Rocha e Simone Nascimento seguem palestrantes. Idempotente.
update summit_2026.session_speakers ss
   set papel = 'mediacao'
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where ss.sessao_id = s.id
   and ss.speaker_id = p.id
   and s.site_session_id = 'd1-1230-curadoria'
   and p.slug = 'ana-prado'
   and ss.papel is distinct from 'mediacao';
