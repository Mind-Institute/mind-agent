-- Agent Intelligence, Fase 1 — o que o agente recebe antes de responder, explícito
-- e com liga/desliga por agente (aprovado pela Adriana em 22/10/2026).
--
-- 1. `agentes.kit_blocos` ganha a seção `instrucoes` (um texto de `agentes.prompts`
--    que entra depois do playbook, ligado ou desligado POR AGENTE) e a coluna `ordem`.
-- 2. `public.mind_agent_instrucoes(rota)` passa a ser a ÚNICA montagem das instruções:
--    o Kit (`mind_agent_kit`) usa ela, e o painel mostra exatamente o mesmo texto.
--    Ordem: base → playbook → instrucoes (por ordem) → decisioning. Para quem não tem
--    bloco `instrucoes`, o texto sai idêntico ao de antes (conferido abaixo, rota a rota).
--    Bloco `instrucoes` obrigatório e ligado cujo texto sumiu: o agente não responde.
-- 3. O protocolo de crise da MIA sai do playbook e vira bloco próprio, obrigatório.
-- 4. A voz do Mind (`tom_de_voz`) aparece DESLIGADA em todos os agentes: hoje nenhum
--    agente de conversa a recebe, e isto não muda nada até alguém ligar.
-- 5. Portas do painel, só service_role. Escrita só do papel administrador; a descrição
--    das ferramentas (skills) guarda a versão anterior em `agentes.prompts_historico`,
--    com a chave `ferramenta:<nome>`.

set lock_timeout = '10s';

alter table agentes.kit_blocos drop constraint kit_blocos_secao_valida;
alter table agentes.kit_blocos add constraint kit_blocos_secao_valida
  check (secao = any (array['structured','knowledge','tools','decisioning','instrucoes']));
alter table agentes.kit_blocos add column if not exists ordem smallint not null default 100;
comment on column agentes.kit_blocos.ordem is
  'Posição do bloco dentro da seção. Em `instrucoes`, define a ordem em que os textos entram depois do playbook.';

alter table concierge.ferramentas add column if not exists atualizado_em timestamptz not null default now();
comment on table agentes.prompts_historico is
  'Versões anteriores dos textos que os agentes recebem: prompts (chave do prompt) e descrições de ferramentas (chave ferramenta:<nome>).';

-- ------------------------------------------------------------------ montagem única
create or replace function public.mind_agent_instrucoes(p_rota text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rota        text := nullif(btrim(p_rota), '');
  v_base        text;
  v_playbook    text;
  v_instrucoes  text;
  v_decisioning text;
  v_texto       text;
  v_faltando    text[];
  v_partes      jsonb;
begin
  select pr.conteudo into v_playbook
    from agentes.prompts pr
   where pr.chave = 'playbook_' || v_rota and pr.ativo
   limit 1;

  select pr.conteudo into v_base
    from agentes.prompts pr
   where pr.chave = 'base' and pr.ativo
     and btrim(coalesce(pr.conteudo, '')) <> ''
   limit 1;

  v_texto := case when v_base is not null and v_playbook is not null
                  then v_base || E'\n\n' || v_playbook
                  else v_playbook end;

  select string_agg(pr.conteudo, E'\n\n' order by k.ordem, k.bloco)
    into v_instrucoes
    from agentes.kit_blocos k
    join agentes.prompts pr on pr.chave = k.bloco and pr.ativo
                           and btrim(coalesce(pr.conteudo, '')) <> ''
   where k.rota = v_rota and k.ativo and k.secao = 'instrucoes';

  if v_instrucoes is not null then
    v_texto := coalesce(v_texto, '') || E'\n\n' || v_instrucoes;
  end if;

  select string_agg(pr.conteudo, E'\n\n' order by k.ordem, k.bloco)
    into v_decisioning
    from agentes.kit_blocos k
    join agentes.prompts pr on pr.chave = k.bloco and pr.ativo
   where k.rota = v_rota and k.ativo and k.secao = 'decisioning';

  if v_decisioning is not null and btrim(v_decisioning) <> '' then
    v_texto := coalesce(v_texto, '') || E'\n\n' || v_decisioning;
  end if;

  -- Sem playbook ou com bloco obrigatório sem texto, não há instrução: fail-closed.
  select coalesce(array_agg(k.bloco order by k.ordem, k.bloco), array[]::text[])
    into v_faltando
    from agentes.kit_blocos k
    left join agentes.prompts pr on pr.chave = k.bloco
   where k.rota = v_rota and k.ativo and k.obrigatorio and k.secao = 'instrucoes'
     and (pr.chave is null or not pr.ativo or btrim(coalesce(pr.conteudo, '')) = '');
  if v_playbook is null then
    v_faltando := array['playbook_' || coalesce(v_rota, '')] || v_faltando;
  end if;
  if cardinality(v_faltando) > 0 then
    v_texto := null;
  end if;

  select coalesce(jsonb_agg(x.parte order by x.pos, x.ordem, x.chave), '[]'::jsonb)
    into v_partes
    from (
      select 1 as pos, 0 as ordem, pr.chave,
             jsonb_build_object(
               'camada', 'base', 'chave', pr.chave, 'titulo', pr.titulo,
               'promptAtivo', pr.ativo, 'blocoAtivo', null, 'obrigatorio', false, 'ordem', null,
               'chars', length(coalesce(pr.conteudo, '')), 'atualizadoEm', null,
               'compartilhadoCom', '[]'::jsonb,
               'entra', v_texto is not null and v_base is not null) as parte
        from agentes.prompts pr
       where pr.chave = 'base'
      union all
      select 2, 0, 'playbook_' || v_rota,
             jsonb_build_object(
               'camada', 'playbook', 'chave', 'playbook_' || v_rota, 'titulo', pr.titulo,
               'promptAtivo', coalesce(pr.ativo, false), 'blocoAtivo', null, 'obrigatorio', true,
               'ordem', null, 'chars', length(coalesce(pr.conteudo, '')), 'atualizadoEm', null,
               'compartilhadoCom', '[]'::jsonb,
               'entra', v_texto is not null)
        from (select 1) um
        left join agentes.prompts pr on pr.chave = 'playbook_' || v_rota
      union all
      select case k.secao when 'instrucoes' then 3 else 4 end, k.ordem, k.bloco,
             jsonb_build_object(
               'camada', k.secao, 'chave', k.bloco, 'titulo', pr.titulo,
               'promptAtivo', coalesce(pr.ativo, false), 'blocoAtivo', k.ativo,
               'obrigatorio', k.obrigatorio, 'ordem', k.ordem,
               'chars', length(coalesce(pr.conteudo, '')), 'atualizadoEm', k.atualizado_em,
               'compartilhadoCom', coalesce((
                 select jsonb_agg(k2.rota order by k2.rota)
                   from agentes.kit_blocos k2
                  where k2.bloco = k.bloco and k2.rota <> k.rota and k2.ativo), '[]'::jsonb),
               'entra', v_texto is not null and k.ativo and coalesce(pr.ativo, false)
                        and btrim(coalesce(pr.conteudo, '')) <> '')
        from agentes.kit_blocos k
        left join agentes.prompts pr on pr.chave = k.bloco
       where k.rota = v_rota and k.secao in ('instrucoes', 'decisioning')
    ) x;

  return jsonb_build_object(
    'ok',          v_texto is not null,
    'rota',        v_rota,
    'texto',       v_texto,
    'decisioning', v_decisioning,
    'chars',       coalesce(length(v_texto), 0),
    'faltando',    to_jsonb(v_faltando),
    'partes',      v_partes);
end;
$$;

revoke all on function public.mind_agent_instrucoes(text) from public, anon, authenticated;
grant execute on function public.mind_agent_instrucoes(text) to service_role;

-- O texto de antes, rota a rota, tem de sair idêntico da montagem nova. Ainda não
-- existe bloco `instrucoes`, então qualquer diferença é erro desta migration.
do $$
declare
  r record;
  v_antigo text;
  v_novo text;
  v_playbook text;
  v_base text;
  v_decisioning text;
begin
  for r in select distinct rota from agentes.kit_blocos loop
    select pr.conteudo into v_playbook from agentes.prompts pr
     where pr.chave = 'playbook_' || r.rota and pr.ativo limit 1;
    select pr.conteudo into v_base from agentes.prompts pr
     where pr.chave = 'base' and pr.ativo and btrim(coalesce(pr.conteudo, '')) <> '' limit 1;
    if v_base is not null and v_playbook is not null then
      v_playbook := v_base || E'\n\n' || v_playbook;
    end if;
    select string_agg(pr.conteudo, E'\n\n' order by k.bloco) into v_decisioning
      from agentes.kit_blocos k
      join agentes.prompts pr on pr.chave = k.bloco and pr.ativo
     where k.rota = r.rota and k.ativo and k.secao = 'decisioning';
    v_antigo := v_playbook;
    if v_decisioning is not null and btrim(v_decisioning) <> '' then
      v_antigo := coalesce(v_antigo, '') || E'\n\n' || v_decisioning;
    end if;
    -- Antes, sem playbook o Gate já barrava a rota; agora a montagem também devolve nada.
    if v_playbook is null then v_antigo := null; end if;

    v_novo := public.mind_agent_instrucoes(r.rota) ->> 'texto';
    if v_novo is distinct from v_antigo then
      raise exception 'mind_agent_instrucoes mudou o texto da rota %', r.rota;
    end if;
  end loop;
end $$;

-- ------------------------------------------------------------------ o Kit usa a montagem
create or replace function public.mind_agent_kit(p_rota text, p_conversa_id uuid, p_necessidade jsonb DEFAULT '{}'::jsonb)
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

  select coalesce(jsonb_agg(jsonb_build_object('nome', f.nome, 'descricao', f.descricao, 'parametros', f.json_schema) order by f.nome), '[]'::jsonb)
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

-- ------------------------------------------------------------------ dados da MIA
-- O protocolo de crise sai do playbook (que guarda a versão anterior no histórico).
do $$
declare
  v_pb  agentes.prompts%rowtype;
  v_pos integer;
begin
  select * into v_pb from agentes.prompts where chave = 'playbook_mia_summit_2026' for update;
  v_pos := position('PROTOCOLO DE CRISE — vale acima' in coalesce(v_pb.conteudo, ''));
  if v_pos = 0 then
    if exists (select 1 from agentes.prompts where chave = 'protocolo_crise_mia_summit_2026') then
      return;
    end if;
    raise exception 'protocolo de crise não encontrado no playbook da MIA';
  end if;

  insert into agentes.prompts (chave, titulo, conteudo, ativo, versao, produto_codigo, atualizado_em)
  values ('protocolo_crise_mia_summit_2026',
          'Protocolo de crise — MIA Summit 2026 (RASCUNHO para revisão da Adriana)',
          btrim(substr(v_pb.conteudo, v_pos), E'\n '),
          true, 1, v_pb.produto_codigo, now());

  insert into agentes.prompts_historico
    (chave, versao, titulo, conteudo, ativo, produto_codigo, vigente_desde, substituida_em, mind_id, substituida_por_nome)
  values
    (v_pb.chave, v_pb.versao, v_pb.titulo, v_pb.conteudo, v_pb.ativo, v_pb.produto_codigo,
     v_pb.atualizado_em, now(), null, 'Migration: o protocolo de crise virou bloco próprio (Adriana, 22/10/2026)');

  update agentes.prompts
     set conteudo = rtrim(substr(v_pb.conteudo, 1, v_pos - 1), E'\n '),
         versao = coalesce(versao, 0) + 1,
         atualizado_em = now()
   where chave = v_pb.chave;
end $$;

insert into agentes.kit_blocos (rota, bloco, provider, secao, obrigatorio, ativo, ordem, atualizado_em)
values ('mia_summit_2026', 'protocolo_crise_mia_summit_2026', 'agentes.prompts', 'instrucoes', true, true, 90, now())
on conflict (rota, bloco) do nothing;

insert into agentes.kit_blocos (rota, bloco, provider, secao, obrigatorio, ativo, ordem, atualizado_em)
select r.rota, 'tom_de_voz', 'agentes.prompts', 'instrucoes', false, false, 10, now()
  from unnest(array['summit_b2c','summit_b2b','institute','dash','cliente_suporte',
                    'concierge_summit','mia_summit_2026']) as r(rota)
on conflict (rota, bloco) do nothing;

-- ------------------------------------------------------------------ portas do painel
create or replace function public.mind_admin_read_agent_instructions(p_id text default null)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when p_id is null
              then (m.instr - 'texto' - 'decisioning')
              else m.instr end || jsonb_build_object('id', r.rota)
    from (
      select distinct x.rota
        from (select c.rota from agentes.canal_competencia c
              union select k.rota from agentes.kit_blocos k) x
       where p_id is null or x.rota = p_id
    ) r
    cross join lateral public.mind_agent_instrucoes(r.rota) as m(instr)
   order by r.rota;
$$;

create or replace function public.mind_admin_create_agent_instruction(
  p_rota text, p_chave text, p_titulo text, p_conteudo text, p_substitui text, p_ator uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role    text;
  v_antigo  agentes.kit_blocos%rowtype;
  v_produto text;
begin
  select a.role into v_role from public.mind_admin_users a where a.user_id = p_ator and a.active;
  if v_role is distinct from 'administrador' then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;

  if p_chave is null or p_chave !~ '^[a-z][a-z0-9_]{2,79}$'
     or p_chave = 'base' or p_chave like 'playbook\_%' then
    raise exception using errcode = '22023', message = 'admin_validation:chave';
  end if;
  if btrim(coalesce(p_titulo, '')) = '' or btrim(coalesce(p_conteudo, '')) = ''
     or length(p_conteudo) > 100000 then
    raise exception using errcode = '22023', message = 'admin_validation:conteudo';
  end if;
  if exists (select 1 from agentes.prompts p where p.chave = p_chave) then
    raise exception using errcode = '22023', message = 'admin_validation:chave_existe';
  end if;

  if p_substitui is not null then
    select * into v_antigo from agentes.kit_blocos k
     where k.rota = p_rota and k.bloco = p_substitui and k.secao = 'instrucoes'
     for update;
    if not found then
      raise exception using errcode = 'P0002', message = 'admin_not_found';
    end if;
  end if;

  select p.produto_codigo into v_produto from agentes.prompts p where p.chave = 'playbook_' || p_rota;

  insert into agentes.prompts (chave, titulo, conteudo, ativo, versao, produto_codigo, atualizado_em)
  values (p_chave, btrim(p_titulo), p_conteudo, true, 1, v_produto, now());

  begin
    insert into agentes.kit_blocos (rota, bloco, provider, secao, obrigatorio, ativo, ordem, atualizado_em)
    values (p_rota, p_chave, 'agentes.prompts', 'instrucoes',
            coalesce(v_antigo.obrigatorio, false), coalesce(v_antigo.ativo, false),
            coalesce(v_antigo.ordem, 50), now());
  exception when check_violation then
    raise exception using errcode = '22023', message = 'admin_validation:rota';
  end;

  -- O bloco substituído sai deste agente; o texto dele continua valendo para os outros.
  if p_substitui is not null then
    update agentes.kit_blocos k
       set ativo = false, atualizado_em = now()
     where k.rota = p_rota and k.bloco = p_substitui;
  end if;

  return (select x from public.mind_admin_read_agent_instructions(p_rota) x limit 1);
end;
$$;

create or replace function public.mind_admin_read_agent_tools(p_id text default null)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', f.nome,
    'nome', f.nome,
    'descricao', f.descricao,
    'parametros', f.json_schema,
    'ativo', f.ativo,
    'escrita', f.escrita,
    'versao', f.versao,
    'atualizadoEm', f.atualizado_em,
    'usadoPor', coalesce((
      select jsonb_agg(k.rota order by k.rota)
        from agentes.kit_blocos k
       where k.bloco = f.nome and k.secao = 'tools' and k.ativo), '[]'::jsonb),
    'historico', case when p_id is null then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
               'versao', h.versao, 'conteudo', h.conteudo,
               'vigenteDesde', h.vigente_desde, 'substituidaEm', h.substituida_em,
               'substituidaPor', h.substituida_por_nome)
             order by h.substituida_em desc)
        from agentes.prompts_historico h
       where h.chave = 'ferramenta:' || f.nome), '[]'::jsonb) end)
  from concierge.ferramentas f
  where (p_id is null and exists (
           select 1 from agentes.kit_blocos k where k.bloco = f.nome and k.secao = 'tools'))
     or f.nome = p_id
  order by f.nome;
$$;

create or replace function public.mind_admin_update_agent_tool(
  p_nome text, p_descricao text, p_ator uuid, p_atualizado_em_esperado timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role    text;
  v_mind_id uuid;
  v_nome    text;
  v_atual   concierge.ferramentas%rowtype;
begin
  select a.role, a.mind_id, a.display_name into v_role, v_mind_id, v_nome
    from public.mind_admin_users a where a.user_id = p_ator and a.active;
  if v_role is distinct from 'administrador' then
    raise exception using errcode = '42501', message = 'admin_forbidden';
  end if;

  select * into v_atual from concierge.ferramentas f where f.nome = p_nome for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'admin_not_found';
  end if;
  if p_atualizado_em_esperado is not null and v_atual.atualizado_em is distinct from p_atualizado_em_esperado then
    raise exception using errcode = '40001', message = 'admin_conflict';
  end if;
  if btrim(coalesce(p_descricao, '')) = '' or length(p_descricao) > 4000 then
    raise exception using errcode = '22023', message = 'admin_validation:descricao';
  end if;
  if p_descricao is not distinct from v_atual.descricao then
    return (select x from public.mind_admin_read_agent_tools(p_nome) x limit 1);
  end if;

  insert into agentes.prompts_historico
    (chave, versao, titulo, conteudo, ativo, produto_codigo, vigente_desde, substituida_em, mind_id, substituida_por_nome)
  values
    ('ferramenta:' || v_atual.nome, v_atual.versao, v_atual.nome, v_atual.descricao, v_atual.ativo, null,
     v_atual.atualizado_em, now(), v_mind_id, v_nome);

  update concierge.ferramentas f
     set descricao = p_descricao,
         versao = coalesce(f.versao, 0) + 1,
         atualizado_em = now()
   where f.nome = p_nome;

  return (select x from public.mind_admin_read_agent_tools(p_nome) x limit 1);
end;
$$;

revoke all on function public.mind_admin_read_agent_instructions(text) from public, anon, authenticated;
revoke all on function public.mind_admin_create_agent_instruction(text, text, text, text, text, uuid) from public, anon, authenticated;
revoke all on function public.mind_admin_read_agent_tools(text) from public, anon, authenticated;
revoke all on function public.mind_admin_update_agent_tool(text, text, uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.mind_admin_read_agent_instructions(text) to service_role;
grant execute on function public.mind_admin_create_agent_instruction(text, text, text, text, text, uuid) to service_role;
grant execute on function public.mind_admin_read_agent_tools(text) to service_role;
grant execute on function public.mind_admin_update_agent_tool(text, text, uuid, timestamptz) to service_role;
