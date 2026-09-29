-- Adriana (27/09/2026), duas correções nas sessões do Summit 2026.
--
-- 1. "Do benefício à estratégia de negocio" ganha o acento: "negócio".
--    O casamento desta sessão com o Yazo é pelo yazo_ids (970), não pelo título.
--
-- 2. Regra de formato revista: quando são 2 pessoas, é painel. Substitui a regra
--    de 26/09 ("mais de 2 pessoas é painel", migration 20260926181809). Mediação
--    conta como pessoa. As quatro sessões com 2 pessoas passam de palestra para painel:
--      d2-1130-voce-aguenta        Você aguenta ser líder?             (Daniel Martins de Barros, Arthur Guerra de Andrade)
--      d2-1600-conversas-corajosas Conversas Corajosas, Times Fortes   (Luciana Campos Lima, Viviane Mansi)
--      d2-1500-seu-cerebro         Seu cérebro não foi feito para isso (Paul Goldsmith; mediação Sibelle Pedral)
--      d2-1640-florescendo-tempos  Florescendo em tempos de incerteza  (Deepika Chopra; mediação Virginie Leite)
--    Sessões com 1 pessoa continuam palestra (ex.: d1-1230-nova-era).
-- Idempotente.

update summit_2026.sessions
   set titulo = replace(titulo, 'estratégia de negocio', 'estratégia de negócio'), atualizado_em = now()
 where site_session_id = 'd1-0915-beneficio-transformacao'
   and titulo like '%estratégia de negocio%';

update summit_2026.sessions
   set tipo = 'painel', atualizado_em = now()
 where site_session_id in ('d2-1130-voce-aguenta', 'd2-1600-conversas-corajosas',
                           'd2-1500-seu-cerebro', 'd2-1640-florescendo-tempos')
   and tipo is distinct from 'painel';
