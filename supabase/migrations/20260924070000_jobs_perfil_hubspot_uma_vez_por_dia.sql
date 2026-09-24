-- Uma vez por dia (Adriana, 24/09/2026): o que foi ligado para perfil/ICP e espelho de contatos do
-- HubSpot deixa de rodar de hora em hora / a cada 3 h. Ordem na manhã (UTC): contatos 06:17 → vendas
-- diretas 06:45 → projeção de perfil e pessoas.pessoas 06:50 → write-back no HubSpot 06:55 (janela de
-- 26 h, para cobrir o dia inteiro com folga). Aplicado direto em produção.
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'hubspot-contatos-diario'), schedule := '17 6 * * *');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'perfil_projetar_horario'), schedule := '50 6 * * *');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'hubspot_perfil_writeback_horario'),
                      schedule := '55 6 * * *',
                      command := $$select public.mind_hubspot_perfil_disparar('contatos', true, interval '26 hours')$$);
