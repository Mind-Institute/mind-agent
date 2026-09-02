-- UM BLOCO OPCIONAL NÃO PODE MAIS CALAR O AGENTE.
--
-- O QUE ACONTECEU EM 02/09. `mind_customer_intelligence` referenciava uma coluna
-- inexistente. Ela alimenta o bloco `customer_intelligence`, que é OPCIONAL e
-- que entrou nos Kits das quatro rotas. O laço de montagem aqui executava cada
-- provider sem proteção nenhuma, então a exceção de um bloco opcional abortava
-- `mind_agent_kit` inteiro. Sem Kit, o runtime falha fechado de propósito — e o
-- App e o vendedor ficaram mudos por um bloco acessório.
--
-- O FAIL-CLOSED ESTAVA CERTO. Ele é que impediu o agente de responder sem dado
-- oficial. O que estava errado era o alcance: o Kit tratava obrigatório e
-- opcional do mesmo jeito, embora a diferença já exista no dado desde sempre —
-- `agentes.kit_blocos.obrigatorio`.
--
-- A REGRA PASSA A HONRAR ESSA COLUNA:
--
--   bloco OBRIGATÓRIO falha  -> a exceção sobe, o Kit não monta, o turno não
--                               acontece. Idêntico ao de hoje. Responder sobre
--                               programação sem a programação é o defeito que o
--                               fail-closed existe para evitar;
--   bloco OPCIONAL falha     -> sai de cena sozinho, com aviso no log, e o turno
--                               segue com o resto. O Concierge fica menos
--                               personalizado por um turno; não fica mudo.
--
-- `mind_kit_meta` continua sendo a autoridade sobre disponibilidade e não muda:
-- ela já confere os obrigatórios antes, inclusive sondando cada provider. O que
-- muda aqui é só o que acontece quando um provider quebra DURANTE a montagem,
-- com uma conversa real — que é o caso que `mind_kit_meta` não tem como prever.
--
-- `when others` NÃO captura cancelamento de consulta nem timeout de statement:
-- esses continuam subindo. É o que se quer — engolir um cancelamento
-- transformaria um turno abortado em resposta degradada silenciosa.
--
-- VISIBILIDADE. Bloco que some calado é como o sistema apodrece devagar. Cada
-- falha vira `raise warning` (log do Postgres) e entra em
-- `meta.blocos_com_falha`, que passa a existir sempre — lista vazia no caso
-- normal. Nenhum consumidor atual lê essa chave, então acrescentá-la não quebra
-- ninguém; quem quiser medir degradação tem onde olhar.

create or replace function public.mind_agent_kit(
  p_rota text, p_conversa_id uuid, p_necessidade jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'agentes', 'engagement', 'concierge'
as $function$
declare
  v_rota       text  := nullif(btrim(p_rota), '');
  v_meta       jsonb;
  v_structured jsonb := '{}'::jsonb;
  v_tools      jsonb;
  v_base       text;
  v_playbook   text;
  v_payload    jsonb;
  v_falhas     text[] := array[]::text[];
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

  -- Conduta injetada em toda conversa. Mesma fonte do WhatsApp; ausente, o Kit segue
  -- exatamente como antes.
  select pr.conteudo into v_base
    from agentes.prompts pr
   where pr.chave = 'base' and pr.ativo
     and btrim(coalesce(pr.conteudo, '')) <> ''
   limit 1;

  if v_base is not null and v_playbook is not null then
    v_playbook := v_base || E'\n\n' || v_playbook;
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
      -- Obrigatório quebrado é turno perdido, e deve ser: é o fail-closed.
      if r.obrigatorio then raise; end if;
      -- Opcional quebrado sai de cena e a conversa continua.
      raise warning 'mind_agent_kit(%): bloco opcional % falhou e foi omitido: %',
        v_rota, r.bloco, sqlerrm;
      v_falhas  := v_falhas || r.bloco;
      v_payload := null;
    end;

    if v_payload is not null then
      v_structured := v_structured || jsonb_build_object(r.bloco, v_payload);
    end if;
  end loop;

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
    'meta',       v_meta || jsonb_build_object('blocos_com_falha', to_jsonb(v_falhas)));
end;
$function$;

do $g$
declare d text;
begin
  select pg_get_functiondef(p.oid) into d
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'mind_agent_kit';

  if position('if r.obrigatorio then raise; end if' in d) = 0 then
    raise exception 'o bloco obrigatorio deixou de falhar fechado'; end if;
  if position('blocos_com_falha' in d) = 0 then
    raise exception 'a lista de blocos com falha nao entrou no meta'; end if;
  if position('k.obrigatorio' in d) = 0 then
    raise exception 'o laco parou de ler a coluna obrigatorio'; end if;
  -- O que não podia mudar junto.
  if position('v_base || E''\n\n'' || v_playbook' in d) = 0 then
    raise exception 'a juncao de base + playbook se perdeu'; end if;
  if position('f.escrita = false' in d) = 0 then
    raise exception 'o filtro de ferramenta de leitura se perdeu'; end if;
  if position('conversa_nao_encontrada' in d) = 0 then
    raise exception 'a validacao de conversa se perdeu'; end if;
end $g$;
