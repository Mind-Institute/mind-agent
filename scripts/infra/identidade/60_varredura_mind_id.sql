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

-- Preenchimento executado em 23/09 (07:21–07:37 UTC), sem criar pessoa nenhuma:
--   1) ligação por identificador já conhecido (engagement.identidades, canal hubspot/whatsapp) —
--      o trigger não chama a porta quando só mind_id muda e a linha já tem pessoa:
--        pipeline_leads_inbound 3.286/3.437 · status_summit_hs 342/342 · status_hs_contatos 6.068/6.132 ·
--        status_da_conversa 5.610/5.615 (telefone normalizado por public.telefone_normalizar);
--   2) 71 linhas (25 pessoas) cujo contato existe em crm.contato_espelho com mind_id mas sem a
--      identidade hubspot em engagement.identidades: ligadas pelo mind_id do espelho, com
--      mind.d5_pular_trigger = '1' (criar_faltantes criaria uma segunda pessoa só com o id HubSpot);
--      mind_pessoa_enriquecer rodou nas 25 e não acrescentou a identidade (2 conflitos) — BACKLOG §20.8;
--   3) o resto foi marcado como resolvido sem pessoa, para não ficar pendente para sempre:
--        141 leads e 3 contatos cujo id HubSpot não está no espelho (contato apagado/fundido no HubSpot)
--        → 'sem pessoa: contato HubSpot fora do espelho (varredura D6)';
--        5 telefones de teste (5511977770009, 5512025550123…) sem conversa → 'sem pessoa: telefone de teste…'.
--   Não usar mind_identidade_criar_faltantes nestas fontes: um id HubSpot sozinho criaria pessoa
--   sem nome nem e-mail. Resultado final: leads 3.296/3.437 · summit_hs 342/342 ·
--   hs_contatos 6.129/6.132 · da_conversa 5.610/5.615 · verificacoes_email 0 linhas.
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
