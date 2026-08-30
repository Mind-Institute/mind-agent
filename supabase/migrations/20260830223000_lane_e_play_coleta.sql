-- ============================================================
-- Lane E — Play: camada de COLETA sobre as casas que já existem
-- ------------------------------------------------------------
-- O QUE ESTA MIGRATION É
--
--   Os writers que faltavam. As casas do Play já existiam e já apontam para
--   a identidade canônica (`pessoas.pessoas.id`), e as ferramentas do Play já
--   estavam registradas em `concierge.ferramentas` com o json_schema fechado.
--   O que não existia era função nenhuma que escrevesse nelas: as quatro
--   tabelas estavam com zero linha e `concierge.ferramenta_chamadas` também.
--
--   Nenhuma tabela nova. Nenhuma coluna nova. Nenhuma Intelligence nova.
--   Nenhuma identidade nova. Nada é escrito em `concierge.*`.
--
-- CONTRATO DE ENTRADA — decisão desta camada
--
--   `p_payload` é o objeto de argumentos LITERAL da ferramenta já registrada
--   em `concierge.ferramentas.json_schema`. O runtime repassa a chamada da
--   ferramenta sem traduzir. Uma casa, um contrato, um lugar para mudar.
--
--     mind_play_feedback_sessao  ← registrar_feedback_sessao
--     mind_play_nps              ← registrar_nps
--     mind_play_feedback_evento  ← registrar_feedback_evento
--     mind_play_feedback         ← registrar_feedback
--
--   `mind_play_nps_agregado` não tem ferramenta: é a leitura determinística
--   de "NPS por sessão e geral" a partir das mesmas casas.
--
-- TAXONOMIA DE ERRO — mesma forma já congelada em `mind_agent_kit`
--
--   Sucesso: {"ok": true, ...}.  Falha: {"ok": false, "motivo": "<codigo>"}.
--   Nada é levantado como exception: o chamador é um runtime de agente e
--   precisa da recusa como dado, não como erro de transação.
--
-- O QUE ESTA CAMADA NÃO DECIDE
--
--   Não pontua, não recomenda, não escreve texto e não interpreta. Ela grava
--   o que a pessoa disse, no lugar canônico, de forma idempotente. Quando o
--   dado não existe, ela devolve ausência — nunca um número fabricado.
-- ============================================================


-- ============================================================
-- 1. mind_play_feedback_sessao — NPS/feedback POR SESSÃO
-- ------------------------------------------------------------
-- Casa: `engagement.sessao_feedback`, UNIQUE (participante_id, sessao_id).
--
-- A ferramenta registrada diz "pode ser preenchido aos poucos, em turnos
-- diferentes". Por isso o UPDATE é COALESCE(novo, antigo) campo a campo: um
-- turno que só traz `insight` não apaga a `nota` do turno anterior. É também
-- o que torna a chamada idempotente — repetir o mesmo payload não duplica
-- linha nem perde conteúdo.
-- ============================================================
create or replace function public.mind_play_feedback_sessao(
  p_pessoa_id   uuid,
  p_payload     jsonb,
  p_conversa_id uuid default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_sessao_txt text;
  v_sessao_id  uuid;
  v_nota_txt   text;
  v_nota       integer;
  v_id         uuid;
  v_criado     boolean;
begin
  if p_pessoa_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa');
  end if;
  if not exists (select 1 from pessoas.pessoas p where p.id = p_pessoa_id) then
    return jsonb_build_object('ok', false, 'motivo', 'pessoa_nao_encontrada');
  end if;

  if p_conversa_id is not null
     and not exists (select 1 from engagement.conversas c where c.id = p_conversa_id) then
    return jsonb_build_object('ok', false, 'motivo', 'conversa_nao_encontrada');
  end if;

  v_sessao_txt := nullif(btrim(coalesce(p_payload->>'sessao_id', '')), '');
  if v_sessao_txt is null
     or v_sessao_txt !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return jsonb_build_object('ok', false, 'motivo', 'sem_sessao');
  end if;
  v_sessao_id := v_sessao_txt::uuid;

  if not exists (select 1 from summit_2026.sessions s where s.id = v_sessao_id) then
    return jsonb_build_object('ok', false, 'motivo', 'sessao_nao_encontrada');
  end if;

  -- nota é opcional; quando vem, é 0..10 inteiro (CHECK da tabela)
  v_nota_txt := nullif(btrim(coalesce(p_payload->>'nota', '')), '');
  if v_nota_txt is not null then
    if v_nota_txt !~ '^-?[0-9]+$' then
      return jsonb_build_object('ok', false, 'motivo', 'nota_invalida');
    end if;
    v_nota := v_nota_txt::integer;
    if v_nota < 0 or v_nota > 10 then
      return jsonb_build_object('ok', false, 'motivo', 'nota_fora_da_faixa');
    end if;
  end if;

  insert into engagement.sessao_feedback as sf
    (participante_id, sessao_id, nota, relevancia, insight,
     intencao_aplicar, o_que_faltou, comentario, conversa_id)
  values
    (p_pessoa_id, v_sessao_id, v_nota,
     nullif(btrim(coalesce(p_payload->>'relevancia', '')), ''),
     nullif(btrim(coalesce(p_payload->>'insight', '')), ''),
     nullif(btrim(coalesce(p_payload->>'intencao_aplicar', '')), ''),
     nullif(btrim(coalesce(p_payload->>'o_que_faltou', '')), ''),
     nullif(btrim(coalesce(p_payload->>'comentario', '')), ''),
     p_conversa_id)
  on conflict (participante_id, sessao_id) do update set
    nota             = coalesce(excluded.nota,             sf.nota),
    relevancia       = coalesce(excluded.relevancia,       sf.relevancia),
    insight          = coalesce(excluded.insight,          sf.insight),
    intencao_aplicar = coalesce(excluded.intencao_aplicar, sf.intencao_aplicar),
    o_que_faltou     = coalesce(excluded.o_que_faltou,     sf.o_que_faltou),
    comentario       = coalesce(excluded.comentario,       sf.comentario),
    conversa_id      = coalesce(excluded.conversa_id,      sf.conversa_id),
    atualizado_em    = now()
  returning sf.id, (xmax = 0) into v_id, v_criado;

  return jsonb_build_object(
    'ok',          true,
    'acao',        case when v_criado then 'criado' else 'atualizado' end,
    'feedback_id', v_id,
    'sessao_id',   v_sessao_id);
end;
$fn$;

revoke all on function public.mind_play_feedback_sessao(uuid, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.mind_play_feedback_sessao(uuid, jsonb, uuid) to service_role;

comment on function public.mind_play_feedback_sessao(uuid, jsonb, uuid) is
  'Play — coleta de feedback/NPS por sessão em engagement.sessao_feedback. p_payload é o objeto literal da ferramenta registrada `registrar_feedback_sessao` (sessao_id, nota, relevancia, insight, intencao_aplicar, o_que_faltou, comentario). Upsert por (participante_id, sessao_id) com preenchimento parcial COALESCE(novo, antigo): turnos diferentes completam a mesma linha sem apagar o que já havia. Motivos de recusa: sem_pessoa > pessoa_nao_encontrada > conversa_nao_encontrada > sem_sessao > sessao_nao_encontrada > nota_invalida > nota_fora_da_faixa. Não pontua, não recomenda, não escreve texto.';


-- ============================================================
-- 2. mind_play_nps — NPS GERAL do Summit
-- ------------------------------------------------------------
-- Casa: `engagement.nps`, UNIQUE (participante_id) — uma nota por pessoa por
-- construção da tabela. Reenviar substitui, e o `retrato` é recalculado junto
-- para continuar sendo o retrato daquele momento, não de um momento antigo.
--
-- `retrato` é derivado só de fato já gravado: quantas sessões a pessoa avaliou,
-- a média dessas notas e o que a jornada dela já registra. Zero inferência.
-- ============================================================
create or replace function public.mind_play_nps(
  p_pessoa_id   uuid,
  p_payload     jsonb,
  p_conversa_id uuid default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_nota_txt text;
  v_nota     integer;
  v_event_id uuid;
  v_retrato  jsonb;
  v_id       uuid;
  v_criado   boolean;
begin
  if p_pessoa_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa');
  end if;
  if not exists (select 1 from pessoas.pessoas p where p.id = p_pessoa_id) then
    return jsonb_build_object('ok', false, 'motivo', 'pessoa_nao_encontrada');
  end if;

  if p_conversa_id is not null
     and not exists (select 1 from engagement.conversas c where c.id = p_conversa_id) then
    return jsonb_build_object('ok', false, 'motivo', 'conversa_nao_encontrada');
  end if;

  -- nota é obrigatória aqui: sem ela não há NPS (a tabela também exige)
  v_nota_txt := nullif(btrim(coalesce(p_payload->>'nota', '')), '');
  if v_nota_txt is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_nota');
  end if;
  if v_nota_txt !~ '^-?[0-9]+$' then
    return jsonb_build_object('ok', false, 'motivo', 'nota_invalida');
  end if;
  v_nota := v_nota_txt::integer;
  if v_nota < 0 or v_nota > 10 then
    return jsonb_build_object('ok', false, 'motivo', 'nota_fora_da_faixa');
  end if;

  -- mesmo critério de evento ativo já usado pelos providers do Kit
  select e.id into v_event_id
    from summit_2026.events e
   where e.ativo
   order by e.slug
   limit 1;

  select jsonb_build_object(
           'em',                              now(),
           'sessoes_avaliadas',               count(*) filter (where sf.nota is not null),
           'nota_media_sessoes',              round(avg(sf.nota)::numeric, 2),
           'sessoes_planejadas',              (select count(*) from engagement.jornada_sessao j
                                                where j.participante_id = p_pessoa_id and j.planejou),
           'sessoes_com_presenca_confirmada', (select count(*) from engagement.jornada_sessao j
                                                where j.participante_id = p_pessoa_id and j.compareceu))
    into v_retrato
    from engagement.sessao_feedback sf
   where sf.participante_id = p_pessoa_id;

  insert into engagement.nps as n
    (participante_id, nota, comentario, retrato, conversa_id, event_id)
  values
    (p_pessoa_id, v_nota,
     nullif(btrim(coalesce(p_payload->>'comentario', '')), ''),
     coalesce(v_retrato, '{}'::jsonb),
     p_conversa_id,
     v_event_id)
  on conflict (participante_id) do update set
    nota        = excluded.nota,
    comentario  = coalesce(excluded.comentario,  n.comentario),
    retrato     = excluded.retrato,
    conversa_id = coalesce(excluded.conversa_id, n.conversa_id),
    event_id    = coalesce(excluded.event_id,    n.event_id)
  returning n.id, (xmax = 0) into v_id, v_criado;

  return jsonb_build_object(
    'ok',      true,
    'acao',    case when v_criado then 'criado' else 'atualizado' end,
    'nps_id',  v_id,
    'nota',    v_nota,
    'retrato', coalesce(v_retrato, '{}'::jsonb));
end;
$fn$;

revoke all on function public.mind_play_nps(uuid, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.mind_play_nps(uuid, jsonb, uuid) to service_role;

comment on function public.mind_play_nps(uuid, jsonb, uuid) is
  'Play — coleta do NPS geral do Summit em engagement.nps. p_payload é o objeto literal da ferramenta registrada `registrar_nps` (nota 0..10 obrigatória, comentario opcional). UNIQUE(participante_id): reenviar substitui a nota e RECALCULA o retrato, que é derivado apenas de fato já gravado (sessões avaliadas, média dessas notas, jornada registrada). event_id vem do evento ativo. Motivos de recusa: sem_pessoa > pessoa_nao_encontrada > conversa_nao_encontrada > sem_nota > nota_invalida > nota_fora_da_faixa.';


-- ============================================================
-- 3. mind_play_feedback_evento — percepção sobre a OPERAÇÃO do evento
-- ------------------------------------------------------------
-- Casa: `engagement.evento_feedback`.
--
-- A tabela não tem chave natural. A idempotência real disponível é a
-- mensagem que originou o relato: uma mensagem produz um relato. Com
-- `p_mensagem_id`, repetir a chamada atualiza a mesma linha; sem ela, cada
-- chamada é um relato novo — que é o comportamento correto para quem relata
-- duas coisas diferentes no mesmo turno.
--
-- `categoria` e `sentimento` não têm CHECK na tabela e NÃO ganham vocabulário
-- aqui: o vocabulário já vive na descrição da ferramenta registrada, que é
-- conteúdo da Adriana. Esta função grava o que recebeu.
-- ============================================================
create or replace function public.mind_play_feedback_evento(
  p_pessoa_id   uuid,
  p_payload     jsonb,
  p_mensagem_id uuid default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_categoria  text;
  v_sentimento text;
  v_sev_txt    text;
  v_severidade integer := 1;
  v_id         uuid;
  v_criado     boolean := true;
begin
  if p_pessoa_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa');
  end if;
  if not exists (select 1 from pessoas.pessoas p where p.id = p_pessoa_id) then
    return jsonb_build_object('ok', false, 'motivo', 'pessoa_nao_encontrada');
  end if;

  if p_mensagem_id is not null
     and not exists (select 1 from engagement.mensagens m where m.id = p_mensagem_id) then
    return jsonb_build_object('ok', false, 'motivo', 'mensagem_nao_encontrada');
  end if;

  v_categoria  := nullif(btrim(coalesce(p_payload->>'categoria',  '')), '');
  v_sentimento := nullif(btrim(coalesce(p_payload->>'sentimento', '')), '');
  if v_categoria is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_categoria');
  end if;
  if v_sentimento is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_sentimento');
  end if;

  v_sev_txt := nullif(btrim(coalesce(p_payload->>'severidade', '')), '');
  if v_sev_txt is not null then
    if v_sev_txt !~ '^-?[0-9]+$' then
      return jsonb_build_object('ok', false, 'motivo', 'severidade_invalida');
    end if;
    v_severidade := v_sev_txt::integer;
    if v_severidade < 1 or v_severidade > 5 then
      return jsonb_build_object('ok', false, 'motivo', 'severidade_fora_da_faixa');
    end if;
  end if;

  if p_mensagem_id is not null then
    update engagement.evento_feedback ef
       set categoria  = v_categoria,
           sentimento = v_sentimento,
           severidade = v_severidade,
           comentario = coalesce(nullif(btrim(coalesce(p_payload->>'comentario','')), ''), ef.comentario),
           local      = coalesce(nullif(btrim(coalesce(p_payload->>'local','')),      ''), ef.local)
     where ef.participante_id = p_pessoa_id
       and ef.mensagem_id     = p_mensagem_id
    returning ef.id into v_id;

    if v_id is not null then
      v_criado := false;
    end if;
  end if;

  if v_id is null then
    insert into engagement.evento_feedback
      (participante_id, categoria, sentimento, severidade, comentario, local, mensagem_id)
    values
      (p_pessoa_id, v_categoria, v_sentimento, v_severidade,
       nullif(btrim(coalesce(p_payload->>'comentario', '')), ''),
       nullif(btrim(coalesce(p_payload->>'local',      '')), ''),
       p_mensagem_id)
    returning id into v_id;
  end if;

  return jsonb_build_object(
    'ok',          true,
    'acao',        case when v_criado then 'criado' else 'atualizado' end,
    'feedback_id', v_id);
end;
$fn$;

revoke all on function public.mind_play_feedback_evento(uuid, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.mind_play_feedback_evento(uuid, jsonb, uuid) to service_role;

comment on function public.mind_play_feedback_evento(uuid, jsonb, uuid) is
  'Play — coleta de percepção sobre a operação do evento em engagement.evento_feedback. p_payload é o objeto literal da ferramenta registrada `registrar_feedback_evento` (categoria e sentimento obrigatórios; severidade 1..5, comentario e local opcionais). Idempotente por p_mensagem_id quando informado: uma mensagem produz um relato. Vocabulário de categoria/sentimento NÃO é definido aqui — vive na descrição da ferramenta. Motivos de recusa: sem_pessoa > pessoa_nao_encontrada > mensagem_nao_encontrada > sem_categoria > sem_sentimento > severidade_invalida > severidade_fora_da_faixa.';


-- ============================================================
-- 4. mind_play_feedback — coleta tipada genérica
-- ------------------------------------------------------------
-- Casa: `engagement.feedbacks` (tipo, valor, contexto). É a casa que já existe
-- para coleta tipada e é onde a votação 2027 e o retorno de
-- masterclass/workshop cabem SEM tabela nova: `tipo` nomeia a coleta, `valor`
-- é a resposta, `contexto` carrega a evidência estruturada.
--
-- Esta função não define quais coletas existem nem quais são as opções de
-- voto. Isso é conteúdo da Adriana. A casa fica pronta e vazia.
--
-- Idempotência: (participante_id, tipo, valor, contexto) idêntico não duplica.
-- Para voto e joinha esse é o comportamento correto — retry não vira dois
-- votos. Duas respostas realmente diferentes diferem em valor ou contexto.
-- ============================================================
create or replace function public.mind_play_feedback(
  p_pessoa_id uuid,
  p_payload   jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $fn$
declare
  v_tipo     text;
  v_valor    text;
  v_contexto jsonb;
  v_id       uuid;
  v_criado   boolean := true;
begin
  if p_pessoa_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_pessoa');
  end if;
  if not exists (select 1 from pessoas.pessoas p where p.id = p_pessoa_id) then
    return jsonb_build_object('ok', false, 'motivo', 'pessoa_nao_encontrada');
  end if;

  v_tipo  := nullif(btrim(coalesce(p_payload->>'tipo',  '')), '');
  v_valor := nullif(btrim(coalesce(p_payload->>'valor', '')), '');
  if v_tipo is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_tipo');
  end if;

  if p_payload ? 'contexto' and jsonb_typeof(p_payload->'contexto') <> 'object' then
    return jsonb_build_object('ok', false, 'motivo', 'contexto_invalido');
  end if;
  v_contexto := coalesce(p_payload->'contexto', '{}'::jsonb);

  select f.id into v_id
    from engagement.feedbacks f
   where f.participante_id   = p_pessoa_id
     and f.tipo              = v_tipo
     and f.valor is not distinct from v_valor
     and f.contexto          = v_contexto
   order by f.criado_em
   limit 1;

  if v_id is not null then
    v_criado := false;
  else
    insert into engagement.feedbacks (participante_id, tipo, valor, contexto)
    values (p_pessoa_id, v_tipo, v_valor, v_contexto)
    returning id into v_id;
  end if;

  return jsonb_build_object(
    'ok',          true,
    'acao',        case when v_criado then 'criado' else 'ja_registrado' end,
    'feedback_id', v_id,
    'tipo',        v_tipo);
end;
$fn$;

revoke all on function public.mind_play_feedback(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.mind_play_feedback(uuid, jsonb) to service_role;

comment on function public.mind_play_feedback(uuid, jsonb) is
  'Play — coleta tipada genérica em engagement.feedbacks. p_payload é o objeto literal da ferramenta registrada `registrar_feedback` (tipo obrigatório, valor e contexto opcionais). É a casa já existente para votação 2027, retorno de masterclass/workshop e joinha, sem tabela nova: tipo nomeia a coleta, valor é a resposta, contexto carrega a evidência. Não define quais coletas existem nem opções de voto — isso é conteúdo. Idempotente: (participante_id, tipo, valor, contexto) idêntico devolve acao=ja_registrado sem duplicar. Motivos de recusa: sem_pessoa > pessoa_nao_encontrada > sem_tipo > contexto_invalido.';


-- ============================================================
-- 5. mind_play_nps_agregado — NPS POR SESSÃO e GERAL
-- ------------------------------------------------------------
-- Leitura determinística das mesmas casas. Sem LLM, sem escrita, sem ranking
-- opinativo: faixa NPS padrão (promotor 9-10, neutro 7-8, detrator 0-6) e
-- ordem cronológica da programação.
--
-- Sem resposta, `nps` e `nota_media` vêm NULL e a sessão não aparece na lista.
-- Zero não é o mesmo que "ninguém respondeu", e esta função não inventa um.
-- ============================================================
create or replace function public.mind_play_nps_agregado(
  p_event_slug text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_slug     text := nullif(btrim(coalesce(p_event_slug, '')), '');
  v_evento   record;
  v_geral    jsonb;
  v_sessoes  jsonb;
begin
  if v_slug is null then
    select e.id, e.slug, e.nome into v_evento
      from summit_2026.events e
     where e.ativo
     order by e.slug
     limit 1;
  else
    select e.id, e.slug, e.nome into v_evento
      from summit_2026.events e
     where e.slug = v_slug
     limit 1;
  end if;

  if v_evento.id is null then
    return jsonb_build_object('ok', false, 'motivo', 'evento_nao_encontrado');
  end if;

  -- NPS geral: engagement.nps é por pessoa e já carrega event_id.
  select jsonb_build_object(
           'respostas',  count(*),
           'promotores', count(*) filter (where n.nota >= 9),
           'neutros',    count(*) filter (where n.nota between 7 and 8),
           'detratores', count(*) filter (where n.nota <= 6),
           'nota_media', round(avg(n.nota)::numeric, 2),
           'nps',        case when count(*) = 0 then null else round(
                           (100.0 * count(*) filter (where n.nota >= 9)
                          - 100.0 * count(*) filter (where n.nota <= 6)) / count(*), 1) end)
    into v_geral
    from engagement.nps n
   where n.event_id = v_evento.id;

  -- NPS por sessão: só sessões do evento que já têm ao menos uma nota.
  select coalesce(jsonb_agg(linha order by linha_inicio, linha_titulo), '[]'::jsonb)
    into v_sessoes
    from (
      select s.inicio as linha_inicio,
             s.titulo as linha_titulo,
             jsonb_build_object(
               'sessao_id',       s.id,
               'site_session_id', s.site_session_id,
               'titulo',          s.titulo,
               'dia',             s.dia,
               'inicio',          s.inicio,
               'respostas',       count(sf.nota),
               'promotores',      count(*) filter (where sf.nota >= 9),
               'neutros',         count(*) filter (where sf.nota between 7 and 8),
               'detratores',      count(*) filter (where sf.nota <= 6),
               'nota_media',      round(avg(sf.nota)::numeric, 2),
               'nps',             round(
                                    (100.0 * count(*) filter (where sf.nota >= 9)
                                   - 100.0 * count(*) filter (where sf.nota <= 6))
                                    / count(sf.nota), 1)) as linha
        from summit_2026.sessions s
        join engagement.sessao_feedback sf
          on sf.sessao_id = s.id and sf.nota is not null
       where s.event_id = v_evento.id
       group by s.id, s.site_session_id, s.titulo, s.dia, s.inicio
    ) agrupado;

  return jsonb_build_object(
    'ok',         true,
    'evento',     jsonb_build_object('slug', v_evento.slug, 'nome', v_evento.nome),
    'geral',      v_geral,
    'por_sessao', v_sessoes);
end;
$fn$;

revoke all on function public.mind_play_nps_agregado(text)
  from public, anon, authenticated;
grant execute on function public.mind_play_nps_agregado(text) to service_role;

comment on function public.mind_play_nps_agregado(text) is
  'Play — leitura determinística de NPS geral (engagement.nps) e por sessão (engagement.sessao_feedback x summit_2026.sessions) do evento. p_event_slug nulo usa o evento ativo. Faixa NPS padrão: promotor 9-10, neutro 7-8, detrator 0-6. Sem resposta, nps e nota_media vêm NULL e a sessão não entra na lista — zero não é ausência e esta função não fabrica número. Read-only, sem LLM. Motivo de recusa: evento_nao_encontrado.';
