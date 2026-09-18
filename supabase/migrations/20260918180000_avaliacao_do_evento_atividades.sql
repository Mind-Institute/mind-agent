-- ============================================================
-- Avaliação do evento — as notas por atividade voltam
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
--
-- POR QUE ESTA MIGRATION EXISTE
-- A pesquisa do evento nasceu sem nota por atividade, por decisão de
-- 18/09: as duas pesquisas do dia já tinham colhido 273 notas com a
-- memória fresca. A decisão mudou no mesmo dia — a avaliação do evento
-- inteiro precisa deixar a pessoa avaliar a programação dos DOIS DIAS,
-- com o filtro por experiência.
--
-- A GRADE AQUI É A DO EVENTO INTEIRO, e essa é a diferença que importa
-- em relação à pesquisa do dia: lá a lista era do dia avaliado e a
-- validação exigia `s.dia = p_dia`. Aqui são as sessões do evento, os
-- dois dias juntos, e a validação exige só que a sessão seja deste
-- evento.
--
-- FORMULÁRIO VERSÃO 2. A versão muda porque a pergunta mudou: quem
-- respondeu a versão 1 não tinha como dar nota de atividade, e ler as
-- duas juntas sem saber disso faria parecer que essas pessoas não
-- avaliaram nada. O número fica gravado em cada resposta.
--
-- O QUE ISTO TOCA
--   tabela nova ........... engagement.avaliacao_do_evento_atividade
--   funções reescritas .... as 4 de `mind_avaliacao_do_evento_*`, todas
--                           da MESMA entrega, para passarem a conhecer
--                           as atividades
--   modificado ............ nada de terceiros; a pesquisa do dia não é
--                           tocada, nem a tabela de resposta do evento
--
-- DESFAZER
--   drop table if exists engagement.avaliacao_do_evento_atividade;
--   (e reponha as 4 funções da 20260918120000)

-- ============================================================
-- 1 · As notas por atividade
-- ============================================================

create table if not exists engagement.avaliacao_do_evento_atividade (
  id uuid primary key default gen_random_uuid(),

  -- Cascata só aqui, e só para dentro da estrutura nova: a nota não
  -- existe sem a resposta que a carrega. Na prática nunca dispara —
  -- resposta concluída não é apagada.
  avaliacao_id uuid not null
    references engagement.avaliacao_do_evento(id) on delete cascade,

  sessao_id uuid not null
    references summit_2026.sessions(id) on delete restrict,

  nota smallint not null,

  constraint avaliacao_do_evento_atividade_unica
    unique (avaliacao_id, sessao_id),
  constraint avaliacao_do_evento_atividade_nota_faixa
    check (nota between 0 and 5)
);

comment on table engagement.avaliacao_do_evento_atividade is
  'Nota de 0 a 5 por atividade do evento inteiro, dada na Avaliação do evento. Ausência de linha é ausência de avaliação — nunca zero.';

create index if not exists avaliacao_do_evento_atividade_sessao_ix
  on engagement.avaliacao_do_evento_atividade (sessao_id);

alter table engagement.avaliacao_do_evento_atividade enable row level security;

-- ============================================================
-- 2 · Estado — agora com a grade dos dois dias
-- ============================================================

create or replace function public.mind_avaliacao_do_evento_estado(
  p_auth_user_id uuid,
  p_event_slug text default 'mind-summit-2026'
)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_config jsonb;
  v_ativo boolean;
  v_abre date;
  v_fecha date;
  v_hoje date;
  v_motivo text;
  v_evento summit_2026.events%rowtype;
  v_participante_id uuid;
  v_resposta engagement.avaliacao_do_evento%rowtype;
  v_sugerida text;
  v_atividades jsonb;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;

  select c.valor into v_config from concierge.config c where c.chave = 'avaliacao_do_evento';
  v_ativo := coalesce((v_config->>'ativo')::boolean, false);
  v_abre  := nullif(v_config->>'abre', '')::date;
  v_fecha := nullif(v_config->>'fecha', '')::date;
  v_hoje  := (now() at time zone v_evento.fuso)::date;

  v_motivo := case
    when not v_ativo then 'desligada'
    when v_abre is not null and v_hoje < v_abre then 'ainda_nao_abriu'
    when v_fecha is not null and v_hoje > v_fecha then 'ja_fechou'
    else null
  end;

  select i.pessoa_id into v_participante_id
  from engagement.identidades i
  where i.canal = 'auth_user' and i.identificador = p_auth_user_id::text
  order by i.criado_em desc limit 1;

  if v_participante_id is not null then
    select * into v_resposta from engagement.avaliacao_do_evento a
    where a.participante_id = v_participante_id and a.event_id = v_evento.id;

    select case lower(r.ticket_category)
             when 'mind' then 'mind' when 'vip' then 'vip' when 'prime' then 'prime'
           end into v_sugerida
    from summit_2026.registrations r
    where r.person_id = v_participante_id and r.event_id = v_evento.id and r.status = 'ativa'
    order by r.criado_em desc limit 1;
  end if;

  -- A GRADE DOS DOIS DIAS, ordenada como o evento aconteceu. `dia` vem
  -- junto porque a tela agrupa por ele: "11:30" aparece duas vezes numa
  -- lista de dois dias e não quer dizer a mesma coisa.
  select coalesce(jsonb_agg(x order by x->>'dia', x->>'inicio', x->>'titulo'), '[]'::jsonb)
    into v_atividades
  from (
    select jsonb_build_object(
      'id', s.id,
      'titulo', s.titulo,
      'dia', s.dia,
      'inicio', to_char(s.inicio at time zone v_evento.fuso, 'HH24:MI'),
      'fim', case when s.fim is null then null
                  else to_char(s.fim at time zone v_evento.fuso, 'HH24:MI') end,
      'espaco', l.nome,
      'tipo', s.tipo,
      'ingressos', to_jsonb(s.ingressos),
      'operacional', s.tipo in ('credenciamento', 'intervalo', 'almoco'),
      'palestrantes', coalesce((
        select jsonb_agg(pe.nome order by pe.nome)
        from summit_2026.session_speakers ss
        join ecossistema.palestrantes_especialistas pe on pe.id = ss.speaker_id
        where ss.sessao_id = s.id
      ), '[]'::jsonb)
    ) as x
    from summit_2026.sessions s
    left join summit_2026.locations l on l.id = s.espaco_id
    where s.event_id = v_evento.id
  ) grade;

  return jsonb_build_object(
    'ativo', v_motivo is null,
    'motivo', v_motivo,
    'identificado', v_participante_id is not null,
    'evento', jsonb_build_object('slug', v_evento.slug, 'nome', v_evento.nome,
                                 'fuso', v_evento.fuso, 'dias', to_jsonb(v_evento.dias)),
    'janela', jsonb_build_object('abre', v_abre, 'fecha', v_fecha),
    'formularioVersao', 2,
    'enviado', v_resposta.id is not null,
    'enviadoEm', v_resposta.enviado_em,
    'experienciaSugerida', v_sugerida,
    'atividades', v_atividades
  );
end;
$function$;

-- ============================================================
-- 3 · O envio, com as notas por atividade
-- ============================================================

create or replace function public.mind_avaliacao_do_evento_registrar(
  p_auth_user_id uuid,
  p_event_slug text,
  p_payload jsonb
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_config jsonb;
  v_ativo boolean;
  v_abre date;
  v_fecha date;
  v_hoje date;
  v_evento summit_2026.events%rowtype;
  v_participante_id uuid;
  v_existente engagement.avaliacao_do_evento%rowtype;
  v_id uuid;
  v_experiencia text;
  v_profissao text;
  v_expectativas text;
  v_nota_rel smallint;
  v_nota_prog smallint;
  v_mais_gostou text;
  v_melhorar text;
  v_comentario text;
  v_atividades jsonb;
  v_invalidas int;
  v_iguais boolean;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;

  select c.valor into v_config from concierge.config c where c.chave = 'avaliacao_do_evento';
  v_ativo := coalesce((v_config->>'ativo')::boolean, false);
  v_abre  := nullif(v_config->>'abre', '')::date;
  v_fecha := nullif(v_config->>'fecha', '')::date;
  v_hoje  := (now() at time zone v_evento.fuso)::date;

  if not v_ativo then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:pesquisa_desligada';
  end if;
  if v_abre is not null and v_hoje < v_abre then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:ainda_nao_abriu';
  end if;
  if v_fecha is not null and v_hoje > v_fecha then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:ja_fechou';
  end if;

  select i.pessoa_id into v_participante_id
  from engagement.identidades i
  where i.canal = 'auth_user' and i.identificador = p_auth_user_id::text
  order by i.criado_em desc limit 1;
  if v_participante_id is null then
    raise exception using errcode = '28000', message = 'avaliacao_sem_identidade';
  end if;

  v_experiencia  := lower(btrim(coalesce(p_payload->>'experiencia', '')));
  v_profissao    := btrim(coalesce(p_payload->>'profissao', ''));
  v_expectativas := btrim(coalesce(p_payload->>'expectativas', ''));
  v_mais_gostou  := nullif(btrim(coalesce(p_payload->>'maisGostou', '')), '');
  v_melhorar     := nullif(btrim(coalesce(p_payload->>'melhorar', '')), '');
  v_comentario   := nullif(btrim(coalesce(p_payload->>'comentario', '')), '');

  if v_experiencia not in ('mind', 'vip', 'prime') then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:experiencia';
  end if;
  if char_length(v_profissao) < 1 or char_length(v_profissao) > 120 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:profissao';
  end if;
  if char_length(v_expectativas) < 1 or char_length(v_expectativas) > 1000 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:expectativas';
  end if;
  if coalesce(char_length(v_mais_gostou), 0) > 1000
     or coalesce(char_length(v_melhorar), 0) > 1000
     or coalesce(char_length(v_comentario), 0) > 1000 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:texto_longo';
  end if;

  if jsonb_typeof(p_payload->'notaRelevancia') <> 'number'
     or jsonb_typeof(p_payload->'notaProgramacao') <> 'number' then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:nota_obrigatoria';
  end if;
  v_nota_rel  := (p_payload->>'notaRelevancia')::numeric;
  v_nota_prog := (p_payload->>'notaProgramacao')::numeric;
  if v_nota_rel not between 0 and 5 or v_nota_prog not between 0 and 5
     or (p_payload->>'notaRelevancia')::numeric <> v_nota_rel
     or (p_payload->>'notaProgramacao')::numeric <> v_nota_prog then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:nota_fora_da_faixa';
  end if;

  v_atividades := coalesce(p_payload->'atividades', '[]'::jsonb);
  if jsonb_typeof(v_atividades) <> 'array' then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:atividades';
  end if;

  -- CADA SESSÃO ENVIADA PRECISA SER DESTE EVENTO. Diferente da pesquisa
  -- do dia, aqui NÃO se exige um dia: a grade é a dos dois. Bloco de
  -- operação continua fora — credenciamento e intervalo não se avalia.
  select count(*) into v_invalidas
  from jsonb_array_elements(v_atividades) a
  where jsonb_typeof(a->'nota') <> 'number'
     or (a->>'nota')::numeric not between 0 and 5
     or (a->>'nota')::numeric <> floor((a->>'nota')::numeric)
     or not exists (
       select 1 from summit_2026.sessions s
       where s.id = nullif(a->>'sessaoId', '')::uuid
         and s.event_id = v_evento.id
         and s.tipo is distinct from 'credenciamento'
         and s.tipo is distinct from 'intervalo'
         and s.tipo is distinct from 'almoco'
     );
  if v_invalidas > 0 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:sessao_invalida';
  end if;

  -- A mesma sessão duas vezes no envio é erro de cliente, não escolha:
  -- aceitar exigiria decidir qual das duas notas vale.
  if (select count(*) from jsonb_array_elements(v_atividades) a)
     <> (select count(distinct a->>'sessaoId') from jsonb_array_elements(v_atividades) a) then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:sessao_repetida';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('avaliacao_do_evento'),
    hashtext(v_participante_id::text || v_evento.id::text)
  );

  select * into v_existente from engagement.avaliacao_do_evento a
  where a.participante_id = v_participante_id and a.event_id = v_evento.id;

  if found then
    v_iguais :=
      v_existente.experiencia = v_experiencia
      and v_existente.profissao = v_profissao
      and v_existente.expectativas = v_expectativas
      and v_existente.nota_relevancia = v_nota_rel
      and v_existente.nota_programacao = v_nota_prog
      and v_existente.mais_gostou is not distinct from v_mais_gostou
      and v_existente.melhorar is not distinct from v_melhorar
      and v_existente.comentario is not distinct from v_comentario
      -- As notas por atividade viram um mapa `sessão → nota` dos dois
      -- lados e os mapas se comparam inteiros. jsonb ignora ordem de
      -- chave, então "mesmas notas em outra ordem" é igual.
      and (
        select coalesce(jsonb_object_agg(at.sessao_id::text, at.nota), '{}'::jsonb)
        from engagement.avaliacao_do_evento_atividade at
        where at.avaliacao_id = v_existente.id
      ) = (
        select coalesce(jsonb_object_agg(novo.sid::text, novo.nota), '{}'::jsonb)
        from (
          select nullif(a->>'sessaoId', '')::uuid as sid, (a->>'nota')::smallint as nota
          from jsonb_array_elements(v_atividades) a
        ) novo
      );

    if v_iguais then
      return jsonb_build_object('id', v_existente.id, 'jaRegistrado', true,
                                'enviadoEm', v_existente.enviado_em);
    end if;
    raise exception using errcode = '23505', message = 'avaliacao_ja_enviada';
  end if;

  insert into engagement.avaliacao_do_evento (
    participante_id, event_id, formulario_versao, experiencia, profissao,
    expectativas, nota_relevancia, nota_programacao, mais_gostou, melhorar,
    comentario, origem
  ) values (
    v_participante_id, v_evento.id, 2, v_experiencia, v_profissao,
    v_expectativas, v_nota_rel, v_nota_prog, v_mais_gostou, v_melhorar,
    v_comentario, 'app'
  ) returning id into v_id;

  insert into engagement.avaliacao_do_evento_atividade (avaliacao_id, sessao_id, nota)
  select v_id, nullif(a->>'sessaoId','')::uuid, (a->>'nota')::smallint
  from jsonb_array_elements(v_atividades) a
  on conflict (avaliacao_id, sessao_id) do nothing;

  return jsonb_build_object('id', v_id, 'jaRegistrado', false,
    'enviadoEm', (select enviado_em from engagement.avaliacao_do_evento where id = v_id));
end;
$function$;

-- ============================================================
-- 4 · O relatório, agora com a tabela por atividade
-- ============================================================
-- SEM CONTAGEM DUPLICADA: as respostas e as notas por atividade são
-- contadas em consultas separadas e só se encontram no jsonb final. Um
-- join entre as duas multiplicaria cada resposta pelo número de notas.
--
-- Atividade sem nota nenhuma sai com `avaliacoes: 0` e `media: null`.
-- Nunca zero — zero é uma nota que alguém deu.

create or replace function public.mind_avaliacao_do_evento_relatorio(
  p_event_slug text default 'mind-summit-2026',
  p_experiencia text default null
)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_evento summit_2026.events%rowtype;
  v_exp text := nullif(lower(btrim(coalesce(p_experiencia, ''))), '');
  v_resultado jsonb;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;
  if v_exp is not null and v_exp not in ('mind', 'vip', 'prime') then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:experiencia';
  end if;

  with respostas as (
    select a.*
    from engagement.avaliacao_do_evento a
    where a.event_id = v_evento.id
      and (v_exp is null or a.experiencia = v_exp)
  ),
  notas as (
    select at.sessao_id, at.nota
    from engagement.avaliacao_do_evento_atividade at
    join respostas r on r.id = at.avaliacao_id
  ),
  por_atividade as (
    select s.id, s.titulo, s.dia,
           to_char(s.inicio at time zone v_evento.fuso, 'HH24:MI') as inicio,
           l.nome as espaco, s.tipo, to_jsonb(s.ingressos) as ingressos,
           count(n.nota) as avaliacoes,
           avg(n.nota)::numeric(4,2) as media,
           count(*) filter (where n.nota = 0) as n0,
           count(*) filter (where n.nota = 1) as n1,
           count(*) filter (where n.nota = 2) as n2,
           count(*) filter (where n.nota = 3) as n3,
           count(*) filter (where n.nota = 4) as n4,
           count(*) filter (where n.nota = 5) as n5
    from summit_2026.sessions s
    left join summit_2026.locations l on l.id = s.espaco_id
    left join notas n on n.sessao_id = s.id
    where s.event_id = v_evento.id
      and s.tipo is distinct from 'credenciamento'
      and s.tipo is distinct from 'intervalo'
      and s.tipo is distinct from 'almoco'
    group by s.id, s.titulo, s.dia, s.inicio, l.nome, s.tipo, s.ingressos
  ),
  base as (select count(*)::int as n from respostas)
  select jsonb_build_object(
    'evento', jsonb_build_object('slug', v_evento.slug, 'nome', v_evento.nome,
                                 'fuso', v_evento.fuso, 'dias', to_jsonb(v_evento.dias)),
    'filtro', jsonb_build_object('experiencia', v_exp),
    'kpis', jsonb_build_object(
      'respondentes', (select n from base),
      'porExperiencia', jsonb_build_object(
        'mind',  (select count(*) from respostas where experiencia = 'mind'),
        'vip',   (select count(*) from respostas where experiencia = 'vip'),
        'prime', (select count(*) from respostas where experiencia = 'prime')),
      'porOrigem', jsonb_build_object(
        'app',     (select count(*) from respostas where origem = 'app'),
        'convite', (select count(*) from respostas where origem = 'convite')),
      'relevancia', (
        select jsonb_build_object(
          'amostra', count(*),
          'media', avg(nota_relevancia)::numeric(4,2),
          'distribuicao', jsonb_build_object(
            '0', count(*) filter (where nota_relevancia = 0),
            '1', count(*) filter (where nota_relevancia = 1),
            '2', count(*) filter (where nota_relevancia = 2),
            '3', count(*) filter (where nota_relevancia = 3),
            '4', count(*) filter (where nota_relevancia = 4),
            '5', count(*) filter (where nota_relevancia = 5)),
          'percentual45', case when count(*) = 0 then null else
            round(100.0 * count(*) filter (where nota_relevancia >= 4) / count(*), 1) end)
        from respostas),
      'programacao', (
        select jsonb_build_object(
          'amostra', count(*),
          'media', avg(nota_programacao)::numeric(4,2),
          'distribuicao', jsonb_build_object(
            '0', count(*) filter (where nota_programacao = 0),
            '1', count(*) filter (where nota_programacao = 1),
            '2', count(*) filter (where nota_programacao = 2),
            '3', count(*) filter (where nota_programacao = 3),
            '4', count(*) filter (where nota_programacao = 4),
            '5', count(*) filter (where nota_programacao = 5)),
          'percentual45', case when count(*) = 0 then null else
            round(100.0 * count(*) filter (where nota_programacao >= 4) / count(*), 1) end)
        from respostas)),
    'avaliacoesDeAtividades', (select count(*) from notas),
    'porAtividade', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pa.id, 'titulo', pa.titulo, 'dia', pa.dia, 'inicio', pa.inicio,
        'espaco', pa.espaco, 'tipo', pa.tipo, 'ingressos', pa.ingressos,
        'avaliacoes', pa.avaliacoes,
        -- `null`, e nunca zero: ninguém avaliou é diferente de nota zero.
        'media', pa.media,
        'distribuicao', jsonb_build_object(
          '0', pa.n0, '1', pa.n1, '2', pa.n2, '3', pa.n3, '4', pa.n4, '5', pa.n5))
        order by pa.dia, pa.inicio, pa.titulo)
      from por_atividade pa), '[]'::jsonb)
  ) into v_resultado;

  return v_resultado;
end;
$function$;

-- ============================================================
-- 5 · As respostas, com quantas atividades cada uma avaliou
-- ============================================================

create or replace function public.mind_avaliacao_do_evento_respostas(
  p_event_slug text default 'mind-summit-2026',
  p_experiencia text default null,
  p_pagina int default 1,
  p_por_pagina int default 50
)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_evento summit_2026.events%rowtype;
  v_exp text := nullif(lower(btrim(coalesce(p_experiencia, ''))), '');
  v_pagina int := greatest(1, coalesce(p_pagina, 1));
  v_por int := least(500, greatest(1, coalesce(p_por_pagina, 50)));
  v_total bigint;
  v_itens jsonb;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;
  if v_exp is not null and v_exp not in ('mind', 'vip', 'prime') then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:experiencia';
  end if;

  select count(*) into v_total
  from engagement.avaliacao_do_evento a
  where a.event_id = v_evento.id
    and (v_exp is null or a.experiencia = v_exp);

  select coalesce(jsonb_agg(x order by ordem), '[]'::jsonb) into v_itens
  from (
    select jsonb_build_object(
      'id', a.id,
      'enviadoEm', a.enviado_em,
      'origem', a.origem,
      'formularioVersao', a.formulario_versao,
      'nome', nullif(btrim(coalesce(p.primeiro_nome, '') || ' ' || coalesce(p.sobrenome, '')), ''),
      'email', p.email,
      'experiencia', a.experiencia,
      'profissao', a.profissao,
      'expectativas', a.expectativas,
      'notaRelevancia', a.nota_relevancia,
      'notaProgramacao', a.nota_programacao,
      'maisGostou', a.mais_gostou,
      'melhorar', a.melhorar,
      'comentario', a.comentario,
      'atividadesAvaliadas', (
        select count(*) from engagement.avaliacao_do_evento_atividade t
        where t.avaliacao_id = a.id)
    ) as x,
    a.enviado_em as ordem
    from engagement.avaliacao_do_evento a
    left join pessoas.pessoas p on p.id = a.participante_id
    where a.event_id = v_evento.id
      and (v_exp is null or a.experiencia = v_exp)
    order by a.enviado_em desc
    limit v_por offset (v_pagina - 1) * v_por
  ) pagina;

  return jsonb_build_object(
    'total', v_total, 'pagina', v_pagina, 'porPagina', v_por, 'itens', v_itens);
end;
$function$;
