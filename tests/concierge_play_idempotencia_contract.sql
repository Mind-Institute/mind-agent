-- ============================================================
-- CONTRATOS — idempotência de transporte do Play
-- ------------------------------------------------------------
-- Prova `public.mind_play_chamada_iniciar` / `..._concluir` sobre a casa que
-- já existe, `concierge.ferramenta_chamadas`.
--
-- COMO RODAR (sem tocar produção):
--   begin;
--     \i supabase/migrations/20260831010000_concierge_play_idempotencia.sql
--     \i tests/concierge_play_idempotencia_contract.sql
--   rollback;
--
-- Qualquer contrato quebrado levanta exception e aborta a transação. Foi assim
-- que este arquivo foi validado contra produção: 8/8, e produção conferida
-- intacta depois (0 funções do ledger, 0 linhas na tabela).
-- ============================================================
do $teste$
declare
  a uuid; b uuid;
  r1 jsonb; r2 jsonb; r3 jsonb; c1 jsonb;
  n bigint;
begin
  select id into a from pessoas.pessoas order by id limit 1;
  select id into b from pessoas.pessoas order by id desc limit 1;
  if a is null or b is null or a = b then
    raise exception 'C0 precisa de duas pessoas distintas em pessoas.pessoas';
  end if;

  -- C1 — SEM CHAVE O COMPORTAMENTO DE HOJE É PRESERVADO
  -- O índice é parcial: NULL nunca colide, então quem não manda
  -- `client_action_id` continua executando, sempre.
  r1 := public.mind_play_chamada_iniciar('registrar_nps', a, null, '{}'::jsonb);
  r2 := public.mind_play_chamada_iniciar('registrar_nps', a, null, '{}'::jsonb);
  if r1->>'estado' <> 'nova' or r2->>'estado' <> 'nova' then
    raise exception 'C1 sem chave deveria ser sempre nova: % / %', r1, r2;
  end if;
  if r1->>'chamada_id' = r2->>'chamada_id' then
    raise exception 'C1 sem chave deveria gerar reservas distintas';
  end if;

  -- C2 — A PRIMEIRA COM CHAVE RESERVA
  r1 := public.mind_play_chamada_iniciar('registrar_feedback_evento', a, 'k-1', '{"categoria":"acesso"}'::jsonb);
  if r1->>'estado' <> 'nova' then raise exception 'C2 esperava nova, veio %', r1; end if;

  -- C3 — REPETIÇÃO ENQUANTO A PRIMEIRA NÃO RESPONDEU
  -- Reservar ANTES de executar é o que fecha a corrida: a segunda tentativa
  -- simultânea não chega ao writer.
  r2 := public.mind_play_chamada_iniciar('registrar_feedback_evento', a, 'k-1', '{"categoria":"acesso"}'::jsonb);
  if r2->>'estado' <> 'em_andamento' then raise exception 'C3 esperava em_andamento, veio %', r2; end if;
  if r2->>'chamada_id' <> r1->>'chamada_id' then raise exception 'C3 deveria apontar a mesma reserva'; end if;

  -- C4 — DEPOIS DE CONCLUÍDA, O RETRY RECEBE O DESFECHO GRAVADO
  -- Uma chave, uma linha: é o que impede o segundo relato em
  -- `engagement.evento_feedback` quando `p_mensagem_id` é nulo.
  c1 := public.mind_play_chamada_concluir((r1->>'chamada_id')::uuid, 'concluida',
          '{"ok":true,"acao":"criado","feedback_id":"x"}'::jsonb, 200, 12);
  if c1->>'ok' <> 'true' then raise exception 'C4 concluir falhou: %', c1; end if;
  r3 := public.mind_play_chamada_iniciar('registrar_feedback_evento', a, 'k-1', '{"categoria":"acesso"}'::jsonb);
  if r3->>'estado' <> 'repetida' or r3->>'status' <> 'concluida' then
    raise exception 'C4 esperava repetida/concluida, veio %', r3;
  end if;
  if r3->'saida'->>'feedback_id' <> 'x' then raise exception 'C4 saida gravada nao voltou: %', r3; end if;
  select count(*) into n from concierge.ferramenta_chamadas where idempotency_key = 'k-1';
  if n <> 1 then raise exception 'C4 a chave deveria ter exatamente 1 linha, tem %', n; end if;

  -- C5 — RECUSA É DADO E VOLTA IGUAL NO RETRY
  -- O writer recusa por domínio (`{ok:false, motivo}`); repetir a mesma
  -- tentativa devolve a mesma recusa, não um sucesso e não uma reexecução.
  r1 := public.mind_play_chamada_iniciar('registrar_nps', a, 'k-2', '{}'::jsonb);
  c1 := public.mind_play_chamada_concluir((r1->>'chamada_id')::uuid, 'recusada',
          '{"ok":false,"motivo":"sem_nota"}'::jsonb, 200, 8);
  r2 := public.mind_play_chamada_iniciar('registrar_nps', a, 'k-2', '{}'::jsonb);
  if r2->>'status' <> 'recusada' or r2->'saida'->>'motivo' <> 'sem_nota' then
    raise exception 'C5 recusa nao voltou igual: %', r2;
  end if;

  -- C6 — A CHAVE VEM DO NAVEGADOR
  -- Reaproveitar a chave de outra ferramenta ou de outra pessoa devolveria a
  -- saída alheia. Confere os dois antes de entregar qualquer coisa.
  r1 := public.mind_play_chamada_iniciar('registrar_feedback', a, 'k-1', '{}'::jsonb);
  if r1->>'motivo' <> 'chave_conflitante' then raise exception 'C6 ferramenta diferente: %', r1; end if;
  r2 := public.mind_play_chamada_iniciar('registrar_feedback_evento', b, 'k-1', '{}'::jsonb);
  if r2->>'motivo' <> 'chave_conflitante' then raise exception 'C6 pessoa diferente: %', r2; end if;

  -- C7 — GUARDAS DE ENTRADA
  if (public.mind_play_chamada_iniciar('', a, 'k-9'))->>'motivo' <> 'sem_ferramenta' then
    raise exception 'C7 ferramenta vazia';
  end if;
  if (public.mind_play_chamada_iniciar('registrar_nps', null, 'k-9'))->>'motivo' <> 'sem_pessoa' then
    raise exception 'C7 sem pessoa';
  end if;
  if (public.mind_play_chamada_concluir(gen_random_uuid(), 'inventado'))->>'motivo' <> 'status_invalido' then
    raise exception 'C7 status invalido';
  end if;

  -- C8 — DESFECHO REGISTRADO NÃO É REESCRITO
  -- Só fecha o que está em andamento: uma tentativa já registrada é história.
  c1 := public.mind_play_chamada_concluir((r3->>'chamada_id')::uuid, 'falhou', null, 502);
  if c1->>'motivo' <> 'chamada_nao_encontrada' then raise exception 'C8 reescreveu desfecho: %', c1; end if;

  raise notice 'TODOS OS 8 CONTRATOS DO LEDGER PASSARAM';
end;
$teste$;
