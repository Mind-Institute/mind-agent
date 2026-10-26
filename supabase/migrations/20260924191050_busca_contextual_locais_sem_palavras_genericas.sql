-- Ajuste do galho `locais` de 20260924191025: "evento", "mind" e "summit" estão em quase toda
-- descrição de local e traziam a Arena Mind para "Tem Wi-Fi no evento?". Saem do foco.
-- A 20260924191025 versionada já nasce com o filtro; aqui só se aplica onde ele falta.

do $migra$
declare d text; o text;
begin
  d := pg_get_functiondef('public.mind_intelligence_buscar_contextual(text,integer,text,text,text,vector)'::regprocedure);
  if position($x$lexeme not in ('event','mind','summit')$x$ in d) > 0 then return; end if;
  o := d;
  d := replace(d, $x$    from unnest(to_tsvector('portuguese',coalesce(btrim(p_necessidade),''))) l
  ), locais as ($x$, $x$    from unnest(to_tsvector('portuguese',coalesce(btrim(p_necessidade),''))) l
    where l.lexeme not in ('event','mind','summit')
  ), locais as ($x$);
  if d = o then raise exception 'foco dos locais não encontrado'; end if;
  execute d;
end $migra$;
