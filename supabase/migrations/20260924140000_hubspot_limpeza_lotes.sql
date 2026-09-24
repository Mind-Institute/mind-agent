-- Limpeza do HubSpot aprovada pela Adriana (24/09/2026, itens 1–9 de docs/HUBSPOT_LIMPEZA_APROVACAO.md).
-- Um lote de operações é gravado em mind_admin_audit e executado uma única vez pela edge function
-- hubspot-limpeza, que não aceita operações vindas de fora. Nenhuma tabela nova.

create or replace function public.mind_hubspot_limpeza_lote(p_lote text, p_ops jsonb, p_quem text)
returns uuid language plpgsql security definer set search_path to 'public'
as $$
declare v_id uuid := gen_random_uuid();
begin
  if exists (select 1 from public.mind_admin_audit where resource = 'hubspot_limpeza_resultado' and record_id = p_lote) then
    raise exception 'lote % já executado', p_lote;
  end if;
  insert into public.mind_admin_audit (id, action, resource, record_id, record_label, after_data, request_id)
  values (v_id, 'criar', 'hubspot_limpeza_lote', p_lote, 'lote de limpeza do HubSpot — ' || coalesce(p_quem, '?'),
          jsonb_build_object('ops', p_ops), gen_random_uuid());
  return v_id;
end $$;

create or replace function public.mind_hubspot_limpeza_disparar(p_lote text)
returns bigint language plpgsql security definer set search_path to 'public', 'platform', 'net'
as $$
declare v_base text; v_key text;
begin
  select base_url, config->>'anon_key' into v_base, v_key from platform.integracoes where codigo = 'supabase_functions' and ativo;
  if v_base is null or v_key is null then raise exception 'integracao supabase_functions sem base_url ou anon_key'; end if;
  return net.http_post(url := v_base || '/hubspot-limpeza',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
    body := jsonb_build_object('lote', p_lote), timeout_milliseconds := 300000);
end $$;

revoke all on function public.mind_hubspot_limpeza_lote(text, jsonb, text) from public, anon, authenticated;
revoke all on function public.mind_hubspot_limpeza_disparar(text) from public, anon, authenticated;
