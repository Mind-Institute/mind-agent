-- Adriana (26/09): regra de formato — mais de 2 pessoas é painel, senão palestra. Quatro sessões
-- estavam 'painel' com até 2 pessoas (no banco e no site) e passam a 'palestra':
--   d1-1230-nova-era            A nova era da alta performance       (Fernanda Catena)
--   d2-1130-voce-aguenta        Você aguenta ser líder?              (Daniel Martins de Barros, Arthur Guerra de Andrade)
--   d2-1600-conversas-corajosas Conversas Corajosas, Times Fortes    (Luciana Campos Lima, Viviane Mansi)
--   d2-1640-florescendo-tempos  Florescendo em tempos de incerteza   (Deepika Chopra)
-- Idempotente.
update summit_2026.sessions
   set tipo = 'palestra', atualizado_em = now()
 where site_session_id in ('d1-1230-nova-era', 'd2-1130-voce-aguenta',
                           'd2-1600-conversas-corajosas', 'd2-1640-florescendo-tempos')
   and tipo is distinct from 'palestra';
