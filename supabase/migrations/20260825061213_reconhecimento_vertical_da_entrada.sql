-- 20260825061213_reconhecimento_vertical_da_entrada
--
-- Reconhecimento: de qual frente (vertical) a pessoa veio.
-- A entrada (site do chat OU host do hs_analytics_first_url) carrega a VERTICAL,
-- nao o produto especifico. Isto NAO grava nada: apenas deriva. Gravar em
-- intelligence.sinais_comerciais.vertical dependera de haver pessoa
-- (pessoas.pessoas hoje esta vazia; o edge function passa participante_id
-- quando existir).
--
-- Classe C (schema + funcao). Aplicada no projeto mind-agent. Reversivel.
-- Testada contra os 11.573 contatos reais de crm.contato_espelho:
--   summit 1069 / institute 110 / dash 1 / desconhecido 2 (dominio nao-Mind).

-- Mapa host -> vertical, primeira classe e data-driven. Semeado com os dominios
-- REAIS observados em crm.contato_espelho.hs_analytics_first_url.
create table if not exists catalogo.vertical_dominios (
  padrao   text primary key,
  vertical text not null check (vertical in ('summit','institute','eventos','dash','outro')),
  nota     text
);
comment on table catalogo.vertical_dominios is
  'Mapa host->vertical para reconhecer de qual frente a pessoa veio a partir do first_url. Semeado com dominios reais; adicionar padroes conforme novas frentes surgirem.';

insert into catalogo.vertical_dominios (padrao, vertical, nota) values
  ('mindsummit',    'summit',    'mindsummit.com.br / .company / .net.br / lp / ingressos / calculadora'),
  ('mindinstitute', 'institute', 'my.mindinstitute.com.br'),
  ('minddash',      'dash',      'www.minddash.online')
on conflict (padrao) do nothing;

-- Deriva a vertical da entrada. Prioridade: site do chat (engagement.origens) ->
-- produto -> vertical. Senao, host do URL -> catalogo.vertical_dominios.
-- Retorna null quando desconhecido: nao chuta vertical.
create or replace function intelligence.vertical_da_entrada(p_site text default null, p_url text default null)
returns text
language sql
stable
set search_path to 'pg_catalog', 'engagement', 'catalogo'
as $$
  with s as (
    select nullif(lower(btrim(coalesce(p_site,''))),'') as site,
           nullif(lower(btrim(coalesce(p_url,''))),'')  as url
  ),
  h as (
    select regexp_replace((select url from s), '^https?://([^/]+).*$', '\1') as host
  ),
  por_site as (
    select p.vertical
    from s
    join engagement.origens o on o.site = s.site
    join catalogo.produtos p on p.codigo = o.produto_codigo
    where s.site is not null
    limit 1
  ),
  por_dominio as (
    select vd.vertical
    from h
    join catalogo.vertical_dominios vd
      on h.host is not null and h.host like '%' || vd.padrao || '%'
    order by length(vd.padrao) desc
    limit 1
  )
  select coalesce((select vertical from por_site), (select vertical from por_dominio));
$$;
comment on function intelligence.vertical_da_entrada(text, text) is
  'De qual frente (vertical) a pessoa veio: prioriza engagement.origens.site; senao deriva do host do first_url via catalogo.vertical_dominios. Retorna null quando desconhecido (nao chuta).';

-- ROLLBACK:
--   drop function if exists intelligence.vertical_da_entrada(text, text);
--   drop table if exists catalogo.vertical_dominios;
