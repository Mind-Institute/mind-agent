-- Adriana (26/09): "não considera o Ricardo". Ricardo Souza sai de "Sobreviver sem destruir o
-- time" (d2-1500-sobreviver-destruir), desfazendo 20260926175610. O cadastro dele foi criado só
-- para essa ligação; sai também, desde que nada mais aponte para ele. Caito Maia e a mediação da
-- Ivana Moreira ficam. Idempotente.
delete from summit_2026.session_speakers ss
 using summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where ss.sessao_id = s.id and ss.speaker_id = p.id
   and s.site_session_id = 'd2-1500-sobreviver-destruir'
   and p.slug = 'ricardo-souza';

delete from ecossistema.palestrantes_especialistas p
 where p.slug = 'ricardo-souza'
   and not exists (select 1 from summit_2026.session_speakers ss where ss.speaker_id = p.id)
   and not exists (select 1 from ecossistema.perfis_publicos pp where pp.palestrante_especialista_id = p.id);
