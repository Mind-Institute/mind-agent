-- ============================================================
-- Avaliação do dia — a consulta que alimenta o relatório em PDF
-- ============================================================
-- Rode no SQL Editor do Supabase, copie a coluna `dados` e salve em um
-- arquivo. Depois:
--
--     npm run relatorio:avaliacao -- <arquivo.json>
--
-- Por que consulta e script separados, e não um script que busca
-- sozinho: o token do operador (`MINDAGENT_ADMIN_TOKEN`) vence em cerca
-- de uma hora, e um relatório que falha por token vencido justo na hora
-- em que alguém pede é pior que dois passos. A consulta lê direto, o
-- script só desenha.
--
-- CONTÉM DADO PESSOAL: nome, e-mail, profissão e os textos escritos
-- pelos participantes. O PDF gerado é de uso interno e está no
-- `.gitignore` — não se versiona.
--
-- Para um dia só, troque o `null` da primeira linha por uma data:
--     with p as (select date '2026-09-16' as dia_alvo, ...

with p as (
  select null::date as dia_alvo, 'mind-summit-2026' as slug
),
ev as (
  select e.* from summit_2026.events e, p where e.slug = p.slug
),

-- ============================================================
-- AS RESPOSTAS DA MADRUGADA — 5 respostas, 47 notas de atividade
-- ============================================================
-- A pesquisa do dia vira à meia-noite, mas o app só trocou a tela do dia
-- 1 para o dia 2 pela manhã. Cinco pessoas responderam entre 00h15 e
-- 07h47 do dia 17 FALANDO DO DIA 1, e o formulário gravou a resposta
-- como sendo do dia 2 — com 47 notas para sessões que ainda não tinham
-- acontecido.
--
-- As notas gerais delas são opinião real e continuam valendo. O que não
-- vale é a nota POR ATIVIDADE: ninguém avalia uma palestra às 6h40 da
-- manhã do dia em que ela começa às 15h. Por isso só a tabela por
-- atividade as exclui, e o resto do relatório não.
--
-- Isto estava sendo feito à mão fora da consulta, e o relatório seguinte
-- teria voltado a incluí-las sem ninguém notar: as notas afetadas não
-- somem, elas só puxam a média para baixo. Medido: no dia 2 a mesma
-- sessão ficava 0,89 abaixo da nota que recebeu na pesquisa do evento,
-- contra 0,25 no dia 1 — e "Em curadoria", que não tem conteúdo nenhum,
-- aparecia com 2,33.
--
-- O CONSERTO DE VERDADE é corrigir `dia` nessas cinco linhas, e isso é
-- escrita em dado de participante: precisa do gate. Enquanto não houver,
-- a consulta exclui e diz por quê.
madrugada as (
  select r.id
  from engagement.avaliacao_do_dia r
  where r.event_id = (select id from ev)
    and r.dia = date '2026-09-17'
    and (r.enviado_em at time zone (select fuso from ev))::time < time '08:00'
)
select jsonb_pretty(jsonb_build_object(

  'evento',   (select nome from ev),
  'geradoEm', to_char(now() at time zone (select fuso from ev), 'DD/MM/YYYY HH24:MI'),
  'recorte',  coalesce((select dia_alvo::text from p), 'todos os dias'),

  'respostas', coalesce((
    select jsonb_agg(jsonb_build_object(
      'quando',       to_char(r.enviado_em at time zone (select fuso from ev), 'DD/MM HH24:MI'),
      'dia',          r.dia,
      'nome',         nullif(btrim(coalesce(pe.primeiro_nome,'') || ' ' || coalesce(pe.sobrenome,'')), ''),
      'email',        pe.email,
      'experiencia',  r.experiencia,
      'profissao',    r.profissao,
      'relevancia',   r.nota_relevancia,
      'programacao',  r.nota_programacao,
      'expectativas', r.expectativas,
      'maisGostou',   r.mais_gostou,
      'melhorar',     r.melhorar,
      'comentario',   r.comentario,
      'atividades',   (select count(*) from engagement.avaliacao_do_dia_atividade t
                        where t.avaliacao_id = r.id))
      order by r.enviado_em desc)
    from engagement.avaliacao_do_dia r
    join pessoas.pessoas pe on pe.id = r.participante_id
    cross join p
    where r.event_id = (select id from ev)
      and (p.dia_alvo is null or r.dia = p.dia_alvo)
  ), '[]'::jsonb),

  -- Blocos operacionais ficam de fora: credenciamento, intervalo e
  -- almoço não recebem nota, então não são linha de relatório.
  -- ORDEM POR DIA E HORÁRIO, e não por nota. O relatório agrupa esta
  -- lista escrevendo um cabeçalho toda vez que o dia MUDA: ordenada por
  -- nota, ela alterna 16/09 e 17/09 dezenas de vezes e imprime um
  -- cabeçalho por linha. A tabela é lida percorrendo a programação.
  --
  -- E `dia` sai formatado: cru ele chega como `2026-09-16` e é isso que
  -- apareceria no cabeçalho do grupo. A ordenação usa a data de verdade
  -- (`x.data`), não o texto — 'DD/MM' ordena errado na virada do ano.
  'porAtividade', coalesce((
    select jsonb_agg(jsonb_build_object(
             'titulo', x.titulo, 'dia', x.dia, 'inicio', x.inicio,
             'espaco', x.espaco, 'n', x.n, 'media', x.media)
           order by x.data, x.inicio, x.titulo)
    from (
      select s.titulo, s.dia as data,
             to_char(s.dia, 'DD/MM') as dia,
             to_char(s.inicio at time zone (select fuso from ev), 'HH24:MI') as inicio,
             l.nome as espaco,
             count(t.nota) as n,
             -- `avg` de conjunto vazio é null, e nada aqui o transforma em
             -- zero: atividade sem nota não é atividade ruim.
             round(avg(t.nota), 2) as media
      -- `cross join p` DEPOIS dos left join, e não `, p` antes: a vírgula
      -- liga mais forte que o join explícito, e `s` deixaria de existir
      -- para o `on` que vem em seguida. Custou um 42P01 para aparecer.
      from summit_2026.sessions s
      left join summit_2026.locations l on l.id = s.espaco_id
      -- A exclusão vai no `on`, e NÃO no `where`: no `where` ela
      -- transformaria o left join em inner e a sessão que ficasse sem
      -- nenhuma nota sumiria da tabela, em vez de aparecer como "Sem
      -- avaliações". É a diferença entre "ninguém avaliou" e "não
      -- existe".
      left join engagement.avaliacao_do_dia_atividade t
             on t.sessao_id = s.id
            and t.avaliacao_id not in (select id from madrugada)
      cross join p
      where s.event_id = (select id from ev)
        and (p.dia_alvo is null or s.dia = p.dia_alvo)
        and s.tipo is distinct from 'credenciamento'
        and s.tipo is distinct from 'intervalo'
        and s.tipo is distinct from 'almoco'
      group by s.id, s.titulo, s.dia, s.inicio, l.nome
    ) x
  ), '[]'::jsonb),

  -- ============================================================
  -- A OUTRA PESQUISA — Avaliação do EVENTO
  -- ============================================================
  -- Mora aqui dentro, e não numa consulta separada, porque um relatório
  -- montado a partir de dois arquivos é um relatório que um dia sai com
  -- as duas metades de datas diferentes. Uma consulta, um retrato.
  --
  -- As notas NÃO se somam às de cima: são perguntas diferentes sobre
  -- recortes diferentes — uma sobre o dia, outra sobre o Summit inteiro.
  -- Por isso `pesquisaDoEvento` é um objeto próprio e não uma linha a
  -- mais em `respostas`.
  --
  -- E o corte desta é POR INGRESSO, não por dia: a pesquisa do evento
  -- não tem `dia`, e quem viveu Mind, VIP e Prime viveu eventos
  -- diferentes. `p.dia_alvo` não se aplica — recortar por data uma
  -- pesquisa que fala do evento todo daria um número sem pergunta.
  'pesquisaDoEvento', jsonb_build_object(

    'apoio', coalesce((
      select 'de ' || to_char(min(enviado_em) at time zone (select fuso from ev), 'DD/MM') ||
             ' a '  || to_char(max(enviado_em) at time zone (select fuso from ev), 'DD/MM')
      from engagement.avaliacao_do_evento where event_id = (select id from ev)
    ), 'ainda sem respostas'),

    'respostas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'quando',       to_char(r.enviado_em at time zone (select fuso from ev), 'DD/MM HH24:MI'),
        'nome',         nullif(btrim(coalesce(pe.primeiro_nome,'') || ' ' || coalesce(pe.sobrenome,'')), ''),
        'email',        pe.email,
        'origem',       r.origem,
        'experiencia',  r.experiencia,
        'profissao',    r.profissao,
        'relevancia',   r.nota_relevancia,
        'programacao',  r.nota_programacao,
        'expectativas', r.expectativas,
        'maisGostou',   r.mais_gostou,
        'melhorar',     r.melhorar,
        'comentario',   r.comentario,
        -- A versão do formulário fica na linha: quem respondeu a v1 não
        -- viu a grade de atividades, e `0 atividades` nela significa
        -- "não perguntamos", não "não gostou de nada".
        'versao',       r.formulario_versao,
        'atividades',   (select count(*) from engagement.avaliacao_do_evento_atividade t
                          where t.avaliacao_id = r.id))
        order by r.enviado_em)
      from engagement.avaliacao_do_evento r
      join pessoas.pessoas pe on pe.id = r.participante_id
      where r.event_id = (select id from ev)
    ), '[]'::jsonb),

    -- O `group by` vai numa subconsulta, e não direto dentro do
    -- `jsonb_agg`: `count(*)` ali dentro é agregado dentro de agregado, e
    -- o Postgres recusa com 42803. Mesma forma do `porAtividade` acima —
    -- agrupa primeiro, monta o JSON depois.
    'porTicket', coalesce((
      select jsonb_agg(jsonb_build_object(
               'rotulo', x.rotulo, 'n', x.n,
               'relevancia', x.relevancia, 'programacao', x.programacao,
               'p45relevancia', x.p45relevancia, 'p45programacao', x.p45programacao,
               -- Uma linha de uma resposta só precisa dizer isso de si
               -- mesma; sem a ressalva ela é lida como tendência.
               'apoio', case when x.n = 1
                 then 'uma resposta só — a linha está aqui para não sumir, não para comparar'
                 end)
             -- Mind, VIP, Prime: a ordem do ingresso, não a alfabética.
             order by x.ordem)
      from (
        select case r.experiencia when 'mind' then 'Mind'
                                  when 'vip'  then 'VIP'
                                  else 'Prime' end as rotulo,
               case r.experiencia when 'mind' then 1
                                  when 'vip'  then 2
                                  else 3 end as ordem,
               count(*) as n,
               avg(r.nota_relevancia)  as relevancia,
               avg(r.nota_programacao) as programacao,
               round(100.0 * count(*) filter (where r.nota_relevancia  >= 4) / count(*)) as p45relevancia,
               round(100.0 * count(*) filter (where r.nota_programacao >= 4) / count(*)) as p45programacao
        from engagement.avaliacao_do_evento r
        where r.event_id = (select id from ev)
        group by r.experiencia
      ) x
    ), '[]'::jsonb),

    'porAtividade', coalesce((
      select jsonb_agg(jsonb_build_object(
               'titulo', x.titulo, 'dia', x.dia, 'inicio', x.inicio,
               'espaco', x.espaco, 'n', x.n, 'media', x.media)
             -- Por dia e horário, e não por nota: esta tabela é lida
             -- como a grade do evento, percorrendo a programação. Pela
             -- data de verdade, não pelo texto 'DD/MM'.
             order by x.data, x.inicio, x.titulo)
      from (
        select s.titulo, s.dia as data,
               to_char(s.dia, 'DD/MM') as dia,
               to_char(s.inicio at time zone (select fuso from ev), 'HH24:MI') as inicio,
               l.nome as espaco,
               count(t.nota) as n,
               round(avg(t.nota), 2) as media
        from summit_2026.sessions s
        left join summit_2026.locations l on l.id = s.espaco_id
        left join engagement.avaliacao_do_evento_atividade t on t.sessao_id = s.id
        where s.event_id = (select id from ev)
          and s.tipo is distinct from 'credenciamento'
          and s.tipo is distinct from 'intervalo'
          and s.tipo is distinct from 'almoco'
        group by s.id, s.titulo, s.dia, s.inicio, l.nome
      ) x
    ), '[]'::jsonb)

  )

)) as dados;
