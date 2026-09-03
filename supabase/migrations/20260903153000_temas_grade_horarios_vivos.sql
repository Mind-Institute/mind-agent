-- Duas sessões mudaram de dia/horário depois do snapshot usado na curadoria.
-- O título é o mesmo; reaplicamos os temas na posição atual da grade viva.

begin;

update summit_2026.sessions s
set topicos_aprendizado='["performance","futuro_trabalho"]'::jsonb, atualizado_em=now()
from summit_2026.events e
where e.id=s.event_id and e.slug='mind-summit-2026'
  and s.dia='2026-09-17'::date
  and to_char(s.inicio at time zone e.fuso,'HH24:MI')='11:30'
  and s.titulo='Bem-estar começa na agenda';

update summit_2026.sessions s
set topicos_aprendizado='["seguranca_psicologica","futuro_trabalho"]'::jsonb, atualizado_em=now()
from summit_2026.events e
where e.id=s.event_id and e.slug='mind-summit-2026'
  and s.dia='2026-09-16'::date
  and to_char(s.inicio at time zone e.fuso,'HH24:MI')='15:00'
  and s.titulo='Falhar melhor';

commit;
