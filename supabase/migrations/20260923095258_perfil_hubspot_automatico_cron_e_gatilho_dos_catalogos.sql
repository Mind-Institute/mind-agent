-- =====================================================================================
-- Automático do perfil → HubSpot (pedido da Adriana, 23/09/2026: "toda vez que [as tabelas de ICP e
-- JTBD] fizerem mudança, algo automático que, ao mudar aqui, mude automaticamente no HubSpot").
-- Condições cumpridas antes de ligar (revisão de 23/09): guarda de última escrita na Edge Function (v3+),
-- ICP do próprio Mind não conta como manual (perfil_projetar), JTBD como conjunto quando o HubSpot tem
-- o que o Mind escreveu (mapping.ts v4), perfil_projetar só carimba atualizado_em quando muda.
--  1. mind_hubspot_perfil_disparar: chama a Edge Function pela porta interna (anon JWT + analise_token);
--  2. perfil_projetar_todos: as 16 fatias de perfil_projetar_lote numa chamada (~40 s);
--  3. pg_cron: projeção ao minuto 36 e write-back ao minuto 41 de cada hora, só para quem teve memória
--     icp/jtbd/cargo/empresa alterada nas últimas 2 h (p_desde) — fora dos horários dos outros jobs
--     (:00/:30 preços, :15 análises, :20/:50 Eduzz, 06:17–06:35 espelhos do HubSpot);
--  4. gatilho por comando em intelligence.icp / intelligence.jtbd: editar o catálogo chama
--     acao "propriedades" (rótulos, ordem, opções novas) — assíncrono, nunca derruba a edição.
-- =====================================================================================

create or replace function public.mind_hubspot_perfil_disparar(p_acao text default 'contatos', p_executar boolean default true, p_desde interval default interval '2 hours')
returns bigint
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'platform', 'intelligence'
as $fn$
declare v_base text; v_key text; v_token text; v_body jsonb;
begin
  select i.base_url, i.config->>'anon_key' into v_base, v_key
    from platform.integracoes i where i.codigo = 'supabase_functions' and i.ativo;
  select c.valor into v_token from intelligence.config c where c.chave = 'analise_token';
  if v_base is null or v_key is null or v_token is null then
    raise exception 'mind_hubspot_perfil_disparar: integração supabase_functions ou analise_token ausentes';
  end if;
  if p_acao not in ('contatos', 'propriedades') then
    raise exception 'mind_hubspot_perfil_disparar: acao inválida %', p_acao;
  end if;
  v_body := jsonb_build_object('token', v_token, 'acao', p_acao, 'executar', p_executar);
  if p_acao = 'contatos' and p_desde is not null then
    v_body := v_body || jsonb_build_object('desde', to_char((now() - p_desde) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
  end if;
  return net.http_post(
    url := v_base || '/hubspot-perfil-writeback',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
    body := v_body,
    timeout_milliseconds := 150000);
end $fn$;
revoke execute on function public.mind_hubspot_perfil_disparar(text, boolean, interval) from public, anon, authenticated;
comment on function public.mind_hubspot_perfil_disparar(text, boolean, interval) is 'Dispara a Edge Function hubspot-perfil-writeback pela porta interna (pg_net): acao contatos (com recorte desde = agora − p_desde) ou propriedades. Devolve o id da requisição em net._http_response. Usada pelo cron horário e pelo gatilho dos catálogos.';

create or replace function intelligence.perfil_projetar_todos(p_gravar boolean default true)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'intelligence'
as $fn$
declare v jsonb := '[]'::jsonb; p text; r jsonb; v_pessoas int := 0; v_ini timestamptz := clock_timestamp();
begin
  foreach p in array array['0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'] loop
    r := intelligence.perfil_projetar_lote(p, p_gravar);
    v := v || r;
    v_pessoas := v_pessoas + coalesce((r->>'pessoas')::int, 0);
  end loop;
  return jsonb_build_object('pessoas', v_pessoas, 'gravou', p_gravar,
                            'segundos', round(extract(epoch from clock_timestamp() - v_ini)::numeric, 1), 'fatias', v);
end $fn$;
revoke execute on function intelligence.perfil_projetar_todos(boolean) from public, anon, authenticated;
comment on function intelligence.perfil_projetar_todos(boolean) is 'Reprojeta o perfil (ICP, cargo/empresa, JTBD) de todas as pessoas com evidência, nas 16 fatias de perfil_projetar_lote. Só toca memória que mudou. Roda no cron horário antes do write-back do HubSpot.';

-- cron: projeção às hh:36, write-back às hh:41 (quem mudou nas últimas 2 h)
select cron.schedule('perfil_projetar_horario', '36 * * * *', $$select intelligence.perfil_projetar_todos(true)$$);
select cron.schedule('hubspot_perfil_writeback_horario', '41 * * * *', $$select public.mind_hubspot_perfil_disparar('contatos', true, interval '2 hours')$$);

-- catálogo editado → alinhar as propriedades icp/jtbd (rótulos, ordem, opções) e criar o resumo se faltar
create or replace function intelligence.catalogo_alinhar_hubspot()
returns trigger
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'intelligence'
as $fn$
begin
  perform public.mind_hubspot_perfil_disparar('propriedades', true, null);
  return null;
exception when others then
  raise warning 'catalogo_alinhar_hubspot: % (a edição do catálogo foi mantida)', sqlerrm;
  return null;
end $fn$;
comment on function intelligence.catalogo_alinhar_hubspot() is 'Gatilho por comando em intelligence.icp / intelligence.jtbd: qualquer edição do catálogo dispara acao propriedades na Edge Function hubspot-perfil-writeback (assíncrono via pg_net). Erro no disparo vira warning; a edição nunca é bloqueada.';
drop trigger if exists icp_alinhar_hubspot on intelligence.icp;
create trigger icp_alinhar_hubspot after insert or update or delete on intelligence.icp
  for each statement execute function intelligence.catalogo_alinhar_hubspot();
drop trigger if exists jtbd_alinhar_hubspot on intelligence.jtbd;
create trigger jtbd_alinhar_hubspot after insert or update or delete on intelligence.jtbd
  for each statement execute function intelligence.catalogo_alinhar_hubspot();
