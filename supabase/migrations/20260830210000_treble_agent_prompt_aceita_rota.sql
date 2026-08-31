-- ============================================================
-- Go-live Vendedor Summit (Lane B) — o compositor de prompt do Treble passa a
-- falar a língua das ROTAS canônicas.
-- ------------------------------------------------------------
-- POR QUE
--
-- Com Router → Gate → Kit dentro do turno, quem escolhe a competência é a rota
-- (`summit_b2c`, `summit_b2b`), não mais o `audience` que o próprio modelo
-- classificava. `public.treble_agent_prompt` já resolvia o playbook certo para
-- uma rota — `'playbook_' || 'summit_b2c'` casa com `playbook_summit_b2c` —,
-- mas as duas condições de audiência abaixo não conheciam os nomes de rota e
-- deixariam de fora justamente o motor comercial:
--
--   ordem 3  sales_decision_engine  (Decisioning comercial)
--   ordem 5  objecoes               (playbook de objeções)
--
-- A MENOR MUDANÇA é acrescentar as duas rotas de venda às listas que já
-- existem. Nada mais muda: mesmo nome, mesma assinatura, mesmo corpo, mesma
-- volatilidade, mesmos grants. Os valores legados (`b2c`, `b2b`,
-- `desconhecido`, `cliente_suporte`, ...) continuam válidos e produzem
-- exatamente a mesma composição de antes — o caminho legado do runtime depende
-- disso.
--
-- EQUIVALÊNCIA VERIFICADA contra os prompts ativos em produção (30/08/2026):
--
--   b2c        -> playbook_router + tom_de_voz + sales_decision_engine + playbook_summit_b2c + objecoes
--   summit_b2c -> playbook_router + tom_de_voz + sales_decision_engine + playbook_summit_b2c + objecoes
--   b2b        -> playbook_router + tom_de_voz + sales_decision_engine + playbook_summit_b2b + objecoes
--   summit_b2b -> playbook_router + tom_de_voz + sales_decision_engine + playbook_summit_b2b + objecoes
--
-- O playbook em ordem 4 é a MESMA linha de `agentes.prompts` que
-- `public.mind_agent_kit(rota, ...)` devolve no campo `playbook`. Não existem
-- dois playbooks da rota, e nenhum conteúdo de prompt é escrito aqui.
--
-- O parâmetro continua chamando-se `p_audience` de propósito: renomeá-lo
-- quebraria a chamada RPC do runtime vivo sem nada em troca. Ele aceita a rota
-- canônica OU o valor legado de audiência.
-- ============================================================

create or replace function public.treble_agent_prompt(p_audience text default 'desconhecido'::text)
returns text
language sql
security definer
set search_path to 'public', 'agentes'
as $function$
  select string_agg(conteudo, E'\n\n' order by ordem)
  from (
    -- identidade, dados e limites (vale sempre)
    select conteudo, 1 as ordem from agentes.prompts
     where chave in ('base','playbook_router') and ativo
    union all
    select conteudo, 2 from agentes.prompts where chave = 'tom_de_voz' and ativo
    union all
    -- motor de decisão comercial (só quando há intenção comercial)
    select conteudo, 3 from agentes.prompts
     where chave = 'sales_decision_engine' and ativo
       and coalesce(p_audience,'desconhecido') in
           ('b2c','b2b','desconhecido','summit_b2c','summit_b2b')
    union all
    -- playbook da rota/audiência: aceita 'playbook_x' e 'playbook_summit_x'
    select conteudo, 4 from agentes.prompts
     where chave in ('playbook_' || coalesce(nullif(p_audience,''), 'desconhecido'),
                     'playbook_summit_' || coalesce(nullif(p_audience,''), 'desconhecido'))
       and ativo
    union all
    select conteudo, 5 from agentes.prompts
     where chave = 'objecoes' and ativo
       and coalesce(p_audience,'desconhecido') in
           ('b2c','desconhecido','b2b','summit_b2c','summit_b2b')
  ) partes;
$function$;

comment on function public.treble_agent_prompt(text) is
  'Compõe as instruções do agente inbound do WhatsApp a partir de agentes.prompts. O argumento aceita a ROTA canônica (summit_b2c, summit_b2b, cliente_suporte, ...) ou o valor legado de audiência (b2c, b2b, desconhecido) — os dois resolvem o mesmo playbook e a mesma composição. Nenhuma regra de venda mora aqui: o conteúdo é dos prompts.';
