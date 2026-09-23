-- Varredura D6 (23/09/2026): as tabelas com informação de cliente que ainda não tinham mind_id
-- entram na Regra #1. Uma chamada por tabela; o preenchimento vem em seguida, em lotes.
select 'crm.pipeline_leads_inbound' as tabela, public.mind_pessoa_ligar_tabela('crm.pipeline_leads_inbound'::regclass, '{"hubspot_ids":["hs_primary_contact_id"]}'::jsonb) as r
union all
select 'crm.status_summit_hs', public.mind_pessoa_ligar_tabela('crm.status_summit_hs'::regclass, '{"hubspot_ids":["hubspot_id"]}'::jsonb)
union all
select 'treble.status_hs_contatos', public.mind_pessoa_ligar_tabela('treble.status_hs_contatos'::regclass, '{"hubspot_ids":["contato_id"]}'::jsonb)
union all
select 'treble.status_da_conversa', public.mind_pessoa_ligar_tabela('treble.status_da_conversa'::regclass, '{"telefones":["telefone"]}'::jsonb)
union all
select 'engagement.verificacoes_email', public.mind_pessoa_ligar_tabela('engagement.verificacoes_email'::regclass, '{"emails":["email"]}'::jsonb);

-- Depois de ligar, preencher (repetir por tabela até restantes_nesta_fonte = 0; fora de :20/:50):
-- select public.mind_identidade_criar_faltantes('crm.pipeline_leads_inbound'::regclass, 1000, false);
-- select public.mind_identidade_criar_faltantes('crm.status_summit_hs'::regclass, 1000, false);
-- select public.mind_identidade_criar_faltantes('treble.status_hs_contatos'::regclass, 1000, false);
-- select public.mind_identidade_criar_faltantes('treble.status_da_conversa'::regclass, 1000, false);
--
-- Ficaram de fora, de propósito (varredura de 23/09, 164 tabelas, 110 sem FK para pessoas):
--   engagement.treble_eventos (43.005) — log bruto dos webhooks; telefone vem sem DDI (~100 não-BR
--     normalizariam errado); é filha de engagement.conversas por payload.session.external_id.
--   crm.empenho_summit_2026 (25) — a pessoa está em propriedades._contatos (ids HubSpot), que o
--     trigger não lê; mind_espelho_ligar removeu esse bloco de propósito. Gate da Adriana.
--   103 tabelas sem cliente (config, catálogo, prompt, log de sistema, equipe, palestrantes) ou
--     filhas de uma linha que já tem mind_id pelo pai (mensagem→conversa, item→pedido).
--   Colunas participante_id/participant_id de "Check Ins Summit", "Reservas_Agenda_APP",
--     controle_de_inscritos_e_presenca e yazo_envio_fila apontam para participantes.id
--     (0 órfãos), não para pessoa: não são o ID universal.
