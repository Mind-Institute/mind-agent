-- Correcao: o criterio de parada estava errado.
--
-- Uma corrida termina com status 'ocioso' sempre que a pagina acabou -- inclusive
-- quando ainda ha milhares de registros depois da marca dagua. Com o criterio
-- antigo, a carga inicial se desligaria na primeira corrida completa, deixando o
-- espelho pela metade e sem ninguem perceber, porque o status diria "ocioso".
--
-- O criterio certo e o unico que significa "acabou": a ultima corrida leu ZERO.
-- Ai sim nao ha mais nada depois da marca dagua.
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
   where marca_dagua is null
      or status <> 'ocioso'
      or coalesce(registros_lidos, 0) > 0;

  if v_faltando = 0 then
    perform cron.unschedule('hubspot-espelho-carga-inicial');
    return;
  end if;

  perform public.mind_espelho_disparar();
end;
$function$;

revoke all on function public.mind_espelho_carga_inicial() from public, anon, authenticated;