-- Faxina do schema mind, tabela 2 de 30 (Adriana, 2026-08-22).
--
-- consents é o registro de LGPD: quem autorizou o quê, sob qual versão de
-- qual política, e com o texto exato que viu na tela. É da PESSOA, não do
-- evento — se ela autorizou receber mensagem, isso não deixa de valer
-- quando o assunto virar Institute.
--
-- Decisão da Adriana: vai para o schema crm.
--
-- Nenhuma função do banco lê ou escreve nesta tabela hoje, então a mudança
-- não quebra nada. As duas FKs continuam valendo entre schemas:
--   participante_id -> mind.people
--   mensagem_id     -> concierge.mensagens

create schema if not exists crm;

comment on schema crm is
  'Pessoas e o relacionamento com elas: consentimento, pedidos de LGPD, enriquecimento. Atravessa produtos — a pessoa não pertence a um evento.';

alter table mind.consents set schema crm;

comment on table crm.consents is
  'Consentimento por finalidade, com a versão da política e o texto exibido — é o que prova depois o que a pessoa aceitou.';
