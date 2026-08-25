-- "Esse aumento, eu nem quero nunca comer. Pode apagar aumentos de tudo. Isso
-- nao e algo que eu nem gostaria que nenhum agente soubesse ou falasse."
-- (Adriana, 23/08/2026)
--
-- Sai o bloco 'aumentos' inteiro: o quanto o preco sobe na virada nao chega
-- mais a nenhum agente. Nao e questao de instruir a nao falar -- o dado nao
-- existe mais na saida, entao nao ha o que vazar.
--
-- O que sobra e a contagem, que continua servindo para o vendedor saber que a
-- janela existe. A linguagem de vendedor sai daqui e vai para o playbook.
create or replace function public.mind_virada_de_lote()
 returns jsonb
 language sql
 security definer
 set search_path to 'public', 'summit', 'comum', 'engagement', 'intelligence', 'mind', 'treble'
as $function$
  with janela as (
    select coalesce((select valor::int from treble.config where chave = 'janela_urgencia_dias'), 7) as dias
  ), atual as (
    select o.elegibilidade->>'categoria' as categoria, o.valor, o.encerra_em
    from summit.offers o
    where o.ativo and o.publico and o.encerra_em is not null
      and not (o.elegibilidade ? 'grupo')
  ), fim as (
    select min(encerra_em) as encerra_em from atual
  ), conta as (
    select f.encerra_em,
           (f.encerra_em at time zone 'America/Sao_Paulo') as fim_sp,
           ((f.encerra_em at time zone 'America/Sao_Paulo')::date
            - (now() at time zone 'America/Sao_Paulo')::date) as dias_restantes,
           j.dias as janela_dias
    from fim f cross join janela j
  )
  select case when (select encerra_em from conta) is null then null else
    jsonb_build_object(
      'ultimo_dia_do_lote_atual', to_char((select fim_sp from conta), 'DD/MM/YYYY'),
      'dia_da_semana', (select case extract(isodow from fim_sp)
          when 1 then 'segunda-feira' when 2 then 'terca-feira' when 3 then 'quarta-feira'
          when 4 then 'quinta-feira'  when 5 then 'sexta-feira' when 6 then 'sabado'
          else 'domingo' end from conta),
      'dias_restantes', (select dias_restantes from conta),
      'janela_de_comunicacao_dias', (select janela_dias from conta),
      'pode_usar_como_urgencia',
        (select dias_restantes <= janela_dias and dias_restantes >= 0 from conta)
    ) end;
$function$;

comment on function public.mind_virada_de_lote() is
  'Contagem ate a virada do lote, derivada de summit.offers. NAO devolve o quanto o preco sobe -- decisao da Adriana em 23/08/2026: nenhum agente deve saber nem falar disso. A janela vem de treble.config.janela_urgencia_dias, que ainda esta no lugar errado: e condicao comercial do Summit, nao config do Treble.';
