-- ============================================================================
-- CONTRATO DA TRAVA DE SENSIBILIDADE + Silence D2
--
-- Passo 15B. Este arquivo é TESTE, não SQL de produção: não cria extensão,
-- schema, tabela, função permanente nem migration. É autocontido e roda inteiro
-- dentro de uma transação que termina em ROLLBACK.
--
-- O que ele prova, na ordem em que importa:
--   1. item sensível NÃO PERSISTE — para cada uma das 10 chaves ativas de
--      intelligence.memoria_bloqueios, uma a uma;
--   2. item sem rótulo, com rótulo desconhecido, com chave inativa ou com o
--      enum ecoado também NÃO PERSISTE (fail closed);
--   3. item com `sensitivity = "none"` persiste, e persiste EXATAMENTE como
--      antes da trava — mesma chave, mesmo tipo, mesmo status;
--   4. o gate não olha o texto: a MESMA frase clínica passa com `none` e é
--      barrada com chave sensível;
--   5. D2 — `dormant` com `followup_count = 0` não tira a oportunidade da
--      fila; com `followup_count > 0` continua tirando;
--   6. D2 não mexe na precedência: compra continua parando a continuidade;
--   7. o prompt v2 carrega o contrato (sensitivity no JSON e `stopped` com a
--      regra de open loop).
--
-- Nenhuma mensagem é enviada, nenhum cron é ligado, nada é escrito fora da
-- transação.
--
-- Como rodar:  psql "$DATABASE_URL" -f tests/memoria_sensivel_fail_closed.sql
-- ============================================================================

begin;

insert into pessoas.pessoas (id, primeiro_nome, sobrenome, origem)
values ('15b00000-0000-4000-8000-000000000001', 'Pessoa', 'Sensivel', 'manual');

insert into engagement.conversas
  (id, participante_id, canal, agente, iniciada_em, ultima_atividade)
values ('15b00000-0000-4000-8000-0000000000c1',
        '15b00000-0000-4000-8000-000000000001',
        'whatsapp', 'treble-inbound-agent', now() - interval '2 hours', now() - interval '2 hours');

insert into engagement.mensagens (conversa_id, participante_id, papel, conteudo, origem)
values ('15b00000-0000-4000-8000-0000000000c1',
        '15b00000-0000-4000-8000-000000000001',
        'lead', 'vou confirmar com o diretor e te falo', 'conversa');


-- ----------------------------------- CONTRATO 1 - AS 10 CHAVES ATIVAS BARRAM
-- Não é uma amostra: o teste percorre `intelligence.memoria_bloqueios` e exige
-- que TODA chave ativa barre. Chave nova ativada amanhã já entra aqui sozinha.
do $c1$
declare
  r        record;
  v_n      integer;
  v_antes  bigint;
  v_depois bigint;
begin
  select count(*) into v_antes from intelligence.participante_memoria;

  for r in select chave from intelligence.memoria_bloqueios where ativo order by chave
  loop
    v_n := public.analise_projetar_memoria(
      '15b00000-0000-4000-8000-000000000001', 'analise_vendas_summit',
      jsonb_build_array(jsonb_build_object(
        'category', 'other',
        'value',    'conteudo sensivel de teste para ' || r.chave,
        'scope',    'stable',
        'confidence','high',
        'sensitivity', r.chave)),
      null);

    if v_n <> 0 then
      raise exception 'CONTRATO 1: sensitivity=% gravou % memoria(s)', r.chave, v_n;
    end if;
  end loop;

  select count(*) into v_depois from intelligence.participante_memoria;
  if v_antes <> v_depois then
    raise exception 'CONTRATO 1: a tabela cresceu de % para % com itens sensiveis', v_antes, v_depois;
  end if;
end
$c1$;


-- --------------------------------- CONTRATO 2 - FAIL CLOSED NOS OUTROS CASOS
do $c2$
declare
  v_caso text; v_item jsonb; v_n integer;
  v_inativa text;
begin
  -- Uma chave que existe mas está inativa não é `none` e não é bloqueio ativo:
  -- tem de cair em "desconhecido" e não persistir.
  insert into intelligence.memoria_bloqueios (chave, sujeito, motivo, ativo)
  values ('teste_chave_inativa', 'titular', 'fixture do teste', false);
  v_inativa := 'teste_chave_inativa';

  for v_caso, v_item in
    select * from (values
      ('sem a chave sensitivity',
       jsonb_build_object('category','interest','value','quer ver a grade','scope','stable','confidence','high')),
      ('sensitivity nula',
       jsonb_build_object('category','interest','value','quer ver a grade','scope','stable','confidence','high','sensitivity', null)),
      ('sensitivity vazia',
       jsonb_build_object('category','interest','value','quer ver a grade','scope','stable','confidence','high','sensitivity','')),
      ('sensitivity so com espacos',
       jsonb_build_object('category','interest','value','quer ver a grade','scope','stable','confidence','high','sensitivity','   ')),
      ('rotulo desconhecido',
       jsonb_build_object('category','interest','value','quer ver a grade','scope','stable','confidence','high','sensitivity','confidencial')),
      ('enum ecoado pelo modelo',
       jsonb_build_object('category','interest','value','quer ver a grade','scope','stable','confidence','high','sensitivity','none | saude_do_titular | religiao')),
      ('chave de bloqueio INATIVA',
       jsonb_build_object('category','interest','value','quer ver a grade','scope','stable','confidence','high','sensitivity', v_inativa))
    ) t(caso, item)
  loop
    v_n := public.analise_projetar_memoria(
      '15b00000-0000-4000-8000-000000000001', 'analise_vendas_summit',
      jsonb_build_array(v_item), null);
    if v_n <> 0 then
      raise exception 'CONTRATO 2: caso "%" devia ser fail closed, gravou %', v_caso, v_n;
    end if;
  end loop;
end
$c2$;


-- -------------------------------- CONTRATO 3 - `none` PERSISTE, COMO ANTES
do $c3$
declare
  v_n integer;
  r   record;
begin
  v_n := public.analise_projetar_memoria(
    '15b00000-0000-4000-8000-000000000001', 'analise_vendas_summit',
    jsonb_build_array(
      jsonb_build_object('category','role','value','diretora de RH',
                         'scope','stable','confidence','high','sensitivity','none'),
      jsonb_build_object('category','goal','value','quer levar o time',
                         'scope','opportunity','confidence','medium','sensitivity','none')),
    null);

  if v_n <> 2 then
    raise exception 'CONTRATO 3: esperava 2 memorias gravadas, veio %', v_n;
  end if;

  -- A derivação continua a mesma: chave canônica para cargo, `tipo:slug` para
  -- o resto; `ativa` só com scope estável e confiança alta.
  select tipo, chave, status, valor->>'text' as txt, valor->>'scope' as escopo, confianca
    into r
    from intelligence.participante_memoria
   where participante_id = '15b00000-0000-4000-8000-000000000001' and chave = 'cargo_atual';
  if not found then raise exception 'CONTRATO 3: cargo_atual nao foi gravado'; end if;
  if r.tipo <> 'cargo' or r.status <> 'ativa' or r.txt <> 'diretora de RH'
     or r.escopo <> 'stable' or r.confianca <> 0.90 then
    raise exception 'CONTRATO 3: derivacao de cargo mudou: %', row_to_json(r);
  end if;

  select tipo, chave, status, confianca into r
    from intelligence.participante_memoria
   where participante_id = '15b00000-0000-4000-8000-000000000001' and tipo = 'objetivo';
  if not found then raise exception 'CONTRATO 3: objetivo nao foi gravado'; end if;
  if r.status <> 'proposta' or r.confianca <> 0.70 then
    raise exception 'CONTRATO 3: derivacao de objetivo mudou: %', row_to_json(r);
  end if;

  -- CAMINHO DE SUBSTITUICAO — o comportamento preservado mais delicado. Cargo
  -- novo com o mesmo `chave` nao acumula: a linha antiga vira `substituida` e
  -- aponta para a nova. O gate nao pode ter quebrado isso.
  v_n := public.analise_projetar_memoria(
    '15b00000-0000-4000-8000-000000000001', 'analise_vendas_summit',
    jsonb_build_array(jsonb_build_object('category','role','value','VP de Pessoas',
                       'scope','stable','confidence','high','sensitivity','none')), null);
  if v_n <> 1 then
    raise exception 'CONTRATO 3: cargo novo devia gravar 1, veio %', v_n;
  end if;

  select count(*) filter (where status = 'substituida') as subs,
         count(*) filter (where status = 'ativa')       as ativas
    into r
    from intelligence.participante_memoria
   where participante_id = '15b00000-0000-4000-8000-000000000001' and chave = 'cargo_atual';
  if r.subs <> 1 or r.ativas <> 1 then
    raise exception 'CONTRATO 3: substituicao de cargo quebrou (substituida=%, ativa=%)', r.subs, r.ativas;
  end if;

  if not exists (
    select 1 from intelligence.participante_memoria a
     where a.chave = 'cargo_atual' and a.status = 'substituida'
       and a.substituida_por is not null
       and a.participante_id = '15b00000-0000-4000-8000-000000000001') then
    raise exception 'CONTRATO 3: a linha substituida nao aponta para a nova';
  end if;
end
$c3$;


-- ------------------------ CONTRATO 4 - O GATE NAO OLHA O TEXTO, OLHA O ROTULO
-- A mesma frase, com vocabulário clínico, passa com `none` e é barrada com
-- chave sensível. É a prova de que a decisão é do rótulo — e de que "é
-- psicóloga clínica" não é destruído por parecer dado de saúde.
do $c4$
declare
  v_frase constant text := 'e psicologa clinica e trabalha com burnout em equipes';
  v_n integer;
begin
  v_n := public.analise_projetar_memoria(
    '15b00000-0000-4000-8000-000000000001', 'analise_vendas_summit',
    jsonb_build_array(jsonb_build_object('category','identity','value', v_frase,
      'scope','stable','confidence','high','sensitivity','none')), null);
  if v_n <> 1 then
    raise exception 'CONTRATO 4: frase clinica com rotulo none devia persistir, veio %', v_n;
  end if;

  v_n := public.analise_projetar_memoria(
    '15b00000-0000-4000-8000-000000000001', 'analise_vendas_summit',
    jsonb_build_array(jsonb_build_object('category','other','value', v_frase,
      'scope','stable','confidence','high','sensitivity','saude_do_titular')), null);
  if v_n <> 0 then
    raise exception 'CONTRATO 4: a MESMA frase com rotulo sensivel devia ser barrada, veio %', v_n;
  end if;
end
$c4$;


-- ------------------------------------------------ CONTRATO 5 - SILENCE D2
do $c5$
declare
  c constant uuid := '15b00000-0000-4000-8000-0000000000c1';
  d constant jsonb := jsonb_build_object(
        'continuation_status', 'dormant',
        'open_loop', 'vai confirmar com o diretor');
  v0 jsonb; v1 jsonb;
begin
  -- followup_count = 0: nada foi esgotado, logo nao pode sair da fila.
  v0 := public.silence_calcular_next_review(c, d, 0, null, null, null);
  if v0->>'continuation_status' = 'dormant' or v0->>'reason_code' = 'followup_exhausted' then
    raise exception 'CONTRATO 5: dormant com followup_count=0 nao foi barrado: %', v0;
  end if;
  if v0->>'continuation_status' <> 'silence' then
    raise exception 'CONTRATO 5: esperava silence com followup_count=0, veio %', v0->>'continuation_status';
  end if;

  -- followup_count = 1: houve retomada, o comportamento antigo continua.
  v1 := public.silence_calcular_next_review(c, d, 1, now() - interval '3 days', null, null);
  if v1->>'continuation_status' <> 'dormant' or v1->>'reason_code' <> 'followup_exhausted' then
    raise exception 'CONTRATO 5: dormant com followup_count=1 devia continuar dormant, veio %', v1;
  end if;
end
$c5$;


-- --------------------------- CONTRATO 6 - D2 NAO MEXE NA PRECEDENCIA
do $c6$
declare
  c constant uuid := '15b00000-0000-4000-8000-0000000000c1';
  v jsonb;
begin
  v := public.silence_calcular_next_review(
         c,
         jsonb_build_object('continuation_status','dormant',
                            'open_loop','vai confirmar com o diretor',
                            'transaction', jsonb_build_object('purchase_status','purchased')),
         0, null, null, null);
  if v->>'continuation_status' <> 'stopped' or v->>'reason_code' <> 'purchase_declared' then
    raise exception 'CONTRATO 6: compra declarada devia parar a continuidade, veio %', v;
  end if;
  if v->>'next_review_at' is not null then
    raise exception 'CONTRATO 6: quem comprou nao pode ganhar proxima revisao: %', v;
  end if;
end
$c6$;


-- ------------------------------------- CONTRATO 7 - O PROMPT CARREGA O CONTRATO
do $c7$
declare
  v_conteudo text;
  v_versao   integer;
  v_ativo    boolean;
  r          record;
begin
  select conteudo, versao, ativo into v_conteudo, v_versao, v_ativo
    from agentes.prompts where chave = 'analise_vendas_summit';

  if not found then raise exception 'CONTRATO 7: prompt analise_vendas_summit sumiu'; end if;
  if v_versao < 2 or not v_ativo then
    raise exception 'CONTRATO 7: prompt devia estar ativo na v2+, veio versao=% ativo=%', v_versao, v_ativo;
  end if;
  if position('"sensitivity"' in v_conteudo) = 0 then
    raise exception 'CONTRATO 7: o JSON de saida nao declara sensitivity';
  end if;
  if position('OBRIGATÓRIO EM TODO ITEM' in v_conteudo) = 0 then
    raise exception 'CONTRATO 7: falta a secao que explica sensitivity';
  end if;

  -- Toda chave ativa de bloqueio precisa estar nomeada no prompt: se o writer
  -- barra por ela, o analisador tem de saber emiti-la.
  for r in select chave from intelligence.memoria_bloqueios where ativo order by chave
  loop
    if position(r.chave in v_conteudo) = 0 then
      raise exception 'CONTRATO 7: a chave ativa % nao aparece no prompt', r.chave;
    end if;
  end loop;

  -- D1: `stopped` deixou de aceitar "a conversa acabou".
  if position('nunca é, sozinho, motivo para `stopped`' in v_conteudo) = 0 then
    raise exception 'CONTRATO 7: falta a regra do D1 sobre stopped';
  end if;
end
$c7$;


select 'todos os 7 contratos passaram' as resultado,
       7 as contratos_verificados,
       (select count(*) from intelligence.participante_memoria
         where participante_id = '15b00000-0000-4000-8000-000000000001') as memorias_gravadas_no_teste;

-- Nada do que este arquivo criou sobrevive a esta linha.
rollback;
