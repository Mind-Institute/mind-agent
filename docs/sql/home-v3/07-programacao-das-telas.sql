-- ============================================================
-- 07 · Programação das telas da home pela data do evento
-- ============================================================
-- Projeto: mind-agent (ymnmotgglsrxmjmonwjz)
-- Depende de: 04 (a chave `home` em `concierge.config`) e 06 (a leitura
-- pública que aplica a regra). Aplicado em produção em 02/09/2026.
--
-- POR QUE NÃO TEM CÓDIGO NOVO AQUI
-- A pergunta "qual tela mostrar hoje?" já tinha motor: `04` criou a chave
-- `home` com `modo`/`momento`/`trocas`, e `06` fez `api.mindagent_home_publico`
-- resolver, em `modo = 'programado'`, a ÚLTIMA troca cujo horário já passou,
-- avaliada no fuso do evento. Sem cron: a regra é aplicada na leitura.
--
-- O que faltava era só o dado — `trocas` estava vazio e `modo` estava em
-- `manual`, com a home pregada em `no-evento` desde 01/09. Ou seja: em 2 de
-- setembro o app mostrava a tela de dia de evento para todo mundo.
--
-- POR QUE A REGRA NÃO MORA NO FRONT-END
-- Seria tentador calcular a fase em `home/estado.js` a partir de `new Date()`.
-- Três razões para não fazer isso:
--   * o relógio seria o do aparelho. Num evento presencial com gente de outros
--     fusos, cada telefone viraria a tela numa hora diferente. Aqui o corte é
--     feito uma vez, no servidor, no fuso do evento;
--   * já existiriam duas autoridades sobre a mesma tela — o painel e o código —
--     e é no dia do evento que isso cobra o preço;
--   * mudar um horário viraria deploy. Pelo painel, é uma linha de configuração.
--
-- A LINHA DO TEMPO, fechada pela Adriana em 02/09:
--
--   até 15/09 23:59  antes
--   16/09 00:00      no-evento     (Dia 1)
--   16/09 19:00      entre-dias
--   17/09 08:00      no-evento     (Dia 2 — ver BACKLOG.md §15)
--   17/09 19:00      depois
--
-- Os intervalos são meio-abertos por construção: como vale a última troca já
-- passada, 16/09 19:00:00 em ponto já é `entre-dias`. Não existe segundo morto
-- entre uma tela e a seguinte.
--
-- A ÂNCORA `troca_antes` existe para a programação não depender do campo
-- `momento`, que é o modo manual. Com uma troca sempre no passado, a fase é
-- inteiramente determinada pela agenda; `momento` volta a ser só o que ele deve
-- ser — a saída de emergência de quem virar a chave para `manual` no dia.
--
-- O DIA 2 NÃO TEM TELA PRÓPRIA e aponta para `no-evento` de propósito. A nota da
-- troca diz isso, então a pendência aparece no painel e não só no backlog.
-- Acrescentar um quinto momento exigiria mexer no `z.enum` do painel, no
-- `MOMENTOS` do front e na validação de `04` — está registrado em BACKLOG.md §15.

update concierge.config
set valor = valor || jsonb_build_object(
  'modo', 'programado',
  -- Saída de emergência: só vale se alguém voltar o modo para `manual`.
  'momento', 'antes',
  'trocas', jsonb_build_array(
    jsonb_build_object(
      'id','troca_antes','quando','2026-01-01T00:00','momento','antes',
      'nota','Âncora: antes do evento. Garante que sempre existe uma troca já passada, então a programação não depende do momento manual.',
      'arquivada',false,'criadoEm',clock_timestamp(),'atualizadoEm',clock_timestamp(),'atualizadoPor','claude/lane-b'),
    jsonb_build_object(
      'id','troca_dia1','quando','2026-09-16T00:00','momento','no-evento',
      'nota','Dia 1 do Summit, da meia-noite.',
      'arquivada',false,'criadoEm',clock_timestamp(),'atualizadoEm',clock_timestamp(),'atualizadoPor','claude/lane-b'),
    jsonb_build_object(
      'id','troca_entre_dias','quando','2026-09-16T19:00','momento','entre-dias',
      'nota','Fim do Dia 1, entre os dois dias.',
      'arquivada',false,'criadoEm',clock_timestamp(),'atualizadoEm',clock_timestamp(),'atualizadoPor','claude/lane-b'),
    jsonb_build_object(
      'id','troca_dia2','quando','2026-09-17T08:00','momento','no-evento',
      'nota','Dia 2 do Summit. REVISITAR: a tela propria do Dia 2 ainda nao existe; por ora reusa a do Dia 1.',
      'arquivada',false,'criadoEm',clock_timestamp(),'atualizadoEm',clock_timestamp(),'atualizadoPor','claude/lane-b'),
    jsonb_build_object(
      'id','troca_depois','quando','2026-09-17T19:00','momento','depois',
      'nota','Fim do Summit, pos-evento.',
      'arquivada',false,'criadoEm',clock_timestamp(),'atualizadoEm',clock_timestamp(),'atualizadoPor','claude/lane-b')
  ))
where chave = 'home';

-- ------------------------------------------------------------
-- Conferência: a linha do tempo inteira, pela mesma regra que a leitura
-- pública aplica. Falha alto se qualquer instante resolver para outra tela.
do $conferir$
declare
  v_esperado constant jsonb := jsonb_build_object(
    '2026-09-02 10:00','antes',
    '2026-09-15 23:59','antes',
    '2026-09-16 00:00','no-evento',
    '2026-09-16 18:59','no-evento',
    '2026-09-16 19:00','entre-dias',
    '2026-09-17 07:59','entre-dias',
    '2026-09-17 08:00','no-evento',
    '2026-09-17 18:59','no-evento',
    '2026-09-17 19:00','depois',
    '2026-09-18 09:00','depois');
  v_instante text; v_quer text; v_tem text; v_valor jsonb;
begin
  select valor into v_valor from concierge.config where chave = 'home';
  if v_valor->>'modo' is distinct from 'programado' then
    raise exception 'a home nao ficou em modo programado';
  end if;
  if jsonb_array_length(v_valor->'trocas') <> 5 then
    raise exception 'esperava 5 trocas, achei %', jsonb_array_length(v_valor->'trocas');
  end if;

  for v_instante, v_quer in select * from jsonb_each_text(v_esperado)
  loop
    select coalesce((
      select troca->>'momento'
      from jsonb_array_elements(coalesce(v_valor->'trocas','[]'::jsonb)) troca
      where coalesce((troca->>'arquivada')::boolean, false) is false
        and (replace(troca->>'quando','T',' '))::timestamp at time zone 'America/Sao_Paulo'
            <= (v_instante::timestamp at time zone 'America/Sao_Paulo')
      order by troca->>'quando' desc limit 1
    ), v_valor->>'momento', 'antes') into v_tem;

    if v_tem is distinct from v_quer then
      raise exception 'em % esperava % e deu %', v_instante, v_quer, v_tem;
    end if;
  end loop;
end $conferir$;
