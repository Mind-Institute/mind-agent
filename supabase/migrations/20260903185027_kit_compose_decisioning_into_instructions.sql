-- O Kit preserva Playbook e Decisioning como fontes separadas, mas compõe
-- ambas na string final `playbook` porque o runtime mindagent-chat já usa esse
-- campo como `instructions` da Responses API. Assim não há duplicação em prompt,
-- hardcode de rota na Edge nem deploy de executor para uma mudança de composição.

create or replace function public.mind_agent_kit(
  p_rota text,
  p_conversa_id uuid,
  p_necessidade jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'agentes', 'engagement', 'concierge'
as $function$
declare
  v_rota         text := nullif(btrim(p_rota), '');
  v_meta         jsonb;
  v_structured   jsonb := '{}'::jsonb;
  v_tools        jsonb;
  v_base         text;
  v_playbook     text;
  v_decisioning  text;
  v_instructions text;
  v_payload      jsonb;
  v_falhas       text[] := array[]::text[];
  r              record;
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

  select pr.conteudo into v_playbook
    from agentes.prompts pr
   where pr.chave = 'playbook_' || v_rota and pr.ativo
   limit 1;

  select pr.conteudo into v_base
    from agentes.prompts pr
   where pr.chave = 'base' and pr.ativo
     and btrim(coalesce(pr.conteudo, '')) <> ''
   limit 1;

  if v_base is not null and v_playbook is not null then
    v_playbook := v_base || E'\n\n' || v_playbook;
  end if;

  select string_agg(pr.conteudo, E'\n\n' order by k.bloco)
    into v_decisioning
    from agentes.kit_blocos k
    join agentes.prompts pr on pr.chave = k.bloco and pr.ativo
   where k.rota = v_rota and k.ativo and k.secao = 'decisioning';

  v_instructions := v_playbook;
  if v_decisioning is not null and btrim(v_decisioning) <> '' then
    v_instructions := coalesce(v_instructions, '') || E'\n\n' || v_decisioning;
  end if;

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

  select coalesce(jsonb_agg(
           jsonb_build_object('nome', f.nome, 'descricao', f.descricao, 'parametros', f.json_schema)
           order by f.nome), '[]'::jsonb)
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
    'meta',        v_meta || jsonb_build_object('blocos_com_falha', to_jsonb(v_falhas)));
end;
$function$;
