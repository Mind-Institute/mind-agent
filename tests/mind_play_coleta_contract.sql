-- ============================================================================
-- CONTRATO DA COLETA DO PLAY (Lane E)
--
--   public.mind_play_feedback_sessao(uuid, jsonb, uuid) -> jsonb
--   public.mind_play_nps(uuid, jsonb, uuid)             -> jsonb
--   public.mind_play_feedback_evento(uuid, jsonb, uuid) -> jsonb
--   public.mind_play_feedback(uuid, jsonb)              -> jsonb
--   public.mind_play_nps_agregado(text)                 -> jsonb
--
-- Este arquivo e TESTE, nao SQL de producao. Ele nao cria extensao, schema,
-- tabela, funcao permanente, migration nem CI: e autocontido e roda inteiro
-- dentro de uma transacao que termina em ROLLBACK. Depois dele, zero fixture
-- permanece e nada no banco muda.
--
-- Testa o CONTRATO OBSERVAVEL das funcoes contra as casas canonicas que elas
-- escrevem (engagement.sessao_feedback, engagement.nps,
-- engagement.evento_feedback, engagement.feedbacks). Nao reimplementa a
-- agregacao para comparar duas copias da mesma logica.
--
-- Qualquer contrato quebrado aborta com uma exception que diz qual.
--
-- Como rodar:  psql "$DATABASE_URL" -f tests/mind_play_coleta_contract.sql
-- ============================================================================

begin;

-- ---------------------------------------------------------------- FIXTURES
-- UUIDs proprios do teste, no prefixo 0e000000-. Nenhum id de producao.
-- A sessao sintetica entra no evento ATIVO de verdade, porque e o evento que
-- mind_play_nps_agregado resolve quando p_event_slug e nulo.

insert into pessoas.pessoas (id, primeiro_nome, sobrenome, empresa, cargo, origem)
values ('0e000000-0000-4000-8000-000000000001',
        'Pessoa', 'Play', 'Empresa Teste', 'Cargo Teste', 'manual');

insert into engagement.conversas (id, participante_id, canal, agente, iniciada_em, ultima_atividade)
values ('0e000000-0000-4000-8000-0000000000c1',
        '0e000000-0000-4000-8000-000000000001',
        'app', 'mindagent-chat', now(), now());

insert into engagement.mensagens (id, conversa_id, participante_id, papel, conteudo)
values ('0e000000-0000-4000-8000-0000000000d1',
        '0e000000-0000-4000-8000-0000000000c1',
        '0e000000-0000-4000-8000-000000000001',
        'lead', 'A fila do almoco estava enorme.');

insert into summit_2026.sessions (id, titulo, dia, inicio, fim, event_id)
values ('0e000000-0000-4000-8000-0000000000a1',
        'Sessao sintetica do contrato do Play',
        current_date, now(), now() + interval '1 hour',
        (select e.id from summit_2026.events e where e.ativo order by e.slug limit 1)),
       ('0e000000-0000-4000-8000-0000000000a2',
        'Sessao sintetica sem nota',
        current_date, now() + interval '2 hours', now() + interval '3 hours',
        (select e.id from summit_2026.events e where e.ativo order by e.slug limit 1));


-- ============================================================ CONTRATO 1
-- mind_play_feedback_sessao grava na casa canonica e devolve acao=criado.
do $c1$
declare v jsonb; v_nota integer; v_linhas integer;
begin
  v := public.mind_play_feedback_sessao(
         '0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('sessao_id', '0e000000-0000-4000-8000-0000000000a1',
                            'nota', 10,
                            'insight', 'O modelo de carga mental fechou a duvida.'),
         '0e000000-0000-4000-8000-0000000000c1');

  if not coalesce((v->>'ok')::boolean, false) then
    raise exception 'CONTRATO 1: devia aceitar, veio %', v;
  end if;
  if v->>'acao' <> 'criado' then
    raise exception 'CONTRATO 1: primeira gravacao devia ser criado, veio %', v->>'acao';
  end if;

  select sf.nota into v_nota from engagement.sessao_feedback sf
   where sf.participante_id = '0e000000-0000-4000-8000-000000000001'
     and sf.sessao_id       = '0e000000-0000-4000-8000-0000000000a1';
  if v_nota is distinct from 10 then
    raise exception 'CONTRATO 1: nota devia ser 10 na casa canonica, veio %', v_nota;
  end if;

  select count(*) into v_linhas from engagement.sessao_feedback sf
   where sf.participante_id = '0e000000-0000-4000-8000-000000000001';
  if v_linhas <> 1 then
    raise exception 'CONTRATO 1: devia haver 1 linha, ha %', v_linhas;
  end if;
end
$c1$;


-- ============================================================ CONTRATO 2
-- Preenchimento parcial: um turno posterior que so traz `o_que_faltou` NAO
-- apaga a nota nem o insight, nao duplica linha e devolve acao=atualizado.
-- E o que a ferramenta registrada promete ("preenchido aos poucos").
do $c2$
declare v jsonb; r record; v_linhas integer;
begin
  v := public.mind_play_feedback_sessao(
         '0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('sessao_id', '0e000000-0000-4000-8000-0000000000a1',
                            'o_que_faltou', 'Faltou tempo para perguntas.'));

  if v->>'acao' <> 'atualizado' then
    raise exception 'CONTRATO 2: segunda gravacao devia ser atualizado, veio %', v->>'acao';
  end if;

  select sf.nota, sf.insight, sf.o_que_faltou, sf.conversa_id into r
    from engagement.sessao_feedback sf
   where sf.participante_id = '0e000000-0000-4000-8000-000000000001'
     and sf.sessao_id       = '0e000000-0000-4000-8000-0000000000a1';

  if r.nota is distinct from 10 then
    raise exception 'CONTRATO 2: preenchimento parcial apagou a nota, veio %', r.nota;
  end if;
  if r.insight is null then
    raise exception 'CONTRATO 2: preenchimento parcial apagou o insight';
  end if;
  if r.o_que_faltou is null then
    raise exception 'CONTRATO 2: o campo novo nao foi gravado';
  end if;
  if r.conversa_id is distinct from '0e000000-0000-4000-8000-0000000000c1'::uuid then
    raise exception 'CONTRATO 2: conversa da primeira gravacao devia ser preservada, veio %', r.conversa_id;
  end if;

  select count(*) into v_linhas from engagement.sessao_feedback sf
   where sf.participante_id = '0e000000-0000-4000-8000-000000000001';
  if v_linhas <> 1 then
    raise exception 'CONTRATO 2: upsert duplicou linha, ha %', v_linhas;
  end if;
end
$c2$;


-- ============================================================ CONTRATO 3
-- Recusa e dado, nao exception. E a precedencia dos motivos e a declarada.
do $c3$
declare v jsonb;
begin
  v := public.mind_play_feedback_sessao(null, jsonb_build_object('sessao_id','0e000000-0000-4000-8000-0000000000a1'));
  if v->>'motivo' <> 'sem_pessoa' then
    raise exception 'CONTRATO 3: pessoa nula devia dar sem_pessoa, veio %', v;
  end if;

  v := public.mind_play_feedback_sessao('0e000000-0000-4000-8000-0000000000ff',
         jsonb_build_object('sessao_id','0e000000-0000-4000-8000-0000000000a1'));
  if v->>'motivo' <> 'pessoa_nao_encontrada' then
    raise exception 'CONTRATO 3: pessoa inexistente devia dar pessoa_nao_encontrada, veio %', v;
  end if;

  v := public.mind_play_feedback_sessao('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('sessao_id','0e000000-0000-4000-8000-0000000000a1'),
         '0e000000-0000-4000-8000-0000000000cf');
  if v->>'motivo' <> 'conversa_nao_encontrada' then
    raise exception 'CONTRATO 3: conversa inexistente devia dar conversa_nao_encontrada, veio %', v;
  end if;

  v := public.mind_play_feedback_sessao('0e000000-0000-4000-8000-000000000001', '{}'::jsonb);
  if v->>'motivo' <> 'sem_sessao' then
    raise exception 'CONTRATO 3: payload sem sessao devia dar sem_sessao, veio %', v;
  end if;

  v := public.mind_play_feedback_sessao('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('sessao_id','nao-e-uuid'));
  if v->>'motivo' <> 'sem_sessao' then
    raise exception 'CONTRATO 3: sessao_id invalido devia dar sem_sessao, veio %', v;
  end if;

  v := public.mind_play_feedback_sessao('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('sessao_id','0e000000-0000-4000-8000-0000000000fe'));
  if v->>'motivo' <> 'sessao_nao_encontrada' then
    raise exception 'CONTRATO 3: sessao inexistente devia dar sessao_nao_encontrada, veio %', v;
  end if;

  v := public.mind_play_feedback_sessao('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('sessao_id','0e000000-0000-4000-8000-0000000000a1','nota', 11));
  if v->>'motivo' <> 'nota_fora_da_faixa' then
    raise exception 'CONTRATO 3: nota 11 devia dar nota_fora_da_faixa, veio %', v;
  end if;

  v := public.mind_play_feedback_sessao('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('sessao_id','0e000000-0000-4000-8000-0000000000a1','nota','otima'));
  if v->>'motivo' <> 'nota_invalida' then
    raise exception 'CONTRATO 3: nota nao numerica devia dar nota_invalida, veio %', v;
  end if;
end
$c3$;


-- ============================================================ CONTRATO 4
-- mind_play_nps grava a nota e um retrato DERIVADO do que ja existe: a
-- sessao avaliada no contrato 1 tem de aparecer na contagem. Retrato nao e
-- inferencia; e leitura.
do $c4$
declare v jsonb; v_linhas integer;
begin
  v := public.mind_play_nps('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('nota', 9, 'comentario', 'Vale pela curadoria.'),
         '0e000000-0000-4000-8000-0000000000c1');

  if not coalesce((v->>'ok')::boolean, false) then
    raise exception 'CONTRATO 4: devia aceitar, veio %', v;
  end if;
  if (v->'retrato'->>'sessoes_avaliadas')::int <> 1 then
    raise exception 'CONTRATO 4: retrato devia contar 1 sessao avaliada, veio %', v->'retrato';
  end if;
  if (v->'retrato'->>'nota_media_sessoes')::numeric <> 10 then
    raise exception 'CONTRATO 4: media das sessoes devia ser 10, veio %', v->'retrato';
  end if;

  select count(*) into v_linhas from engagement.nps n
   where n.participante_id = '0e000000-0000-4000-8000-000000000001';
  if v_linhas <> 1 then
    raise exception 'CONTRATO 4: devia haver 1 linha de NPS, ha %', v_linhas;
  end if;
end
$c4$;


-- ============================================================ CONTRATO 5
-- UNIQUE(participante_id): reenviar substitui a nota, nao cria segunda linha,
-- e o comentario anterior nao e apagado por um reenvio sem comentario.
do $c5$
declare v jsonb; r record; v_linhas integer;
begin
  v := public.mind_play_nps('0e000000-0000-4000-8000-000000000001', jsonb_build_object('nota', 6));
  if v->>'acao' <> 'atualizado' then
    raise exception 'CONTRATO 5: reenvio devia ser atualizado, veio %', v->>'acao';
  end if;

  select n.nota, n.comentario, n.event_id into r
    from engagement.nps n where n.participante_id = '0e000000-0000-4000-8000-000000000001';
  if r.nota <> 6 then
    raise exception 'CONTRATO 5: nota devia ter sido substituida por 6, veio %', r.nota;
  end if;
  if r.comentario is null then
    raise exception 'CONTRATO 5: reenvio sem comentario nao pode apagar o anterior';
  end if;
  if r.event_id is null then
    raise exception 'CONTRATO 5: event_id devia vir do evento ativo';
  end if;

  select count(*) into v_linhas from engagement.nps n
   where n.participante_id = '0e000000-0000-4000-8000-000000000001';
  if v_linhas <> 1 then
    raise exception 'CONTRATO 5: UNIQUE(participante_id) violada, ha % linhas', v_linhas;
  end if;

  v := public.mind_play_nps('0e000000-0000-4000-8000-000000000001', '{}'::jsonb);
  if v->>'motivo' <> 'sem_nota' then
    raise exception 'CONTRATO 5: NPS sem nota devia dar sem_nota, veio %', v;
  end if;
end
$c5$;


-- ============================================================ CONTRATO 6
-- Feedback de operacao do evento: idempotente por mensagem_id quando ela
-- existe; sem mensagem_id, cada chamada e um relato novo.
do $c6$
declare v jsonb; v_msg uuid; v_linhas integer;
begin
  select m.id into v_msg from engagement.mensagens m
   where m.id = '0e000000-0000-4000-8000-0000000000d1';

  v := public.mind_play_feedback_evento('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('categoria','alimentacao','sentimento','negativo',
                            'severidade', 3, 'comentario','Fila longa no almoco.',
                            'local','Praca de alimentacao'),
         v_msg);
  if v->>'acao' <> 'criado' then
    raise exception 'CONTRATO 6: primeiro relato devia ser criado, veio %', v;
  end if;

  if v_msg is not null then
    v := public.mind_play_feedback_evento('0e000000-0000-4000-8000-000000000001',
           jsonb_build_object('categoria','alimentacao','sentimento','negativo','severidade', 4),
           v_msg);
    if v->>'acao' <> 'atualizado' then
      raise exception 'CONTRATO 6: mesma mensagem devia atualizar, veio %', v;
    end if;

    select count(*) into v_linhas from engagement.evento_feedback ef
     where ef.participante_id = '0e000000-0000-4000-8000-000000000001'
       and ef.mensagem_id     = v_msg;
    if v_linhas <> 1 then
      raise exception 'CONTRATO 6: idempotencia por mensagem falhou, ha % linhas', v_linhas;
    end if;
  end if;

  v := public.mind_play_feedback_evento('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('categoria','sinalizacao','sentimento','negativo'));
  if v->>'acao' <> 'criado' then
    raise exception 'CONTRATO 6: relato novo sem mensagem devia ser criado, veio %', v;
  end if;

  v := public.mind_play_feedback_evento('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('sentimento','negativo'));
  if v->>'motivo' <> 'sem_categoria' then
    raise exception 'CONTRATO 6: sem categoria devia dar sem_categoria, veio %', v;
  end if;

  v := public.mind_play_feedback_evento('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('categoria','acesso','sentimento','neutro','severidade', 9));
  if v->>'motivo' <> 'severidade_fora_da_faixa' then
    raise exception 'CONTRATO 6: severidade 9 devia dar severidade_fora_da_faixa, veio %', v;
  end if;
end
$c6$;


-- ============================================================ CONTRATO 7
-- Coleta tipada generica: e a casa da votacao 2027 e do retorno de
-- masterclass/workshop, sem tabela nova. Retry nao vira dois votos; resposta
-- diferente e linha diferente.
do $c7$
declare v jsonb; v_linhas integer;
begin
  v := public.mind_play_feedback('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('tipo','votacao_2027','valor','tema-x',
                            'contexto', jsonb_build_object('origem','play')));
  if v->>'acao' <> 'criado' then
    raise exception 'CONTRATO 7: primeiro registro devia ser criado, veio %', v;
  end if;

  v := public.mind_play_feedback('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('tipo','votacao_2027','valor','tema-x',
                            'contexto', jsonb_build_object('origem','play')));
  if v->>'acao' <> 'ja_registrado' then
    raise exception 'CONTRATO 7: payload identico devia dar ja_registrado, veio %', v;
  end if;

  v := public.mind_play_feedback('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('tipo','masterclass_valor','valor','repetiria'));
  if v->>'acao' <> 'criado' then
    raise exception 'CONTRATO 7: coleta de tipo diferente devia ser criada, veio %', v;
  end if;

  select count(*) into v_linhas from engagement.feedbacks f
   where f.participante_id = '0e000000-0000-4000-8000-000000000001';
  if v_linhas <> 2 then
    raise exception 'CONTRATO 7: deviam existir 2 linhas, ha %', v_linhas;
  end if;

  v := public.mind_play_feedback('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('valor','sem tipo'));
  if v->>'motivo' <> 'sem_tipo' then
    raise exception 'CONTRATO 7: sem tipo devia dar sem_tipo, veio %', v;
  end if;

  v := public.mind_play_feedback('0e000000-0000-4000-8000-000000000001',
         jsonb_build_object('tipo','votacao_2027','contexto','texto'));
  if v->>'motivo' <> 'contexto_invalido' then
    raise exception 'CONTRATO 7: contexto nao-objeto devia dar contexto_invalido, veio %', v;
  end if;
end
$c7$;


-- ============================================================ CONTRATO 8
-- Agregado: le as mesmas casas, usa a faixa NPS padrao e NAO fabrica numero
-- onde nao houve resposta. A sessao sem nota nao aparece na lista.
do $c8$
declare v jsonb; v_sessao jsonb;
begin
  v := public.mind_play_nps_agregado();
  if not coalesce((v->>'ok')::boolean, false) then
    raise exception 'CONTRATO 8: devia resolver o evento ativo, veio %', v;
  end if;

  -- geral: uma unica resposta, nota 6 (contrato 5) => detrator => NPS -100
  if (v->'geral'->>'respostas')::int <> 1 then
    raise exception 'CONTRATO 8: geral devia ter 1 resposta, veio %', v->'geral';
  end if;
  if (v->'geral'->>'detratores')::int <> 1 then
    raise exception 'CONTRATO 8: nota 6 devia contar como detrator, veio %', v->'geral';
  end if;
  if (v->'geral'->>'nps')::numeric <> -100 then
    raise exception 'CONTRATO 8: NPS geral devia ser -100, veio %', v->'geral';
  end if;

  select elem into v_sessao
    from jsonb_array_elements(v->'por_sessao') elem
   where elem->>'sessao_id' = '0e000000-0000-4000-8000-0000000000a1';
  if v_sessao is null then
    raise exception 'CONTRATO 8: a sessao avaliada devia aparecer em por_sessao';
  end if;
  if (v_sessao->>'respostas')::int <> 1 or (v_sessao->>'promotores')::int <> 1 then
    raise exception 'CONTRATO 8: nota 10 devia contar como 1 promotor, veio %', v_sessao;
  end if;
  if (v_sessao->>'nps')::numeric <> 100 then
    raise exception 'CONTRATO 8: NPS da sessao devia ser 100, veio %', v_sessao;
  end if;

  if exists (select 1 from jsonb_array_elements(v->'por_sessao') elem
              where elem->>'sessao_id' = '0e000000-0000-4000-8000-0000000000a2') then
    raise exception 'CONTRATO 8: sessao sem nota nao pode aparecer em por_sessao';
  end if;

  v := public.mind_play_nps_agregado('evento-que-nao-existe');
  if v->>'motivo' <> 'evento_nao_encontrado' then
    raise exception 'CONTRATO 8: slug inexistente devia dar evento_nao_encontrado, veio %', v;
  end if;
end
$c8$;


-- ============================================================ CONTRATO 9
-- Superficie de execucao: nenhuma das cinco funcoes fica aberta a
-- public/anon/authenticated, e service_role executa todas.
do $c9$
declare r record; v_exec text[];
begin
  for r in
    select p.oid, p.proname, p.proacl, p.prosecdef
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'mind\_play\_%'
  loop
    if not r.prosecdef then
      raise exception 'CONTRATO 9: %() devia ser SECURITY DEFINER', r.proname;
    end if;

    select array_agg(distinct a.grantee::regrole::text order by a.grantee::regrole::text)
      into v_exec
      from aclexplode(r.proacl) a
     where a.privilege_type = 'EXECUTE';

    if v_exec is null then
      raise exception 'CONTRATO 9: %() sem ACL — EXECUTE estaria aberto a todos', r.proname;
    end if;
    if not ('service_role' = any(v_exec)) then
      raise exception 'CONTRATO 9: service_role devia executar %(), ACL = %', r.proname, v_exec;
    end if;
    if 'public' = any(v_exec) or 'anon' = any(v_exec) or 'authenticated' = any(v_exec) then
      raise exception 'CONTRATO 9: %() nao pode estar liberada para public/anon/authenticated, ACL = %',
        r.proname, v_exec;
    end if;
  end loop;

  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname like 'mind\_play\_%') <> 5 then
    raise exception 'CONTRATO 9: deviam existir exatamente 5 funcoes mind_play_*';
  end if;
end
$c9$;


select 'todos os 9 contratos passaram' as resultado,
       9 as contratos_verificados,
       (select count(*) from engagement.sessao_feedback
         where participante_id::text like '0e000000-%') as feedback_de_sessao_na_transacao,
       (select count(*) from engagement.feedbacks
         where participante_id::text like '0e000000-%') as coleta_tipada_na_transacao;

-- Nada do que este arquivo criou sobrevive a esta linha.
rollback;
