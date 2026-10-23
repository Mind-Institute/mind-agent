-- Espelho de contatos do HubSpot: de 1x/dia para a cada 3 horas (23/09/2026).
-- Cada chamada do hubspot-sync lê até ~1.000 contatos (10 páginas em ~45 s). Com o write-back
-- horário de perfil, o HubSpot chegou a 2.704 contatos alterados num único dia (23/09); uma
-- rodada diária não alcançava. A cada 3 h = até ~8.000/dia. Aplicado direto em produção.
select cron.alter_job(
  job_id   := (select jobid from cron.job where jobname = 'hubspot-contatos-diario'),
  schedule := '17 */3 * * *');

-- Recuperação única do atraso desde 09/09 (a paginação por cursor batia no teto de 10.000 do
-- HubSpot): a posição incremental travada foi zerada para recomeçar da marca d'água, e um job
-- temporário 'hubspot-contatos-recuperacao-tmp' (a cada minuto) foi ligado e removido quando
-- o espelho alcançou o presente. Nada disso fica: só o registro.
