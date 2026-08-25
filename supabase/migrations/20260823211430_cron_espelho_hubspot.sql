-- A chave anon e publica (e a mesma que qualquer navegador ve), mas nao vai
-- literal dentro do comando do cron: fica em platform.integracoes, junto com o
-- resto da config de integracao. Rotacionar vira UPDATE.
insert into platform.integracoes (codigo, rotulo, base_url, secret_ref, config) values
  ('supabase_functions', 'Edge Functions do proprio projeto',
   'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1', null,
   jsonb_build_object('anon_key',
     'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inltbm1vdGdnbHNyeG1qbW9ud2p6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcyMDEzNTUsImV4cCI6MjEwMjc3NzM1NX0._i9E4J2BykUeVTArAVQRCLqEU9tVIZf9QbWNnCzyrwc'))
on conflict (codigo) do update set config = excluded.config, atualizado_em = now();

-- Um disparo so, usado pelas duas tarefas. Devolve o id da requisicao; quem
-- quiser ver a resposta le net._http_response.
create or replace function public.mind_espelho_disparar()
returns bigint
language plpgsql
security definer
set search_path to 'public', 'platform', 'net'
as $function$
declare
  v_base text;
  v_key text;
begin
  select base_url, config->>'anon_key' into v_base, v_key
    from platform.integracoes where codigo = 'supabase_functions' and ativo;

  if v_base is null or v_key is null then
    raise exception 'integracao supabase_functions sem base_url ou anon_key';
  end if;

  return net.http_post(
    url := v_base || '/hubspot-sync',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || v_key),
    body := '{}'::jsonb,
    timeout_milliseconds := 150000);
end;
$function$;

-- A CARGA INICIAL: cada corrida tem orcamento de 90s e devolve de onde parou,
-- entao 20 mil registros viram varias corridas curtas em vez de uma que nunca
-- termina. Ela se DESLIGA SOZINHA quando as tres fontes estiverem ociosas com
-- marca dagua -- ninguem precisa lembrar de desligar, que e como esse tipo de
-- tarefa vira lixo eterno.
create or replace function public.mind_espelho_carga_inicial()
returns void
language plpgsql
security definer
set search_path to 'public', 'crm', 'cron'
as $function$
declare v_faltando int;
begin
  select count(*) into v_faltando
    from crm.sync_estado
   where status <> 'ocioso' or marca_dagua is null;

  if v_faltando = 0 then
    perform cron.unschedule('hubspot-espelho-carga-inicial');
    return;
  end if;

  perform public.mind_espelho_disparar();
end;
$function$;

revoke all on function public.mind_espelho_disparar() from public, anon, authenticated;
revoke all on function public.mind_espelho_carga_inicial() from public, anon, authenticated;

-- Regime permanente: uma corrida de madrugada, incremental.
select cron.schedule('hubspot-espelho-diario', '17 6 * * *', 'select public.mind_espelho_disparar();');

-- Temporaria, some sozinha.
select cron.schedule('hubspot-espelho-carga-inicial', '* * * * *', 'select public.mind_espelho_carga_inicial();');