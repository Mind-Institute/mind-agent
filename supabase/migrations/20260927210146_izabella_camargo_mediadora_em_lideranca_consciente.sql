-- Adriana (27/09/2026): em "Liderança Consciente" (d1-1720-lideranca-consciente, 16/09, 17:20,
-- Arena Mind), Izabella Camargo foi a mediadora. Ela entrou como palestrante no lugar da
-- Daiana Garbin em 20260926204500; passa a mediação. Adriana Drulla e Ana Bógus seguem
-- palestrantes. Idempotente.
update summit_2026.session_speakers ss
   set papel = 'mediacao'
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where ss.sessao_id = s.id
   and ss.speaker_id = p.id
   and s.site_session_id = 'd1-1720-lideranca-consciente'
   and p.slug = 'izabella-camargo'
   and ss.papel is distinct from 'mediacao';
