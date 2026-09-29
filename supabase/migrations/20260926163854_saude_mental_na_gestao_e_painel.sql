-- Adriana (26/09): "Como incorporar a saúde mental à gestão de equipes" (Arena LinkedIn, 16/09
-- 12:30, app 983) é painel. O tipo estava nulo desde 20260923170000 porque a planilha do app não
-- informa o formato; agora a informação veio de quem sabe.
update summit_2026.sessions
   set tipo = 'painel', atualizado_em = now()
 where site_session_id = 'd1-1230-curadoria'
   and tipo is distinct from 'painel';
