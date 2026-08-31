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
--      regra de open loop);
--   8. o gate vale para o analisador SOB CONTRATO e só para ele — outro
--      analisador não é barrado, mas também não ganha marcador;
--   9. o MARCADOR `valor.sensitivity = 'none'` é gravado no insert e ACRESCENTADO
--      na revalidação de mesmo texto, sem duplicar a linha;
--  10. substituição `ativa → ativa` de identidade, cargo e empresa funciona —
--      era o bug de ordem contra o índice parcial;
--  11. o SEGUNDO WRITER (`mindagent_chat_save_interests`) é fail closed antes de
--      `session_interests`, e o item aprovado sai com marcador.
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

  -- O MARCADOR entra junto: item aprovado sob o contrato v2 grava
  -- `valor.sensitivity = 'none'`. Sem isso o coletor nao expoe a linha.
  if not exists (
    select 1 from intelligence.participante_memoria
     where participante_id = '15b00000-0000-4000-8000-000000000001'
       and chave = 'cargo_atual' and valor->>'sensitivity' = 'none') then
    raise exception 'CONTRATO 3: item aprovado nao ganhou o marcador no valor';
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


-- --------------- CONTRATO 8 - O GATE VALE PARA O ANALISADOR SOB CONTRATO
-- Hoje o contrato v2 e de `analise_vendas_summit`, e so dele. Outro analisador
-- nao e barrado (nao teria como cumprir um contrato que ainda nao tem), mas
-- tambem NAO GANHA MARCADOR — entao o que ele grava continua invisivel para o
-- coletor. E esse o resultado seguro: o gate nao vira regra global calada, e
-- ainda assim nada sem contrato chega ao Agent.
do $c8$
declare v_n integer; v_marcador text;
begin
  v_n := public.analise_projetar_memoria(
    '15b00000-0000-4000-8000-000000000001', 'analise_concierge',
    jsonb_build_array(jsonb_build_object('category','interest','value','quer saber de credenciamento',
                       'scope','opportunity','confidence','high')), null);
  if v_n <> 1 then
    raise exception 'CONTRATO 8: analisador fora do contrato devia gravar, veio %', v_n;
  end if;

  select valor->>'sensitivity' into v_marcador from intelligence.participante_memoria
   where participante_id = '15b00000-0000-4000-8000-000000000001'
     and origem = 'analise_concierge';
  if v_marcador is not null then
    raise exception 'CONTRATO 8: analisador fora do contrato NAO pode marcar, veio %', v_marcador;
  end if;

  -- O mesmo item, sob o analisador do contrato, e barrado.
  v_n := public.analise_projetar_memoria(
    '15b00000-0000-4000-8000-000000000001', 'analise_vendas_summit',
    jsonb_build_array(jsonb_build_object('category','interest','value','outro assunto qualquer',
                       'scope','opportunity','confidence','high')), null);
  if v_n <> 0 then
    raise exception 'CONTRATO 8: sob contrato, item sem rotulo devia ser barrado, veio %', v_n;
  end if;
end
$c8$;


-- -------- CONTRATO 9 - REVALIDACAO DE LEGADO: MARCA SEM DUPLICAR (caso "b")
-- Uma linha gravada sob o contrato v1 nao tem marcador. Quando o MESMO texto
-- volta a ser emitido sob o v2 com `none`, a linha existente ganha o marcador
-- em vez de nascer uma segunda. E assim que o legado se torna visivel sem ser
-- reescrito nem apagado.
do $c9$
declare v_id uuid; v_n integer; r record;
begin
  insert into intelligence.participante_memoria
    (participante_id, tipo, chave, valor, confianca, origem, status)
  -- A `chave` tem de ser exatamente a que a funcao deriva do texto
  -- (`tipo || ':' || mind_slug(texto)`), senao nao ha o que revalidar.
  values ('15b00000-0000-4000-8000-000000000001', 'preferencia',
          'preferencia:' || public.mind_slug('prefere sessoes de manha'),
          jsonb_build_object('text','prefere sessoes de manha','scope','stable'),
          0.70, 'analise_vendas_summit', 'proposta')
  returning id into v_id;

  if (select valor ? 'sensitivity' from intelligence.participante_memoria where id = v_id) then
    raise exception 'CONTRATO 9: a fixture v1 nao devia nascer marcada';
  end if;

  v_n := public.analise_projetar_memoria(
    '15b00000-0000-4000-8000-000000000001', 'analise_vendas_summit',
    jsonb_build_array(jsonb_build_object('category','preference','value','prefere sessoes de manha',
                       'scope','stable','confidence','high','sensitivity','none')), null);

  -- Revalidacao nao e insercao: nada novo foi gravado.
  if v_n <> 0 then
    raise exception 'CONTRATO 9: revalidacao devia atualizar, nao inserir (veio %)', v_n;
  end if;

  select count(*) as n,
         count(*) filter (where valor->>'sensitivity' = 'none') as marcadas,
         min(valor->>'text') as txt
    into r
    from intelligence.participante_memoria
   where participante_id = '15b00000-0000-4000-8000-000000000001'
     and chave = 'preferencia:' || public.mind_slug('prefere sessoes de manha');

  if r.n <> 1 then
    raise exception 'CONTRATO 9: revalidacao duplicou a linha (% linhas)', r.n;
  end if;
  if r.marcadas <> 1 then
    raise exception 'CONTRATO 9: a linha revalidada nao ganhou o marcador';
  end if;
  if r.txt <> 'prefere sessoes de manha' then
    raise exception 'CONTRATO 9: a revalidacao reescreveu o texto: %', r.txt;
  end if;
end
$c9$;


-- ------------- CONTRATO 10 - SUBSTITUICAO `ativa -> ativa` (o bug da §16.8)
-- As tres chaves canonicas, uma a uma. Antes da correcao da ordem, o insert
-- colidia com o indice parcial e o item sumia sem erro.
do $c10$
declare
  v_pessoa constant uuid := '15b00000-0000-4000-8000-000000000002';
  r record; v_n integer; v_cat text; v_chave text;
begin
  insert into pessoas.pessoas (id, primeiro_nome, origem) values (v_pessoa, 'Troca', 'manual');

  for v_cat, v_chave in
    select * from (values ('identity','identidade'), ('role','cargo_atual'), ('company','empresa_atual')) t(c,k)
  loop
    -- primeira versao: entra como `ativa` (stable + high)
    v_n := public.analise_projetar_memoria(v_pessoa, 'analise_vendas_summit',
      jsonb_build_array(jsonb_build_object('category', v_cat, 'value', 'primeira versao de ' || v_chave,
        'scope','stable','confidence','high','sensitivity','none')), null);
    if v_n <> 1 then raise exception 'CONTRATO 10: % nao gravou a primeira versao', v_chave; end if;

    -- segunda versao, tambem `ativa`: e exatamente o caso que se perdia
    v_n := public.analise_projetar_memoria(v_pessoa, 'analise_vendas_summit',
      jsonb_build_array(jsonb_build_object('category', v_cat, 'value', 'segunda versao de ' || v_chave,
        'scope','stable','confidence','high','sensitivity','none')), null);
    if v_n <> 1 then
      raise exception 'CONTRATO 10: % perdeu a troca ativa->ativa (veio %)', v_chave, v_n;
    end if;

    select count(*) filter (where status = 'ativa')        as ativas,
           count(*) filter (where status = 'substituida')  as subs,
           count(*) filter (where status = 'substituida' and substituida_por is not null) as ligadas,
           max(valor->>'text') filter (where status = 'ativa') as texto_vivo
      into r
      from intelligence.participante_memoria
     where participante_id = v_pessoa and chave = v_chave;

    if r.ativas <> 1 or r.subs <> 1 or r.ligadas <> 1 then
      raise exception 'CONTRATO 10: % ficou com ativas=%, substituidas=%, ligadas=%',
        v_chave, r.ativas, r.subs, r.ligadas;
    end if;
    if r.texto_vivo <> 'segunda versao de ' || v_chave then
      raise exception 'CONTRATO 10: % manteve a versao errada viva: %', v_chave, r.texto_vivo;
    end if;
  end loop;
end
$c10$;


-- ------------------ CONTRATO 11 - O SEGUNDO WRITER TAMBEM E FAIL CLOSED
-- `mindagent_chat_save_interests` grava em `engagement.session_interests` antes
-- de qualquer promocao — inclusive em sessao sem participante. Por isso o gate
-- roda ANTES dela: proteger so a promocao deixaria o dado sensivel gravado no
-- primeiro salto.
do $c11$
declare
  v_disp    constant uuid := '15b00000-0000-4000-8000-0000000000d1';
  v_sessao  constant uuid := '15b00000-0000-4000-8000-0000000000e1';
  v_token   constant text := 'hash-de-teste-lane-d';
  v_auth    uuid;
  v_out jsonb; r record;
begin
  -- `agent_sessions.auth_user_id` tem FK para `auth.users`, entao a sessao de
  -- teste toma emprestado um usuario que ja existe. E LEITURA: nada em
  -- auth.users e criado, alterado ou removido, e a sessao criada aqui morre no
  -- rollback junto com o resto.
  select u.id into v_auth from auth.users u order by u.id limit 1;
  if v_auth is null then
    raise exception 'PRE-CONDICAO: nao ha usuario em auth.users para ancorar a sessao de teste';
  end if;

  insert into engagement.dispositivos (id, chave) values (v_disp, 'dispositivo-teste-lane-d');
  insert into engagement.agent_sessions
    (id, dispositivo_id, participante_id, token_hash, origem_identidade, expira_em, auth_user_id)
  values (v_sessao, v_disp, '15b00000-0000-4000-8000-000000000001', v_token,
          'teste', now() + interval '1 hour', v_auth);

  -- (i) sem rotulo: nada e gravado, nem em session_interests
  v_out := public.mindagent_chat_save_interests(v_auth, v_sessao, v_token,
    jsonb_build_array(jsonb_build_object('key','burnout','label','burnout','confidence',0.95,'confirmed','true')));
  if (v_out->>'blocked')::int <> 1 or (v_out->>'saved')::int <> 0 or (v_out->>'promoted')::int <> 0 then
    raise exception 'CONTRATO 11: item sem rotulo devia ser bloqueado, veio %', v_out;
  end if;

  -- (ii) chave de bloqueio: idem
  v_out := public.mindagent_chat_save_interests(v_auth, v_sessao, v_token,
    jsonb_build_array(jsonb_build_object('key','afastamento','label','afastada por burnout',
      'confidence',0.95,'confirmed','true','sensitivity','saude_do_titular')));
  if (v_out->>'blocked')::int <> 1 or (v_out->>'saved')::int <> 0 then
    raise exception 'CONTRATO 11: chave de bloqueio devia ser barrada, veio %', v_out;
  end if;

  if exists (select 1 from engagement.session_interests where agent_session_id = v_sessao) then
    raise exception 'CONTRATO 11: item barrado vazou para session_interests';
  end if;

  -- (iii) `none` confirmado: grava, promove e SAI MARCADO (caso "d" do legado)
  v_out := public.mindagent_chat_save_interests(v_auth, v_sessao, v_token,
    jsonb_build_array(jsonb_build_object('key','lideranca','label','lideranca de equipes',
      'confidence',0.95,'confirmed','true','sensitivity','none')));
  if (v_out->>'saved')::int <> 1 or (v_out->>'promoted')::int <> 1 or (v_out->>'blocked')::int <> 0 then
    raise exception 'CONTRATO 11: item none devia gravar e promover, veio %', v_out;
  end if;

  if not exists (select 1 from engagement.session_interests
                  where agent_session_id = v_sessao and chave = 'lideranca') then
    raise exception 'CONTRATO 11: item aprovado nao chegou em session_interests';
  end if;

  select valor->>'sensitivity' as marcador, status into r
    from intelligence.participante_memoria
   where participante_id = '15b00000-0000-4000-8000-000000000001'
     and chave = 'lideranca' and origem = 'confirmado_pelo_usuario';
  if not found or r.marcador is distinct from 'none' then
    raise exception 'CONTRATO 11: memoria da web saiu sem marcador (%)', r;
  end if;

  if not exists (
    select 1 from intelligence.participante_contexto pc,
                  jsonb_array_elements(pc.temas_relevantes) t
     where pc.participante_id = '15b00000-0000-4000-8000-000000000001'
       and t->>'key' = 'lideranca' and t->>'sensitivity' = 'none') then
    raise exception 'CONTRATO 11: o item de perfil saiu sem marcador';
  end if;
end
$c11$;


select 'todos os 11 contratos passaram' as resultado,
       11 as contratos_verificados,
       (select count(*) from intelligence.participante_memoria
         where participante_id = '15b00000-0000-4000-8000-000000000001') as memorias_gravadas_no_teste;

-- Nada do que este arquivo criou sobrevive a esta linha.
rollback;
