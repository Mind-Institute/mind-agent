insert into treble.config (chave, valor)
values ('janela_urgencia_dias', '7')
on conflict (chave) do update set valor = excluded.valor;

alter table mind.offers
  add column if not exists procura text not null default 'normal'
    check (procura in ('normal','alta','ultimas_vagas')),
  add column if not exists procura_nota text;

comment on column mind.offers.procura is
  'Nivel de procura desta categoria. So o agente pode citar escassez quando este campo disser que ela existe — nunca por deducao.';

update mind.offers
   set procura = 'alta',
       procura_nota = 'Categoria com bastante venda. Pode dizer que tem alta procura e que, na virada de lote, quem estava em duvida corre — sem prometer que vai esgotar em data nenhuma.',
       atualizado_em = now()
 where elegibilidade->>'categoria' in ('vip','prime');

create or replace function public.mind_virada_de_lote()
returns jsonb
language sql
security definer
set search_path = public, mind, treble
as $fn$
  with janela as (
    select coalesce((select valor::int from treble.config where chave = 'janela_urgencia_dias'), 7) as dias
  ), atual as (
    select o.elegibilidade->>'categoria' as categoria, o.valor, o.encerra_em
    from mind.offers o
    where o.ativo and o.publico and o.encerra_em is not null
      and not (o.elegibilidade ? 'grupo')
  ), fim as (
    select min(encerra_em) as encerra_em from atual
  ), proximo as (
    select o.elegibilidade->>'categoria' as categoria, o.valor
    from mind.offers o
    where not o.ativo and o.inicia_em is not null and o.inicia_em > now()
      and not (o.elegibilidade ? 'grupo')
      and o.inicia_em = (select min(i.inicia_em) from mind.offers i
                          where i.inicia_em > now() and not (i.elegibilidade ? 'grupo'))
  ), conta as (
    select f.encerra_em,
           ((f.encerra_em at time zone 'America/Sao_Paulo')::date
            - (now() at time zone 'America/Sao_Paulo')::date) as dias_restantes,
           j.dias as janela_dias
    from fim f cross join janela j
  )
  select case when (select encerra_em from conta) is null then null else
    jsonb_build_object(
      'ultimo_dia_do_lote_atual',
        to_char((select encerra_em from conta) at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'),
      'dia_da_semana',
        to_char((select encerra_em from conta) at time zone 'America/Sao_Paulo', 'TMDay'),
      'dias_restantes', (select dias_restantes from conta),
      'janela_de_comunicacao_dias', (select janela_dias from conta),
      'pode_usar_como_urgencia',
        (select dias_restantes <= janela_dias and dias_restantes >= 0 from conta),
      'como_falar', case
        when (select dias_restantes from conta) < 0 then 'Lote ja virou: nao mencione contagem.'
        when (select dias_restantes from conta) > (select janela_dias from conta)
          then 'Ainda falta muito para a virada. NAO use a virada de lote como urgencia nesta conversa; venda pelo conteudo.'
        when (select dias_restantes from conta) = 0
          then 'Hoje e o ultimo dia deste lote. Diga isso com clareza, uma vez, sem pressionar.'
        when (select dias_restantes from conta) = 1
          then 'Falta 1 dia para a virada. Pode dizer.'
        else 'Faltam ' || (select dias_restantes from conta) || ' dias para a virada. Pode dizer.' end,
      'aumentos', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'categoria', a.categoria,
                 'valor_hoje', a.valor,
                 'valor_depois_da_virada', p.valor,
                 'aumento', p.valor - a.valor) order by a.valor), '[]'::jsonb)
        from atual a join proximo p on p.categoria = a.categoria
        where p.valor > a.valor)
    ) end;
$fn$;
revoke all on function public.mind_virada_de_lote() from public, anon, authenticated;

comment on function public.mind_virada_de_lote() is
  'Contagem oficial ate a virada de lote: dias restantes, se a janela de comunicacao esta aberta, e quanto cada categoria sobe. O agente nao conta dias sozinho.';
