-- "Outros" no HubSpot não é dado (REGRA_ICP_POR_CARGO.md: "Outros" = não escreveu um cargo ou está fora
-- do mercado). Quando o contato tem ICP "Outros" e o banco tem algo melhor, a troca passa como a do
-- credenciamento (forcar), em vez de ficar como conflito de "valor manual". Na primeira execução de
-- 24/09 eram 22 contatos (advogadas, jornalistas… que o HubSpot guardava como "Outros").
do $migra$
declare d text := pg_get_functiondef('public.mind_hubspot_perfil_plano(timestamptz)'::regprocedure); o text;
begin
  o := d;
  d := replace(d, $x$         y.cargo is not null as forcar$x$,
                  $x$         (y.cargo is not null
           or (icp.hubspot_valor is not null and icp.hubspot_valor <> 'Outros'
               and exists (select 1 from crm.contato_espelho ce
                            where ce.hubspot_id = ct.hubspot_id and lower(btrim(ce.icp)) = 'outros'))) as forcar$x$);
  if d = o then raise exception 'mind_hubspot_perfil_plano: trecho do forcar não encontrado'; end if;
  execute d;
end $migra$;
