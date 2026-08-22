
update mind.locations
set aliases = (
  select array_agg(distinct alias order by alias)
  from unnest(
    coalesce(aliases, '{}'::text[]) ||
    case slug
      when 'praca-alimentacao' then array['comer','onde comer','almoço','almoco','almoçar','almocar','lanche','refeição','refeicao']
      when 'barracas-alimentacao' then array['comer','lanche','quiosque de comida']
      when 'chapelaria' then array['guardar mochila','guardar bagagem','guardar casaco','deixar mochila']
      when 'credenciamento' then array['fazer check-in','pegar credencial','pegar crachá','retirar crachá']
      when 'entrada-principal' then array['como entrar','por onde entro']
      when 'saida-principal' then array['como sair','por onde saio']
      else '{}'::text[]
    end
  ) alias
)
where slug in (
  'praca-alimentacao','barracas-alimentacao','chapelaria',
  'credenciamento','entrada-principal','saida-principal'
);
