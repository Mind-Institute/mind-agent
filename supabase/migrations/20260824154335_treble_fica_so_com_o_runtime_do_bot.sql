-- treble guarda o runtime do bot. Sobravam quatro tabelas que não são dele:
--   conversations / messages          -> conversa (engagement.conversas / .mensagens, já existem)
--   conversation_interests            -> inferência (intelligence)
--   agent_events                      -> log de idempotência descartável do bot
-- São 25 / 84 / 0 / 1 linhas de TESTE. Não migramos linha por linha: a Edge
-- Function será reconstruída contra a estrutura final e escreverá direto no
-- lugar certo (engagement + intelligence). Aqui só esvaziamos o treble.
--
-- Destrutivo, mas seguro: conferido que NADA de fora aponta para estas tabelas
-- (zero FK/view externa). As funções que as leem — a EF e os RPCs do runtime —
-- vão quebrar de propósito e entram na lista de reconstrução.
--
-- Sem rollback de dado: dados de teste, descartados por decisão da Adriana.
-- Reversível estruturalmente: o formato das tabelas está nas migrations que as
-- criaram (histórico do repositório), caso a EF nova precise consultá-lo.

drop table if exists treble.conversation_interests cascade;
drop table if exists treble.messages cascade;
drop table if exists treble.conversations cascade;
drop table if exists treble.agent_events cascade;
