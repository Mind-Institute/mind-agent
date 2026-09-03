-- ============================================================================
-- CONTRATO DO PÓS-TURNO — fila por recência, ICP medium no slot vazio,
-- classificador v3.
--
-- Este arquivo é TESTE, não SQL de produção. Roda inteiro dentro de uma
-- transação que termina em ROLLBACK: nenhuma fixture permanece e nada no banco
-- muda. Fixtures usam o prefixo 09030000-. Nenhum id de produção.
--
-- Testa o CONTRATO OBSERVÁVEL das migrations de 03/09:
--   20260903060000_fila_do_pos_turno_por_recencia.sql
--   20260903061000_icp_medium_ocupa_slot_vazio.sql
--   20260903063000_classificador_v3_conhece_a_pessoa.sql
--
-- Qualquer contrato quebrado aborta com uma exception que diz qual.
--
-- Como rodar:  psql "$DATABASE_URL" -f tests/pos_turno_fila_e_icp_contract.sql
-- ============================================================================

begin;

-- ---------------------------------------------------------------- FIXTURES
insert into pessoas.pessoas (id, primeiro_nome, sobrenome, empresa, cargo, origem)
values ('09030000-0000-4000-8000-000000000001',
        'Pessoa', 'PosTurno', 'Empresa Teste', 'HRBP', 'manual');

-- A: substantiva, mais ANTIGA. B: substantiva, mais RECENTE. C: o lead só mandou
-- mídia (conteudo null). D: já analisada até a última mensagem.
insert into engagement.conversas (id, participante_id, canal, agente, iniciada_em, ultima_atividade)
values
 ('09030000-0000-4000-8000-0000000000a1','09030000-0000-4000-8000-000000000001',
  'mindagent-web','mindagent-chat', now() - interval '1 hour', now() - interval '1 hour'),
 ('09030000-0000-4000-8000-0000000000b1','09030000-0000-4000-8000-000000000001',
  'mindagent-web','mindagent-chat', now() - interval '1 minute', now() - interval '1 minute'),
 ('09030000-0000-4000-8000-0000000000c1','09030000-0000-4000-8000-000000000001',
  'whatsapp','treble', now(), now()),
 ('09030000-0000-4000-8000-0000000000d1','09030000-0000-4000-8000-000000000001',
  'whatsapp','treble', now() - interval '2 hours', now() - interval '2 hours');

insert into engagement.mensagens (id, conversa_id, participante_id, papel, conteudo, origem, criado_em)
values
 ('09030000-0000-4000-8000-0000000000e1','09030000-0000-4000-8000-0000000000a1',
  '09030000-0000-4000-8000-000000000001','lead','Sou HRBP e preciso desenvolver os gestores que apoio.','conversa', now() - interval '1 hour'),
 ('09030000-0000-4000-8000-0000000000e2','09030000-0000-4000-8000-0000000000b1',
  '09030000-0000-4000-8000-000000000001','lead','Quero muito ver a Amy Edmondson.','conversa', now() - interval '1 minute'),
 ('09030000-0000-4000-8000-0000000000e3','09030000-0000-4000-8000-0000000000c1',
  '09030000-0000-4000-8000-000000000001','lead', null,'treble', now()),
 ('09030000-0000-4000-8000-0000000000e4','09030000-0000-4000-8000-0000000000d1',
  '09030000-0000-4000-8000-000000000001','lead','Quanto custa o ingresso?','treble', now() - interval '2 hours');

insert into intelligence.analise_conversa
  (id, conversa_id, participante_id, analisador, funcao, dados, prompt_versao,
   ultima_mensagem_analisada_id, conversa_atualizada_ate)
values
 ('09030000-0000-4000-8000-0000000000f4','09030000-0000-4000-8000-0000000000d1',
  '09030000-0000-4000-8000-000000000001','analise_vendas_summit','comercial','{}'::jsonb,1,
  '09030000-0000-4000-8000-0000000000e4', now() - interval '2 hours'),
 ('09030000-0000-4000-8000-0000000000f1','09030000-0000-4000-8000-0000000000a1',
  '09030000-0000-4000-8000-000000000001','analise_concierge','concierge','{}'::jsonb,6,
  null, null);


-- ------------------------------------------------ CONTRATO 1 - FILA POR RECÊNCIA
do $c1$
declare
  c_antiga  constant uuid := '09030000-0000-4000-8000-0000000000a1';
  c_recente constant uuid := '09030000-0000-4000-8000-0000000000b1';
  c_so_midia constant uuid := '09030000-0000-4000-8000-0000000000c1';
  c_feita   constant uuid := '09030000-0000-4000-8000-0000000000d1';
  pos_antiga bigint; pos_recente bigint; n_midia int; n_feita int;
begin
  create temp table fila on commit drop as
    select conversa_id, row_number() over () as pos from public.analise_pendentes(1000000);

  select pos into pos_antiga  from fila where conversa_id = c_antiga;
  select pos into pos_recente from fila where conversa_id = c_recente;
  select count(*) into n_midia from fila where conversa_id = c_so_midia;
  select count(*) into n_feita from fila where conversa_id = c_feita;

  if pos_antiga is null or pos_recente is null then
    raise exception 'CONTRATO 1: as duas conversas substantivas deviam estar na fila (antiga=%, recente=%)', pos_antiga, pos_recente;
  end if;
  if pos_recente >= pos_antiga then
    raise exception 'CONTRATO 1: a conversa mais recente devia vir antes (recente=%, antiga=%)', pos_recente, pos_antiga;
  end if;
  if n_midia <> 0 then
    raise exception 'CONTRATO 1: conversa cujo lead só mandou mídia não pode entrar na fila';
  end if;
  if n_feita <> 0 then
    raise exception 'CONTRATO 1: conversa já analisada até a última mensagem não pode voltar à fila';
  end if;
end
$c1$;


-- ------------------------------------------- CONTRATO 2 - ICP MEDIUM NO SLOT VAZIO
do $c2$
declare
  p constant uuid := '09030000-0000-4000-8000-000000000001';
  a constant uuid := '09030000-0000-4000-8000-0000000000f1';
  ev constant uuid := '09030000-0000-4000-8000-0000000000e1';
  item jsonb; n int; r text;
begin
  item := jsonb_build_object('category','icp','value','People Leader / Business Partner',
    'confidence','medium','scope','stable','sensitivity','none','evidence_kind','role_inference',
    'memory_action','observe','evidence_message_id', ev::text);

  -- 2a. slot vazio: medium entra ativa, com a confiança 0,70 exposta.
  n := public.analise_projetar_memoria(p, 'analise_concierge', jsonb_build_array(item), a);
  select string_agg(status||':'||(valor->>'text')||':'||confianca, ' | ' order by status) into r
  from intelligence.participante_memoria where participante_id = p and chave = 'icp_atual';
  if n <> 1 or r is distinct from 'ativa:People Leader / Business Partner:0.70' then
    raise exception 'CONTRATO 2a: medium no slot vazio devia virar ativa 0.70, veio n=% r=%', n, r;
  end if;

  -- 2b. slot ocupado: outro medium NÃO derruba (regra do Passo 4 preservada).
  n := public.analise_projetar_memoria(p, 'analise_concierge',
         jsonb_build_array(item || jsonb_build_object('value','CEO / C-Suite')), a);
  select string_agg(status||':'||(valor->>'text'), ' | ' order by status) into r
  from intelligence.participante_memoria where participante_id = p and chave = 'icp_atual';
  if n <> 0 or r is distinct from 'ativa:People Leader / Business Partner' then
    raise exception 'CONTRATO 2b: medium não pode derrubar ICP ativo, veio n=% r=%', n, r;
  end if;

  -- 2c. high substitui, como antes.
  n := public.analise_projetar_memoria(p, 'analise_concierge',
         jsonb_build_array(item || jsonb_build_object('value','CHRO / VP de Pessoas','confidence','high')), a);
  select string_agg(status||':'||(valor->>'text'), ' | ' order by status) into r
  from intelligence.participante_memoria where participante_id = p and chave = 'icp_atual';
  if n <> 1 or r is distinct from 'ativa:CHRO / VP de Pessoas | substituida:People Leader / Business Partner' then
    raise exception 'CONTRATO 2c: high devia substituir o ativo, veio n=% r=%', n, r;
  end if;

  -- 2d. o leitor universal entrega o ICP ativo com a fonte e a confiança.
  select (public.mind_customer_intelligence(p)->'professional_context'->'icp')::text into r;
  if r not like '%CHRO / VP de Pessoas%' or r not like '%"source": "memory"%' then
    raise exception 'CONTRATO 2d: mind_customer_intelligence devia expor o ICP ativo, veio %', r;
  end if;
end
$c2$;


-- ------------------------------------------------ CONTRATO 3 - CLASSIFICADOR V3
do $c3$
declare v_versao int; v_txt text;
begin
  select versao, conteudo into v_versao, v_txt
  from agentes.prompts where chave = 'analise_classificador' and ativo;
  if v_versao < 3 then
    raise exception 'CONTRATO 3: analise_classificador devia estar na versão 3+, está na %', v_versao;
  end if;
  if v_txt not like '%quem ela é profissionalmente%'
     or v_txt not like '%cargo, função ou área que a própria pessoa declara%' then
    raise exception 'CONTRATO 3: o critério 5 devia incluir cargo/função/desafio profissional';
  end if;
  if v_txt like '%RH conversa sobre levar 30 gestores ao Summit e precisa conseguir aprovação do diretor.

OUTPUT:
["analise_vendas_summit"]%' then
    raise exception 'CONTRATO 3: o exemplo do RH com 30 gestores ainda aciona só vendas';
  end if;
end
$c3$;

rollback;
