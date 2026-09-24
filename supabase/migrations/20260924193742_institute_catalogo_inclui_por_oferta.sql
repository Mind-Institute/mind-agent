-- O que cada oferta inclui fica na OFERTA, não no programa: só a condição Summit da Certificação
-- traz o Mind Journey; o preço regular não. Na versão aplicada primeiro, "inclui" vinha somado no
-- programa e fazia o preço regular parecer incluir o Journey. A 20260924193707 versionada já nasce
-- com a forma certa; aqui só se aplica onde ela falta.

do $migra$
declare d text; o text;
begin
  d := pg_get_functiondef('public.mind_kit_institute_catalogo(uuid,jsonb)'::regprocedure);
  if position('''inclui'', (select jsonb_agg(pp.nome order by pp.ordem)' in d) > 0 then return; end if;
  o := d;
  d := replace(d, $x$        'inclui_as_formacoes', (
          select jsonb_agg(distinct pp.nome)
            from api.oferta_inclui oi
            join ofertas o on o.codigo = oi.oferta_codigo and o.programa_codigo = p.codigo
            join api.programas pp on pp.codigo = oi.programa_codigo
           where oi.programa_codigo <> p.codigo),
$x$, '');
  if d = o then raise exception 'inclui do programa não encontrado'; end if;
  o := d;
  d := replace(d, $x$                   'valida_ate', to_char(o.encerra_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY "às" HH24"h"MI'),
$x$, $x$                   'valida_ate', to_char(o.encerra_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY "às" HH24"h"MI'),
                   'inclui', (select jsonb_agg(pp.nome order by pp.ordem)
                                from api.oferta_inclui oi join api.programas pp on pp.codigo = oi.programa_codigo
                               where oi.oferta_codigo = o.codigo and oi.programa_codigo <> p.codigo),
$x$);
  if d = o then raise exception 'valida_ate da oferta não encontrado'; end if;
  execute d;
end $migra$;
