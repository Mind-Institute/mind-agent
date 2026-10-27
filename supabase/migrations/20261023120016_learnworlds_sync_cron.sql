-- LearnWorlds, Fase 1 — agenda da sincronização (aprovada pela Adriana em 23/10/2026).
-- A cada 6 horas, como o espelho de empresas do HubSpot. A primeira carga (23/10) leu 20 cursos,
-- 3 bundles, 2.558 pessoas e 2.334 matrículas em 70 s; a função retoma de onde parou se passar de 120 s.
select cron.schedule(
  'learnworlds_sync',
  '11 */6 * * *',
  $$
  select net.http_post(
    url := 'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/learnworlds-sync?token='
           || (select valor from intelligence.config where chave='analise_token'),
    body := '{}'::jsonb,
    headers := '{"Content-Type":"application/json"}'::jsonb,
    timeout_milliseconds := 150000);
  $$
);
