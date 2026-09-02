-- ============================================================================
-- CONTRATO DE public.mind_memoria_fatos(p_pessoa_id uuid) -> jsonb
--
-- Passo 15. Este arquivo e TESTE, nao SQL de producao. Ele nao cria extensao,
-- schema, tabela, funcao permanente, migration nem CI: e autocontido e roda
-- inteiro dentro de uma transacao que termina em ROLLBACK. Depois dele, zero
-- fixture permanece e nada no banco muda.
--
-- Testa o CONTRATO OBSERVAVEL da leitura de memoria. Nao reimplementa o
-- coletor para comparar duas copias da mesma logica: as fixtures cobrem cada
-- regra congelada e o teste afirma o que sai.
--
-- Qualquer contrato quebrado aborta com uma exception que diz qual.
--
-- Como rodar:  psql "$DATABASE_URL" -f tests/mind_memoria_fatos_contract.sql
-- ============================================================================

begin;

-- ---------------------------------------------------------------- FIXTURES
-- UUIDs proprios do teste, no prefixo 15000000-. Nenhum id de producao.
--
-- Uma pessoa com as SEIS situacoes que o contrato precisa distinguir:
--   1 ativa    (forma {text,scope} — writer analise_projetar_memoria)
--   1 ativa    (forma {label,confirmed} — writer mindagent_chat_save_interests,
--              o caso "web segura sai")
--   2 proposta (uma delas com valido_ate no FUTURO: continua viva)
--   1 proposta EXPIRADA  -> nao sai, vira contagem
--   1 substituida        -> nao sai, vira contagem
--   1 LEGADO v1 sem marcador -> viva e nao expirada, e ainda assim NAO SAI
-- E uma segunda pessoa SEM memoria nenhuma, para provar as listas vazias.

insert into pessoas.pessoas (id, primeiro_nome, sobrenome, empresa, cargo, origem)
values ('15000000-0000-4000-8000-000000000001',
        'Pessoa', 'Memoria', 'Empresa Teste', 'Cargo Teste', 'manual'),
       ('15000000-0000-4000-8000-000000000002',
        'Pessoa', 'SemMemoria', null, null, 'manual');

-- Uma conversa da pessoa 1, so para o CONTRATO 8 provar que o AGENT_CONTEXT do
-- Passo 8 continua com o mesmo conjunto exato de chaves depois desta migration.
insert into engagement.conversas
  (id, participante_id, canal, agente, iniciada_em, ultima_atividade)
values ('15000000-0000-4000-8000-0000000000e1',
        '15000000-0000-4000-8000-000000000001',
        'whatsapp', 'treble-inbound-agent', now() - interval '1 hour', now() - interval '1 hour');

insert into intelligence.participante_memoria
  (id, participante_id, tipo, chave, valor, confianca, origem, status, valido_ate, importancia)
values
  -- ATIVA, forma do analisador
  ('15000000-0000-4000-8000-0000000000a1',
   '15000000-0000-4000-8000-000000000001', 'cargo', 'cargo_atual',
   jsonb_build_object('text', 'diretora de RH', 'scope', 'stable', 'sensitivity', 'none'),
   0.90, 'analise_vendas_summit', 'ativa', null, 0.80),

  -- ATIVA, forma da superficie de chat: tem label, NAO tem text nem scope
  ('15000000-0000-4000-8000-0000000000a2',
   '15000000-0000-4000-8000-000000000001', 'interesse', 'burnout',
   jsonb_build_object('label', 'burnout', 'confirmed', true, 'sensitivity', 'none'),
   0.95, 'confirmado_pelo_usuario', 'ativa', null, 0.95),

  -- PROPOSTA sem prazo
  ('15000000-0000-4000-8000-0000000000b1',
   '15000000-0000-4000-8000-000000000001', 'objetivo', 'objetivo:levar_o_time',
   jsonb_build_object('text', 'quer levar o time', 'scope', 'opportunity', 'sensitivity', 'none'),
   0.70, 'analise_vendas_summit', 'proposta', null, 0.50),

  -- PROPOSTA com prazo ainda no futuro: continua viva
  ('15000000-0000-4000-8000-0000000000b2',
   '15000000-0000-4000-8000-000000000001', 'outro', 'outro:com_pressa',
   jsonb_build_object('text', 'com pressa hoje', 'scope', 'moment', 'sensitivity', 'none'),
   0.60, 'analise_vendas_summit', 'proposta', now() + interval '1 day', 0.30),

  -- PROPOSTA EXPIRADA: prazo no passado
  ('15000000-0000-4000-8000-0000000000c1',
   '15000000-0000-4000-8000-000000000001', 'outro', 'outro:estado_de_ontem',
   jsonb_build_object('text', 'estado de ontem', 'scope', 'moment', 'sensitivity', 'none'),
   0.60, 'analise_vendas_summit', 'proposta', now() - interval '1 day', 0.30),

  -- SUBSTITUIDA: historico
  ('15000000-0000-4000-8000-0000000000d1',
   '15000000-0000-4000-8000-000000000001', 'empresa', 'empresa_antiga',
   jsonb_build_object('text', 'empresa antiga', 'scope', 'stable', 'sensitivity', 'none'),
   0.90, 'analise_vendas_summit', 'substituida', null, 0.50),

  -- LEGADO v1: gravada antes do contrato v2, sem marcador. Viva, nao expirada,
  -- nao substituida — e ainda assim NAO PODE SAIR. E o caso (a) da revalidacao.
  ('15000000-0000-4000-8000-0000000000e2',
   '15000000-0000-4000-8000-000000000001', 'interesse', 'interesse:legado_v1',
   jsonb_build_object('text', 'memoria gravada sob o contrato v1', 'scope', 'stable'),
   0.90, 'analise_vendas_summit', 'ativa', null, 0.50);


-- ------------------------------------------------- CONTRATO 1 - TAXONOMIA DE ERRO
do $c1$
declare
  v_nulo  jsonb := public.mind_memoria_fatos(null);
  v_fanta jsonb := public.mind_memoria_fatos('15000000-0000-4000-8000-0000000000ff');
begin
  if (v_nulo->>'ok')::boolean is distinct from false
     or v_nulo->>'motivo' <> 'sem_pessoa' then
    raise exception 'CONTRATO 1: pessoa nula devia dar ok=false/sem_pessoa, veio %', v_nulo;
  end if;
  if (v_fanta->>'ok')::boolean is distinct from false
     or v_fanta->>'motivo' <> 'pessoa_nao_encontrada' then
    raise exception 'CONTRATO 1: pessoa inexistente devia dar pessoa_nao_encontrada, veio %', v_fanta;
  end if;
  if v_fanta->>'pessoa_id' is null then
    raise exception 'CONTRATO 1: o erro de pessoa inexistente devia ecoar o pessoa_id, veio %', v_fanta;
  end if;
end
$c1$;


-- ---------------------------------------------------- CONTRATO 2 - CHAVES DO TOPO
do $c2$
declare
  v          jsonb := public.mind_memoria_fatos('15000000-0000-4000-8000-000000000001');
  v_chaves   text[];
  v_esperado constant text[] := array['memorias','meta','ok','pessoa_id','propostas'];
begin
  select array_agg(k order by k) into v_chaves from jsonb_object_keys(v) k;
  if v_chaves <> v_esperado then
    raise exception 'CONTRATO 2: chaves do topo sao %, esperado %', v_chaves, v_esperado;
  end if;
end
$c2$;


-- ------------------------- CONTRATO 3 - ATIVA E PROPOSTA NUNCA SE MISTURAM
-- A regra que impede inferencia fraca de virar fato: as duas listas sao
-- disjuntas e cada uma carrega exatamente o seu status.
do $c3$
declare
  v jsonb := public.mind_memoria_fatos('15000000-0000-4000-8000-000000000001');
begin
  if jsonb_array_length(v->'memorias') <> 2 then
    raise exception 'CONTRATO 3: memorias devia ter as 2 ativas, tem %',
      jsonb_array_length(v->'memorias');
  end if;
  if jsonb_array_length(v->'propostas') <> 2 then
    raise exception 'CONTRATO 3: propostas devia ter as 2 propostas vivas, tem %',
      jsonb_array_length(v->'propostas');
  end if;

  -- nenhuma chave aparece nas duas listas
  if exists (
    select 1
      from jsonb_array_elements(v->'memorias')  m,
           jsonb_array_elements(v->'propostas') p
     where m->>'chave' = p->>'chave') then
    raise exception 'CONTRATO 3: a mesma chave saiu em memorias e em propostas';
  end if;

  -- a proposta com prazo no futuro esta viva
  if not exists (select 1 from jsonb_array_elements(v->'propostas') p
                  where p->>'chave' = 'outro:com_pressa') then
    raise exception 'CONTRATO 3: proposta com valido_ate no futuro devia estar viva';
  end if;
end
$c3$;


-- ------------------- CONTRATO 4 - EXPIRADA E SUBSTITUIDA NAO SAEM, MAS CONTAM
do $c4$
declare
  v jsonb := public.mind_memoria_fatos('15000000-0000-4000-8000-000000000001');
begin
  if exists (select 1 from jsonb_array_elements(v->'memorias' || v->'propostas') x
              where x->>'chave' in ('outro:estado_de_ontem','empresa_antiga')) then
    raise exception 'CONTRATO 4: memoria expirada ou substituida vazou para o payload';
  end if;
  if (v->'meta'->>'expiradas_ignoradas')::int <> 1 then
    raise exception 'CONTRATO 4: expiradas_ignoradas devia ser 1, veio %',
      v->'meta'->>'expiradas_ignoradas';
  end if;
  if (v->'meta'->>'substituidas_ignoradas')::int <> 1 then
    raise exception 'CONTRATO 4: substituidas_ignoradas devia ser 1, veio %',
      v->'meta'->>'substituidas_ignoradas';
  end if;
  if (v->'meta'->>'ativas')::int <> 2 or (v->'meta'->>'propostas')::int <> 2 then
    raise exception 'CONTRATO 4: meta nao bate com as listas: %', v->'meta';
  end if;

  -- LEGADO SEM MARCADOR: existe, esta viva, e nao sai. A ausencia e contada.
  if exists (select 1 from jsonb_array_elements(v->'memorias' || v->'propostas') x
              where x->>'chave' = 'interesse:legado_v1') then
    raise exception 'CONTRATO 4: memoria v1 SEM MARCADOR vazou para o payload';
  end if;
  if (v->'meta'->>'sem_marcador_ignoradas')::int <> 1 then
    raise exception 'CONTRATO 4: sem_marcador_ignoradas devia ser 1, veio %',
      v->'meta'->>'sem_marcador_ignoradas';
  end if;
end
$c4$;


-- ------------------ CONTRATO 5 - AS DUAS FORMAS DE `valor`, SEM TERCEIRA
-- texto = coalesce(text, label). `valor` sai cru. `escopo` fica NULO quando o
-- writer nao gravou escopo: o coletor nao completa o que nao foi gravado.
do $c5$
declare
  v         jsonb := public.mind_memoria_fatos('15000000-0000-4000-8000-000000000001');
  v_analise jsonb;
  v_chat    jsonb;
  v_chaves  text[];
  v_esperado constant text[] := array[
    'analise_conversa_id','atualizada_em','chave','confianca','escopo',
    'evidencia_message_id','importancia','origem','registrada_em','texto',
    'tipo','valido_ate','valor'];
begin
  select x into v_analise from jsonb_array_elements(v->'memorias') x where x->>'chave' = 'cargo_atual';
  select x into v_chat    from jsonb_array_elements(v->'memorias') x where x->>'chave' = 'burnout';

  if v_analise->>'texto' <> 'diretora de RH' or v_analise->>'escopo' <> 'stable' then
    raise exception 'CONTRATO 5: forma {text,scope} nao foi lida, veio %', v_analise;
  end if;
  if v_chat->>'texto' <> 'burnout' then
    raise exception 'CONTRATO 5: forma {label,confirmed} devia dar texto=label, veio %', v_chat;
  end if;
  if v_chat->>'escopo' is not null then
    raise exception 'CONTRATO 5: escopo devia ser nulo quando o writer nao grava scope, veio %',
      v_chat->>'escopo';
  end if;
  -- `valor` sai CRU, com o marcador incluso: e ele que autorizou a linha a sair.
  if v_chat->'valor' <> jsonb_build_object('label','burnout','confirmed',true,'sensitivity','none') then
    raise exception 'CONTRATO 5: valor devia sair cru (com o marcador), veio %', v_chat->'valor';
  end if;

  select array_agg(k order by k) into v_chaves from jsonb_object_keys(v_analise) k;
  if v_chaves <> v_esperado then
    raise exception 'CONTRATO 5: chaves do item sao %, esperado %', v_chaves, v_esperado;
  end if;
end
$c5$;


-- ------------------------------ CONTRATO 6 - PESSOA SEM MEMORIA NAO E ERRO
do $c6$
declare
  v jsonb := public.mind_memoria_fatos('15000000-0000-4000-8000-000000000002');
begin
  if (v->>'ok')::boolean is not true then
    raise exception 'CONTRATO 6: pessoa sem memoria devia dar ok=true, veio %', v;
  end if;
  if v->'memorias' <> '[]'::jsonb or v->'propostas' <> '[]'::jsonb then
    raise exception 'CONTRATO 6: listas deviam vir vazias, veio % / %',
      v->'memorias', v->'propostas';
  end if;
  if (v->'meta'->>'ativas')::int <> 0 or (v->'meta'->>'propostas')::int <> 0
     or (v->'meta'->>'sem_marcador_ignoradas')::int <> 0
     or v->'meta'->'origens' <> '[]'::jsonb
     or v->'meta'->>'ultima_atualizacao' is not null then
    raise exception 'CONTRATO 6: meta de pessoa vazia esta errada: %', v->'meta';
  end if;
end
$c6$;


-- ------------------------ CONTRATO 7 - ORDEM DETERMINISTICA (tipo, chave)
do $c7$
declare
  v      jsonb := public.mind_memoria_fatos('15000000-0000-4000-8000-000000000001');
  v_ord  text[];
begin
  select array_agg((x->>'tipo') || '|' || (x->>'chave') order by t.ord)
    into v_ord
    from jsonb_array_elements(v->'memorias') with ordinality t(x, ord);

  if v_ord <> array['cargo|cargo_atual','interesse|burnout'] then
    raise exception 'CONTRATO 7: memorias fora da ordem (tipo, chave): %', v_ord;
  end if;
end
$c7$;


-- ---------------- CONTRATO 8 - O COLETOR NAO ESCREVE E NAO TOCA O PASSO 8
do $c8$
declare
  v_antes  bigint;
  v_depois bigint;
  v_ctx    jsonb;
  v_chaves text[];
  v_esperado_ctx constant text[] := array[
    'commercial','conversa_id','conversation','crm','engagement','entry','ok','person','pessoa_id'];
begin
  select count(*) into v_antes from intelligence.participante_memoria;
  perform public.mind_memoria_fatos('15000000-0000-4000-8000-000000000001');
  select count(*) into v_depois from intelligence.participante_memoria;
  if v_antes <> v_depois then
    raise exception 'CONTRATO 8: o coletor escreveu na memoria (% -> %)', v_antes, v_depois;
  end if;

  -- O AGENT_CONTEXT do Passo 8 continua com o mesmo conjunto exato de chaves:
  -- esta migration nao liga a memoria no caminho sincrono.
  v_ctx := public.mind_agent_context('15000000-0000-4000-8000-0000000000ee');
  if (v_ctx->>'ok')::boolean is not false then
    raise exception 'CONTRATO 8: fixture de conversa inexistente devia dar ok=false';
  end if;
  select array_agg(k order by k) into v_chaves
    from jsonb_object_keys(
           public.mind_agent_context('15000000-0000-4000-8000-0000000000e1')) k;
  if v_chaves <> v_esperado_ctx then
    raise exception 'CONTRATO 8: mind_agent_context mudou de chaves: %', v_chaves;
  end if;
end
$c8$;


-- ------------------------------------- CONTRATO 9 - SEGURANCA DA FUNCAO
do $c9$
declare
  r      record;
  v_exec text[];
begin
  select p.prosecdef, p.proconfig, p.proacl, p.provolatile
    into r
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'mind_memoria_fatos';

  if not found then
    raise exception 'CONTRATO 9: public.mind_memoria_fatos nao existe';
  end if;
  if not r.prosecdef then
    raise exception 'CONTRATO 9: a funcao devia ser SECURITY DEFINER';
  end if;
  if r.provolatile <> 's' then
    raise exception 'CONTRATO 9: a funcao devia ser STABLE, e %', r.provolatile;
  end if;
  if r.proconfig is null or not exists (select 1 from unnest(r.proconfig) c where c like 'search_path=%') then
    raise exception 'CONTRATO 9: a funcao devia ter search_path explicito, tem %', r.proconfig;
  end if;

  select array_agg(distinct a.grantee::regrole::text order by a.grantee::regrole::text)
    into v_exec
    from aclexplode(r.proacl) a
   where a.privilege_type = 'EXECUTE';

  if v_exec is null then
    raise exception 'CONTRATO 9: sem ACL — EXECUTE estaria aberto a todos';
  end if;
  if not ('service_role' = any(v_exec)) then
    raise exception 'CONTRATO 9: service_role devia poder executar, ACL = %', v_exec;
  end if;
  if 'public' = any(v_exec) or 'anon' = any(v_exec) or 'authenticated' = any(v_exec) then
    raise exception 'CONTRATO 9: EXECUTE nao pode estar liberado para public/anon/authenticated, ACL = %', v_exec;
  end if;
end
$c9$;


select 'todos os 9 contratos passaram' as resultado,
       9 as contratos_verificados,
       (select count(*) from intelligence.participante_memoria
         where participante_id::text like '15000000-0000-4000-8000-%') as fixtures_na_transacao;

-- Nada do que este arquivo criou sobrevive a esta linha.
rollback;
