-- O Kit passa a dizer quais skills são obrigatórias (agentes.kit_blocos.obrigatorio, que já
-- existia para os blocos de dados). O runtime usa isso para forçar a busca no primeiro turno
-- de conteúdo: a MIA Summit respondia de memória com o contexto pronto e nunca consultava o
-- acervo (Adriana, 23/10/2026, item 3 aprovado). Mesma função, uma chave a mais por skill.

create or replace function public.mind_agent_kit(p_rota text, p_conversa_id uuid, p_necessidade jsonb default '{}'::jsonb)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'agentes', 'engagement', 'concierge'
as $function$
declare
  v_rota        text := nullif(btrim(p_rota), '');
  v_meta        jsonb;
  v_structured  jsonb := '{}'::jsonb;
  v_tools       jsonb;
  v_montagem    jsonb;
  v_decisioning text;
  v_instructions text;
  v_payload     jsonb;
  v_falhas      text[] := array[]::text[];
  r             record;
begin
  v_meta := public.mind_kit_meta(v_rota);
  if not coalesce((v_meta->>'ok')::boolean, false) then
    return v_meta;
  end if;

  if p_conversa_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_conversa');
  end if;

  if not exists (select 1 from engagement.conversas c where c.id = p_conversa_id) then
    return jsonb_build_object('ok', false, 'motivo', 'conversa_nao_encontrada', 'conversa_id', p_conversa_id);
  end if;

  -- Base, playbook, blocos de instrução e decisioning: a mesma montagem que o painel mostra.
  v_montagem := public.mind_agent_instrucoes(v_rota);
  v_instructions := v_montagem->>'texto';
  v_decisioning := v_montagem->>'decisioning';

  for r in
    select k.bloco, k.obrigatorio, n.nspname as sch, p.proname as fn
    from agentes.kit_blocos k
    left join pg_proc p
      on p.oid = to_regprocedure(
           case when k.provider ~ '^[a-z_][a-z0-9_$]*\.[a-z_][a-z0-9_$]*$'
                then k.provider || '(uuid,jsonb)'
           end)
     and p.prokind = 'f' and p.pronargs = 2
     and p.proargtypes[0] = 'uuid'::regtype and p.proargtypes[1] = 'jsonb'::regtype
     and p.prorettype = 'jsonb'::regtype and not p.proretset
     and p.provolatile = 's' and p.prosecdef
    left join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where k.rota = v_rota and k.ativo and k.secao = 'structured'
    order by k.bloco
  loop
    continue when r.sch is null or r.fn is null;
    begin
      execute format('select %I.%I($1::uuid, $2::jsonb)', r.sch, r.fn)
        into v_payload using p_conversa_id, p_necessidade;
    exception when others then
      if r.obrigatorio then raise; end if;
      raise warning 'mind_agent_kit(%): bloco opcional % falhou e foi omitido: %', v_rota, r.bloco, sqlerrm;
      v_falhas := v_falhas || r.bloco;
      v_payload := null;
    end;
    if v_payload is not null then
      v_structured := v_structured || jsonb_build_object(r.bloco, v_payload);
    end if;
  end loop;

  -- `obrigatorio` em uma skill = o runtime força a chamada no primeiro turno de conteúdo.
  select coalesce(jsonb_agg(jsonb_build_object('nome', f.nome, 'descricao', f.descricao, 'parametros', f.json_schema, 'obrigatorio', k.obrigatorio) order by f.nome), '[]'::jsonb)
    into v_tools
    from agentes.kit_blocos k
    join concierge.ferramentas f on f.nome = k.bloco
   where k.rota = v_rota and k.ativo and k.secao = 'tools'
     and f.ativo and f.escrita = false;

  return jsonb_build_object(
    'playbook',    v_instructions,
    'decisioning', v_decisioning,
    'structured',  v_structured,
    'knowledge',   '[]'::jsonb,
    'tools',       coalesce(v_tools, '[]'::jsonb),
    'meta',        v_meta || jsonb_build_object(
                     'blocos_com_falha', to_jsonb(v_falhas),
                     'instrucoes_faltando', coalesce(v_montagem->'faltando', '[]'::jsonb)));
end;
$function$;

-- A MIA busca antes de responder: a lupa é obrigatória nela (e só nela, por enquanto).
update agentes.kit_blocos
   set obrigatorio = true, atualizado_em = now()
 where rota = 'mia_summit_2026' and bloco = 'buscar_intelligence' and secao = 'tools' and not obrigatorio;
