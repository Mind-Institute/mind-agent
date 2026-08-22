-- gen_random_bytes vive em pgcrypto (schema extensions) e nao esta no
-- search_path da funcao. gen_random_uuid e core do Postgres e basta.
create or replace function public.mind_utm_registrar(p_dados jsonb)
returns text
language plpgsql
security definer
set search_path = public, mind
as $fn$
declare
  t text;
  tentativa int := 0;
begin
  loop
    t := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
    exit when not exists (select 1 from mind.utm_sessoes where token = t);
    tentativa := tentativa + 1;
    if tentativa > 20 then raise exception 'nao foi possivel gerar token'; end if;
  end loop;

  insert into mind.utm_sessoes (
    token, site, origem_codigo, utm_source, utm_medium, utm_campaign,
    utm_content, utm_term, gclid, fbclid, referrer, landing_url)
  values (
    t,
    left(nullif(trim(p_dados->>'site'),''), 40),
    (select o.codigo from mind.origens o
      where o.codigo = nullif(trim(p_dados->>'origem'),'') and o.ativo),
    left(nullif(trim(p_dados->>'utm_source'),''), 120),
    left(nullif(trim(p_dados->>'utm_medium'),''), 120),
    left(nullif(trim(p_dados->>'utm_campaign'),''), 200),
    left(nullif(trim(p_dados->>'utm_content'),''), 200),
    left(nullif(trim(p_dados->>'utm_term'),''), 200),
    left(nullif(trim(p_dados->>'gclid'),''), 200),
    left(nullif(trim(p_dados->>'fbclid'),''), 200),
    left(nullif(trim(p_dados->>'referrer'),''), 500),
    left(nullif(trim(p_dados->>'landing_url'),''), 500));

  return t;
end;
$fn$;
grant execute on function public.mind_utm_registrar(jsonb) to anon, authenticated;
