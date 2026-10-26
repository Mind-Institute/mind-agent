-- Adriana (23/09): o workshop da Carla Tieppo (17/09, 18h, Sala Workshop 1) passa a
-- se chamar como na propriedade do HubSpot - "Navegar a mudança: liderança em
-- contextos de incerteza" - em vez de "Infraestrutura de Performance: Desenho
-- pessoal para executivos sob pressão crônica". Reservas e check-ins já estão
-- ligados por sessao_id, então nada se perde.
update summit_2026.sessions
   set titulo = 'Navegar a mudança: liderança em contextos de incerteza',
       descricao = 'Liderança em contextos de incerteza',
       atualizado_em = now()
 where id = '2022a60e-278b-4f25-b373-ec2baaf2103b'
   and titulo like 'Infraestrutura de Performance%';
