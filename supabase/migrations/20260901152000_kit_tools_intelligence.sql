-- O Kit passa a entregar TOOLS de verdade. Até aqui `mind_agent_kit` devolvia
-- `'tools', '[]'::jsonb` — literal, fixo, para toda rota. O Agent lia contexto e
-- respondia; não tinha como investigar.
--
-- O QUE MUDA NO PENSAMENTO. Antes: `Kit recupera contexto -> modelo lê -> responde`.
-- O contexto era escolhido ANTES de o modelo pensar, a partir da frase crua da pessoa.
-- Agora: `modelo entende a necessidade -> consulta Intelligence quando precisa -> lê ->
-- pode aprofundar -> responde`. Quem formula a consulta passa a ser quem entendeu a
-- pergunta.
--
-- NADA DE MOTOR NOVO. `mind_intelligence_buscar` e `mind_intelligence_ler` já existem
-- desde 20260831070000, já leem as casas canônicas (palestrantes, sessões,
-- knowledge_documents) e já foram medidas. Não há embedding novo, banco de conhecimento
-- novo nem fonte da verdade duplicada. Esta migration não escreve motor: ela liga o que
-- existe ao Kit.
--
-- POR QUE DUAS CASAS, E NÃO UMA COLUNA NOVA. O descritor de uma tool — nome, descrição,
-- json_schema, destino, se escreve — já tem casa: `concierge.ferramentas`. A pergunta
-- "quais tools ESTA rota expõe" tem outra: `agentes.kit_blocos`, cujo CHECK já admite
-- `secao='tools'` desde que o contrato do Kit foi desenhado. São perguntas diferentes e
-- cada uma já tinha onde morar. Criar `parametros jsonb` em `kit_blocos` duplicaria o
-- catálogo; criar tabela seria pior.
--
-- POR QUE A EXPOSIÇÃO É POR ROTA, E NÃO O CATÁLOGO INTEIRO. `concierge.ferramentas` tem
-- 28 linhas — o desenho do concierge completo, da Lane E. A esmagadora maioria não tem
-- executor hoje. Expor o catálogo ao modelo seria oferecer 26 ferramentas que falham.
-- Quem decide o que está ligado é `kit_blocos`, rota por rota. Nesta entrega: DUAS.
--
-- POR QUE SÓ LEITURA. O join filtra `escrita = false`. Nenhuma ferramenta que escreve
-- chega ao modelo por este caminho sem uma mudança deliberada — o Play continua com o
-- caminho dele, invocado pela tela, com a pessoa no controle. Ligar escrita aqui seria
-- outbound sem gate por acidente.

insert into concierge.ferramentas (nome, descricao, json_schema, tipo_exec, destino, escrita, ativo)
values
  ('buscar_intelligence',
   'Procura na Intelligence do Mind (palestrantes, sessões e conhecimento) a partir de uma NECESSIDADE que você mesmo formula. Não repita a frase da pessoa: traduza o que ela quer para os termos do domínio. Exemplo: "um time onde as pessoas discordem sem medo" vira "segurança psicológica discordância liderança". Devolve candidatos compactos com tipo e id.',
   '{"type":"object","additionalProperties":false,
     "properties":{
       "necessidade":{"type":"string","description":"A necessidade traduzida para os termos do domínio, não a frase crua da pessoa."},
       "limite":{"type":["integer","null"],"description":"Quantos candidatos no máximo (1 a 10). null usa o padrão."}},
     "required":["necessidade","limite"]}'::jsonb,
   'sql', 'public.mind_intelligence_buscar', false, true),

  ('ler_intelligence',
   'Abre em profundidade UM objeto encontrado por buscar_intelligence, usando o tipo e o id que ele devolveu. Use quando precisar raciocinar sobre o conteúdo — quem é a pessoa, o que ela defende, por que a sessão importa — e não apenas citar o título.',
   '{"type":"object","additionalProperties":false,
     "properties":{
       "tipo":{"type":"string","enum":["palestrante","sessao","conhecimento"],"description":"O tipo devolvido por buscar_intelligence."},
       "id":{"type":"string","description":"O id devolvido por buscar_intelligence."}},
     "required":["tipo","id"]}'::jsonb,
   'sql', 'public.mind_intelligence_ler', false, true)
on conflict (nome) do update
  set descricao   = excluded.descricao,
      json_schema = excluded.json_schema,
      tipo_exec   = excluded.tipo_exec,
      destino     = excluded.destino,
      escrita     = excluded.escrita,
      ativo       = excluded.ativo;

-- Quais tools ESTA rota expõe. `provider` aponta a casa do descritor — é o catálogo,
-- não uma função `(uuid,jsonb)`; por isso `obrigatorio = false`: linha de `secao='tools'`
-- nunca entra na conta de disponibilidade do Kit, que é sobre dado oficial.
insert into agentes.kit_blocos (rota, secao, bloco, provider, obrigatorio, ativo) values
  ('concierge_summit', 'tools', 'buscar_intelligence', 'concierge.ferramentas', false, true),
  ('concierge_summit', 'tools', 'ler_intelligence',    'concierge.ferramentas', false, true)
on conflict (rota, bloco) do update
  set secao = excluded.secao, provider = excluded.provider,
      obrigatorio = excluded.obrigatorio, ativo = excluded.ativo;

-- `kit_configurado` volta a significar o que sempre significou: a rota tem Kit de dado
-- oficial. Sem o filtro, uma rota que só tivesse tools passaria a se declarar configurada
-- e o Gate abriria para um Kit vazio. Hoje isto não muda nada — todas as linhas
-- existentes são `structured` —, e é exatamente por isso que é a hora de fechar.
create or replace function public.mind_kit_meta(p_rota text)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'agentes'
as $function$
declare
  v_rota         text    := nullif(btrim(p_rota), '');
  v_configurado  boolean;
  v_obrigatorios text[]  := array[]::text[];
  v_ausentes     text[]  := array[]::text[];
  v_payload      jsonb;
  r              record;
begin
  if v_rota is null or v_rota not in (
       'summit_b2c','summit_b2b','institute','dash','cliente_suporte','concierge_summit') then
    return jsonb_build_object('ok', false, 'motivo', 'rota_invalida');
  end if;

  select exists (
    select 1 from agentes.kit_blocos k
     where k.rota = v_rota and k.ativo and k.secao = 'structured')
    into v_configurado;

  for r in
    select k.bloco, n.nspname as sch, p.proname as fn
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
    where k.rota = v_rota and k.ativo and k.obrigatorio and k.secao = 'structured'
    order by k.bloco
  loop
    v_obrigatorios := v_obrigatorios || r.bloco;
    if r.sch is null or r.fn is null then
      v_ausentes := v_ausentes || r.bloco;
    else
      execute format('select %I.%I($1::uuid, $2::jsonb)', r.sch, r.fn)
        into v_payload using null::uuid, null::jsonb;
      if v_payload is null then v_ausentes := v_ausentes || r.bloco; end if;
    end if;
  end loop;

  return jsonb_build_object(
    'ok',                  true,
    'rota',                v_rota,
    'kit_configurado',     v_configurado,
    'kit_disponivel',      v_configurado and cardinality(v_ausentes) = 0,
    'blocos_obrigatorios', to_jsonb(v_obrigatorios),
    'blocos_ausentes',     to_jsonb(v_ausentes));
end;
$function$;

-- `tools` deixa de ser literal vazio. O resto do contrato do Kit — `playbook`,
-- `structured`, `knowledge`, `meta` — fica exatamente como está.
create or replace function public.mind_agent_kit(
  p_rota text, p_conversa_id uuid, p_necessidade jsonb default null
) returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'agentes'
as $function$
declare
  v_rota       text  := nullif(btrim(p_rota), '');
  v_meta       jsonb;
  v_structured jsonb := '{}'::jsonb;
  v_tools      jsonb;
  v_playbook   text;
  v_payload    jsonb;
  r            record;
begin
  v_meta := public.mind_kit_meta(v_rota);
  if not coalesce((v_meta->>'ok')::boolean, false) then
    return v_meta;
  end if;

  if p_conversa_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_conversa');
  end if;

  if not exists (select 1 from engagement.conversas c where c.id = p_conversa_id) then
    return jsonb_build_object(
      'ok', false, 'motivo', 'conversa_nao_encontrada', 'conversa_id', p_conversa_id);
  end if;

  select pr.conteudo into v_playbook
    from agentes.prompts pr
   where pr.chave = 'playbook_' || v_rota and pr.ativo
   limit 1;

  for r in
    select k.bloco, n.nspname as sch, p.proname as fn
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
    execute format('select %I.%I($1::uuid, $2::jsonb)', r.sch, r.fn)
      into v_payload using p_conversa_id, p_necessidade;
    if v_payload is not null then
      v_structured := v_structured || jsonb_build_object(r.bloco, v_payload);
    end if;
  end loop;

  -- TOOLS. A rota declara quais em `kit_blocos`; o descritor vem do catálogo. Só
  -- ferramenta ATIVA e de LEITURA atravessa. Nome é a chave do join — nunca vira
  -- identificador executável aqui.
  select coalesce(jsonb_agg(
           jsonb_build_object('nome', f.nome, 'descricao', f.descricao,
                              'parametros', f.json_schema)
           order by f.nome), '[]'::jsonb)
    into v_tools
    from agentes.kit_blocos k
    join concierge.ferramentas f on f.nome = k.bloco
   where k.rota = v_rota and k.ativo and k.secao = 'tools'
     and f.ativo and f.escrita = false;

  return jsonb_build_object(
    'playbook',   v_playbook,
    'structured', v_structured,
    'knowledge',  '[]'::jsonb,
    'tools',      coalesce(v_tools, '[]'::jsonb),
    'meta',       v_meta);
end;
$function$;

-- GUARDA. Duas tools no concierge, nenhuma no vendedor e no suporte, e o Kit dos
-- outros continua disponível como antes.
do $$
declare v_c jsonb; v_s jsonb; v_b jsonb;
begin
  select public.mind_agent_kit('concierge_summit', c.id, null) into v_c
    from engagement.conversas c where c.canal = 'mindagent-web' order by c.iniciada_em desc limit 1;
  if v_c is null then raise notice 'sem conversa mindagent-web para conferir tools'; else
    if jsonb_array_length(v_c->'tools') <> 2 then
      raise exception 'concierge deveria expor 2 tools, veio: %', v_c->'tools';
    end if;
  end if;

  select public.mind_agent_kit('cliente_suporte', c.id, null) into v_s
    from engagement.conversas c where c.canal = 'mindagent-web' order by c.iniciada_em desc limit 1;
  if v_s is not null and jsonb_array_length(coalesce(v_s->'tools','[]'::jsonb)) <> 0 then
    raise exception 'cliente_suporte nao deveria expor tools nesta entrega: %', v_s->'tools';
  end if;

  v_b := public.mind_kit_meta('summit_b2c');
  if (v_b->>'kit_disponivel')::boolean is not true then
    raise exception 'summit_b2c regrediu apos o filtro de secao: %', v_b;
  end if;
end $$;
