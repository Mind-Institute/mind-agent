-- Contrato: Product Decisioning reutilizado pelo Concierge sem duplicar o prompt no playbook.
-- Leitura apenas; não deixa fixture.

do $test$
declare
  v_c uuid;
  v_concierge jsonb;
  v_suporte jsonb;
  v_fonte_playbook text;
  v_treble text;
begin
  select id into v_c
  from engagement.conversas
  where participante_id is not null
  order by iniciada_em desc
  limit 1;
  if v_c is null then raise exception 'sem conversa com participante'; end if;

  v_concierge := public.mind_agent_kit(
    'concierge_summit', v_c,
    jsonb_build_object('pergunta','quero continuar aprendendo depois do Summit','interesses','[]'::jsonb)
  );
  v_suporte := public.mind_agent_kit(
    'cliente_suporte', v_c,
    jsonb_build_object('pergunta','meu ingresso não apareceu','interesses','[]'::jsonb)
  );

  if coalesce((v_concierge->'meta'->>'kit_disponivel')::boolean,false) is not true then
    raise exception 'kit concierge indisponivel';
  end if;
  if not ((v_concierge->'structured') ? 'customer_intelligence') then
    raise exception 'sem customer_intelligence';
  end if;
  if not ((v_concierge->'structured') ? 'product_intelligence') then
    raise exception 'sem product_intelligence';
  end if;
  if position('NENHUMA RECOMENDAÇÃO É UM RESULTADO VÁLIDO' in coalesce(v_concierge->>'decisioning',''))=0 then
    raise exception 'decisioning v2 ausente do campo separado';
  end if;
  if position('NENHUMA RECOMENDAÇÃO É UM RESULTADO VÁLIDO' in coalesce(v_concierge->>'playbook',''))=0 then
    raise exception 'decisioning v2 ausente do bundle consumido pelo runtime';
  end if;

  select conteudo into v_fonte_playbook
  from agentes.prompts
  where chave='playbook_concierge_summit' and ativo
  limit 1;
  if position('PRODUCT DECISIONING ENTRE SOLUÇÕES MIND' in coalesce(v_fonte_playbook,''))>0 then
    raise exception 'decisioning foi duplicado no playbook fonte';
  end if;

  if nullif(btrim(coalesce(v_suporte->>'decisioning','')),'') is not null then
    raise exception 'decisioning vazou para suporte';
  end if;
  if position('PRODUCT DECISIONING ENTRE SOLUÇÕES MIND' in coalesce(v_suporte->>'playbook',''))>0 then
    raise exception 'bundle de suporte recebeu decisioning';
  end if;

  select public.treble_agent_prompt('summit_b2c','decisioning') into v_treble;
  if position('NENHUMA RECOMENDAÇÃO É UM RESULTADO VÁLIDO' in coalesce(v_treble,''))=0 then
    raise exception 'treble perdeu product decisioning v2';
  end if;
end $test$;
