-- Adriana (26/09): regra de formato — mais de 2 pessoas é painel, senão palestra. "Sobreviver sem
-- destruir o time" (Arena LinkedIn, 17/09 15:00, app 1035) tem 3 (Caito Maia, Ricardo Souza e
-- Ivana Moreira na mediação): palestra -> painel. As demais sessões da Arena LinkedIn já seguem a
-- regra. Mediações ficam como estão (decisão dela). Idempotente.
update summit_2026.sessions
   set tipo = 'painel', atualizado_em = now()
 where site_session_id = 'd2-1500-sobreviver-destruir'
   and tipo is distinct from 'painel';
