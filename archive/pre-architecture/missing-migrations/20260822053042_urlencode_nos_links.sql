-- "utm_term=evento bem estar corporativo" com espacos literais quebra o
-- link no WhatsApp. Postgres nao tem urlencode nativo; este faz
-- percent-encoding UTF-8 correto.
create or replace function public.mind_urlencode(p text)
returns text
language sql immutable
as $fn$
  select coalesce(string_agg(
    case when c ~ '^[A-Za-z0-9_.~-]$' then c
         else (select string_agg('%' || upper(substring(x.h from i for 2)), '')
                 from (select encode(convert_to(c, 'UTF8'), 'hex') as h) x,
                      generate_series(1, length(x.h), 2) as i)
    end, '' order by n), '')
  from unnest(string_to_array(p, null)) with ordinality as u(c, n);
$fn$;

create or replace function public.mind_checkout_url(
  p_url text,
  p_utm jsonb default null,
  p_origem text default null,
  p_conversa text default null
) returns text
language sql stable security definer set search_path = public, mind
as $fn$
  select p_url
      || case when position('?' in p_url) > 0 then '&' else '?' end
      -- UTM original intacta: quem pagou pelo clique continua levando o credito.
      || 'utm_source='   || public.mind_urlencode(coalesce(nullif(p_utm->>'utm_source',''),
                              (select o.site from mind.origens o where o.codigo = p_origem), 'mind'))
      || '&utm_medium='  || public.mind_urlencode(coalesce(nullif(p_utm->>'utm_medium',''), 'chatbot'))
      || '&utm_campaign='|| public.mind_urlencode(coalesce(nullif(p_utm->>'utm_campaign',''), 'mind-summit-2026'))
      || '&utm_content=' || public.mind_urlencode(coalesce(nullif(p_utm->>'utm_content',''),
                              nullif(p_origem,''), 'sem_origem'))
      || case when nullif(p_utm->>'utm_term','') is null then ''
              else '&utm_term=' || public.mind_urlencode(p_utm->>'utm_term') end
      -- Identificadores de clique de midia: sem eles o Google e a Meta nao
      -- fecham a conversao com o clique que a gerou.
      || case when nullif(p_utm->>'gclid','') is null then ''
              else '&gclid=' || public.mind_urlencode(p_utm->>'gclid') end
      || case when nullif(p_utm->>'fbclid','') is null then ''
              else '&fbclid=' || public.mind_urlencode(p_utm->>'fbclid') end
      -- Camada do bot: nao disputa com a UTM de midia.
      || '&mind_canal=chatbot'
      || case when nullif(p_origem,'') is null then ''
              else '&mind_origem=' || public.mind_urlencode(p_origem) end
      || case when nullif(p_conversa,'') is null then ''
              else '&mind_conversa=' || public.mind_urlencode(p_conversa) end;
$fn$;
revoke all on function public.mind_checkout_url(text, jsonb, text, text)
  from public, anon, authenticated;

create or replace function public.mind_material_link(
  p_url text, p_codigo text, p_utm_campaign text, p_canal text, p_origem text default null
) returns text
language sql stable security definer set search_path = public, mind
as $fn$
  select p_url
      || case when position('?' in p_url) > 0 then '&' else '?' end
      || 'utm_source=' || public.mind_urlencode(coalesce(
           (select o.site from mind.origens o where o.codigo = p_origem), 'mind'))
      || '&utm_medium=' || case p_canal
            when 'whatsapp_treble' then 'chatbot'
            when 'site_concierge'  then 'chatbot_concierge'
            else public.mind_urlencode(p_canal) end
      || '&utm_campaign=' || public.mind_urlencode(coalesce(nullif(p_utm_campaign,''), p_codigo))
      || '&utm_content=' || public.mind_urlencode(coalesce(nullif(p_origem,''), 'sem_origem'));
$fn$;
revoke all on function public.mind_material_link(text, text, text, text, text)
  from public, anon, authenticated;
