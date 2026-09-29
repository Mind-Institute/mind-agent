-- Adriana (26/09): "Liderança Consciente" (Arena Mind, 16/09 17:20, d1-1720-lideranca-consciente)
-- foi com Izabella Camargo; Daiana Garbin não participou em 2026. Sai a ligação da Daiana
-- (mediacao) e entra a Izabella como palestrante (nenhum texto a indica como mediadora). A sessão
-- segue com 3 pessoas, então o tipo continua 'painel'. O cadastro da Daiana não é tocado aqui.
-- Idempotente.
delete from summit_2026.session_speakers ss
 using summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where ss.sessao_id = s.id and ss.speaker_id = p.id
   and s.site_session_id = 'd1-1720-lideranca-consciente'
   and p.slug = 'daiana-garbin';

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, 'palestrante'
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where s.site_session_id = 'd1-1720-lideranca-consciente'
   and p.slug = 'izabella-camargo'
on conflict do nothing;
