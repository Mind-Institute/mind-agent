-- O App nunca recebeu a conduta de handoff. Agora recebe -- pelo mesmo bloco.
--
-- O QUE SE DESCOBRIU. A conduta canonica de "quando nao souber, admita e ofereca a saida
-- do canal" mora em `agentes.prompts['base']` desde 31/08, e e injetada em toda conversa
-- do WhatsApp por `treble_agent_prompt`. O App monta o prompt por outro caminho --
-- `mind_agent_kit` -> `playbook_<rota>` -- e esse caminho NUNCA leu `base`. Conferido:
-- o playbook entregue ao App nao continha uma linha do bloco.
--
-- Ou seja: nao falta mecanismo de handoff no App, falta o mecanismo chegar la. Isto e
-- reuso do que existe, nao um segundo mecanismo -- e `base` ja prevê exatamente o caso
-- deste canal: "se este canal nao transfere, diga que alguem do time entra em contato".
--
-- ORDEM. `base` primeiro, playbook da rota depois -- a mesma ordem de
-- `treble_agent_prompt`, onde `base` e a primeira parte. Conduta geral emoldura a
-- competencia especifica; o contrario faria a rota parecer excecao a ela.

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
  v_base       text;
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

-- CRITERIO DE ESCALONAMENTO. Conduta, e por isso mora no playbook -- nao na orquestracao.
-- A distincao que importa: necessidade OPERACIONAL (alguem precisa resolver algo) escala;
-- informacao que nao existe na base NAO escala, so se diz que ainda nao esta disponivel.
update agentes.prompts
   set conteudo = conteudo || E'\n\nQUANDO ENCAMINHAR PARA O ATENDIMENTO:\n'
     || E'Você é dono desta conversa e responde tudo que estiver na sua capacidade. Encaminhar é para NECESSIDADE OPERACIONAL — quando alguém precisa RESOLVER algo por ela:\n'
     || E'- ingresso que não aparece ou não chegou;\n'
     || E'- problema de acesso, de pagamento, reembolso, troca de titularidade;\n'
     || E'- erro técnico, reclamação, exceção de política;\n'
     || E'- qualquer situação que dependa de alguém agir no sistema por ela.\n'
     || E'Nesses casos, diga com naturalidade que alguém do time entra em contato assim que possível — e antes disso responda o que você ainda consegue responder.\n\n'
     || E'INFORMAÇÃO QUE NÃO EXISTE NÃO É CASO DE ATENDIMENTO. Se alguém pergunta o cardápio do almoço e isso não está na base, a resposta é que essa informação ainda não está disponível. Não transforme ausência de dado em pedido de suporte: quem procurava uma informação sai com uma promessa de retorno que ninguém precisava dar.'
 where chave = 'playbook_concierge_summit' and ativo
   -- Reaplicacao nao duplica: o bloco so entra se ainda nao estiver la.
   and position('QUANDO ENCAMINHAR PARA O ATENDIMENTO' in conteudo) = 0;

do $$
declare v_kit jsonb; v_base text;
begin
  select conteudo into v_base from agentes.prompts where chave='base' and ativo;

  select public.mind_agent_kit('concierge_summit', c.id, null) into v_kit
    from engagement.conversas c where c.canal='mindagent-web' order by c.iniciada_em desc limit 1;
  if v_kit is null then raise notice 'sem conversa do app para conferir'; return; end if;

  if position(left(v_base, 80) in (v_kit->>'playbook')) = 0 then
    raise exception 'o Kit do App continua sem o bloco base';
  end if;
  if (v_kit->>'playbook') !~ 'NECESSIDADE OPERACIONAL' then
    raise exception 'playbook do concierge sem o criterio de escalonamento';
  end if;
  if (v_kit->>'playbook') !~ 'ainda não está disponível' then
    raise exception 'playbook sem a regra de ausencia de informacao';
  end if;

  -- O vendedor nao pode ter mudado: ele monta prompt por treble_agent_prompt.
  if (public.mind_agent_kit('summit_b2c', (select id from engagement.conversas
        where canal='whatsapp' order by iniciada_em desc limit 1), null)->>'playbook') is null then
    raise exception 'summit_b2c ficou sem playbook';
  end if;
end $$;
