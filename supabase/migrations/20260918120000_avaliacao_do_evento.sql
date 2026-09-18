-- ============================================================
-- Avaliação do evento — a segunda pesquisa, ao lado da do dia
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
--
-- O QUE ISTO É
-- A pesquisa do Mind Summit inteiro, aberta depois que o evento acaba:
-- uma resposta por participante, por evento. As mesmas nove perguntas
-- da Avaliação do dia, com "hoje" trocado por "o evento". Notas de 0 a
-- 5. NÃO é NPS: não há escala 0-10, não há promotor nem detrator.
--
-- POR QUE TABELA NOVA, E NÃO A DO DIA
-- A identidade da resposta do dia é (participante, evento, DIA) — o dia
-- é parte da chave, e o relatório, o painel e o PDF agrupam por ele.
-- Uma resposta sobre o evento inteiro não tem dia; enfiá-la ali com um
-- dia inventado colocaria uma linha que não é de nenhum dia dentro da
-- série que se lê por dia, e estragaria as duas leituras.
--
-- POR QUE NÃO AS CASAS QUE JÁ EXISTEM
--   engagement.evento_feedback  ledger de reclamação escrito pelo agente
--                               (categoria, sentimento, severidade,
--                               tratado). Não tem nota, não tem pergunta
--                               e não tem trava de uma por pessoa.
--   engagement.feedbacks        chave/valor genérico, sem contrato.
--   engagement.nps              é NPS, e NPS não se mistura com isto.
--   engagement.sessao_feedback  é por sessão, não pelo evento.
--
-- SEM NOTA POR ATIVIDADE, de propósito. As duas pesquisas do dia já
-- colhearam 273 notas de atividade enquanto a memória estava fresca.
-- Repetir a grade dos dois dias aqui traria nota pior sobre a mesma
-- coisa, e alongaria a pesquisa justo onde a pessoa desiste.
--
-- O QUE ISTO NÃO TOCA
-- Nada. Nenhuma tabela, coluna, função, trigger, policy ou permissão
-- existente é alterada. Tudo aqui é objeto novo:
--
--   tabela nova ........... engagement.avaliacao_do_evento
--   funções novas ......... 4, todas com nome próprio
--   linha nova ............ chave 'avaliacao_do_evento' em concierge.config
--   modificado ............ nada
--
-- A pesquisa do dia continua exatamente como está, inclusive ligada.
--
-- QUEM RESPONDE
-- Só participante identificado. Quem chega pelo app já vem com a sessão
-- Auth, e é dela que sai a identidade — o cliente nunca manda quem é.
-- O convite por link, que alcança quem não abre mais o app, é a camada
-- seguinte e mora em migration própria: ele mexe em identidade e por
-- isso espera gate.
--
-- DESFAZER
--   drop function if exists public.mind_avaliacao_do_evento_respostas(text,text,int,int);
--   drop function if exists public.mind_avaliacao_do_evento_relatorio(text,text);
--   drop function if exists public.mind_avaliacao_do_evento_registrar(uuid,text,jsonb);
--   drop function if exists public.mind_avaliacao_do_evento_estado(uuid,text);
--   drop table if exists engagement.avaliacao_do_evento;
--   delete from concierge.config where chave = 'avaliacao_do_evento';
--
-- SEGURANÇA
-- RLS ligada e nenhuma política, como as outras tabelas de `engagement`.
-- Quem lê e escreve é função SECURITY DEFINER chamada pela Edge Function
-- com `service_role`. `anon` e `authenticated` não ganham superfície
-- nova: sem policy e sem grant, a tabela é inalcançável pelo PostgREST.

-- ============================================================
-- 1 · A resposta do evento
-- ============================================================

create table if not exists engagement.avaliacao_do_evento (
  id uuid primary key default gen_random_uuid(),

  -- Mesma regra da pesquisa do dia: sem cascata em nenhuma direção.
  -- Apagar uma pessoa passa a exigir decidir o que fazer com a resposta
  -- dela, em vez de a resposta sumir junto sem ninguém ver.
  participante_id uuid not null
    references pessoas.pessoas(id) on delete restrict,
  event_id uuid not null
    references summit_2026.events(id) on delete restrict,

  -- Muda quando as perguntas mudarem. Serve para ler resposta antiga
  -- sabendo a que pergunta ela respondeu — e para invalidar rascunho.
  formulario_versao smallint not null default 1,

  -- AUTODECLARADA. Não altera ingresso, cadastro nem permissão: é o que
  -- a pessoa diz ter vivido, e é isso que a análise precisa saber.
  experiencia text not null,

  profissao text not null,
  expectativas text not null,

  -- As mesmas duas notas da pesquisa do dia, sobre o evento inteiro.
  -- Os nomes são iguais aos de lá de propósito: o painel, o CSV e o PDF
  -- leem a mesma forma, e comparar as duas pesquisas não exige tradução.
  nota_relevancia smallint not null,
  nota_programacao smallint not null,

  mais_gostou text,
  melhorar text,
  comentario text,

  -- COMO A PESSOA CHEGOU. 'app' é quem respondeu logado; 'convite' é
  -- quem veio por link. A coluna nasce aqui, já preenchida com 'app',
  -- para a camada de convite não precisar alterar esta tabela depois —
  -- alterar tabela com resposta real dentro é o que se quer evitar.
  origem text not null default 'app',

  -- Gerada no servidor, sempre. O relógio do aparelho não entra aqui.
  enviado_em timestamptz not null default now(),

  -- UMA RESPOSTA POR PARTICIPANTE, POR EVENTO. Sem dia na chave: é esta
  -- linha que diz que a pesquisa é do evento inteiro.
  constraint avaliacao_do_evento_unica
    unique (participante_id, event_id),

  constraint avaliacao_do_evento_experiencia_valida
    check (experiencia in ('mind', 'vip', 'prime')),

  constraint avaliacao_do_evento_origem_valida
    check (origem in ('app', 'convite')),

  -- Zero É resposta: "nada relevante" é diferente de não responder, e o
  -- `not null` acima é o que garante que a diferença não se perca.
  constraint avaliacao_do_evento_nota_relevancia_faixa
    check (nota_relevancia between 0 and 5),
  constraint avaliacao_do_evento_nota_programacao_faixa
    check (nota_programacao between 0 and 5),

  -- Os mesmos limites que o formulário aplica, repetidos aqui porque
  -- validação de tela não é validação.
  constraint avaliacao_do_evento_profissao_tamanho
    check (char_length(profissao) between 1 and 120),
  constraint avaliacao_do_evento_expectativas_tamanho
    check (char_length(expectativas) between 1 and 1000),
  constraint avaliacao_do_evento_mais_gostou_tamanho
    check (mais_gostou is null or char_length(mais_gostou) <= 1000),
  constraint avaliacao_do_evento_melhorar_tamanho
    check (melhorar is null or char_length(melhorar) <= 1000),
  constraint avaliacao_do_evento_comentario_tamanho
    check (comentario is null or char_length(comentario) <= 1000)
);

comment on table engagement.avaliacao_do_evento is
  'Avaliação do Mind Summit inteiro: uma resposta por participante por evento, aberta depois do evento. Notas de 0 a 5. Não é NPS e não usa a fórmula de promotores menos detratores. Separada de engagement.avaliacao_do_dia porque aquela tem o dia na chave.';
comment on column engagement.avaliacao_do_evento.experiencia is
  'Autodeclarada pela pessoa. Não altera ingresso, cadastro nem permissão.';
comment on column engagement.avaliacao_do_evento.nota_relevancia is
  'Quanto o que a pessoa vivenciou no evento foi relevante para a vida pessoal ou profissional dela, de 0 a 5. NÃO mede expectativa atendida — a expectativa é a pergunta aberta `expectativas`.';
comment on column engagement.avaliacao_do_evento.origem is
  'Por onde a resposta entrou: app (sessão logada) ou convite (link com token). Serve para ler a amostra sabendo quem ela alcançou.';

create index if not exists avaliacao_do_evento_evento_ix
  on engagement.avaliacao_do_evento (event_id, enviado_em desc);

alter table engagement.avaliacao_do_evento enable row level security;

-- ============================================================
-- 2 · O interruptor, com janela
-- ============================================================
-- A pesquisa do dia se fecha sozinha pela grade: fora de um dia do
-- evento, não abre. Esta não pode usar essa regra — ela existe JUSTAMENTE
-- para depois do evento. Então a janela é explícita, e é dado, não código:
--
--   ativo  liga e desliga na mão, e vale acima de tudo
--   abre   primeiro dia em que aceita resposta (nulo = assim que ligar)
--   fecha  último dia em que aceita resposta, inclusive (nulo = sem fim)
--
-- As duas datas são lidas no fuso do evento, não no do servidor nem no
-- do aparelho de quem responde.
--
-- Nasce DESLIGADA e sem datas. Ligar é decisão de produto, e decisão de
-- produto não vem embutida em migration.

insert into concierge.config (chave, valor)
values ('avaliacao_do_evento',
        jsonb_build_object('ativo', false, 'abre', null, 'fecha', null))
on conflict (chave) do nothing;

-- ============================================================
-- 3 · Estado da pesquisa para um participante
-- ============================================================
-- Responde três coisas para a tela: a pesquisa está aberta? quem está
-- perguntando é participante? ele já respondeu?
--
-- Nunca devolve resposta de terceiro, e nunca aceita do cliente quem é
-- a pessoa: a identidade sai do vínculo canônico da sessão Auth.

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

  -- O MOTIVO É PARTE DA RESPOSTA. Sem ele a tela só sabe dizer "não
  -- disponível", e quem chega cedo demais recebe a mesma frase de quem
  -- chega tarde demais.
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

  return jsonb_build_object(
    'ativo', v_motivo is null,
    'motivo', v_motivo,
    'identificado', v_participante_id is not null,
    'evento', jsonb_build_object('slug', v_evento.slug, 'nome', v_evento.nome,
                                 'fuso', v_evento.fuso, 'dias', to_jsonb(v_evento.dias)),
    'janela', jsonb_build_object('abre', v_abre, 'fecha', v_fecha),
    'formularioVersao', 1,
    'enviado', v_resposta.id is not null,
    'enviadoEm', v_resposta.enviado_em,
    'experienciaSugerida', v_sugerida
  );
end;
$function$;

comment on function public.mind_avaliacao_do_evento_estado(uuid, text) is
  'Estado da Avaliação do evento para um participante: se está aberta (com o motivo quando não está), se quem pergunta é participante e se já respondeu.';

-- ============================================================
-- 4 · O envio definitivo
-- ============================================================
-- Uma transação, tudo ou nada. Se qualquer validação falhar, nada fica
-- gravado pela metade.
--
-- REENVIO
--   idêntico  → devolve a resposta já gravada (`jaRegistrado: true`).
--               É o caso do timeout: o envio chegou, a resposta não.
--   divergente→ recusa. Resposta concluída não se edita.

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
  v_iguais boolean;
begin
  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;

  -- A JANELA VALE NO ENVIO, e não só na abertura da tela. Quem deixou a
  -- aba aberta a noite inteira e mandou depois de fechar não entra: a
  -- tela não é o que decide.
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

  -- Quem responde é o dono da sessão Auth, pelo vínculo canônico. Sem
  -- vínculo não há resposta para gravar — e não existe coleta anônima
  -- nesta pesquisa.
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

  -- `jsonb_typeof` antes do cast: `"3"` e `3` chegam diferentes de
  -- clientes diferentes, e um cast direto de texto vazio explodiria com
  -- erro de banco em vez de erro de validação.
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

  -- Trava contra envio duplo e concorrente: dois cliques simultâneos
  -- disputam esta linha, e o segundo só continua depois que o primeiro
  -- terminou — então ele encontra a resposta já gravada em vez de criar
  -- a segunda.
  perform pg_advisory_xact_lock(
    hashtext('avaliacao_do_evento'),
    hashtext(v_participante_id::text || v_evento.id::text)
  );

  select * into v_existente from engagement.avaliacao_do_evento a
  where a.participante_id = v_participante_id and a.event_id = v_evento.id;

  if found then
    -- Reenvio idêntico reconhece o que já está gravado. Divergente é
    -- recusado: `upsert` aqui sobrescreveria resposta concluída.
    v_iguais :=
      v_existente.experiencia = v_experiencia
      and v_existente.profissao = v_profissao
      and v_existente.expectativas = v_expectativas
      and v_existente.nota_relevancia = v_nota_rel
      and v_existente.nota_programacao = v_nota_prog
      and v_existente.mais_gostou is not distinct from v_mais_gostou
      and v_existente.melhorar is not distinct from v_melhorar
      and v_existente.comentario is not distinct from v_comentario;

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
    v_participante_id, v_evento.id, 1, v_experiencia, v_profissao,
    v_expectativas, v_nota_rel, v_nota_prog, v_mais_gostou, v_melhorar,
    v_comentario, 'app'
  ) returning id into v_id;

  return jsonb_build_object('id', v_id, 'jaRegistrado', false,
    'enviadoEm', (select enviado_em from engagement.avaliacao_do_evento where id = v_id));
end;
$function$;

comment on function public.mind_avaliacao_do_evento_registrar(uuid, text, jsonb) is
  'Envio definitivo da Avaliação do evento, numa transação. A janela é conferida no envio, não só na abertura. Reenvio idêntico devolve a resposta já gravada; divergente é recusado.';

-- ============================================================
-- 5 · O relatório — os números
-- ============================================================
-- A MÉDIA NUNCA SAI SOZINHA: cada uma vem com o tamanho da amostra e
-- com a distribuição de 0 a 5. Sem a amostra ao lado, 5,0 de uma pessoa
-- e 5,0 de duzentas são o mesmo número na tela de quem decide.

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
        from respostas))
  ) into v_resultado;

  return v_resultado;
end;
$function$;

comment on function public.mind_avaliacao_do_evento_relatorio(text, text) is
  'Números da Avaliação do evento: respondentes por experiência e por origem, e as duas notas com amostra, distribuição de 0 a 5 e percentual de 4 ou 5.';

-- ============================================================
-- 6 · As respostas, uma a uma — para a lista e para o CSV
-- ============================================================
-- Paginada, e com nome e e-mail do cadastro: é tela de operador, não
-- página pública. Quem chama já provou ser operador na Edge Function.

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
      'nome', nullif(btrim(coalesce(p.primeiro_nome, '') || ' ' || coalesce(p.sobrenome, '')), ''),
      'email', p.email,
      'experiencia', a.experiencia,
      'profissao', a.profissao,
      'expectativas', a.expectativas,
      'notaRelevancia', a.nota_relevancia,
      'notaProgramacao', a.nota_programacao,
      'maisGostou', a.mais_gostou,
      'melhorar', a.melhorar,
      'comentario', a.comentario
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

comment on function public.mind_avaliacao_do_evento_respostas(text, text, int, int) is
  'Respostas da Avaliação do evento, paginadas, com nome e e-mail do cadastro. Uso de operador: a Edge Function confere o papel antes de chamar.';

-- ============================================================
-- 7 · Permissões mínimas
-- ============================================================
-- Só `service_role`. Quem chama é a Edge Function `mindagent-avaliacao`,
-- que resolve a identidade e o papel antes. `anon` e `authenticated` não
-- executam nenhuma delas — participante não alcança resposta de terceiro
-- nem o relatório, e não há caminho de PostgREST para a tabela.

revoke execute on function public.mind_avaliacao_do_evento_estado(uuid, text) from public;
revoke execute on function public.mind_avaliacao_do_evento_registrar(uuid, text, jsonb) from public;
revoke execute on function public.mind_avaliacao_do_evento_relatorio(text, text) from public;
revoke execute on function public.mind_avaliacao_do_evento_respostas(text, text, int, int) from public;

grant execute on function public.mind_avaliacao_do_evento_estado(uuid, text) to service_role;
grant execute on function public.mind_avaliacao_do_evento_registrar(uuid, text, jsonb) to service_role;
grant execute on function public.mind_avaliacao_do_evento_relatorio(text, text) to service_role;
grant execute on function public.mind_avaliacao_do_evento_respostas(text, text, int, int) to service_role;
