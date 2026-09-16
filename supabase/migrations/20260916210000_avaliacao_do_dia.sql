-- ============================================================
-- Avaliação do dia — estrutura própria, ao lado do que já existe
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
--
-- O QUE ISTO É
-- A pesquisa "Avaliação do dia" do Mind Summit: uma resposta por
-- participante por dia de evento, mais notas opcionais por atividade.
-- Notas de 0 a 5. NÃO é NPS: não há escala 0-10, não há promotor nem
-- detrator, e a média não vira índice.
--
-- O QUE ISTO NÃO TOCA
-- Nada. Nenhuma tabela, coluna, função, trigger, policy ou permissão
-- existente é alterada. Tudo aqui é objeto novo:
--
--   tabelas novas ......... engagement.avaliacao_do_dia
--                           engagement.avaliacao_do_dia_atividade
--   funções novas ......... 4, todas com nome próprio
--   linha nova ............ chave 'avaliacao_do_dia' em concierge.config
--   modificado ............ nada
--
-- `engagement.nps` e `engagement.sessao_feedback` continuam intactas e
-- não são reaproveitadas: a pesquisa tem outro contrato, e misturar as
-- duas coisas estragaria as duas.
--
-- DESFAZER
--   drop function if exists public.mind_avaliacao_do_dia_respostas(text,date,text,uuid,int,int);
--   drop function if exists public.mind_avaliacao_do_dia_relatorio(text,date,text);
--   drop function if exists public.mind_avaliacao_do_dia_registrar(uuid,text,date,jsonb);
--   drop function if exists public.mind_avaliacao_do_dia_estado(uuid,text,date);
--   drop table if exists engagement.avaliacao_do_dia_atividade;
--   drop table if exists engagement.avaliacao_do_dia;
--   delete from concierge.config where chave = 'avaliacao_do_dia';
--
-- SEGURANÇA
-- RLS ligada e nenhuma política, como as outras tabelas de `engagement`.
-- Quem lê e escreve é função SECURITY DEFINER chamada pela Edge Function
-- com `service_role`. `anon` e `authenticated` não ganham superfície
-- nova: sem policy e sem grant, a tabela é inalcançável pelo PostgREST.

-- ============================================================
-- 1 · A resposta do dia
-- ============================================================

create table if not exists engagement.avaliacao_do_dia (
  id uuid primary key default gen_random_uuid(),

  -- Participante canônico. Sem cascata em nenhuma direção: apagar uma
  -- pessoa passa a exigir decidir o que fazer com a resposta dela, em
  -- vez de a resposta sumir junto sem ninguém ver.
  participante_id uuid not null
    references pessoas.pessoas(id) on delete restrict,
  event_id uuid not null
    references summit_2026.events(id) on delete restrict,

  -- O dia AVALIADO, fixado quando o formulário abre. Não é a data do
  -- envio: quem começa às 23h50 e envia às 00h05 avaliou o dia anterior.
  dia date not null,

  -- Muda quando as perguntas mudarem. Serve para ler resposta antiga
  -- sabendo a que pergunta ela respondeu — e para invalidar rascunho.
  formulario_versao smallint not null default 1,

  -- AUTODECLARADA. Não altera ingresso, cadastro nem permissão: é o que
  -- a pessoa diz ter vivido, e é isso que a análise precisa saber.
  experiencia text not null,

  profissao text not null,
  expectativas text not null,

  nota_expectativas smallint not null,
  nota_programacao smallint not null,

  mais_gostou text,
  melhorar text,
  comentario text,

  -- Gerada no servidor, sempre. O relógio do aparelho não entra aqui.
  enviado_em timestamptz not null default now(),

  -- UMA RESPOSTA POR PARTICIPANTE, POR EVENTO, POR DIA.
  constraint avaliacao_do_dia_unica
    unique (participante_id, event_id, dia),

  constraint avaliacao_do_dia_experiencia_valida
    check (experiencia in ('mind', 'vip', 'prime')),

  -- Zero É resposta: "não atendeu" é diferente de não responder, e o
  -- `not null` acima é o que garante que a diferença não se perca.
  constraint avaliacao_do_dia_nota_expectativas_faixa
    check (nota_expectativas between 0 and 5),
  constraint avaliacao_do_dia_nota_programacao_faixa
    check (nota_programacao between 0 and 5),

  -- Os mesmos limites que o formulário aplica, repetidos aqui porque
  -- validação de tela não é validação.
  constraint avaliacao_do_dia_profissao_tamanho
    check (char_length(profissao) between 1 and 120),
  constraint avaliacao_do_dia_expectativas_tamanho
    check (char_length(expectativas) between 1 and 1000),
  constraint avaliacao_do_dia_mais_gostou_tamanho
    check (mais_gostou is null or char_length(mais_gostou) <= 1000),
  constraint avaliacao_do_dia_melhorar_tamanho
    check (melhorar is null or char_length(melhorar) <= 1000),
  constraint avaliacao_do_dia_comentario_tamanho
    check (comentario is null or char_length(comentario) <= 1000)
);

comment on table engagement.avaliacao_do_dia is
  'Avaliação do dia do Mind Summit: uma resposta por participante por dia. Notas de 0 a 5. Não é NPS e não usa a fórmula de promotores menos detratores.';
comment on column engagement.avaliacao_do_dia.dia is
  'O dia avaliado, fixado na abertura do formulário. Atravessar a meia-noite não muda este valor.';
comment on column engagement.avaliacao_do_dia.experiencia is
  'Autodeclarada pela pessoa. Não altera ingresso, cadastro nem permissão.';

create index if not exists avaliacao_do_dia_evento_dia_ix
  on engagement.avaliacao_do_dia (event_id, dia);

alter table engagement.avaliacao_do_dia enable row level security;

-- ============================================================
-- 2 · As notas por atividade
-- ============================================================

create table if not exists engagement.avaliacao_do_dia_atividade (
  id uuid primary key default gen_random_uuid(),

  -- Cascata só aqui, e só para dentro da estrutura nova: a nota não
  -- existe sem a resposta que a carrega. Na prática nunca dispara —
  -- resposta concluída não é apagada.
  avaliacao_id uuid not null
    references engagement.avaliacao_do_dia(id) on delete cascade,

  sessao_id uuid not null
    references summit_2026.sessions(id) on delete restrict,

  nota smallint not null,

  constraint avaliacao_do_dia_atividade_unica
    unique (avaliacao_id, sessao_id),
  constraint avaliacao_do_dia_atividade_nota_faixa
    check (nota between 0 and 5)
);

comment on table engagement.avaliacao_do_dia_atividade is
  'Nota de 0 a 5 por atividade avaliada. Ausência de linha é ausência de avaliação — nunca zero.';

create index if not exists avaliacao_do_dia_atividade_sessao_ix
  on engagement.avaliacao_do_dia_atividade (sessao_id);

alter table engagement.avaliacao_do_dia_atividade enable row level security;

-- ============================================================
-- 3 · O interruptor
-- ============================================================
-- `concierge.config` é a casa de configuração da experiência do
-- participante — 24 chaves já moram lá. Uma tabela nova para um booleano
-- seria inventar casa onde já tem.
--
-- DESLIGADA POR PADRÃO. Ligar é `update ... set valor = '{"ativo": true}'`.
-- Desligar tira o card da home e recusa envio novo; o que já foi
-- respondido continua gravado e continua no relatório.

insert into concierge.config (chave, valor, descricao)
values (
  'avaliacao_do_dia',
  jsonb_build_object('ativo', false),
  'Liga e desliga a pesquisa "Avaliação do dia" no app. Desligada, o card não aparece e envio novo é recusado; respostas já gravadas não são afetadas.'
)
on conflict (chave) do nothing;

-- ============================================================
-- 4 · Estado da pesquisa para um participante, num dia
-- ============================================================
-- Devolve tudo que a tela precisa numa chamada só: se a pesquisa está
-- ligada, qual dia está sendo avaliado, se a pessoa já enviou, qual
-- experiência sugerir e a programação oficial daquele dia.
--
-- A GRADE VEM DAQUI, não de uma cópia. Título, horário, palestrantes e
-- espaço saem de `summit_2026.sessions` e das tabelas que ela já usa.

create or replace function public.mind_avaliacao_do_dia_estado(
  p_auth_user_id uuid,
  p_event_slug text default 'mind-summit-2026',
  p_dia date default null
)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_ativo boolean;
  v_evento summit_2026.events%rowtype;
  v_dia date;
  v_participante_id uuid;
  v_resposta engagement.avaliacao_do_dia%rowtype;
  v_atividades jsonb;
  v_sugerida text;
begin
  select coalesce((c.valor->>'ativo')::boolean, false) into v_ativo
  from concierge.config c where c.chave = 'avaliacao_do_dia';
  v_ativo := coalesce(v_ativo, false);

  -- QUEM É A PESSOA SAI DAQUI, NÃO DO CLIENTE. A função recebe o dono da
  -- sessão Supabase Auth e procura o vínculo canônico que a identidade
  -- do app já criou (`engagement.identidades`, canal `auth_user`). Um
  -- `participante_id` mandado pelo navegador não teria como ser conferido
  -- e por isso nem é aceito.
  select i.pessoa_id into v_participante_id
  from engagement.identidades i
  where i.canal = 'auth_user' and i.identificador = p_auth_user_id::text
  order by i.criado_em desc limit 1;

  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;

  -- O dia pedido, ou o dia de hoje no fuso do evento. Fora dos dias do
  -- evento não há pesquisa: não se abre pesquisa para data que não
  -- aconteceu.
  v_dia := coalesce(p_dia, (now() at time zone v_evento.fuso)::date);
  if not (v_dia = any (v_evento.dias)) then
    return jsonb_build_object(
      'ativo', false,
      'motivo', 'fora_do_evento',
      'identificado', v_participante_id is not null,
      'evento', jsonb_build_object('slug', v_evento.slug, 'nome', v_evento.nome,
                                   'fuso', v_evento.fuso, 'dias', to_jsonb(v_evento.dias)),
      'dia', v_dia,
      'formularioVersao', 1,
      'enviado', false,
      'atividades', '[]'::jsonb
    );
  end if;

  if v_participante_id is not null then
    select * into v_resposta from engagement.avaliacao_do_dia a
    where a.participante_id = v_participante_id and a.event_id = v_evento.id and a.dia = v_dia;

    -- Sugestão, não decisão: a pessoa confirma ou corrige na tela, e o que
    -- vale é o que ela disser. `camarote` não é uma das três opções do
    -- formulário, então não é sugerido — a pessoa escolhe.
    select case lower(r.ticket_category)
             when 'mind' then 'mind' when 'vip' then 'vip' when 'prime' then 'prime'
           end into v_sugerida
    from summit_2026.registrations r
    where r.person_id = v_participante_id and r.event_id = v_evento.id and r.status = 'ativa'
    order by r.criado_em desc limit 1;
  end if;

  select coalesce(jsonb_agg(x order by x->>'inicio', x->>'titulo'), '[]'::jsonb)
    into v_atividades
  from (
    select jsonb_build_object(
      'id', s.id,
      'titulo', s.titulo,
      'inicio', to_char(s.inicio at time zone v_evento.fuso, 'HH24:MI'),
      'fim', case when s.fim is null then null
                  else to_char(s.fim at time zone v_evento.fuso, 'HH24:MI') end,
      'espaco', l.nome,
      'tipo', s.tipo,
      -- Categoria de ACESSO (`ingressos`), não trilha. `trilhas` existe na
      -- tabela e está vazia em todas as 77 sessões — filtrar por ela
      -- devolveria nada e pareceria grade vazia.
      'ingressos', to_jsonb(s.ingressos),
      -- Credenciamento, intervalo e almoço aparecem na lista para a grade
      -- ficar inteira, mas não recebem nota: não são atividade avaliável.
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
    where s.event_id = v_evento.id and s.dia = v_dia
  ) grade;

  return jsonb_build_object(
    'ativo', v_ativo,
    -- Sem vínculo canônico não há de quem seja a resposta. A tela usa
    -- isto para orientar a pessoa a entrar pelo app do evento, em vez de
    -- abrir um formulário anônimo.
    'identificado', v_participante_id is not null,
    'evento', jsonb_build_object('slug', v_evento.slug, 'nome', v_evento.nome,
                                 'fuso', v_evento.fuso, 'dias', to_jsonb(v_evento.dias)),
    'dia', v_dia,
    'formularioVersao', 1,
    'enviado', v_resposta.id is not null,
    'enviadoEm', v_resposta.enviado_em,
    'experienciaSugerida', v_sugerida,
    'atividades', v_atividades
  );
end;
$function$;

comment on function public.mind_avaliacao_do_dia_estado(uuid, text, date) is
  'Estado da Avaliação do dia para um participante: se está ligada, o dia avaliado, se já enviou e a programação oficial daquele dia.';

-- ============================================================
-- 5 · O envio definitivo
-- ============================================================
-- Uma transação, tudo ou nada. Se qualquer validação falhar, nada fica
-- gravado pela metade.
--
-- REENVIO
--   idêntico  → devolve a resposta já gravada (`jaRegistrado: true`).
--               É o caso do timeout: o envio chegou, a resposta não.
--   divergente→ recusa. Resposta concluída não se edita.

create or replace function public.mind_avaliacao_do_dia_registrar(
  p_auth_user_id uuid,
  p_event_slug text,
  p_dia date,
  p_payload jsonb
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_ativo boolean;
  v_evento summit_2026.events%rowtype;
  v_participante_id uuid;
  v_existente engagement.avaliacao_do_dia%rowtype;
  v_id uuid;
  v_experiencia text;
  v_profissao text;
  v_expectativas text;
  v_nota_exp smallint;
  v_nota_prog smallint;
  v_mais_gostou text;
  v_melhorar text;
  v_comentario text;
  v_atividades jsonb;
  v_iguais boolean;
  v_invalidas int;
begin
  select coalesce((c.valor->>'ativo')::boolean, false) into v_ativo
  from concierge.config c where c.chave = 'avaliacao_do_dia';
  if coalesce(v_ativo, false) is false then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:pesquisa_desligada';
  end if;

  select * into v_evento from summit_2026.events e where e.slug = p_event_slug;
  if not found then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:evento_desconhecido';
  end if;
  if p_dia is null or not (p_dia = any (v_evento.dias)) then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:dia_fora_do_evento';
  end if;

  -- Mesma regra do estado: quem responde é o dono da sessão Auth, pelo
  -- vínculo canônico. Sem vínculo não há resposta para gravar — e não
  -- existe coleta anônima nesta pesquisa.
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
  if jsonb_typeof(p_payload->'notaExpectativas') <> 'number'
     or jsonb_typeof(p_payload->'notaProgramacao') <> 'number' then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:nota_obrigatoria';
  end if;
  v_nota_exp  := (p_payload->>'notaExpectativas')::numeric;
  v_nota_prog := (p_payload->>'notaProgramacao')::numeric;
  if v_nota_exp not between 0 and 5 or v_nota_prog not between 0 and 5
     or (p_payload->>'notaExpectativas')::numeric <> v_nota_exp
     or (p_payload->>'notaProgramacao')::numeric <> v_nota_prog then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:nota_fora_da_faixa';
  end if;

  v_atividades := coalesce(p_payload->'atividades', '[]'::jsonb);
  if jsonb_typeof(v_atividades) <> 'array' then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:atividades';
  end if;

  -- CADA SESSÃO ENVIADA PRECISA SER DESTE EVENTO E DESTE DIA. Um id de
  -- outro dia, de outro evento ou inventado derruba o envio inteiro.
  select count(*) into v_invalidas
  from jsonb_array_elements(v_atividades) a
  where jsonb_typeof(a->'nota') <> 'number'
     or (a->>'nota')::numeric not between 0 and 5
     or (a->>'nota')::numeric <> floor((a->>'nota')::numeric)
     or not exists (
       select 1 from summit_2026.sessions s
       where s.id = nullif(a->>'sessaoId', '')::uuid
         and s.event_id = v_evento.id and s.dia = p_dia
         and s.tipo is distinct from 'credenciamento'
         and s.tipo is distinct from 'intervalo'
         and s.tipo is distinct from 'almoco'
     );
  if v_invalidas > 0 then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:sessao_invalida';
  end if;

  -- A mesma sessão duas vezes no envio é erro de cliente, não escolha:
  -- aceitar exigiria decidir qual das duas notas vale, e não há resposta
  -- certa para isso.
  if (select count(*) from jsonb_array_elements(v_atividades) a)
     <> (select count(distinct a->>'sessaoId') from jsonb_array_elements(v_atividades) a) then
    raise exception using errcode = '22023', message = 'avaliacao_validacao:sessao_repetida';
  end if;

  -- Trava contra envio duplo e concorrente: dois cliques simultâneos
  -- disputam esta linha, e o segundo só continua depois que o primeiro
  -- terminou — então ele encontra a resposta já gravada em vez de criar
  -- a segunda.
  perform pg_advisory_xact_lock(
    hashtext('avaliacao_do_dia'),
    hashtext(v_participante_id::text || v_evento.id::text || p_dia::text)
  );

  select * into v_existente from engagement.avaliacao_do_dia a
  where a.participante_id = v_participante_id and a.event_id = v_evento.id and a.dia = p_dia;

  if found then
    -- Reenvio idêntico reconhece o que já está gravado. Divergente é
    -- recusado: `upsert` aqui sobrescreveria resposta concluída.
    v_iguais :=
      v_existente.experiencia = v_experiencia
      and v_existente.profissao = v_profissao
      and v_existente.expectativas = v_expectativas
      and v_existente.nota_expectativas = v_nota_exp
      and v_existente.nota_programacao = v_nota_prog
      and v_existente.mais_gostou is not distinct from v_mais_gostou
      and v_existente.melhorar is not distinct from v_melhorar
      and v_existente.comentario is not distinct from v_comentario
      -- As notas por atividade viram um mapa `sessão → nota` dos dois
      -- lados e os mapas se comparam inteiros. jsonb ignora ordem de
      -- chave, então "mesmas notas em outra ordem" é igual — que é o
      -- que a pessoa mandou.
      and (
        select coalesce(jsonb_object_agg(at.sessao_id::text, at.nota), '{}'::jsonb)
        from engagement.avaliacao_do_dia_atividade at
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
                                'enviadoEm', v_existente.enviado_em, 'dia', v_existente.dia);
    end if;
    raise exception using errcode = '23505', message = 'avaliacao_ja_enviada';
  end if;

  insert into engagement.avaliacao_do_dia (
    participante_id, event_id, dia, formulario_versao, experiencia, profissao,
    expectativas, nota_expectativas, nota_programacao, mais_gostou, melhorar, comentario
  ) values (
    v_participante_id, v_evento.id, p_dia, 1, v_experiencia, v_profissao,
    v_expectativas, v_nota_exp, v_nota_prog, v_mais_gostou, v_melhorar, v_comentario
  ) returning id into v_id;

  insert into engagement.avaliacao_do_dia_atividade (avaliacao_id, sessao_id, nota)
  select v_id, nullif(a->>'sessaoId','')::uuid, (a->>'nota')::smallint
  from jsonb_array_elements(v_atividades) a
  on conflict (avaliacao_id, sessao_id) do nothing;

  return jsonb_build_object('id', v_id, 'jaRegistrado', false, 'dia', p_dia,
                            'enviadoEm', (select enviado_em from engagement.avaliacao_do_dia where id = v_id));
end;
$function$;

comment on function public.mind_avaliacao_do_dia_registrar(uuid, text, date, jsonb) is
  'Envio definitivo da Avaliação do dia, numa transação. Reenvio idêntico devolve a resposta já gravada; divergente é recusado.';

-- ============================================================
-- 6 · O relatório — KPIs e a tabela por atividade
-- ============================================================
-- SEM CONTAGEM DUPLICADA: as respostas e as notas por atividade são
-- contadas em consultas separadas e só se encontram no jsonb final. Um
-- join entre as duas multiplicaria cada resposta pelo número de notas
-- que ela tem.
--
-- Atividade sem nota nenhuma sai com `avaliacoes: 0` e `media: null`.
-- Nunca zero — zero é uma nota que alguém deu.

create or replace function public.mind_avaliacao_do_dia_relatorio(
  p_event_slug text default 'mind-summit-2026',
  p_dia date default null,
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
    from engagement.avaliacao_do_dia a
    where a.event_id = v_evento.id
      and (p_dia is null or a.dia = p_dia)
      and (v_exp is null or a.experiencia = v_exp)
  ),
  notas as (
    select at.sessao_id, at.nota
    from engagement.avaliacao_do_dia_atividade at
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
      and (p_dia is null or s.dia = p_dia)
      and s.tipo is distinct from 'credenciamento'
      and s.tipo is distinct from 'intervalo'
      and s.tipo is distinct from 'almoco'
    group by s.id, s.titulo, s.dia, s.inicio, l.nome, s.tipo, s.ingressos
  )
  select jsonb_build_object(
    'evento', jsonb_build_object('slug', v_evento.slug, 'nome', v_evento.nome,
                                 'dias', to_jsonb(v_evento.dias), 'fuso', v_evento.fuso),
    'filtro', jsonb_build_object('dia', p_dia, 'experiencia', v_exp),
    'kpis', (
      select jsonb_build_object(
        'respondentes', count(*),
        'porExperiencia', jsonb_build_object(
          'mind',  count(*) filter (where experiencia = 'mind'),
          'vip',   count(*) filter (where experiencia = 'vip'),
          'prime', count(*) filter (where experiencia = 'prime')
        ),
        -- Cada média usa só as respostas da própria pergunta. Aqui as
        -- duas são obrigatórias, então o denominador é o mesmo — e sai
        -- explícito assim mesmo, para a tela poder mostrá-lo.
        'expectativas', jsonb_build_object(
          'amostra', count(nota_expectativas),
          'media', avg(nota_expectativas)::numeric(4,2),
          'distribuicao', jsonb_build_object(
            '0', count(*) filter (where nota_expectativas = 0),
            '1', count(*) filter (where nota_expectativas = 1),
            '2', count(*) filter (where nota_expectativas = 2),
            '3', count(*) filter (where nota_expectativas = 3),
            '4', count(*) filter (where nota_expectativas = 4),
            '5', count(*) filter (where nota_expectativas = 5)),
          'percentual45', case when count(nota_expectativas) = 0 then null
            else round(100.0 * count(*) filter (where nota_expectativas >= 4)
                       / count(nota_expectativas), 1) end
        ),
        'programacao', jsonb_build_object(
          'amostra', count(nota_programacao),
          'media', avg(nota_programacao)::numeric(4,2),
          'distribuicao', jsonb_build_object(
            '0', count(*) filter (where nota_programacao = 0),
            '1', count(*) filter (where nota_programacao = 1),
            '2', count(*) filter (where nota_programacao = 2),
            '3', count(*) filter (where nota_programacao = 3),
            '4', count(*) filter (where nota_programacao = 4),
            '5', count(*) filter (where nota_programacao = 5)),
          'percentual45', case when count(nota_programacao) = 0 then null
            else round(100.0 * count(*) filter (where nota_programacao >= 4)
                       / count(nota_programacao), 1) end
        )
      ) from respostas
    ),
    'avaliacoesDeAtividades', (select count(*) from notas),
    'porAtividade', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'titulo', titulo, 'dia', dia, 'inicio', inicio,
        'espaco', espaco, 'tipo', tipo, 'ingressos', ingressos,
        'avaliacoes', avaliacoes,
        'media', media,
        'distribuicao', jsonb_build_object('0', n0, '1', n1, '2', n2, '3', n3, '4', n4, '5', n5)
      ) order by dia, inicio, titulo)
      from por_atividade
    ), '[]'::jsonb)
  ) into v_resultado;

  return v_resultado;
end;
$function$;

comment on function public.mind_avaliacao_do_dia_relatorio(text, date, text) is
  'KPIs e tabela por atividade da Avaliação do dia. Média sempre acompanhada do tamanho da amostra; atividade sem nota tem media nula, nunca zero.';

-- ============================================================
-- 7 · As respostas, uma a uma — para a lista e para o CSV
-- ============================================================
-- Paginada. Traz as abertas junto, porque a tela do painel mostra as
-- duas coisas no mesmo lugar e o CSV exporta a mesma linha.

create or replace function public.mind_avaliacao_do_dia_respostas(
  p_event_slug text default 'mind-summit-2026',
  p_dia date default null,
  p_experiencia text default null,
  p_sessao_id uuid default null,
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

  -- Filtrar por atividade estreita as RESPOSTAS a quem avaliou aquela
  -- atividade. `exists` e não join: join traria a resposta uma vez por
  -- nota, e a mesma pessoa apareceria repetida na lista e na contagem.
  select count(*) into v_total
  from engagement.avaliacao_do_dia a
  where a.event_id = v_evento.id
    and (p_dia is null or a.dia = p_dia)
    and (v_exp is null or a.experiencia = v_exp)
    and (p_sessao_id is null or exists (
      select 1 from engagement.avaliacao_do_dia_atividade at
      where at.avaliacao_id = a.id and at.sessao_id = p_sessao_id));

  select coalesce(jsonb_agg(x order by ordem), '[]'::jsonb) into v_itens
  from (
    select jsonb_build_object(
      'id', a.id,
      'dia', a.dia,
      'enviadoEm', a.enviado_em,
      'experiencia', a.experiencia,
      'profissao', a.profissao,
      'expectativas', a.expectativas,
      'notaExpectativas', a.nota_expectativas,
      'notaProgramacao', a.nota_programacao,
      'maisGostou', a.mais_gostou,
      'melhorar', a.melhorar,
      'comentario', a.comentario,
      'atividadesAvaliadas', (
        select count(*) from engagement.avaliacao_do_dia_atividade at
        where at.avaliacao_id = a.id)
    ) as x,
    row_number() over (order by a.enviado_em desc, a.id) as ordem
    from engagement.avaliacao_do_dia a
    where a.event_id = v_evento.id
      and (p_dia is null or a.dia = p_dia)
      and (v_exp is null or a.experiencia = v_exp)
      and (p_sessao_id is null or exists (
        select 1 from engagement.avaliacao_do_dia_atividade at
        where at.avaliacao_id = a.id and at.sessao_id = p_sessao_id))
    order by a.enviado_em desc, a.id
    offset (v_pagina - 1) * v_por
    limit v_por
  ) pagina;

  return jsonb_build_object('total', v_total, 'pagina', v_pagina,
                            'porPagina', v_por, 'itens', v_itens);
end;
$function$;

comment on function public.mind_avaliacao_do_dia_respostas(text, date, text, uuid, int, int) is
  'Respostas da Avaliação do dia, paginadas, com as perguntas abertas. Restrita ao painel administrativo.';

-- ============================================================
-- 8 · Permissões mínimas
-- ============================================================
-- Só `service_role`. Quem chama é a Edge Function `mindagent-avaliacao`,
-- que resolve a identidade e o papel antes. `anon` e `authenticated` não
-- executam nenhuma delas — participante não alcança resposta de terceiro
-- nem o relatório, e não há caminho de PostgREST para as tabelas.

revoke execute on function public.mind_avaliacao_do_dia_estado(uuid, text, date) from public;
revoke execute on function public.mind_avaliacao_do_dia_registrar(uuid, text, date, jsonb) from public;
revoke execute on function public.mind_avaliacao_do_dia_relatorio(text, date, text) from public;
revoke execute on function public.mind_avaliacao_do_dia_respostas(text, date, text, uuid, int, int) from public;

grant execute on function public.mind_avaliacao_do_dia_estado(uuid, text, date) to service_role;
grant execute on function public.mind_avaliacao_do_dia_registrar(uuid, text, date, jsonb) to service_role;
grant execute on function public.mind_avaliacao_do_dia_relatorio(text, date, text) to service_role;
grant execute on function public.mind_avaliacao_do_dia_respostas(text, date, text, uuid, int, int) to service_role;
