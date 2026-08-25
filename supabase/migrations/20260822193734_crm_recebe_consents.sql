-- Faxina do schema mind, tabela 2 de 30 (Adriana, 2026-08-22).
--
-- consents e o registro de LGPD: quem autorizou o que, sob qual versao de
-- qual politica, e com o texto exato que viu na tela. E da PESSOA, nao do
-- evento — se ela autorizou receber mensagem, isso nao deixa de valer
-- quando o assunto virar Institute.
--
-- Decisao da Adriana: vai para o schema crm.
--
-- Nenhuma funcao do banco le ou escreve nesta tabela hoje, entao a mudanca
-- nao quebra nada. As duas FKs continuam valendo entre schemas:
--   participante_id -> mind.people
--   mensagem_id     -> concierge.mensagens

create schema if not exists crm;

comment on schema crm is
  'Pessoas e o relacionamento com elas: consentimento, pedidos de LGPD, enriquecimento. Atravessa produtos — a pessoa nao pertence a um evento.';

alter table mind.consents set schema crm;

comment on table crm.consents is
  'Consentimento por finalidade, com a versao da politica e o texto exibido — e o que prova depois o que a pessoa aceitou.';
