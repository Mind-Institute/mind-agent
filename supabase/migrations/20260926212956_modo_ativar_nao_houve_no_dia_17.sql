-- Adriana (26/09): não houve Modo Ativar com Bel Mota no dia 17.
-- Desfaz 20260926205846_modo_ativar_tambem_no_dia_17. A sessão do dia 16
-- (d1-1430-modo-ativar) e o cadastro da Bel Mota ficam como estão.
delete from summit_2026.session_speakers ss
 using summit_2026.sessions s
 where ss.sessao_id = s.id
   and s.site_session_id = 'd2-1430-modo-ativar';

delete from summit_2026.sessions
 where site_session_id = 'd2-1430-modo-ativar';
