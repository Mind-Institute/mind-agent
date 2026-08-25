-- A Edge Function nao fala com tabela, so com RPC em public -- mesma regra dos
-- agentes. Assim ela nao depende de quais schemas o PostgREST expoe, e o dia em
-- que alguem trocar isso nada quebra em silencio.
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
    'tabela_destino', s.tabela_destino,
    'chave_destino', s.chave_destino,
    'config', coalesce(cfg, '{}'::jsonb));
end;
$function$;

-- Marca o progresso. Chamada a cada pagina: se a corrida morrer no meio, a
-- proxima comeca de onde a ultima pagina GRAVADA parou, nunca do zero.
create or replace function public.mind_sync_marcar(
  p_fonte text,
  p_marca timestamptz default null,
  p_lidos int default null,
  p_gravados int default null,
  p_status text default null,
  p_erro text default null)
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
         concluido_em      = case when p_status = 'ocioso' then now() else concluido_em end
   where fonte = p_fonte;
$function$;

comment on function public.mind_sync_abrir(text) is
  'Abre uma corrida de sincronizacao: devolve a marca dagua, a tabela de destino e a config da integracao, e marca a fonte como rodando.';
comment on function public.mind_sync_marcar(text, timestamptz, int, int, text, text) is
  'Registra o progresso de uma corrida. Chamada por pagina -- a marca dagua so anda depois de gravar.';

revoke all on function public.mind_sync_abrir(text) from public, anon, authenticated;
revoke all on function public.mind_sync_marcar(text, timestamptz, int, int, text, text) from public, anon, authenticated;
