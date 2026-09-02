-- CORREÇÃO DE INCIDENTE. `public.mind_customer_intelligence`, criada em
-- `20260902140000`, ordenava a identidade de HubSpot da pessoa por
-- `i.atualizado_em` — coluna que `engagement.identidades` NÃO tem. A tabela tem
-- `id, pessoa_id, canal, identificador, verificado, confianca, criado_em`.
--
-- POR QUE ISSO PASSOU. PL/pgSQL não resolve os nomes de coluna do corpo na
-- criação: só na execução. A função foi criada sem erro, e o erro só apareceu
-- quando o caminho que constrói o ICP a partir do espelho de CRM foi exercido
-- com uma pessoa real.
--
-- O ESTRAGO. `mind_kit_customer_intelligence` chama esta função, e o bloco
-- `customer_intelligence` entrou nos Kits das QUATRO rotas — `concierge_summit`,
-- `cliente_suporte`, `summit_b2c` e `summit_b2b`. Como `mind_agent_kit` monta
-- todos os blocos do Kit, a exceção derrubava o Kit inteiro. E o runtime falha
-- fechado de propósito: sem Kit, não chama o modelo. Resultado medido em
-- produção às 06:58 de 02/09 — `mindagent-chat` devolvendo
-- `503 official_data_unavailable` em toda conversa do App, e o mesmo Kit
-- quebrado do lado do vendedor no WhatsApp.
--
-- O fail-closed funcionou como projetado: o agente ficou mudo em vez de
-- responder sem os dados oficiais. Foi ele que transformou um erro de coluna
-- numa indisponibilidade visível em vez de uma resposta inventada.
--
-- A MENOR MUDANÇA CORRETA é um token: a intenção da subconsulta é "a identidade
-- de HubSpot mais recente desta pessoa", e `criado_em` é o único carimbo de
-- tempo que a tabela tem. As outras referências a `atualizado_em` no corpo são
-- válidas e ficam como estão — `crm.contato_espelho` e
-- `intelligence.participante_memoria` têm a coluna.
--
-- Aplicada em produção em 02/09 por substituição de um token sobre a definição
-- viva, com guarda de ocorrência única. Este arquivo é idempotente e serve para
-- o replay da cadeia de migrations reproduzir o estado corrigido.

do $corrige$
declare d text; n int;
begin
  select pg_get_functiondef(p.oid) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'mind_customer_intelligence';

  if d is null then
    raise exception 'mind_customer_intelligence nao existe; aplique 20260902140000 antes';
  end if;

  n := (length(d) - length(replace(d, 'i.atualizado_em', ''))) / length('i.atualizado_em');

  if n = 0 then
    raise notice 'ja corrigida; nada a fazer';
  elsif n = 1 then
    execute replace(d, 'i.atualizado_em', 'i.criado_em');
  else
    raise exception 'esperava no maximo 1 ocorrencia de i.atualizado_em, achei %', n;
  end if;
end $corrige$;

do $confere$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'mind_customer_intelligence';

  if position('i.criado_em' in d) = 0 then
    raise exception 'a correcao nao entrou'; end if;
  if position('i.atualizado_em' in d) > 0 then
    raise exception 'ainda ha referencia a i.atualizado_em'; end if;
  -- As ordenações legítimas não podem ter sido levadas junto.
  if position('e.atualizado_em desc nulls last limit 1' in d) = 0 then
    raise exception 'a ordenacao de crm.contato_espelho se perdeu'; end if;
  if position('pm.atualizado_em' in d) = 0 then
    raise exception 'a ordenacao de participante_memoria se perdeu'; end if;
end $confere$;

-- Prova de que o Kit volta a montar nas quatro rotas que receberam o bloco.
do $prova$
declare
  v_conversa uuid;
  v_rota text;
  v_kit jsonb;
begin
  select id into v_conversa from engagement.conversas
   where participante_id is not null order by iniciada_em desc limit 1;
  if v_conversa is null then
    raise notice 'sem conversa com participante para provar; conferencia estrutural ja passou';
    return;
  end if;

  foreach v_rota in array array['concierge_summit','cliente_suporte','summit_b2c','summit_b2b']
  loop
    v_kit := public.mind_agent_kit(v_rota, v_conversa,
      jsonb_build_object('pergunta','oi','limite',12,'interesses','[]'::jsonb));
    if coalesce((v_kit->'meta'->>'kit_disponivel')::boolean, false) is not true then
      raise exception 'o Kit de % nao monta: %', v_rota, coalesce(v_kit->>'motivo','sem motivo');
    end if;
  end loop;
end $prova$;
