-- "Falhar melhor" tinha ido para a Sala Workshop 1 seguindo a planilha do app,
-- que a coloca lá junto com "Resiliência em tempo real" no mesmo horário e deixa
-- a Sala Workshop 2 vazia. Duas turmas na mesma sala é fisicamente impossível, e
-- os outros três blocos de workshop ocupam as três salas em paralelo — a planilha
-- do app é que está errada aqui. Decisão da Adriana: devolver à Sala Workshop 2.
update summit_2026.sessions s
   set espaco_id = l.id, atualizado_em = now()
  from summit_2026.locations l
 where s.site_session_id = 'd1-1500-falhar-melhor'
   and l.nome = 'Sala Workshop 2';
