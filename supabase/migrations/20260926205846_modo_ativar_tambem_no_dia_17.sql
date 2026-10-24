-- Adriana (26/09): a experiência Modo Ativar com Bel Mota também aconteceu no segundo dia
-- (17/09), no mesmo horário do dia 1 (14:30-14:50, Arena Mind). Nova sessão d2-1430-modo-ativar,
-- cópia de d1-1430-modo-ativar mudando só a data; sem id do app (yazo_ids vazio), porque o app não
-- tinha essa sessão no dia 17. Bel Mota ligada como palestrante, como no dia 1. Idempotente.
insert into summit_2026.sessions
  (titulo, descricao, dia, inicio, fim, duracao_min, espaco_id, tipo, trilhas, ingressos,
   precisa_reserva, reserva_recomendada, lugares_limitados, topicos_aprendizado, resultados,
   jtbd, event_id, site_session_id, yazo_ids, atualizado_em)
select d1.titulo, d1.descricao, date '2026-09-17',
       timestamptz '2026-09-17 14:30-03', timestamptz '2026-09-17 14:50-03', d1.duracao_min,
       d1.espaco_id, d1.tipo, d1.trilhas, d1.ingressos,
       d1.precisa_reserva, d1.reserva_recomendada, d1.lugares_limitados, d1.topicos_aprendizado,
       d1.resultados, d1.jtbd, d1.event_id, 'd2-1430-modo-ativar', '{}'::text[], now()
  from summit_2026.sessions d1
 where d1.site_session_id = 'd1-1430-modo-ativar'
   and not exists (select 1 from summit_2026.sessions x where x.site_session_id = 'd2-1430-modo-ativar');

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, 'palestrante'
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where s.site_session_id = 'd2-1430-modo-ativar'
   and p.slug = 'bel-mota'
on conflict do nothing;
