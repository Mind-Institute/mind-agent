-- ============================================================================
-- CONTRATO DE public.mind_agent_context(p_conversa_id uuid) -> jsonb
--
-- Passo 9. Este arquivo e TESTE, nao SQL de producao. Ele nao cria extensao,
-- schema, tabela, funcao permanente, migration nem CI: e autocontido e roda
-- inteiro dentro de uma transacao que termina em ROLLBACK. Depois dele, zero
-- fixture permanece e nada no banco muda.
--
-- Testa o CONTRATO OBSERVAVEL. Nao reimplementa mind_agent_context para
-- comparar duas copias da mesma logica: quando precisa de referencia, compara
-- com as fontes canonicas ja fechadas (engagement.conversas e os cinco
-- coletores factuais).
--
-- Qualquer contrato quebrado aborta com uma exception que diz qual.
--
-- Como rodar:  psql "$DATABASE_URL" -f tests/mind_agent_context_contract.sql
-- ============================================================================

begin;

-- ---------------------------------------------------------------- FIXTURES
-- UUIDs proprios do teste, no prefixo 09000000-. Nenhum id de producao.
--
-- Os INSERTs entram em ordem A, B, C, mas os `iniciada_em` sao B(-5d), C(-3d),
-- A(-1d): a ordem factual e diferente da ordem de insercao, de proposito, para
-- provar que o contrato preserva a primeira e nao a segunda.

insert into engagement.origens (codigo, site, botao_rotulo, descricao, ativo)
values ('p9-origem-teste', 'outro', 'Botao de teste do Passo 9',
        'Origem sintetica criada dentro da transacao de teste.', true);

insert into pessoas.pessoas (id, primeiro_nome, sobrenome, empresa, cargo, origem)
values ('09000000-0000-4000-8000-000000000001',
        'Pessoa', 'Contrato', 'Empresa Teste', 'Cargo Teste', 'manual');

-- O espelho resolve o credenciamento pela identidade canônica antes de o coletor
-- ser chamado. Nome nunca é usado como identidade.
insert into engagement.identidades
  (pessoa_id, canal, identificador, verificado, confianca)
values
  ('09000000-0000-4000-8000-000000000001',
   'email', 'p9-credenciamento@example.test', true, 'alta');

insert into credenciamento_summit_2026.participantes
  (id, name, email, cellphone, telefone_norm, ticket_type, ticket_name,
   status, revogado_em, sincronizado_em)
values
  ('09000000-0000-4000-8000-0000000000e1', 'Pessoa Credenciada',
   'p9-credenciamento@example.test', '+55 11 98888-7777', '5511988887777',
   'VIP', 'VIP', 'ativo', null, now() - interval '2 minutes'),
  ('09000000-0000-4000-8000-0000000000e2', 'Pessoa Credenciada',
   'p9-credenciamento@example.test', '+55 11 98888-7777', '5511988887777',
   'VIP', 'VIP', 'ativo', null, now() - interval '1 minute'),
  ('09000000-0000-4000-8000-0000000000e3', 'Pessoa Credenciada',
   'p9-credenciamento@example.test', '+55 11 98888-7777', '5511988887777',
   'SEM MAPA', 'SEM MAPA', 'ativo', null, now()),
  ('09000000-0000-4000-8000-0000000000e4', 'Pessoa Credenciada',
   'p9-credenciamento@example.test', '+55 11 98888-7777', '5511988887777',
   'Mind', 'Mind', 'revogado', now(), now());

-- CONVERSA A -- a mais recente. variables em ARRAY. Carrega estado do agente
-- (audience, stage e as chaves de resultado) para provar que ele nao vaza.
insert into engagement.conversas
  (id, participante_id, canal, agente, origem_codigo, produto_codigo,
   iniciada_em, ultima_atividade, encerrada_em, audience, stage, variables)
values ('09000000-0000-4000-8000-0000000000a1',
        '09000000-0000-4000-8000-000000000001',
        'whatsapp', 'treble-inbound-agent', 'p9-origem-teste', 'produto-teste-p9',
        now() - interval '1 day', now() - interval '1 day', null,
        'b2c', 'qualificacao',
        jsonb_build_array(
          jsonb_build_object('key','hubspot_opcao_selecionada_treble','value','CTA ARRAY'),
          jsonb_build_object('key','intent','value','comprar'),
          jsonb_build_object('key','objection','value','preco'),
          jsonb_build_object('key','ticket_interest','value','vip'),
          jsonb_build_object('key','needs_human','value','false'),
          jsonb_build_object('key','checkout_sent','value','true'),
          jsonb_build_object('key','desfecho','value','lead_qualificado')));

-- CONVERSA B -- a mais antiga. variables em OBJECT com as DUAS chaves de CTA,
-- para travar a precedencia. Tem os 9 campos preenchidos.
insert into engagement.conversas
  (id, participante_id, canal, agente, origem_codigo, produto_codigo,
   iniciada_em, ultima_atividade, encerrada_em, audience, stage, variables)
values ('09000000-0000-4000-8000-0000000000b1',
        '09000000-0000-4000-8000-000000000001',
        'whatsapp', 'treble', 'p9-origem-teste', 'produto-teste-p9',
        now() - interval '5 days', now() - interval '5 days', now() - interval '5 days',
        'b2b', 'diagnostico',
        jsonb_build_object(
          'opcao_selecionada',                'CTA FALLBACK',
          'hubspot_opcao_selecionada_treble', 'CTA PRIORITARIA',
          'intent',        'duvida',
          'objection',     'tempo',
          'ticket_interest','prime',
          'needs_human',   true,
          'checkout_sent', false,
          'desfecho',      'abandono'));

-- CONVERSA C -- intermediaria e minima: sem origem, sem variables.
insert into engagement.conversas
  (id, participante_id, canal, agente, iniciada_em, ultima_atividade, encerrada_em)
values ('09000000-0000-4000-8000-0000000000c1',
        '09000000-0000-4000-8000-000000000001',
        'mindagent-web', 'mindagent-chat',
        now() - interval '3 days', now() - interval '3 days', now() - interval '3 days');

-- CONVERSA ORFA -- existe, mas sem pessoa. So para o contrato de erro.
insert into engagement.conversas (id, participante_id, canal, iniciada_em)
values ('09000000-0000-4000-8000-0000000000d1', null, 'whatsapp', now() - interval '2 days');

-- Mensagens, tambem fora da ordem de insercao. A mensagem do lead em A contem
-- de proposito as palavras "intent" e "objection": se a pessoa escreveu, isso
-- e historico factual e continua no transcrito. O contrato proibe essas chaves
-- na ESTRUTURA, nao essas palavras no texto.
insert into engagement.mensagens (conversa_id, participante_id, papel, conteudo, origem, criado_em)
values
 ('09000000-0000-4000-8000-0000000000a1','09000000-0000-4000-8000-000000000001',
  'agente','Resposta do agente na conversa A.','agente', now() - interval '1 day' + interval '2 min'),
 ('09000000-0000-4000-8000-0000000000a1','09000000-0000-4000-8000-000000000001',
  'lead','Meu intent e comprar e minha objection e preco.','treble', now() - interval '1 day' + interval '1 min'),
 ('09000000-0000-4000-8000-0000000000b1','09000000-0000-4000-8000-000000000001',
  'lead','Primeira mensagem da conversa B.','treble', now() - interval '5 days' + interval '1 min'),
 ('09000000-0000-4000-8000-0000000000b1','09000000-0000-4000-8000-000000000001',
  'agente','Resposta na conversa B.','agente', now() - interval '5 days' + interval '2 min'),
 ('09000000-0000-4000-8000-0000000000c1','09000000-0000-4000-8000-000000000001',
  'lead','Unica mensagem da conversa C.','conversa', now() - interval '3 days' + interval '1 min');


-- ------------------------------------------------------- CONTRATO 1 - ERROS
do $c1$
declare
  v jsonb;
  c_inexistente constant uuid := '09000000-0000-4000-8000-00000000dead';
  c_orfa        constant uuid := '09000000-0000-4000-8000-0000000000d1';
begin
  v := public.mind_agent_context(null);
  if v <> jsonb_build_object('ok', false, 'motivo', 'sem_conversa') then
    raise exception 'CONTRATO 1: p_conversa_id null devia devolver {ok:false,motivo:sem_conversa}, veio %', v;
  end if;

  v := public.mind_agent_context(c_inexistente);
  if (v->>'ok')::boolean is not false
     or v->>'motivo' <> 'conversa_nao_encontrada'
     or v->>'conversa_id' <> c_inexistente::text then
    raise exception 'CONTRATO 1: conversa inexistente devia devolver conversa_nao_encontrada com o id preservado, veio %', v;
  end if;

  v := public.mind_agent_context(c_orfa);
  if (v->>'ok')::boolean is not false
     or v->>'motivo' <> 'conversa_sem_pessoa'
     or v->>'conversa_id' <> c_orfa::text then
    raise exception 'CONTRATO 1: conversa sem participante_id devia devolver conversa_sem_pessoa com o id preservado, veio %', v;
  end if;
  -- Chegar aqui ja prova que nenhum dos tres lancou exception.
end
$c1$;


-- ----------------------------------------------------- CONTRATO 2 - ANCORA
do $c2$
declare
  c_atual  constant uuid := '09000000-0000-4000-8000-0000000000a1';
  v        jsonb := public.mind_agent_context(c_atual);
  v_espera uuid;
begin
  select participante_id into v_espera from engagement.conversas where id = c_atual;
  if (v->>'pessoa_id')::uuid is distinct from v_espera then
    raise exception 'CONTRATO 2: pessoa_id (%) devia ser o participante_id da conversa (%)',
      v->>'pessoa_id', v_espera;
  end if;
  if (v->>'conversa_id')::uuid is distinct from c_atual then
    raise exception 'CONTRATO 2: conversa_id devolvido (%) difere do pedido (%)', v->>'conversa_id', c_atual;
  end if;
end
$c2$;


-- --------------------------------------------- CONTRATO 3 - CHAVES DO TOPO
do $c3$
declare
  v         jsonb := public.mind_agent_context('09000000-0000-4000-8000-0000000000a1');
  v_chaves  text[];
  v_esperado constant text[] := array[
    'commercial','conversa_id','conversation','credenciamento','crm',
    'engagement','entry','ok','person','pessoa_id'];
begin
  select array_agg(k order by k) into v_chaves from jsonb_object_keys(v) k;
  if v_chaves <> v_esperado then
    raise exception 'CONTRATO 3: chaves do topo sao % , esperado %', v_chaves, v_esperado;
  end if;
end
$c3$;


-- ------------------------------------- CONTRATO 4 - COLETORES INTEGRAIS
do $c4$
declare
  c_atual constant uuid := '09000000-0000-4000-8000-0000000000a1';
  v       jsonb := public.mind_agent_context(c_atual);
  v_pid   uuid  := (v->>'pessoa_id')::uuid;
begin
  if v->'person' <> public.mind_pessoa_fatos(v_pid) then
    raise exception 'CONTRATO 4: context.person difere de mind_pessoa_fatos(%)', v_pid;
  end if;
  if v->'crm' <> public.mind_crm_fatos(v_pid) then
    raise exception 'CONTRATO 4: context.crm difere de mind_crm_fatos(%)', v_pid;
  end if;
  if v->'commercial' <> public.mind_crm_comercial(v_pid) then
    raise exception 'CONTRATO 4: context.commercial difere de mind_crm_comercial(%)', v_pid;
  end if;
  if v->'credenciamento' <> public.mind_credenciamento_fatos(v_pid) then
    raise exception 'CONTRATO 4: context.credenciamento difere de mind_credenciamento_fatos(%)', v_pid;
  end if;
end
$c4$;


-- ------------------------------------------- CONTRATO 5 - CONVERSATION
do $c5$
declare
  -- B tem os nove campos preenchidos; e nela que a igualdade de chaves e exata.
  c_atual constant uuid := '09000000-0000-4000-8000-0000000000b1';
  v       jsonb := public.mind_agent_context(c_atual);
  v_pid   uuid  := (v->>'pessoa_id')::uuid;
  v_do_coletor jsonb;
  v_chaves text[];
  v_esperado constant text[] := array[
    'agente','canal','conversa_id','encerrada_em','iniciada_em','mensagens',
    'origem_codigo','produto_codigo','ultima_atividade'];
begin
  select e into v_do_coletor
    from jsonb_array_elements(public.mind_engagement_fatos(v_pid)->'conversas') e
   where (e->>'conversa_id')::uuid = c_atual;

  if v_do_coletor is null then
    raise exception 'CONTRATO 5: a conversa % nao aparece em mind_engagement_fatos(%)', c_atual, v_pid;
  end if;
  if v->'conversation' <> v_do_coletor then
    raise exception 'CONTRATO 5: conversation nao e identica ao objeto do coletor. context=% coletor=%',
      v->'conversation', v_do_coletor;
  end if;

  select array_agg(k order by k) into v_chaves from jsonb_object_keys(v->'conversation') k;
  if v_chaves <> v_esperado then
    raise exception 'CONTRATO 5: conversation nao preserva a linguagem do coletor. chaves=% esperado=%',
      v_chaves, v_esperado;
  end if;
end
$c5$;


-- ------------------------------ CONTRATO 6 - PARTICAO LOSSLESS DO ENGAGEMENT
do $c6$
declare
  c_atual constant uuid := '09000000-0000-4000-8000-0000000000a1';
  v       jsonb := public.mind_agent_context(c_atual);
  v_pid   uuid  := (v->>'pessoa_id')::uuid;
  v_coll  jsonb := public.mind_engagement_fatos(v_pid);
  v_ant   jsonb := v->'engagement'->'conversas_anteriores';
  v_ant_esperadas jsonb;
  v_ids_ctx  uuid[];
  v_ids_coll uuid[];
  v_ocorrencias int;
  v_msgs_atual int;
  v_msgs_ant   int;
begin
  -- 1) a conversa atual aparece exatamente uma vez no coletor
  select count(*) into v_ocorrencias
    from jsonb_array_elements(v_coll->'conversas') e
   where (e->>'conversa_id')::uuid = c_atual;
  if v_ocorrencias <> 1 then
    raise exception 'CONTRATO 6.1: a conversa atual aparece % vezes no coletor, esperado 1', v_ocorrencias;
  end if;

  -- 2) a conversa atual NAO aparece nas anteriores
  if exists (select 1 from jsonb_array_elements(v_ant) e where e->>'conversa_id' = v->>'conversa_id') then
    raise exception 'CONTRATO 6.2: a conversa atual aparece dentro de conversas_anteriores';
  end if;

  -- 3 e 4) nenhuma conversa perdida, nenhuma duplicada
  select array_agg(x order by x) into v_ids_ctx from (
    select (v->'conversation'->>'conversa_id')::uuid as x
    union all
    select (e->>'conversa_id')::uuid from jsonb_array_elements(v_ant) e) t;
  select array_agg((e->>'conversa_id')::uuid order by (e->>'conversa_id')::uuid) into v_ids_coll
    from jsonb_array_elements(v_coll->'conversas') e;
  if v_ids_ctx <> v_ids_coll then
    raise exception 'CONTRATO 6.3/6.4: atual+anteriores (%) nao reproduz o conjunto do coletor (%)',
      v_ids_ctx, v_ids_coll;
  end if;
  if array_length(v_ids_ctx,1) <> cardinality(array(select distinct unnest(v_ids_ctx))) then
    raise exception 'CONTRATO 6.4: ha conversa duplicada em atual+anteriores (%)', v_ids_ctx;
  end if;

  -- 5) ordem das anteriores = ordem do coletor sem a atual
  select coalesce(jsonb_agg(e.valor order by e.ord), '[]'::jsonb) into v_ant_esperadas
    from jsonb_array_elements(v_coll->'conversas') with ordinality e(valor, ord)
   where (e.valor->>'conversa_id')::uuid <> c_atual;
  if v_ant <> v_ant_esperadas then
    raise exception 'CONTRATO 6.5: ordem/conteudo das conversas anteriores difere do coletor sem a atual';
  end if;

  -- 6 e 7) resumo e meta integrais
  if v->'engagement'->'resumo' <> v_coll->'resumo' then
    raise exception 'CONTRATO 6.6: engagement.resumo difere do resumo do coletor';
  end if;
  if v->'engagement'->'meta' <> v_coll->'meta' then
    raise exception 'CONTRATO 6.7: engagement.meta difere do meta do coletor';
  end if;

  -- contagem de conversas
  if 1 + jsonb_array_length(v_ant) <> (v->'engagement'->'resumo'->>'conversas_total')::int then
    raise exception 'CONTRATO 6: 1 + % anteriores <> conversas_total (%)',
      jsonb_array_length(v_ant), v->'engagement'->'resumo'->>'conversas_total';
  end if;

  -- contagem de mensagens
  v_msgs_atual := jsonb_array_length(v->'conversation'->'mensagens');
  select coalesce(sum(jsonb_array_length(e->'mensagens')), 0)::int into v_msgs_ant
    from jsonb_array_elements(v_ant) e;
  if v_msgs_atual + v_msgs_ant <> (v->'engagement'->'resumo'->>'mensagens_total')::int then
    raise exception 'CONTRATO 6: % (atual) + % (anteriores) <> mensagens_total (%)',
      v_msgs_atual, v_msgs_ant, v->'engagement'->'resumo'->>'mensagens_total';
  end if;
end
$c6$;


-- ------------------------------------------------------ CONTRATO 7 - ENTRY
do $c7$
declare
  v jsonb := public.mind_agent_context('09000000-0000-4000-8000-0000000000a1');
  v_chaves text[];
  v_esperado_entry  constant text[] := array['canal','entry_action','origem','origem_codigo','produto_codigo'];
  v_esperado_origem constant text[] := array['botao_rotulo','descricao','site'];
begin
  select array_agg(k order by k) into v_chaves from jsonb_object_keys(v->'entry') k;
  if v_chaves <> v_esperado_entry then
    raise exception 'CONTRATO 7: chaves de entry sao %, esperado %', v_chaves, v_esperado_entry;
  end if;

  if v->'entry'->>'origem_codigo' is null then
    raise exception 'CONTRATO 7: a fixture tem origem_codigo; entry.origem_codigo veio nulo';
  end if;

  select array_agg(k order by k) into v_chaves from jsonb_object_keys(v->'entry'->'origem') k;
  if v_chaves <> v_esperado_origem then
    raise exception 'CONTRATO 7: entry.origem devolveu % — devia devolver apenas %, nunca a linha inteira de engagement.origens',
      v_chaves, v_esperado_origem;
  end if;

  if v->'entry'->>'canal' is distinct from 'whatsapp'
     or v->'entry'->>'produto_codigo' is distinct from 'produto-teste-p9' then
    raise exception 'CONTRATO 7: canal/produto_codigo nao refletem a conversa. entry=%', v->'entry';
  end if;
end
$c7$;


-- ----------------------------------------------- CONTRATO 8 - ENTRY_ACTION
do $c8$
declare
  v_array  jsonb := public.mind_agent_context('09000000-0000-4000-8000-0000000000a1');
  v_object jsonb := public.mind_agent_context('09000000-0000-4000-8000-0000000000b1');
begin
  if v_array->'entry'->>'entry_action' is distinct from 'CTA ARRAY' then
    raise exception 'CONTRATO 8: variables em ARRAY devia dar entry_action="CTA ARRAY", veio %',
      v_array->'entry'->>'entry_action';
  end if;
  if v_object->'entry'->>'entry_action' is distinct from 'CTA PRIORITARIA' then
    raise exception 'CONTRATO 8: variables em OBJECT com as duas chaves devia dar "CTA PRIORITARIA" (hubspot_opcao_selecionada_treble vence), veio %',
      v_object->'entry'->>'entry_action';
  end if;
end
$c8$;


-- ------------------------------ CONTRATO 9 - ESTADO DO AGENTE NAO E FATO
do $c9$
declare
  v_ids uuid[] := array['09000000-0000-4000-8000-0000000000a1',
                        '09000000-0000-4000-8000-0000000000b1'];
  c_estado constant text[] := array[
    'audience','stage','intent','objection','ticket_interest','needs_human','checkout_sent','desfecho'];
  v  jsonb;
  id uuid;
  k  text;
begin
  foreach id in array v_ids loop
    v := public.mind_agent_context(id);
    foreach k in array c_estado loop
      if v ? k then
        raise exception 'CONTRATO 9: "%" aparece no topo do AGENT_CONTEXT (conversa %)', k, id;
      end if;
      if v->'entry' ? k then
        raise exception 'CONTRATO 9: "%" aparece dentro de entry (conversa %)', k, id;
      end if;
    end loop;
  end loop;

  -- A palavra escrita pela pessoa continua sendo historico factual.
  v := public.mind_agent_context('09000000-0000-4000-8000-0000000000a1');
  if not exists (select 1 from jsonb_array_elements(v->'conversation'->'mensagens') m
                  where m->>'conteudo' like '%intent%') then
    raise exception 'CONTRATO 9: o texto que a pessoa escreveu foi alterado ou removido do transcrito';
  end if;
end
$c9$;


-- ------------------------------------- CONTRATO 10 - AUSENCIAS DELIBERADAS
-- Estrutura, nunca busca textual no JSON serializado: a palavra pode aparecer
-- legitimamente dentro de uma mensagem.
do $c10$
declare
  v jsonb := public.mind_agent_context('09000000-0000-4000-8000-0000000000a1');
  c_proibidas constant text[] := array[
    'session_external_id','telefone','telefone_hash','nome_contato','dispositivo_id',
    'utm','utm_token','variables',
    'memory','route','decision','evento','ofertas','ofertas_vigentes','agenda','faq',
    'policies','politicas','regras_comerciais'];
  k text;
begin
  foreach k in array c_proibidas loop
    if v ? k then
      raise exception 'CONTRATO 10: "%" nao pode existir no topo do AGENT_CONTEXT', k;
    end if;
    if v->'entry' ? k then
      raise exception 'CONTRATO 10: "%" nao pode existir dentro de entry', k;
    end if;
    if v->'conversation' ? k then
      raise exception 'CONTRATO 10: "%" nao pode existir dentro de conversation', k;
    end if;
    if v->'engagement' ? k then
      raise exception 'CONTRATO 10: "%" nao pode existir dentro de engagement', k;
    end if;
  end loop;

  -- engagement e exatamente a particao: resumo, conversas_anteriores e meta.
  if (select array_agg(x order by x) from jsonb_object_keys(v->'engagement') x)
     <> array['conversas_anteriores','meta','resumo'] then
    raise exception 'CONTRATO 10: engagement tem chaves alem de resumo/conversas_anteriores/meta';
  end if;
end
$c10$;


-- ----------------------------------------------- CONTRATO 11 - DETERMINISMO
do $c11$
declare
  id uuid;
  v_ids uuid[] := array['09000000-0000-4000-8000-0000000000a1',
                        '09000000-0000-4000-8000-0000000000b1',
                        '09000000-0000-4000-8000-0000000000c1',
                        '09000000-0000-4000-8000-0000000000d1'];
begin
  foreach id in array v_ids loop
    if public.mind_agent_context(id)::text <> public.mind_agent_context(id)::text then
      raise exception 'CONTRATO 11: duas chamadas com o mesmo estado factual divergiram (conversa %)', id;
    end if;
  end loop;
end
$c11$;


-- ------------------------------------------- CONTRATO 12 - PROPRIEDADES
do $c12$
declare
  r record;
  v_exec text[];
begin
  select p.provolatile, p.prosecdef, p.proconfig, p.proacl
    into r
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'mind_agent_context';

  if r is null then
    raise exception 'CONTRATO 12: public.mind_agent_context nao existe';
  end if;
  if r.provolatile <> 's' then
    raise exception 'CONTRATO 12: a funcao devia ser STABLE, e "%"', r.provolatile;
  end if;
  if not r.prosecdef then
    raise exception 'CONTRATO 12: a funcao devia ser SECURITY DEFINER';
  end if;
  if r.proconfig is null or not exists (select 1 from unnest(r.proconfig) c where c like 'search_path=%') then
    raise exception 'CONTRATO 12: a funcao devia ter search_path explicito, tem %', r.proconfig;
  end if;

  select array_agg(distinct a.grantee::regrole::text order by a.grantee::regrole::text)
    into v_exec
    from aclexplode(r.proacl) a
   where a.privilege_type = 'EXECUTE';

  if v_exec is null then
    raise exception 'CONTRATO 12: sem ACL — EXECUTE estaria aberto a todos';
  end if;
  if not ('postgres' = any(v_exec)) then
    raise exception 'CONTRATO 12: postgres devia poder executar, ACL = %', v_exec;
  end if;
  if not ('service_role' = any(v_exec)) then
    raise exception 'CONTRATO 12: service_role devia poder executar, ACL = %', v_exec;
  end if;
  if 'public' = any(v_exec) or 'anon' = any(v_exec) or 'authenticated' = any(v_exec) then
    raise exception 'CONTRATO 12: EXECUTE nao pode estar liberado para public/anon/authenticated, ACL = %', v_exec;
  end if;
end
$c12$;


-- ------------------ CONTRATO 13 - PARTICIPANTE SIM, COMPRADOR NUNCA
do $c13$
declare
  v_pid constant uuid := '09000000-0000-4000-8000-000000000001';
  v jsonb := public.mind_credenciamento_fatos(v_pid);
  v_chaves text[];
  r record;
  v_exec text[];
begin
  select array_agg(k order by k) into v_chaves from jsonb_object_keys(v) k;
  if v_chaves <> array[
    'categoria_unica','categorias','evento_codigo','ingressos','meta','ok',
    'participante','pessoa_id','tem_ingresso_ativo'] then
    raise exception 'CONTRATO 13.1: chaves do credenciamento são %', v_chaves;
  end if;

  if v->>'pessoa_id' <> v_pid::text
     or v->>'evento_codigo' <> 'mind-summit-2026'
     or (v->>'tem_ingresso_ativo')::boolean is not true
     or v->'participante' <> jsonb_build_object(
       'nome','Pessoa Credenciada',
       'email','p9-credenciamento@example.test',
       'whatsapp','5511988887777')
     or v->>'categoria_unica' <> 'VIP'
     or v->'categorias' <> '["VIP"]'::jsonb
     or v->'ingressos' <> '[{"categoria":"VIP","quantidade":2}]'::jsonb then
    raise exception 'CONTRATO 13.2: ativo/revogado/SEM MAPA ou agregação divergiram: %', v;
  end if;

  select array_agg(k order by k) into v_chaves from jsonb_object_keys(v->'meta') k;
  if v_chaves <> array['dados_comprador_omitidos','fonte','sincronizado_em']
     or (v->'meta'->>'dados_comprador_omitidos')::boolean is not true
     or v->'meta'->>'fonte' <> 'credenciamento_oficial' then
    raise exception 'CONTRATO 13.3: meta do credenciamento divergiu: %', v->'meta';
  end if;

  select array_agg(k order by k) into v_chaves
    from jsonb_object_keys(v->'ingressos'->0) k;
  if v_chaves <> array['categoria','quantidade'] then
    raise exception 'CONTRATO 13.4: ingresso expôs campo além de categoria/quantidade: %',
      v->'ingressos'->0;
  end if;

  if v::text ~ 'buyer_(name|email|company|cpf|cnpj)|"comprador"'
     or v ? 'comprador'
     or v->'participante' ? 'buyer_name'
     or v->'participante' ? 'buyer_email' then
    raise exception 'CONTRATO 13.5: dado do comprador vazou no contexto: %', v;
  end if;

  if public.mind_credenciamento_fatos(null)
     <> jsonb_build_object('ok', false, 'motivo', 'sem_pessoa') then
    raise exception 'CONTRATO 13.6: pessoa nula não falhou de forma controlada';
  end if;

  select p.provolatile, p.prosecdef, p.proconfig, p.proacl
    into r
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'mind_credenciamento_fatos';

  if r is null or r.provolatile <> 's' or not r.prosecdef
     or r.proconfig is null
     or not exists (select 1 from unnest(r.proconfig) c where c like 'search_path=%') then
    raise exception 'CONTRATO 13.7: propriedades de segurança/estabilidade inválidas: %', row_to_json(r);
  end if;

  select array_agg(distinct a.grantee::regrole::text order by a.grantee::regrole::text)
    into v_exec
    from aclexplode(r.proacl) a
   where a.privilege_type = 'EXECUTE';

  if v_exec is null
     or not ('postgres' = any(v_exec))
     or not ('service_role' = any(v_exec))
     or 'public' = any(v_exec)
     or 'anon' = any(v_exec)
     or 'authenticated' = any(v_exec) then
    raise exception 'CONTRATO 13.8: ACL do coletor inválida: %', v_exec;
  end if;
end
$c13$;


-- ----------------------- CONTRATO 14 - VALIDAÇÃO E WHATSAPP DECLARADO
do $c14$
declare
  v_pid constant uuid := '09000000-0000-4000-8000-000000000001';
  v jsonb;
  v_exec text[];
  r record;
  v_nome text;
begin
  if (public.mind_identificador_validar('email','Pessoa@Example.COM')->>'valido')::boolean is not true
     or (public.mind_identificador_validar('email','pessoa@example')->>'valido')::boolean is not false
     or (public.mind_identificador_validar('whatsapp','(11) 97777-6666')->>'valido')::boolean is not true
     or (public.mind_identificador_validar('whatsapp','123')->>'valido')::boolean is not false then
    raise exception 'CONTRATO 14.1: validação de e-mail/WhatsApp divergiu';
  end if;

  v := public.mind_identificador_declarado_registrar(
    v_pid, 'whatsapp', '(11) 97777-6666'
  );
  if v->>'ok' <> 'true' or v->>'status' <> 'registrado'
     or v->>'verificado' <> 'false' or v->>'confianca' <> 'media' then
    raise exception 'CONTRATO 14.2: writer não registrou declaração corretamente: %', v;
  end if;

  if not exists (
    select 1 from engagement.identidades i
    where i.pessoa_id = v_pid
      and i.canal = 'whatsapp'
      and i.identificador = '5511977776666'
      and i.verificado is false
      and i.confianca = 'media'
  ) then
    raise exception 'CONTRATO 14.3: WhatsApp não foi normalizado/gravado na identidade canônica';
  end if;

  if (select p.whatsapp from pessoas.pessoas p where p.id=v_pid)
     is distinct from '5511977776666' then
    raise exception 'CONTRATO 14.4: projeção vazia de pessoas.pessoas.whatsapp não foi preenchida';
  end if;

  perform public.mind_identificador_declarado_registrar(
    v_pid, 'whatsapp', '+55 11 97777-6666'
  );
  if (select count(*) from engagement.identidades i
      where i.canal='whatsapp' and i.identificador='5511977776666') <> 1 then
    raise exception 'CONTRATO 14.5: retry duplicou a identidade';
  end if;

  if (public.mind_identificador_declarado_registrar(v_pid,'whatsapp','123')->>'ok')::boolean
     is not false then
    raise exception 'CONTRATO 14.6: WhatsApp inválido foi aceito';
  end if;

  foreach v_nome in array array[
    'mind_identificador_validar',
    'mind_identificador_declarado_registrar'
  ] loop
    select p.prosecdef, p.proconfig, p.proacl into r
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=v_nome;

    select array_agg(distinct a.grantee::regrole::text order by a.grantee::regrole::text)
      into v_exec
      from aclexplode(r.proacl) a
     where a.privilege_type='EXECUTE';

    if r is null or not r.prosecdef or r.proconfig is null
       or v_exec is null
       or not ('postgres'=any(v_exec))
       or not ('service_role'=any(v_exec))
       or 'public'=any(v_exec)
       or 'anon'=any(v_exec)
       or 'authenticated'=any(v_exec) then
      raise exception 'CONTRATO 14.7: segurança inválida em %, ACL %', v_nome, v_exec;
    end if;
  end loop;
end
$c14$;


select 'todos os 14 contratos passaram' as resultado,
       14 as contratos_verificados,
       (select count(*) from engagement.conversas
         where id::text like '09000000-0000-4000-8000-%') as fixtures_na_transacao;

-- Nada do que este arquivo criou sobrevive a esta linha.
rollback;
