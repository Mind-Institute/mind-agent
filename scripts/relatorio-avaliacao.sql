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
  'porAtividade', coalesce((
    select jsonb_agg(jsonb_build_object(
             'titulo', x.titulo, 'dia', x.dia, 'inicio', x.inicio,
             'espaco', x.espaco, 'n', x.n, 'media', x.media)
           order by x.n desc, x.media desc nulls last, x.dia, x.inicio)
    from (
      select s.titulo, s.dia,
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
      left join engagement.avaliacao_do_dia_atividade t on t.sessao_id = s.id
      cross join p
      where s.event_id = (select id from ev)
        and (p.dia_alvo is null or s.dia = p.dia_alvo)
        and s.tipo is distinct from 'credenciamento'
        and s.tipo is distinct from 'intervalo'
        and s.tipo is distinct from 'almoco'
      group by s.id, s.titulo, s.dia, s.inicio, l.nome
    ) x
  ), '[]'::jsonb)

)) as dados;
