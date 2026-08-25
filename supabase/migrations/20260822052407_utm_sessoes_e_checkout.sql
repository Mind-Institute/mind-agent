-- Atribuicao ponta a ponta (Adriana, 2026-08-22):
-- a UTM que trouxe a pessoa para o site precisa sobreviver ate o checkout
-- da Eduzz. O WhatsApp quebra a cadeia (nao tem query string), entao o site
-- registra a UTM aqui, recebe um token curto, e manda esse token dentro do
-- texto pre-preenchido do wa.me. O cerebro le o token na primeira mensagem,
-- resolve, guarda na conversa e repassa a UTM original para o checkout.
--
-- Decisao importante: no checkout a UTM ORIGINAL vai intacta (utm_source
-- google/meta continua sendo google/meta), senao a midia paga perde o
-- credito da venda. A camada do bot vai em parametros proprios
-- (mind_canal, mind_origem, mind_conversa), que nao disputam com o utm_.

create table if not exists mind.utm_sessoes (
  token text primary key,
  site text,
  origem_codigo text references mind.origens(codigo),
  utm_source text, utm_medium text, utm_campaign text,
  utm_content text, utm_term text,
  gclid text, fbclid text,
  referrer text, landing_url text,
  criado_em timestamptz not null default now(),
  usado_em timestamptz
);
create index if not exists utm_sessoes_criado_idx on mind.utm_sessoes (criado_em desc);

comment on table mind.utm_sessoes is
  'Ponte de atribuicao site -> WhatsApp. O site registra a UTM e recebe um token curto, que viaja no texto pre-preenchido do wa.me.';

alter table mind.utm_sessoes enable row level security;

alter table treble.conversations
  add column if not exists utm jsonb,
  add column if not exists utm_token text;

-- Chamada pelo site (anon). Devolve so o token: nao le nem expoe nada.
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
    t := lower(substr(replace(encode(gen_random_bytes(8), 'base64'), '/', ''), 1, 8));
    t := regexp_replace(t, '[^a-z0-9]', '', 'g');
    exit when length(t) = 8 and not exists (select 1 from mind.utm_sessoes where token = t);
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

comment on function public.mind_utm_registrar(jsonb) is
  'O site chama com as UTMs da URL e recebe um token curto para embutir no link do WhatsApp. So escreve; nunca devolve dado de ninguem.';

-- Monta o link de checkout preservando a atribuicao original.
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
      || 'utm_source='   || coalesce(nullif(p_utm->>'utm_source',''),
                                     (select o.site from mind.origens o where o.codigo = p_origem),
                                     'mind')
      || '&utm_medium='  || coalesce(nullif(p_utm->>'utm_medium',''), 'chatbot')
      || '&utm_campaign='|| coalesce(nullif(p_utm->>'utm_campaign',''), 'mind-summit-2026')
      || '&utm_content=' || coalesce(nullif(p_utm->>'utm_content',''),
                                     nullif(p_origem,''), 'sem_origem')
      || case when nullif(p_utm->>'utm_term','') is null then ''
              else '&utm_term=' || (p_utm->>'utm_term') end
      -- Camada do bot: nao disputa com a UTM de midia.
      || '&mind_canal=chatbot'
      || case when nullif(p_origem,'') is null then '' else '&mind_origem=' || p_origem end
      || case when nullif(p_conversa,'') is null then '' else '&mind_conversa=' || p_conversa end;
$fn$;
revoke all on function public.mind_checkout_url(text, jsonb, text, text)
  from public, anon, authenticated;
