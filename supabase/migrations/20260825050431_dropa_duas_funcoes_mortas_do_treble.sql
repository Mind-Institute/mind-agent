-- Andaime morto do runtime velho do treble: as duas referenciavam
-- treble.conversations (dropada na redução do treble a config) e ainda citavam
-- crm.pessoas (movida). Não funcionam desde então; saem para não deixar lixo.
-- Serão reconstruídas do zero quando a gente montar o runtime do treble.
drop function if exists public.mind_identificar_pessoa(text, text, text, text, boolean);
drop function if exists public.treble_agent_start(text, jsonb, text, text);
