-- A carga inicial estava pulando registros em silencio.
--
-- Evidencia: o HubSpot tem 1.930 contatos modificados em julho e 9.634 em agosto.
-- O espelho parou em 1.600 e a marca dagua pulou para hoje -- ou seja, a busca
-- ordenada por data de modificacao NAO estava devolvendo do mais antigo para o
-- mais novo, e a marca andou por cima de milhares de registros que nunca vieram.
--
-- Pior: isso nao da erro. A fonte fica 'ocioso' e parece pronta.
--
-- Correcao: carga inicial deixa de usar a Search API e passa a usar a listagem
-- (/crm/v3/objects/...), que percorre TODOS os registros por cursor, sem depender
-- de ordenacao nem do teto de 10 mil da busca. O cursor fica aqui entre corridas.
-- A busca por marca dagua continua sendo o caminho do incremental diario, onde
-- ela e barata e o volume e pequeno.
alter table crm.sync_estado add column if not exists cursor text;
alter table crm.sync_estado add column if not exists carga_completa_em timestamptz;

comment on column crm.sync_estado.cursor is
  'Cursor da listagem do HubSpot durante a carga inicial. Nulo depois que ela termina -- dai em diante quem manda e a marca dagua.';
comment on column crm.sync_estado.carga_completa_em is
  'Quando a carga inicial varreu tudo. Enquanto for nulo, a fonte ainda esta se enchendo e a marca dagua NAO e confiavel.';

create or replace function public.mind_sync_abrir(p_fonte text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'crm', 'platform'
as $function$
declare
  s crm.sync_estado;
  cfg jsonb;
begin
  select * into s from crm.sync_estado where fonte = p_fonte;
  if not found then
    raise exception 'fonte desconhecida: %', p_fonte;
  end if;

  select config into cfg from platform.integracoes where codigo = 'hubspot' and ativo;

  update crm.sync_estado
     set status = 'rodando', iniciado_em = now(), erro = null
   where fonte = p_fonte;

  return jsonb_build_object(
    'marca_dagua', s.marca_dagua,
    'cursor', s.cursor,
    'carga_completa_em', s.carga_completa_em,
    'tabela_destino', s.tabela_destino,
    'chave_destino', s.chave_destino,
    'config', coalesce(cfg, '{}'::jsonb));
end;
$function$;

create or replace function public.mind_sync_marcar(
  p_fonte text,
  p_marca timestamptz default null,
  p_lidos int default null,
  p_gravados int default null,
  p_status text default null,
  p_erro text default null,
  p_cursor text default null,
  p_completou boolean default false)
returns void
language sql
security definer
set search_path to 'public', 'crm'
as $function$
  update crm.sync_estado
     set marca_dagua       = coalesce(p_marca, marca_dagua),
         registros_lidos   = coalesce(p_lidos, registros_lidos),
         registros_gravados= coalesce(p_gravados, registros_gravados),
         status            = coalesce(p_status, status),
         erro              = p_erro,
         -- cursor nulo so e apagado quando a varredura completa termina; no meio
         -- do caminho, nulo significa "nao mexe".
         cursor            = case when p_completou then null else coalesce(p_cursor, cursor) end,
         carga_completa_em = case when p_completou then now() else carga_completa_em end,
         concluido_em      = case when p_status = 'ocioso' then now() else concluido_em end
   where fonte = p_fonte;
$function$;

-- A carga inicial acabou quando TODAS as fontes varreram tudo -- nao quando uma
-- corrida leu zero, que era o criterio anterior e mentia.
create or replace function public.mind_espelho_carga_inicial()
returns void
language plpgsql
security definer
set search_path to 'public', 'crm', 'cron'
as $function$
declare v_faltando int;
begin
  select count(*) into v_faltando
    from crm.sync_estado where carga_completa_em is null;

  if v_faltando = 0 then
    perform cron.unschedule('hubspot-espelho-carga-inicial');
    return;
  end if;

  perform public.mind_espelho_disparar();
end;
$function$;

revoke all on function public.mind_sync_abrir(text) from public, anon, authenticated;
revoke all on function public.mind_sync_marcar(text, timestamptz, int, int, text, text, text, boolean) from public, anon, authenticated;
revoke all on function public.mind_espelho_carga_inicial() from public, anon, authenticated;
