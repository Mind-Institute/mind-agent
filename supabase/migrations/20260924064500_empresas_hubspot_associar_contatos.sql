-- Associar contatos à company que já existe no HubSpot (Adriana, 24/09/2026 — passo 6 do enriquecimento).
--
-- hubspot-empresas-writeback só associava contatos às companies que ele mesmo acabou de criar. Quem tem
-- empresa em pessoas.pessoas ligada a uma company que JÁ existia no HubSpot, mas cujo contato lá não tem
-- company nenhuma, ficava sem associação. Estes pares são só aditivos: contato sem company ganha a
-- company da sua empresa. Contato já associado a outra company não entra (revisão, não sobrescrita).

create or replace function pessoas.empresas_hubspot_associar_pares()
 returns jsonb language sql stable security definer
 set search_path to 'pg_catalog', 'public', 'pessoas', 'crm'
as $$
  select coalesce(jsonb_agg(jsonb_build_object('mind_id', p.id, 'contato', p.hubspot_id, 'company', e.hubspot_company_id)), '[]'::jsonb)
    from pessoas.pessoas p
    join pessoas.empresas e on e.id = p.empresa_id and e.hubspot_company_id is not null
    join crm.contato_espelho c on c.hubspot_id::text = p.hubspot_id::text
    join crm.empresa_espelho ce on ce.hubspot_company_id = e.hubspot_company_id
   where p.hubspot_id is not null and p.fundida_em is null
     and nullif(c.propriedades->>'associatedcompanyid', '') is null;
$$;

create or replace function pessoas.empresas_hubspot_associar_registrar(p_pares jsonb)
 returns jsonb language plpgsql security definer
 set search_path to 'pg_catalog', 'public', 'pessoas'
as $$
begin
  insert into public.mind_admin_audit (action, resource, record_id, record_label, after_data, request_id)
  values ('atualizar', 'hubspot_contato_company', to_char(now(), 'YYYYMMDDHH24MISSMS'),
          'Contatos associados à company da sua empresa (HubSpot)', p_pares, gen_random_uuid());
  return jsonb_build_object('registrados', jsonb_array_length(coalesce(p_pares, '[]'::jsonb)));
end $$;

create or replace function public.mind_empresas_hubspot_associar_pares()
 returns jsonb language sql stable security definer set search_path to 'pg_catalog', 'public'
as $$ select pessoas.empresas_hubspot_associar_pares() $$;
create or replace function public.mind_empresas_hubspot_associar_registrar(p_pares jsonb)
 returns jsonb language sql security definer set search_path to 'pg_catalog', 'public'
as $$ select pessoas.empresas_hubspot_associar_registrar(p_pares) $$;
create or replace function public.mind_empresas_hubspot_associar_disparar(p_executar boolean)
 returns bigint language plpgsql security definer set search_path to 'public', 'platform', 'net'
as $$
declare v_base text; v_key text;
begin
  select base_url, config->>'anon_key' into v_base, v_key from platform.integracoes where codigo = 'supabase_functions' and ativo;
  if v_base is null or v_key is null then raise exception 'integracao supabase_functions sem base_url ou anon_key'; end if;
  return net.http_post(url := v_base || '/hubspot-empresas-writeback',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
    body := jsonb_build_object('associar', true, 'executar', p_executar), timeout_milliseconds := 150000);
end $$;

revoke all on function pessoas.empresas_hubspot_associar_pares() from public, anon, authenticated;
revoke all on function pessoas.empresas_hubspot_associar_registrar(jsonb) from public, anon, authenticated;
revoke all on function public.mind_empresas_hubspot_associar_pares() from public, anon, authenticated;
revoke all on function public.mind_empresas_hubspot_associar_registrar(jsonb) from public, anon, authenticated;
revoke all on function public.mind_empresas_hubspot_associar_disparar(boolean) from public, anon, authenticated;
grant execute on function public.mind_empresas_hubspot_associar_pares() to service_role;
grant execute on function public.mind_empresas_hubspot_associar_registrar(jsonb) to service_role;
