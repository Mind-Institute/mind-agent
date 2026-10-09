-- A busca do agente passa a encontrar LOCAIS do evento, com os apelidos no resumo.
--
-- Caso real (17/09, 00:07): "Há algum lugar onde eu possa guardar minha mala??" -> o agente
-- respondeu "não encontrei confirmação de guarda-volumes". A Chapelaria existe em
-- `summit_2026.locations`, com os apelidos "guarda-volumes", "guardar bagagem", "deixar
-- mochila". Três defeitos somados:
--   1. `mind_intelligence_buscar_contextual` (a ferramenta `buscar_intelligence` do concierge)
--      aproveitava da busca do evento só palestrantes e sessões — local nunca virava candidato,
--      embora `mind_intelligence_ler` saiba ler `local`;
--   2. a busca do evento usa AND entre as palavras, então a frase inteira não casava nada;
--   3. o resumo do local não mostrava os apelidos, então "Chapelaria" não dizia "mala".
--
-- Menor mudança, na casa que já existe:
--   * `buscar_contextual` ganha o galho `locais` para as rotas do Summit: OR entre as palavras
--     (o mesmo `foco` de `mind_intelligence_buscar`, sem "evento/mind/summit", que estão em
--     toda descrição e trariam a Arena para "tem Wi-Fi no evento?"), casando nome, slug, apelidos, descrição e
--     como chegar; resumo com "também chamado: <apelidos>"; no máximo 2 locais, pontuados acima
--     do conhecimento genérico (0,02 + rank) para não sumirem atrás de documentos;
--   * a Chapelaria ganha os apelidos "mala", "malas", "guardar mala".
--
-- Reversível: recriar a função pela 20260923051546 e tirar os três apelidos.

do $migra$
declare
  d text; o text;
begin
  d := pg_get_functiondef('public.mind_intelligence_buscar_contextual(text,integer,text,text,text,vector)'::regprocedure);
  o := d;

  d := replace(d, $x$  ), outros as ($x$, $x$  ), foco as (
    select nullif(string_agg(quote_literal(l.lexeme),' | '),'')::tsquery q
    from unnest(to_tsvector('portuguese',coalesce(btrim(p_necessidade),''))) l
    where l.lexeme not in ('event','mind','summit')
  ), locais as (
    select jsonb_build_object('tipo','local','id',l.id::text,'titulo',l.nome,
      'resumo',nullif(concat_ws(' · ',nullif(l.tipo,''),nullif(l.andar,''),nullif(l.descricao,''),
        nullif(l.como_chegar,''),
        case when cardinality(l.aliases)>0 then 'também chamado: '||array_to_string(l.aliases,', ') end),'')) candidato,
      (0.02+ts_rank_cd(to_tsvector('portuguese',l.nome||' '||coalesce(l.slug,'')||' '||
        coalesce(array_to_string(l.aliases,' '),'')||' '||coalesce(l.descricao,'')||' '||coalesce(l.como_chegar,'')),f.q))::double precision score
    from summit_2026.locations l
    join summit_2026.events e on e.id=l.event_id and e.slug='mind-summit-2026' and e.ativo
    cross join foco f
    where coalesce(p_rota,'') in ('summit_b2c','summit_b2b','concierge_summit','cliente_suporte')
      and f.q is not null and l.ativo
      and to_tsvector('portuguese',l.nome||' '||coalesce(l.slug,'')||' '||
        coalesce(array_to_string(l.aliases,' '),'')||' '||coalesce(l.descricao,'')||' '||coalesce(l.como_chegar,''))@@f.q
    order by score desc limit 2
  ), outros as ($x$);
  if d = o then raise exception 'buscar_contextual: ponto de inserção dos locais não encontrado'; end if;

  o := d;
  d := replace(d, $x$    union all select candidato,score from outros$x$,
                  $x$    union all select candidato,score from outros
    union all select candidato,score from locais$x$);
  if d = o then raise exception 'buscar_contextual: união final não encontrada'; end if;

  execute d;
end $migra$;

update summit_2026.locations
   set aliases = aliases || array(select a from unnest(array['mala','malas','guardar mala']) a
                                   where a <> all(aliases)),
       atualizado_em = now()
 where slug = 'chapelaria'
   and not (aliases @> array['mala','malas','guardar mala']);
