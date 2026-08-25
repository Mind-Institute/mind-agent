-- O antigo "base" não é universal: é a identidade + o roteamento do agente do
-- Treble, que entra em todo turno DELE (não de todo agente). Passa a se chamar
-- pelo que faz: playbook_router — o bloco sempre-ligado que decide qual playbook
-- de venda/atendimento aplicar. tom_de_voz continua sendo o único universal.
update agentes.prompts set chave = 'playbook_router' where chave = 'base';
